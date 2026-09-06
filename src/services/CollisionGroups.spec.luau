--!strict

--[[
	Teste dedicado de `./CollisionGroups.luau` (regra 01: teste na mesma tarefa da lógica que
	cobre) -- task-services-023. Cobre o modelo de dados puro (nomes registrados, matriz de
	colidibilidade par a par, limite de 32) isolado de qualquer `Runtime.Instance` -- a ponte com
	`Workspace`/`PhysicsService` é coberta em `./behavior/WorldRoot.spec.luau`/
	`./behavior/PhysicsService.spec.luau`.

	Roda SEM `Services.Bootstrap`/`Runtime` -- `CollisionGroups.luau` não conhece Instance (ver
	cabeçalho do módulo). Roda com `lune run src/services/CollisionGroups.spec.luau`.
]]

local process = require("@lune/process")
local CollisionGroups = require("./CollisionGroups")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

-- ================= Estado inicial =================

test("new() já vem com 'Default' registrado", function()
	local registry = CollisionGroups.new()
	assert(registry:IsRegistered("Default"), "'Default' deveria estar registrado desde a criação")
end)

test("GetMax() == 32 (fato confirmado)", function()
	local registry = CollisionGroups.new()
	assert(registry:GetMax() == 32, `GetMax() deveria ser 32, recebeu {registry:GetMax()}`)
end)

test("GetRegisteredNames() começa com só {'Default'}", function()
	local registry = CollisionGroups.new()
	local names = registry:GetRegisteredNames()
	assert(#names == 1, `esperava 1 nome registrado no início, recebeu {#names}`)
	assert(names[1] == "Default", `esperava 'Default' primeiro, recebeu '{names[1]}'`)
end)

test("GetRegisteredNames() devolve uma CÓPIA -- mutar o retorno não afeta o registro", function()
	local registry = CollisionGroups.new()
	local names = registry:GetRegisteredNames()
	table.insert(names, "Forjado")
	local namesAgain = registry:GetRegisteredNames()
	assert(#namesAgain == 1, "mutar a cópia devolvida não deveria afetar o registro interno")
end)

-- ================= Register =================

test("Register de um nome novo funciona -- IsRegistered vira true e entra em GetRegisteredNames em ORDEM de registro, depois de 'Default'", function()
	local registry = CollisionGroups.new()
	registry:Register("Players")
	registry:Register("Enemies")

	assert(registry:IsRegistered("Players"), "Players deveria estar registrado")
	assert(registry:IsRegistered("Enemies"), "Enemies deveria estar registrado")

	local names = registry:GetRegisteredNames()
	assert(#names == 3, `esperava 3 nomes, recebeu {#names}`)
	assert(names[1] == "Default" and names[2] == "Players" and names[3] == "Enemies", "ordem deveria ser Default, Players, Enemies")
end)

test("Register('Default') ERRA -- o nome cannot be 'Default' (citação da doc oficial)", function()
	local registry = CollisionGroups.new()
	local ok, err = pcall(function()
		registry:Register("Default")
	end)
	assert(not ok, "Register('Default') deveria erro")
	assert(string.find(tostring(err), "Default", 1, true) ~= nil, `mensagem deveria citar 'Default', recebeu: {err}`)
end)

test("Register de nome JÁ registrado é IDEMPOTENTE -- não erra, não duplica em GetRegisteredNames", function()
	local registry = CollisionGroups.new()
	registry:Register("Players")
	local ok = pcall(function()
		registry:Register("Players")
	end)
	assert(ok, "uma segunda chamada de Register com o MESMO nome não deveria erro (decisão: idempotente, ver cabeçalho do módulo)")

	local names = registry:GetRegisteredNames()
	assert(#names == 2, `esperava 2 nomes (Default + Players, sem duplicata), recebeu {#names}`)
end)

test("Register além do limite de 32 ERRA", function()
	local registry = CollisionGroups.new()
	-- "Default" já ocupa 1 slot -- registra mais 31 (total 32, no limite).
	for i = 1, 31 do
		registry:Register(`Group{i}`)
	end
	assert(#registry:GetRegisteredNames() == 32, "deveria ter exatamente 32 grupos registrados (Default + 31)")

	local ok, err = pcall(function()
		registry:Register("UmAMais")
	end)
	assert(not ok, "Register do 33º grupo deveria erro -- excede GetMax() == 32")
	assert(string.find(tostring(err), "32", 1, true) ~= nil, `mensagem deveria citar o limite 32, recebeu: {err}`)
end)

-- ================= Colidibilidade =================

test("dois grupos RECÉM-REGISTRADOS colidem por padrão (fato confirmado)", function()
	local registry = CollisionGroups.new()
	registry:Register("A")
	registry:Register("B")
	assert(registry:AreCollidable("A", "B"), "A e B deveriam colidir por padrão")
	assert(registry:AreCollidable("B", "A"), "a colidibilidade é simétrica -- B e A também deveriam colidir")
end)

test("SetCollidable(a, b, false) desliga a colisão nos DOIS sentidos", function()
	local registry = CollisionGroups.new()
	registry:Register("A")
	registry:Register("B")
	registry:SetCollidable("A", "B", false)

	assert(not registry:AreCollidable("A", "B"), "A e B não deveriam mais colidir")
	assert(not registry:AreCollidable("B", "A"), "a mudança deveria valer nos dois sentidos (matriz simétrica)")
end)

test("SetCollidable(a, b, false) seguido de SetCollidable(a, b, true) restaura a colisão", function()
	local registry = CollisionGroups.new()
	registry:Register("A")
	registry:Register("B")
	registry:SetCollidable("A", "B", false)
	registry:SetCollidable("A", "B", true)

	assert(registry:AreCollidable("A", "B"), "A e B deveriam voltar a colidir")
end)

test("SetCollidable/AreCollidable com grupo NÃO registrado ERRA", function()
	local registry = CollisionGroups.new()
	registry:Register("A")

	local okSet, errSet = pcall(function()
		registry:SetCollidable("A", "Fantasma", true)
	end)
	assert(not okSet, "SetCollidable com grupo não registrado deveria erro")
	assert(string.find(tostring(errSet), "Fantasma", 1, true) ~= nil, `mensagem deveria citar o nome não registrado, recebeu: {errSet}`)

	local okAre, errAre = pcall(function()
		registry:AreCollidable("Fantasma", "A")
	end)
	assert(not okAre, "AreCollidable com grupo não registrado deveria erro")
	assert(string.find(tostring(errAre), "Fantasma", 1, true) ~= nil, `mensagem deveria citar o nome não registrado, recebeu: {errAre}`)
end)

test("um grupo pode ter sua AUTO-colisão desligada (name1 == name2 é permitido)", function()
	local registry = CollisionGroups.new()
	registry:Register("A")
	assert(registry:AreCollidable("A", "A"), "um grupo deveria colidir consigo mesmo por padrão")

	registry:SetCollidable("A", "A", false)
	assert(not registry:AreCollidable("A", "A"), "a auto-colisão deveria poder ser desligada")
end)

-- ================= Unregister =================

test("Unregister de um grupo registrado funciona -- IsRegistered vira false, some de GetRegisteredNames", function()
	local registry = CollisionGroups.new()
	registry:Register("Temporario")
	registry:Unregister("Temporario")

	assert(not registry:IsRegistered("Temporario"), "Temporario não deveria mais estar registrado")
	local names = registry:GetRegisteredNames()
	assert(#names == 1, "só 'Default' deveria sobrar depois do Unregister")
end)

test("Unregister('Default') ERRA -- reservado, nunca removível", function()
	local registry = CollisionGroups.new()
	local ok, err = pcall(function()
		registry:Unregister("Default")
	end)
	assert(not ok, "Unregister('Default') deveria erro")
	assert(string.find(tostring(err), "Default", 1, true) ~= nil, `mensagem deveria citar 'Default', recebeu: {err}`)
end)

test("Unregister de um nome NÃO registrado é NO-OP idempotente -- não erra", function()
	local registry = CollisionGroups.new()
	local ok = pcall(function()
		registry:Unregister("NuncaExistiu")
	end)
	assert(ok, "Unregister de um nome nunca registrado não deveria erro (decisão: no-op idempotente, ver cabeçalho do módulo)")
end)

test("Unregister limpa a matriz de colidibilidade -- registrar o MESMO nome de novo não herda um SetCollidable antigo", function()
	local registry = CollisionGroups.new()
	registry:Register("A")
	registry:Register("B")
	registry:SetCollidable("A", "B", false)
	registry:Unregister("B")
	registry:Register("B")

	assert(registry:AreCollidable("A", "B"), "um 'B' recém-registrado de novo deveria colidir com A por padrão -- rastro antigo da matriz não deveria sobreviver ao Unregister")
end)

-- ================= Rename =================

test("Rename de um grupo registrado funciona -- nome antigo some, novo aparece na MESMA posição", function()
	local registry = CollisionGroups.new()
	registry:Register("Velho")
	registry:Rename("Velho", "Novo")

	assert(not registry:IsRegistered("Velho"), "'Velho' não deveria mais estar registrado")
	assert(registry:IsRegistered("Novo"), "'Novo' deveria estar registrado")

	local names = registry:GetRegisteredNames()
	assert(names[2] == "Novo", `'Novo' deveria estar na posição 2 (mesma de 'Velho' antes), recebeu '{names[2]}'`)
end)

test("Rename PRESERVA as entradas da matriz de colidibilidade do nome antigo para o novo", function()
	local registry = CollisionGroups.new()
	registry:Register("A")
	registry:Register("Velho")
	registry:SetCollidable("A", "Velho", false)

	registry:Rename("Velho", "Novo")

	assert(not registry:AreCollidable("A", "Novo"), "a colidibilidade desligada deveria sobreviver ao Rename, sob o nome novo")
end)

test("Rename(from='Default', ...) e Rename(..., to='Default') ERRAM", function()
	local registry = CollisionGroups.new()
	registry:Register("X")

	local okFrom = pcall(function()
		registry:Rename("Default", "Outro")
	end)
	assert(not okFrom, "Rename com from == 'Default' deveria erro")

	local okTo = pcall(function()
		registry:Rename("X", "Default")
	end)
	assert(not okTo, "Rename com to == 'Default' deveria erro")
end)

test("Rename de um 'from' NÃO registrado ERRA", function()
	local registry = CollisionGroups.new()
	local ok, err = pcall(function()
		registry:Rename("Fantasma", "Novo")
	end)
	assert(not ok, "Rename com 'from' não registrado deveria erro")
	assert(string.find(tostring(err), "Fantasma", 1, true) ~= nil, `mensagem deveria citar o nome não registrado, recebeu: {err}`)
end)

test("Rename para um 'to' JÁ registrado ERRA", function()
	local registry = CollisionGroups.new()
	registry:Register("A")
	registry:Register("B")

	local ok, err = pcall(function()
		registry:Rename("A", "B")
	end)
	assert(not ok, "Rename para um nome já registrado deveria erro")
	assert(string.find(tostring(err), "B", 1, true) ~= nil, `mensagem deveria citar o nome já registrado, recebeu: {err}`)
end)

test("Rename(x, x) -- to == from -- é NO-OP, nunca erro", function()
	local registry = CollisionGroups.new()
	registry:Register("A")
	local ok = pcall(function()
		registry:Rename("A", "A")
	end)
	assert(ok, "Rename para o MESMO nome não deveria erro")
	assert(registry:IsRegistered("A"), "A deveria continuar registrado")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
