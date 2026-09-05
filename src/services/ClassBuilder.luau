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

--[[
	Superfície FIXA de `Runtime.Instance` -- nomes que `src/runtime/Instance.luau` já trata
	nativamente e que `Instance.SetClassMethods` REJEITA se aparecerem numa tabela de
	`ClassDescriptor.Methods` (colisão pega em runtime, uma vez por classe, no primeiro `new()`).
	Confirmado por leitura direta de `src/runtime/Instance.luau` nesta tarefa (task-services-003),
	não por suposição (regra 00):

	- `FIXED_PROPERTY_KEYS` (Instance.luau ~L544): ClassName/Name/Parent.
	- `SIGNAL_KEYS` (Instance.luau ~L533): os 5 sinais fixos -- Changed/ChildAdded/ChildRemoved/
	  AncestryChanged/Destroying.
	- os 13 MÉTODOS BASE nativos da tabela `Methods` de Instance.luau (confirmado por grep de
	  `function Methods.X` no arquivo): GetChildren/GetDescendants/FindFirstChild/
	  FindFirstChildOfClass/FindFirstChildWhichIsA/FindFirstAncestor/IsA/IsDescendantOf/
	  IsAncestorOf/ClearAllChildren/GetFullName/Destroy/WaitForChild.

	O Roblox API Dump DECLARA vários desses nomes como membros Function reais da classe "Instance"
	(ex.: `FindFirstChild`, `Security: None`) -- o gerador (task-services-002) os emite em
	`GeneratedClass.MethodNames` corretamente, espelhando o dump 1:1 (regra 03: o gerador não pode
	inventar nem omitir por conta própria). Mas isso colide com a superfície fixa que
	`Runtime.Instance` já implementa nativamente, e `Instance.SetClassMethods` existe
	DELIBERADAMENTE para pegar essa colisão alto e claro (ver o comentário dela em
	`src/runtime/Instance.luau`: "Colisão é bug do gerador de `services` e tem que estourar uma vez
	no load, nunca ser resolvida por ordem de consulta em `__index`" -- e a própria mensagem de erro
	runtime diz "corrigir lá", ou seja, aqui, em `services`). Confirmado empiricamente nesta tarefa:
	registrar "Instance" sem este filtro e instanciar "Folder" (que herda o `Methods` achatado de
	"Instance") erra `Instance.SetClassMethods: a chave 'FindFirstChild' colide com a superfície
	fixa de Instance ...`.

	`ClassBuilder` é o ponto certo do filtro, não `runtime`: omitir essas chaves do
	`ClassDescriptor.Methods` resultante é TRANSPARENTE para o script do usuário --
	`InstanceMeta.__index` (passo 3, métodos base) já resolve essas chamadas ANTES de sequer olhar
	`classMethods` (passo 4), então um stub `[LuauBench]` para um desses nomes seria morto por
	construção, nunca alcançável. Nenhuma classe desta leva precisa REDEFINIR o comportamento de um
	nome reservado (isso exigiria mudar `runtime`, fora do território de `services`) -- se algum dia
	precisar, é decisão do arquiteto, não algo que `ClassBuilder` decide sozinho.
]]
local RESERVED_INSTANCE_SURFACE: { [string]: boolean } = {
	-- FIXED_PROPERTY_KEYS
	ClassName = true,
	Name = true,
	Parent = true,
	-- SIGNAL_KEYS (os 5 sinais fixos)
	Changed = true,
	ChildAdded = true,
	ChildRemoved = true,
	AncestryChanged = true,
	Destroying = true,
	-- os 13 métodos base nativos
	GetChildren = true,
	GetDescendants = true,
	FindFirstChild = true,
	FindFirstChildOfClass = true,
	FindFirstChildWhichIsA = true,
	FindFirstAncestor = true,
	IsA = true,
	IsDescendantOf = true,
	IsAncestorOf = true,
	ClearAllChildren = true,
	GetFullName = true,
	Destroy = true,
	WaitForChild = true,
}

function ClassBuilder.Build(generated: Types.GeneratedClass, behavior: Types.Behavior?): Runtime.ClassDescriptor
	local behaviorMethods: { [string]: unknown } = if behavior ~= nil and behavior.Methods ~= nil
		then behavior.Methods
		else {}

	-- (a) invariante 1 da regra 00 virando código: TODA chave de `behavior.Methods` precisa
	-- existir em `generated.MethodNames`. Erro alto, em português (engenharia interna de
	-- `services`/`behavior`, nunca observável pelo script do usuário -- o load falha antes de
	-- qualquer script rodar, então nenhum comportamento fantasma chega a ser aprovado por
	-- descuido). Checagem adicional (RESERVED_INSTANCE_SURFACE, ver comentário acima): nenhum
	-- `behavior.Methods` pode tentar implementar um nome da superfície fixa de `Runtime.Instance`
	-- -- isso nunca teria efeito (a superfície nativa sempre vence em `__index`) e hoje estouraria
	-- de forma confusa dentro de `Instance.SetClassMethods`; aqui a mensagem é clara e em português.
	local declaredMethodNames: { [string]: boolean } = {}
	for _, methodName in generated.MethodNames do
		declaredMethodNames[methodName] = true
	end

	for methodName in behaviorMethods do
		if RESERVED_INSTANCE_SURFACE[methodName] then
			error(
				`método '{methodName}' de '{generated.ClassName}' é superfície fixa nativa de Runtime.Instance (propriedade/evento/método base) e não pode ser reimplementado por behavior -- mudança de comportamento nativo é decisão de runtime/arquiteto, não de services`,
				2
			)
		end
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
	-- runtime que cada valor instalado é de fato uma função. Nomes em RESERVED_INSTANCE_SURFACE
	-- são OMITIDOS por completo (nem stub) -- ver o comentário de RESERVED_INSTANCE_SURFACE acima
	-- para o porquê disso ser transparente, não uma lacuna de cobertura.
	local methods: { [string]: unknown } = {}
	for _, methodName in generated.MethodNames do
		if not RESERVED_INSTANCE_SURFACE[methodName] then
			local implementation = behaviorMethods[methodName]
			if implementation ~= nil then
				methods[methodName] = implementation
			else
				methods[methodName] = makeUnsimulatedMethodStub(generated.ClassName, methodName)
			end
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
