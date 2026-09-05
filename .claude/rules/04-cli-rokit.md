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

## Contrato com `runtime`/`services`

- `cli` consome a API pública de `runtime` (`DataModel.new`, `Instance.new`, etc.) e depende de `services` só através do registro central que `services` expõe — nunca importa um módulo interno de `src/services/<Classe>.luau` diretamente por fora da API pública.
