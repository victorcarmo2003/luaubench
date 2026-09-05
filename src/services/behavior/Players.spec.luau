--!strict

--[[
	Teste dedicado de `./Players.luau` (regra 01: teste na mesma tarefa da lógica que cobre).
	`../Integration.spec.luau`, seção "1b", já cobre a superfície GENÉRICA de Service
	(ClassName/Parent/singleton) para `Players` via `game:GetService` -- este arquivo cobre a
	superfície ESPECÍFICA desta classe: o comportamento MÍNIMO e HONESTO de um mundo sem
	jogadores (ver cabeçalho de `./Players.luau`).

	Roda com `lune run src/services/behavior/Players.spec.luau`.
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

-- Idempotente (guarda local em ../init.luau) -- seguro mesmo que outro spec do processo já tenha
-- chamado.
Services.Register()

-- Monta um `Players` de verdade, pelo caminho de produção inteiro: `Services.Bootstrap`
-- (Register + Context.Set) seguido de `game:GetService`. `Players` não tem `Initialize`
-- (ver cabeçalho de `./Players.luau`), então nem precisaria de Bootstrap -- mas o caminho
-- completo é o que um script do usuário de fato percorre, e é o mesmo padrão de
-- `RunService.spec.luau`.
local function makePlayers(): Runtime.Instance
	local scheduler = Runtime.Scheduler.new()
	local game = Runtime.DataModel.new()
	Services.Bootstrap({ scheduler = scheduler, dataModel = game })
	return game:GetService("Players")
end

test("Players:GetPlayers() devolve uma tabela VAZIA, nunca nil -- resultado honesto de um mundo sem jogadores", function()
	local players = makePlayers()
	local playersDynamic = (players :: unknown) :: Dynamic
	local getPlayers = playersDynamic.GetPlayers :: (self: Dynamic) -> { unknown }

	local result = getPlayers(playersDynamic)

	assert(result ~= nil, "GetPlayers() nunca deveria devolver nil -- o Roblox real também não devolve nil com zero jogadores")
	assert(#result == 0, `GetPlayers() deveria devolver tabela vazia, recebeu {#result} elemento(s)`)
end)

test("Players.LocalPlayer é nil, sem erro -- lido direto do Default do schema gerado", function()
	local players = makePlayers()
	local playersDynamic = (players :: unknown) :: Dynamic

	local ok, value = pcall(function()
		return playersDynamic.LocalPlayer
	end)

	assert(ok, "ler Players.LocalPlayer não deveria erro -- é uma propriedade do schema com Default nil")
	assert(value == nil, "Players.LocalPlayer deveria ser nil -- não há client simulado nesta leva")
end)

test("Players:GetPlayerByUserId(qualquer) devolve nil -- não existe Player nenhum para devolver", function()
	local players = makePlayers()
	local playersDynamic = (players :: unknown) :: Dynamic
	local getPlayerByUserId = playersDynamic.GetPlayerByUserId :: (self: Dynamic, userId: unknown) -> unknown

	assert(getPlayerByUserId(playersDynamic, 12345) == nil, "GetPlayerByUserId deveria devolver nil para qualquer userId")
	assert(getPlayerByUserId(playersDynamic, 0) == nil, "GetPlayerByUserId deveria devolver nil mesmo para userId 0")
end)

test("Players:GetPlayerFromCharacter(qualquer) devolve nil -- classe Player não existe nesta leva", function()
	local players = makePlayers()
	local playersDynamic = (players :: unknown) :: Dynamic
	local getPlayerFromCharacter = playersDynamic.GetPlayerFromCharacter :: (self: Dynamic, character: unknown) -> unknown

	local fakeCharacter = Services.new("Folder", "FakeCharacter")
	assert(
		getPlayerFromCharacter(playersDynamic, fakeCharacter) == nil,
		"GetPlayerFromCharacter deveria devolver nil para qualquer character, mesmo um Instance real"
	)
	assert(getPlayerFromCharacter(playersDynamic, nil) == nil, "GetPlayerFromCharacter deveria devolver nil também para nil")
end)

test("Players.PlayerAdded é conectável sem erro -- existe, e nunca dispara (nenhum código chama :Fire)", function()
	local players = makePlayers()
	local playersDynamic = (players :: unknown) :: Dynamic
	local playerAdded = playersDynamic.PlayerAdded :: Runtime.Signal<unknown>

	local ok = pcall(function()
		playerAdded:Connect(function() end)
	end)
	assert(ok, "conectar em Players.PlayerAdded não deveria erro -- é um Signal real, seedado pelo schema")

	local fired = false
	playerAdded:Connect(function()
		fired = true
	end)

	assert(not fired, "Players.PlayerAdded não deveria ter disparado sozinho, sem nenhum :Fire explícito")
end)

test("Players.PlayerRemoving é conectável sem erro -- mesma disciplina de PlayerAdded", function()
	local players = makePlayers()
	local playersDynamic = (players :: unknown) :: Dynamic
	local playerRemoving = playersDynamic.PlayerRemoving :: Runtime.Signal<unknown, unknown>

	local ok = pcall(function()
		playerRemoving:Connect(function() end)
	end)
	assert(ok, "conectar em Players.PlayerRemoving não deveria erro")
end)

test(
	"DIVERGÊNCIA DECLARADA: PlayerAdded/PlayerRemoving NUNCA disparam sob N StepOnce -- LuauBench não simula conexão de cliente",
	function()
		local scheduler = Runtime.Scheduler.new()
		local game = Runtime.DataModel.new()
		Services.Bootstrap({ scheduler = scheduler, dataModel = game })
		local players = game:GetService("Players")
		local playersDynamic = (players :: unknown) :: Dynamic
		local playerAdded = playersDynamic.PlayerAdded :: Runtime.Signal<unknown>

		local fired = false
		playerAdded:Connect(function()
			fired = true
		end)

		for _ = 1, 20 do
			scheduler:StepOnce(1 / 60)
		end

		assert(
			not fired,
			"PlayerAdded nunca deveria disparar, mesmo depois de vários StepOnce -- é a divergência declarada: um jogo real espera esse callback rodar quando um jogador conecta, aqui isso nunca acontece"
		)
	end
)

test("método sem behavior desta leva (BanAsync, por exemplo) continua com o stub [LuauBench]", function()
	local players = makePlayers()
	local playersDynamic = (players :: unknown) :: Dynamic

	local ok, err = pcall(function()
		local banAsync = playersDynamic.BanAsync :: (self: Dynamic, config: unknown) -> ()
		banAsync(playersDynamic, {})
	end)

	assert(not ok, "BanAsync não tem Methods em behavior/Players.luau -- deveria cair no stub do ClassBuilder")
	assert(
		string.find(tostring(err), "[LuauBench] Players:BanAsync() exists in the Roblox API Dump", 1, true) ~= nil,
		`mensagem deveria ter o prefixo [LuauBench] (regra 03), recebeu: {err}`
	)
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
