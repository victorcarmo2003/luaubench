--!strict

-- Cenário: VALOR EXTRA de task-test-cloud-001 -- session lock do ProfileStore exercitado por DOIS
-- PROCESSOS `lune` REAIS E SEPARADOS (não um único processo chamando o módulo duas vezes, e não
-- um `ActiveSession` forjado à mão) -- "servidor 1" abre uma sessão via `StartSessionAsync` e a
-- segura aberta por alguns segundos reais; enquanto isso, "servidor 2" (processo `lune` diferente,
-- `game.JobId` genuinamente diferente -- confirmado empiricamente por esta mesma task, ver
-- relatório) tenta a MESMA chave contra o MESMO estado persistido em disco
-- (`.luaubench/cloud/datastore.json`) -- primeiro sem `Steal` (deve falhar), depois com
-- `Steal = true` (deve suceder).
--
-- Origem: sintético (harness deste arquivo + fixture novo
-- tests/scenarios/fixtures/cloud-profilestore-two-process/) que REQUER o ProfileStore REAL já
-- existente em tests/scenarios/fixtures/ProfileStore.luau (cópia byte-a-byte do
-- MadStudioRoblox/ProfileStore, ver o cabeçalho de
-- tests/scenarios/datastore-profilestore-pattern.scenario.luau para a proveniência completa --
-- este cenário não duplica o arquivo, só aponta um `$path` pra ele).
--
-- Superfície exercitada: `luaubench run [caminho]` via DOIS processos reais (`process.create` +
-- `process.exec`, não `Cli.Main` in-process), persistência local do "cloud"
-- (`.luaubench/cloud/datastore.json`), `game.JobId` (task-runtime-034), ProfileStore real
-- (`StartSessionAsync`/`Steal`/`Cancel`/`IsActive`/`SetConstant`, mesma API pública já coberta por
-- `datastore-profilestore-pattern.scenario.luau`).
--
-- POR QUE ISTO NÃO EXISTIA ANTES (contexto para quem for revisar): o cabeçalho de
-- `datastore-profilestore-pattern.scenario.luau` documenta que o passo 3 daquele cenário (session
-- lock) foi REDESENHADO pra forjar um `ActiveSession` de "outro servidor" via `SetAsync` direto,
-- em vez de usar dois servidores de verdade -- na ÉPOCA daquele redesenho (2026-09-05/06), duas
-- chamadas de `chunk()` no MESMO processo `lune` compartilhavam o MESMO `game.JobId`
-- (`PROCESS_JOB_ID` é constante de MÓDULO, gerado uma vez por PROCESSO -- `DataModel.luau`) e a
-- persistência do DataStore era só intra-processo (`Store.new()` module-local, sem
-- `Export`/`Import`/disco) -- não havia como dois "servidores" verem o MESMO estado com JobIds
-- DIFERENTES sem essas duas peças. Esta task (task-test-cloud-001) traz as duas: persistência real
-- em disco (task-cli-029/030, task-services-029/030/031) e a confirmação empírica (nesta mesma
-- rodada, ver relatório) de que dois processos `lune` SEPARADOS realmente geram `PROCESS_JOB_ID`
-- diferentes (o `math.random` do Lune já sai semeado de forma distinta por processo -- não
-- precisou de nenhuma mudança de código pra isso já ser verdade, só faltava a persistência pra
-- expor o comportamento).
--
-- O session lock FORJADO em `datastore-profilestore-pattern.scenario.luau` continua sendo o
-- cenário de referência (determinístico, rápido, sem depender de timing de wall-clock entre dois
-- processos) -- este arquivo é um cenário ADICIONAL, não uma substituição: prova a MESMA garantia
-- de trava de sessão, mas contra a topologia de produção real (dois servidores de verdade), pelo
-- preço de depender de polling com timeout sobre um arquivo em disco (ver `waitForRoleMark`,
-- abaixo) -- mais lento e um tanto mais sensível a timing do que o cenário forjado, de propósito
-- documentado, não por descuido.
--
-- Status: passa hoje -- rodado repetidamente nesta rodada sem flake observado (ver relatório).

local process = require("@lune/process")
local fs = require("@lune/fs")
local task = require("@lune/task")

local passedCount = 0
local failedCount = 0
local totalCount = 0

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

local FIXTURE_DIR = "tests/scenarios/fixtures/cloud-profilestore-two-process"
local CLOUD_ROOT_DIR = FIXTURE_DIR .. "/.luaubench"
local CLOUD_DOCUMENT_PATH = CLOUD_ROOT_DIR .. "/cloud/datastore.json"

local function cleanCloudState(): ()
	if fs.isDir(CLOUD_ROOT_DIR) then
		fs.removeDir(CLOUD_ROOT_DIR)
	end
end

local function readDocumentOrEmpty(): string
	if fs.isFile(CLOUD_DOCUMENT_PATH) then
		return fs.readFile(CLOUD_DOCUMENT_PATH)
	end
	return ""
end

-- Espera (polling real, com `task.wait` entre tentativas -- este arquivo roda FORA do
-- Runtime.Scheduler do LuauBench, então não há `task.wait` simulado aqui, só o real do Lune) até
-- o documento persistido conter `mark` em algum lugar, ou `timeoutSeconds` reais se esgotarem.
-- Suficiente pra este cenário: o "servidor 1" grava `Role = "server1-active"` como um valor de
-- DataStore comum, então a substring aparece literalmente no JSON assim que o flush coalescido
-- por tique (arquiteto-persistencia-cloud-2026-09-06.md, seção 6) rodar pelo menos uma vez depois
-- da escrita -- não precisa decodificar o envelope pra este propósito.
local function waitForMarkInDocument(mark: string, timeoutSeconds: number): boolean
	local deadline = os.clock() + timeoutSeconds
	repeat
		local contents = readDocumentOrEmpty()
		if string.find(contents, mark, 1, true) ~= nil then
			return true
		end
		task.wait(0.05)
	until os.clock() >= deadline
	return string.find(readDocumentOrEmpty(), mark, 1, true) ~= nil
end

local function runFixture(extraArgs: { string }?): { string }
	local args = { "run", "src/cli/main.luau", "run", FIXTURE_DIR, "--no-color", "--timeout", "20" }
	if extraArgs ~= nil then
		for _, extra in extraArgs do
			table.insert(args, extra)
		end
	end
	return args
end

cleanCloudState()

test("dois processos `lune` reais (JobId diferente, estado persistido compartilhado): servidor 2 NÃO rouba sem Steal, e rouba imediatamente COM Steal=true", function()
	-- SERVIDOR 1: processo em BACKGROUND (`process.create`, não bloqueante -- confirmado
	-- empiricamente nesta task) -- abre a sessão e a segura por `HOLD_SECONDS` (5s) reais dentro
	-- do PRÓPRIO fixture, sem chamar EndSession.
	local server1 = process.create("lune", runFixture())

	local ok, err = pcall(function()
		local becameActive = waitForMarkInDocument('"server1-active"', 10)
		assert(
			becameActive,
			`servidor 1 não marcou a sessão como ativa (Role="server1-active" persistido em disco) dentro de 10s reais de polling em "{CLOUD_DOCUMENT_PATH}" -- servidor 2 não pode ser lançado com segurança sem essa confirmação`
		)

		-- SERVIDOR 2: processo EM PRIMEIRO PLANO (`process.exec`, bloqueante) -- lançado só DEPOIS
		-- de confirmar (via disco, não suposição de timing) que o servidor 1 já abriu a sessão.
		local server2 = process.exec("lune", runFixture())

		assert(
			server2.ok,
			`servidor 2 deveria sair com sucesso (code {server2.code}) -- stdout: {server2.stdout} stderr: {server2.stderr}`
		)
		assert(
			string.find(server2.stdout, "SCENARIO_MARK: server2-start", 1, true) ~= nil,
			`esperava o servidor 2 ter tomado o RAMO de servidor 2 (deveria ver "Role" já gravado pelo servidor 1) -- stdout: {server2.stdout}`
		)
		assert(
			string.find(server2.stdout, "SCENARIO_MARK: server2-no-steal-acquired=false", 1, true) ~= nil,
			`servidor 2 NÃO deveria ter conseguido a sessão sem Steal=true enquanto o servidor 1 (JobId diferente) ainda está com ela aberta -- trava de sessão real violada -- stdout: {server2.stdout}`
		)
		assert(
			string.find(server2.stdout, "SCENARIO_MARK: server2-steal-acquired=true", 1, true) ~= nil,
			`servidor 2 deveria ter conseguido a sessão IMEDIATAMENTE com Steal=true (fixture: "steal_session == true or user_steal == true" bypassa a espera de SESSION_STEAL) -- stdout: {server2.stdout}`
		)
	end)

	-- SEMPRE espera o servidor 1 terminar e recolhe seu stdout, sucesso ou falha do bloco acima --
	-- nunca deixa um processo `lune` pendurado em background, e o stdout dele entra no diagnóstico
	-- de uma falha upstream mesmo quando o problema não era dele.
	local status1 = server1:status()
	local stdout1Ok, stdout1 = pcall(function()
		return server1.stdout:readToEnd()
	end)

	if not ok then
		error(`{tostring(err)}\n       [diagnóstico servidor 1] status={status1.code} stdout={if stdout1Ok then stdout1 else "<falhou ao ler>"}`)
	end

	assert(status1.ok, `servidor 1 deveria sair com sucesso (code {status1.code}) -- stdout: {if stdout1Ok then stdout1 else "<falhou ao ler>"}`)
	assert(stdout1Ok, "falha ao ler stdout do servidor 1 depois dele terminar")
	assert(
		string.find(stdout1, "SCENARIO_MARK: server1-session-active", 1, true) ~= nil,
		`esperava o servidor 1 ter confirmado sessão ativa -- stdout: {stdout1}`
	)
	-- INFORMATIVO, não uma asserção de PASS/FAIL deste teste: se o servidor 1 detecta que perdeu a
	-- sessão (via re-validação própria do ProfileStore, fora do escopo verificado aqui) é um bônus,
	-- não um requisito -- a garantia que este cenário prova é a TRAVA (servidor 2 não rouba sem
	-- Steal, rouba com Steal), não a notificação de volta ao servidor que perdeu.
	local lostActiveMatch = string.find(stdout1, "stillActiveAfterHold=false", 1, true)
	print(`       [informativo] servidor 1 detectou perda da sessão depois do Steal do servidor 2? {tostring(lostActiveMatch ~= nil)}`)
end)

cleanCloudState()

print(`\n{passedCount}/{totalCount} testes passaram ({failedCount} falharam)`)

if failedCount > 0 then
	process.exit(1)
end
