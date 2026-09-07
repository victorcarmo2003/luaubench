# task-services-034 — HttpService:GetAsync falha esporádica escapava do pipeline de erro

## Causa raiz (CONFIRMADA em `services`, não cruza para `runtime`)

`performNetRequest` (`src/services/behavior/HttpService.luau`) já tinha um `pcall` correto ao
redor de `net.request` e já retraduzia a falha via `error(...)` — isso nunca foi o problema. O
problema é **quem resume a coroutine depois que `net.request` (função nativa assíncrona do Lune)
termina**.

`net.request` yielda a coroutine chamadora de verdade, e é resumida depois pelo runtime interno do
PRÓPRIO Lune — nunca por `Scheduler.resumeThread` (`src/runtime/Scheduler.luau`), que é o ÚNICO
ponto de código do projeto que converte uma retomada falha em `ThreadError:Fire(...)`. Quando essa
retomada nativa entrega um ERRO (a falha de rede, já traduzida por `performNetRequest`), esse
`error()` se propaga através de `chunk()` (`Sandbox.luau:549`) sem nunca passar por
`resumeThread` — escapa direto para o handler de erro não tratado do próprio Lune, que imprime um
dump cru (`[Stack Begin]/[Stack End]`) e deixa o sumário de `RunCommand` mentindo "0 error(s)"
com exit code 0.

É a MESMA classe de bug já documentada no cabeçalho de `Scheduler.luau` para `Signal:Wait()` antes
de `ThreadBroker` existir — a diferença é que o resume de `Signal:Wait()` era Lua puro (podia ser
redirecionado para `ThreadBroker.Resume`); o resume de `net.request` é nativo do Lune (Rust/C),
opaco a código Luau — **não há hook exposto pelo Lune 0.10.5 para interceptar esse resume
específico** (API completa de `net.luau`/`task.luau` conferida). Por isso a correção não tenta
mudar quem resume a chamada de rede — ela garante que a chamada de rede nunca seja resumida por
ninguém além de uma coroutine descartável, gerida só pelo Lune, que nunca deixa nada escapar sem
tratamento.

## Reprodução (antes do fix)

Script descartável (`repro-getasync.luau`, não versionado): 40 rounds seriais, cada um sobe um
`net.serve` local numa porta nova e roda `lune run src/cli/main.luau run <projeto> --allow-http
--allow-http-local` contra ele. **2/40 falharam**, as 2 com exit code 0, "0 error(s)" no sumário e
o dump cru citando `HttpService.luau:1353`/`Sandbox.luau:549` — reproduz byte-a-byte o achado do
revisor de task-cli-034.

## Fix

`performNetRequest` isola `net.request` dentro de uma coroutine descartável criada por
`@lune/task.spawn` (gerida só pelo Lune, nunca pelo `Scheduler` do LuauBench), protegida por um
`pcall` próprio que nunca deixa nada escapar — sucesso ou falha, essa coroutine sempre termina
normalmente. O resultado é escrito em upvalues compartilhadas e lido de volta pela thread GERIDA
por um laço de `Context.GetScheduler():Wait(NET_REQUEST_POLL_INTERVAL)` — todo resume desse laço
passa pelo ponto único `Scheduler.resumeThread`. Só depois desse laço terminar o módulo chama
`error()`, garantindo que a falha vire `ThreadError` pelo mesmo caminho que qualquer outro erro de
script.

**Achado adicional (crítico para não regredir)**: `NET_REQUEST_POLL_INTERVAL` precisa ser um
número POSITIVO (`0.001`, 1ms), nunca `0`. Confirmado rodando com um probe direto contra
`Scheduler.luau`: `Scheduler.Run()` só chama `@lune/task.wait` de verdade (`if sleepFor > 0 then
LuneTask.wait(sleepFor) end`) quando `nextWakeInterval` calcula algo `> 0` — é ESSA chamada,
sozinha, que devolve o controle ao reator assíncrono do próprio Lune (o único jeito de
`net.request` sequer progredir). Um laço de `Wait(0)` fica sempre "imediatamente devido", nunca
chama `task.wait`, e a requisição TRAVA PARA SEMPRE — medido: 2 milhões de tiques / ~2.9s sem
completar contra ~5-9ms completando de verdade com `Wait(0.001)`. Isto não é latência artificial —
é o piso técnico do próprio mecanismo assíncrono do Lune.

## Verificação (depois do fix)

- Mesmo `repro-getasync.luau` (40 rounds): **3/40 ainda falham** (taxa de flakiness inerente à rede
  real, inalterada — correto, não deveria mudar) — mas agora TODAS saem como `error
  ServerScriptService.Main: runtime error: ... failed: the request could not be completed`, "1
  error(s), 0 warning(s)" no sumário, **exit code 1**. Zero dumps crus, zero discrepância de
  contagem.
- `luau-lsp analyze --platform=standard --settings=".luaurc"` em `HttpService.luau` e
  `HttpService.spec.luau`: exit 0, zero diagnósticos.
- Suíte completa `HttpService.spec.luau`: **101/101 testes passam** com o fix (rodada limpa,
  `spec_full_run2.log`). Um teste pré-existente ("RequestAsync contra host inexistente...", linha
  625) usa um domínio `.invalid` cuja resolução DNS às vezes passa de 10s NESTE sandbox
  específico — **confirmado via `git stash` que essa mesma falha ocorre IDENTICAMENTE no código
  ORIGINAL (sem meu fix)**, portanto é flakiness ambiental pré-existente, não uma regressão desta
  tarefa. Não toquei o watchdog desse teste (fora de escopo) — só reportando para visibilidade.
- Teste NOVO dedicado (`HttpService.spec.luau`, seção "REGRESSÃO task-services-034"): chama
  `GetAsync` **sem nenhum pcall** (como um script real faria — `local body =
  HttpService:GetAsync(...)`) contra uma porta onde nada escuta, conecta em
  `scheduler.ThreadError` diretamente, e afirma que a falha sai por lá (nunca como dump cru).
  Verificado isoladamente (script descartável, fora do território) rodando limpo: `finished=false
  threadErrorCount=1`, mensagem traduzida correta, ~16ms.
  **Achado que explica por que nenhum teste pré-existente pegava o bug**: todos os testes de rede
  de `HttpService.spec.luau` usam o helper `runOnScheduler`, que envolve a chamada num `pcall`
  PRÓPRIO — e um `pcall` comum já protege corretamente através de qualquer yield/resume,
  independente de quem fez o resume por baixo. O bug só se manifesta quando NÃO há pcall nenhum
  entre a chamada e o topo da thread gerida (a forma de um script real sem tratamento de erro) —
  por isso o teste novo dirige o `Scheduler` manualmente, sem usar `runOnScheduler`.

## Arquivos

- Modificado: `src/services/behavior/HttpService.luau` (`performNetRequest` reescrito + `require("@lune/task")` + cabeçalho atualizado documentando causa raiz/fix).
- Modificado: `src/services/behavior/HttpService.spec.luau` (novo teste de regressão + helper `pickPortWithNothingListening`).
- Nenhum arquivo fora de `src/services/` tocado. `src/runtime/` e `src/cli/` intactos (usei um script descartável DENTRO de `src/runtime/` só para investigação empírica do comportamento de `Scheduler.Run`/`Wait(0)` vs Lune, rodado e removido antes de terminar a tarefa — não sobrou nenhum arquivo lá).

## Observação para a thread principal (fora do meu território, não corrigido aqui)

`src/cli/RunCommand.spec.luau` (teste "fixture 'http-audit'") tem um comentário longo (linhas
~398-425) descrevendo este MESMO bug como "fora do território desta tarefa para `coder-services`/
`coder-runtime` investigarem" e uma mitigação de retry (`MAX_ROUNDTRIP_ATTEMPTS = 8`) só no teste
para contornar a falha esporádica de rede (não o bug de propagação, que agora está corrigido). Como
o bug raiz já está corrigido, esse comentário ficou desatualizado (ainda descreve o sintoma como
"não corrigido"). Sugiro uma tarefa pequena de `coder-cli` para atualizar o comentário — o retry em
si pode continuar (a flakiness de REDE em si, ~5-20%/tentativa, é real e não é o que esta tarefa
corrigiu; só a PROPAGAÇÃO do erro estava quebrada). Não toquei `src/cli/` por estar fora do meu
território.

Também vale nota: `HttpService.spec.luau` já tinha um teste pré-existente ("RequestAsync contra
host inexistente...") usando um domínio `.invalid` cuja resolução DNS é lenta o bastante neste
sandbox para estourar o watchdog de 10s ocasionalmente — comportamento ambiental, não relacionado a
este fix (confirmado via `git stash`). Não ajustei esse watchdog (fora de escopo desta tarefa).
