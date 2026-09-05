--!strict

-- Cenário: montar uma árvore de Instance na mão (estilo "leaderstats" de um PlayerAdded real)
-- e exercitar hierarquia/eventos/busca/WaitForChild como um script de gameplay faria.
-- Origem: sintético (o padrão "pasta leaderstats sob o Player" é onipresente no ecossistema
-- Roblox -- confirmado indiretamente pelo recon: `game:GetService("Players")` é o 3º Service
-- mais referenciado nos jogos reais do usuário, 154 ocorrências -- mas como ainda não existe
-- ClassRegistry/DataModel/Players aqui, a árvore é montada manualmente com Instance.NewBase no
-- lugar de Instance.new("Folder")/Instance.new("IntValue") reais).
-- Superfície exercitada: Instance.NewBase, .Parent, .Name, GetChildren, GetDescendants,
-- FindFirstChild (raso e recursivo), FindFirstChildOfClass, FindFirstChildWhichIsA,
-- FindFirstAncestor, IsA, IsDescendantOf/IsAncestorOf, WaitForChild (sem timeout via thread
-- gerida, e com timeout via thread NÃO gerida -- branch (C) documentado em Instance.luau),
-- Changed/ChildAdded/ChildRemoved/AncestryChanged/Destroying, ClearAllChildren, Destroy,
-- GetFullName.
-- Status: passa hoje.

local process = require("@lune/process")
local nativeTask = require("@lune/task")
local Instance = require("../../src/runtime/Instance")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

-- ── Monta a árvore: Workspace-símile > PlayerFolder > leaderstats > Coins/Level ──────────
local root = Instance.NewBase("Folder", "PlayersFolder")
local playerFolder = Instance.NewBase("Folder", "Herobrine123")
playerFolder.Parent = root

local leaderstats = Instance.NewBase("Folder", "leaderstats")
leaderstats.Parent = playerFolder

local coins = Instance.NewBase("IntValue", "Coins")
coins.Parent = leaderstats
local level = Instance.NewBase("IntValue", "Level")
level.Parent = leaderstats

test("GetChildren/GetDescendants refletem a árvore montada", function()
	local playerChildren = playerFolder:GetChildren()
	assert(#playerChildren == 1, `playerFolder deveria ter 1 filho direto, tem {#playerChildren}`)
	assert(playerChildren[1] == leaderstats, "o único filho direto de playerFolder deveria ser leaderstats")

	local descendants = playerFolder:GetDescendants()
	assert(#descendants == 3, `playerFolder deveria ter 3 descendentes (leaderstats+Coins+Level), tem {#descendants}`)
end)

test("FindFirstChild raso não acha neto, recursivo acha", function()
	assert(playerFolder:FindFirstChild("Coins") == nil, "FindFirstChild raso não deveria achar um neto")
	assert(playerFolder:FindFirstChild("Coins", true) == coins, "FindFirstChild recursivo deveria achar Coins")
end)

test("FindFirstChildOfClass/FindFirstChildWhichIsA usam a ClassName/classChain default de NewBase", function()
	assert(leaderstats:FindFirstChildOfClass("IntValue") == coins, "deveria achar o primeiro IntValue (Coins, inserido antes de Level)")
	assert(leaderstats:FindFirstChildWhichIsA("IntValue") == coins, "FindFirstChildWhichIsA deveria achar pela classChain")
	assert(coins:IsA("IntValue"), "coins deveria satisfazer IsA da própria classe concreta")
	assert(coins:IsA("Instance"), "toda Instance de NewBase satisfaz IsA('Instance') pela classChain default")
	assert(not coins:IsA("Folder"), "coins não deveria satisfazer IsA de uma classe que não está na sua chain")
end)

test("FindFirstAncestor / IsDescendantOf / IsAncestorOf coerentes com a árvore", function()
	assert(coins:FindFirstAncestor("Herobrine123") == playerFolder, "FindFirstAncestor deveria subir até playerFolder pelo nome")
	assert(coins:IsDescendantOf(root), "coins deveria ser descendente de root")
	assert(root:IsAncestorOf(coins), "root deveria ser ancestral de coins")
	assert(not root:IsDescendantOf(coins), "root não é descendente de coins (sentido errado)")
end)

test("GetFullName concatena a cadeia de Name até a raiz (sem tratamento especial de DataModel)", function()
	assert(coins:GetFullName() == "PlayersFolder.Herobrine123.leaderstats.Coins", `GetFullName inesperado: {coins:GetFullName()}`)
end)

test("Changed dispara ao renomear; ChildAdded/ChildRemoved/AncestryChanged disparam ao reparentar", function()
	local changedKeys: { string } = {}
	local nameConn = level.Changed:Connect(function(key: string)
		table.insert(changedKeys, key)
	end)
	level.Name = "PlayerLevel"
	assert(level.Name == "PlayerLevel", "renomear deveria de fato mudar Name")
	assert(#changedKeys == 1 and changedKeys[1] == "Name", "Changed deveria disparar exatamente uma vez com 'Name'")
	nameConn:Disconnect()

	local addedChild: Instance.Instance? = nil
	local addedConn = leaderstats.ChildAdded:Connect(function(child: Instance.Instance)
		addedChild = child
	end)
	local gems = Instance.NewBase("IntValue", "Gems")
	gems.Parent = leaderstats
	assert(addedChild == gems, "ChildAdded deveria disparar com a Instance recém-parentada")
	addedConn:Disconnect()

	local ancestryEvents: { [string]: boolean } = {}
	local ancestryConn = gems.AncestryChanged:Connect(function(_inst: Instance.Instance, _newParent: Instance.Instance?)
		ancestryEvents.gems = true
	end)
	local removedChild: Instance.Instance? = nil
	local removedConn = leaderstats.ChildRemoved:Connect(function(child: Instance.Instance)
		removedChild = child
	end)
	gems.Parent = nil
	assert(removedChild == gems, "ChildRemoved deveria disparar no antigo pai quando o filho é desparentado")
	assert(ancestryEvents.gems, "AncestryChanged deveria disparar em gems ao desparentar")
	ancestryConn:Disconnect()
	removedConn:Disconnect()
end)

test("WaitForChild SEM timeout, chamado fora de qualquer Scheduler, bloqueia até o filho aparecer", function()
	-- Sem Scheduler adotando esta coroutine, WaitForChild sem timeout cai no branch (A):
	-- Signal:Wait() puro. Como esta é a thread principal do chunk (não uma coroutine
	-- separada), disparamos a criação do filho de dentro de um `task.spawn` nativo do
	-- próprio Lune (fora do sandbox simulado -- aqui é só o "motor de teste" agindo).
	local waitTarget = Instance.NewBase("Folder", "SlowFolder")
	local found: Instance.Instance? = nil

	local co = coroutine.create(function()
		found = waitTarget:WaitForChild("LateChild")
	end)
	local ok = coroutine.resume(co)
	assert(ok, "a coroutine que chama WaitForChild não deveria erroar ao iniciar")
	assert(coroutine.status(co) == "suspended", "deveria estar suspensa esperando o filho aparecer")

	nativeTask.spawn(function()
		nativeTask.wait(0.05)
		local lateChild = Instance.NewBase("Folder", "LateChild")
		lateChild.Parent = waitTarget
	end)

	local deadline = os.clock() + 2
	while coroutine.status(co) ~= "dead" and os.clock() < deadline do
		nativeTask.wait(0.01)
	end

	assert(coroutine.status(co) == "dead", "a coroutine deveria ter terminado depois que LateChild foi parentado")
	assert(found ~= nil and (found :: Instance.Instance).Name == "LateChild", "WaitForChild deveria ter resolvido com LateChild")
end)

test("WaitForChild COM timeout, thread não gerida (branch C, polling): expira retornando nil", function()
	local lonelyFolder = Instance.NewBase("Folder", "LonelyFolder")
	local startedAt = os.clock()
	local result = lonelyFolder:WaitForChild("NeverComes", 0.1)
	local elapsed = os.clock() - startedAt
	assert(result == nil, "WaitForChild com timeout deveria retornar nil quando o filho nunca aparece")
	assert(elapsed >= 0.1 - 0.02, `deveria ter esperado ~0.1s antes de desistir, esperou {elapsed}`)
end)

test("Destroy cascateia para os descendentes e trava reparenting depois", function()
	local destroyingFired = false
	leaderstats.Destroying:Connect(function()
		destroyingFired = true
	end)

	leaderstats:Destroy()

	assert(destroyingFired, "Destroying deveria ter disparado em leaderstats")
	assert(leaderstats.Parent == nil, "Destroy desparenta a própria Instance")
	assert(#playerFolder:GetChildren() == 0, "playerFolder não deveria mais ter leaderstats como filho")
	assert(coins.Parent == nil, "Destroy cascateia: coins (filho de leaderstats) também é destruído/desparentado")

	local threw = false
	local ok = pcall(function()
		coins.Parent = playerFolder
	end)
	threw = not ok
	assert(threw, "reparentar uma Instance já destruída deveria erroar (Destroy trava Parent)")
end)

test("ClearAllChildren destrói (não só desparenta) cada filho, igual ao Roblox real", function()
	local parent = Instance.NewBase("Folder", "ParentComFilhos")
	local childA = Instance.NewBase("Folder", "A")
	childA.Parent = parent
	local childB = Instance.NewBase("Folder", "B")
	childB.Parent = parent

	local aDestroyed = false
	childA.Destroying:Connect(function()
		aDestroyed = true
	end)

	parent:ClearAllChildren()

	assert(aDestroyed, "ClearAllChildren deveria disparar Destroying em cada filho (não é só um desparentar)")
	assert(#parent:GetChildren() == 0, "parent não deveria ter mais filhos depois de ClearAllChildren")
	local ok = pcall(function()
		childB.Name = "Renomeado"
	end)
	assert(ok, "renomear um filho destruído não deveria erroar (só Parent é travado após Destroy)")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
