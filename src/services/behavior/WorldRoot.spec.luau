--!strict

--[[
	Teste dedicado de `./WorldRoot.luau` (regra 01: teste na mesma tarefa da lógica que cobre) --
	task-services-023. Cobre os oito métodos de grupo de colisão alcançados via
	`game:GetService("Workspace")` -- a lógica de negócio em si (nome reservado, limite de 32,
	idempotência, matriz de colidibilidade) já está coberta em `../CollisionGroups.spec.luau`; este
	arquivo cobre a PONTE (Instance real, estado por instância, ausência de Initialize).

	`./PhysicsService.spec.luau` cobre a delegação cruzada (`PhysicsService` <-> `Workspace`
	enxergando o MESMO registro) -- não duplicada aqui.

	Roda com `lune run src/services/behavior/WorldRoot.spec.luau`.
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

-- Monta um `Workspace` de verdade, via o caminho de produção inteiro (Bootstrap + GetService) --
-- mesmo padrão de `./RunService.spec.luau`/`./HttpService.spec.luau`.
local function makeWorkspace(): Dynamic
	local scheduler = Runtime.Scheduler.new()
	local game = Runtime.DataModel.new()
	Services.Bootstrap({ scheduler = scheduler, dataModel = game })
	return (game:GetService("Workspace") :: unknown) :: Dynamic
end

test("game:GetService('Workspace') devolve uma instância -- singleton do processo (Service)", function()
	local workspaceInstance = makeWorkspace()
	assert(workspaceInstance ~= nil, "Workspace deveria existir depois de Bootstrap")
	local instance = (workspaceInstance :: unknown) :: Runtime.Instance
	assert(instance.ClassName == "Workspace", `ClassName deveria ser Workspace, recebeu {instance.ClassName}`)
end)

test("'Default' já vem registrado em workspace:IsCollisionGroupRegistered", function()
	local workspaceInstance = makeWorkspace()
	local isCollisionGroupRegistered = workspaceInstance.IsCollisionGroupRegistered :: (self: Dynamic, name: string) -> boolean
	assert(isCollisionGroupRegistered(workspaceInstance, "Default"), "'Default' deveria estar registrado desde o início, sem nenhuma chamada de Register")
end)

test("workspace:GetMaxCollisionGroups() == 32", function()
	local workspaceInstance = makeWorkspace()
	local getMax = workspaceInstance.GetMaxCollisionGroups :: (self: Dynamic) -> number
	assert(getMax(workspaceInstance) == 32, `GetMaxCollisionGroups() deveria ser 32, recebeu {getMax(workspaceInstance)}`)
end)

test("workspace:RegisterCollisionGroup + IsCollisionGroupRegistered funcionam de ponta a ponta", function()
	local workspaceInstance = makeWorkspace()
	local register = workspaceInstance.RegisterCollisionGroup :: (self: Dynamic, name: string) -> ()
	local isCollisionGroupRegistered = workspaceInstance.IsCollisionGroupRegistered :: (self: Dynamic, name: string) -> boolean

	assert(not isCollisionGroupRegistered(workspaceInstance, "Players"), "Players não deveria estar registrado antes do Register")
	register(workspaceInstance, "Players")
	assert(isCollisionGroupRegistered(workspaceInstance, "Players"), "Players deveria estar registrado depois do Register")
end)

test("dois grupos recém-registrados via workspace colidem por padrão (CollisionGroupsAreCollidable)", function()
	local workspaceInstance = makeWorkspace()
	local register = workspaceInstance.RegisterCollisionGroup :: (self: Dynamic, name: string) -> ()
	local areCollidable = workspaceInstance.CollisionGroupsAreCollidable :: (self: Dynamic, name1: string, name2: string) -> boolean

	register(workspaceInstance, "A")
	register(workspaceInstance, "B")
	assert(areCollidable(workspaceInstance, "A", "B"), "A e B deveriam colidir por padrão")
end)

test("workspace:CollisionGroupSetCollidable desliga a colisão, refletido em CollisionGroupsAreCollidable", function()
	local workspaceInstance = makeWorkspace()
	local register = workspaceInstance.RegisterCollisionGroup :: (self: Dynamic, name: string) -> ()
	local setCollidable = workspaceInstance.CollisionGroupSetCollidable :: (self: Dynamic, name1: string, name2: string, collidable: boolean) -> ()
	local areCollidable = workspaceInstance.CollisionGroupsAreCollidable :: (self: Dynamic, name1: string, name2: string) -> boolean

	register(workspaceInstance, "A")
	register(workspaceInstance, "B")
	setCollidable(workspaceInstance, "A", "B", false)
	assert(not areCollidable(workspaceInstance, "A", "B"), "A e B não deveriam mais colidir")
	assert(not areCollidable(workspaceInstance, "B", "A"), "a colidibilidade é simétrica")
end)

test("workspace:UnregisterCollisionGroup remove o grupo -- IsCollisionGroupRegistered vira false", function()
	local workspaceInstance = makeWorkspace()
	local register = workspaceInstance.RegisterCollisionGroup :: (self: Dynamic, name: string) -> ()
	local unregister = workspaceInstance.UnregisterCollisionGroup :: (self: Dynamic, name: string) -> ()
	local isCollisionGroupRegistered = workspaceInstance.IsCollisionGroupRegistered :: (self: Dynamic, name: string) -> boolean

	register(workspaceInstance, "Temporario")
	unregister(workspaceInstance, "Temporario")
	assert(not isCollisionGroupRegistered(workspaceInstance, "Temporario"), "Temporario não deveria mais estar registrado")
end)

test("workspace:UnregisterCollisionGroup('Default') ERRA -- reservado", function()
	local workspaceInstance = makeWorkspace()
	local unregister = workspaceInstance.UnregisterCollisionGroup :: (self: Dynamic, name: string) -> ()

	local ok, err = pcall(function()
		unregister(workspaceInstance, "Default")
	end)
	assert(not ok, "UnregisterCollisionGroup('Default') deveria erro")
	assert(string.find(tostring(err), "Default", 1, true) ~= nil, `mensagem deveria citar 'Default', recebeu: {err}`)
end)

test("workspace:RenameCollisionGroup funciona de ponta a ponta", function()
	local workspaceInstance = makeWorkspace()
	local register = workspaceInstance.RegisterCollisionGroup :: (self: Dynamic, name: string) -> ()
	local rename = workspaceInstance.RenameCollisionGroup :: (self: Dynamic, from: string, to: string) -> ()
	local isCollisionGroupRegistered = workspaceInstance.IsCollisionGroupRegistered :: (self: Dynamic, name: string) -> boolean

	register(workspaceInstance, "Velho")
	rename(workspaceInstance, "Velho", "Novo")
	assert(not isCollisionGroupRegistered(workspaceInstance, "Velho"), "'Velho' não deveria mais estar registrado")
	assert(isCollisionGroupRegistered(workspaceInstance, "Novo"), "'Novo' deveria estar registrado")
end)

test("workspace:RegisterCollisionGroup('Default') ERRA", function()
	local workspaceInstance = makeWorkspace()
	local register = workspaceInstance.RegisterCollisionGroup :: (self: Dynamic, name: string) -> ()

	local ok, err = pcall(function()
		register(workspaceInstance, "Default")
	end)
	assert(not ok, "RegisterCollisionGroup('Default') deveria erro")
	assert(string.find(tostring(err), "Default", 1, true) ~= nil, `mensagem deveria citar 'Default', recebeu: {err}`)
end)

test("workspace:GetRegisteredCollisionGroups() inclui 'Default' e os grupos registrados, cada um como { Name: string }", function()
	local workspaceInstance = makeWorkspace()
	local register = workspaceInstance.RegisterCollisionGroup :: (self: Dynamic, name: string) -> ()
	local getRegistered = workspaceInstance.GetRegisteredCollisionGroups :: (self: Dynamic) -> { { Name: string } }

	register(workspaceInstance, "Players")
	local groups = getRegistered(workspaceInstance)
	assert(#groups == 2, `esperava 2 entradas (Default + Players), recebeu {#groups}`)
	assert(groups[1].Name == "Default", `primeira entrada deveria ser 'Default', recebeu '{groups[1].Name}'`)
	assert(groups[2].Name == "Players", `segunda entrada deveria ser 'Players', recebeu '{groups[2].Name}'`)
end)

test("DUAS instâncias de Workspace (Bootstrap diferentes) têm registros de colisão ISOLADOS -- estado por INSTÂNCIA, nunca module-global", function()
	local workspaceA = makeWorkspace()
	local workspaceB = makeWorkspace()

	local registerA = workspaceA.RegisterCollisionGroup :: (self: Dynamic, name: string) -> ()
	local isRegisteredA = workspaceA.IsCollisionGroupRegistered :: (self: Dynamic, name: string) -> boolean
	local isRegisteredB = workspaceB.IsCollisionGroupRegistered :: (self: Dynamic, name: string) -> boolean

	registerA(workspaceA, "SoNaA")

	assert(isRegisteredA(workspaceA, "SoNaA"), "workspaceA deveria enxergar o grupo que ELE registrou")
	assert(not isRegisteredB(workspaceB, "SoNaA"), "workspaceB NÃO deveria enxergar um grupo registrado só em workspaceA -- registros são por instância (InstanceState), nunca compartilhados entre DataModels diferentes")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
