# Confirmação de task-runtime-012 — isolamento dos cenários 1/2/3a/3b em `Integration.spec.luau`

Revisão de confirmação (não é achado novo — é validação independente do relatório do coder,
que já tinha marcado a tarefa `done` sem esperar revisão; movida para `review` pelo
orquestrador antes desta checagem). Read-only. Nenhum arquivo de `src/runtime/` foi editado
por mim. Todo repro extra rodou sobre **cópias** de `Signal.luau`/`Instance.luau`/
`Scheduler.luau`/`ThreadBroker.luau`/`Integration.spec.luau` em
`%TEMP%\luaubench-revisor-012-repro`, removido ao final (`rm -rf` confirmado).

Lune usado: `C:\Users\hakor\.rokit\bin\.rokit\tool-storage\lune-org\lune\0.10.5\lune.exe`
(binário real por trás do shim do Rokit — o shim `C:\Users\hakor\.rokit\bin\lune.exe` falha
fora de um diretório com manifesto Rokit, então a cópia de scratch precisou do binário direto;
mesma versão `0.10.5` que `.luaurc` referencia e que as revisões anteriores usaram). `luau-lsp`
1.69.0.

## 1. Reprodução independente da validação do coder

Copiei `Signal.luau`, `ThreadBroker.luau`, `Instance.luau`, `Scheduler.luau` e
`Integration.spec.luau` para o diretório de scratch e reverti **só** `Signal.luau:Wait()`
para `coroutine.resume` cru (bypassando `ThreadBroker.Resume`), exatamente a regressão do
achado GRAVE 2 original:

```lua
Wait = function(_self: Signal<T...>): T...
    local co = coroutine.running()
    connect(listeners, function(...: T...)
        local ok, err = coroutine.resume(co, ...)
        if not ok then error(err, 0) end
    end, true)
    return coroutine.yield()
end,
```

Rodando o `Integration.spec.luau` sem alterações contra essa cópia, ele já falha na primeira
asserção nova (linha da instrumentação do cenário 1), como esperado de um `test()` sem
`pcall`. Para ver todas as falhas de uma vez (mesma técnica descrita pelo coder), apliquei um
harness diagnóstico *só nesta cópia de scratch* (`pcall` em volta de `run()` dentro de `test()`,
nunca no arquivo real) e rodei de novo:

```
[FAIL] 1. Spawn + Heartbeat:Wait() + StepOnce -> ...            (ThreadBroker ainda managed)
[FAIL] 2. Spawn + WaitForChild sem timeout + Parent -> ...      (ThreadBroker ainda managed)
[FAIL] 3a. Run() termina sozinho ... (caso Heartbeat:Wait)      (capturedManagedDuringFire == true)
[FAIL] 3b. Run() termina sozinho ... (caso WaitForChild+Parent) (capturedManagedDuringFire == true)
[PASS] 4. WaitForChild(nome, 0.05) ...
[PASS] 5. WaitForChild(nome, 5) sob StepOnce ...
[FAIL] 6. Heartbeat:Wait() seguido de error() -> ...            (ThreadError aponta pra thread errada)
[PASS] 7. corrida deadline x ChildAdded ...
[PASS] 8. erro no primeiro de dois listeners ...

4/9 testes passaram
```

**Confirmado: exatamente os cenários 1, 2, 3a, 3b e 6 falham (4/9), nem mais nem menos** —
bate byte a byte com o que o coder relatou no board. Os cenários 4/5/7/8 não dependem do
roteamento de `Signal:Wait()` por `ThreadBroker` (4/5 exercitam o timeout via `WakeAfter`
direto; 7 é sobre a corrida `cancelled` de `WaitingEntry`; 8 é sobre isolamento de erro em
`Fire`, que continua intacto mesmo com a regressão) — coerente com a regressão ser isolada a
um único caminho (`Signal:Wait()`).

Contra o código real (`src/runtime/`, não revertido), rodei os mesmos arquivos sem a
instrumentação diagnóstica: `Integration.spec.luau` **9/9 PASS**.

## 2. Rede de segurança de `IsAlive()` — não foi enfraquecida

`git diff -- src/runtime/Scheduler.luau` mostra que o único arquivo tocado pela tarefa
task-runtime-012 é `src/runtime/Integration.spec.luau` — confirmado por `git status`/
`git diff --stat`: `Scheduler.luau`, `Scheduler.spec.luau` e `ThreadBroker.luau` aparecem
modificados, mas pelo diff é claro que essas mudanças pertencem a task-runtime-011
(chamadas de `ThreadBroker.RunCleanups` adicionadas em `resumeThread`/`Cancel`/`IsAlive`,
mais o comentário de cabeçalho sobre o achado MÉDIO de task-011), tarefa paralela e
independente, não relacionada a task-012.

O corpo de `Scheduler.IsAlive()` continua podando `liveThreads` por
`coroutine.status(co) == "dead"` exatamente como antes (a única adição do diff dentro de
`IsAlive` é uma chamada a `ThreadBroker.RunCleanups(co)`, que não afeta a lógica de poda em
si nem a torna mais permissiva) — a rede de segurança não foi removida, reduzida nem
contornada. `git diff -- src/runtime/Integration.spec.luau` confirma que o `.spec` em si não
toca `Scheduler.luau`.

## 3. Técnica do "segundo listener depois do Spawn alvo" — determinística, não corrida de timing

Verifiquei em `Signal.luau`:

- `connect()` (linha 53-72) registra via `table.insert(listeners, listener)` — sempre no fim
  do array, preservando ordem de chamada de `Connect`/`Once`.
- `Fire()` (linha 111-156) tira um snapshot copiando `listeners` NA MESMA ORDEM
  (`for _, listener in listeners do table.insert(snapshot, listener) end`) e itera esse
  snapshot sequencialmente (`for _, listener in snapshot do ... end`), cada listener isolado
  por `pcall` individual, um de cada vez, síncrono — não há yield/concorrência entre um
  listener e o próximo dentro do mesmo `Fire`.

Como o listener interno de `Signal:Wait()` (registrado dentro do `Spawn` alvo, quando a
thread chega no `scheduler.Heartbeat:Wait()`/`parent:WaitForChild(...)`) é conectado **antes**
do segundo listener de instrumentação (registrado depois, no corpo do teste), ele
necessariamente ocupa um índice anterior no array `listeners`, e portanto é executado
**antes** dentro do mesmo laço de `Fire` — sem exceção possível, dado que Luau é
single-threaded e o laço é uma iteração de array comum, não uma fila reordenável por
prioridade/timing. Isso é uma garantia estrutural do código (ordem de inserção + iteração
sequencial síncrona), não uma coincidência de agendamento.

Encadeando com `Scheduler.tick()`/`Run()`: `fireProtected` chama `signal:Fire(...)` uma vez
por tique, e só depois que `Fire` retorna (todos os listeners já rodaram, incluindo a
continuação de `Wait()` e o probe) o controle volta para `tick()` e depois para `Run()`, que
só então chama `IsAlive()` de novo. Não existe caminho pelo qual `Run()`/`IsAlive()` seja
chamado **entre** os dois listeners do mesmo `Fire` — confirmado lendo o corpo de `tick()` e
`Run()` (nenhuma chamada a `IsAlive()` entre `resumeDueWaiting`/`fireProtected(heartbeat)` e o
fim do laço `while`). A instrumentação dos cenários 1/2 (sem `Run()`, só `StepOnce` chamado
manualmente pelo teste) é ainda mais direta: `StepOnce` só chama `tick()`, que não invoca
`IsAlive()` em nenhum ponto — confirmado lendo o corpo de `Scheduler.StepOnce`.

## 4. Regressão contra o código real

Rodei eu mesmo, sem reverter nada:

- `lune run src/runtime/Integration.spec.luau`: **9/9 PASS**.
- `lune run src/runtime/Signal.spec.luau`: **6/6 PASS**.
- `lune run src/runtime/Instance.spec.luau`: **33/33 PASS** (cresceu de 24/24 desde o
  relatório de task-009 por causa de task-runtime-014/015, não relacionado a esta tarefa).
- `lune run src/runtime/Scheduler.spec.luau`: **16/16 PASS** (cresceu de 12/12 por causa de
  task-runtime-011, não relacionado a esta tarefa).
- `git diff -- src/runtime/Integration.spec.luau`: só adiciona o `require("./ThreadBroker")` e
  as quatro instrumentações (mais comentários) nos cenários 1/2/3a/3b — nada mais no arquivo
  muda; nenhuma asserção pré-existente foi removida/enfraquecida.
- Nem `Signal.luau` nem `Instance.luau` aparecem no `git status` — não foram tocados por
  nenhuma tarefa em andamento, então a comparação "sem alterar esses arquivos" do critério de
  aceite se sustenta pelo estado real do repositório, não só pela palavra do coder.
- `luau-lsp analyze --platform=standard src/runtime/Integration.spec.luau`: exit 0, limpo.
- `grep '\bany\b' src/runtime/Integration.spec.luau`: zero ocorrências; `--!strict` na linha 1.

## Achados

Nenhum. Esta tarefa era uma correção pontual e cirúrgica de um achado MÉDIO já identificado
(rede de segurança de `IsAlive()` mascarando regressão isolada em `Signal.luau`); verifiquei os
quatro pontos pedidos e todos se confirmam exatamente como relatado pelo coder, sem
divergência. Não há achado novo de gravidade alguma nesta rodada.

## Veredito

**APROVADO.**

- Reprodução independente confirma: revertendo só `Signal.luau:Wait()` para `coroutine.resume`
  cru, os cenários 1, 2, 3a, 3b e 6 falham (4/9) — a instrumentação nova cobre exatamente a
  lacuna apontada na revisão de task-runtime-009.
- Rede de segurança de `Scheduler.IsAlive()` intacta — task-012 não tocou `Scheduler.luau`
  (as mudanças ali pertencem à task-runtime-011, paralela e não relacionada).
- Técnica do segundo listener é determinística por construção (ordem de inserção +
  iteração síncrona de array em `Signal.Fire`), não uma corrida que só funciona por sorte de
  timing.
- `Integration.spec.luau` 9/9 contra o código real; `Signal.spec`/`Instance.spec`/
  `Scheduler.spec` passam e nenhum dos dois primeiros foi tocado por nenhuma tarefa em
  andamento (confirmado por `git status`); `Scheduler.spec` cresceu por task-011, não por
  task-012. Escopo de arquivo respeitado: só `src/runtime/Integration.spec.luau` no diff desta
  tarefa. `--!strict`, zero `any`, `luau-lsp analyze` limpo.
