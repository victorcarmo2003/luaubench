--!strict

-- Cenário: confirma que a leva 1 de `valuetypes` + a ponte `cli` (task-cli-025) eliminaram os 4
-- warnings `plan/non-primitive-property` que o projeto REAL "Tiktok" emitia (Ambient/Position/
-- Color/Size -- os ÚNICOS contatos reais com value types que a bancada já tinha observado, ver
-- `.claude/agents-memory/testador-roblox-games-2026-09-05.md`), e que os valores materializados
-- são tipados corretamente onde a classe dona já é coberta por `services`. Roda também um script
-- de usuário REAL dentro do sandbox exercitando Vector3/CFrame/Color3/Enum -- primeira vez que a
-- pendência do item 5 daquele relatório ("falso positivo de sandbox nunca foi testável porque
-- nenhum script de usuário que usasse esses tipos chegava a rodar") é de fato testável.
--
-- Origem:
--   - Teste 1: "Tiktok" real, C:\Users\hakor\Documents\Roblox-Games\Tiktok (read-only, nunca
--     editado -- só o `default.project.json`/scripts são lidos pelo LuauBench via `process.exec`).
--   - Teste 2: fixture SINTÉTICA `tests/scenarios/fixtures/value-types-project/` (`$properties`
--     com os MESMOS valores literais que a Baseplate/Lighting do "Tiktok" usam para
--     Position/Color/Ambient, mas aplicados a classes JÁ cobertas por `services`
--     (Workspace/Lighting/StarterPlayer) -- necessário porque `Part` (a classe do Baseplate)
--     AINDA não é simulada, então não dá pra ler de volta Baseplate.Position/Size/Color pela
--     árvore materializada do "Tiktok" nesta rodada, ver achado 2 abaixo) + um script de servidor
--     real que lê essas propriedades de volta e também constrói/opera Vector3/CFrame/Color3/Enum
--     por conta própria (`tests/scenarios/fixtures/value-types-project/src/server/init.server.luau`).
-- Superfície exercitada: `RunCommand`/`TreePlanner`/`TreeMaterializer` (plan/materialize de
-- `$properties` primitivo vs. array vs. string-de-enum), `valuetypes` (`Decode.FromRojoJson`,
-- globais `Vector3`/`CFrame`/`Color3`/`Enum` injetados no sandbox), `runtime` `Sandbox`
-- (`typeof` fiel dentro do script real).
-- Status: passa hoje -- documentando tanto o comportamento CORRIGIDO (achado 1) quanto uma
-- limitação de cobertura ainda aberta (achado 2, território `services`, já esperada). Ver
-- comentários de cada teste abaixo.
--
-- ATUALIZAÇÃO 2026-09-07 (task-test-rojo-properties-001, verificação de rotina ao reexecutar
-- `real-roblox-games-pipeline-smoke.scenario.luau` -- ver `.claude/agents-memory/
-- arquiteto-rojo-properties-2026-09-07.md` para a leva que motivou a rodada): este cenário estava
-- com 2 asserções desatualizadas, por causas TOTALMENTE independentes da leva de `$properties`/
-- Security -- atualizadas aqui como manutenção de rotina de território (mesmo aviso já registrado
-- em `real-roblox-games-pipeline-smoke.scenario.luau`), não como parte do trabalho daquela leva:
--   - Teste 1 ('Tiktok'): o assert de "SoundService ainda não simulado"/"FilteringEnabled somente-
--     leitura" ficou obsoleto -- `SoundService` passou a ser coberto por `services` numa leva
--     anterior (commit `ad83d97`) e `Workspace.FilteringEnabled` hidrata sem erro desde
--     task-cli-038 (ver `rojo-init-template-hydration.scenario.luau` para a prova dedicada). Único
--     erro remanescente contra o Tiktok real: `Part` (Baseplate) ainda não simulado.
--   - Teste 2 (achado 3, fixture): o bug de `Enum` via `$properties` virando string crua (em vez de
--     `EnumItem`) JÁ FOI CORRIGIDO -- `git log -- src/cli/TreeMaterializer.luau` confirma
--     `9ea5cef fix(cli): decode Enum via \$properties instead of writing raw string`, task
--     independente (task-cli-027) escrita bem antes desta leva. `StarterPlayer.CameraMode` agora
--     resolve como `EnumItem` de verdade -- o teste foi atualizado de "FIXTURE-FAIL esperado" para
--     "FIXTURE-PASS esperado" (8/8), e o achado 3 (antes documentado como bug aberto) foi removido
--     do comentário do teste -- mantido só aqui, no cabeçalho, como histórico.

local process = require("@lune/process")

local passedCount = 0
local failedCount = 0
local totalCount = 0

-- Harness resiliente -- mesmo padrão corrigido em `real-roblox-games-pipeline-smoke.scenario.luau`
-- (Parte 1 do relatório de contexto): um assert falho em `run()` NÃO pode derrubar os demais
-- testes -- cada um roda isolado via `pcall`, reporta `[FAIL]` com a mensagem, e o script continua.
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
local FIXTURE_PATH = "tests/scenarios/fixtures/value-types-project"

-- ====================================================================================================
-- TESTE 1 -- "Tiktok" real: os 4 warnings antigos sumiram, e o PORQUÊ de cada um sumir é verificado
-- individualmente (não basta "não aparece mais" -- alguns sumiram pelo motivo CERTO, um sumiu por um
-- motivo que não prova nada ainda, ver comentário dentro do teste).
-- ====================================================================================================

test("'Tiktok': os 4 warnings 'plan/non-primitive-property' (Ambient/Position/Color/Size) sumiram do stderr", function()
	local result = runRealProcess(TIKTOK_PATH)

	-- Achado 1 (POSITIVO, confirmado): nenhum warning `plan/non-primitive-property` aparece mais em
	-- lugar nenhum -- os 4 contatos reais com value types que a bancada tinha documentado em
	-- 2026-09-05 (Ambient/Position/Color/Size) não emitem mais esse warning específico.
	assert(
		string.find(result.stderr, "plan/non-primitive-property", 1, true) == nil,
		`NÃO deveria mais haver "plan/non-primitive-property" no stderr, recebeu: {result.stderr}`
	)
	assert(
		string.find(result.stdout, "0 warning(s)", 1, true) ~= nil,
		`esperava "0 warning(s)" no resumo final, recebeu stdout: {result.stdout}`
	)

	-- Achado 1a (POSITIVO, confirmado): `Lighting.Ambient` -- a ÚNICA das 4 propriedades cuja classe
	-- dona (`Lighting`) já é coberta por `services` -- não produz NENHUM diagnóstico (nem warning nem
	-- error) em stderr. Ausência total de diagnóstico é o sinal esperado de sucesso silencioso (a
	-- propriedade foi decodificada e escrita sem erro) -- confirmado de forma mais forte no Teste 2
	-- abaixo, onde um script real lê esse MESMO formato de volta e confere o tipo/valor exatos.
	assert(
		string.find(result.stderr, "Ambient", 1, true) == nil,
		`"Ambient" NÃO deveria aparecer em nenhum diagnóstico de stderr (decode bem-sucedido), recebeu: {result.stderr}`
	)

	-- Achado 2 (BUG DE COBERTURA JÁ CONHECIDO, território `services`, não `cli`/`valuetypes` --
	-- mantido em paridade com `real-roblox-games-pipeline-smoke.scenario.luau`): `Part` (a classe do
	-- `Baseplate`) AINDA não é simulada por `services` (`Covered = false` em
	-- `src/services/generated/Manifest.luau`). Isso importa aqui porque é a explicação CORRETA de
	-- por que os outros 3 warnings antigos (Position/Color/Size, todos properties do Baseplate)
	-- também sumiram: NÃO é porque o decode de Vector3/Color3 rodou com sucesso sobre o Baseplate --
	-- é porque `TreeMaterializer.materializeNode` pula a subárvore INTEIRA (incluindo `$properties`)
	-- quando `createInstance` falha (`Part` não simulado bate em `materialize/invalid-class` ANTES de
	-- `applyProperties` rodar -- ver `TreeMaterializer.luau`, função `materializeNode`, linhas
	-- ~570-586: `applyProperties` só é chamado se `createInstance` devolveu uma Instance não-nil).
	-- Ou seja: o warning sumiu, mas a pergunta "Position/Color/Size decodificam certo quando a classe
	-- dona existe?" continua SEM RESPOSTA a partir do "Tiktok" sozinho -- é exatamente o que o Teste
	-- 2 abaixo responde (com Vector3/Color3 nos MESMOS valores literais, sobre classes cobertas).
	assert(
		string.find(result.stderr, "materialize/invalid-class", 1, true) ~= nil
			and string.find(result.stderr, "Baseplate", 1, true) ~= nil
			and string.find(result.stderr, "Part", 1, true) ~= nil,
		`esperava "Part"/"Baseplate" reportados como ainda não simulados por "materialize/invalid-class" (achado 2, território services), recebeu: {result.stderr}`
	)

	-- ATUALIZAÇÃO 2026-09-07 (ver "ATUALIZAÇÃO 2026-09-07" no cabeçalho do arquivo): os 2 asserts
	-- abaixo esperavam "SoundService"/"FilteringEnabled" como erros remanescentes -- DESATUALIZADO.
	-- `SoundService` já é coberto por `services` (leva anterior, não relacionada) e
	-- `Workspace.FilteringEnabled` hidrata sem erro desde task-cli-038. Único erro legítimo
	-- remanescente contra o Tiktok real hoje: `Part` (Baseplate) ainda não simulado.
	assert(
		string.find(result.stderr, "SoundService", 1, true) == nil,
		`"SoundService" NÃO deveria mais aparecer em nenhum diagnóstico (classe coberta por services), recebeu: {result.stderr}`
	)
	assert(
		string.find(result.stderr, "FilteringEnabled", 1, true) == nil,
		`"FilteringEnabled" NÃO deveria mais aparecer em nenhum diagnóstico (hidratação bypassa ReadOnly desde task-cli-038), recebeu: {result.stderr}`
	)
	assert(
		string.find(result.stderr, "materialize/invalid-class", 1, true) ~= nil and string.find(result.stderr, "Part", 1, true) ~= nil,
		`esperava "Part" (Baseplate) reportado como ainda não simulado por "materialize/invalid-class" (único erro legítimo remanescente), recebeu: {result.stderr}`
	)

	-- Baseline inalterado: o script real do servidor continua rodando.
	assert(
		string.find(result.stdout, "Hello world, from server!", 1, true) ~= nil,
		`esperava o script real do servidor ter rodado, recebeu stdout: {result.stdout}`
	)
	assert(result.code == 2, `esperava ExitCode 2 (1 erro legítimo remanescente -- Part/Baseplate), recebeu {result.code} (stdout: {result.stdout} stderr: {result.stderr})`)
end)

-- ====================================================================================================
-- TESTE 2 -- fixture sintética: confirma com um script REAL (rodando via o binário real, dentro do
-- sandbox de execução, NUNCA chamada in-process) que Vector3/Color3 aplicados por `$properties`
-- viram value types de verdade (não tabela crua) quando a classe dona é coberta, e que Vector3/
-- CFrame/Color3/Enum construídos/operados DENTRO do script funcionam. Revela também um BUG REAL
-- novo (achado 3, território `cli`) para o caso de Enum via `$properties`.
-- ====================================================================================================

test("fixture 'value-types-project': script real confirma Vector3/Color3/CFrame na árvore materializada e operados no sandbox", function()
	local result = runRealProcess(FIXTURE_PATH)

	-- A fixture não usa nenhuma classe/propriedade não-coberta de propósito -- deveria terminar
	-- limpa (0 erro, 0 warning, o script roda até o fim e imprime seu resumo).
	assert(result.code == 0, `esperava ExitCode 0 (fixture só usa classes/properties cobertas), recebeu {result.code} (stdout: {result.stdout} stderr: {result.stderr})`)
	assert(
		string.find(result.stdout, "0 error(s), 0 warning(s).", 1, true) ~= nil,
		`esperava "0 error(s), 0 warning(s)." no resumo, recebeu stdout: {result.stdout}`
	)

	-- Achado 1a confirmado de forma FORTE (não só "ausência de diagnóstico" como no Teste 1): o
	-- script real leu `workspace.GlobalWind`/`Lighting.Ambient` de volta e confirmou
	-- `typeof(...) == "Vector3"/"Color3"` com os componentes exatos vindos do `$properties`
	-- (mesmos valores literais do Position/Color reais do Baseplate do "Tiktok" -- ver fixture).
	assert(
		string.find(result.stdout, "[FIXTURE-PASS] workspace.GlobalWind é um Vector3 de verdade", 1, true) ~= nil,
		`esperava a checagem de Vector3 via $properties passar, recebeu stdout: {result.stdout}`
	)
	assert(
		string.find(result.stdout, "[FIXTURE-PASS] Lighting.Ambient é um Color3 de verdade", 1, true) ~= nil,
		`esperava a checagem de Color3 via $properties passar, recebeu stdout: {result.stdout}`
	)

	-- Pendência do item 5 do relatório de 2026-09-05 FECHADA: um script de usuário real, rodando
	-- dentro do sandbox de execução de verdade (não `require` in-process de um `.spec.luau`),
	-- constrói e opera Vector3/CFrame/Color3/Enum sem vazamento nem `nil` inesperado.
	assert(
		string.find(result.stdout, "[FIXTURE-PASS] Vector3.new + Vector3.new soma corretamente", 1, true) ~= nil,
		`esperava Vector3 construído/operado no sandbox passar, recebeu stdout: {result.stdout}`
	)
	assert(
		string.find(result.stdout, "[FIXTURE-PASS] CFrame.new(pos) * CFrame.new(pos) compõe translação corretamente", 1, true) ~= nil,
		`esperava CFrame construído/operado no sandbox passar, recebeu stdout: {result.stdout}`
	)
	assert(
		string.find(result.stdout, "[FIXTURE-PASS] CFrame + Vector3 translada", 1, true) ~= nil,
		`esperava CFrame + Vector3 no sandbox passar, recebeu stdout: {result.stdout}`
	)
	assert(
		string.find(result.stdout, "[FIXTURE-PASS] Color3.new: tostring no formato 'R, G, B'", 1, true) ~= nil,
		`esperava Color3.new/tostring no sandbox passar, recebeu stdout: {result.stdout}`
	)
	assert(
		string.find(result.stdout, "[FIXTURE-PASS] Enum: navegação Enum.<Nome>.<Item>, FromName e GetEnumItems funcionam de dentro do sandbox", 1, true) ~= nil,
		`esperava Enum navegado/operado no sandbox passar, recebeu stdout: {result.stdout}`
	)

	-- ------------------------------------------------------------------------------------------
	-- Achado 3 (HISTÓRICO -- FECHADO, ver "ATUALIZAÇÃO 2026-09-07" no cabeçalho do arquivo): esta
	-- fixture já capturou aqui um bug real de `src/cli/TreeMaterializer.luau` (`resolvePropertyValue`
	-- tratava QUALQUER `raw` string como primitivo, sem consultar `ValueCategory == "Enum"" do
	-- `MemberDescriptor` -- `StarterPlayer.CameraMode = "LockFirstPerson"` terminava como STRING Lua
	-- crua em vez de `EnumItem`, `typeof()` mentindo, `== Enum.CameraMode.LockFirstPerson` nunca
	-- batendo, sem nenhum diagnóstico). Corrigido por `9ea5cef fix(cli): decode Enum via
	-- \$properties instead of writing raw string` (task-cli-027, independente desta leva de
	-- `$properties`/Security) -- confirmado rodando o binário real: `StarterPlayer.CameraMode`
	-- resolve como `EnumItem` de verdade agora. Assert abaixo atualizado de "FIXTURE-FAIL esperado"
	-- para "FIXTURE-PASS esperado" (8/8).
	-- ------------------------------------------------------------------------------------------
	assert(
		string.find(
			result.stdout,
			'[FIXTURE-PASS] StarterPlayer.CameraMode é um EnumItem de verdade (typeof), igual a Enum.CameraMode.LockFirstPerson',
			1,
			true
		) ~= nil,
		`esperava a checagem de Enum via $properties passar (bug fechado por task-cli-027) -- se este assert falhar, pode ser uma REGRESSÃO real: recebeu stdout: {result.stdout}`
	)
	assert(
		string.find(result.stdout, "[FIXTURE-SUMMARY] 8/8 verificações passaram, 0 falharam", 1, true) ~= nil,
		`esperava o resumo da fixture confirmar 8/8 (todas as checagens passam, incluindo Enum via $properties), recebeu stdout: {result.stdout}`
	)

	assert(string.find(result.stderr, "stack traceback", 1, true) == nil, "stack trace cru do Lune vazou pro usuário")
end)

print(`{passedCount}/{totalCount} cenários de value-types passaram, {failedCount} falharam`)

if failedCount > 0 then
	process.exit(1)
end
