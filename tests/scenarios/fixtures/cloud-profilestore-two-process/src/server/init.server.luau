-- Fixture: usa o ProfileStore REAL (require de "../ProfileStore.luau", a MESMA cópia byte-a-byte
-- usada por tests/scenarios/datastore-profilestore-pattern.scenario.luau -- ver o cabeçalho
-- daquele arquivo pra proveniência completa) dentro de um projeto Rojo de verdade, executado via
-- `luaubench run` por DOIS PROCESSOS `lune` REAIS E SEPARADOS -- não uma chamada in-process.
--
-- Usado por tests/scenarios/profilestore-two-process-session-steal.scenario.luau (VALOR EXTRA de
-- task-test-cloud-001): a persistência local do "cloud" (task-cli-029/030, task-services-029/030/
-- 031) somada ao fato de que `game.JobId` é gerado por PROCESSO (não por `DataModel.new()` --
-- ver `src/runtime/DataModel.luau`, "DIVERGÊNCIA DECLARADA", `PROCESS_JOB_ID`) finalmente permite
-- exercitar o session lock do ProfileStore com DUAS INSTÂNCIAS REAIS de "servidor" (JobId
-- genuinamente diferente, estado do DataStore genuinamente compartilhado via disco) -- ao invés
-- do session lock FORJADO que tests/scenarios/datastore-profilestore-pattern.scenario.luau usa
-- (semear `ActiveSession` manualmente via `SetAsync`, ver o cabeçalho daquele arquivo, "REDESENHO
-- do passo 3") por não ter, até esta task, como obter dois processos reais compartilhando estado.
--
-- Nenhum script simulado recebe argv/env (regra 00) -- então este script decide seu PAPEL
-- ("servidor 1" ou "servidor 2") lendo o próprio estado persistido: o processo que chega primeiro
-- e não vê nenhum "Role" gravado assume o papel de servidor 1 (abre a sessão e segura por um
-- tempo real limitado, SEM liberar); o processo que chega depois e já vê "Role" gravado assume o
-- papel de servidor 2 (tenta a MESMA chave enquanto o servidor 1 ainda está com ela aberta).

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProfileStore = require(ReplicatedStorage.ProfileStoreLib)

-- API pública REAL do módulo (fixture ~1226, "ProfileStore.SetConstant") -- mesmo mecanismo que
-- os testes oficiais do próprio MadStudioRoblox/ProfileStore usam pra acelerar timing. Sem isto,
-- o backoff padrão (FIRST_LOAD_REPEAT=5s, LOAD_REPEAT_PERIOD=10s) tornaria este cenário lento
-- sem necessidade -- o COMPORTAMENTO testado (trava de sessão entre dois JobId reais) não muda.
ProfileStore.SetConstant("FIRST_LOAD_REPEAT", 1)
ProfileStore.SetConstant("LOAD_REPEAT_PERIOD", 1)

local SHARED_SESSION_KEY = "SharedSessionKey"
local HOLD_SECONDS = 5 -- quanto tempo real o "servidor 1" segura a sessão aberta sem liberar.

local store = ProfileStore.New("TwoProcessSessionLockStore", { Coins = 0 })

-- Store SEPARADO só pra coordenar QUEM já chegou primeiro -- nunca compartilha chave com
-- `SHARED_SESSION_KEY` acima (dados de coordenação do CENÁRIO, não dado de jogo).
local roleStore = DataStoreService:GetDataStore("TwoProcessRole")
local role = roleStore:GetAsync("Role")

if role == nil then
	-- SERVIDOR 1.
	roleStore:SetAsync("Role", "server1")
	print(`SCENARIO_MARK: server1-start jobid={game.JobId}`)

	local profile = store:StartSessionAsync(SHARED_SESSION_KEY, nil)
	if profile == nil then
		print("SCENARIO_MARK: server1-start-session-failed")
	else
		print(`SCENARIO_MARK: server1-session-active jobid={game.JobId}`)

		-- Só marca "ativo" DEPOIS que a sessão de fato abriu -- é o sinal que o cenário externo
		-- espera (via polling do arquivo persistido) antes de lançar o servidor 2.
		roleStore:SetAsync("Role", "server1-active")

		-- Segura o processo aberto por tempo real limitado, SEM chamar EndSession -- pra que
		-- `ActiveSession` continue apontando pra ESTE JobId enquanto o servidor 2 tenta a mesma
		-- chave. NÃO É um bug/vazamento: é exatamente o cenário que este fixture existe pra
		-- provar (sessão de um "servidor" genuinamente diferente, ainda viva).
		local holdDeadline = os.clock() + HOLD_SECONDS
		while os.clock() < holdDeadline do
			task.wait()
		end

		print(`SCENARIO_MARK: server1-done stillActiveAfterHold={tostring(profile:IsActive())}`)
	end
else
	-- SERVIDOR 2 -- processo `lune` SEPARADO, JobId diferente (confirmado empiricamente pelo
	-- cenário externo antes deste fixture existir -- ver o cabeçalho do .scenario.luau).
	print(`SCENARIO_MARK: server2-start jobid={game.JobId}`)

	-- Tenta a chave já aberta pelo servidor 1, SEM Steal, com um Cancel que desiste depois de
	-- ~2s reais -- não deveria conseguir enquanto o servidor 1 ainda está ativo.
	local cancelDeadline = os.clock() + 2
	local resultNoSteal = store:StartSessionAsync(SHARED_SESSION_KEY, {
		Cancel = function(): boolean
			return os.clock() >= cancelDeadline
		end,
	})
	print(`SCENARIO_MARK: server2-no-steal-acquired={tostring(resultNoSteal ~= nil)}`)

	-- Agora COM Steal=true -- deve suceder imediatamente (fixture ~1499, `steal_session == true or
	-- user_steal == true` bypassa a espera de SESSION_STEAL).
	local resultSteal = store:StartSessionAsync(SHARED_SESSION_KEY, { Steal = true })
	print(`SCENARIO_MARK: server2-steal-acquired={tostring(resultSteal ~= nil)}`)

	if resultSteal ~= nil then
		resultSteal:EndSession()
	end
end
