--!strict

--[[
	Empacotamento do LuauBench para distribuição via Rokit (task-cli-039;
	.claude/agents-memory/pesquisa-lune-build-standalone-2026-09-07.md;
	.claude/rules/04-cli-rokit.md, seção "Empacotamento (bundle + build)").

	`lune build` (0.10.5, pinado em rokit.toml) NÃO resolve `require()` de arquivo local -- é uma
	lacuna estrutural confirmada no código-fonte real do Lune (`crates/lune/src/standalone/
	tracer.rs` é um TODO vazio), não uma configuração faltando. O binário standalone só embute o
	bytecode de UM arquivo. Por isso o pipeline de release tem DOIS passos, nunca um só:

		1. `darklua process src/cli/main.luau <bundle>` -- resolve o grafo inteiro de `require`
		   (`runtime`/`services`/`valuetypes`/`cli`, todos os territórios) e produz um único
		   arquivo `.luau` autocontido. `require_mode = "luau"` (não "path") é o modo que a doc do
		   darklua descreve como "the require mode used by the Lune runtime" -- é o que entende a
		   mesma semântica de `require("./")`/`require("../x")`/`init.luau` que o código-fonte já
		   usa. `bundle.excludes = ["@lune/*"]` (.darklua.json, raiz do projeto) impede o darklua de
		   tentar inlinar os módulos nativos do Lune (`@lune/fs`, `@lune/process`, etc.) -- eles
		   continuam sendo `require`-ados normalmente dentro do binário, que já os provê.
		2. `lune build <bundle> -o <binário>` -- compila o arquivo único já resolvido pelo passo 1
		   num executável standalone de verdade.

	Único ponto de entrada REPRODUZÍVEL desse pipeline: `lune run tools/build.luau` (ou
	`lune run tools/build`), rodado da RAIZ do repositório -- não depende de memória de quem
	rodou o build uma vez manualmente. Script DEV-TIME, nunca requerido por `src/` nem chamado
	de dentro do próprio `luaubench run` (mesma disciplina de `tools/generate-services.luau`).

	IDEMPOTÊNCIA: confirmado empiricamente (task-cli-039) que tanto `darklua process` quanto
	`lune build -o` sobrescrevem o arquivo de destino sem erro quando ele já existe -- só a
	CRIAÇÃO de diretório (`fs.writeDir`) precisa do guard `fs.isDir` (a API do Lune lança erro se
	o diretório já existir).

	Saídas (ambas fora do controle de versão -- ver .gitignore):
		- Bundle intermediário: `.cache/build/bundled.luau` (dentro de `.cache/`, já ignorado por
		  inteiro -- cache local do Roblox API Dump já vive lá, mesmo padrão).
		- Binário final: `bin/luaubench` (`bin/luaubench.exe` no Windows -- é o próprio `lune
		  build` que decide a extensão por plataforma; este script NUNCA a acrescenta na hora de
		  invocar `lune build`, só na hora de IMPRIMIR o caminho final pro usuário). `bin/` já é
		  ignorado por padrão (`/bin/` no .gitignore, mesma convenção citada em
		  .claude/agents/github.md).

	NÃO faz parte deste script (fora do escopo de task-cli-039, ver o board): nenhuma automação de
	CI/GitHub Actions, nenhuma criação de tag/release/upload pro GitHub Releases -- só o build
	MANUAL ponta a ponta. Nenhum `require()` dentro de `src/**` é alterado por este script; ele só
	invoca `darklua`/`lune` como processos externos.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")

local ENTRY_POINT = "src/cli/main.luau"
local BUNDLE_DIR = ".cache/build"
local BUNDLE_PATH = BUNDLE_DIR .. "/bundled.luau"
local BIN_DIR = "bin"
local BIN_PATH_NO_EXT = BIN_DIR .. "/luaubench"

-- Sanidade: este script só faz sentido rodado da raiz do repositório (mesma convenção de
-- `tools/generate-services.luau`, que lê `tools/api-dump.lock.json` com caminho relativo). Falha
-- clara e cedo em vez de deixar `darklua`/`fs` produzirem um erro de I/O críptico mais adiante.
local function assertRunningFromRepoRoot(): ()
	if not fs.isFile(ENTRY_POINT) then
		stdio.ewrite(
			`[LuauBench] tools/build.luau precisa rodar da RAIZ do repositório (não achei "{ENTRY_POINT}" a partir do diretório atual). `
				.. `Rode "lune run tools/build.luau" a partir da pasta que contém rokit.toml.\n`
		)
		process.exit(1)
	end
end

local function ensureDir(path: string): ()
	if not fs.isDir(path) then
		fs.writeDir(path)
	end
end

-- Roda um comando externo com stdout/stderr herdados (build é um comando interativo/manual --
-- o usuário vê o progresso de `darklua`/`lune` em tempo real) e aborta com mensagem clara se o
-- processo terminar com código diferente de zero. Nunca deixa um `process.exec` malsucedido
-- passar batido (regra 01: nunca engolir erro sem repassar).
local function runStep(label: string, program: string, args: { string }): ()
	print(`[LuauBench build] {label}: {program} {table.concat(args, " ")}`)
	local result = process.exec(program, args, { stdio = "inherit" })
	if not result.ok then
		stdio.ewrite(`[LuauBench build] Falhou em "{label}" (código de saída {result.code}). Veja a saída de "{program}" acima.\n`)
		process.exit(1)
	end
end

assertRunningFromRepoRoot()
ensureDir(BUNDLE_DIR)
ensureDir(BIN_DIR)

-- Passo 1: bundle. `darklua` precisa estar instalado via Rokit (`rokit.toml`, `rokit install`) --
-- se não estiver no PATH, `process.exec` já devolve `ok = false` com uma mensagem do próprio SO,
-- capturada e repassada por `runStep` (não um crash cru deste script).
runStep("bundle (darklua)", "darklua", { "process", ENTRY_POINT, BUNDLE_PATH })

-- Passo 2: build standalone. `-o` recebe o caminho SEM extensão -- é o `lune build` quem decide
-- ".exe" (Windows) ou nenhuma extensão (Linux/macOS), confirmado empiricamente (task-cli-039).
runStep("build (lune)", "lune", { "build", BUNDLE_PATH, "-o", BIN_PATH_NO_EXT })

local finalBinaryPath = if process.os == "windows" then BIN_PATH_NO_EXT .. ".exe" else BIN_PATH_NO_EXT

print(`[LuauBench build] OK -- binário standalone gerado em "{finalBinaryPath}".`)
print(`[LuauBench build] Verificação rápida sugerida: "{finalBinaryPath}" --help`)
