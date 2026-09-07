# Revisão — task-cli-039 (darklua bundle antes de lune build)

Data: 2026-09-07. Read-only, tudo abaixo foi **reproduzido por mim**, não aceito por self-report.
Ambiente confirmado: `lune 0.10.5`, `darklua 0.19.0`, `luau-lsp 1.69.0` — batem com `rokit.toml`.

## O que fiz

1. Li `.claude/tasks.json` (task-cli-039, ainda com `"column": "todo"`), a pesquisa
   `pesquisa-lune-build-standalone-2026-09-07.md` e o relatório do coder.
2. Li `.darklua.json`, `tools/build.luau`, `rokit.toml`, `.gitignore` e a seção nova de
   `.claude/rules/04-cli-rokit.md`.
3. Apaguei `bin/` e `.cache/build/` e rodei `lune run tools/build.luau` do zero — sucesso,
   sem intervenção manual.
4. Rodei `bin/luaubench.exe --help` e `--version` — ambos funcionam, exit 0, sem
   `require is not supported in this context`.
5. Rodei `bin/luaubench.exe run tests/scenarios/fixtures/value-types-project --no-persist` —
   8/8 verificações do fixture passaram, `0 error(s), 0 warning(s)`, exit 0.
6. **Teste decisivo reproduzido**: copiei `bin/luaubench.exe` para o scratchpad (fora do
   repositório) como `luaubench-standalone.exe`, `cd` pra lá, e rodei contra
   `C:\Users\hakor\Documents\Roblox-Games\Tiktok` (read-only) com `--no-persist`. Saída:
   `ServerScriptService.Server: Hello world, from server!` seguido só do erro genuíno de
   cobertura (`Part` ainda não simulado). Nenhum erro de require/bundling. Confirmei via
   `ls -la` que nenhum arquivo novo apareceu na pasta do Tiktok (sem `.luaubench/`, sem
   artefato extra) — comportamento read-only preservado.
7. Rodei `lune run tools/build.luau` uma segunda vez seguida — idempotente, sobrescreveu
   sem erro.
8. `git status --porcelain=v1 -uall` antes e depois do build: só
   `.claude/rules/04-cli-rokit.md` (M), `rokit.toml` (M), `.darklua.json` (novo),
   `tools/build.luau` (novo) e os 2 arquivos de `agents-memory` (novos, esperados). `bin/` e
   `.cache/build/bundled.luau` nunca aparecem — confirmei também com `git ls-files bin/ .cache/`
   (vazio). Território limpo, bate exatamente com o alegado.
9. `git status --porcelain -uall -- src/` vazio — nenhum `require()` ou qualquer outro
   arquivo de `src/**` foi tocado.
10. `luau-lsp analyze --platform=standard --settings=".luaurc" tools/build.luau` — exit 0,
    zero diagnósticos (mesmo padrão de tooling já usado em tasks anteriores de `coder-cli`).
    `--!strict` na linha 1, todas as funções com assinatura tipada, nenhum `any`.
11. Validei a sintaxe do `.darklua.json` contra a doc real do darklua (fetch de
    `site/content/docs/bundle/index.md` e `luau-require-mode/index.md` no repo
    `seaofvoices/darklua`, branch `main`):
    - `require_mode: {name: "luau"}` é forma mínima válida e documentada (equivalente à
      string `"luau"` com defaults) — confirmado.
    - `excludes` é lista de glob patterns da lib `wax` (Rust). Doc oficial do darklua usa
      `["@lune/**"]` como exemplo — o coder escreveu `["@lune/*"]` (asterisco simples).

## Achado — divergência no glob de `excludes` (`.darklua.json`)

**[MÉDIO] `.darklua.json:6`**
Problema: `excludes: ["@lune/*"]` usa um único asterisco, que na sintaxe da lib `wax`
(usada pelo darklua) **nunca cruza `/`** — só casa dentro de um componente de path. O exemplo
oficial da doc do darklua usa `["@lune/**"]` (asterisco duplo, cruza componentes).
Cenário: hoje funciona (confirmei empiricamente — nenhum `require("@lune/...")` foi inlinado
no bundle de 28829 linhas: `fs`, `process`, `stdio`, `task`, `net`, `serde`, `datetime`, `luau`
todos preservados intactos) porque **todo módulo nativo do Lune atual é de um segmento só**
(`@lune/fs`, não `@lune/algo/fs`). Se o Lune algum dia introduzir um builtin aninhado, ou se
algum alias de projeto precisar excluir um path com mais de um nível, `@lune/*` deixaria de
casar e o darklua tentaria resolver esse require como arquivo local, quebrando o build (ou pior,
falhando silenciosamente dependendo de como o darklua trata exclude miss — não testado esse
caso extremo pois não é reproduzível com os builtins atuais).
Correção: trocar para `"@lune/**"`, igual ao exemplo oficial da doc — mesmo resultado hoje,
mais robusto contra o futuro, e evita a pergunta "por que aqui não segue o exemplo da doc"
numa revisão futura sem contexto.

Não é bloqueante — o comportamento atual está correto e foi comprovado por execução real, não
é uma falha ativa. Rebaixo para ressalva, não reprovação.

## Demais critérios do relatório do coder — todos confirmados por reprodução direta

- `.darklua.json`: `bundle.require_mode.name = "luau"` — confirmado correto e válido contra doc.
- `tools/build.luau`: encapsula `darklua process` → `lune build`, valida cwd
  (`assertRunningFromRepoRoot`, erro claro se rodado fora da raiz), cria diretórios
  (`ensureDir` com guard `fs.isDir`), e `runStep` verifica `result.ok`/`result.code` e chama
  `process.exit(1)` com mensagem — nunca engole falha silenciosamente. Confirmado.
- `rokit.toml`: `darklua = "seaofvoices/darklua@0.19.0"` — mesma sintaxe `owner/repo@versão`
  de `lune`/`luau-lsp`, coerente.
- `.gitignore`: nenhuma mudança necessária, `/bin/` e `.cache/` já cobrem os artefatos —
  confirmado por `git status`/`git ls-files` depois do build.
- Bundle produzido: 28829 linhas (bate com o alegado "~28.8k"), minificado por variável mas
  com os `require("@lune/...")` (sintaxe `require"@lune/x"` pós-minify) preservados.
- `lune build` compilou sem erro, binário roda `--help`/`--version`/`run` sem erro de bundling.
- Teste decisivo (binário fora do repo, contra projeto real read-only) reproduzido igual.
- Idempotência confirmada com 2 execuções seguidas.

## Seção nova de `.claude/rules/04-cli-rokit.md`

Li a seção "Empacotamento (bundle + build) — exceção documentada à invariante 3". Documenta:
decisão revisitada em 2026-09-07 (task-cli-039), por que precisa do darklua (fonte: pesquisa,
citada por caminho), o pipeline de 2 passos com comandos exatos, o comando único reproduzível
(`lune run tools/build.luau`), o conteúdo do `.darklua.json`, por que `require_mode = "luau"`
(não `"path"`), como `darklua` entra no `rokit.toml`, e o que fica fora do escopo. Um agente
futuro entenderia a decisão sem precisar achar a pesquisa original — critério atendido.

## Observação de processo (não é achado de código)

`task-cli-039` em `.claude/tasks.json` ainda está com `"column": "todo"` — não foi movida para
`done`/`in-review` apesar do trabalho estar completo e verificado. Não é uma falha de
implementação, mas o board não reflete o estado real; quem despachou deveria atualizar isso.

## Veredito

APROVADO COM RESSALVAS — toda a funcionalidade alegada foi reproduzida e confirmada
empiricamente (build limpo, binário standalone funcional, teste decisivo fora do repo contra
projeto real, idempotência, território limpo, `--!strict` sem `any`, doc da regra 04
atualizada de forma clara). A única ressalva é o glob `@lune/*` em vez de `@lune/**` no
`excludes` do `.darklua.json` — funciona hoje (comprovado), mas diverge do exemplo oficial da
doc do darklua e é menos robusto a builtins aninhados futuros do Lune. Troca de uma linha,
sem risco. Board da task-cli-039 também não foi movido para `done`.
