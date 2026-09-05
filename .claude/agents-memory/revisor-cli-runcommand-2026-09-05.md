# Revisão `task-cli-006` — ScriptRunner + OutputFormatter + RunCommand (pipeline `luaubench run` ponta a ponta)

Data: 2026-09-05. Read-only, `D:\UserData\Documents\GitHub\luaubench`. Nenhum self-report do coder foi aceito sem reprodução direta — todo item abaixo foi rodado por mim, com `lune 0.10.5` real (`C:\Users\hakor\.rokit\bin\lune`).

## Contexto lido

- `.claude/tasks.json` → `task-cli-006` (título, description, acceptance completos).
- `.claude/agents-memory/arquiteto-cli-2026-09-05.md` — inteiro (763 linhas), Decisões 3/4/5/7/11/13, seção "Pipeline", "Contrato entre territórios", "Fidelidade vs. pragmatismo", "Riscos e decisões".
- `src/cli/ScriptRunner.luau` + spec, `src/cli/OutputFormatter.luau` + spec, `src/cli/RunCommand.luau` + spec (código completo, não só grep).
- `git diff` de `src/cli/Messages.luau`, `src/cli/init.luau`, `src/cli/init.spec.luau`.
- As 3 fixtures novas em `src/cli/fixtures/run-e2e/{basic,module-error,timeout}` (conteúdo completo).

## O que foi verificado por reexecução própria (não por leitura do relatório do coder)

### 1. Contagem de specs — CONFIRMADA EXATA
Rodei cada `.spec.luau` individualmente via `lune run`:
- `src/runtime/*.spec.luau`: 29+12+63+9+20+16+7+6 = **162/162**
- `src/services/*.spec.luau` + `src/services/behavior/*.spec.luau`: 9+3+14+5+16+4+8+11+3 = **73/73**
- `src/cli/*.spec.luau` (15 arquivos): 13+7+8+10+12+13+17+11+6+7+28+8+17+5+7 = **169/169**
- Total = 162+73+169 = **404 asserções**, batendo exatamente com a alegação.

### 2. Binário real, stdout/stderr separados por redirecionamento de verdade — CONFIRMADO
```
lune run src/cli/main.luau run src/cli/fixtures/run-e2e/basic 1>out 2>err
```
- `out`: `ServerScriptService.Main: count is 15` + linha de sumário + linha de contagem — só isso.
- `err`: `warn  ServerScriptService.Main: cache miss for demo-key` com ANSI (`\x1b[33m...\x1b[0m`).
- Nenhuma string `THIS SHOULD NEVER RUN` em nenhum dos dois streams (grep -c = 0 nos dois).
- `require(game.ReplicatedStorage.Modules.Counter)` com `setmetatable`/OOP funcionou de ponta a ponta (`Counter.new(10):Add(5):Get()` → 15).

### 3. Exit codes reais — CONFIRMADOS nos 3 cenários + 2 extras
- `basic` → **0**.
- `module-error` → **1** (`ErrorCount >= 1`).
- `.project.json` com campo desconhecido (`unknown-field`) → **2**, mensagem `error: [project/unknown-field] Unknown field "unknownField"...` — sem stack trace.
- Extra: JSON de verdade malformado (`malformed` fixture) → **2**, `Failed to parse ... as JSON: Unterminated object on line 4 column 1` — limpo.
- Extra: projeto só com warnings → **0** (confirma que warning não vira erro).

### 4. Reatribuição de linha/nome de erro de módulo — CONFIRMADO
`run-e2e/module-error` real:
```
error ReplicatedStorage.Modules.Broken:6: attempt to index nil with 'explode' (required by ServerScriptService.Main)
```
Linha 6 bate com `wc -l` do fixture (última linha, `return nothing.explode`). Cita o módulo (nome+linha) E o Script de origem (`required by ...`). Nenhum marcador cru `[string "..."]` vazou. A linha seguinte ao `require` que falhou (`print("THIS SHOULD NEVER RUN...")`) nunca rodou.

### 5. `--timeout` interrompendo `while true do task.wait() end` — CONFIRMADO E CRONOMETRADO
- Baseline sem loop: `real 0m0.887s` (overhead fixo do Lune).
- `--timeout 2` no fixture `timeout`: `real 0m2.846s` (≈ baseline + 2s).
- `--timeout 0.5`: `real 0m1.438s` (≈ baseline + 0.5s).
- Exit code do timeout é **0** (não é erro de script, é corte — coerente com o desenho).

### 6. `LocalScript` / `Enabled=false` / `Script` fora de container — CONFIRMADO NUNCA EXECUTAM
Fixture `basic` tem os três casos (`ClientEntry.client.lua`, `Muted.server.lua` com `Muted.meta.json{Enabled:false}`, `NotRun.server.lua` sob `ReplicatedStorage`). `grep -c "THIS SHOULD NEVER RUN"` = 0 em stdout e stderr, com e sem `--no-color`. Sumário reporta corretamente `1 LocalScript(s) not executed`, `1 Script(s) skipped (not under a configured server container)`, `1 Script(s) skipped (Enabled = false)`.

### 7. `--no-color` / `NO_COLOR` — CONFIRMADO POR GREP DE BYTE ANSI (`\x1b`)
- Sem flag/env: 1 ocorrência de `\x1b` no stderr (cor ligada por padrão).
- Com `--no-color`: 0 ocorrências em stdout e stderr.
- Com `NO_COLOR=1` (sem `--no-color`): 0 ocorrências em stdout e stderr.

### 8. Ordem determinística — CONFIRMADO BYTE A BYTE, incluindo caso de borda
Projeto de teste com 4 scripts (`ServerScriptService/{A,B}.server.lua`, `Workspace/{A,C}.server.lua}` — nomes duplicados **entre containers diferentes**, caso não coberto por nenhuma fixture existente):
```
run1 == run2 (diff vazio)
ServerScriptService.A → ServerScriptService.B → Workspace.A → Workspace.C
```
Confirma que o agrupamento por `ServerScriptContainers` (não a ordem alfabética de `tree.Scripts`) está correto mesmo com nomes colidindo entre containers.

### 9. `RunCommand.Execute` planeja ANTES de registrar/materializar — CONFIRMADO por leitura de código E por comportamento
Leitura de `RunCommand.luau`: `locateAndPlan` (linha 155) roda e retorna **antes** de qualquer `Runtime.Scheduler.new()`/`Runtime.DataModel.new()`/`Services.Bootstrap` (linhas 165-171) — se `plan == nil`, a função retorna na linha 156-163 sem alcançar essas chamadas. Confirmado experimentalmente: rodar contra um projeto com erro de projeto nunca produz nenhuma saída de script (stdout vazio), só o diagnóstico em stderr e exit 2.

### 10. `--timeout` como rede de segurança, não watchdog — CONFIRMADO QUE A LIMITAÇÃO É REAL
Criei um fixture `while true do end` (sem yield) fora do repo (`/tmp/hang-test`) e rodei:
```
timeout 6 lune run src/cli/main.luau run /tmp/hang-test --timeout 1 --no-color
→ exit 124 (o `timeout` do SO teve que matar o processo)
```
Ou seja: **o `--timeout` de 1s do LuauBench não teve efeito nenhum** contra um loop sem yield — o processo continuaria rodando indefinidamente até ser morto de fora. Isso é exatamente a limitação que o código documenta (`Scheduler:Run` só consulta `shouldContinue` entre tiques; um loop sem yield trava o `coroutine.resume` de verdade) — **não é bug, é a limitação aceita e corretamente declarada**, mas é bom que o usuário final saiba que rodar um script assim vai exigir Ctrl+C manual.

### 11. `git diff` de `Messages.luau`/`init.luau`/`init.spec.luau` — CONFIRMADO COERENTE
- `Messages.luau`: `54 insertions(+)`, **0 deletions** — só bloco novo no fim (`OutputFormatter`/`RunCommand` messages), nenhuma linha antiga tocada.
- `init.luau`: substituição real e intencional do placeholder `Messages.RunPipelineNotImplementedYet()` pela chamada de verdade a `RunCommand.Execute`, `Cli.RunProject` adicionada como documentado no desenho, comentários atualizados coerentemente com o novo comportamento.

### 12. `--!strict` sem `any` — CONFIRMADO
`grep -n '\bany\b'` vazio nos três arquivos novos; `luau-lsp analyze --platform=standard` com os typedefs do Lune 0.10.5 (exceto `fs.luau`, que tem um bug de carregamento de tipo `DateTime.DateTime` não relacionado a este código e não usado por nenhum dos 3 arquivos) devolveu **zero diagnósticos** para `ScriptRunner.luau`, `OutputFormatter.luau`, `RunCommand.luau`.

### 13. Tentativas ativas de quebrar — resultado misto (achados abaixo)
- Projeto **sem nenhum Script**: exit 0, sumário `0 Script(s) executed, 0 ...` — correto, não quebra.
- Dois Scripts com **mesmo nome em containers diferentes**: ordem determinística correta (item 8).
- `require` cíclico (`A requer B requer A`): erro limpo `Requested module was required recursively`, capturável por `pcall`, CLI não trava nem crasha, exit 0 (erro tratado pelo script).
- Módulo que retorna 2 valores: erro limpo `Module code did not return exactly one value`, sem vazamento.
- **Achado real (não hipotético): erro de `$properties` inválido vaza o caminho absoluto de disco do módulo INTERNO do LuauBench.** Ver "Achados" abaixo — é o único ponto onde encontrei algo que se aproxima de "vazar informação crua do motor".
- Confirmei também que um erro de projeto (`$properties` inválido) que acontece **depois** de um Script já ter rodado com sucesso ainda vence na prioridade do exit code: script imprimiu normalmente (`ran fine...`), mas o exit code final foi **2** (erro de projeto), não 0 — bate com o comentário do próprio `RunCommand.luau` (linhas 36-42). **Esse cenário específico não tem teste automatizado** (`RunCommand.spec.luau` não cobre a combinação "script roda bem" + "erro de materialize simultâneo") — verifiquei manualmente, funciona, mas é uma lacuna de cobertura.

## Achados

### [MÉDIO] `src/cli/TreeMaterializer.luau:136` (via `Messages.luau:345-347`, exposto por `RunCommand.luau` no pipeline agora ligado)
**Problema:** um erro de `$properties` inválido no `.project.json` (nome errado, propriedade somente-leitura) chega ao usuário com o caminho absoluto de disco e a linha do MÓDULO INTERNO do LuauBench embutidos na mensagem, não apenas a informação do projeto do usuário.

**Cenário:** usuário escreve `"$properties": {"Gravty": 10}` (typo) em qualquer nó do `.project.json`. `luaubench run` produz:
```
error: [materialize/invalid-property] Could not apply "$properties.Gravty" at "tree.ServerScriptService":
D:\UserData\Documents\GitHub\luaubench\src\cli\TreeMaterializer:136: Gravty is not a valid member of
ServerScriptService "DataModel.ServerScriptService" (node: tree.ServerScriptService, field: Gravty)
```
O motivo é técnico: `TreeMaterializer.applyProperties` (linha 136) faz `pcall(function() writable[key] = value end)`, e o `__newindex` real do `runtime` levanta o erro com `error(msg, 2)` (ou equivalente) — atribuindo a posição ao CALL SITE do `pcall`, que é o próprio `TreeMaterializer.luau`, não o script do usuário. Diferente do erro de script real (onde o call site É o arquivo do usuário, e citar ele é correto/fiel ao Roblox), aqui o call site é sempre um módulo interno do CLI — então o `tostring(err)` embutido cru em `Messages.MaterializePropertyAssignmentFailed` está vazando um detalhe de implementação (caminho de instalação do LuauBench no disco de quem roda) que não ajuda o usuário a corrigir o `.project.json` e é exatamente a categoria de coisa que a regra 04 pede para nunca vazar ("nunca stack trace cru do parser").

Não é um crash e não é uma stack trace multi-linha (`stack traceback: ...`) — a mensagem continua com `Code`/`NodePath`/`Field` corretos e ainda é acionável (o nome real do problema, "Gravty is not a valid member...", está lá) — por isso não é GRAVE/ALTO. Mas é um vazamento real, reproduzido, do tipo que o item 13 do pedido pediu para caçar ativamente.

**Nota de escopo:** o bug de origem vive em `TreeMaterializer.luau` (task-cli-004, já fechada e revisada antes — `.claude/agents-memory/revisor-cli-treematerializer-2026-09-05.md` não menciona isto), não em nenhum dos três arquivos novos desta tarefa (`ScriptRunner`/`OutputFormatter`/`RunCommand`). Só ficou visível agora porque `task-cli-006` é a primeira vez que o pipeline inteiro roda de ponta a ponta contra um `.project.json` de verdade — antes só aparecia em specs com fixtures controladas. Não bloqueia a aprovação desta tarefa especificamente, mas é uma ressalva real a corrigir (task nova, território `cli`).

**Correção sugerida:** em `Messages.MaterializePropertyAssignmentFailed`, ou em `TreeMaterializer.applyProperties`, extrair só a mensagem depois do primeiro `: ` do erro (mesmo padrão de `stripDataModelPrefix`/`tryReattributeModuleError` que `OutputFormatter` já usa para esconder detalhe de implementação), citando só `NodePath`/`Field`/o texto real do motor sem o prefixo de chunk interno.

### [BAIXO] `src/cli/RunCommand.spec.luau` — lacuna de cobertura para a prioridade de exit code
**Problema:** o comentário do cabeçalho de `RunCommand.luau` (linhas 36-42) documenta explicitamente que um erro de projeto tem prioridade sobre sucesso de script no exit code final, mesmo quando scripts já rodaram sem erro — mas nenhum teste em `RunCommand.spec.luau` exercita esse cenário combinado (só testa "só erro de projeto" e "só erro de script" separadamente).

**Cenário:** um projeto com um Script válido que roda com sucesso E um `$properties` inválido em outro nó. Verifiquei manualmente que o comportamento está correto (exit code 2, script rodou e imprimiu normalmente) — mas é exatamente o tipo de interação entre dois subsistemas que regride silenciosamente sem uma asserção própria.

**Correção sugerida:** adicionar um caso a `RunCommand.spec.luau` combinando um Script que imprime com sucesso e um nó com `$properties` inválido no mesmo projeto, afirmando `ExitCode == 2` e que o stdout do script ainda aparece.

## O que NÃO achei (verificado e descartado)

- Nenhum vazamento de stack trace multi-linha do motor Luau em nenhum cenário testado (erro de script, erro de módulo, JSON malformado, campo desconhecido, ciclo de `require`, módulo com retorno múltiplo).
- Nenhuma race/inconsistência de ordem determinística, inclusive com nomes duplicados entre containers.
- Nenhum caso de "silenciosamente executa o que não deveria" ou "silenciosamente não executa o que deveria".
- `--timeout` não finge resolver o caso sem yield — a limitação é real e poderia congelar o terminal do usuário até um Ctrl+C manual se ele rodar um script realmente sem nenhum yield sem saber disso; isso já está documentado no código e no desenho do arquiteto, então não é surpresa, mas vale reforçar na documentação de usuário final (fora do escopo desta tarefa).

## Veredito

**APROVADO COM RESSALVAS**

O pipeline `luaubench run` de ponta a ponta funciona de verdade — reproduzi eu mesmo, com processo real e redirecionamento real, todas as alegações centrais do coder: contagens de teste exatas (404 = 162+73+169), execução real de `setmetatable`/OOP entre `Script`→`ModuleScript`, separação `stdout`/`stderr`, os três exit codes, reatribuição de erro de módulo, `--timeout` como rede de segurança cronometrada, `LocalScript`/`Enabled=false`/fora-de-container nunca executando, `--no-color`/`NO_COLOR`, ordem determinística (inclusive com nomes duplicados entre containers), ordem "planejar antes de materializar", `--!strict` sem `any`, e o diff append-only de `Messages.luau`.

As duas ressalvas (MÉDIO: vazamento de caminho de módulo interno em erro de `$properties`; BAIXO: lacuna de teste para prioridade de exit code) não invalidam o pipeline nem os critérios de aceite específicos de `task-cli-006` — a primeira tem raiz em `TreeMaterializer.luau` (task-cli-004 já fechada), só ficou visível agora que o pipeline real está ligado ponta a ponta.
