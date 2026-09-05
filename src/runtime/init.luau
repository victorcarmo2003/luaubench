--!strict

--[[
	Ponto de entrada público do runtime do LuauBench (task-runtime-007). `services`/`cli`
	fazem `require` SÓ deste arquivo -- nunca de um módulo individual dentro de
	`src/runtime/` (regra 02, seção "Contrato com `services`"/"Contrato com `cli`"; desenho
	completo em .claude/agents-memory/arquiteto-runtime-2026-09-04.md, seção "`init.luau`").
	Uso esperado, de fora deste diretório: `local Runtime = require("../runtime")` (contrato
	já documentado no desenho) -- NUNCA `require("./init")` nem `require("./init.luau")` de um
	módulo irmão dentro do próprio `src/runtime/`: confirmado empiricamente nesta tarefa que o
	resolvedor de `require` do Lune (0.10.5) trata as duas formas como erro ("could not resolve
	child component 'init' (ambiguous)" / "... 'init.luau'") -- só a forma "estilo diretório"
	(`require("../runtime")`, ou `require("./")` de dentro do próprio `src/runtime/`) carrega
	este arquivo. `src/runtime/init.spec.luau`, apesar de morar no mesmo diretório, usa
	`require("./")` por este exato motivo (comentário lá também).

	PENDÊNCIA DE TOOLING (`luau-lsp analyze` 1.69.0, não do Lune nem deste código -- ver o
	comentário completo em `init.spec.luau`, que é onde ela aparece): confirmado empiricamente
	que `luau-lsp` devolve um falso-positivo de "Unknown require" quando o arquivo ANALISADO
	(não este `init.luau`, e sim quem o requer) tem nome começando por "init" -- ex.:
	`init.spec.luau` requerendo `"./"` OU `"../runtime"`, as duas formas, sempre falso-positivo.
	Um arquivo de controle com outro nome, na mesma pasta, com a mesma linha de `require`,
	analisa limpo. `services`/`cli` (nomes normais) não deveriam ver este problema ao escrever
	`require("../runtime")` de verdade -- só quem nomear um arquivo começando por "init" ao lado
	de um `init.luau` real esbarraria nisto.

	GOTCHA DO LUNE (confirmado empiricamente, não documentado antes desta tarefa -- reportado no
	relatório desta task para o `arquiteto`/`pesquisador` registrarem oficialmente): quando este
	arquivo é carregado pela forma "estilo diretório", o Lune identifica o chunk pelo caminho do
	PRÓPRIO DIRETÓRIO (`src/runtime`), não por `src/runtime/init`. Isso desloca a base de
	resolução dos `require` relativos DENTRO deste arquivo em um nível: `require("./Signal")`
	aqui resolveria para `src/Signal` (o diretório `src`, não `src/runtime/Signal`) -- confirmado
	rodando `lune run` isolado antes de escrever isto, nunca por suposição (regra 00: não
	adivinhar comportamento de formato/ferramenta externa). Por isso os `require` abaixo usam
	`./runtime/Xxx` em vez de `./Xxx`: é o caminho que, combinado com a base deslocada acima,
	aponta de volta para o arquivo certo (`src/runtime/Xxx`). Nenhum outro módulo de
	`src/runtime/` precisa deste ajuste -- o gotcha é específico de arquivos literalmente
	chamados `init.luau` carregados no estilo diretório; `Signal.luau`/`Instance.luau`/etc. têm
	identidade de chunk normal (`src/runtime/NomeDoArquivo`) e resolvem `./Vizinho` do jeito
	óbvio, como os próprios specs deles já confirmam.

	A superfície abaixo NÃO é o desenho original ao pé da letra: segue as três correções
	posteriores registradas no mesmo arquivo de arquitetura e no desenho de `services` --

	- "Revisão pós-integração 2026-09-04 (2)", subseção "Consequência: `Runtime.Instance.NewBase`
	  sai da superfície pública": com `ClassRegistry.new` passando a criar a instância base e
	  aplicar a cadeia de classes ele mesmo (task-runtime-013), `Instance.NewBase` deixou de ter
	  uso legítimo fora de `ClassRegistry.luau` -- reexportá-lo aqui reabriria exatamente o
	  caminho que aquela correção fechou (instância sem descriptor, sem cadeia resolvida, sem
	  `ClassName` validado). `Runtime.ClassRegistry.new` é o único criador de instância
	  disponível a `services`/`cli`.
	- "Revisão pós-integração 2026-09-04 (3)", subseção final: pela mesma razão,
	  `Instance.SetClassChain`/`Instance.SetClassMethods` também não são reexportadas -- são
	  plumbing interno consumido só por `ClassRegistry.luau`, que já roda dentro do território de
	  `runtime`. `ThreadBroker.luau` também não é reexportado (plumbing interno do `Scheduler`,
	  ver seção "Revisão pós-integração 2026-09-04 — contrato Wait/resume").
	- Desenho de `services` (task-runtime-022, `.claude/agents-memory/arquiteto-services-2026-09-05.md`,
	  seção "Contrato entre territórios", subseção "`runtime` -> `services`"): `Instance.SetClassSchema`
	  entra na MESMA lista de plumbing interno acima, pela MESMA razão -- `ClassRegistry.new` é o
	  único chamador legítimo, na ordem que garante a validação (schema congelado + forma de cada
	  `MemberDescriptor`, ver `Instance.luau`). Reexportá-lo aqui reabriria o mesmo buraco que
	  `NewBase`/`SetClassChain`/`SetClassMethods` já fecham: uma instância com schema instalado por
	  fora do fluxo que semeia os defaults e cria um `Signal` fresco por evento (`ClassRegistry.new`,
	  "Decisão 6" do desenho de `services`). Em contrapartida, o MESMO desenho exige reexportar os
	  TIPOS `MemberKind`/`MemberDescriptor`/`ClassSchema` (de `Instance.luau`, task-runtime-018) e
	  `FireableSignal<T...>` (de `Signal.luau`, existente desde a task-runtime-001): `services`
	  precisa declarar o tipo do schema que ele mesmo gera (`ClassDescriptor.Schema: ClassSchema?`,
	  já em `ClassRegistry.luau`) e precisa estreitar o `unknown` que
	  `Runtime.Instance.GetPropertyRaw(instance, "PlayerAdded")` devolve para disparar um evento de
	  classe concreta (ex.: `Players.PlayerAdded`) sem recorrer a um cast cego para um tipo que
	  `services` teria de redeclarar à mão. Só o TIPO `FireableSignal` é reexportado -- `Signal.new`
	  continua sendo a única forma pública de CRIAR um `FireableSignal`, já exposta acima.

	`Runtime.Instance.GetPropertyRaw`/`SetPropertyRaw` CONTINUAM expostos: é o caminho tipado de
	leitura/escrita de propriedade genérica que `services` usa para propriedade somente-leitura
	do ponto de vista do script do usuário (ver ClassRegistry.luau, cabeçalho).
]]

local SignalModule = require("./runtime/Signal")
local InstanceModule = require("./runtime/Instance")
local ClassRegistryModule = require("./runtime/ClassRegistry")
local DataModelModule = require("./runtime/DataModel")
local SchedulerModule = require("./runtime/Scheduler")
local SandboxModule = require("./runtime/Sandbox")

export type Signal<T...> = SignalModule.Signal<T...>
export type Connection = SignalModule.Connection
-- Só o TIPO -- `Signal.new` (abaixo) continua sendo a única forma pública de criar um
-- `FireableSignal` de verdade (ver cabeçalho deste arquivo, item novo do desenho de `services`).
export type FireableSignal<T...> = SignalModule.FireableSignal<T...>
export type Instance = InstanceModule.Instance
export type MemberKind = InstanceModule.MemberKind
export type MemberDescriptor = InstanceModule.MemberDescriptor
export type ClassSchema = InstanceModule.ClassSchema
export type ClassDescriptor = ClassRegistryModule.ClassDescriptor
export type DataModel = DataModelModule.DataModel
export type Scheduler = SchedulerModule.Scheduler
export type TaskHandle = SchedulerModule.TaskHandle
export type SandboxOptions = SandboxModule.SandboxOptions
export type SandboxResult = SandboxModule.SandboxResult
export type OutputRecord = SandboxModule.OutputRecord
export type OutputLevel = SandboxModule.OutputLevel

local Runtime = {
	Signal = {
		new = SignalModule.new,
	},

	-- Só GetPropertyRaw/SetPropertyRaw -- NewBase/SetClassChain/SetClassMethods/SetClassSchema
	-- ficam de fora (ver cabeçalho deste arquivo).
	Instance = {
		GetPropertyRaw = InstanceModule.GetPropertyRaw,
		SetPropertyRaw = InstanceModule.SetPropertyRaw,
	},

	ClassRegistry = {
		Register = ClassRegistryModule.Register,
		Get = ClassRegistryModule.Get,
		IsRegistered = ClassRegistryModule.IsRegistered,
		new = ClassRegistryModule.new,
	},

	DataModel = {
		new = DataModelModule.new,
	},

	Scheduler = {
		new = SchedulerModule.new,
	},

	Sandbox = {
		Run = SandboxModule.Run,
	},
}

return Runtime
