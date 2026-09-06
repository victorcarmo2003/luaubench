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
	  5. `Services.Bootstrap({ scheduler = scheduler, dataModel = game })` -- registra as classes E
	     instala o resolvedor de classe desconhecida (task-services-011, ver abaixo)
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
	  `Runtime.ClassRegistry` ainda E porque nenhum `Runtime.UnknownClassResolver` foi instalado
	  ainda (`DataModel.GetService`, em `runtime`, erra de engenharia interna, em português, nos
	  dois casos).
	- **`Services.Register()` (chamado por `Bootstrap`, passo 5) também instala
	  `Runtime.UnknownClassResolver`** (task-services-011): é o que permite `game:GetService(...)`
	  de uma classe NÃO registrada distinguir as três realidades do Roblox real -- nome inexistente
	  (erra família Roblox, sem prefixo), classe real sem tag `Service` (devolve `nil`, sem erro), e
	  Service real ainda não coberto por esta leva (erra com prefixo `[LuauBench]`, mesma frase de
	  `Services.new`, caso 3) -- em vez da mensagem única de engenharia interna que `GetService`
	  usava antes deste mecanismo existir. `runtime` nunca lê o Roblox API Dump (regra 02): quem
	  responde pelo resolvedor é o fechamento `resolveUnknownClass`, definido logo acima de
	  `Services.Register` neste arquivo, que só consulta `generated/Manifest.luau` (as 916 classes).
	  Consequência de tipo, já refletida na assinatura que `runtime` expõe: `GetService`/
	  `FindService` devolvem `Instance?`, não mais `Instance` -- o caso "classe real sem tag
	  Service" é `nil` de verdade, fiel ao Roblox, não um erro.
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
	`Services` abaixo (`Bootstrap`/`new`/`IsKnownClass`/`IsSimulatedClass`/`GetDumpVersion`/
	`IsServiceClass`/`GetSimulatedServiceClasses` -- task-services-009, leitura pura do manifesto,
	seguras de chamar ANTES de `Bootstrap`; `IsEngineFixedChild` -- task-services-010, mesma
	garantia, leitura pura de `EngineFixedChildren.luau`; `IsEngineOnlyClass` -- task-services-014,
	mesma garantia, leitura pura do manifesto + `RUNTIME_OWNED_CLASSES`; `FlushCloudState`/
	`HasPendingCloudState` -- task-services-031, persistência local do estado "cloud" (só fazem
	sentido DEPOIS de `Bootstrap`, ver comentário de cada uma abaixo) -- ver comentário de cada uma
	abaixo).
	`EngineFixedChildren.Of` fica INTERNO: não é reexportado por este arquivo -- `cli` não tem uso
	legítimo para a lista completa de filhos fixos, só para o predicado. Nenhuma função NOVA
	exportada por task-services-011 -- `Register()`/`Bootstrap()` continuam sendo os únicos pontos
	de entrada que `cli` chama, só o EFEITO de `Register()` cresceu (agora também chama
	`Runtime.UnknownClassResolver.Set` por dentro, invisível para `cli`).
]]

local Types = require("./services/Types")
local Context = require("./services/Context")
local ClassBuilder = require("./services/ClassBuilder")
local GeneratedIndex = require("./services/generated/Index")
local BehaviorIndex = require("./services/behavior/Index")
local Manifest = require("./services/generated/Manifest")
local EngineFixedChildren = require("./services/EngineFixedChildren")
local Runtime = require("./runtime")

-- task-services-031 (arquiteto-persistencia-cloud-2026-09-06.md, seção 10): fiação da persistência
-- local do estado "cloud" (hoje: DataStoreService). `Snapshot` é o formato de documento em disco
-- (`./services/datastore/Snapshot.luau`, já aprovado -- task-services-029); `GlobalDataStoreBehavior`
-- dá acesso ao `Store` MÓDULO-LOCAL singleton onde `SetAsync`/etc de fato guardam dado (mesmo
-- `require` direto, sem passar por `behavior/Index.luau`, que `./services/behavior/DataStore.luau`
-- já usa para o mesmo fim -- ver o comentário de lá). `DateTime` é módulo padrão do Lune (nenhuma
-- dependência nova, regra 00) -- `./services/datastore/Store.luau` já o usa pelo mesmo motivo.
local Snapshot = require("./services/datastore/Snapshot")
local Store = require("./services/datastore/Store")
local GlobalDataStoreBehavior = require("./services/behavior/GlobalDataStore")
local DateTime = require("@lune/datetime")

-- Nome lógico do documento de DataStoreService -- ver `Types.CloudPersistence`, "document é sempre
-- um NOME LÓGICO opaco". Só este arquivo conhece esse literal (não é um caminho -- só `cli`, via
-- `CloudStore.luau`, decide como um nome vira caminho em disco).
local DATASTORE_DOCUMENT_NAME = "datastore"

export type BootstrapOptions = Types.BootstrapOptions

local Services = {}

-- Guarda local de idempotência: `Runtime.ClassRegistry.Register` erra em `ClassName` duplicado e
-- não tem reset (src/runtime/ClassRegistry.luau, cabeçalho) -- sem esta guarda, uma segunda
-- chamada a `Services.Register`/`Services.Bootstrap` (ex.: `cli` reiniciando o script de entrada
-- em watch mode sem reiniciar o processo Lune) erraria tentando registrar a mesma classe de novo.
local registered = false

-- task-services-011: mesma frase de `Services.new` (caso 3, "existe no dump mas não simulada
-- ainda") -- fatorada num único lugar para que as duas famílias `[LuauBench]` do território
-- (`Instance.new`, via `Services.new` abaixo, e `GetService`, via `resolveUnknownClass` logo
-- adiante) NUNCA divirjam por alguém editar uma cópia e esquecer a outra. Prefixo `[LuauBench]`
-- obrigatório (regra de idioma dos erros): este erro NÃO tem contraparte no Roblox real -- lá a
-- classe funciona normalmente, é o LuauBench que está incompleto.
local function unsimulatedClassMessage(className: string): string
	return `[LuauBench] {className} exists in the Roblox API Dump ({Manifest.DumpVersion}) but is not simulated by LuauBench yet`
end

--[[
	task-services-011 (arquiteto-runtime-2026-09-04.md, "Revisão pós-integração 2026-09-05 (5)",
	subseção "Lado services"): implementação de `Runtime.UnknownClassResolver` (contrato definido
	em src/runtime/UnknownClassResolver.luau) que `Services.Register()` instala via
	`Runtime.UnknownClassResolver.Set`. `runtime` chama isto SÓ quando `ClassRegistry.Get(className)`
	já devolveu `nil` (a classe não está registrada) -- ou seja, este fechamento só precisa
	classificar o que `runtime` sozinho não sabe: se o nome é (1) inexistente no Roblox, (2) uma
	classe real sem a tag `Service`, ou (3) uma Service real ainda não coberta por esta leva.

	PURO E TOTAL (contrato obrigatório de `Runtime.UnknownClassResolver`, ver cabeçalho daquele
	módulo): só consulta a tabela estática `Manifest.Classes` (já carregada no `require` do topo
	deste arquivo), sem efeito colateral, e NUNCA chama `error()` -- responde para QUALQUER
	`className: string`, inclusive `""` (`Manifest.Classes[""]` é `nil`, cai no primeiro ramo,
	`{ Kind = "NotAClass" }`, sem lançar nada). Quem decide errar ou devolver `nil` com o veredito é
	`DataModel:GetService` (`src/runtime/DataModel.luau`), nunca este fechamento.

	`Manifest.Covered` NÃO é consultado aqui, DE PROPÓSITO: `runtime` só chama este resolvedor
	quando a classe já não está em `Runtime.ClassRegistry` -- e "não registrada" JÁ É a resposta
	operacional para "não simulada" (a invariante documentada no cabeçalho deste arquivo: toda
	classe com `Covered == true` está registrada depois de `Services.Register()`, porque as duas
	listas nascem da mesma `tools/coverage.luau`). Consultar `Covered` de novo aqui criaria um
	QUINTO caso silencioso só para cobrir uma divergência entre as duas listas que, em produção, é
	impossível de acontecer -- superfície extra sem benefício real, rejeitada.
]]
local function resolveUnknownClass(className: string): Runtime.UnknownClassVerdict
	local entry = Manifest.Classes[className]
	if entry == nil then
		return { Kind = "NotAClass" }
	end
	if not entry.IsService then
		return { Kind = "NotAService" }
	end
	return { Kind = "ServiceNotSimulated", Message = unsimulatedClassMessage(className) }
end

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

	-- task-services-011: instala o resolvedor de classe desconhecida ANTES do laço de registro
	-- (não depois) -- se o laço estourar no meio (ex.: um Behavior futuro inventando um método
	-- fora do dump), o resolvedor já está de pé e a mensagem seguinte de GetService é útil em vez
	-- de "resolvedor não instalado" (src/runtime/DataModel.luau, ramo `verdict == nil`). Ver
	-- `resolveUnknownClass` abaixo para o mecanismo completo.
	Runtime.UnknownClassResolver.Set(resolveUnknownClass)

	for className, generated in GeneratedIndex do
		local behavior = BehaviorIndex[className]
		local descriptor = ClassBuilder.Build(generated, behavior)
		Runtime.ClassRegistry.Register(descriptor)
	end
end

--[[
	task-services-031 (arquiteto-persistencia-cloud-2026-09-06.md, seção 10, "Quem chama primeiro"):
	SE `Context.GetCloudPersistence()` devolve um port (não-nil), carrega o documento "datastore" e
	restaura o `Store` MÓDULO-LOCAL de `GlobalDataStore.luau` ANTES de qualquer script do usuário
	rodar -- chamado de dentro de `Services.Bootstrap`, logo depois de `Context.Set` (que é quem
	torna o port alcançável por `Context.GetCloudPersistence`).

	SEM guarda de "só uma vez por processo" (diferente de `Services.Register`, que TEM essa guarda):
	toda chamada a `Services.Bootstrap` com um port presente executa este passo de novo. Em uso real
	(`cli` chama `Bootstrap` uma única vez por processo, ver `Context.luau`, cabeçalho) isso não
	muda nada na prática -- e é o que permite um teste simular "processo novo, mesmo projeto" dentro
	do MESMO processo Lune (o `Store` é module-local, singleton do PROCESSO -- não há como criar um
	`Services`/`Store` genuinamente novo sem reiniciar o Lune; chamar `Bootstrap` de novo com o
	MESMO port, depois de limpar o `Store` em memória, é a forma honesta de exercitar este código de
	carga sem inventar um mecanismo de reset só para teste -- ver `init.spec.luau`, "task-services-031").

	`raw == nil` (documento nunca existiu -- primeira execução deste projeto): NENHUMA ação, o
	`Store` continua como já estava (vazio, se for de fato a primeira chamada de `Bootstrap` deste
	processo). Falha de `Load` (arquivo existe mas está ilegível) OU de `Snapshot.DecodeDocument`
	(JSON malformado, `SchemaVersion` desconhecido) PROPAGA sem `pcall` -- acceptance explícito da
	tarefa: "Load que erra no Bootstrap PROPAGA" (`cli` transforma isso num erro de projeto, exit 2
	-- nunca "recomeça do zero em silêncio", que apagaria estado real do usuário).
]]
local function loadCloudStateIfPresent(): ()
	local cloudPersistence = Context.GetCloudPersistence()
	if cloudPersistence == nil then
		return
	end

	local raw = cloudPersistence.Load(DATASTORE_DOCUMENT_NAME)
	if raw == nil then
		return
	end

	local document = Snapshot.DecodeDocument(raw)
	-- CAST DE FRONTEIRA -- `Document.Stores` é opaco para `Snapshot.luau` (`{ [string]: unknown }`,
	-- ver o cabeçalho daquele módulo); `Store.Import` VALIDA a forma de verdade em runtime antes de
	-- aplicar qualquer mudança (tudo-ou-nada, erro claro se malformado) -- mesma disciplina de
	-- outros casts de fronteira do território (ex.: `Snapshot.DecodeFromJson`).
	GlobalDataStoreBehavior.Store:Import(document.Stores :: Store.Snapshot)
end

-- `Register()` + `Context.Set()` + carga do estado "cloud" (se um port foi injetado). É a única
-- coisa que `cli` precisa chamar antes de qualquer `GetService` (arquiteto-services-2026-09-05.md,
-- "Contrato entre territórios" -> "Quem chama primeiro"; task-services-031 acrescenta o passo de
-- carga, ver `loadCloudStateIfPresent` acima).
function Services.Bootstrap(options: BootstrapOptions): ()
	Services.Register()
	Context.Set(options)
	loadCloudStateIfPresent()
end

-- Corta a stack trace multi-linha que um erro nativo do Lune produz (mesma disciplina já usada em
-- `./services/datastore/Snapshot.luau`/`../cli/CloudStore.luau` para o mesmo tipo de erro) --
-- usado só por `Services.FlushCloudState`, abaixo, para nunca deixar um erro de I/O do port vazar
-- um `stack traceback:` cru de várias linhas na mensagem que devolve para `cli`.
--
-- task-services-033 (achado residual de revisão de task-cli-030,
-- `.claude/agents-memory/revisor-cli-task-cli-030-2026-09-06.md`, achado ALTO): esta função
-- SÓ cortava a primeira quebra de linha -- nunca removia o prefixo `<caminho>:<linha>: ` que
-- `error(msg, level)` antepõe quando `level ~= 0` (é exatamente esse prefixo, não o
-- `stack traceback:`, que carrega o caminho absoluto de instalação do LuauBench em disco, ex.:
-- `D:\...\src\cli\CloudStore:170: CloudStore: could not create ...`). Hoje isso era MITIGADO só
-- porque `RunCommand.luau` (`cli`) aplica um segundo strip correto por fora (via
-- `TreeMaterializer.StripEngineErrorLocation`, defesa em profundidade) -- mas `services` NUNCA
-- pode depender de `cli` aplicar essa segunda camada para não vazar path (regra 03, "Contrato com
-- runtime": nunca `services` depende de comportamento de `cli`) -- qualquer chamador de
-- `Services.FlushCloudState` que não repita esse strip veria o caminho de novo.
--
-- `services` NÃO pode importar `src/cli/TreeMaterializer.luau` (territórios não se sobrepõem,
-- regra 05) -- por isso esta é uma CÓPIA local da mesma lógica (mesmo padrão de duplicação
-- deliberada já existente entre `Sandbox.splitErrorMessage`/`OutputFormatter.tryReattributeModuleError`/
-- o `firstLineOf` original de `cli`, três cópias antes desta correção) -- não um `require`
-- cruzado novo. O padrão `^.-:%d+: (.*)$` é IDÊNTICO ao de
-- `TreeMaterializer.StripEngineErrorLocation` (`src/cli/TreeMaterializer.luau:242-248`): `.-`
-- não-guloso garante casar o PRIMEIRO `:<número>: ` da string (o prefixo de localização real),
-- nunca um `: ` qualquer que a mensagem substantiva do erro possa conter depois; se o padrão não
-- casar (erro sem prefixo de localização reconhecível), devolve a linha inalterada.
local function firstLineOf(err: unknown): string
	local text = tostring(err)
	local line = string.match(text, "^[^\n]*") or text
	local withoutLocation = string.match(line, "^.-:%d+: (.*)$")
	return withoutLocation or line
end

--[[
	task-services-031 (arquiteto-persistencia-cloud-2026-09-06.md, seção 10, "services expõe"):
	grava o estado "cloud" (hoje: só DataStoreService) se houver mutação pendente. `cli` chama isto
	na fronteira de tique do scheduler e nos flushes forçados (fim de `scheduler:Run`, flush final).

	NO-OP SILENCIOSO, devolvendo `(false, nil)`, em DOIS casos -- nenhum dos dois é uma condição de
	erro: (1) nenhum port foi injetado (`Context.GetCloudPersistence() == nil` -- `--no-persist`, ou
	`Bootstrap` nunca chamado); (2) há um port, mas nada mudou desde o último flush
	(`Store.IsDirty() == false`) -- neste caso NADA é serializado (nem `Store.Export`, nem
	`Snapshot.EncodeDocument` rodam) -- acceptance explícito: "FlushCloudState não serializa nada
	quando nada está sujo".

	Devolve `(true, nil)` se gravou com sucesso -- e só ENTÃO chama `Store.ClearDirty()` (uma
	gravação que falhou deixa a marca-suja INTACTA, para que o próximo flush tente de novo com o
	mesmo dado pendente, em vez de perder a mutação silenciosamente).

	NUNCA propaga uma exceção de I/O do port: `cloudPersistence.Save` sob `pcall`, erro vira
	`(false, mensagem)` -- acceptance explícito: "Save que erra vira (false, mensagem), nunca
	exceção propagada" (perder persistência não deve derrubar a execução do script do usuário --
	regra 01, "erro ... nunca derruba o processo").
]]
function Services.FlushCloudState(): (boolean, string?)
	local cloudPersistence = Context.GetCloudPersistence()
	if cloudPersistence == nil then
		return false, nil
	end

	local store = GlobalDataStoreBehavior.Store
	if not store:IsDirty() then
		return false, nil
	end

	local snapshot = store:Export()
	local document = Snapshot.EncodeDocument(snapshot, DateTime.now().unixTimestampMillis)

	local ok, err = pcall(function()
		cloudPersistence.Save(DATASTORE_DOCUMENT_NAME, document)
	end)
	if not ok then
		return false, firstLineOf(err)
	end

	store:ClearDirty()
	return true, nil
end

-- task-services-031: "estado corrente (para o sumário final: 'cloud state saved to
-- .luaubench/cloud')" -- literal do contrato do arquiteto (seção 10). Reflete `Store.IsDirty()`
-- diretamente, SEM considerar se um `CloudPersistence` foi injetado: esta função só responde "há
-- mutação NÃO PERSISTIDA NESTE `Store`", nunca "vale a pena chamar `FlushCloudState`" (que já é o
-- trabalho do PRÓPRIO `FlushCloudState`, incluindo a checagem de porta ausente) -- é `cli`, que
-- sabe se passou um port a `Bootstrap`, quem decide o que essa informação significa no sumário.
function Services.HasPendingCloudState(): boolean
	return GlobalDataStoreBehavior.Store:IsDirty()
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
	task-services-009 (arquiteto-cli-2026-09-05.md, Decisão 4, "A lacuna: `cli` não tem como
	perguntar 'isto é um Service?'"): a tag `Service` do dump, para as 916 classes do manifesto
	(`ManifestEntry.IsService`).

	PURA -- só lê `generated/Manifest.luau`, uma tabela estática já carregada no `require` do topo
	deste arquivo. NÃO toca em `Runtime.ClassRegistry` nem em `Context`: por isso é explicitamente
	SEGURA de chamar ANTES de `Services.Bootstrap` ter rodado. `cli` chama esta função no passo 4 do
	pipeline (`TreePlanner.Plan`, que lê o `.project.json` e o filesystem -- NENHUMA Instance criada
	ainda), bem ANTES do `Bootstrap` no passo 7 (arquiteto-cli-2026-09-05.md, "Pipeline do
	`luaubench run`").

	É o que permite `cli` reproduzir a inferência de Service do Rojo (filho nomeado diretamente sob
	a raiz cujo nome bate com um Service real vira aquele Service, mesmo sem `$className` explícito)
	sem `cli` conhecer nome de classe nenhum e sem abrir `generated/Manifest.luau` por fora (regra
	03, "Contrato com runtime": registro central, nunca `if ClassName == "Workspace" then`).

	Classe ausente do manifesto (typo do usuário, ex. "Frmae") -> `false`, nunca erro: esta função só
	classifica: decidir se um `className` desconhecido é um erro de projeto é responsabilidade de
	quem chama (`TreePlanner`), não desta função.
]]
function Services.IsServiceClass(className: string): boolean
	local entry = Manifest.Classes[className]
	return entry ~= nil and entry.IsService
end

--[[
	task-services-009 (arquiteto-cli-2026-09-05.md, Decisão 4): as classes com `IsService == true`
	E `Covered == true` no manifesto -- os Services que este build do LuauBench de fato simula,
	ordenados por nome (ordem determinística, estável entre chamadas: nunca a ordem de iteração de
	`pairs`, sempre `table.sort` na saída).

	PURA, mesma garantia de `IsServiceClass` acima -- só lê `generated/Manifest.luau`, SEGURA de
	chamar ANTES de `Services.Bootstrap`. `cli` usa o resultado no passo 8 do pipeline (depois do
	`Bootstrap` no passo 7, mas o próprio cálculo da lista não depende disso), chamando
	`game:GetService(x)` para cada nome devolvido.

	Por quê isso existe: no Roblox real TODO Service existe sempre, mesmo que o `.project.json` não
	declare nada para ele -- `game.ReplicatedStorage` funciona num lugar que nunca colocou nada
	dentro. `Runtime.DataModel` é leniente (não cria singleton sozinho), então sem pré-criar via essa
	lista o acesso por ponto a um Service não declarado devolveria `nil` -- divergência silenciosa
	com o Roblox real, proibida pela regra 00. Pré-criar a partir desta lista (em vez de `cli`
	conhecer os nomes na mão) é o que mantém zero nome de classe dentro do território de `cli`.

	Cada nome do resultado só funciona com `game:GetService(...)` DEPOIS de `Services.Bootstrap` ter
	rodado -- é `Bootstrap`/`Register` que registra a classe em `Runtime.ClassRegistry`; antes disso
	`GetService` erra "classe não registrada" (comportamento de `Runtime.DataModel`, não desta
	função). Ver teste "cada GetService do resultado de GetSimulatedServiceClasses funciona depois
	do Bootstrap" em init.spec.luau.
]]
function Services.GetSimulatedServiceClasses(): { string }
	local names: { string } = {}
	for className, entry in Manifest.Classes do
		if entry.IsService and entry.Covered then
			table.insert(names, className)
		end
	end
	table.sort(names)
	return names
end

--[[
	task-services-010 (arquiteto-cli-2026-09-05.md, "Revisão pós-implementação 2026-09-05
	(task-cli-015) -- filho fixo do motor: adotar, não criar"): "este `(parentClassName, name,
	className)` é um filho que o MOTOR do LuauBench já pré-cria dentro de `parentClassName`?" --
	delega inteiramente a `EngineFixedChildren.Is` (módulo folha, dados puros).

	PURA -- só lê `EngineFixedChildren.luau` (tabela estática, já carregada no `require` do topo
	deste arquivo). NÃO toca `Runtime.ClassRegistry` nem `Context`: por isso é explicitamente
	SEGURA de chamar ANTES de `Services.Bootstrap` ter rodado -- mesma garantia de `IsServiceClass`/
	`GetSimulatedServiceClasses` acima. `cli` (`TreeMaterializer.createInstance`, task-cli-016) usa
	este predicado para decidir entre ADOTAR a instância que `behavior/<Pai>.luau` já criou
	(`parent:FindFirstChild(node.Name)`) e o ramo normal de criação (`Services.new`) -- nunca uma
	API de criação nova (rejeitada explicitamente pelo desenho, ver a seção citada acima).

	Exigir Name E ClassName no trio (não só ClassName) é o que mantém fiel o caso
	`"MyScripts": { "$className": "StarterPlayerScripts" }` sob `StarterPlayer`: devolve `false`, e
	`cli` cai no ramo normal, que erra `Unable to create an Instance of type "StarterPlayerScripts"`
	-- exatamente o que o Roblox real faria, sem caso especial nenhum escrito para isso.
]]
function Services.IsEngineFixedChild(parentClassName: string, name: string, className: string): boolean
	return EngineFixedChildren.Is(parentClassName, name, className)
end

-- task-services-014 (arquiteto-cli-2026-09-05.md, Decisão 17, "RUNTIME_OWNED_CLASSES -- a
-- armadilha nº 2, encontrada verificando o manifesto"): classes que o LuauBench simula FORA do
-- pipeline gerado de `services` (implementadas por `runtime`) e que por isso aparecem com
-- `Covered == false` no manifesto SEM que isso signifique "não simulada" -- `Covered` é gerado por
-- `tools/coverage.luau` a partir do registro de `services`, e `DataModel` (`Runtime.DataModel.new()`)
-- nunca passa por esse pipeline. Hoje só `DataModel`. Sem esta tabela, `IsEngineOnlyClass("DataModel")`
-- devolveria `false` (`Covered == false`) e a guarda de `cli` (`TreePlanner`, Decisão 17) não
-- dispararia no caso original que motivou esta tarefa (`task-cli-022`).
local RUNTIME_OWNED_CLASSES: { [string]: boolean } = { DataModel = true }

--[[
	task-services-014 (arquiteto-cli-2026-09-05.md, Decisão 17, "Contrato entre territórios
	(delta)"): "só o MOTOR cria instância desta classe, E este build sabe simulá-la" -- tag
	`NotCreatable` do dump (`ManifestEntry.IsAbstract`; o NOME DO CAMPO é enganoso -- é a tradução
	literal de `NotCreatable`, não "classe abstrata" no sentido de OOP; a renomeação para
	`IsNotCreatable` já está registrada como pendente em `src/runtime/ClassRegistry.luau`, NÃO feita
	nesta tarefa) E (coberta por esta leva de `services`, `Covered == true`, OU implementada por
	`runtime` fora do pipeline gerado, `RUNTIME_OWNED_CLASSES` acima).

	PURA -- só lê `generated/Manifest.luau` e `RUNTIME_OWNED_CLASSES` (tabelas estáticas, já
	carregada/definida no `require`/topo deste arquivo). NÃO toca `Runtime.ClassRegistry` nem
	`Context`: por isso é explicitamente SEGURA de chamar ANTES de `Services.Bootstrap` ter rodado --
	mesma garantia de `IsServiceClass`/`IsEngineFixedChild`/`GetSimulatedServiceClasses` acima.
	`Services.IsSimulatedClass` (consulta `Runtime.ClassRegistry`, a fonte VIVA) NÃO serve para este
	uso: `TreePlanner.Plan` roda no passo 4 do pipeline de `cli` (lê `.project.json` + filesystem,
	NENHUMA Instance criada ainda), bem ANTES de `Services.Bootstrap` no passo 7.

	`cli` (`TreePlanner.resolveCore`, Decisão 17) usa este predicado para antecipar, uma fase antes,
	que `TreeMaterializer.createInstance` vai cair no ramo 3 (`Services.new`) para este nó E que essa
	chamada não pode dar certo -- SEM pré-julgar classe que este build ainda não simula: uma classe
	`NotCreatable` mas `Covered == false` (ex. "Terrain") continua devolvendo `false` aqui, para que o
	usuário veja a mensagem VERDADEIRA (`[LuauBench] ... is not simulated yet`, no `Materialize`), e
	não uma acusação de erro de projeto por algo que o LuauBench simplesmente ainda não cobre. Esta
	função classifica "não pode nascer via `Services.new`" -- NUNCA decide legitimidade de POSIÇÃO
	(um Service coberto como "Workspace"/"ReplicatedStorage" também devolve `true` aqui; é o
	`isServiceRoot` de `TreePlanner`, uma camada acima, que sabe que a raiz é uma posição legítima).

	NOME DELIBERADO: não `IsAbstractClass` -- ver acima sobre `IsAbstract` ser a tag `NotCreatable`,
	não "abstrata"; `IsAbstractClass("Workspace") == true` levaria quem lê a uma conclusão errada
	(`Workspace` não é abstrata em sentido nenhum, só não é instanciável por script). `Engine*` já é
	vocabulário do repositório (`EngineFixedChildren`, `NewEngineInstance`) para "criado pelo motor,
	não por script do usuário" -- e o nome carrega o recorte de cobertura sem prometer ser um espelho
	cru da tag do dump.

	Classe ausente do manifesto (typo do usuário, ex. "Frmae") -> `false`, NUNCA erro: esta função só
	classifica -- decidir se um `className` desconhecido é erro de projeto é responsabilidade de quem
	chama (`TreePlanner`), igual às vizinhas acima.
]]
function Services.IsEngineOnlyClass(className: string): boolean
	local entry = Manifest.Classes[className]
	return entry ~= nil and entry.IsAbstract and (entry.Covered or RUNTIME_OWNED_CLASSES[className] == true)
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
		-- task-services-011: mesma frase de `resolveUnknownClass` (o lado GetService) -- fatorada
		-- em `unsimulatedClassMessage` para que as duas famílias `[LuauBench]` nunca divirjam.
		error(unsimulatedClassMessage(className), 2)
	end

	error(`Unable to create an Instance of type "{className}"`, 2)
end

return Services
