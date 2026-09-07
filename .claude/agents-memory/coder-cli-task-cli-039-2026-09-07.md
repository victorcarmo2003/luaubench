# [task-cli-039] Adotar darklua como passo de bundle antes de lune build

## Arquivos

**Criados:**
- `.darklua.json` (raiz) — config do darklua, `bundle.require_mode.name = "luau"`, `bundle.excludes = ["@lune/*"]`.
- `tools/build.luau` — script dev-time `lune run tools/build.luau`: encapsula os dois passos do pipeline (`darklua process` → `lune build`), valida que roda da raiz do repo, cria `.cache/build/`/`bin/` se faltarem, aborta com mensagem clara (nunca stack trace cru) se `darklua`/`lune` falharem.

**Modificados:**
- `rokit.toml` — adicionado `darklua = "seaofvoices/darklua@0.19.0"` (via `rokit trust seaofvoices/darklua` + `rokit add seaofvoices/darklua`, mesmo canal de `lune`/`luau-lsp`).
- `.claude/rules/04-cli-rokit.md` — nova seção "Empacotamento (bundle + build) — exceção documentada à invariante 3": registra a decisão do usuário (2026-09-07), explica o "porquê" (fonte: pesquisa já concluída), documenta o pipeline de 2 passos, o comando único reproduzível, o conteúdo do `.darklua.json`, e a verificação manual feita.

**Não tocados (confirmado, fora do escopo):** nenhum `require()` dentro de `src/**`; nenhum arquivo de `src/runtime/`/`src/services/`; `.gitignore` não precisou de mudança (ver abaixo).

## Comando(s)/fluxo

Pipeline de release, dois passos, sempre nesta ordem:
1. `darklua process src/cli/main.luau .cache/build/bundled.luau`
2. `lune build .cache/build/bundled.luau -o bin/luaubench`

Comando único reproduzível: **`lune run tools/build.luau`** (rodado da raiz do repo). Confirmado idempotente — rodei duas vezes seguidas, ambos os passos sobrescrevem o destino sem erro (só `fs.writeDir` precisa do guard `fs.isDir`, que o script já faz).

## API de runtime/services consumida

Nenhuma nova — `tools/build.luau` só usa `@lune/fs` (`isFile`/`isDir`/`writeDir`), `@lune/process` (`exec`, `os`, `exit`) e `@lune/stdio` (`ewrite`), mesmo padrão de `tools/generate-services.luau`. Não é código de `src/cli/` (fica em `tools/`, dev-time, nunca requerido pelo runtime do LuauBench nem pelo binário final).

## API faltante

Nenhuma — o achado de `lune build` não resolver `require()` (pesquisa já concluída, `.claude/agents-memory/pesquisa-lune-build-standalone-2026-09-07.md`) é uma lacuna do **Lune**, não algo que `runtime`/`services` precisariam expor de diferente para `cli`.

## Verificação (rodei eu mesmo, `lune 0.10.5`, `darklua 0.19.0`, `rokit 1.2.0`)

- `darklua process src/cli/main.luau <bundle>` — roda sem erro, produz um único `.luau` (28829 linhas) com todos os territórios inlinados (`runtime`/`services`/`valuetypes`/`cli`) e os `require("@lune/...")` preservados intactos (não inlinados). Testado 2x seguidas (overwrite limpo).
- `lune build <bundle> -o <binário>` — compila sem erro. `-o` sem extensão; `lune` decide `.exe` no Windows.
- `bin/luaubench.exe --help` — funciona, mostra a mesma tela de ajuda de sempre. **Sem `require is not supported in this context`.**
- `bin/luaubench.exe --version` — funciona (`luaubench 0.1.0`, dump `0.737.0.7371584`) — confirma que `src/services/generated/Manifest.luau` (dado do API Dump) foi embutido como código Luau estático pelo bundle, não lido do disco em runtime.
- `bin/luaubench.exe run tests/scenarios/fixtures/value-types-project` — pipeline completo (parsing `.project.json` → materialização da árvore → execução do script → Vector3/CFrame/Color3/Enum reais dentro do sandbox) roda ponta a ponta: **8/8 verificações do fixture passaram**, `0 error(s), 0 warning(s)`, exit code 0.
- **Smoke test decisivo**: copiei o binário para `/tmp` (fora do repositório inteiro) e rodei `luaubench-standalone.exe run "C:\Users\hakor\Documents\Roblox-Games\Tiktok"` (read-only, projeto Rojo real de terceiro) a partir de `/tmp` como cwd. Resultado: `ServerScriptService.Server: Hello world, from server!` (script real do projeto rodou), seguido de um erro `[materialize/invalid-class] ... "Part" ... not simulated by LuauBench yet` — **erro de cobertura genuíno e esperado** (Part ainda não é uma classe simulada por `services`), não um erro de bundling/require. Confirma que o binário funciona fora do diretório do repo, contra um projeto externo real, sem qualquer path relativo quebrado ou módulo faltando.
- `lune run tools/build.luau` rodado do zero (`rm -rf bin .cache/build`) reproduziu tudo acima sem intervenção manual, e rodado de novo em seguida (idempotência) sem erro.
- `git status` confirma que `.cache/build/bundled.luau` e `bin/luaubench.exe` NÃO aparecem como untracked — já cobertos por `.cache/` e `/bin/` no `.gitignore` existente, nenhuma mudança de `.gitignore` foi necessária.

## Pendências

- Nenhuma dentro do escopo desta task. Fora do escopo (explicitamente, por instrução): automação de CI/GitHub Actions do build, criação de tag/release e upload para GitHub Releases — fica para tarefa futura se o usuário pedir.
- Observação para releases futuras (não bloqueia esta task): `rokit add seaofvoices/darklua` pediu confirmação de "trust" na primeira execução (`rokit trust seaofvoices/darklua` resolveu, não-interativo) — quem clonar o repo pela primeira vez e rodar `rokit install` provavelmente vai precisar do mesmo passo de trust na primeira vez que instalar uma fonte nova de tool; comportamento padrão do Rokit, não específico do LuauBench, não documentado aqui por não ser parte do pipeline de build em si.
