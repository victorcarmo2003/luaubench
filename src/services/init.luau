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

	LIMITAÇÃO DECLARADA DESTA TAREFA (task-services-001, primeira do território -- ainda não há
	gerador nem classe gerada, task-services-002 constrói os dois): `Services.Register()` não
	registra NENHUMA classe ainda, e o lookup "está no dump mas ainda não simulada" (caso da
	família de erros de `Services.new` abaixo) fica sempre vazio -- `KNOWN_BUT_UNSIMULATED` é o
	ponto de extensão que task-services-002 substitui pelo require real de
	`generated/Manifest.luau` (as 916 classes do dump, ver desenho "Decisão 5" -> "Manifesto
	completo"). Consequência honesta enquanto isso: só os casos "classe registrada" e "classe não
	existe no Roblox" da família de três erros são alcançáveis por `Services.new` nesta tarefa --
	o terceiro caso ("existe no dump, ainda não simulada") está implementado e comentado, mas fica
	sem dado real para disparar até a próxima tarefa. Não é um comportamento definitivo, é o
	esqueleto contra o qual o gerador vai emitir.
]]

local Types = require("./services/Types")
local Context = require("./services/Context")
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

	NESTA TAREFA não há nenhuma classe gerada para registrar (ver cabeçalho do arquivo). Quando
	task-services-002 existir, este é o ponto que itera `generated/Index.luau` +
	`behavior/Index.luau` e chama `ClassBuilder.Build` + `Runtime.ClassRegistry.Register` para
	cada classe coberta.
]]
function Services.Register(): ()
	if registered then
		return
	end
	registered = true
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
