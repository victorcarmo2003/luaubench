# Regra 04 — CLI, integração Rojo e distribuição Rokit (`src/cli/`)

## Comando `luaubench run`

- Lê o `.project.json` do Rojo (ou o sourcemap gerado por `rojo sourcemap`) para descobrir a árvore de instâncias do projeto do usuário — nunca assume estrutura de pasta fixa sem checar o arquivo de projeto.
- Popula o `DataModel` simulado (via API pública de `runtime`) espelhando exatamente a árvore do Rojo: `ServerScriptService`, `ReplicatedStorage`, etc., com os `Script`/`ModuleScript`/`LocalScript` do disco carregados como Instance com o código-fonte associado.
- Executa o(s) script(s) de entrada dentro do sandbox de execução (ver `.claude/rules/02-runtime-simulation.md` — execução de código arbitrário) e imprime saída/erro formatado como o Output do Studio (nome do script, linha, stack).
- Falha ao ler `.project.json` (arquivo ausente, JSON inválido, referência a path que não existe) é um erro claro apontando o campo problemático — nunca stack trace cru do parser.

## Watch mode

- Reagir a mudança de arquivo do projeto do usuário via observador de filesystem do Lune, nunca por polling em intervalo.
- Re-executar só o necessário ao detectar mudança (ideal: recarregar o script/módulo alterado) — se a primeira versão precisar reiniciar o `DataModel` inteiro a cada mudança, isso é uma limitação a declarar no relatório, não a esconder.

## Formato de projeto Rojo

- Não invente campo do `.project.json` que o Rojo não define. **Confirmado por pesquisa contra o código-fonte real do Rojo (`.claude/agents-memory/pesquisa-formato-projeto-rojo-2026-09-05.md`): o struct raiz do `.project.json` usa `#[serde(deny_unknown_fields)]` — qualquer campo extra no topo (incluindo um namespace tipo `"luaubench": {...}`) faz `rojo serve`/`build` reais falharem.** Extensão do LuauBench NUNCA vive dentro do `.project.json` — vive em arquivo separado (ex: `luaubench.toml` na raiz do projeto do usuário).
- Formato de referência já pesquisado e confirmado em `.claude/agents-memory/pesquisa-formato-projeto-rojo-2026-09-05.md`: schema completo do `.project.json` (`ProjectNode`: `$className`/`$path`/`$properties`/`$attributes`/`$id`/`$ignoreUnknownInstances`), convenção arquivo→ClassName (`.server.lua`→`Script`, `.client.lua`→`LocalScript`, `init.*` para pastas, etc.), formato do sourcemap (`{name, className, filePaths, children}` — por padrão só inclui Script/LocalScript/ModuleScript, precisa de `--include-non-scripts` pro resto), resolução de `$path` relativa à pasta do `.project.json` que define aquele nó, e detecção de projetos Rojo aninhados. `coder-cli` lê esse arquivo antes de implementar o parser — não repita a pesquisa.

## Distribuição via Rokit

- Build final é executável standalone via `lune build`, publicado em GitHub Release com tag semver (`vMAJOR.MINOR.PATCH`).
- Manifesto compatível com Rokit (ex: `rokit.toml` do próprio projeto, ou o formato que o Rokit espera do binário publicado) mantido atualizado a cada release — `rokit add victorcarmo2003/luaubench` precisa continuar funcionando depois de qualquer mudança de build.
- Nenhum outro canal de instalação (script `curl | sh`, instalador separado) entra sem decisão explícita do usuário — Rokit é o caminho oficial único.

## Empacotamento (bundle + build) — exceção documentada à invariante 3

**Decisão revisitada e aprovada pelo usuário em 2026-09-07 (task-cli-039).** A invariante 3 do projeto ("nenhuma dependência de binário externo além do que o Lune já provê entra sem essa decisão ser revisitada explicitamente com o usuário") tem, a partir desta data, **uma única exceção registrada: [`darklua`](https://github.com/seaofvoices/darklua)**, usado exclusivamente como passo de *bundle* antes de `lune build`. Nenhuma outra dependência de binário externo entra sem repetir esse mesmo processo de revisão.

**Por que precisa de `darklua`** — confirmado por pesquisa contra o código-fonte real do Lune 0.10.5 (`.claude/agents-memory/pesquisa-lune-build-standalone-2026-09-07.md`): `lune build` compila e embute **só o bytecode do arquivo de entrada único**. Resolver o grafo de `require()` entre arquivos locais é uma lacuna estrutural do próprio Lune (`crates/lune/src/standalone/tracer.rs` é um TODO vazio, não implementado) — sem bundling, o binário standalone gerado crasha na primeira chamada de `require()` com `require is not supported in this context`. Essa é a solução oficialmente recomendada pelo CHANGELOG do Lune desde que `lune build` existe (entrada da versão `0.8.0`).

**Pipeline de release, dois passos, sempre nesta ordem:**

1. `darklua process src/cli/main.luau .cache/build/bundled.luau` — resolve o grafo inteiro de `require` (`runtime`/`services`/`valuetypes`/`cli`) e produz um único arquivo `.luau` autocontido.
2. `lune build .cache/build/bundled.luau -o bin/luaubench` — compila o arquivo já resolvido pelo passo 1 num executável standalone (`bin/luaubench.exe` no Windows — é o próprio `lune build` que decide a extensão por plataforma, nunca o script).

**Comando único reproduzível:** `lune run tools/build.luau`, rodado da raiz do repositório — encapsula os dois passos acima, valida que está rodando da raiz (existência de `src/cli/main.luau`), cria os diretórios de saída se faltarem, e aborta com mensagem clara (nunca stack trace cru) se `darklua`/`lune` não estiverem instalados (`rokit install`) ou falharem. Não depende de memória de quem rodou o build uma vez.

**Config do darklua** (`.darklua.json`, raiz do projeto):

```json
{
  "bundle": {
    "require_mode": { "name": "luau" },
    "excludes": ["@lune/**"]
  }
}
```

- `require_mode = "luau"` — **não** `"path"`. Confirmado contra a doc oficial do darklua: `"luau"` é literalmente descrito como "the require mode used by the Lune runtime" — é o modo que entende a mesma semântica de `require("./")`/`require("../x")`/carregamento "estilo diretório" de `init.luau` que o código-fonte de `cli`/`runtime`/`services`/`valuetypes` já usa (documentada nos cabeçalhos de cada `init.luau`).
- `bundle.excludes = ["@lune/**"]` (dupla estrela — a lib `wax` usada pelo darklua nunca cruza `/` com um asterisco simples; `**` é o padrão da própria doc oficial do darklua e continua correto se um builtin do Lune ganhar um segmento a mais no nome no futuro) — os módulos nativos do Lune (`@lune/fs`, `@lune/process`, etc.) nunca são inlinados; continuam sendo `require`-ados normalmente dentro do binário, que já os provê nativamente.
- `darklua` entra no `rokit.toml` pelo mesmo canal já usado por `lune`/`luau-lsp` (`rokit add seaofvoices/darklua`) — nenhum gerenciador de pacote novo.

**Verificação de que o binário FUNCIONA de verdade** (não só que compilou) — confirmado manualmente na task-cli-039: `bin/luaubench.exe --help`/`--version` sem erro, e `bin/luaubench.exe run <projeto>` executado a partir de um diretório fora do repositório contra um projeto Rojo real materializou a árvore e rodou o script de entrada sem `require is not supported in this context` nem qualquer outro erro de bundling (path relativo quebrado, módulo faltando). O único erro observado nesse teste foi um erro de cobertura genuíno e esperado (`Part` ainda não simulado por `services`) — não um problema de empacotamento.

**Artefatos intermediário e final nunca são commitados** — `.cache/build/bundled.luau` cai dentro de `.cache/` (já ignorado por inteiro no `.gitignore`); `bin/luaubench`/`bin/luaubench.exe` caem dentro de `/bin/` (já ignorado). Rodar `lune run tools/build.luau` de novo sobrescreve os dois sem erro (idempotente, confirmado empiricamente) — não precisa apagar nada manualmente antes.

**Fora do escopo desta decisão** (fica para tarefa futura, se o usuário pedir): automação de CI/GitHub Actions do build, criação de tag/release e upload para GitHub Releases. `darklua` cobre só o passo de bundle local — nenhum `require()` dentro de `src/**` foi ou deve ser alterado por causa dele; o código-fonte continua modular, o bundle é gerado, nunca escrito à mão.

## Contrato com `runtime`/`services`

- `cli` consome a API pública de `runtime` (`DataModel.new`, `Instance.new`, etc.) e depende de `services` só através do registro central que `services` expõe — nunca importa um módulo interno de `src/services/<Classe>.luau` diretamente por fora da API pública.
