# Revisão task-cli-035 — RunCommand consome onCallbackError (fecha contagem dupla)

Território: `src/cli/RunCommand.luau` + `src/cli/RunCommand.spec.luau` + fixture nova
`src/cli/fixtures/run-e2e/bindtoclose-overlap/`. Read-only, self-report do coder NÃO aceito —
tudo abaixo foi reproduzido por mim, incluindo o antes/depois via `git stash`.

## 1. Suítes (rodei eu mesmo, várias vezes)

- `RunCommand.spec.luau` rodado 21 vezes seguidas nesta sessão: **19/21 com "31/31 testes
  passaram"**, teste `bindtoclose-overlap` presente e com `[PASS]` em **100% das 21 execuções**
  (nunca falhou). As 2 falhas que ocorreram foram em outros testes de "Processo real" da PARTE 4
  (persistência, `task-cli-030`), não relacionados a `BindToClose`:
  - 1x: `exit code 0 na 2ª execução, recebeu -1073740791` (linha 609, teste do `first-create-message`).
  - 1x: `fatal runtime error: Rust cannot catch foreign exceptions, aborting` (crash do processo real).
  Ambos os casos são testes que spawnam processo real (`runRealProcess`) fora do escopo desta task
  e fora do código tocado pelo diff (`RunCommand.luau` só mudou a janela de `BindToClose`, nada em
  persistência). Correção ao alegado do coder: a instabilidade conhecida não é só `http-audit`
  (`task-cli-034`) — há flakiness mais ampla nos testes de "Processo real" que spawnam
  subprocessos reais no Windows deste ambiente. Não bloqueia esta task (não é o que ela mexe, e o
  cenário do acceptance — `bindtoclose-overlap` — nunca falhou), mas vale registrar/expandir
  `task-cli-034` para cobrir a categoria toda, não só `http-audit`.
- Rodei os 16 `*.spec.luau` de `src/cli/` uma vez cada: 18+9+7+8+16+12+13+17+31+8+7+33+28+38+6+7 =
  **258/258** (a única exceção pontual foi a flakiness de `http-audit`/persistência já discutida
  acima, reproduzida e recontabilizada nas rodadas seguintes de `RunCommand.spec` isoladas).

## 2. Reprodução antes/depois — feita por mim, processo real (`lune run src/cli/main.luau run ...`)

- **DEPOIS** (código atual, fix aplicado), 3 execuções: erro aparece **1x** no stderr, `1
  error(s)`, `exitcode=1`, em todas as 3.
- Revertido `RunCommand.luau` via `git stash push -- src/cli/RunCommand.luau` (só este arquivo,
  spec e fixture ficaram intactos) para o estado anterior (listener pega-tudo de task-cli-032) —
  `DataModel.luau` já tinha o 3º parâmetro de `task-runtime-038`, chamada antiga com 2 args
  continua válida (parâmetro opcional). **ANTES**, 3 execuções: erro aparece **2x**, `2 error(s)`,
  `exitcode=1`, em todas as 3. `git stash pop` restaurado com sucesso, `git diff --stat` confirmado
  igual ao estado original antes do experimento.
- Prova, não alegação: o fix é real e a mudança de comportamento é exatamente a reivindicada.

## 3. Lógica de formatação inalterada

`parseBindToCloseThreadError` (linhas 203-218) está fora de qualquer hunk do diff — comparei
`git diff` linha a linha: só o bloco de `Execute` (linhas ~582-623) mudou, a função de parsing e a
construção do `Runtime.OutputRecord` (level/campos) são idênticas caractere a caractere entre antes
e depois. Confirmado também pela saída real: mesmo texto de erro
(`ServerScriptService.Main:N: <mensagem>`) nos dois lados do experimento acima — só a
CONTAGEM mudou, nunca o texto.

## 4. Regressões dedicadas (rodei via processo real)

- `bindtoclose` (sem erro): `0 error(s)`, `exitcode=0`. OK.
- `bindtoclose-error` isolado (sem overlap de timeout): `1 error(s)`, `exitcode=1` — nem 0 nem 2. OK.

## 5. Erro normal de script (sem BindToClose nenhum)

Fixture `run-e2e/module-error` via processo real: `1 error(s)`, `exitcode=1`, mensagem
`ReplicatedStorage.Modules.Broken:6: attempt to index nil with 'explode' (required by
ServerScriptService.Main)`. Regressão mais antiga (contagem simples de erro de script) intacta.

## 6. `--!strict` / `any`

Ambos os arquivos começam com `--!strict`. Única ocorrência de `any` em `RunCommand.luau` é dentro
de um comentário que explica um estreitamento SEM `any` (linha 518) — zero uso real. `luau-lsp
analyze --platform=standard` nos dois arquivos: 1 único diagnóstico, `RunCommand.luau:470`
("Function only returns 1 value, but 2 are required here", no `pcall(bootstrapServices)`) — **linha
fora do diff desta task**, confirmado pré-existente rodando o mesmo `analyze` contra
`git show HEAD:src/cli/RunCommand.luau` (mesmo erro aparece). Não é regressão de task-cli-035, não
bloqueia, mas fica registrado como débito pré-existente não coberto por esta tarefa.

## 7. Território

`git status`: `.claude/tasks.json` (só `column: todo → in-progress`, nada de código),
`src/cli/RunCommand.luau`, `src/cli/RunCommand.spec.luau` modificados, `src/cli/fixtures/run-e2e/
bindtoclose-overlap/` novo (2 arquivos: `default.project.json` + `server/Main.server.lua`). Nada
fora do esperado.

## 8. Contrato com `runtime` (task-runtime-038)

`DataModel.RunBindToCloseCallbacks(dataModel, scheduler, onCallbackError: ((thread, string) ->
())?)` — assinatura em `src/runtime/DataModel.luau:371-375` bate exatamente com a chamada em
`RunCommand.luau`: `Runtime.DataModel.RunBindToCloseCallbacks(game, scheduler,
onBindToCloseCallbackError)`, onde `onBindToCloseCallbackError` é `local function(...): (thread,
string) -> ()` — sem cast, sem `::`, sem gambiarra de tipo. Filtro por `ownThreads` já é interno ao
`runtime` (task-runtime-038, já revisado e aprovado antes desta task) — `cli` não conecta mais
`scheduler.ThreadError` diretamente (confirmado por grep: zero `:Connect` restante nesse sinal em
`RunCommand.luau`, só menções em comentário).

## Veredito

APROVADO.

Nenhum achado bloqueante. Dois pontos não-bloqueantes registrados para follow-up (nenhum no
território/escopo desta task):
1. Flakiness de "Processo real" mais ampla do que só `http-audit` (2 falhas em 21 execuções, ambas
   em testes de persistência/`task-cli-030`, nunca em `bindtoclose*`) — recomendo expandir
   `task-cli-034` para cobrir a categoria, não só o fixture `http-audit`.
2. `luau-lsp analyze` acusa 1 erro de tipagem pré-existente em `RunCommand.luau:470`
   (`pcall(bootstrapServices)`), fora do diff desta task e já presente em HEAD antes dela — abrir
   task de correção separada em `cli`.
