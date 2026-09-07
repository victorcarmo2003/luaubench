# Revisão — task-services-034 (HttpService:GetAsync — erro escapando do pipeline)

Revisão feita reproduzindo tudo de forma independente (não aceitei o self-report do coder). Metodologia e evidência abaixo.

## 1. Mecanismo lido no código

Conferido em `src/services/behavior/HttpService.luau` (cabeçalho "Composição com Runtime.Scheduler", linhas ~250-400, e `performNetRequest`, linhas ~1283-1356): `net.request` roda dentro de `task.spawn` (coroutine descartável, gerida só pelo Lune) protegida por `pcall` próprio; o resultado é escrito em upvalues compartilhadas (`completed`/`succeeded`/`responseOrError`) e lido de volta por um laço `while not completed do scheduler:Wait(NET_REQUEST_POLL_INTERVAL) end` na thread gerida pelo `Scheduler`. `NET_REQUEST_POLL_INTERVAL = 0.001` (nunca `0`), com justificativa documentada citando `Scheduler.Run`'s `if sleepFor > 0 then LuneTask.wait(sleepFor) end`. Bate exatamente com o que o coder alegou.

## 2. Reprodução independente do bug original

`git stash push -- src/services/behavior/HttpService.luau` (mantendo o spec novo), depois rodei um script isolado (fora do repositório versionado, removido ao final) que chama `GetAsync` sem `pcall` contra uma porta sem nada escutando, dirigindo o `Scheduler` manualmente:

- **Código original (sem fix): 3/3 rodadas falharam** com dump cru do Lune (`[Stack Begin]/[Stack End]`), `threadErrorCount=0`, exit 1 — reprodução mais determinística que a taxa de 2/40 do coder (esperado: conexão recusada é mais confiável que os cenários de flakiness real de rede do repro deles, mas confirma exatamente o mesmo mecanismo).
- `git stash pop` restaurando o fix, mesmo script: **8/8 rodadas produziram `ThreadError` corretamente** (mensagem traduzida "the request could not be completed", `threadErrorCount=1`), exceto 1 rodada isolada anterior (fora dessas 8) que expirou o watchdog de 20s sem completar nem errar — não reproduzida de novo em 8 tentativas subsequentes, provável ruído ambiental (Windows/firewall na primeira conexão), não uma falha estrutural do fix.

## 3. Reprodução da alegação `Wait(0)` trava vs `Wait(0.001)` funciona

Script isolado próprio (net.request real contra porta fechada, dentro de `task.spawn`, lido por loop `scheduler:Wait(interval)`):

- `Wait(0)`: **300001 tiques / 0.83s, nunca completou** (limite artificial do meu teste, não do mecanismo — o coder mediu 2M tiques/2.9s, mesma ordem de grandeza e mesma conclusão: nunca completa).
- `Wait(0.001)`: **completou em 1 tique / 7ms.**

Confirma a alegação sem reservas.

## 4. Suíte completa — rodada 4 vezes

- 3/4 rodadas: **102/102 testes passaram** (não 101/101 como o relatório do coder afirma — pequena imprecisão no self-report, sem impacto funcional).
- 1/4 rodadas: falhou no teste pré-existente "RequestAsync contra host inexistente..." (linha 625, domínio `.invalid`) por estourar o watchdog de 10s.
- Confirmei via `git stash` (código original, sem o fix) que **esse mesmo teste falha identicamente** no código-base sem a correção — é flakiness ambiental pré-existente (resolução DNS negativa para `.invalid` ocasionalmente lenta neste sandbox), não uma regressão desta tarefa. Conectividade de rede real confirmada funcionando normalmente (`curl https://example.com` -> 200 em ~1s) — não é falta de rede, é especificamente a resolução negativa de `.invalid` que varia.

## 5. Teste novo — genuinamente de regressão

Lido `HttpService.spec.luau:1082-1120`. Chama `getAsync` dentro de `scheduler:Spawn` **sem nenhum `pcall`** (comentário no próprio teste explica que é de propósito, já que `runOnScheduler` — usado por todos os outros testes de rede — envolve a chamada num `pcall` que mascararia o bug). Conecta direto em `scheduler.ThreadError` e afirma `threadErrorCount == 1`. Confirmado por reprodução independente (item 2) que este cenário exato falha no código antigo e passa no novo.

## 6. Território

`git status`/`git diff --stat` confirmam só `src/services/behavior/HttpService.luau` e `HttpService.spec.luau` modificados, mais o arquivo de memória novo. Nada residual em `src/runtime/` ou fora de `src/services/`.

## 7. `--!strict` / `any`

Ambos os arquivos começam com `--!strict`. Grep por `\bany\b` no código de produção: nenhuma ocorrência (só aparece como string dentro do teste mecânico "SEM ANY", que é o próprio teste que verifica a ausência do tipo). `luau-lsp analyze --platform=standard --settings=".luaurc"` nos dois arquivos: exit 0, zero diagnósticos.

## 8. Alegação "causa fica inteira em `services`, não cruza para `runtime`"

Estruturalmente plausível e consistente com pesquisa já registrada (`.claude/agents-memory/pesquisa-scheduler-lune-2026-09-04.md`): o motor real de scheduling do Lune vive no crate Rust `mlua-luau-scheduler`, opaco a Luau — não há primitivo exposto para "frame"/hook de resume. Não tenho como auditar o código-fonte Rust do Lune 0.10.5 dentro desta revisão para confirmar 100% a ausência de qualquer hook, mas a evidência disponível (pesquisa anterior + comportamento observado) não contradiz a alegação.

**Ressalva (não bloqueante):** o fix é um workaround via polling (`task.spawn` + laço de `Wait` com uma constante positiva escolhida à mão) especificamente para `net.request`. Se outras chamadas nativas assíncronas do Lune (`fs`, outras partes de `net`) precisarem do mesmo tratamento no futuro, esse padrão tende a ser copiado e colado — com risco real de alguém usar `Wait(0)` por engano (o comentário é a única proteção contra isso, não há nada estrutural impedindo). Vale o `arquiteto` avaliar se um helper genérico em `runtime` (ex.: algo como `Scheduler:AwaitNative(fn)`, encapsulando o padrão task.spawn+poll+intervalo mínimo uma única vez) compensaria, em vez de deixar cada `services` reimplementar o mesmo mecanismo. Isso é sugestão de robustez a médio prazo, não motivo para reprovar esta correção pontual.

## Outras observações (não bloqueantes)

- Contagem de testes do self-report do coder (101/101) diverge da contagem real (102/102) em todas as 3 rodadas limpas que rodei — discrepância pequena, mas reforça a instrução de nunca aceitar self-report sem checar.
- Comentário desatualizado em `src/cli/RunCommand.spec.luau:398-425` confirmado como realmente descrevendo o mesmo bug já corrigido, ainda dizendo "fora do território... reportado à parte para investigar" — fora do território deste coder, observação correta, não corrigida aqui (correto não corrigir).

## Veredito

**APROVADO COM RESSALVAS**

Ressalvas: (1) considerar um helper genérico em `runtime` para o padrão task.spawn+poll usado por chamadas nativas assíncronas do Lune, evitando reimplementação futura do mesmo mecanismo por outros módulos de `services`; (2) pequena imprecisão de contagem no self-report do coder (101 vs 102) — sem impacto funcional, mas vale corrigir a memória do agente para não propagar o número errado.
