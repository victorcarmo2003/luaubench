# Revisão conjunta — Signal.luau / Instance.luau / Scheduler.luau (task-runtime-001/002/003)

Revisão read-only de `src/runtime/Signal.luau`, `src/runtime/Instance.luau`, `src/runtime/Scheduler.luau` e seus `.spec.luau`. Testes rodados de verdade com `D:\Moved\.rokit\tool-storage\lune-org\lune\0.10.5\lune.exe` (não aceitei os números do relatório dos coders sem re-rodar) e tipagem verificada com `luau-lsp analyze --platform=standard` (`D:/Moved/.rokit/tool-storage/johnnymorganz/luau-lsp/1.68.1/luau-lsp.exe`, após gerar `.luaurc`/typedefs via `lune setup` para resolver `@lune/task`).

## Números confirmados

- `Signal.spec.luau`: **6/6** — confere com o relatado.
- `Instance.spec.luau`: **24/24** — confere com o relatado.
- `Scheduler.spec.luau`: **12/12** — confere com o relatado.
- `luau-lsp analyze` nos três arquivos: sem erros de tipo.

Os três specs passam, mas **nenhum deles exercita o cenário real de integração** (uma thread gerida por `Scheduler:Spawn`/`Scheduler:Run()` que suspende via `Signal:Wait()` de outro módulo, ou via `Instance:WaitForChild` rodando dentro do laço real de `Run()`). Escrevi repros isolados (fora de `src/runtime/`, apagados ao final de cada verificação — nenhum arquivo do território foi editado) para testar exatamente essa integração. Os resultados seguem abaixo.

---

## Achados (ordenados por gravidade)

### [GRAVE] Instance.luau (WaitForChild com timeout) × Scheduler.luau — timeout não é respeitado quando a thread é dirigida por `Scheduler:Run()`

**Problema:** `WaitForChild(name, timeout)` (`Instance.luau:380-419`) faz polling via `@lune/task.wait` nativo. Quando chamado de dentro de uma thread criada por `Scheduler:Spawn` **enquanto `Scheduler:Run()` está de fato rodando o laço principal**, o timeout deixa de ser respeitado — a resolução leva ordens de grandeza mais tempo que o pedido.

**Cenário de falha (reproduzido empiricamente, 3 variações para isolar a causa):**
1. Coroutine crua (`coroutine.create`/`coroutine.resume`, sem Scheduler) + laço externo manual de `nativeTask.wait` → `WaitForChild("X", 0.05)` resolve em **~0.065s**. Correto.
2. `Scheduler:Spawn` + laço externo **manual** (sem chamar `Scheduler:Run()`) → mesma chamada resolve em **~0.064s**. Correto.
3. `Scheduler:Spawn` + **`Scheduler:Run()` de verdade dirigindo o laço** → a mesma chamada (`timeout = 0.05`) **não resolveu em 2 segundos de wall-clock** (só retornou porque um `shouldContinue` de segurança externo forçou `Run()` a parar aos 2s — sem esse guard, o teste teria ficado preso indefinidamente).

A diferença entre (2) e (3) isola a causa em `Scheduler:Run()` especificamente (não em `Scheduler:Spawn`, não em coroutines aninhadas em geral): o laço de `Run()` (tick + `LuneTask.wait(sleepFor)` a cada iteração) parece "esfomear" o timer nativo independente que o polling de `WaitForChild` registra por conta própria — o mesmo risco que o comentário do coder em `Instance.luau:380-407` já sinalizava como "Incerto", mas o `pesquisa-scheduler-lune-2026-09-04.md` citado **não cobre esse cenário específico** (interação de `Scheduler:Run()` real com um timer nativo concorrente e não-gerido).

**Por que isso importa:** o critério de aceitação de task-runtime-002 é explícito — "com timeout, retorna nil após o tempo se o filho não aparecer". Isso é falso na prática assim que o `Scheduler` real (não o teste isolado do próprio `Instance.spec.luau`, que nunca roda dentro de `Scheduler:Run()`) está dirigindo a execução — que é exatamente como um script de usuário real vai rodar (via `Sandbox.Run` → `Scheduler:Spawn`, task-006).

**Correção:** a decisão de "pollar via `@lune/task.wait` nativo para não acoplar a `Scheduler.luau`" (ver ponto 2 da tarefa) precisa ser revisitada — ela não é tecnicamente segura como está, mesmo sendo bem documentada como incerta. `pesquisador` precisa confirmar o mecanismo exato de como o executor assíncrono do Lune agenda/prioriza múltiplos timers nativos concorrentes quando um deles é dirigido por um laço Luau síncrono como `Scheduler:Run()`. Alternativa arquitetural: `WaitForChild` com timeout devolver o controle para quem o chama de um jeito que permita `Scheduler` registrar o deadline nas próprias filas (`delayed`/`waiting`) em vez de usar um timer nativo paralelo e invisível ao `Scheduler`.

---

### [GRAVE] Signal.luau × Scheduler.luau — `Signal:Wait()` não respeita o "ponto único de `coroutine.resume`", `liveThreads` vaza e `Scheduler:Run()` nunca termina sozinho

**Problema:** `Signal:Wait()` (`Signal.luau:88-97`) resume a coroutine que espera com um `coroutine.resume(thread, ...)` **direto**, dentro do próprio `Fire`. Isso é, por desenho, um segundo ponto de `coroutine.resume` **fora** de `Scheduler.luau:resumeThread` (o "ponto único" que a própria tarefa exige — "Ponto único de `coroutine.resume`: toda retomada de thread gerida passa por ele"). Quando uma thread gerida por `Scheduler:Spawn` termina sua vida através desse resume (não através de `Scheduler:Wait`/`Delay`/`Defer`), o bookkeeping `self.liveThreads[co] = nil` — que só roda dentro de `resumeThread` — **nunca acontece**.

**Cenário de falha (reproduzido empiricamente, 2 variações):**
```lua
scheduler:Spawn(function()
    scheduler.Heartbeat:Wait() -- Signal:Wait puro
    finished = true
end)
scheduler:StepOnce(0.016)
-- finished == true, mas scheduler:IsAlive() == true PARA SEMPRE
```
```lua
scheduler:Spawn(function()
    parent:WaitForChild("Alvo") -- sem timeout -> ChildAdded:Wait() por baixo
    wfcFinished = true
end)
child.Parent = parent
-- wfcFinished == true, mas scheduler:IsAlive() == true PARA SEMPRE
```
Rodei um terceiro caso chamando `Scheduler:Run()` sem `shouldContinue`: **o laço nunca teria terminado sozinho** (só não travou o teste porque usei um `shouldContinue` de guarda para forçar a saída aos 0.5s).

**Por que isso importa:** `IsAlive reflete corretamente threads/conexões vivas` é um critério de aceitação explícito de task-runtime-003, e é falso. `WaitForChild` sem timeout (a forma "correta"/fiel ao Roblox, exigida pela regra 02: "espera de verdade, nunca retorna nil cedo") é, por construção, exatamente o gatilho deste bug — ou seja, o caminho que a própria tarefa pede como o mais fiel ao Roblox real é o que quebra a garantia central do scheduler ("`Run()` continua enquanto `IsAlive()`... script que roda e não deixa nada pendente termina o processo sozinho"). Na prática, `luaubench run` de um script real que usa `WaitForChild` sem timeout (ou qualquer `Signal:Wait()` custom, inclusive de `services` futuros como `Touched`) como a última operação relevante nunca terminaria sozinho.

**Correção:** como `Signal.luau` corretamente não pode depender de `Scheduler.luau` (zero dependências é o desenho certo), a correção precisa viver em `Scheduler.luau`: podar `liveThreads` verificando `coroutine.status(thread) == "dead"` para as entradas existentes (por exemplo dentro de `IsAlive()` ou a cada `tick()`), em vez de confiar exclusivamente em `resumeThread` ser o único lugar que atualiza esse mapa.

---

### [ALTO] Signal.luau — `Fire` não isola listeners entre si; erro em um listener cancela os seguintes no mesmo disparo (divergência não documentada do Roblox real)

**Problema:** o laço de disparo em `Signal.Fire` (`Signal.luau:106-127`) chama `listener.callback(...)` diretamente, sem `pcall` por listener. Se um callback lança erro (via `error()` direto, ou via a re-propagação de erro que o próprio `Wait()` faz), o laço `for _, listener in snapshot do ... end` é interrompido — os listeners seguintes na mesma chamada de `Fire` **nunca rodam para aquele disparo específico**.

**Cenário de falha (reproduzido empiricamente):**
```lua
signal:Connect(function() error("erro no primeiro listener") end)
signal:Connect(function() secondRan = true end)
pcall(function() signal:Fire() end)
-- secondRan == false
```
No Roblox real, cada função conectada a um evento roda em sua própria coroutine — erro ou yield em uma conexão nunca afeta as demais conexões do mesmo evento. Esta implementação diverge disso e **não documenta a divergência em lugar nenhum** (viola regra 00: "Toda divergência de comportamento... é documentada explicitamente... nunca silenciosa"). Na prática: se um Script tem um listener de `ChildAdded` com bug que erra, qualquer outro listener de `ChildAdded` de outro Script/Service (ex: um `RunService`/`services` futuro observando o mesmo evento) deixa de disparar para aquele evento específico, sem nenhum sinal de que isso aconteceu.

**Correção:** envolver cada `listener.callback(...)` num `pcall` individual dentro do laço de `Fire`, repassando o erro para um canal central (ex: propagar para quem tiver acesso ao "ponto único" de erro do sistema que estiver usando este Signal) sem abortar os listeners seguintes — ou, se a decisão for manter o comportamento atual, documentar explicitamente a divergência no código e levar para o `arquiteto` decidir se é aceitável.

---

### [ALTO] Scheduler.luau — `ThreadError` pode reportar a thread errada quando o erro vem de uma continuação de `Signal:Wait()`

**Problema:** consequência direta do achado anterior. Quando uma thread suspensa via `scheduler.Heartbeat:Wait()` (ou qualquer `Signal:Wait()`) erra depois de acordar, o erro é re-lançado (via `error(err, 0)`, dentro de `Signal.luau:88-97`) para dentro de quem chamou `Fire` — não necessariamente a thread original. `fireProtected` (`Scheduler.luau:165-172`) então reporta `coroutine.running()` como a thread culpada — que é a thread hospedeira de `tick()`/`Run()`, **não** a thread que de fato errou.

**Cenário de falha (reproduzido empiricamente):**
```lua
local waiterHandle = scheduler:Spawn(function()
    scheduler.Heartbeat:Wait()
    error("erro no waiter de verdade")
end)
scheduler:StepOnce(0.016)
-- reportedThread (recebido em ThreadError) ~= waiterHandle
```
**Por que isso importa:** rule 00/01 exigem que mensagem de erro tenha contexto suficiente pra debugar sem re-rodar (qual thread/script). Quando `Sandbox.luau` (task-006) for construído sobre `ThreadError` para montar `OutputRecord{scriptName=...}`, essa atribuição errada vai apontar o dedo pro script errado.

**Correção:** mesma raiz do achado 2 — resolver ali resolve isto também (ou, no mínimo, `fireProtected` precisaria alguma forma de recuperar a thread real de origem, o que não é possível hoje porque `Signal.luau` não expõe qual thread estava esperando).

---

### [MÉDIO] Scheduler.luau — `:: any` no construtor é evitável e viola regra 01 sem necessidade

**Problema:** `Scheduler.new()` (`Scheduler.luau:432`) usa `(setmetatable(raw, Scheduler) :: any) :: Scheduler`. O comentário do coder (linhas 426-431) justifica isso como "mesmo padrão de qualquer OOP baseado em metatable em Luau estrito" e alega que nenhuma assinatura pública fica com `any`.

**Verificação:** copiei o arquivo para um diretório isolado e troquei a linha por `(setmetatable(raw, Scheduler) :: unknown) :: Scheduler` — rodei `luau-lsp analyze --platform=standard` e **o arquivo tipa limpo, sem nenhum erro**, exatamente como `Instance.luau:75` já faz para o problema estruturalmente idêntico (mesmo comentário, aliás: "cast em duas etapas via `unknown` (nunca `any`, regra 01)"). Ou seja, o próprio território já tem o padrão correto documentado e comprovadamente funcional — `Scheduler.luau` só não o usou.

**Por que isso importa:** regra 01 é explícita: "Sem `any`... sem exceção, inclusive script de teste." Não é uma exceção aceitável dado que há prova, no mesmo repositório, de que o problema é solucionável sem `any`.

**Correção:** trocar `:: any` por `:: unknown` na linha 432.

---

### [BAIXO] Instance.luau — dependência de `@lune/task` não reflete no cabeçalho/desenho

**Problema:** `Instance.luau` importa `@lune/task` (linha 20) para o polling de `WaitForChild` com timeout, mas o comentário de cabeçalho do módulo (linhas 13-16) e o desenho do arquiteto ("Depende de: Signal.luau.") só mencionam `Signal.luau` como dependência. Não é um vazamento de sandbox (uso interno, nunca exposto ao script do usuário) nem quebra a regra de território — é só uma omissão de documentação.

**Correção:** atualizar o comentário de cabeçalho para citar a dependência de `@lune/task` explicitamente, já que ela é central para o comportamento de `WaitForChild` com timeout.

---

## Pontos específicos pedidos — respostas diretas

1. **Comentário da ordem hipotética de reparenting (`Instance.luau:143-161`):** presente, explícito, cita a ordem exata (1)-(5), menciona que não foi confirmada, cita o arquivo de pesquisa que não cobre isso, e pede validação de `pesquisador`/`revisor-runtime`. **Satisfaz o requisito — não rejeito por isso.**

2. **WaitForChild com timeout via polling nativo em vez de Signal/Scheduler:** a documentação da decisão é excelente (raciocínio detalhado, reconhece a incerteza). Mas **tecnicamente não é aceitável como está** — o achado GRAVE acima mostra que ela quebra na integração real com `Scheduler:Run()` (não é só um risco teórico "Incerto": é um bug reproduzido, com números). Para quem for integrar depois (task-006/007), a documentação atual é clara o bastante para entender a decisão, mas **não avisa que ela falha empiricamente** — isso precisa ser corrigido antes de aceitar.

3. **`fireProtected` fecha o vazamento de erro de `Heartbeat`/`Stepped:Fire`?** Sim, tecnicamente fecha *esse* caminho específico — nenhum erro escapa de dentro do `pcall` que envolve `signal:Fire(...)` em `tick()`, confirmado pelo teste próprio do coder e por leitura do código. Mas **"ponto único de `coroutine.resume` continua sendo respeitado para as demais threads geridas"? Não.** `Signal.luau:Wait()` cria um segundo ponto de resume fora do controle de `resumeThread`, e isso quebra o bookkeeping de `liveThreads` (achado GRAVE 2) e a atribuição de thread em `ThreadError` (achado ALTO 4). O `fireProtected` resolve "não derrubar o processo", mas não resolve "o scheduler continua correto depois".

4. **`:: any` no construtor de Scheduler — mecânica interna, ou vaza?** Não vaza para nenhuma assinatura pública — confirmado lendo o arquivo inteiro (só usado dentro do corpo de `Scheduler.new()`, o tipo de retorno da função continua `Scheduler`). Mas **não é uma exceção aceitável** à regra "sem `any"` — ver achado MÉDIO acima, com prova de que `unknown` resolve o mesmo problema.

5. **Imports fora do necessário:** `Signal.luau` não importa nada (confirmado). `Instance.luau` não importa `Scheduler.luau` nem `ClassRegistry.luau` (confirmado) — importa `Signal.luau` + `@lune/task` nativo (ver achado BAIXO). `Scheduler.luau` importa `Signal.luau` + `@lune/task` nativo (esperado). **Nenhuma violação de território.**

6. **Testes rodados de novo:** 6/6 (Signal), 24/24 (Instance), 12/12 (Scheduler) — todos confirmados batendo com o relatado. Mas nenhum desses testes cobre os cenários de integração real acima (thread gerida por `Scheduler` suspensa via `Signal:Wait()` de outro módulo, ou `WaitForChild` com timeout rodando dentro de `Scheduler:Run()` de verdade) — é exatamente aí que os bugs GRAVES vivem, invisíveis aos specs atuais porque cada um testa seu módulo isoladamente ou usa mocks/`coroutine.create` cru em vez do outro módulo real.

---

## Veredito por tarefa

### task-runtime-001 (Signal.luau) — **APROVADO COM RESSALVAS**
Cumpre a lista de aceitação original (Connect/Once/DisconnectAll/Fire na ordem/Wait bloqueando) e os 6/6 testes confirmam isso isoladamente. Mas o desenho de `Fire`/`Wait()` tem duas propriedades que quebram quando integradas com `Scheduler.luau` real (achados ALTO 3 e GRAVE 2/ALTO 4) — a ressalva é que este módulo não pode ser considerado "fechado" até essas propriedades serem endereçadas (mesmo que a correção termine vivendo em `Scheduler.luau`, como recomendado).

### task-runtime-002 (Instance.luau) — **REPROVADO**
O comentário de risco exigido está presente (não rejeito por isso). Mas o critério de aceitação explícito "com timeout, retorna nil após o tempo se o filho não aparecer" **falha empiricamente** assim que testado contra o `Scheduler` real (achado GRAVE 1) — a decisão de implementação (polling nativo) não é apenas "arriscada/não confirmada" como documentado, é **demonstravelmente quebrada** no cenário de uso real (script rodando via Scheduler:Spawn/Run). Isso não é aceitável para aprovação como está.

### task-runtime-003 (Scheduler.luau) — **REPROVADO**
12/12 testes passam, mas nenhum cobre o cenário que quebra: uma thread gerida que termina via `Signal:Wait()` (que é exatamente o mecanismo que o próprio `Scheduler.luau` usa internamente para expor `Heartbeat`/`Stepped` como `Signal` públicos!). O critério de aceitação explícito "IsAlive reflete corretamente threads/conexões vivas" é **falso** (achado GRAVE 2) — `Scheduler:Run()` não termina sozinho no cenário mais comum de uso real (script que termina esperando um evento). Some-se a isso o uso evitável de `any` (achado MÉDIO 5), que por si só já seria motivo de ressalva pela regra 01 ser explícita em "sem exceção".

## Veredito do conjunto

**REPROVADO.**

Cada arquivo isolado passa nos próprios testes, mas a integração real entre os três — que é o propósito explícito desta revisão — quebra três garantias centrais do projeto: (1) `Scheduler:Run()` termina sozinho quando não há mais trabalho pendente; (2) `WaitForChild` com timeout respeita o timeout pedido; (3) erro é atribuído à thread/script correto. As três quebras têm a mesma raiz: `Signal:Wait()` (e, por extensão, o polling nativo de `WaitForChild` com timeout) resume/conclui threads geridas por `Scheduler` por um caminho que o próprio `Scheduler.luau` não enxerga — e isso é justamente o tipo de risco que os próprios coders sinalizaram como "não resolvido"/"incerto" nos comentários, mas que se provou, ao testar de verdade, não ser um risco teórico: é um bug reproduzível com um script de 10 linhas.

Recomendação: antes de re-submeter para revisão, (a) implementar a poda de `liveThreads` por status em `Scheduler.luau` (achado GRAVE 2, resolve também o ALTO 4), (b) acionar `pesquisador` para confirmar o mecanismo exato do executor assíncrono do Lune com múltiplos timers nativos concorrentes antes de manter a estratégia de polling de `WaitForChild` com timeout (achado GRAVE 1), (c) decidir com `arquiteto` se `Signal.Fire` deve isolar listeners entre si via `pcall` individual (achado ALTO 3), (d) trocar o `any` por `unknown` em `Scheduler.luau:432` (achado MÉDIO 5).
