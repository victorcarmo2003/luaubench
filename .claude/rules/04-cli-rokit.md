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

- Não invente campo do `.project.json` que o Rojo não define. Se o parsing precisar de algo que o formato do Rojo não cobre, isso é uma extensão do LuauBench e vive em campo claramente namespaced (ex: `"luaubench": {...}` dentro do `.project.json`), nunca sobrescrevendo semântica do Rojo.
- `pesquisador` confirma o formato exato do `.project.json`/sourcemap antes de `coder-cli` implementar o parser, se houver dúvida sobre um campo.

## Distribuição via Rokit

- Build final é executável standalone via `lune build`, publicado em GitHub Release com tag semver (`vMAJOR.MINOR.PATCH`).
- Manifesto compatível com Rokit (ex: `rokit.toml` do próprio projeto, ou o formato que o Rokit espera do binário publicado) mantido atualizado a cada release — `rokit add victorcarmo2003/luaubench` precisa continuar funcionando depois de qualquer mudança de build.
- Nenhum outro canal de instalação (script `curl | sh`, instalador separado) entra sem decisão explícita do usuário — Rokit é o caminho oficial único.

## Contrato com `runtime`/`services`

- `cli` consome a API pública de `runtime` (`DataModel.new`, `Instance.new`, etc.) e depende de `services` só através do registro central que `services` expõe — nunca importa um módulo interno de `src/services/<Classe>.luau` diretamente por fora da API pública.
