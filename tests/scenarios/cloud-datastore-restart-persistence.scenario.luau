--!strict

-- Cenário: a promessa central da persistência local do estado "cloud" (DataStoreService), do
-- ponto de vista de quem usa `luaubench run` de verdade -- rodar o comando DUAS VEZES (dois
-- processos `lune` REAIS e SEPARADOS, `process.exec`, nunca uma chamada in-process) contra o
-- MESMO projeto-fixture, e confirmar que o DataStore sobreviveu ao restart (valor corrente,
-- histórico de versão via ListVersionsAsync, e ordenação de OrderedDataStore), enquanto a árvore
-- de Instance/scripts é reconstruída do zero a cada execução -- que é o comportamento CORRETO e
-- não muda (não está sob teste aqui).
-- Origem: sintético (harness deste arquivo + tests/scenarios/fixtures/cloud-persistence-project/,
-- fixture escrito para este cenário).
-- Superfície exercitada: `luaubench run [caminho]` via processo real (`src/cli/main.luau`),
-- `--no-persist`, `game:GetService("DataStoreService")`, `DataStore:GetAsync/SetAsync/
-- UpdateAsync/ListVersionsAsync`, `OrderedDataStore:GetSortedAsync`, `Pages:GetCurrentPage`,
-- persistência local em `.luaubench/cloud/datastore.json` (task-cli-029/030, task-services-
-- 029/030/031, arquiteto-persistencia-cloud-2026-09-06.md).
-- Status: passa hoje -- os 3 `test()` abaixo rodam de ponta a ponta contra binário `lune` real,
-- sem stub. Task: task-test-cloud-001.
--
-- POR QUE DOIS `process.exec` SEPARADOS E NÃO `Cli.Main` CHAMADO DUAS VEZES IN-PROCESS: o
-- comportamento sob teste É a sobrevivência do estado entre PROCESSOS -- uma chamada in-process
-- reusaria o `PROCESS_JOB_ID`/módulos já carregados deste próprio script de teste e não provaria
-- nada sobre persistência em disco (o objetivo inteiro da feature). Mesmo padrão de
-- `tests/scenarios/real-roblox-games-pipeline-smoke.scenario.luau`.

local process = require("@lune/process")
local fs = require("@lune/fs")

local passedCount = 0
local failedCount = 0
local totalCount = 0

-- Harness resiliente (mesmo padrão dos demais cenários deste diretório): uma falha de assert não
-- derruba os testes seguintes, só marca [FAIL] e segue.
local function test(name: string, run: () -> ())
	totalCount += 1
	local ok, err = pcall(run)
	if ok then
		passedCount += 1
		print(`[PASS] {name}`)
	else
		failedCount += 1
		print(`[FAIL] {name}`)
		print(`       {tostring(err)}`)
	end
end

local FIXTURE_DIR = "tests/scenarios/fixtures/cloud-persistence-project"
local CLOUD_ROOT_DIR = FIXTURE_DIR .. "/.luaubench"
local CLOUD_DOCUMENT_PATH = CLOUD_ROOT_DIR .. "/cloud/datastore.json"

-- Acceptance da task (task-test-cloud-001): "a fixture limpa o PRÓPRIO .luaubench/ antes e
-- depois (teste determinístico, nunca herda estado de execução anterior da suíte)". Chamado no
-- início e no fim deste arquivo, e entre os testes que dependem de partir de um estado limpo.
local function cleanCloudState(): ()
	if fs.isDir(CLOUD_ROOT_DIR) then
		fs.removeDir(CLOUD_ROOT_DIR)
	end
end

local function runProject(extraArgs: { string }?): process.ExecResult
	local args = { "run", "src/cli/main.luau", "run", FIXTURE_DIR, "--no-color", "--timeout", "10" }
	if extraArgs ~= nil then
		for _, extra in extraArgs do
			table.insert(args, extra)
		end
	end
	return process.exec("lune", args)
end

local function hasMark(stdout: string, mark: string): boolean
	return string.find(stdout, mark, 1, true) ~= nil
end

----------------------------------------------------------------------------------------------
-- Teste 1: o caso central -- persistência LIGADA por padrão (sem nenhuma flag), duas execuções
-- reais e separadas.
----------------------------------------------------------------------------------------------
cleanCloudState()

test("luaubench run x2 (persistência LIGADA por padrão): valor, histórico de versão (ListVersionsAsync) e ordenação (OrderedDataStore:GetSortedAsync) sobrevivem ao restart", function()
	local first = runProject()
	assert(first.ok, `primeira execução deveria sair com sucesso (code {first.code}) -- stdout: {first.stdout} stderr: {first.stderr}`)
	assert(
		hasMark(first.stdout, "SCENARIO_MARK: run=first"),
		`esperava a PRIMEIRA execução tomar o ramo de "primeira execução" (".luaubench/" não existia antes deste teste) -- stdout: {first.stdout}`
	)
	assert(
		fs.isFile(CLOUD_DOCUMENT_PATH),
		`esperava "{CLOUD_DOCUMENT_PATH}" ter sido criado pela primeira execução (persistência LIGADA por padrão, sem precisar de nenhuma flag)`
	)

	-- SEGUNDO PROCESSO `lune` REAL E SEPARADO -- não reaproveita nenhum estado em memória do
	-- primeiro (novo `PROCESS_JOB_ID`, novo `Store.new()` module-local de `GlobalDataStore.luau`,
	-- nova DataModel/Scheduler) -- só o arquivo em disco liga os dois.
	local second = runProject()
	assert(second.ok, `segunda execução deveria sair com sucesso (code {second.code}) -- stdout: {second.stdout} stderr: {second.stderr}`)
	assert(
		hasMark(second.stdout, "SCENARIO_MARK: run=second"),
		`esperava a SEGUNDA execução ver "HasRunBefore" == true, persistido pela PRIMEIRA execução (processo separado) -- prova de que o Bootstrap desta segunda execução leu ".luaubench/cloud/datastore.json" de verdade antes do script rodar -- stdout: {second.stdout}`
	)
	assert(
		hasMark(second.stdout, "SCENARIO_MARK: coins=175"),
		`PlayerCoins deveria ter persistido como 100+50+25=175 (SetAsync + 2x UpdateAsync da primeira execução) -- stdout: {second.stdout}`
	)
	assert(
		hasMark(second.stdout, "SCENARIO_MARK: version-count=3"),
		`ListVersionsAsync deveria devolver as 3 versões escritas na primeira execução -- histórico completo sobrevive ao restart, não só o valor corrente (arquiteto-persistencia-cloud-2026-09-06.md, seção 5) -- stdout: {second.stdout}`
	)
	assert(
		hasMark(second.stdout, "SCENARIO_MARK: versions-ascending=true"),
		`a ordem lexicográfica de Version deveria continuar batendo com a ordem de inserção MESMO depois do restart -- exige que Store.Import restaure o versionCounter (seção 5 do desenho, "achado: o contador de versão precisa ser restaurado no Import") -- stdout: {second.stdout}`
	)
	assert(
		hasMark(second.stdout, "SCENARIO_MARK: ordered=Bob=10,Carol=20,Alice=30"),
		`OrderedDataStore:GetSortedAsync deveria continuar ordenado por VALOR (10 < 20 < 30), não pela ordem de escrita (Alice, Bob, Carol) -- e essa ordenação deriva do valor persistido, então só existe se o valor sobreviveu ao restart -- stdout: {second.stdout}`
	)
end)

cleanCloudState()

----------------------------------------------------------------------------------------------
-- Teste 2: `--no-persist` nunca cria ".luaubench/", mesmo escrevendo no DataStore várias vezes.
----------------------------------------------------------------------------------------------
test("--no-persist: execução nunca cria .luaubench/, mesmo chamando SetAsync/UpdateAsync/SetAsync (ordered) várias vezes", function()
	assert(not fs.isDir(CLOUD_ROOT_DIR), "pré-condição do teste: .luaubench/ não deveria existir ainda (cleanCloudState acima)")

	local result = runProject({ "--no-persist" })
	assert(result.ok, `execução com --no-persist deveria sair com sucesso (code {result.code}) -- stdout: {result.stdout} stderr: {result.stderr}`)
	assert(
		hasMark(result.stdout, "SCENARIO_MARK: run=first"),
		`esperava o ramo de "primeira execução" (nada persistido pra ler ainda) -- stdout: {result.stdout}`
	)
	assert(
		not fs.isDir(CLOUD_ROOT_DIR),
		"--no-persist NUNCA deveria criar .luaubench/ -- o script chamou SetAsync/UpdateAsync/SetAsync (ordered) 6 vezes e nenhuma delas deveria ter tocado o disco"
	)
end)

cleanCloudState()

----------------------------------------------------------------------------------------------
-- Teste 3: `--no-persist` não LÊ o que uma execução anterior (sem a flag) persistiu, e não
-- corrompe esse estado em disco -- nem por leitura nem por escrita.
----------------------------------------------------------------------------------------------
test("--no-persist: não lê o estado que uma execução anterior sem a flag persistiu, e não altera o documento em disco dela", function()
	local persisted = runProject()
	assert(persisted.ok, `execução com persistência LIGADA deveria sair com sucesso -- stdout: {persisted.stdout} stderr: {persisted.stderr}`)
	assert(hasMark(persisted.stdout, "SCENARIO_MARK: run=first"), `stdout: {persisted.stdout}`)
	assert(fs.isFile(CLOUD_DOCUMENT_PATH), "execução com persistência LIGADA deveria ter criado o documento")

	local contentsBeforeNoPersist = fs.readFile(CLOUD_DOCUMENT_PATH)

	local noPersistRun = runProject({ "--no-persist" })
	assert(noPersistRun.ok, `execução --no-persist deveria sair com sucesso -- stdout: {noPersistRun.stdout} stderr: {noPersistRun.stderr}`)
	assert(
		hasMark(noPersistRun.stdout, "SCENARIO_MARK: run=first"),
		`--no-persist deveria ter tomado o ramo de "primeira execução" DE NOVO -- NÃO deveria ter lido "HasRunBefore" que a execução anterior persistiu em disco (Bootstrap com CloudPersistence=nil nunca chama Load) -- stdout: {noPersistRun.stdout}`
	)

	local contentsAfterNoPersist = fs.readFile(CLOUD_DOCUMENT_PATH)
	assert(
		contentsAfterNoPersist == contentsBeforeNoPersist,
		"--no-persist NÃO deveria ter tocado o documento em disco de jeito nenhum (nem leitura, nem escrita) -- o conteúdo do arquivo mudou depois de uma execução com a flag ligada"
	)

	-- Confirmação final: uma execução SEGUINTE com persistência LIGADA de novo ainda vê o estado
	-- ORIGINAL da primeira execução -- não o que a execução --no-persist teria escrito por cima
	-- se, por algum bug, tivesse persistido de qualquer forma.
	local resumed = runProject()
	assert(resumed.ok, `stderr: {resumed.stderr}`)
	assert(
		hasMark(resumed.stdout, "SCENARIO_MARK: run=second"),
		`esperava esta execução (persistência LIGADA de novo) ainda ver o estado ORIGINAL persistido pela primeira execução, ignorando por completo a execução --no-persist no meio -- stdout: {resumed.stdout}`
	)
	assert(hasMark(resumed.stdout, "SCENARIO_MARK: coins=175"), `stdout: {resumed.stdout}`)
end)

cleanCloudState()

print(`\n{passedCount}/{totalCount} testes passaram ({failedCount} falharam)`)

if failedCount > 0 then
	process.exit(1)
end
