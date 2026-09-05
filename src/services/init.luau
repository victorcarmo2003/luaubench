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
	cabeçalho desse arquivo para o porquê) via `ClassBuilder.Build`. `KNOWN_BUT_UNSIMULATED`
	CONTINUA vazio nesta tarefa -- ligá-lo a `generated/Manifest.luau` (as 916 classes do dump,
	"Decisão 5" -> "Manifesto completo") é escopo de task-services-005 ("Services.new: a família de
	três erros de classe"), não desta. Consequência honesta enquanto isso: só os casos "classe
	registrada" e "classe não existe no Roblox" da família de três erros de `Services.new` são
	alcançáveis agora -- o terceiro caso ("existe no dump, ainda não simulada") continua
	implementado e comentado, sem dado real para disparar até task-services-005.

	BLOQUEIO DE RUNTIME DESCOBERTO NESTA TAREFA (confirmado rodando de verdade, não suposição --
	ver o relatório de task-services-003 para o desenho do fix e o repro completo): TODA classe
	`Service` coberta por esta leva (ReplicatedStorage/ServerStorage/ServerScriptService/
	ReplicatedFirst/StarterPack/StarterGui/StarterPlayer/Workspace/Lighting) carrega a tag
	`NotCreatable` no dump -- fiel ao Roblox real (não dá para `Instance.new("Workspace")` lá
	também) -- e o gerador traduz isso corretamente para `GeneratedClass.IsAbstract = true`. O
	problema: `Runtime.ClassRegistry.new` rejeita `IsAbstract == true` INCONDICIONALMENTE, sem
	distinguir "script chamando `Instance.new` numa classe não-criável" (o que a tag deveria
	bloquear, e que `Services.new` abaixo já bloqueia por conta própria, ANTES de chamar
	`ClassRegistry.new`) de "o motor construindo o singleton internamente" (o que
	`DataModel:GetService`, em `src/runtime/DataModel.luau`, precisa fazer -- e o Roblox real
	permite). Resultado confirmado: `game:GetService("ReplicatedStorage")` e
	`game:GetService("Workspace")` ERRAM HOJE com `'{Classe}' é abstrata, não pode ser
	instanciada` -- em vez de devolver o singleton. Isso está FORA do território deste módulo
	(a rejeição vive em `src/runtime/ClassRegistry.luau`, chamada por `src/runtime/DataModel.luau`)
	e não é contornável por `services` sem violar "não toque em `src/runtime/`". `Services.new`
	abaixo NÃO é afetado para o caminho `Instance.new` do usuário (ele já barra classe abstrata
	antes de chegar em `ClassRegistry.new` -- ver o comentário de `Services.new`), mas
	`game:GetService(...)` de qualquer Service desta leva, e a criação dos filhos fixos de
	`StarterPlayer`, ficam bloqueados até `coder-runtime` resolver isso (despachado pelo relatório
	desta tarefa).

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
]]

local Types = require("./services/Types")
local Context = require("./services/Context")
local ClassBuilder = require("./services/ClassBuilder")
local GeneratedIndex = require("./services/generated/Index")
local BehaviorIndex = require("./services/behavior/Index")
local Runtime = require("./runtime")

export type BootstrapOptions = Types.BootstrapOptions

-- Versão do Roblox API Dump fixada nesta leva -- mesmo valor, mesma razão do literal duplicado
-- em ClassBuilder.luau (ver o comentário lá): nenhum dos dois arquivos que normalmente seriam a
-- fonte única (tools/api-dump.lock.json, generated/Manifest.luau) existe ainda nesta tarefa.
local DUMP_COMMIT = "28360dea4b90b35dc3fe9f829baae64fb6c50e75"
local DUMP_VERSION = "0.737.0.7371584"

-- Ponto de extensão: "está no dump, ainda não simulada" -- terceiro caso da família de erros de
-- `Services.new`, abaixo. Vazio nesta tarefa (ver cabeçalho do arquivo) -- task-services-002
-- substitui isto por um require real de `generated/Manifest.luau`. Enquanto isso,
-- `IsKnownClass` só enxerga o que está REGISTRADO em `Runtime.ClassRegistry`: sem manifesto,
-- "conhecida do dump" e "simulada" são, na prática, a mesma pergunta -- verdade honesta do
-- estado atual, não uma aproximação escondida.
local KNOWN_BUT_UNSIMULATED: { [string]: boolean } = {}

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

-- "Está no dump?" -- inclui tanto o que já está simulado (registrado) quanto o que só consta no
-- manifesto completo (ver limitação declarada no cabeçalho: `KNOWN_BUT_UNSIMULATED` está vazio
-- nesta tarefa, então hoje isto equivale a `IsSimulatedClass`).
function Services.IsKnownClass(className: string): boolean
	return Runtime.ClassRegistry.IsRegistered(className) or KNOWN_BUT_UNSIMULATED[className] == true
end

-- "Está coberta (registrada, comportamento existe)?" -- sempre um subconjunto de IsKnownClass.
function Services.IsSimulatedClass(className: string): boolean
	return Runtime.ClassRegistry.IsRegistered(className)
end

function Services.GetDumpVersion(): { Commit: string, Version: string }
	return { Commit = DUMP_COMMIT, Version = DUMP_VERSION }
end

--[[
	O `Instance.new` que `cli` injeta em `extraGlobals.Instance.new` do Sandbox
	(arquiteto-services-2026-09-05.md, "Decisão 5"). Família de erros, nesta ordem -- só DUAS
	mensagens distintas para quatro branches, de propósito (ver tabela do desenho):

	1. Classe registrada (simulada) e NÃO abstrata -> instancia via `Runtime.ClassRegistry.new`.
	2. Classe registrada e ABSTRATA (tag `NotCreatable` do dump) -> erra com a MESMA mensagem do
	   caso 4 -- é o que o Roblox real faz para uma classe não-criável (aproximação de boa-fé;
	   string exata não confirmada byte-a-byte, comentada como tal no próprio desenho).
	3. Classe NÃO registrada mas conhecida do dump (existe, ainda não simulada por LuauBench) ->
	   erra com prefixo "[LuauBench]" (regra de idioma: sem contraparte real, é o LuauBench que
	   está incompleto, não o Roblox). Inalcançável nesta tarefa -- ver limitação declarada no
	   cabeçalho do arquivo.
	4. Classe nem registrada nem conhecida do dump (não existe no Roblox) -> família Roblox, sem
	   prefixo, mesma mensagem do caso 2.
]]
function Services.new(className: string, name: string?): Runtime.Instance
	local descriptor = Runtime.ClassRegistry.Get(className)
	if descriptor ~= nil then
		if descriptor.IsAbstract then
			error(`Unable to create an Instance of type "{className}"`, 2)
		end
		return Runtime.ClassRegistry.new(className, name)
	end

	if KNOWN_BUT_UNSIMULATED[className] then
		error(
			`[LuauBench] {className} exists in the Roblox API Dump ({DUMP_VERSION}) but is not simulated by LuauBench yet`,
			2
		)
	end

	error(`Unable to create an Instance of type "{className}"`, 2)
end

return Services
