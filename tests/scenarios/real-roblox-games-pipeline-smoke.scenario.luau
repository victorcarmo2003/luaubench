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
-- Status: passa hoje NO SENTIDO DE "reproduz de forma estável" -- mas os asserts abaixo
-- caracterizam um BUG GRAVE confirmado (ver comentário antes do teste 1): os TRÊS projetos reais
-- testados (e, por inspeção de `default.project.json`, TODOS os 17 projetos Rojo encontrados em
-- Roblox-Games que usam StarterPlayer) batem a MESMA parede -- `[plan/missing-class-name]` em
-- "StarterPlayer.StarterPlayerScripts" -- ANTES de qualquer script rodar. Quando `TreePlanner`
-- for corrigido (ver comentário), estes asserts de ExitCode==2/mensagem precisam ser atualizados
-- para refletir o novo comportamento (a pipeline deveria seguir adiante).

local process = require("@lune/process")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
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
	BUG GRAVE (território `cli`, `src/cli/TreePlanner.luau`) -- confirmado contra os 3 projetos
	reais abaixo E via inspeção (grep) de TODOS os 17 `default.project.json` encontrados em
	Roblox-Games: todo projeto Rojo com a árvore padrão `StarterPlayer > StarterPlayerScripts`
	(SEM `$className` explícito no nó `StarterPlayerScripts` -- o padrão universal gerado por
	`rojo init` e replicado em todo projeto real do usuário) falha em `TreePlanner.Plan` com
	`[plan/missing-class-name]`, ANTES de qualquer script do usuário rodar.

	TreePlanner.luau:596/921 só ativa a inferência de "known service" quando
	`parentClassName == "DataModel"` (`options.IsServiceClass(name)`) -- e
	`generated/Manifest.luau:749` confirma `StarterPlayerScripts` tem `IsService = false` (é
	fiel ao dump: StarterPlayerScripts não é uma Service GetService()-ável), então mesmo relaxar
	o `parentClassName` não bastaria por essa via -- Rojo resolve isso por um mecanismo
	DIFERENTE de "Service por nome".

	CONFIRMADO CONTRA O ROJO REAL (não é suposição -- regra 00, "pesquisador confirma antes de
	implementar", aplicada aqui pelo testador com o binário disponível): `rojo sourcemap
	default.project.json --include-non-scripts` (Rojo 7.7.0, via `rokit` local do projeto
	Tiktok) rodado DE VERDADE contra o `default.project.json` ATUAL (não um sourcemap.json
	obsoleto que já estava no repo -- gerado fresco nesta sessão) devolve
	`{"name":"StarterPlayerScripts","className":"StarterPlayerScripts", ...}` como filho de
	`StarterPlayer`, SEM `$className` no projeto -- ou seja, o Rojo real resolve isso com
	sucesso. Isso CONTRADIZ a leitura anterior registrada em
	`.claude/agents-memory/pesquisa-formato-projeto-rojo-2026-09-05.md` linha 90-91 ("infer_class_name
	só entra em ação se parent_class == DataModel") -- ou aquela pesquisa está incompleta para
	este caso (provavelmente Rojo tem uma segunda via de inferência, não coberta na pesquisa
	original, para filhos fixos e conhecidos de uma classe -- StarterPlayerScripts/
	StarterCharacterScripts são os dois filhos fixos de StarterPlayer no Roblox real), ou o
	comportamento mudou entre a versão pesquisada e o Rojo 7.7.0. De todo modo: `pesquisador`
	precisa revisitar esse ponto específico antes de `coder-cli` tentar corrigir
	`TreePlanner.luau` -- não é só "relaxar `parentClassName == DataModel`" (isso quebraria a
	guarda que existe hoje pra não inferir Service em qualquer profundidade da árvore).

	IMPACTO: 100% dos 17 projetos Rojo reais encontrados em Roblox-Games usam esse padrão --
	é o padrão universal de qualquer jogo Roblox com StarterPlayerScripts populado (todo jogo
	com LocalScript de cliente). Bloqueia a pipeline INTEIRA (nenhum script chega a rodar) para
	praticamente qualquer projeto Roblox real -- é a lacuna de maior impacto encontrada nesta
	rodada, maior que qualquer Service/value-type faltante.
]]
test("BUG GRAVE: 'Tiktok' (projeto Rojo 'default' padrão) falha em plan/missing-class-name para StarterPlayer.StarterPlayerScripts, ANTES de qualquer script rodar", function()
	local result = runRealProcess(TIKTOK_PATH)
	assert(result.ok == false, `esperava falha (ExitCode != 0), recebeu ok={result.ok} code={result.code}`)
	assert(result.code == 2, `esperava ExitCode 2 (erro de projeto), recebeu {result.code} (stdout: {result.stdout} stderr: {result.stderr})`)
	assert(
		string.find(result.stderr, "plan/missing-class-name", 1, true) ~= nil,
		`esperava diagnóstico "plan/missing-class-name" no stderr, recebeu: {result.stderr}`
	)
	assert(
		string.find(result.stderr, "StarterPlayerScripts", 1, true) ~= nil,
		`esperava o nó "StarterPlayerScripts" citado no stderr, recebeu: {result.stderr}`
	)

	-- Efeito colateral documentado, NÃO um bug: `$properties` com array (Vector3/Color3 -- ainda
	-- não simulados, ver `src/cli/UnsimulatedGlobals.luau`) vira WARNING (não erro), citando o
	-- campo exato -- comportamento correto e gracioso (regra 00: nunca inventa valor, nunca
	-- falha silenciosamente). Confirma que esta parte da pipeline já está bem tratada.
	assert(
		string.find(result.stderr, "plan/non-primitive-property", 1, true) ~= nil,
		`esperava warning "plan/non-primitive-property" (Vector3/Color3 array em $properties) no stderr, recebeu: {result.stderr}`
	)
end)

test("BUG GRAVE (mesma causa): 'Panic - CHESSS' (jogo de xadrez real, framework Modux) bate a MESMA parede StarterPlayerScripts", function()
	local result = runRealProcess(CHESS_PATH)
	assert(result.code == 2, `esperava ExitCode 2, recebeu {result.code} (stdout: {result.stdout} stderr: {result.stderr})`)
	assert(
		string.find(result.stderr, "plan/missing-class-name", 1, true) ~= nil,
		`esperava diagnóstico "plan/missing-class-name" no stderr, recebeu: {result.stderr}`
	)

	-- Nenhum stack trace cru do Lune deveria vazar (regra 04: "Falha ao ler .project.json ... é
	-- um erro claro apontando o campo problemático -- nunca stack trace cru do parser").
	assert(string.find(result.stderr, "stack traceback", 1, true) == nil, "stack trace cru do Lune vazou pro usuário")
	assert(string.find(result.stderr, "attempt to index nil", 1, true) == nil, "erro Lua cru vazou pro usuário (deveria ser diagnóstico formatado)")
end)

test("BUG GRAVE (mesma causa) + achado incidental: 'TheGame' (310 arquivos, projeto maior) roda rápido e sem crash, mas Wally Packages/ServerPackages não instalados viram erro de projeto à parte", function()
	local startClock = os.clock()
	local result = runRealProcess(THEGAME_PATH)
	local elapsed = os.clock() - startClock

	assert(result.code == 2, `esperava ExitCode 2, recebeu {result.code} (stdout: {result.stdout} stderr: {result.stderr})`)
	assert(
		string.find(result.stderr, "plan/missing-class-name", 1, true) ~= nil,
		`esperava diagnóstico "plan/missing-class-name" no stderr, recebeu: {result.stderr}`
	)

	-- Achado de PERFORMANCE (positivo): planejar a árvore inteira de um projeto com 310 arquivos
	-- .luau leva poucos segundos, mesmo tendo que ler cada arquivo do disco -- sem sinal de
	-- travamento/lentidão exponencial nesta escala. Não é um teste de carga rigoroso (só um
	-- projeto, uma rodada), mas é um dado real, não suposição.
	assert(elapsed < 15, `esperava planejar+errar em menos de 15s pra 310 arquivos, levou {elapsed}s`)

	-- Achado incidental (NÃO bug do LuauBench -- é o checkout local deste projeto real que não
	-- tem `wally install` rodado): `$path` apontando pra pasta inexistente também vira erro
	-- claro, citando o caminho absoluto resolvido -- mesma qualidade de diagnóstico do caso
	-- principal.
	assert(
		string.find(result.stderr, "plan/required-path-not-found", 1, true) ~= nil,
		`esperava diagnóstico de $path inexistente (Packages/ServerPackages não instalados via wally), recebeu: {result.stderr}`
	)
end)

print(`{passedCount}/{totalCount} cenários reais de Roblox-Games passaram (caracterizando o bug atual -- ver comentários)`)
