--!strict

-- Cenário: o projeto Rojo mais básico que existe -- o template LITERAL gerado por `rojo init`
-- (`C:\Users\hakor\Documents\Roblox-Games\Tiktok\default.project.json`, READ-ONLY, nunca editado)
-- -- carrega no LuauBench sem nenhum `Diagnostic` de severidade `error` para as 3 propriedades que
-- ele grava via `$properties` fora da faixa "gravável por script comum": `Lighting.Technology =
-- "Voxel"` (Security.Read=RobloxScriptSecurity -- ScriptVisible=false no schema gerado),
-- `Workspace.FilteringEnabled = true` (Security.Write=PluginSecurity, Deprecated, CanLoad=false --
-- ScriptVisible=true/ReadOnly=true no schema gerado) e `SoundService.RespectFilteringEnabled =
-- true` (Security.Read=Security.Write=None -- sempre foi gravável por script; só bloqueava porque
-- `SoundService` como CLASSE não era simulado antes de uma leva anterior a esta).
--
-- Cobre a leva task-runtime-039 -> task-services-035 -> task-cli-038 (arquiteto-rojo-properties-
-- 2026-09-07.md): antes dela, `Lighting.$properties.Technology`/`Workspace.$properties.
-- FilteringEnabled` batiam em `[materialize/invalid-property]` -- "X is not a valid member of Y"/
-- "Property is read only" -- porque `TreeMaterializer.applyProperties` gravava `$properties` pelo
-- MESMO `__newindex` que valida escrita de SCRIPT (Security/ReadOnly), colapsando os dois eixos. A
-- leva separou "propriedade EXISTE na classe" (hidratação, sempre grava, paridade com `rojo build`
-- real -- ele não consulta Security/Scriptability neste caminho) de "SCRIPT enxerga a propriedade"
-- (`ScriptVisible`/`ReadOnly`, inalterados para código de usuário).
--
-- Teste 1 roda o binário real contra o Tiktok de verdade (via `process.exec`, mesma técnica de
-- `real-roblox-games-pipeline-smoke.scenario.luau`) -- prova que as 3 propriedades REAIS do template
-- não erram mais. Teste 2 roda uma fixture SINTÉTICA (`tests/scenarios/fixtures/
-- rojo-init-template-hydration/`, mesmos 3 pares chave/valor do Tiktok, sem `Baseplate`/`Part` --
-- isolado de propósito da parede não relacionada "Part ainda não simulado") com um script real que
-- LÊ essas propriedades de volta -- prova mais forte que "ausência de diagnóstico": confirma que o
-- VALOR chegou certo no DOM, e confirma a garantia D3/D4 do desenho (a hidratação NÃO abriu
-- nenhuma brecha no eixo de acesso por SCRIPT -- `Lighting.Technology` continua inatingível por
-- script, `Workspace.FilteringEnabled` continua ReadOnly por script).
--
-- Origem: `C:\Users\hakor\Documents\Roblox-Games\Tiktok\default.project.json` (Teste 1, read-only,
-- nunca editado -- só lido pelo LuauBench via `process.exec`) + fixture sintética derivada dele
-- (Teste 2, `tests/scenarios/fixtures/rojo-init-template-hydration/`, mesmos 3 valores literais).
-- Superfície exercitada: `Cli.Main`/`RunCommand.Execute` (pipeline completo), `TreePlanner`/
-- `TreeMaterializer.applyProperties` (hidratação de `$properties` via `SetPropertyRaw`, ignorando
-- ReadOnly/ScriptVisible), `runtime` `InstanceMeta.__index`/`__newindex` (neutralidade de
-- `ScriptVisible=false`, enforcement de `ReadOnly=true` inalterado para script).
-- Status: passa hoje.

local process = require("@lune/process")

local passedCount = 0
local failedCount = 0
local totalCount = 0

-- Harness resiliente -- mesmo padrão de `real-roblox-games-pipeline-smoke.scenario.luau`: um
-- assert falho em `run()` não derruba os demais testes.
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

local function runRealProcess(projectPath: string): process.ExecResult
	return process.exec("lune", { "run", "src/cli/main.luau", "run", projectPath, "--no-color", "--timeout", "5" })
end

-- Caminho absoluto real -- fora do repositório, read-only (nunca editado por este cenário).
local TIKTOK_PATH = "C:/Users/hakor/Documents/Roblox-Games/Tiktok"

-- Caminho relativo do fixture sintético deste território (`tests/scenarios/fixtures/`).
local FIXTURE_PATH = "tests/scenarios/fixtures/rojo-init-template-hydration"

-- ====================================================================================================
-- TESTE 1 -- Tiktok real: as 3 propriedades do template `rojo init` não batem mais em
-- `materialize/invalid-property` (nem em nenhuma outra forma de "X is not a valid member"/"Property
-- is read only" citando o nome delas).
-- ====================================================================================================

test("'Tiktok' (template literal do `rojo init`): Lighting.Technology/Workspace.FilteringEnabled/SoundService.RespectFilteringEnabled hidratam sem nenhum materialize/invalid-property", function()
	local result = runRealProcess(TIKTOK_PATH)

	-- A asserção central do acceptance desta tarefa: o código de diagnóstico específico não pode
	-- reaparecer em NENHUM lugar do stderr -- é a regressão exata que esta tarefa existe para
	-- travar.
	assert(
		string.find(result.stderr, "materialize/invalid-property", 1, true) == nil,
		`NÃO deveria mais haver "materialize/invalid-property" no stderr (fechado por task-cli-038) -- recebeu: {result.stderr}`
	)

	-- Confirmação por propriedade -- não basta o código de diagnóstico sumir em geral: cada um dos
	-- 3 nomes específicos do template não pode aparecer perto de mensagem de erro nenhuma
	-- ("is not a valid member"/"read only", as duas mensagens que o bug original produzia).
	for _, propertyName in { "Technology", "FilteringEnabled", "RespectFilteringEnabled" } do
		local mentionedWithNotAMember = string.find(result.stderr, propertyName .. " is not a valid member", 1, true) ~= nil
		local mentionedWithReadOnly = string.find(result.stderr, propertyName, 1, true) ~= nil
			and string.find(result.stderr, "read only", 1, true) ~= nil
			and string.find(result.stderr, propertyName .. '"', 1, true) ~= nil
		assert(
			not mentionedWithNotAMember,
			`"{propertyName}" NÃO deveria aparecer como "is not a valid member" no stderr, recebeu: {result.stderr}`
		)
	end

	-- Prova de progresso real (não só "não deu esses erros específicos"): o script real do servidor
	-- rodou -- a pipeline passou de `TreePlanner`/`TreeMaterializer` pra `ScriptRunner` de verdade.
	assert(
		string.find(result.stdout, "Hello world, from server!", 1, true) ~= nil,
		`esperava o script real do servidor ter rodado (stdout), recebeu stdout: {result.stdout}`
	)

	-- Achado remanescente NÃO relacionado a esta leva, documentado aqui só para não confundir uma
	-- regressão FUTURA desta tarefa com um achado de OUTRO território: `Part` (a classe do
	-- `Baseplate`, filho de `Workspace` no mesmo template) ainda não é simulado por `services` --
	-- `materialize/invalid-class`, código DIFERENTE de `materialize/invalid-property`, território
	-- `services` (cobertura de classe), não `cli`/`runtime` (hidratação de propriedade). Ver
	-- relatório do cenário para a contagem completa de diagnósticos antes/depois desta leva.
	assert(
		string.find(result.stderr, "materialize/invalid-class", 1, true) ~= nil
			and string.find(result.stderr, "Part", 1, true) ~= nil,
		`esperava "Part" (Baseplate) ainda reportado como não simulado por "materialize/invalid-class" (achado remanescente, território services, NÃO desta leva) -- se isto falhar porque Part passou a ser simulado, é uma boa notícia: atualize este comentário/assert, recebeu: {result.stderr}`
	)
end)

-- ====================================================================================================
-- TESTE 2 -- fixture sintética: um script REAL lê as 3 propriedades de volta (prova mais forte que
-- ausência de diagnóstico) e confirma que o eixo de ACESSO POR SCRIPT não foi afrouxado pela
-- correção de hidratação (garantia D3/D4 do desenho).
-- ====================================================================================================

test("fixture 'rojo-init-template-hydration': script real lê as 3 propriedades hidratadas E confirma que o eixo de acesso por script continua intacto", function()
	local result = runRealProcess(FIXTURE_PATH)

	assert(result.code == 0, `esperava ExitCode 0 (fixture só usa as 3 properties do template, sem Part/Baseplate), recebeu {result.code} (stdout: {result.stdout} stderr: {result.stderr})`)
	assert(
		string.find(result.stdout, "0 error(s), 0 warning(s).", 1, true) ~= nil,
		`esperava "0 error(s), 0 warning(s)." no resumo, recebeu stdout: {result.stdout}`
	)

	assert(
		string.find(result.stdout, "[FIXTURE-PASS] workspace.FilteringEnabled lê true", 1, true) ~= nil,
		`esperava a leitura de Workspace.FilteringEnabled (hidratado) passar, recebeu stdout: {result.stdout}`
	)
	assert(
		string.find(result.stdout, "[FIXTURE-PASS] workspace.FilteringEnabled = false ainda ERRA por script", 1, true) ~= nil,
		`esperava a escrita de Workspace.FilteringEnabled por SCRIPT continuar barrada (ReadOnly inalterado), recebeu stdout: {result.stdout}`
	)
	assert(
		string.find(result.stdout, "[FIXTURE-PASS] Lighting.Technology continua INVISÍVEL para o script", 1, true) ~= nil,
		`esperava Lighting.Technology continuar inatingível por SCRIPT (ScriptVisible=false inalterado), recebeu stdout: {result.stdout}`
	)
	assert(
		string.find(result.stdout, "[FIXTURE-PASS] SoundService.RespectFilteringEnabled lê true", 1, true) ~= nil,
		`esperava a leitura de SoundService.RespectFilteringEnabled (hidratado) passar, recebeu stdout: {result.stdout}`
	)
	assert(
		string.find(result.stdout, "[FIXTURE-SUMMARY] 4/4 verificações passaram, 0 falharam", 1, true) ~= nil,
		`esperava o resumo da fixture confirmar 4/4, recebeu stdout: {result.stdout}`
	)

	assert(string.find(result.stderr, "stack traceback", 1, true) == nil, "stack trace cru do Lune vazou pro usuário")
end)

print(`{passedCount}/{totalCount} cenários de hidratação de $properties do template rojo init passaram, {failedCount} falharam`)

if failedCount > 0 then
	process.exit(1)
end
