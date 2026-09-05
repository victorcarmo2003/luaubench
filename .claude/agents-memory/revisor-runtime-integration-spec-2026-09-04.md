# Revisão de `src/runtime/Integration.spec.luau` — task-runtime-009

Revisão read-only. Nenhum arquivo de `src/runtime/` foi editado. Todos os repros extras foram
escritos e rodados sobre **cópias** de `Signal.luau`/`Instance.luau`/`Scheduler.luau`/
`ThreadBroker.luau` num diretório isolado do scratchpad (`repro1/`, `repro2/`) — timestamps de
`src/runtime/*.luau` conferidos antes e depois desta revisão: inalterados.

Lune usado: `D:\Moved\.rokit\tool-storage\lune-org\lune\0.10.5\lune.exe` (mesmo binário das
revisões anteriores; `.luaurc` do projeto aponta typedefs para 0.10.5, confirmando que é o
binário "de sempre"). `luau-lsp` 1.68.1.

## Números confirmados (rodando eu mesmo)

- `lune run src/runtime/Integration.spec.luau`: **9/9 PASS**, saída idêntica ao relatado.
- Regressão: `Signal.spec.luau` **6/6**, `Instance.spec.luau` **24/24**, `Scheduler.spec.luau`
  **12/12** — todos rodados diretamente, sem tocar nos três arquivos.
- Timestamps (`Get-ChildItem` ordenado por `LastWriteTime`): os três `.spec.luau` existentes
  são mais antigos que `Signal.luau`/`Instance.luau`/`Scheduler.luau`/`ThreadBroker.luau`
  (patch de task-runtime-008), que por sua vez são mais antigos que `Integration.spec.luau`.
  Confirma que task-runtime-009 não tocou nos três specs nem nos quatro módulos.
- `luau-lsp analyze --platform=standard src/runtime/Integration.spec.luau`: limpo, sem erros.
- `grep '\bany\b' src/runtime/Integration.spec.luau`: zero ocorrências. `--!strict` na linha 1.
- Padrão de `test()`/`process.exit(0)` idêntico aos três specs existentes (sem `pcall`
  envolvendo cada teste — mesma convenção já aceita no território, não é regressão desta
  tarefa).
- Escopo: só `require("./Scheduler")` e `require("./Instance")` (que por sua vez trazem
  `Signal`/`ThreadBroker`) — nenhum import de fora de `src/runtime/`, nenhuma referência a
  `services`/`cli`.

## Cenário 4 (GRAVE 1) — julgamento pedido: a prova alternativa é aceitável?

**Sim, é aceitável — julgamento (a): a medição original ">2s" não se sustenta como reprodutível
sob demanda neste ambiente, mas a correção arquitetural elimina a classe inteira do risco
hipotetizado, e isso é verificável de forma determinística.** Evidência reunida:

1. **Não consegui reproduzir o estouro eu mesmo.** Copiei os 4 módulos para
   `scratchpad/repro1/`, forcei `driver = nil` em `Instance.luau:390` (equivalente a desabilitar
   o ramo (B) gerido, forçando sempre o polling nativo do ramo (C) mesmo sob thread gerida por
   `Scheduler:Run()` real — a mesma configuração que reproduziu o achado GRAVE 1 originalmente).
   Rodei `scheduler:Spawn(function() parent:WaitForChild("Fantasma", 0.05) end)` dirigido por
   `Scheduler:Run()` real, **10 tentativas seguidas**: todas resolveram entre 0.0587s e 0.0626s,
   nunca perto de 2s. Rodei também uma variante de estresse com **30 threads concorrentes**
   fazendo a mesma coisa sob o mesmo `Scheduler:Run()`: min=0.0605s, max=0.0607s, 30/30
   completaram — nenhum sinal de contenção mesmo sob carga.
2. **A causa-raiz alternativa do coder está correta e eu a confirmei de forma independente.**
   Com o mesmo `driver = nil` forçado, chamei `WaitForChild("Fantasma", 5)` e avancei o relógio
   **simulado** via `StepOnce(1)` oito vezes (`self.time` chegando a 8, muito além do timeout de
   5) **sem deixar nenhum wall-clock real relevante passar** — o resultado nunca resolveu
   (`resolved=false` em todas as 8 chamadas). Isso prova exatamente a alegação: sem o ramo (B),
   `WaitForChild` com timeout fica **inteiramente desacoplado do relógio do Scheduler**, só
   resolve por polling de `os.clock()` real. Contra o código real (não revertido), o cenário 5
   do próprio `Integration.spec.luau` já prova o oposto: resolve exatamente no 5º `StepOnce(1)`,
   sem nenhum wall-clock real ter passado — reconfirmei isso rodando o spec.
3. **Por que aceito isso como prova suficiente, mesmo sem reproduzir o número original:** o
   critério de aceitação de task-runtime-002 ("com timeout, retorna nil após o tempo se o filho
   não aparecer") está demonstrado como verdadeiro contra o código real, de forma determinística
   E em wall-clock real repetida (40 execuções combinadas minhas, zero variância relevante). A
   correção não é "ajustar um número mágico até o teste passar" — é uma mudança estrutural que
   **remove por completo o uso de timer nativo (`@lune/task`) do caminho de thread gerida**,
   eliminando a categoria de risco (contenção entre o laço de `Scheduler:Run()` e um timer nativo
   concorrente) que a teoria original do achado GRAVE 1 apontava como causa. Mesmo que a causa
   raiz *exata* do ">2s" observado na revisão original nunca venha a ser confirmada (os repros
   daquela revisão foram escritos fora do repositório e apagados ao final — não há artefato para
   re-rodar literalmente), a correção atual não depende dessa causa ter sido identificada
   corretamente: ela ataca a classe inteira de mecanismo (timer nativo concorrente) that poderia
   causar o sintoma, e o comportamento resultante é correto e estável nas condições testadas.
4. **Ressalva que registro (não bloqueia aprovação):** não é possível descartar 100% que a
   medição original de ">2s" tenha sido causada por outra coisa (carga da máquina naquele
   momento específico, artefato do script de repro daquela sessão — que não sobreviveu para
   comparação direta) e que essa outra causa ainda exista sob alguma condição não testada aqui
   (ex: máquina sob carga pesada de I/O/CPU externa ao Lune, milhares de threads geridas
   simultâneas, um `luaubench run` de longa duração). Recomendo registrar essa incerteza
   residual explicitamente no comentário de `Instance.luau:392-402` (hoje ele apresenta o
   ">2s" da revisão original como fato estabelecido, sem mencionar que tentativas posteriores de
   reproduzir o sintoma literal falharam) — não é uma exigência de regra 00 no sentido estrito
   (a correção em si não é uma divergência de comportamento do Roblox), mas é o tipo de
   transparência que a regra pede para não deixar uma alegação de bug soar mais confirmada do
   que está. **Não bloqueia esta tarefa** — é uma sugestão de documentação, entregável em uma
   tarefa futura de baixo custo.

## Achado novo — [MÉDIO] Integration.spec.luau — cenários 1/2/3a/3b não isolam a correção de `Signal.luau` (ThreadBroker.Resume); a rede de segurança de `Scheduler.IsAlive()` sozinha já mascara uma regressão só em `Signal.luau`

**Problema:** os cenários 1, 2, 3a e 3b afirmam (nos comentários e nas asserções) reproduzir o
achado GRAVE 2 — "`Signal:Wait()` resumia a thread suspensa com `coroutine.resume` cru... fora
do ponto único de `resumeThread`... `liveThreads` nunca era podado... `IsAlive()` ficava `true`
para sempre". Mas a asserção usada para provar isso é sempre `scheduler:IsAlive()` (ou o laço de
`Run()`, que chama `IsAlive()` a cada iteração) — e `Scheduler.IsAlive()` (`Scheduler.luau:400-
418`) tem uma **rede de segurança independente** (adicionada no mesmo patch de task-runtime-008,
"pedida pelo revisor" segundo o comentário) que poda `liveThreads` por `coroutine.status(co) ==
"dead"` **toda vez que é chamada**, não importa por qual caminho a coroutine morreu. Essa rede,
sozinha, já é suficiente para fazer `IsAlive()` (e portanto `Run()`) se autocorrigir, **mesmo se
`Signal.luau:Wait()` regredir para `coroutine.resume` cru** — porque o simples fato de chamar
`IsAlive()` depois de uma continuação de `Wait()` já limpa o estado, independente de quem
resumiu a coroutine.

**Cenário de falha (reproduzido empiricamente, 2 variações para isolar):**
1. Copiei `Signal.luau` e reverti só o `Wait()` para `coroutine.resume(co, ...)` cru (bypassando
   `ThreadBroker.Resume`), mantendo `Scheduler.luau` (com a rede de segurança) intocado. Rodei o
   cenário 1 exatamente como está no arquivo (`Spawn` + `Heartbeat:Wait()` + `StepOnce` +
   `IsAlive()`): **`IsAlive() == false` — o teste PASSARIA mesmo com essa regressão em
   `Signal.luau`.** Ou seja, uma regressão real e isolada (só em `Signal.luau`, o exato arquivo
   que o achado GRAVE 2 aponta como culpado) passa despercebida pelo cenário 1.
2. Removendo TAMBÉM a rede de segurança de `IsAlive()` (além do `Signal.luau` revertido) — aí
   sim `IsAlive() == true` para sempre, reproduzindo o sintoma GRAVE 2 como descrito.

**Por que importa:** o objetivo explícito de task-runtime-009 (e da lista "Testes de integração
exigidos" do arquiteto) é blindar contra os bugs GRAVE voltarem a passar despercebidos — "foi
exatamente por isso que os dois bugs GRAVE passaram batido" nos specs isolados anteriores. O
cenário 1 (e 2/3a/3b, que compartilham a mesma dependência estrutural em `IsAlive()`) dá a
impressão de testar a correção de `Signal.luau`, mas na prática testa a rede de segurança de
`Scheduler.luau` — um mecanismo diferente, adicionado no mesmo patch, mas em arquivo diferente.
Uma regressão futura confinada a `Signal.luau` (cenário plausível: um refactor de `services`
tocando `Signal.luau` sem querer reverte o `Wait()` para algo mais simples) passaria por 1/2/3a/
3b sem disparar nenhuma falha — só o cenário 6 (ALTO 4, atribuição de thread em `ThreadError`)
pegaria essa regressão especificamente, por um caminho indireto (o erro reportado apontaria para
a thread hospedeira errada), não pela ausência de `IsAlive()` correto.

**Isso não é uma alegação falsa do coder** — a acceptance de task-runtime-009 pede que o teste
falhe revertendo "o patch de task-runtime-008" como unidade (todos os 4 arquivos), e sob essa
interpretação literal a alegação do coder ("1 e 6 falham revertendo o patch") **é verdadeira**;
confirmei isso revertendo os 4 arquivos juntos (`Signal.luau` + removendo a rede de `IsAlive()`),
cenário 1 falha como esperado. O achado aqui é mais fino: a rede de segurança de `IsAlive()`
(defesa em profundidade, coisa boa) tem o efeito colateral de esconder de quais dos dois
mecanismos (roteamento por `ThreadBroker` em `Signal.luau`, ou a rede de poda em
`Scheduler.IsAlive()`) um cenário específico realmente depende — isso é uma fraqueza de
precisão do teste de regressão, não um bug de runtime.

**Correção sugerida:** não bloqueante, mas recomendo para uma tarefa de acompanhamento pequena:
adicionar pelo menos um cenário que force a asserção pela via mais direta possível de que
`Signal:Wait()` está roteando por `ThreadBroker.Resume` quando há driver — por exemplo, verificar
`coroutine.status(handle)` mudando para `dead` estritamente durante a chamada de `StepOnce`/
`Fire` (antes de qualquer chamada subsequente a `IsAlive()`, que é o que aciona a rede de
segurança), ou instrumentar via um segundo `Scheduler` num teste dedicado que force um erro na
continuação e confirme que `ThreadError` (não `IsAlive()`) é quem primeiro sinaliza o problema.
O cenário 6 já faz algo parecido para o ALTO 4 — vale generalizar essa técnica para o GRAVE 2
também, em vez de depender só de `IsAlive()`/`Run()` como ponto de observação.

## Verificações adicionais

- Nenhum dos 9 cenários depende de `sleep` arbitrário "pra dar tempo" — os únicos dois que usam
  wall-clock real (3a/3b/4) usam `runWithGuard`, que asserta explicitamente que a guarda nunca
  foi o motivo do término (`guardTriggered == false`), conforme exigido pela regra 01/acceptance.
  Conferido lendo o código e reconfirmado pela saída real (`guardTriggered=false` nos 3 casos).
- Cenário 7 (corrida deadline × ChildAdded): reconfirmei a lógica lendo `resumeDueWaiting`
  (`Scheduler.luau:243-264`) — o campo `cancelled` da `WaitingEntry` é checado no momento do
  `resumeThread`, não no momento de extração para `due`, então a entrada de B (cancelada pelo
  `ChildAdded` que resolveu durante a resolução de A, no mesmo tique) é pulada corretamente. Bate
  com o resultado observado (`threadErrorCount == 0`, `resolvedBCount == 1`).
- Cenário 8: usa `scheduler.Heartbeat:Connect` real (não um `Signal.new()` solto) — de fato
  exercita `fireProtected`/`Signal.Fire` com pcall por listener, isolamento confirmado.
- Território: nenhum import de `services`/`cli`, nenhuma nova API pública exposta pelo arquivo de
  teste, `ThreadBroker` não é tocado/exposto por este arquivo.
- Ressalva ainda em aberto de task-runtime-008 (Cancel não desconecta listener registrado por
  `Signal:Wait()`/`WaitForChild` branch B em `Signal`s de terceiros — MÉDIO, ver
  `revisor-runtime-patch-threadbroker-2026-09-04.md`): **continua sem endereçar**, mas está fora
  do escopo de task-runtime-009 (tarefa é só sobre o arquivo de teste) — não afeta o veredito
  desta tarefa, só menciono para não se perder de vista antes de `services` depender de
  `Signal:Wait()`/cancelamento em produção.

## Veredito

**task-runtime-009: APROVADO COM RESSALVAS.**

Os 9/9 testes passam, confirmados por mim rodando o mesmo binário Lune. Regressão dos três specs
existentes (6/6, 24/24, 12/12) confirmada, arquivos intocados (timestamps + conteúdo). Tipagem
estrita, sem `any`, `luau-lsp analyze` limpo. A prova alternativa de causa-raiz para o cenário 4
(repro de GRAVE 1) é **aceita como evidência suficiente** de que o achado original está
corrigido — reproduzi eu mesmo a não-reprodução do sintoma literal (10 tentativas + estresse de
30 threads concorrentes, zero variância relevante) e confirmei de forma independente e
determinística o mecanismo de causa-raiz alternativo (decoupling do relógio simulado sem o ramo
gerido). Recomendo, sem bloquear, documentar essa incerteza residual sobre a medição original no
comentário de `Instance.luau`.

A ressalva é o achado **[MÉDIO]** novo: cenários 1/2/3a/3b não isolam a correção de
`Signal.luau` (roteamento por `ThreadBroker.Resume`) da rede de segurança independente em
`Scheduler.IsAlive()` — uma regressão futura confinada só a `Signal.luau` passaria despercebida
por esses quatro cenários (seria pega só pelo cenário 6, por um caminho indireto). Não é uma
alegação falsa do coder (a acceptance fala em reverter "o patch" como unidade, e isso se
confirma), mas é uma lacuna de precisão que vale endereçar antes de tratar a suíte de integração
como blindagem completa contra os dois achados GRAVE originais.
