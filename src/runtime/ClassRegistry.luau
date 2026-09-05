--!strict

--[[
	Registro central de classes: o mecanismo de inversão de dependência que permite `services`
	"avisar" `runtime` da existência de uma classe sem `runtime` conhecer o nome dela de
	antemão (regra 02 — `runtime` nunca conhece um Service/classe concreta por nome, nunca lê
	o API Dump). Ver .claude/agents-memory/arquiteto-runtime-2026-09-04.md, seção
	"ClassRegistry.luau", a seção "Revisão pós-integração 2026-09-04 (2) — contrato
	ClassDescriptor.Construct" (contrato Initialize atual, substitui o Construct original) e a
	seção "Revisão pós-integração 2026-09-04 (3) — acesso a membro" (campo Methods + achatamento
	de métodos de classe, task-runtime-016).

	`services` chama `Register` uma vez por classe coberta do API Dump, no carregamento do
	módulo (efeito de `require("services")`, antes de qualquer `cli` tentar `new`). `cli`
	(e o Sandbox, através do que `services` embrulhar em `extraGlobals.Instance.new`) chama
	`ClassRegistry.new` para instanciar por nome — é esta função, e só ela, que cria a instância
	base (via Instance.NewBase), aplica a cadeia de classes (via Instance.SetClassChain) e
	instala os métodos achatados da classe (via Instance.SetClassMethods) ANTES de chamar o
	Initialize da classe concreta. `Instance.NewBase` não é mais chamado por `services` (ver
	seção "Consequência: Runtime.Instance.NewBase sai da superfície pública") —
	`ClassRegistry.new` é o único criador de instância disponível a `services`/`cli`.

	Depende de: Instance.luau (tipo Instance, Instance.NewBase e Instance.SetClassChain, para
	resolver IsA sem Instance.luau precisar conhecer ClassRegistry.luau — evita require
	circular; a cadeia é resolvida aqui, uma vez por construção, e só consultada como cache
	local dentro de Instance.IsA, ver desenho seção "Riscos e decisões").

	Invariante de processo: ClassRegistry assume um processo por execução do LuauBench — não
	há desregistro nem reset do `registry` global (achado BAIXO da revisão de task-runtime-004).
	Cada `luaubench run` é um processo Lune novo, então o registro fixo por processo é seguro;
	se algum dia existir um harness agregado (vários "processos" simulados na mesma VM Lune) ou
	um watch mode que precise invalidar isso, essa invariante volta ao arquiteto antes de mudar.
]]

local InstanceModule = require("./Instance")

type Instance = InstanceModule.Instance

export type ClassDescriptor = {
	ClassName: string,
	SuperClassName: string?, -- nil = herda direto de Instance
	IsAbstract: boolean, -- ex.: "Instance"/"PVInstance" não instanciáveis via .new
	IsService: boolean, -- true = DataModel:GetService cria singleton sob a raiz

	-- Métodos que ESTA classe declara — nunca os herdados. Espelha como o Roblox API Dump modela
	-- herança (campo `Superclass`, sem redeclarar membro da superclasse): o gerador de `services`
	-- emite exatamente o que o dump diz, e quem achata a cadeia inteira é ClassRegistry (uma vez
	-- por classe, cache lazy no primeiro `new`) — ver resolveClassMethods abaixo. Opcional: classe
	-- sem método próprio dispensa o campo. task-runtime-016, ver arquiteto-runtime-2026-09-04.md,
	-- seção "Revisão pós-integração 2026-09-04 (3) — acesso a membro".
	Methods: InstanceModule.ClassMethods?,

	-- Chamado por ClassRegistry.new SOBRE uma instância base JÁ criada, JÁ com a cadeia de
	-- classes aplicada e JÁ com os métodos da classe instalados — logo tanto
	-- `instance:IsA(qualquerAncestral)` quanto `instance:MetodoDaPropriaClasse()` são confiáveis
	-- aqui dentro. Só configura: não cria, não devolve nada. `instance.Name` já vem preenchido (o
	-- `name` passado a ClassRegistry.new, ou o ClassName como default, resolvido por NewBase).
	-- Opcional: classe sem propriedade default nem método próprio dispensa a função inteira.
	Initialize: ((instance: Instance) -> ())?,
}

-- Storage: um `ClassDescriptor` por `ClassName`, populado por `Register` e nunca removido —
-- não há caso de uso de "desregistrar uma classe" nesta fase (a lista de classes conhecidas é
-- fixa por processo, resolvida do API Dump no carregamento de `services`).
local registry: { [string]: ClassDescriptor } = {}

-- Cache module-local da tabela de métodos ACHATADA (própria + herdada) e CONGELADA por
-- ClassName, construída preguiçosamente no primeiro `new()` — mesma razão já documentada para
-- `resolveClassChain`: `services` pode registrar fora de ordem topológica, então a cadeia só
-- precisa estar completa na hora de instanciar, não no momento do registro. `methods = nil`
-- guardado explicitamente distingue "já resolvido, esta classe não tem método nenhum na cadeia"
-- de "ainda não resolvido", evitando recomputar o achatamento a cada `new()` da mesma classe.
type MethodsCacheEntry = { methods: InstanceModule.ClassMethods? }
local methodsCache: { [string]: MethodsCacheEntry } = {}

local ClassRegistry = {}

function ClassRegistry.Register(descriptor: ClassDescriptor): ()
	if registry[descriptor.ClassName] ~= nil then
		error(`classe '{descriptor.ClassName}' já registrada em ClassRegistry`, 2)
	end
	registry[descriptor.ClassName] = descriptor
end

function ClassRegistry.Get(className: string): ClassDescriptor?
	return registry[className]
end

function ClassRegistry.IsRegistered(className: string): boolean
	return registry[className] ~= nil
end

-- Resolve a cadeia de superclasses de `descriptor` andando por `SuperClassName` através dos
-- descriptors já registrados (nunca lendo o API Dump — isso é responsabilidade de `services`).
-- Feito em `new()`, não em `Register`, de propósito: `services` pode registrar classes fora de
-- ordem topológica (ex.: uma subclasse antes da sua superclasse), já que a cadeia só precisa
-- estar completa no momento em que alguém de fato instancia, não no momento do registro.
-- Termina sempre em "Instance": `SuperClassName == nil` (ou o literal "Instance", aceito pelo
-- mesmo motivo) é o contrato de "herda direto de Instance" — "Instance" nunca tem/precisa de
-- descriptor próprio aqui, é a base universal que `Instance.luau` já constrói via `NewBase`.
--
-- Nível 3 nos dois `error` abaixo (em vez de 0): `resolveClassChain` é local, chamada de um
-- único call site (`ClassRegistry.new`, logo abaixo) e não em posição de tail call, então o
-- nível 3 aponta para quem chamou `ClassRegistry.new` — o mesmo alvo do nível 2 usado dentro de
-- `new`. Se algum dia esta função ganhar um segundo call site, essa conta muda e o nível
-- precisa ser revisto.
local function resolveClassChain(descriptor: ClassDescriptor): { string }
	local chain: { string } = {}
	local seen: { [string]: boolean } = {}

	local currentClassName: string = descriptor.ClassName
	local currentSuperClassName: string? = descriptor.SuperClassName

	while true do
		if seen[currentClassName] then
			error(`ciclo de herança detectado na cadeia de classes envolvendo '{currentClassName}'`, 3)
		end
		seen[currentClassName] = true
		table.insert(chain, currentClassName)

		if currentSuperClassName == nil or currentSuperClassName == "Instance" then
			break
		end

		local superDescriptor = registry[currentSuperClassName]
		if superDescriptor == nil then
			error(
				`classe '{currentClassName}' referencia superclasse '{currentSuperClassName}' não registrada em ClassRegistry`,
				3
			)
		end

		currentClassName = currentSuperClassName
		currentSuperClassName = superDescriptor.SuperClassName
	end

	table.insert(chain, "Instance")
	return chain
end

-- Achata `Methods` de cada elo de `chain` (já resolvida por resolveClassChain, formato
-- {Concreta, ..., Super, "Instance"}) numa única tabela congelada, cacheada por `className`.
-- Percorre a cadeia DE TRÁS PARA FRENTE (do fim, "Instance", até o início, a classe concreta):
-- "Instance" nunca tem descriptor próprio aqui (mesmo motivo de resolveClassChain) e é pulado
-- silenciosamente; cada superclasse registrada mescla o que ELA declara, e a classe mais
-- concreta mescla por ÚLTIMO — sobrescrevendo qualquer método de mesmo nome de uma superclasse,
-- que é a semântica de override correta. Devolve `nil` se nenhum elo da cadeia declarar Methods
-- (classe sem método próprio nem herdado): ClassRegistry.new pula SetClassMethods nesse caso,
-- mantendo `classMethods` nil e o comportamento idêntico ao de hoje.
local function resolveClassMethods(className: string, chain: { string }): InstanceModule.ClassMethods?
	local cached = methodsCache[className]
	if cached ~= nil then
		return cached.methods
	end

	local flattened: InstanceModule.ClassMethods = {}
	local hasAny = false

	for i = #chain, 1, -1 do
		local linkDescriptor = registry[chain[i]]
		if linkDescriptor ~= nil then
			local linkMethods = linkDescriptor.Methods
			if linkMethods ~= nil then
				hasAny = true
				for key, value in linkMethods do
					flattened[key] = value
				end
			end
		end
	end

	if not hasAny then
		methodsCache[className] = { methods = nil }
		return nil
	end

	table.freeze(flattened)
	methodsCache[className] = { methods = flattened }
	return flattened
end

function ClassRegistry.new(className: string, name: string?): Instance
	local descriptor = registry[className]
	if descriptor == nil then
		error(`classe '{className}' não registrada`, 2)
	end
	if descriptor.IsAbstract then
		error(`'{className}' é abstrata, não pode ser instanciada`, 2)
	end

	-- Ordem obrigatória (task-runtime-013 fixou resolver->NewBase->SetClassChain->Initialize;
	-- task-runtime-016 insere SetClassMethods entre SetClassChain e Initialize — mesma razão:
	-- a identidade de classe precisa estar COMPLETA antes de qualquer código de `services`
	-- rodar, para que dentro do próprio Initialize tanto `instance:IsA(ancestral)` quanto
	-- `instance:MetodoDaPropriaClasse()` já funcionem). ClassName/identidade da tabela/default
	-- de Name ficam garantidos aqui, não confiados a cada uma das dezenas de classes geradas.
	local chain = resolveClassChain(descriptor)
	local instance = InstanceModule.NewBase(className, name)
	InstanceModule.SetClassChain(instance, chain)

	local methods = resolveClassMethods(className, chain)
	if methods ~= nil then
		InstanceModule.SetClassMethods(instance, methods)
	end

	-- SEM pcall: erro dentro do Initialize de uma classe é erro real de construção e sobe para
	-- quem chamou (`cli`/Sandbox), exatamente como no Roblox. A base meio-inicializada fica sem
	-- referência e é coletada pelo GC — `internals` em Instance.luau é mapa fraco por chave, não
	-- precisa de limpeza explícita aqui.
	if descriptor.Initialize ~= nil then
		descriptor.Initialize(instance)
	end

	return instance
end

return ClassRegistry
