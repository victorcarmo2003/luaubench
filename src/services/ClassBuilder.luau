--!strict

--[[
	Converte um `Types.GeneratedClass` (o que o gerador do dump emite, task-services-002) + um
	`Types.Behavior?` (o que um humano escreve à mão em `behavior/<Classe>.luau`) num
	`Runtime.ClassDescriptor` -- o formato que `Runtime.ClassRegistry.Register` espera. É onde a
	invariante 1 da regra 00 ("nenhum agente inventa propriedade, evento ou comportamento de
	Instance que não esteja no dump") deixa de ser regra de revisão e vira código verificado
	mecanicamente, uma vez por classe, no LOAD -- não em teste, não em revisão manual (ver Build,
	passo (a) abaixo). Ver .claude/agents-memory/arquiteto-services-2026-09-05.md, seção
	"Módulos" -> "src/services/ClassBuilder.luau", para a ordem exata que Build segue.

	REGRA DE IDIOMA DOS ERROS (mesmo desenho, "Decisão 5"): erro com contraparte real no Roblox
	usa a família do Roblox, em inglês, sem prefixo; erro SEM contraparte real (só existe porque o
	LuauBench é incompleto) usa inglês COM prefixo "[LuauBench]"; erro de engenharia interna (uso
	errado da API por `services`/`behavior` -- é o caso do passo (a) abaixo: um agente inventando
	`behavior.Methods` fora do que o dump declara) fica em português.

	Depende de: Types.luau, ../runtime. Usado por: init.luau (Services.Register, quando existir --
	nesta tarefa ainda não há classe gerada para passar por aqui em produção; o exercício de ponta
	a ponta vive nos specs, com uma classe FICTÍCIA).
]]

local Types = require("./Types")
local Runtime = require("../runtime")

local ClassBuilder = {}

-- "Instance" é a raiz simulada do LuauBench -- `Runtime.ClassDescriptor.SuperClassName == nil`
-- significa "herda direto de Instance" (ver src/runtime/ClassRegistry.luau, comentário do campo).
-- O gerador normaliza `Superclass == "Object"` do dump para a STRING "Instance"
-- (arquiteto-services-2026-09-05.md, "Decisão 1 -- Fecho transitivo automático": "Object nunca é
-- emitido como classe; Instance é a raiz simulada do LuauBench"), então QUALQUER GeneratedClass
-- cujo `Superclass` normalizado seja literalmente "Instance" -- inclusive o da própria classe
-- "Instance" -- termina a cadeia aqui, sem nenhum lookup no registry.
local INSTANCE_CLASS_NAME = "Instance"

-- Versão do Roblox API Dump fixada nesta leva (arquiteto-services-2026-09-05.md, "Decisão 2").
-- Duplicado do valor que vai viver em tools/api-dump.lock.json/generated/Manifest.luau -- nenhum
-- dos dois existe ainda nesta tarefa (task-services-002 constrói o gerador). Quando
-- generated/Manifest.luau existir, ele vira a fonte única e este literal é substituído por uma
-- leitura dele -- ver o mesmo comentário em src/services/init.luau (GetDumpVersion).
local DUMP_VERSION = "0.737.0.7371584"

--[[
	Passo (b) de Build: mensagem do stub para um método que o dump declara mas que `services`
	ainda não implementou. Regra 03: "Service não coberto ainda não é stub silencioso que finge
	funcionar" -- aqui aplicado a MÉTODO dentro de uma classe já coberta, não à classe inteira.
	SEM contraparte real (é o LuauBench que está incompleto, não o Roblox) -- prefixo
	"[LuauBench]" obrigatório pela regra de idioma dos erros acima. Note a ausência da versão do
	dump aqui (diferente de `Services.new`, em init.luau, que a inclui para classe não simulada) --
	mesma assimetria já fechada no desenho ("Decisão 5", tabela de mensagens: a mensagem de método
	não traz versão, a de classe traz).
]]
local function makeUnsimulatedMethodStub(className: string, methodName: string): (...unknown) -> ()
	return function(...: unknown): ()
		error(
			`[LuauBench] {className}:{methodName}() exists in the Roblox API Dump but is not simulated by LuauBench yet`,
			2
		)
	end
end

function ClassBuilder.Build(generated: Types.GeneratedClass, behavior: Types.Behavior?): Runtime.ClassDescriptor
	local behaviorMethods: { [string]: unknown } = if behavior ~= nil and behavior.Methods ~= nil
		then behavior.Methods
		else {}

	-- (a) invariante 1 da regra 00 virando código: TODA chave de `behavior.Methods` precisa
	-- existir em `generated.MethodNames`. Erro alto, em português (engenharia interna de
	-- `services`/`behavior`, nunca observável pelo script do usuário -- o load falha antes de
	-- qualquer script rodar, então nenhum comportamento fantasma chega a ser aprovado por
	-- descuido).
	local declaredMethodNames: { [string]: boolean } = {}
	for _, methodName in generated.MethodNames do
		declaredMethodNames[methodName] = true
	end

	for methodName in behaviorMethods do
		if not declaredMethodNames[methodName] then
			error(
				`método '{methodName}' não existe em '{generated.ClassName}' segundo o Roblox API Dump {DUMP_VERSION}`,
				2
			)
		end
	end

	-- (b) completa MethodNames sem implementação com o stub que erra -- nunca stub silencioso,
	-- nunca nil (regra 03). Método implementado por `behavior` entra como está: `unknown` é o
	-- tipo honesto (a mesma disciplina de `Runtime.ClassMethods` -- ver Instance.luau) --
	-- `Instance.SetClassMethods`, chamado depois por `Runtime.ClassRegistry.new`, valida em
	-- runtime que cada valor instalado é de fato uma função.
	local methods: { [string]: unknown } = {}
	for _, methodName in generated.MethodNames do
		local implementation = behaviorMethods[methodName]
		if implementation ~= nil then
			methods[methodName] = implementation
		else
			methods[methodName] = makeUnsimulatedMethodStub(generated.ClassName, methodName)
		end
	end

	-- (c) table.freeze -- exigência de `Instance.SetClassMethods` (chamada depois, por
	-- `Runtime.ClassRegistry.new`): a tabela é compartilhada por todas as instâncias da classe e
	-- não pode ficar mutável depois de instalada.
	table.freeze(methods)

	-- (d) monta o ClassDescriptor. Ver INSTANCE_CLASS_NAME acima para a tradução
	-- Superclass -> SuperClassName. `Initialize` é sempre o de `behavior` (ou nil) -- nada
	-- gerado cria Signal: quem semeia um Signal fresco por entrada `Kind == "Event"` do schema é
	-- `Runtime.ClassRegistry.new`, via `Instance.SetClassSchema` (Decisão 6, item 1), ANTES de
	-- chamar este Initialize.
	return {
		ClassName = generated.ClassName,
		SuperClassName = if generated.Superclass == INSTANCE_CLASS_NAME then nil else generated.Superclass,
		IsAbstract = generated.IsAbstract,
		IsService = generated.IsService,
		Methods = methods,
		Schema = generated.Schema,
		Initialize = if behavior ~= nil then behavior.Initialize else nil,
	}
end

return ClassBuilder
