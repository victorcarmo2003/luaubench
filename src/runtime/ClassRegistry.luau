--!strict

--[[
	Registro central de classes: o mecanismo de inversão de dependência que permite `services`
	"avisar" `runtime` da existência de uma classe sem `runtime` conhecer o nome dela de
	antemão (regra 02 — `runtime` nunca conhece um Service/classe concreta por nome, nunca lê
	o API Dump). Ver .claude/agents-memory/arquiteto-runtime-2026-09-04.md, seção
	"ClassRegistry.luau", a seção "Revisão pós-integração 2026-09-04 (2) — contrato
	ClassDescriptor.Construct" (contrato Initialize atual, substitui o Construct original) e a
	seção "Revisão pós-integração 2026-09-04 (3) — acesso a membro" (campo Methods + achatamento
	de métodos de classe, task-runtime-016) e .claude/agents-memory/arquiteto-services-2026-09-05.md,
	"Decisão 3"/"Decisão 4"/"Decisão 6" (campo Schema + achatamento de schema, modo estrito de
	Instance.luau, task-runtime-018).

	`services` chama `Register` uma vez por classe coberta do API Dump, no carregamento do
	módulo (efeito de `require("services")`, antes de qualquer `cli` tentar `new`). `cli`
	(e o Sandbox, através do que `services` embrulhar em `extraGlobals.Instance.new`) chama
	`ClassRegistry.new` para instanciar por nome — a via PÚBLICA, com a política de `NotCreatable`
	(ver campo `IsAbstract`, abaixo). `ClassRegistry.new` e `ClassRegistry.NewEngineInstance`
	(task-runtime-023, ver .claude/agents-memory/arquiteto-runtime-2026-09-04.md, seção "Revisão
	pós-integração 2026-09-05 (4) — `NotCreatable` vs. abstrata: dois construtores em
	`ClassRegistry`") fazem a MESMA construção completa — criam a instância base (via
	Instance.NewBase), aplicam a cadeia de classes (via Instance.SetClassChain), instalam os
	métodos achatados da classe (via Instance.SetClassMethods) e instalam + semeiam o schema
	achatado da classe (via Instance.SetClassSchema) ANTES de chamar o Initialize da classe
	concreta — mas `ClassRegistry.new` aplica, ANTES de delegar, a guarda de `IsAbstract`
	("`Instance.new` não cria isto", a tradução da tag `NotCreatable` do dump), e
	`ClassRegistry.NewEngineInstance` não. `Instance.NewBase` não é mais chamado por `services`
	(ver seção "Consequência: Runtime.Instance.NewBase sai da superfície pública") — as duas
	funções acima são os únicos criadores de instância disponíveis a `services`/`cli`.

	DOIS CONSTRUTORES, LISTA FECHADA DE CHAMADORES LEGÍTIMOS de `NewEngineInstance` (a via do
	motor, sem a guarda de `IsAbstract` — a guarda de "classe não registrada" NÃO é pulada, essa
	continua valendo nas duas vias):
	  1. `runtime/DataModel.luau`, em `GetService` — construção do singleton de Service (toda
	     Service do dump é `NotCreatable` e mesmo assim o motor a cria).
	  2. `services`, dentro de um `Behavior.Initialize`, para criar filho fixo de uma classe
	     (ex.: `StarterPlayer` criando `StarterPlayerScripts`/`StarterCharacterScripts`, as duas
	     `NotCreatable` e `IsService = false` — inalcançáveis por `GetService`).
	  3. `services`, dentro de um `Behavior.Methods`, para construir um objeto do motor que o
	     método real DEVOLVE e que não é filho de ninguém (ex.: `DataStoreService:GetDataStore`
	     -> `DataStore`, `GlobalDataStore:GetAsync` -> `DataStoreKeyInfo`,
	     `DataStore:ListVersionsAsync` -> `DataStoreVersionPages`, `TweenService:Create` ->
	     `Tween` — todas `NotCreatable` e `IsService = false`, logo inalcançáveis por
	     `ClassRegistry.new` (que recusa `IsAbstract`, e deve continuar recusando) e por
	     `GetService`). Ver .claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.0.3 —
	     `ClassRegistry.NewEngineInstance` ganha um terceiro chamador legítimo" (leva 2 de
	     `services`, task-runtime-035).
	  4. `cli` NUNCA — `cli` usa `game:GetService(...)` para Service e `ClassRegistry.new`/
	     `Services.new` para o resto, preservando o erro claro para um `"$className"` inválido
	     vindo do `.project.json` (entrada não confiável do usuário).

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

	-- `IsAbstract` traduz a tag `NotCreatable` do Roblox API Dump e significa exatamente uma
	-- coisa: "`Instance.new` não cria isto" — o gate voltado ao script, aplicado por
	-- `Services.new`. NÃO significa "nunca existe instância desta classe": toda `Service` é
	-- `NotCreatable` e mesmo assim o motor cria o singleton, e `StarterPlayerScripts`
	-- (`IsService = false`) é criada pelo próprio `StarterPlayer`. Construção pelo motor usa
	-- `ClassRegistry.NewEngineInstance` (ver cabeçalho do módulo, lista fechada de chamadores
	-- legítimos). O nome do campo é um resíduo do desenho de 09-04 e está errado; renome
	-- pendente (para algo como `IsNotCreatable`), adiado até a leva 3 de `services` (tipos de
	-- valor) mexer no gerador por outro motivo de qualquer jeito — ver
	-- .claude/agents-memory/arquiteto-runtime-2026-09-04.md, "Revisão pós-integração 2026-09-05
	-- (4) — `NotCreatable` vs. abstrata: dois construtores em `ClassRegistry`".
	IsAbstract: boolean,

	IsService: boolean, -- true = DataModel:GetService cria singleton sob a raiz

	-- Métodos que ESTA classe declara — nunca os herdados. Espelha como o Roblox API Dump modela
	-- herança (campo `Superclass`, sem redeclarar membro da superclasse): o gerador de `services`
	-- emite exatamente o que o dump diz, e quem achata a cadeia inteira é ClassRegistry (uma vez
	-- por classe, cache lazy no primeiro `new`) — ver resolveClassMethods abaixo. Opcional: classe
	-- sem método próprio dispensa o campo. task-runtime-016, ver arquiteto-runtime-2026-09-04.md,
	-- seção "Revisão pós-integração 2026-09-04 (3) — acesso a membro".
	Methods: InstanceModule.ClassMethods?,

	-- Schema de Property/Event/Callback que ESTA classe declara — nunca os herdados (mesmo
	-- espelhamento do campo `Superclass` do dump que `Methods` já faz, acima). Opcional: classe
	-- sem membro desse tipo dispensa o campo — instância permanece no modo LENIENTE de
	-- `Instance.luau` (sem checagem de nome desconhecido) até que algum elo da cadeia declare
	-- Schema. Achatamento em `resolveClassSchema`, abaixo (mesma disciplina de
	-- `resolveClassMethods`); instalação + semeadura de defaults (incluindo um `Signal.new()`
	-- fresco por entrada `Kind == "Event"`) em `Instance.SetClassSchema`, chamada por
	-- `ClassRegistry.new`. task-runtime-018, ver
	-- .claude/agents-memory/arquiteto-services-2026-09-05.md, "Decisão 3"/"Decisão 4"/"Decisão 6".
	Schema: InstanceModule.ClassSchema?,

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
-- Feito em `NewEngineInstance()`, não em `Register`, de propósito: `services` pode registrar
-- classes fora de ordem topológica (ex.: uma subclasse antes da sua superclasse), já que a
-- cadeia só precisa estar completa no momento em que alguém de fato instancia, não no momento
-- do registro. Termina sempre em "Instance": `SuperClassName == nil` (ou o literal "Instance",
-- aceito pelo mesmo motivo) é o contrato de "herda direto de Instance" — "Instance" nunca
-- tem/precisa de descriptor próprio aqui, é a base universal que `Instance.luau` já constrói
-- via `NewBase`.
--
-- NÍVEL 1 (o default, omitido) nos dois `error` abaixo — task-runtime-023 mudou de nível 3 para
-- nível 1 (ver .claude/agents-memory/arquiteto-runtime-2026-09-04.md, "Revisão pós-integração
-- 2026-09-05 (4) — `NotCreatable` vs. abstrata: dois construtores em `ClassRegistry`", seção
-- "Efeito colateral obrigatório"). Motivo: com o construtor separado em `ClassRegistry.new`/
-- `ClassRegistry.NewEngineInstance`, esta função passou a ser alcançada em DUAS profundidades
-- diferentes dependendo de qual das duas foi a entrada externa (`new` insere um frame de
-- wrapper a mais antes de chegar aqui do que `NewEngineInstance` insere) — nenhuma constante de
-- nível aponta para "quem chamou" corretamente nos dois casos ao mesmo tempo. São erros de
-- REGISTRO MALFORMADO (`services` registrando um ciclo, ou uma superclasse que nunca foi
-- registrada) — a posição de quem chamou `new`/`NewEngineInstance` não explica a causa, a
-- mensagem já nomeia as duas classes envolvidas (a informação acionável), e nível 1 aponta para
-- a checagem aqui dentro, IMUNE a qualquer mudança de profundidade futura — o landmine morre
-- aqui, não é adiado. Nível 0 foi considerado e descartado: descarta a posição (ainda que
-- inútil) sem ganhar nada sobre o nível 1.
local function resolveClassChain(descriptor: ClassDescriptor): { string }
	local chain: { string } = {}
	local seen: { [string]: boolean } = {}

	local currentClassName: string = descriptor.ClassName
	local currentSuperClassName: string? = descriptor.SuperClassName

	while true do
		if seen[currentClassName] then
			error(`ciclo de herança detectado na cadeia de classes envolvendo '{currentClassName}'`)
		end
		seen[currentClassName] = true
		table.insert(chain, currentClassName)

		if currentSuperClassName == nil or currentSuperClassName == "Instance" then
			break
		end

		local superDescriptor = registry[currentSuperClassName]
		if superDescriptor == nil then
			error(
				`classe '{currentClassName}' referencia superclasse '{currentSuperClassName}' não registrada em ClassRegistry`
			)
		end

		currentClassName = currentSuperClassName
		currentSuperClassName = superDescriptor.SuperClassName
	end

	table.insert(chain, "Instance")
	return chain
end

--[[
	AUDITORIA DE NÍVEL DE ERRO (task-runtime-023, mesma seção do arquiteto citada acima,
	"Auditoria obrigatória junto"): o mesmo raciocínio de profundidade-dependente foi checado
	para todo `error(..., N)` alcançável pelo caminho novo (`new`/`NewEngineInstance`).
	Resultado — nada mais precisou mudar além de `resolveClassChain`, acima:

	- `Instance.NewBase` — não tem nenhum `error()`. Fora do escopo da auditoria.
	- `resolveClassMethods`/`resolveClassSchema` (esta abaixo, a de schema mais adiante) —
	  nenhuma das duas tem `error()`; ambas só constroem a tabela achatada ou devolvem `nil`.
	  Fora do escopo.
	- `Instance.SetClassMethods`/`Instance.SetClassSchema` (Instance.luau) — têm `error(..., 2)`,
	  mas o nível 2 aponta para "quem chamou SetClassMethods/SetClassSchema". Dentro deste
	  módulo, as duas só são chamadas de dentro de `NewEngineInstance` (nunca diretamente por
	  `ClassRegistry.new`, que só delega). O frame extra que `new()` insere fica ACIMA de
	  `NewEngineInstance` na pilha, não ENTRE `NewEngineInstance` e essas duas funções — então o
	  nível 2 aponta sempre para a mesma linha (dentro de `NewEngineInstance`), não importa qual
	  das duas entradas externas foi usada. Diferente de `resolveClassChain`: o problema ali era
	  especificamente ela ser chamada de dentro de `NewEngineInstance` enquanto o PRÓPRIO
	  `NewEngineInstance` passou a ter duas profundidades possíveis vistas de fora. Nenhuma
	  mudança necessária. (CORREÇÃO task-runtime-024: `Instance.SetClassMethods` tem um SEGUNDO
	  call site real, fora deste módulo — `DataModel.luau`, construção da raiz `game` — chamado
	  diretamente, sem passar por `ClassRegistry.new`/`NewEngineInstance`. Esse call site é
	  igualmente estável e fora do escopo desta auditoria, que trata só do wrapper de `new()`;
	  citado aqui apenas para não afirmar "único ponto" quando não é.)
	- `getInternal` (Instance.luau, chamada internamente por SetClassChain/SetClassMethods/
	  SetClassSchema, nível 3) — mesmo raciocínio do item acima: chamada num único ponto fixo
	  dentro de cada uma dessas três funções, blindada do frame extra do wrapper pela mesma
	  razão. Não fazia parte da lista nomeada pelo arquiteto, mas foi conferida por completude.
	  Nenhuma mudança necessária.
]]

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

-- Cache module-local do `ClassSchema` ACHATADO (próprio + herdado) e CONGELADO por `className`,
-- construído preguiçosamente no primeiro `new()` — mesmo padrão e mesma razão já documentados
-- para `methodsCache`/`resolveClassMethods`, acima (task-runtime-016): achatamento de trás para
-- frente (classe mais concreta sobrescreve superclasse), cache por identidade de `className`.
-- `schema = nil` guardado explicitamente distingue "já resolvido, esta classe não declara schema
-- nenhum na cadeia" de "ainda não resolvido". task-runtime-018, ver
-- .claude/agents-memory/arquiteto-services-2026-09-05.md, "Decisão 6" (último parágrafo: "o
-- achatamento do schema segue a mesma disciplina já construída para Methods").
type SchemaCacheEntry = { schema: InstanceModule.ClassSchema? }
local schemaCache: { [string]: SchemaCacheEntry } = {}

local function resolveClassSchema(className: string, chain: { string }): InstanceModule.ClassSchema?
	local cached = schemaCache[className]
	if cached ~= nil then
		return cached.schema
	end

	local flattened: InstanceModule.ClassSchema = {}
	local hasAny = false

	for i = #chain, 1, -1 do
		local linkDescriptor = registry[chain[i]]
		if linkDescriptor ~= nil then
			local linkSchema = linkDescriptor.Schema
			if linkSchema ~= nil then
				hasAny = true
				for key, memberDescriptor in linkSchema do
					flattened[key] = memberDescriptor
				end
			end
		end
	end

	if not hasAny then
		schemaCache[className] = { schema = nil }
		return nil
	end

	table.freeze(flattened)
	schemaCache[className] = { schema = flattened }
	return flattened
end

-- Via do MOTOR: mesma assinatura e MESMA construção completa de `ClassRegistry.new` (abaixo),
-- SEM a guarda de `IsAbstract` — a guarda de "classe não registrada" NÃO é pulada, continua
-- valendo aqui também. Task-runtime-023, decisão do arquiteto (opção (b) refinada) — ver
-- cabeçalho do módulo para a lista fechada de chamadores legítimos. Corpo idêntico ao que
-- `ClassRegistry.new` tinha antes desta tarefa — só mudou de lugar, ordem preservada
-- integralmente (resolver -> NewBase -> SetClassChain -> SetClassMethods -> SetClassSchema ->
-- Initialize continua sendo a ordem load-bearing documentada em três lugares).
function ClassRegistry.NewEngineInstance(className: string, name: string?): Instance
	local descriptor = registry[className]
	if descriptor == nil then
		error(`classe '{className}' não registrada`, 2)
	end

	-- Ordem obrigatória (task-runtime-013 fixou resolver->NewBase->SetClassChain->Initialize;
	-- task-runtime-016 insere SetClassMethods entre SetClassChain e Initialize; task-runtime-018
	-- insere SetClassSchema entre SetClassMethods e Initialize — mesma razão em todos os casos:
	-- a identidade de classe precisa estar COMPLETA antes de qualquer código de `services`
	-- rodar, para que dentro do próprio Initialize tanto `instance:IsA(ancestral)` quanto
	-- `instance:MetodoDaPropriaClasse()` quanto uma leitura/escrita de propriedade do schema já
	-- funcionem. ClassName/identidade da tabela/default de Name ficam garantidos aqui, não
	-- confiados a cada uma das dezenas de classes geradas). Ordem final fechada em
	-- .claude/agents-memory/arquiteto-services-2026-09-05.md, "Decisão 4": resolver -> NewBase ->
	-- SetClassChain -> SetClassMethods -> SetClassSchema -> Initialize.
	local chain = resolveClassChain(descriptor)
	local instance = InstanceModule.NewBase(className, name)
	InstanceModule.SetClassChain(instance, chain)

	local methods = resolveClassMethods(className, chain)
	if methods ~= nil then
		InstanceModule.SetClassMethods(instance, methods)
	end

	-- SetClassSchema, quando chamada, também semeia os defaults desta instância (incluindo um
	-- Signal.new() fresco por entrada Kind == "Event") direto no storage interno — ver comentário
	-- de Instance.SetClassSchema para o porquê disso rodar ali e não aqui.
	local schema = resolveClassSchema(className, chain)
	if schema ~= nil then
		InstanceModule.SetClassSchema(instance, schema)
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

-- Via PÚBLICA, com a política de `NotCreatable`: rejeita `descriptor.IsAbstract` (script não
-- pode criar isto — o Roblox real também erra: `Instance.new("Workspace")` estoura) e delega o
-- resto para `NewEngineInstance`, acima. O lookup de `registry[className]` é feito aqui de novo
-- (duplicado em relação ao que `NewEngineInstance` já faz) DE PROPÓSITO — mantém
-- `NewEngineInstance` autossuficiente/chamável direto sem depender de um wrapper já ter
-- validado o registro; não é duplicação acidental, revisor não precisa sinalizar.
function ClassRegistry.new(className: string, name: string?): Instance
	local descriptor = registry[className]
	if descriptor == nil then
		error(`classe '{className}' não registrada`, 2)
	end
	if descriptor.IsAbstract then
		error(
			`classe '{className}' não é criável por script (tag NotCreatable do Roblox API Dump); construção interna do motor usa ClassRegistry.NewEngineInstance`,
			2
		)
	end

	return ClassRegistry.NewEngineInstance(className, name)
end

return ClassRegistry
