--!strict

--[[
	Ponto de entrada público do território `services` (arquiteto-services-2026-09-05.md, seção
	"Módulos" -> "src/services/init.luau"). `cli` faz `require` SÓ deste arquivo -- nunca de um
	módulo interno (`generated/**`, `behavior/**`, `Types`/`Context`/`ClassBuilder` direto) --
	regra 03, "Contrato com runtime": "toda classe nova registrada por services é discoverable
	por runtime/cli sem que eles precisem conhecer o nome da classe de antemão (registro central,
	não `if ClassName == "Workspace" then`)".

	Uso esperado de fora deste diretório: `local Services = require("../services")`. Mesmo gotcha
	de `require` do Lune já documentado no cabeçalho de src/runtime/init.luau (arquivo chamado
	`init.luau`, carregado "estilo diretório" -- confirmado empiricamente por `coder-runtime` que
	só essa forma resolve; `require("./init")`/`require("./init.luau")` de um irmão dá erro
	"ambiguous"): `init.spec.luau`, no mesmo diretório deste arquivo, usa `require("./")` pela
	mesma razão -- ver o comentário completo lá.

	MESMO GOTCHA, agora do lado de DENTRO deste arquivo (reconfirmado empiricamente nesta tarefa,
	rodando `lune run` isolado antes de fechar isto -- regra 00): quando `init.luau` é carregado
	"estilo diretório", o Lune identifica este chunk pelo caminho do PRÓPRIO DIRETÓRIO
	(`src/services`), não por `src/services/init` -- isso desloca a base de resolução dos
	`require` relativos ESCRITOS AQUI DENTRO em um nível. Por isso os `require` abaixo usam
	`./services/Types`/`./services/Context` (não `./Types`/`./Context`) para alcançar os arquivos
	irmãos, e `./runtime` (não `../runtime`) para alcançar `src/runtime` -- confirmado rodando
	`lune run src/services/init.spec.luau` de verdade, nunca por suposição. Mesmo raciocínio do
	cabeçalho de src/runtime/init.luau, aplicado a este diretório.

	task-services-003 (primeira leva de classes reais -- contêineres da árvore Rojo + Scripts +
	Workspace + Lighting): `Services.Register()` PASSA A REGISTRAR de verdade, iterando
	`generated/Index.luau` (as 24 classes desta leva, task-services-002) cruzado com
	`behavior/Index.luau` (a lista curada de comportamento à mão -- vazia nesta leva, ver o
	cabeçalho desse arquivo para o porquê) via `ClassBuilder.Build`.

	task-services-005 ("Services.new: a família de três erros de classe e o Instance.new do
	sandbox"): É AQUI, e não em `runtime`, que "não existe no Roblox" deixa de ser indistinguível
	de "existe no Roblox e ainda não simulado" -- `Runtime.ClassRegistry.new` só sabe dizer "classe
	não registrada" (mensagem de engenharia interna, em português), o que confundiria um typo do
	usuário com uma lacuna real de cobertura do LuauBench. `KNOWN_BUT_UNSIMULATED` (tabela local,
	vazia, do rascunho de task-services-001/003) É REMOVIDA nesta tarefa -- substituída pela leitura
	real de `generated/Manifest.luau` (as 916 classes do dump inteiro, "Decisão 5" -> "Manifesto
	completo" do desenho). Consequência: as TRÊS mensagens da família de erro de `Services.new`
	agora são alcançáveis de verdade, não só as duas primeiras:
	(a) `className` AUSENTE do manifesto (não existe no Roblox, ex.: typo "Frmae") -> família
	    Roblox, em inglês, SEM prefixo -- string aproximada de boa-fé, não confirmada byte-a-byte
	    (pendência declarada de task-services-006/pesquisador, ver `GetDumpVersion`/comentário de
	    `Services.new` abaixo).
	(b) `className` no manifesto com `IsAbstract == true` (tag `NotCreatable` do dump, ex.:
	    "Workspace") -> a MESMA mensagem de (a) -- é o que o Roblox real faz para uma classe
	    não-criável. Sempre alcançada via `Runtime.ClassRegistry.Get`, nunca via o manifesto (ver
	    invariante abaixo).
	(c) `className` no manifesto, NÃO abstrata, mas `Covered == false` (existe no dump, ainda sem
	    Schema/comportamento em `services`, ex.: "Frame") -> `[LuauBench] {X} exists in the Roblox
	    API Dump ({versão}) but is not simulated by LuauBench yet` -- prefixo `[LuauBench]`
	    OBRIGATÓRIO: este erro NÃO tem contraparte no Roblox real (lá a classe funciona
	    normalmente); ele só existe porque o LuauBench é incompleto, e nunca pode ser confundido com
	    uma mensagem do motor (regra de idioma dos erros, "Decisão 5" do desenho).

	INVARIANTE que `Services.new` explora (confirmada nesta tarefa, contando as duas fontes: 24
	entradas com `Covered = true` em `generated/Manifest.luau` == 24 requires em
	`generated/Index.luau`): TODA classe com `Covered == true` no manifesto está registrada em
	`Runtime.ClassRegistry` depois de `Services.Register()` -- as duas listas nascem da MESMA
	`tools/coverage.luau` no gerador. Por isso `Services.new` consulta `ClassRegistry.Get` PRIMEIRO
	(cobre (a)-parcial e (b) por completo) e só cai no manifesto para decidir entre (a) e (c) --
	nunca o contrário, e nunca precisa checar `Covered` explicitamente no ramo feliz.

	BLOQUEIO DE RUNTIME RESOLVIDO (retomada de task-services-003 -- estava documentado aqui como
	bloqueio confirmado quando esta tarefa rodou pela primeira vez): TODA classe `Service` coberta
	por esta leva (ReplicatedStorage/ServerStorage/ServerScriptService/ReplicatedFirst/StarterPack/
	StarterGui/StarterPlayer/Workspace/Lighting) carrega a tag `NotCreatable` no dump -- fiel ao
	Roblox real (não dá para `Instance.new("Workspace")` lá também) -- e o gerador traduz isso
	corretamente para `GeneratedClass.IsAbstract = true`. O problema era que
	`Runtime.ClassRegistry.new` rejeitava `IsAbstract == true` INCONDICIONALMENTE, sem distinguir
	"script chamando `Instance.new` numa classe não-criável" (o que a tag deveria bloquear, e que
	`Services.new` abaixo já bloqueia por conta própria, ANTES de chamar `ClassRegistry.new`) de "o
	motor construindo o singleton internamente" (o que `DataModel:GetService`, em
	`src/runtime/DataModel.luau`, precisa fazer -- e o Roblox real permite). `task-runtime-023`
	resolveu com DOIS construtores em `Runtime.ClassRegistry` (ver
	.claude/agents-memory/arquiteto-runtime-2026-09-04.md, seção "Revisão pós-integração 2026-09-05
	(4)"): a via PÚBLICA (`ClassRegistry.new`) mantém a guarda de `IsAbstract`, e a via NOVA do
	motor (`ClassRegistry.NewEngineInstance`, mesma construção completa, SEM a guarda) passou a ser
	usada por `DataModel.GetService` -- e por `behavior/StarterPlayer.luau` (novo nesta retomada),
	para os dois filhos fixos. Resultado confirmado agora (`Integration.spec.luau`, seções "1b" e
	"6"): `game:GetService("ReplicatedStorage")`/`("Workspace")`/etc. devolvem o singleton, e
	`StarterPlayer` nasce com `StarterPlayerScripts`/`StarterCharacterScripts`. `Services.new`
	abaixo continua com o mesmo comportamento de sempre para o caminho `Instance.new` do usuário
	(ele já barra classe abstrata antes de chegar em `ClassRegistry.new` -- ver o comentário de
	`Services.new`) -- nada mudou aqui, o fix inteiro viveu em `src/runtime/`.

	DIVERGÊNCIAS DE FIDELIDADE DESTA LEVA (regra 00: toda divergência é declarada, nunca
	silenciosa -- "Fidelidade vs. pragmatismo" do desenho de `services`, seção homônima):
	- `Workspace.Terrain` e `Workspace.CurrentCamera` sempre leem `nil` -- `Terrain` puxaria toda a
	  hierarquia de `BasePart`/`Instance` física (fora de escopo desta fase), `CurrentCamera` fica
	  para uma leva de render que não existe ainda. Já é o comportamento de hoje (o `Default` do
	  schema gerado por task-services-002 é `nil` para as duas -- ver
	  `generated/classes/Workspace.luau`), documentado aqui porque `Workspace` não tem
	  `behavior/Workspace.luau` nesta leva (não precisa de `Initialize`) e este é o único lugar de
	  `services` que fala sobre a classe.
	- `Lighting` guarda e devolve TODAS as suas propriedades (`Ambient`, `Brightness`, `ClockTime`,
	  etc.) fielmente -- mas nada é renderizado: `lighting.Ambient = Color3.new(...)` (quando
	  `Color3` existir, leva 3) é dado morto, sem efeito visual nenhum. Mesmo motivo do item
	  acima: `Lighting` não precisa de `behavior/Lighting.luau` nesta leva (contêiner de dados
	  puro), então fica documentado aqui.
	- `Default` de propriedade cujo `ValueType` é `Enum` ou `DataType` (Vector3/CFrame/Color3/...)
	  é `nil` nesta fase (Decisão 3 do desenho) -- afeta várias propriedades de `Workspace`/
	  `Lighting`/`StarterPlayer` nesta leva (ex.: `Workspace.GlobalWind`, `Lighting.FogColor`,
	  `StarterPlayer.CameraMode`). Não há tipos de valor simulados ainda (leva 3) -- inventar um
	  valor aproximado mentiria (`part.Shape == Enum.PartType.Block` teria que ser verdade, e não
	  há `Enum` para isso funcionar).

	SEQUÊNCIA DE BOOTSTRAP que `cli` DEVE seguir (arquiteto-services-2026-09-05.md, "Contrato entre
	territórios" -> "Quem chama primeiro"; os 8 passos, copiados aqui porque `cli` só lê este
	arquivo, nunca o desenho do arquiteto diretamente):

	  1. `local Runtime  = require("../runtime")`
	  2. `local Services = require("../services")`
	  3. `local scheduler = Runtime.Scheduler.new()`
	  4. `local game      = Runtime.DataModel.new()`
	  5. `Services.Bootstrap({ scheduler = scheduler, dataModel = game })` -- registra as classes
	  6. `game:GetService("ReplicatedStorage")` ... (populado a partir do `.project.json`)
	  7. `Runtime.Sandbox.Run{ extraGlobals = { game = game, workspace = game:GetService("Workspace"),
	     Instance = { new = Services.new }, script = <a Instance do script> }, ... }`
	  8. `scheduler:Run(shouldContinue)`

	DUAS REGRAS DURAS desta sequência, ambas verificadas pelo teste de fumaça em `init.spec.luau`:

	- **Passo 5 (`Services.Bootstrap`) SEMPRE ANTES de qualquer `GetService` (passo 6 em diante).**
	  Invariante de `cli`, não imposta por `runtime` (que não conhece essa ordem, regra 02) nem por
	  `services` (`Context.GetScheduler`/`GetDataModel` só ERRAM claro se ninguém chamou
	  `Bootstrap` ainda -- não adivinham, não usam um scheduler/dataModel default). Chamar
	  `GetService` antes de `Bootstrap` erra porque NENHUMA classe foi registrada em
	  `Runtime.ClassRegistry` ainda (`DataModel.GetService`, em `runtime`, erra "classe não
	  registrada").
	- **`cli` injeta `extraGlobals.Instance = { new = Services.new }` no `Sandbox`** (passo 7) --
	  é a ÚNICA forma de `Instance.new(...)` alcançar o script do usuário: `Runtime.Sandbox.Run`
	  nunca expõe `Instance` por conta própria (whitelist fixa de globals, `src/runtime/Sandbox.luau`
	  -- `services` não é module do `runtime`, e um sandbox não pode saber de antemão o nome de
	  nenhuma classe). `Services.new` é a função exportada por este arquivo pensada exatamente para
	  isso: recebe `(className, name)`, os mesmos dois parâmetros do `Instance.new` real do Roblox.

	`cli` NUNCA requer `src/services/generated/**` nem `src/services/behavior/**` diretamente -- só
	`require("../services")` (este arquivo). É o que preserva a regra 03 ("toda classe nova
	registrada por `services` é discoverable por `runtime`/`cli` sem que eles precisem conhecer o
	nome da classe de antemão, registro central, não `if ClassName == "Workspace" then"`): se `cli`
	um dia precisasse abrir `generated/Index.luau` para descobrir uma classe, o registro central
	deixaria de ser central. A ÚNICA superfície que `cli` enxerga de `services` é a exportada por
	`Services` abaixo (`Bootstrap`/`new`/`IsKnownClass`/`IsSimulatedClass`/`GetDumpVersion`).
]]

local Types = require("./services/Types")
local Context = require("./services/Context")
local ClassBuilder = require("./services/ClassBuilder")
local GeneratedIndex = require("./services/generated/Index")
local BehaviorIndex = require("./services/behavior/Index")
local Manifest = require("./services/generated/Manifest")
local Runtime = require("./runtime")

export type BootstrapOptions = Types.BootstrapOptions

local Services = {}

-- Guarda local de idempotência: `Runtime.ClassRegistry.Register` erra em `ClassName` duplicado e
-- não tem reset (src/runtime/ClassRegistry.luau, cabeçalho) -- sem esta guarda, uma segunda
-- chamada a `Services.Register`/`Services.Bootstrap` (ex.: `cli` reiniciando o script de entrada
-- em watch mode sem reiniciar o processo Lune) erraria tentando registrar a mesma classe de novo.
local registered = false

--[[
	Registra todas as classes cobertas no Runtime.ClassRegistry. Idempotente: a segunda chamada
	em diante é um no-op silencioso (nunca um erro) -- é isso que torna `Bootstrap` seguro de
	chamar mais de uma vez no mesmo processo.

	Itera `generated/Index.luau` (as `GeneratedClass` emitidas pelo gerador, task-services-002) e,
	para cada uma, busca o `Behavior` correspondente em `behavior/Index.luau` (ausente para a
	maioria -- contêiner puro, ver cabeçalho de `behavior/Index.luau`); `ClassBuilder.Build`
	converte o par num `Runtime.ClassDescriptor` (valida `behavior.Methods` contra
	`generated.MethodNames`, completa o resto com stub `[LuauBench]`, filtra a superfície fixa de
	`Runtime.Instance` -- ver comentário de `RESERVED_INSTANCE_SURFACE` em `ClassBuilder.luau`), e
	`Runtime.ClassRegistry.Register` o registra.

	Ordem de iteração de `generated/Index.luau` (uma tabela Lua, sem ordem garantida) NÃO importa:
	`Runtime.ClassRegistry.Register` só guarda o descriptor -- a cadeia de superclasses só é
	resolvida (e só precisa estar completa) no primeiro `ClassRegistry.new` de cada classe, nunca
	no registro (`src/runtime/ClassRegistry.luau`, comentário de `resolveClassChain`: "`services`
	pode registrar classes fora de ordem topológica"). Confirmado nesta tarefa: as 24 classes
	registram com sucesso em qualquer ordem de `pairs`.

	SEM pcall: erro de `ClassBuilder.Build` (ex.: um `Behavior` inventando um método fora do dump)
	ou de `Runtime.ClassRegistry.Register` (ex.: `ClassName` duplicado) é erro real de configuração
	de `services` e sobe para quem chamou `Bootstrap` -- mesma filosofia de
	`Runtime.ClassRegistry.new` não engolir erro de `Initialize` (regra 01: nunca pcall silencioso).
]]
function Services.Register(): ()
	if registered then
		return
	end
	registered = true

	for className, generated in GeneratedIndex do
		local behavior = BehaviorIndex[className]
		local descriptor = ClassBuilder.Build(generated, behavior)
		Runtime.ClassRegistry.Register(descriptor)
	end
end

-- `Register()` + `Context.Set()`. É a única coisa que `cli` precisa chamar antes de qualquer
-- `GetService` (arquiteto-services-2026-09-05.md, "Contrato entre territórios" ->
-- "Quem chama primeiro").
function Services.Bootstrap(options: BootstrapOptions): ()
	Services.Register()
	Context.Set(options)
end

-- "Está no dump?" -- as 916 classes de `generated/Manifest.luau` (task-services-005), não só o
-- que está registrado em `Runtime.ClassRegistry`. `IsKnownClass("Frame") == true` mesmo `Frame`
-- nunca tendo sido registrada (não está na leva atual, `Covered == false` no manifesto) -- é
-- exatamente a distinção que esta tarefa introduz (ver cabeçalho do arquivo).
function Services.IsKnownClass(className: string): boolean
	return Manifest.Classes[className] ~= nil
end

-- "Está coberta (registrada, comportamento existe)?" -- subconjunto de IsKnownClass para TODA
-- classe que passou pelo pipeline real (`Services.Register()`, que só registra o que também está
-- no manifesto -- mesma `tools/coverage.luau` gera as duas listas, ver invariante no cabeçalho do
-- arquivo). Só deixa de valer se algo chamar `Runtime.ClassRegistry.Register` diretamente, por
-- fora de `Services.Register()` (cenário de teste com uma classe fictícia, nunca de produção --
-- ver `init.spec.luau`, teste "IsKnownClass/IsSimulatedClass refletem o estado do registro").
-- Consulta `Runtime.ClassRegistry` (a fonte viva), não `ManifestEntry.Covered` (o instantâneo
-- gerado em dev-time): é a pergunta certa de se fazer aqui, e é o que `Services.new` de fato
-- consulta para decidir se instancia.
function Services.IsSimulatedClass(className: string): boolean
	return Runtime.ClassRegistry.IsRegistered(className)
end

-- Commit/versão do Roblox API Dump fixados na Decisão 2 do desenho, lidos de
-- `generated/Manifest.luau` -- a fonte única depois desta tarefa (antes, `init.luau` e
-- `ClassBuilder.luau` duplicavam o mesmo literal porque nenhum dos dois tinha de onde ler; ver
-- comentário histórico ainda presente em `ClassBuilder.luau`, que segue com o literal próprio até
-- uma tarefa própria de `services` migrar aquele uso também -- fora do território desta tarefa,
-- que é só `init.luau` + specs).
function Services.GetDumpVersion(): { Commit: string, Version: string }
	return { Commit = Manifest.DumpCommit, Version = Manifest.DumpVersion }
end

--[[
	O `Instance.new` que `cli` injeta em `extraGlobals.Instance.new` do Sandbox
	(arquiteto-services-2026-09-05.md, "Decisão 5" -> "Manifesto completo — as outras 894"). Família
	de erros, nesta ordem -- só DUAS mensagens distintas para três casos, de propósito (ver tabela
	do desenho e o cabeçalho deste arquivo, seção "task-services-005"):

	1. Classe registrada (simulada) e NÃO abstrata -> instancia via `Runtime.ClassRegistry.new`.
	   Ex.: "Folder".
	2. Classe registrada e ABSTRATA (tag `NotCreatable` do dump) -> erra com a MESMA mensagem do
	   caso 3 -- é o que o Roblox real faz para uma classe não-criável (aproximação de boa-fé;
	   string exata não confirmada byte-a-byte, comentada como tal no próprio desenho). Ex.:
	   "Workspace" (Service, sempre `NotCreatable` no dump).
	3. Classe NÃO registrada mas conhecida do manifesto (`generated/Manifest.luau`, as 916 classes)
	   com `Covered == false` -- existe no Roblox, ainda não simulada por LuauBench -> erra com
	   prefixo "[LuauBench]" citando a versão do dump (regra de idioma: SEM contraparte real, é o
	   LuauBench que está incompleto, não o Roblox -- nunca pode ser confundido com uma mensagem do
	   motor). Ex.: "Frame" (existe no dump -- `GuiObject`/render -- fora da leva atual).
	4. Classe nem registrada nem no manifesto (não existe no Roblox, ex.: typo "Frmae") -> família
	   Roblox, sem prefixo, MESMA mensagem do caso 2 -- só a origem interna difere (branch
	   `descriptor == nil` cai direto aqui quando o manifesto também não conhece o nome).

	NUNCA `nil` silencioso: um `className` desconhecido, abstrato ou incompleto sempre ERRA (regra
	03, "Service não coberto ainda não é stub silencioso") -- as quatro entradas acima cobrem TODO
	`className: string` possível, sem `else` implícito escondido.
]]
function Services.new(className: string, name: string?): Runtime.Instance
	local descriptor = Runtime.ClassRegistry.Get(className)
	if descriptor ~= nil then
		if descriptor.IsAbstract then
			error(`Unable to create an Instance of type "{className}"`, 2)
		end
		return Runtime.ClassRegistry.new(className, name)
	end

	-- Não registrada: consulta o manifesto (as 916) para decidir entre os casos 3 e 4 -- ver a
	-- invariante documentada no cabeçalho do arquivo (`Covered == true` implica sempre registrada,
	-- então chegar aqui com `Covered == true` seria um bug de `services`, não do script do
	-- usuário; tratado como caso 4 por segurança, nunca como um quinto caso silencioso).
	local manifestEntry = Manifest.Classes[className]
	if manifestEntry ~= nil and not manifestEntry.Covered then
		error(
			`[LuauBench] {className} exists in the Roblox API Dump ({Manifest.DumpVersion}) but is not simulated by LuauBench yet`,
			2
		)
	end

	error(`Unable to create an Instance of type "{className}"`, 2)
end

return Services
