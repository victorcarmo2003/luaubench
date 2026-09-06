-- Fixture: script de projeto REAL (não roda in-process -- é executado via `luaubench run` de
-- verdade, um processo `lune` completo por execução) usado por
-- tests/scenarios/cloud-datastore-restart-persistence.scenario.luau (task-test-cloud-001).
--
-- Este script NÃO recebe nenhum argumento externo (nenhum ambiente/CLI arg alcança um script
-- simulado -- regra 00) -- a ÚNICA forma de ele saber se é a "primeira" ou a "segunda" execução
-- deste projeto é ler o próprio estado que uma execução anterior deixou no DataStore. É exatamente
-- esse comportamento observável (não um hack de teste) que prova a promessa da feature: se o
-- "cloud" persistiu de verdade entre dois processos `luaubench run` separados, a chave marcadora
-- "HasRunBefore" está lá na segunda execução; se não persistiu, o script re-executa o ramo de
-- "primeira execução" de novo.
--
-- O cenário externo roda este projeto via `process.exec("lune", {"run", "src/cli/main.luau",
-- "run", <este projeto>, ...})` DUAS VEZES (dois processos `lune` reais, não uma chamada
-- in-process) e lê o stdout de cada uma procurando por linhas "SCENARIO_MARK: ...".

local DataStoreService = game:GetService("DataStoreService")

local store = DataStoreService:GetDataStore("CloudScenarioPlayerData")
local ordered = DataStoreService:GetOrderedDataStore("CloudScenarioLeaderboard")

local hasRunBefore = store:GetAsync("HasRunBefore")

if hasRunBefore == nil then
	-- PRIMEIRA EXECUÇÃO conhecida deste projeto (ou `--no-persist` estava ativo em toda execução
	-- anterior, o que também nunca escreveria esta chave em disco) -- popula o estado que a
	-- SEGUNDA execução (rodada com persistência LIGADA) vai conferir que sobreviveu.

	store:SetAsync("PlayerCoins", 100)
	-- Duas atualizações extras, de propósito -- criam TRÊS versões distintas e recuperáveis da
	-- MESMA chave, pra exercitar `ListVersionsAsync` sobrevivendo ao restart (não só o valor
	-- corrente).
	store:UpdateAsync("PlayerCoins", function(old: unknown): number
		return ((old :: number?) or 0) + 50
	end)
	store:UpdateAsync("PlayerCoins", function(old: unknown): number
		return ((old :: number?) or 0) + 25
	end)

	-- OrderedDataStore: valores fora de ordem alfabética de propósito -- a ordenação tem que vir
	-- do VALOR, não da ordem de escrita, tanto antes quanto depois do restart.
	ordered:SetAsync("Alice", 30)
	ordered:SetAsync("Bob", 10)
	ordered:SetAsync("Carol", 20)

	-- Escrita por ÚLTIMO, de propósito: se o processo morresse no meio deste bloco, a próxima
	-- execução ainda veria `HasRunBefore == nil` e tentaria semear tudo de novo (idempotente o
	-- bastante para este cenário -- SetAsync/UpdateAsync sobre as mesmas chaves não corrompe nada).
	store:SetAsync("HasRunBefore", true)

	print("SCENARIO_MARK: run=first")
else
	-- SEGUNDA EXECUÇÃO: só chega neste ramo se o documento ".luaubench/cloud/datastore.json" da
	-- execução anterior foi lido de verdade no Bootstrap DESTE processo novo (task-services-031,
	-- `loadCloudStateIfPresent`) -- prova de persistência entre processos, não só entre chamadas
	-- dentro do mesmo `lune run`.
	print("SCENARIO_MARK: run=second")

	local coins = store:GetAsync("PlayerCoins")
	print("SCENARIO_MARK: coins=" .. tostring(coins))

	local versionPages = store:ListVersionsAsync("PlayerCoins")
	local versionItems = versionPages:GetCurrentPage()
	print("SCENARIO_MARK: version-count=" .. tostring(#versionItems))

	local versionList = {}
	for _, item in versionItems do
		table.insert(versionList, tostring((item :: any).Version))
	end
	print("SCENARIO_MARK: versions=" .. table.concat(versionList, "|"))

	local versionsAscending = true
	for i = 2, #versionList do
		if versionList[i] < versionList[i - 1] then
			versionsAscending = false
		end
	end
	print("SCENARIO_MARK: versions-ascending=" .. tostring(versionsAscending))

	local sortedPages = ordered:GetSortedAsync(true, 10)
	local sortedItems = sortedPages:GetCurrentPage()
	local orderedParts = {}
	for _, item in sortedItems do
		local entry = item :: { key: string, value: number }
		table.insert(orderedParts, entry.key .. "=" .. tostring(entry.value))
	end
	print("SCENARIO_MARK: ordered=" .. table.concat(orderedParts, ","))
end
