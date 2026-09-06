--!strict

--[[
	Behavior de `WorldRoot` -- task-services-023. LER
	.claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.5 -- Grupo 4", subseção
	"L2.5.1 -- Achado: os grupos de colisão pertencem ao `WorldRoot`, não ao `PhysicsService`", e
	.claude/agents-memory/pesquisa-services-leva2-pendencias-2026-09-05.md, item 3, ANTES de mexer
	aqui -- o desenho abaixo segue as duas ao pé da letra.

	ACHADO QUE DEFINE ESTE ARQUIVO: `WorldRoot` (superclasse de `Workspace`, já gerada na leva 1)
	declara sua PRÓPRIA cópia scriptável dos oito métodos de grupo de colisão -- ver
	`../generated/classes/WorldRoot.luau`, `MethodNames` -- todos `Security None`,
	`Capabilities ["Physics"]` (concedível, já em `tools/capabilities.lock.json`), escopados POR
	INSTÂNCIA DE MUNDO. A doc oficial já marca os homônimos de `PhysicsService` como *superseded by
	WorldRoot*. Este `Behavior`, portanto, é o DONO do estado (o registro de grupos de colisão) --
	`behavior/PhysicsService.luau` é a vista LEGADA que delega para cá (`WorldRoot.GetRegistry`,
	exportado abaixo), nunca o contrário.

	É A PRIMEIRA VEZ QUE `Workspace` GANHA COMPORTAMENTO DE VERDADE (até task-services-023, `Workspace`
	não tinha entrada em `behavior/Index.luau`).

	MECANISMO -- por que NÃO tem `Initialize`: `Runtime.ClassRegistry.NewEngineInstance`/`.new` só
	chamam `descriptor.Initialize` do `ClassDescriptor` da classe EXATA sendo construída
	(`registry[className]`, className == "Workspace" na prática -- confirmado por leitura direta de
	`src/runtime/ClassRegistry.luau`, `NewEngineInstance`) -- NUNCA o `Initialize` de uma
	superclasse no meio da cadeia. Um `Initialize` escrito aqui, em `WorldRoot`, NUNCA rodaria para
	uma instância real de `Workspace` (só `Methods`/`Schema` são ACHATADOS pela cadeia inteira --
	`resolveClassMethods`/`resolveClassSchema`, mesmo módulo -- `Initialize` não é). Por isso o
	registro de colisão é criado PREGUIÇOSAMENTE, na primeira chamada de qualquer um dos oito
	métodos, via `InstanceState` (mesmo padrão documentado no cabeçalho de `../InstanceState.luau`,
	que já cita `WorldRoot` como consumidor previsto) -- `getRegistry`, abaixo. Isto também torna o
	mecanismo correto para QUALQUER classe futura que venha a herdar de `WorldRoot` (hoje só
	`Workspace`), sem precisar de um `Initialize` por classe concreta.

	COMPORTAMENTO (o "como", à mão -- o dump só deu o "o quê"): toda a lógica de negócio (nome
	reservado "Default", limite de 32, matriz de colidibilidade par a par, idempotência de
	registro/remoção duplicados) mora em `../CollisionGroups.luau` (dado puro, sem `Instance`) --
	este módulo só faz a PONTE entre a Instance simulada e aquele registro: cria/recupera o
	`Registry` por instância e traduz cada `Method` do dump numa chamada nele. Nenhuma decisão de
	negócio é tomada aqui -- ver o cabeçalho de `../CollisionGroups.luau` para as decisões
	confirmadas/não confirmadas (nome duplicado, restrição cliente/servidor, formato de
	`GetRegisteredCollisionGroups`).

	Os demais 18 métodos que sobram em `MethodNames` de `WorldRoot` (`Raycast`/`Blockcast`/
	`FindPartsInRegion3`/etc. -- física/geometria real, fora do escopo desta tarefa e da regra 03,
	"Services físicos/render: cobertura mínima") ficam SEM `Methods` aqui de propósito:
	`ClassBuilder.Build` já completa qualquer `MethodNames` sem implementação com o stub
	`[LuauBench] ... not simulated by LuauBench yet` (regra 03) -- nenhum deles tem comportamento
	definido por esta tarefa.

	Depende de `../../runtime` (tipo `Instance`), `../InstanceState` (estado privado por instância)
	e `../CollisionGroups` (o registro em si) -- NUNCA de `../Types` diretamente: o módulo devolve
	`{ Methods, GetRegistry }`, mais do que `Types.Behavior` declara (só `Methods`/`Initialize`), e
	é `./Index.luau` quem faz o downcast (`require("./WorldRoot") :: Types.Behavior`) -- mesmo
	padrão e mesma razão de `./DataStoreKeyInfo.luau`/`./GlobalDataStore.luau` (ver os cabeçalhos
	deles). Usado por `./Index.luau` (registro em `BehaviorIndex.WorldRoot`) e por
	`./PhysicsService.luau` (via `WorldRoot.GetRegistry`, exportado além do contrato).
]]

local Runtime = require("../../runtime")
local InstanceState = require("../InstanceState")
local CollisionGroups = require("../CollisionGroups")

local RegistryState = InstanceState.new("_LuauBenchCollisionGroups")
	:: InstanceState.InstanceStateAccessor<CollisionGroups.Registry>

-- Get-or-create preguiçoso -- ver cabeçalho, "MECANISMO", para o porquê de não haver `Initialize`.
-- Exportado (ver `return` no fim do arquivo) para `./PhysicsService.luau` alcançar o MESMO
-- `Registry` de uma instância de `Workspace` sem duplicar este mecanismo.
local function getRegistry(instance: Runtime.Instance): CollisionGroups.Registry
	local existing = RegistryState.Get(instance)
	if existing ~= nil then
		return existing
	end

	local created = CollisionGroups.new()
	RegistryState.Set(instance, created)
	return created
end

-- Anotação explícita de `{ [string]: unknown }` -- mesmo padrão de `RunService.luau`/`Lighting.luau`.
local Methods: { [string]: unknown } = {
	RegisterCollisionGroup = function(self: Runtime.Instance, name: string): ()
		getRegistry(self):Register(name)
	end,

	-- Restrição cliente/servidor CONFIRMADA oficialmente para este método (pesquisa item 3) --
	-- NUNCA observável no LuauBench, que sempre se apresenta como servidor (ver cabeçalho de
	-- `../CollisionGroups.luau`, "NÃO CONFIRMADO" -> restrição cliente/servidor, para a
	-- justificativa completa de por que isto NÃO vira um branch condicional morto aqui).
	UnregisterCollisionGroup = function(self: Runtime.Instance, name: string): ()
		getRegistry(self):Unregister(name)
	end,

	IsCollisionGroupRegistered = function(self: Runtime.Instance, name: string): boolean
		return getRegistry(self):IsRegistered(name)
	end,

	-- Restrição cliente/servidor CONFIRMADA oficialmente para este método -- mesma nota de
	-- `UnregisterCollisionGroup`, acima.
	RenameCollisionGroup = function(self: Runtime.Instance, from: string, to: string): ()
		getRegistry(self):Rename(from, to)
	end,

	-- Formato do elemento -- `{ Name: string }` -- é uma DIVERGÊNCIA DECLARADA quanto a um possível
	-- campo `Mask`/id numérico do Roblox real, ver cabeçalho de `../CollisionGroups.luau`,
	-- "DIVERGÊNCIA DECLARADA".
	GetRegisteredCollisionGroups = function(self: Runtime.Instance): { { Name: string } }
		local names = getRegistry(self):GetRegisteredNames()
		local result = table.create(#names)
		for index, name in names do
			result[index] = { Name = name }
		end
		return result
	end,

	GetMaxCollisionGroups = function(self: Runtime.Instance): number
		return getRegistry(self):GetMax()
	end,

	CollisionGroupSetCollidable = function(self: Runtime.Instance, name1: string, name2: string, collidable: boolean): ()
		getRegistry(self):SetCollidable(name1, name2, collidable)
	end,

	CollisionGroupsAreCollidable = function(self: Runtime.Instance, name1: string, name2: string): boolean
		return getRegistry(self):AreCollidable(name1, name2)
	end,
}

local WorldRootBehavior = {
	Methods = Methods,

	-- Exportado ALÉM do contrato `Types.Behavior` -- mesmo padrão de `./GlobalDataStore.luau`
	-- (`StoreIdState`)/`./DataStoreKeyInfo.luau`: `behavior/Index.luau` faz
	-- `require("./WorldRoot") :: Types.Behavior` (downcast seguro, descarta este campo extra);
	-- `./PhysicsService.luau` faz `require("./WorldRoot")` SEM cast para alcançar `.GetRegistry`.
	GetRegistry = getRegistry,
}

return WorldRootBehavior
