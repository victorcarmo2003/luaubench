--!strict

--[[
	Behavior de `Players` -- task-services-004. LER
	.claude/agents-memory/arquiteto-services-2026-09-05.md, "Decisão 5" e "Fidelidade vs.
	pragmatismo" ANTES de mexer aqui.

	Players é a classe #3 mais usada no recon do `testador` (154 usos). Comportamento MÍNIMO e
	HONESTO -- e a distinção importa: isto NÃO é um stub que finge funcionar (regra 03 proíbe
	isso), é o resultado CORRETO de um mundo sem jogadores. `GetPlayers()` devolve `{}` porque
	não existe jogador nenhum para devolver -- não porque o método não foi implementado. É
	exatamente por essa diferença que estes três métodos ganham `Methods` de verdade aqui, em vez
	de ficarem com o stub `[LuauBench] ... not simulated by LuauBench yet` do `ClassBuilder`
	(que, sim, continua cobrindo os outros ~20 métodos desta classe -- BanAsync,
	CreateHumanoidModelFromDescription, GetFriendsAsync etc. -- que de fato não têm comportamento
	simulado nesta leva).

	DIVERGÊNCIA DECLARADA (regra 00 -- nunca silenciosa): um jogo real espera
	`Players.PlayerAdded` disparar assim que alguém entra no servidor, e conta com
	`Players:GetPlayers()` devolvendo pelo menos os jogadores já conectados. Aqui `PlayerAdded`/
	`PlayerRemoving` NUNCA disparam e `GetPlayers()` está sempre vazio -- o LuauBench não simula
	conexão de cliente nesta leva (nem em nenhuma leva planejada até agora). Um script que
	dependa de `PlayerAdded` para inicializar dados de jogador (o padrão mais comum do
	ecossistema, incluindo ProfileStore) simplesmente nunca vê esse callback rodar aqui --
	limitação real, não bug.

	NADA a fazer em `Initialize`: `LocalPlayer` já lê `nil` pelo `Default = nil` do schema gerado
	(generated/classes/Players.luau) -- nenhum código precisa reforçar isso. `PlayerAdded`/
	`PlayerRemoving` já nascem como um `Signal.new()` fresco por instância, seedado por
	`Runtime.ClassRegistry.new`/`NewEngineInstance` (Kind == "Event" no schema) ANTES de qualquer
	Initialize rodar (arquiteto-services-2026-09-05.md, "Decisão 6") -- são conectáveis por
	construção, e como NADA neste módulo chama `:Fire` sobre eles, nunca disparam. Não é preciso
	instalar nem sobrescrever nada -- diferente de `RunService`, que precisa LIGAR seus eventos a
	um Signal externo (o do Scheduler); aqui o comportamento correto já É o que o schema semeia
	sozinho.

	A classe `Player` NÃO entra nesta leva (arquiteto-services-2026-09-05.md, "O que
	deliberadamente NÃO fazer agora") -- é por isso que `GetPlayerByUserId`/
	`GetPlayerFromCharacter` devolvem sempre `nil`: não há nenhuma instância de `Player` possível
	para devolver, em nenhum cenário.
]]

local Runtime = require("../../runtime")
local Types = require("../Types")

-- Anotação explícita de `{ [string]: unknown }` necessária para o literal de tabela com campos
-- de função concreta ser aceito onde `Types.Behavior.Methods` espera um mapa indexado por
-- string, não um record "sealed" -- mesmo padrão já usado em `ClassBuilder.spec.luau`.
local Methods: { [string]: unknown } = {
	-- Roblox real: `Players:GetPlayers(): {Player}`. Sem classe `Player` simulada e sem
	-- conexão de cliente nesta leva, o único array honesto é o vazio -- nunca `nil` (o
	-- Roblox real também nunca devolve `nil` aqui, mesmo com zero jogadores).
	GetPlayers = function(_self: Runtime.Instance): { Runtime.Instance }
		return {}
	end,

	-- Roblox real: `Players:GetPlayerByUserId(userId: number): Player?` -- devolve `nil`
	-- quando ninguém com esse UserId está no servidor. Aqui NINGUÉM nunca está no servidor,
	-- então o resultado honesto é sempre `nil`, para qualquer userId.
	GetPlayerByUserId = function(_self: Runtime.Instance, _userId: unknown): unknown
		return nil
	end,

	-- Roblox real: `Players:GetPlayerFromCharacter(character: Model): Player?` -- devolve
	-- `nil` quando `character` não pertence a nenhum Player conectado. Aqui não existe
	-- Player conectado nenhum, então o resultado honesto é sempre `nil`, para qualquer
	-- character recebido.
	GetPlayerFromCharacter = function(_self: Runtime.Instance, _character: unknown): unknown
		return nil
	end,
}

local PlayersBehavior: Types.Behavior = {
	Methods = Methods,
}

return PlayersBehavior
