--!strict

-- Cenário: rodar `luaubench run` (processo real: `lune run src/cli/main.luau run <path>`) contra
-- 3 projetos Roblox REAIS do usuário (fora do repositório) -- primeira rodada de teste ponta a
-- ponta do pipeline completo (ProjectFile -> TreePlanner -> TreeMaterializer -> ScriptRunner)
-- contra código de produção de verdade, não fixture sintética. Objetivo: confirmar que o comando
-- roda, dá erro claro/acionável (nunca crash cru), e documentar ONDE cada projeto bate a primeira
-- parede.
-- Origem: 3 caminhos reais em C:\Users\hakor\Documents\Roblox-Games (read-only, NUNCA copiados
-- nem editados -- só os `default.project.json`/scripts de cada um são lidos pelo LuauBench via
-- `process.exec`):
--   - Tiktok (3 arquivos .luau, 80K) -- o projeto Rojo "default" (rojo init) com Baseplate/
--     Lighting/SoundService padrão.
--   - "Panic - CHESSS" (30 arquivos .luau, 846K) -- jogo de xadrez real com framework Modux
--     próprio (src/server/Services/*, src/shared/Chess/*).
--   - TheGame (310 arquivos .luau, 3.3M) -- projeto maior, com dependências Wally
--     (Packages/ServerPackages) não instaladas neste checkout.
-- Superfície exercitada: `Cli.Main`/`RunCommand.Execute` (pipeline `luaubench run` completo),
-- `TreePlanner` (resolução de ClassName, inferência de Service, `$properties`).
--
-- STATUS (task-cli-014 + task-cli-016, CORRIGIDO): o BUG GRAVE original -- os 3 projetos batendo
-- em `[plan/missing-class-name]` em "StarterPlayer.StarterPlayerScripts" ANTES de qualquer script
-- rodar -- está FECHADO (ver bloco de comentário logo abaixo, mantido como histórico). Os 3
-- projetos AVANÇAM de verdade pela pipeline -- 'Tiktok' e 'Panic - CHESSS' chegam a EXECUTAR o
-- script real do servidor -- e cada um bate numa parede LEGÍTIMA e DIFERENTE (Service/classe/
-- propriedade ainda não simulada, ou dependência Wally não instalada neste checkout), não mais na
-- inferência de ClassName do Rojo. Ver "Atualização 2026-09-05 (pós task-cli-016)" no final deste
-- comentário: a re-execução contra o binário real mostrou que a correção foi além do esperado --
-- `StarterPlayerScripts` não aparece MAIS EM NENHUM diagnóstico (nem `missing-class-name`, nem
-- `invalid-class`) -- o `LocalScript` de `StarterPlayerScripts.Client` é materializado e
-- corretamente listado como "not executed" (LuauBench roda como servidor). Os asserts abaixo
-- foram atualizados pra refletir isso.

local process = require("@lune/process")

local passedCount = 0
local failedCount = 0
local totalCount = 0

-- Harness resiliente (achado do `revisor-cli` em `task-cli-016`, corrigido aqui): antes, um
-- `assert` falho dentro de `run()` propagava pra fora de `test()` sem `pcall` -- derrubava o
-- script INTEIRO (`exit 1`, zero `[PASS]` impresso), então se o teste do 'Tiktok' quebrasse, os
-- testes de 'Panic - CHESSS'/'TheGame' nem chegavam a rodar (falso-negativo de cobertura: parecia
-- que 0 cenários rodaram, quando na verdade só 1 falhou). Agora cada teste roda isolado -- uma
-- falha é reportada com `[FAIL]` e a mensagem do assert, mas os próximos testes continuam.
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

local function runRealProcess(projectPath: string, extraArgs: { string }?): process.ExecResult
	local args = { "run", "src/cli/main.luau", "run", projectPath, "--no-color", "--timeout", "5" }
	if extraArgs ~= nil then
		for _, arg in extraArgs do
			table.insert(args, arg)
		end
	end
	return process.exec("lune", args)
end

-- Caminhos absolutos reais -- fora do repositório, read-only (nunca editados por este cenário).
local TIKTOK_PATH = "C:/Users/hakor/Documents/Roblox-Games/Tiktok"
local CHESS_PATH = "C:/Users/hakor/Documents/Roblox-Games/Panic - CHESSS"
local THEGAME_PATH = "C:/Users/hakor/Documents/Roblox-Games/TheGame"

--[[
	HISTÓRICO -- BUG GRAVE FECHADO por task-cli-014 (território `cli`, `src/cli/TreePlanner.luau` +
	`src/cli/SyncRules.luau`). Mantido aqui por completude/auditoria -- não é mais o comportamento
	atual, ver os 3 testes abaixo.

	Confirmado contra os 3 projetos reais abaixo E via inspeção (grep) de TODOS os 17
	`default.project.json` encontrados em Roblox-Games: todo projeto Rojo com a árvore padrão
	`StarterPlayer > StarterPlayerScripts` (SEM `$className` explícito no nó `StarterPlayerScripts`
	-- o padrão universal gerado por `rojo init` e replicado em todo projeto real do usuário)
	falhava em `TreePlanner.Plan` com `[plan/missing-class-name]`, ANTES de qualquer script do
	usuário rodar.

	CAUSA RAIZ (confirmada por leitura literal do código-fonte do Rojo,
	`pesquisa-formato-projeto-rojo-2026-09-05.md`, seção "Correção 2026-09-05"): a função real do
	Rojo (`infer_class_name`, `src/snapshot_middleware/project.rs`) tem 3 ramos `if`/`else if`
	MUTUAMENTE EXCLUSIVOS por `parentClassName` -- `TreePlanner.luau` só implementava 1 dos 3
	(`parentClassName == "DataModel"` -> Service reconhecido). Faltavam os outros 2, também
	hardcoded no Rojo real: `parentClassName == "StarterPlayer"` ->
	`"StarterPlayerScripts"`/`"StarterCharacterScripts"`; `parentClassName == "Workspace"` ->
	`"Terrain"`. Não era mudança de versão do Rojo -- os dois ramos faltantes existem desde
	`v6.0.0`/`v7.4.0-rc1` respectivamente, bem antes da versão fixada (`v7.7.0`); a pesquisa
	original simplesmente não reportou os dois `else if` seguintes da mesma função.

	CORREÇÃO (task-cli-014): `SyncRules.InferFixedChildClassName(parentClassName, name)` (dados
	puros, tabela `StarterPlayer -> {StarterPlayerScripts, StarterCharacterScripts}`,
	`Workspace -> {Terrain}`) somada ao ramo de Service já existente em `TreePlanner.luau`,
	resolvendo o `ClassName` no MESMO ponto e com a MESMA precedência (`$className` explícito >
	`$path` != Folder > inferência > `Folder` genérico > erro).

	IMPACTO ORIGINAL: 100% dos 17 projetos Rojo reais encontrados em Roblox-Games usavam esse
	padrão -- bloqueava a pipeline INTEIRA (nenhum script chegava a rodar) para praticamente
	qualquer projeto Roblox real.

	CORREÇÃO COMPLEMENTAR (task-cli-016): resolver o `ClassName` (task-cli-014) não bastava --
	`StarterPlayerScripts`/`StarterCharacterScripts`/`Terrain` são filhos FIXOS do motor (já
	existem no `DataModel` antes de qualquer script rodar, não são Services de verdade --
	`IsService = false` no dump). A materialização criava uma Instance NOVA e DUPLICADA em vez de
	adotar o filho fixo já existente, e essa criação batia em `materialize/invalid-class` (via
	pública bloqueada de propósito pra esses filhos). `task-cli-016` trocou "criar" por "adotar o
	filho fixo existente e aplicar `$path`/`$properties`/filhos nele" -- fechando essa segunda
	parede por completo, não só trocando o código do erro.
]]

test("FIXED (task-cli-014 + task-cli-016): 'Tiktok' (projeto Rojo 'default' padrão) NÃO bate mais em plan/missing-class-name nem em materialize/invalid-class para StarterPlayer.StarterPlayerScripts -- a pipeline avança até EXECUTAR o script real do servidor e materializa o LocalScript do cliente corretamente (não executado, LuauBench é servidor)", function()
	local result = runRealProcess(TIKTOK_PATH)

	-- O bug original deste cenário está fechado: nem o diagnóstico nem essa causa aparecem mais.
	assert(
		string.find(result.stderr, "plan/missing-class-name", 1, true) == nil,
		`NÃO deveria mais haver "plan/missing-class-name" no stderr (bug corrigido por task-cli-014) -- recebeu: {result.stderr}`
	)

	-- Confirmação da correção COMPLEMENTAR (task-cli-016, retestado em 2026-09-05): StarterPlayerScripts
	-- não aparece mais em NENHUM diagnóstico de erro/warning -- nem por missing-class-name (task-cli-014)
	-- nem por invalid-class (o que a versão anterior deste cenário ainda esperava). O filho fixo é
	-- adotado com sucesso, e o `LocalScript` real (`src/client/init.client.luau`) é materializado nele.
	assert(
		string.find(result.stderr, "StarterPlayerScripts", 1, true) == nil,
		`"StarterPlayerScripts" NÃO deveria mais aparecer em nenhum diagnóstico de stderr (task-cli-016 fechou a parede de invalid-class também) -- recebeu: {result.stderr}`
	)

	-- Prova de que a pipeline avançou de verdade, não só "não deu esses erros específicos": o
	-- script real do servidor RODOU (stdout de `print`, não diagnóstico) -- antes da correção,
	-- `TreePlanner.Plan` falhava e nenhum script chegava a ser materializado/executado.
	assert(
		string.find(result.stdout, "Hello world, from server!", 1, true) ~= nil,
		`esperava o script real do servidor ter rodado (stdout), recebeu stdout: {result.stdout}`
	)
	assert(
		string.find(result.stdout, "1 Script(s) executed", 1, true) ~= nil,
		`esperava o resumo confirmar 1 Script executado, recebeu stdout: {result.stdout}`
	)

	-- Confirmação ponta a ponta do fix: o LocalScript dentro de StarterPlayerScripts.Client É
	-- materializado (não bate mais em invalid-class) mas corretamente NÃO executado -- LuauBench
	-- roda como servidor, e LocalScript nunca roda no servidor no Roblox real. Isso é o
	-- comportamento CORRETO, não uma limitação -- documentado aqui como prova de que o fix
	-- funciona de ponta a ponta, não só "parou de dar esse erro".
	assert(
		string.find(result.stdout, "1 LocalScript(s) not executed (LuauBench runs as a server)", 1, true) ~= nil,
		`esperava o resumo confirmar 1 LocalScript materializado e corretamente não executado (roda como servidor), recebeu stdout: {result.stdout}`
	)

	-- Ainda assim, o processo termina em erro -- mas por causas LEGÍTIMAS, todas em território
	-- `services`/`runtime` (não `cli`): `Lighting.Technology` não é uma propriedade válida na
	-- simulação atual (propriedade removida/deprecada no Roblox moderno -- divergência esperada,
	-- não bug), `SoundService` ainda não é simulado, `Part` (do Baseplate) ainda não tem cobertura
	-- de `services`, e `Workspace.FilteringEnabled` é somente-leitura na simulação -- o que bate
	-- com o Roblox real atual (FilteringEnabled foi deprecada e é sempre true, não pode mais ser
	-- setada por script/projeto). Documentado aqui pra não confundir uma regressão futura DESTE
	-- bug com esses achados, que são de outro território e refletem fidelidade correta com o
	-- Roblox real, não bugs.
	assert(result.code == 2, `esperava ExitCode 2 (erros legítimos remanescentes, não relacionados a este bug), recebeu {result.code} (stdout: {result.stdout} stderr: {result.stderr})`)
	assert(
		string.find(result.stderr, "materialize/service-not-simulated", 1, true) ~= nil and string.find(result.stderr, "SoundService", 1, true) ~= nil,
		`esperava "SoundService" reportado como ainda não simulado (achado legítimo, território services), recebeu: {result.stderr}`
	)
	assert(
		string.find(result.stderr, "materialize/invalid-class", 1, true) ~= nil and string.find(result.stderr, "Part", 1, true) ~= nil,
		`esperava "Part" (Baseplate) reportado como ainda não simulado por "materialize/invalid-class", recebeu: {result.stderr}`
	)
	assert(
		string.find(result.stderr, "FilteringEnabled", 1, true) ~= nil and string.find(result.stderr, "read only", 1, true) ~= nil,
		`esperava "Workspace.FilteringEnabled" reportado como somente-leitura (fidelidade correta com o Roblox real -- propriedade deprecada), recebeu: {result.stderr}`
	)

	-- Efeito colateral documentado, NÃO um bug (mantido de antes da correção): `$properties` com
	-- array (Vector3/Color3 -- ainda não simulados, ver `src/cli/UnsimulatedGlobals.luau`) vira
	-- WARNING (não erro), citando o campo exato -- comportamento correto e gracioso (regra 00:
	-- nunca inventa valor, nunca falha silenciosamente). Confirma que esta parte da pipeline já
	-- estava bem tratada mesmo antes desta correção.
	assert(
		string.find(result.stderr, "plan/non-primitive-property", 1, true) ~= nil,
		`esperava warning "plan/non-primitive-property" (Vector3/Color3 array em $properties) no stderr, recebeu: {result.stderr}`
	)
end)

test("FIXED (task-cli-014) + achado novo: 'Panic - CHESSS' (jogo de xadrez real, framework Modux) avança até EXECUTAR código real do jogo -- erra em runtime por 'HttpService' não registrada (achado LEGÍTIMO, território services/runtime, não cli)", function()
	local result = runRealProcess(CHESS_PATH)

	assert(
		string.find(result.stderr, "plan/missing-class-name", 1, true) == nil,
		`NÃO deveria mais haver "plan/missing-class-name" no stderr (bug corrigido por task-cli-014) -- recebeu: {result.stderr}`
	)

	-- A pipeline chega a EXECUTAR código real do jogo (framework Modux próprio,
	-- `src/server/Services/MatchmakingService.luau`) e erra DENTRO dele -- prova de progresso
	-- ainda mais forte que 'Tiktok': aqui é um erro de linha de SCRIPT do usuário (via
	-- `DataModel:GetService`), não mais um diagnóstico de planejamento/materialização.
	assert(
		string.find(result.stderr, "MatchmakingService:4", 1, true) ~= nil,
		`esperava o erro citar a linha real do script do usuário (MatchmakingService:4), recebeu: {result.stderr}`
	)
	assert(
		string.find(result.stderr, "HttpService", 1, true) ~= nil,
		`esperava o erro citar "HttpService" (Service real do jogo ainda não registrado em ClassRegistry -- achado legítimo, território services, não cli), recebeu: {result.stderr}`
	)
	assert(result.code == 2, `esperava ExitCode 2, recebeu {result.code} (stdout: {result.stdout} stderr: {result.stderr})`)

	-- Nenhum stack trace cru do Lune deveria vazar (regra 04: "Falha ao ler .project.json ... é
	-- um erro claro apontando o campo problemático -- nunca stack trace cru do parser"). Mantido
	-- de antes da correção -- continua valendo.
	assert(string.find(result.stderr, "stack traceback", 1, true) == nil, "stack trace cru do Lune vazou pro usuário")
	assert(string.find(result.stderr, "attempt to index nil", 1, true) == nil, "erro Lua cru vazou pro usuário (deveria ser diagnóstico formatado)")
end)

test("FIXED (task-cli-014): 'TheGame' (310 arquivos, projeto maior) roda rápido e sem crash -- agora bate SÓ na parede de Wally Packages/ServerPackages não instalados (achado incidental, não é bug do LuauBench)", function()
	local startClock = os.clock()
	local result = runRealProcess(THEGAME_PATH)
	local elapsed = os.clock() - startClock

	assert(
		string.find(result.stderr, "plan/missing-class-name", 1, true) == nil,
		`NÃO deveria mais haver "plan/missing-class-name" no stderr (bug corrigido por task-cli-014) -- recebeu: {result.stderr}`
	)
	assert(result.code == 2, `esperava ExitCode 2, recebeu {result.code} (stdout: {result.stdout} stderr: {result.stderr})`)

	-- Achado incidental (NÃO bug do LuauBench -- é o checkout local deste projeto real que não
	-- tem `wally install` rodado): `$path` apontando pra pasta inexistente vira erro claro, citando
	-- o caminho absoluto resolvido -- mesma qualidade de diagnóstico de sempre. Sem essa
	-- dependência instalada, `TreePlanner.Plan` já falha (`bag:HasErrors()`) ANTES da fase de
	-- materialização/execução -- por isso, ao contrário de 'Tiktok'/'Panic - CHESSS', nenhum
	-- Script chega a rodar aqui (não é regressão do bug corrigido -- é uma parede ANTERIOR,
	-- de dependência ausente em disco, que a correção de task-cli-014 não afeta nem poderia
	-- afetar).
	assert(
		string.find(result.stderr, "plan/required-path-not-found", 1, true) ~= nil,
		`esperava diagnóstico de $path inexistente (Packages/ServerPackages não instalados via wally), recebeu: {result.stderr}`
	)

	-- Achado de PERFORMANCE (positivo, mantido de antes): planejar a árvore inteira de um projeto
	-- com 310 arquivos .luau leva menos de 1s na re-execução de 2026-09-05 (777ms medidos por
	-- fora do processo via `time`), mesmo tendo que ler cada arquivo do disco -- sem sinal de
	-- travamento/lentidão exponencial nesta escala. Não é um teste de carga rigoroso (só um
	-- projeto, uma rodada), mas é um dado real, não suposição.
	assert(elapsed < 15, `esperava planejar+errar em menos de 15s pra 310 arquivos, levou {elapsed}s`)
end)

print(`{passedCount}/{totalCount} cenários reais de Roblox-Games passaram, {failedCount} falharam (bug de StarterPlayerScripts corrigido -- task-cli-014 + task-cli-016; ver comentários pros achados legítimos remanescentes)`)

if failedCount > 0 then
	process.exit(1)
end
