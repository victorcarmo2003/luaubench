--!strict

--[[
	Teste dedicado de `./PhysicsService.luau` (regra 01: teste na mesma tarefa da lógica que cobre)
	-- task-services-023. `./WorldRoot.spec.luau` já cobre a lógica de negócio de cada método (nome
	reservado, limite de 32, matriz de colidibilidade) via `Workspace`; este arquivo cobre a
	DELEGAÇÃO: `PhysicsService` nunca tem estado próprio, sempre enxerga o MESMO `Registry` da
	instância de `Workspace` corrente (`Context.GetDataModel():GetService("Workspace")`) -- acceptance
	da tarefa: "PhysicsService e workspace compartilham o MESMO registro (spec cruzada nos dois
	sentidos)".

	Roda com `lune run src/services/behavior/PhysicsService.spec.luau`.
]]

local process = require("@lune/process")
local Runtime = require("../../runtime")
local Services = require("../")

type Dynamic = { [string]: unknown }

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

Services.Register()

-- Monta, num MESMO Bootstrap (mesmo `game`, mesmo Context corrente), tanto `PhysicsService`
-- quanto `Workspace` -- mesmo padrão de `./RunService.spec.luau` (retorna as duas peças que o
-- teste precisa cruzar).
local function makePhysicsServiceAndWorkspace(): (Dynamic, Dynamic)
	local scheduler = Runtime.Scheduler.new()
	local game = Runtime.DataModel.new()
	Services.Bootstrap({ scheduler = scheduler, dataModel = game })
	local physicsService = (game:GetService("PhysicsService") :: unknown) :: Dynamic
	local workspaceInstance = (game:GetService("Workspace") :: unknown) :: Dynamic
	return physicsService, workspaceInstance
end

test("game:GetService('PhysicsService') devolve uma instância -- singleton do processo (Service, NotCreatable)", function()
	local physicsService = (makePhysicsServiceAndWorkspace())
	assert(physicsService ~= nil, "PhysicsService deveria existir depois de Bootstrap")
	local instance = (physicsService :: unknown) :: Runtime.Instance
	assert(instance.ClassName == "PhysicsService", `ClassName deveria ser PhysicsService, recebeu {instance.ClassName}`)
end)

test("PhysicsService:GetMaxCollisionGroups() == 32 -- mesmo valor de Workspace", function()
	local physicsService = (makePhysicsServiceAndWorkspace())
	local getMax = physicsService.GetMaxCollisionGroups :: (self: Dynamic) -> number
	assert(getMax(physicsService) == 32, `GetMaxCollisionGroups() deveria ser 32, recebeu {getMax(physicsService)}`)
end)

test("PhysicsService:IsCollisionGroupRegistered('Default') == true -- vê o MESMO 'Default' pré-registrado de Workspace", function()
	local physicsService = (makePhysicsServiceAndWorkspace())
	local isCollisionGroupRegistered = physicsService.IsCollisionGroupRegistered :: (self: Dynamic, name: string) -> boolean
	assert(isCollisionGroupRegistered(physicsService, "Default"), "'Default' deveria estar registrado, herdado do registro de Workspace")
end)

test("SENTIDO 1: PhysicsService:RegisterCollisionGroup(X) -> workspace:IsCollisionGroupRegistered(X) == true", function()
	local physicsService, workspaceInstance = makePhysicsServiceAndWorkspace()
	local registerViaPhysics = physicsService.RegisterCollisionGroup :: (self: Dynamic, name: string) -> ()
	local isRegisteredViaWorkspace = workspaceInstance.IsCollisionGroupRegistered :: (self: Dynamic, name: string) -> boolean

	registerViaPhysics(physicsService, "RegistradoViaPhysics")
	assert(
		isRegisteredViaWorkspace(workspaceInstance, "RegistradoViaPhysics"),
		"um grupo registrado via PhysicsService deveria aparecer em workspace:IsCollisionGroupRegistered -- MESMO registro (acceptance da tarefa)"
	)
end)

test("SENTIDO 2: workspace:RegisterCollisionGroup(Y) -> PhysicsService:IsCollisionGroupRegistered(Y) == true", function()
	local physicsService, workspaceInstance = makePhysicsServiceAndWorkspace()
	local registerViaWorkspace = workspaceInstance.RegisterCollisionGroup :: (self: Dynamic, name: string) -> ()
	local isRegisteredViaPhysics = physicsService.IsCollisionGroupRegistered :: (self: Dynamic, name: string) -> boolean

	registerViaWorkspace(workspaceInstance, "RegistradoViaWorkspace")
	assert(
		isRegisteredViaPhysics(physicsService, "RegistradoViaWorkspace"),
		"um grupo registrado via workspace deveria aparecer em PhysicsService:IsCollisionGroupRegistered -- MESMO registro (acceptance da tarefa)"
	)
end)

test("CollisionGroupSetCollidable via PhysicsService é visível via CollisionGroupsAreCollidable de Workspace, e vice-versa", function()
	local physicsService, workspaceInstance = makePhysicsServiceAndWorkspace()
	local registerViaPhysics = physicsService.RegisterCollisionGroup :: (self: Dynamic, name: string) -> ()
	local setCollidableViaPhysics = physicsService.CollisionGroupSetCollidable :: (self: Dynamic, name1: string, name2: string, collidable: boolean) -> ()
	local areCollidableViaWorkspace = workspaceInstance.CollisionGroupsAreCollidable :: (self: Dynamic, name1: string, name2: string) -> boolean
	local setCollidableViaWorkspace = workspaceInstance.CollisionGroupSetCollidable :: (self: Dynamic, name1: string, name2: string, collidable: boolean) -> ()
	local areCollidableViaPhysics = physicsService.CollisionGroupsAreCollidable :: (self: Dynamic, name1: string, name2: string) -> boolean

	registerViaPhysics(physicsService, "A")
	registerViaPhysics(physicsService, "B")

	setCollidableViaPhysics(physicsService, "A", "B", false)
	assert(not areCollidableViaWorkspace(workspaceInstance, "A", "B"), "desligar a colisão via PhysicsService deveria refletir em workspace:CollisionGroupsAreCollidable")

	setCollidableViaWorkspace(workspaceInstance, "A", "B", true)
	assert(areCollidableViaPhysics(physicsService, "A", "B"), "religar a colisão via workspace deveria refletir em PhysicsService:CollisionGroupsAreCollidable")
end)

test("PhysicsService:UnregisterCollisionGroup/RenameCollisionGroup delegam corretamente (mesma família de erro para 'Default')", function()
	local physicsService = (makePhysicsServiceAndWorkspace())
	local unregister = physicsService.UnregisterCollisionGroup :: (self: Dynamic, name: string) -> ()
	local rename = physicsService.RenameCollisionGroup :: (self: Dynamic, from: string, to: string) -> ()

	local okUnregister, errUnregister = pcall(function()
		unregister(physicsService, "Default")
	end)
	assert(not okUnregister, "UnregisterCollisionGroup('Default') via PhysicsService deveria erro")
	assert(string.find(tostring(errUnregister), "Default", 1, true) ~= nil, `mensagem deveria citar 'Default', recebeu: {errUnregister}`)

	local okRename, errRename = pcall(function()
		rename(physicsService, "Default", "Outro")
	end)
	assert(not okRename, "RenameCollisionGroup('Default', ...) via PhysicsService deveria erro")
	assert(string.find(tostring(errRename), "Default", 1, true) ~= nil, `mensagem deveria citar 'Default', recebeu: {errRename}`)
end)

test("PhysicsService:GetRegisteredCollisionGroups() devolve a MESMA lista que workspace:GetRegisteredCollisionGroups()", function()
	local physicsService, workspaceInstance = makePhysicsServiceAndWorkspace()
	local registerViaPhysics = physicsService.RegisterCollisionGroup :: (self: Dynamic, name: string) -> ()
	local getViaPhysics = physicsService.GetRegisteredCollisionGroups :: (self: Dynamic) -> { { Name: string } }
	local getViaWorkspace = workspaceInstance.GetRegisteredCollisionGroups :: (self: Dynamic) -> { { Name: string } }

	registerViaPhysics(physicsService, "Players")

	local fromPhysics = getViaPhysics(physicsService)
	local fromWorkspace = getViaWorkspace(workspaceInstance)
	assert(#fromPhysics == #fromWorkspace, `as duas listas deveriam ter o mesmo tamanho, recebeu {#fromPhysics} vs {#fromWorkspace}`)
	for index, entry in fromPhysics do
		assert(entry.Name == fromWorkspace[index].Name, `entrada {index} deveria bater: '{entry.Name}' vs '{fromWorkspace[index].Name}'`)
	end
end)

-- ================= 7 métodos Deprecated -- stub `[LuauBench]`, de propósito (regra 03) =================

local deprecatedMethodNames: { string } = {
	"CreateCollisionGroup",
	"GetCollisionGroupId",
	"GetCollisionGroupName",
	"GetCollisionGroups",
	"RemoveCollisionGroup",
	"SetPartCollisionGroup",
	"CollisionGroupContainsPart",
}

for _, methodName in deprecatedMethodNames do
	test(`PhysicsService:{methodName}() (Deprecated) ERRA com o stub [LuauBench] do ClassBuilder -- não implementado nesta tarefa`, function()
		local physicsService = (makePhysicsServiceAndWorkspace())
		local method = physicsService[methodName] :: (...unknown) -> ...unknown

		local ok, err = pcall(function()
			return method(physicsService, "qualquer")
		end)
		assert(not ok, `PhysicsService:{methodName}() deveria erro -- Deprecated, fora do escopo desta tarefa`)
		local message = tostring(err)
		assert(
			string.find(message, "[LuauBench]", 1, true) ~= nil,
			`mensagem deveria trazer o prefixo [LuauBench] (stub do ClassBuilder, regra 03), recebeu: {message}`
		)
		assert(
			string.find(message, "not simulated by LuauBench yet", 1, true) ~= nil,
			`mensagem deveria trazer "not simulated by LuauBench yet", recebeu: {message}`
		)
	end)
end

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
