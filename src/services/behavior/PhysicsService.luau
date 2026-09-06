--!strict

--[[
	Behavior de `PhysicsService` -- task-services-023. LER
	.claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.5 -- Grupo 4", subseção
	"L2.5.1", e .claude/agents-memory/pesquisa-services-leva2-pendencias-2026-09-05.md, item 3,
	ANTES de mexer aqui -- o desenho abaixo segue as duas ao pé da letra. Ver `./WorldRoot.luau`
	para o achado completo ("os grupos de colisão pertencem ao `WorldRoot`, não ao `PhysicsService`")
	-- este arquivo é a METADE "vista legada" daquele desenho.

	`PhysicsService` é `Instance`-direto no dump (`Superclass: "Instance"`, confirmado por leitura
	direta de `.cache/api-dump/28360dea....json`, `Classes[].Name == "PhysicsService"`), 15 funções
	(zero propriedades, zero eventos sobreviventes ao filtro de Security -- `IkSolve`/`LocalIkSolve`
	são `RobloxScriptSecurity`/`LocalUserSecurity`, excluídos pelo gerador; `CollisionGroupCollidableChanged`
	é `RobloxSecurity`+`Hidden`, idem): "o Grupo 4 com maior retorno e nenhuma aproximação -- zero
	propriedades, quinze funções, tudo dado puro" (citação do arquiteto, L2.5.1). NENHUMA física é
	simulada aqui -- grupo de colisão é bookkeeping puro, e o LuauBench o reproduz EXATAMENTE (mesma
	garantia de `../CollisionGroups.luau`).

	DELEGAÇÃO, NÃO DUPLICAÇÃO: os 8 métodos não-Deprecated (`RegisterCollisionGroup`,
	`UnregisterCollisionGroup`, `IsCollisionGroupRegistered`, `RenameCollisionGroup`,
	`GetRegisteredCollisionGroups`, `GetMaxCollisionGroups`, `CollisionGroupSetCollidable`,
	`CollisionGroupsAreCollidable`) são idênticos, byte a byte do dump, aos oito de `WorldRoot` --
	mesmos nomes, mesma assinatura, mesma `Capability ["Physics"]`. Este módulo NUNCA cria seu
	próprio `CollisionGroups.Registry`: alcança o da instância de `Workspace` corrente via
	`Context.GetDataModel():GetService("Workspace")` + `WorldRoot.GetRegistry(workspaceInstance)`
	(a MESMA função get-or-create que `./WorldRoot.luau` usa internamente, reexportada por ela --
	ver o cabeçalho dela). É isto que garante `PhysicsService:RegisterCollisionGroup("X")` seguido
	de `workspace:IsCollisionGroupRegistered("X")` devolver `true`, como no Roblox real (uma verdade
	só -- escrever um segundo registro aqui inverteria a relação real, exatamente o erro que o
	achado de L2.5.1 avisa para não cometer).

	Nenhuma mensagem de erro/regra de negócio (nome "Default" reservado, limite de 32, restrição
	cliente/servidor de `Unregister`/`Rename`) é reimplementada ou duplicada aqui -- tudo isso mora
	uma vez só em `../CollisionGroups.luau` (chamado através de `WorldRoot.GetRegistry(...)`), para
	que `PhysicsService`/`WorldRoot` nunca possam divergir um do outro por acidente de manutenção.

	7 MÉTODOS DEPRECATED (sinalizado no relatório da tarefa, regra 03: "Propriedade marcada como
	Deprecated no dump é implementada só se algum projeto real ainda depender dela") -- ficam com o
	stub `[LuauBench] ... not simulated by LuauBench yet` do `ClassBuilder`, DE PROPÓSITO, nunca
	implementados às cegas:
	- `CreateCollisionGroup`/`GetCollisionGroupId`/`GetCollisionGroupName`/`GetCollisionGroups`/
	  `RemoveCollisionGroup` -- expõem o modelo de ID NUMÉRICO de grupo de colisão que o Roblox
	  moderno abandonou (`PreferredDescriptorName` no dump aponta todos para o nome moderno
	  correspondente) -- reimplementar o esquema de id seria simular um modelo que o próprio Roblox
	  já descontinuou, sem nenhum consumidor real esperado (`ProfileStore`/data managers nunca usam
	  isto).
	- `SetPartCollisionGroup`/`CollisionGroupContainsPart` -- dependem de `BasePart`, classe NÃO
	  coberta por nenhuma leva de `services` até esta tarefa (fora do escopo: árvore Rojo +
	  DataStoreService + HttpService/MessagingService + Grupo 4 mínimo, regra 03) -- implementá-los
	  exigiria simular parte da hierarquia de `BasePart`/física, o que a regra 03 explicitamente
	  não pede para o Grupo 4 ("cobertura mínima de API, comportamento simplificado e documentado").

	Depende de `../../runtime` (tipo `Instance`), `../Types` (`Types.Behavior`), `../Context`
	(`Context.GetDataModel()`) e `./WorldRoot` (`WorldRoot.GetRegistry`, ver cabeçalho dela). Usado
	por `./Index.luau` (registro em `BehaviorIndex.PhysicsService`).
]]

local Runtime = require("../../runtime")
local Types = require("../Types")
local Context = require("../Context")
local CollisionGroups = require("../CollisionGroups")
local WorldRootBehavior = require("./WorldRoot")

-- Alcança o `Registry` da instância de `Workspace` CORRENTE -- nunca cria um `Registry` próprio
-- (ver cabeçalho, "DELEGAÇÃO, NÃO DUPLICAÇÃO"). `game:GetService("Workspace")` nunca deveria
-- devolver `nil` nesta altura (invariante interna: `Workspace` é Service coberto desde a leva 1,
-- sempre registrado em `Runtime.ClassRegistry` -- ver `../init.luau`) -- o erro abaixo é
-- `[LuauBench]`/interno, não um erro real do Roblox, porque não tem contraparte: no Roblox de
-- verdade não existe um estado em que `PhysicsService` exista sem `Workspace` existir também.
local function getWorkspaceRegistry(): CollisionGroups.Registry
	local workspaceInstance = Context.GetDataModel():GetService("Workspace")
	if workspaceInstance == nil then
		error(
			"[LuauBench] PhysicsService: game:GetService('Workspace') devolveu nil -- Workspace deveria estar sempre coberta por services e registrada como Service nesta altura do pipeline; invariante interna quebrada, não um erro esperado de projeto do usuário",
			2
		)
	end
	return WorldRootBehavior.GetRegistry(workspaceInstance)
end

-- Anotação explícita de `{ [string]: unknown }` -- mesmo padrão de `RunService.luau`/`WorldRoot.luau`.
local Methods: { [string]: unknown } = {
	RegisterCollisionGroup = function(_self: Runtime.Instance, name: string): ()
		getWorkspaceRegistry():Register(name)
	end,

	-- Restrição cliente/servidor CONFIRMADA oficialmente para este método -- ver
	-- `../CollisionGroups.luau`, cabeçalho, "NÃO CONFIRMADO" -> restrição cliente/servidor.
	UnregisterCollisionGroup = function(_self: Runtime.Instance, name: string): ()
		getWorkspaceRegistry():Unregister(name)
	end,

	IsCollisionGroupRegistered = function(_self: Runtime.Instance, name: string): boolean
		return getWorkspaceRegistry():IsRegistered(name)
	end,

	-- Restrição cliente/servidor CONFIRMADA oficialmente para este método -- mesma nota acima.
	RenameCollisionGroup = function(_self: Runtime.Instance, from: string, to: string): ()
		getWorkspaceRegistry():Rename(from, to)
	end,

	-- Formato do elemento -- `{ Name: string }` -- mesma DIVERGÊNCIA DECLARADA de
	-- `./WorldRoot.luau` (ver o cabeçalho dela e o de `../CollisionGroups.luau`).
	GetRegisteredCollisionGroups = function(_self: Runtime.Instance): { { Name: string } }
		local names = getWorkspaceRegistry():GetRegisteredNames()
		local result = table.create(#names)
		for index, name in names do
			result[index] = { Name = name }
		end
		return result
	end,

	GetMaxCollisionGroups = function(_self: Runtime.Instance): number
		return getWorkspaceRegistry():GetMax()
	end,

	CollisionGroupSetCollidable = function(_self: Runtime.Instance, name1: string, name2: string, collidable: boolean): ()
		getWorkspaceRegistry():SetCollidable(name1, name2, collidable)
	end,

	CollisionGroupsAreCollidable = function(_self: Runtime.Instance, name1: string, name2: string): boolean
		return getWorkspaceRegistry():AreCollidable(name1, name2)
	end,
}

local PhysicsServiceBehavior: Types.Behavior = {
	Methods = Methods,
}

return PhysicsServiceBehavior
