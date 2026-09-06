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
-- Status: passa hoje -- documentando tanto o comportamento CORRIGIDO (achado 1) quanto um BUG
-- REAL novo e confirmado (achado 2, território `cli`) e uma limitação de cobertura ainda aberta
-- (achado 3, território `services`, já esperada). Ver comentários de cada teste abaixo.

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

	-- Os outros 2 erros legítimos remanescentes (paridade com `real-roblox-games-pipeline-smoke`,
	-- território services/runtime -- fidelidade correta com o Roblox real atual, não bugs):
	assert(
		string.find(result.stderr, "SoundService", 1, true) ~= nil
			and string.find(result.stderr, "materialize/service-not-simulated", 1, true) ~= nil,
		`esperava "SoundService" reportado como ainda não simulado, recebeu: {result.stderr}`
	)
	assert(
		string.find(result.stderr, "FilteringEnabled", 1, true) ~= nil and string.find(result.stderr, "read only", 1, true) ~= nil,
		`esperava "Workspace.FilteringEnabled" reportado como somente-leitura (fidelidade correta, propriedade deprecada), recebeu: {result.stderr}`
	)

	-- Baseline inalterado: o script real do servidor continua rodando.
	assert(
		string.find(result.stdout, "Hello world, from server!", 1, true) ~= nil,
		`esperava o script real do servidor ter rodado, recebeu stdout: {result.stdout}`
	)
	assert(result.code == 2, `esperava ExitCode 2 (2 erros legítimos remanescentes -- SoundService/Part/FilteringEnabled), recebeu {result.code} (stdout: {result.stdout} stderr: {result.stderr})`)
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
	-- Achado 3 -- BUG REAL NOVO, CONFIRMADO, território `cli` (`src/cli/TreeMaterializer.luau`,
	-- função `resolvePropertyValue`). NÃO escondido -- documentado aqui como comportamento ATUAL
	-- (o assert abaixo captura o que a bancada observou rodando o binário real, não uma suposição).
	--
	-- `resolvePropertyValue` (linhas ~280-284) trata QUALQUER `raw` cujo `typeof` seja
	-- "boolean"/"number"/"string" como primitivo e grava DIRETO, sem consultar o `ValueCategory`
	-- do `MemberDescriptor` da propriedade. Isso é CORRETO para uma property realmente primitiva
	-- (ex.: `Lighting.TimeOfDay = "14:00:00"`, uma string de verdade) mas ERRADO para uma property
	-- `ValueCategory == "Enum"` expressa como string -- o formato Rojo PADRÃO para Enum via
	-- `$properties` (confirmado por `src/valuetypes/Decode.spec.luau`, "string com alvo Enum ->
	-- EnumItem", e é exatamente como `StarterPlayer.CameraMode = "LockFirstPerson"` está escrito
	-- nesta fixture). O `rawKind == "string"` do início da função faz `return raw` ANTES de a
	-- função sequer chegar no bloco que consultaria `descriptor.ValueCategory == "Enum"` e chamaria
	-- `ValueTypes.Decode.FromRojoJson` -- ou seja, o branch de decode de Enum (linhas ~318-333)
	-- nunca é alcançado quando o valor bruto já É uma string.
	--
	-- Consequência observada (reproduzida rodando o binário real, não inferida por leitura de
	-- código): `StarterPlayer.CameraMode` termina com uma STRING Lua crua ("LockFirstPerson") em
	-- vez de um `EnumItem` (`Enum.CameraMode.LockFirstPerson`) -- `typeof()` mente (devolve
	-- "string" em vez de "EnumItem", divergência de FIDELIDADE com o Roblox real, regra 00) e
	-- `== Enum.CameraMode.LockFirstPerson` nunca bate. NENHUM erro/warning é emitido -- é uma
	-- CORRUPÇÃO SILENCIOSA de tipo, exatamente a categoria de bug que o comentário da própria
	-- função diz querer evitar ("um array cru escrito direto num Vector3/Color3 real seria a
	-- corrupção silenciosa que a invariante 2 do projeto proíbe") -- só que o mesmo raciocínio não
	-- foi estendido ao caso "string crua escrita direto num Enum real".
	--
	-- Alcance provável (por leitura de código, NÃO testado nesta rodada -- sinalizado como
	-- hipótese, não fato confirmado): o MESMO `rawKind == "number"` early-return sugere que um
	-- Enum property setado por VALOR numérico (`Value`) em vez de nome, outro formato válido de
	-- Rojo, teria o mesmo problema -- vale confirmar numa tarefa de fix, não assumido aqui como
	-- comprovado.
	--
	-- Impacto real: `Enum` via `$properties` é um padrão MUITO comum em projetos Rojo reais
	-- (`Part.Material`, `Lighting.LightingStyle`, `StarterPlayer.CameraMode`, etc. -- mais comum,
	-- inclusive, que Vector3/Color3 via array) -- qualquer projeto real que configure uma
	-- propriedade Enum via `$properties` recebe hoje um valor com tipo ERRADO na árvore
	-- materializada, sem nenhum diagnóstico. Recomendo tarefa de fix em `cli`.
	-- ------------------------------------------------------------------------------------------
	assert(
		string.find(
			result.stdout,
			'[FIXTURE-FAIL] StarterPlayer.CameraMode é um EnumItem de verdade (typeof), igual a Enum.CameraMode.LockFirstPerson',
			1,
			true
		) ~= nil,
		`BUG CONFIRMADO (achado 3, território cli) esperado no stdout -- se este assert falhar, o bug foi CORRIGIDO: atualize este teste para esperar "[FIXTURE-PASS]" em vez de "[FIXTURE-FAIL]". Recebeu stdout: {result.stdout}`
	)
	assert(
		string.find(result.stdout, 'recebeu string', 1, true) ~= nil,
		`esperava a mensagem do FIXTURE-FAIL citar "recebeu string" (typeof mentiu -- deveria ser EnumItem), recebeu stdout: {result.stdout}`
	)
	assert(
		string.find(result.stdout, "[FIXTURE-SUMMARY] 7/8 verificações passaram, 1 falharam", 1, true) ~= nil,
		`esperava o resumo da fixture confirmar 7/8 (só a checagem de Enum via $properties falha hoje), recebeu stdout: {result.stdout}`
	)

	assert(string.find(result.stderr, "stack traceback", 1, true) == nil, "stack trace cru do Lune vazou pro usuário")
end)

print(`{passedCount}/{totalCount} cenários de value-types passaram, {failedCount} falharam`)

if failedCount > 0 then
	process.exit(1)
end
