# Revisão — task-services-004 (RunService/Players/RejectingSignal)

Data: 2026-09-05. Território revisado: `src/services/RejectingSignal.luau` (+spec),
`src/services/behavior/RunService.luau` (+spec), `src/services/behavior/Players.luau` (+spec),
`src/services/behavior/Index.luau` (+spec), `src/services/Integration.spec.luau` (diff).

Metodologia: nada aceito por relato do coder. Todos os 13 pontos do pedido de revisão foram
verificados rodando os testes de verdade (`lune 0.10.5`, binário do Rokit) e lendo o código-fonte
linha a linha, mais `luau-lsp analyze --platform=standard` (1.69.0) nos 9 arquivos do território.

## Verificação ponto a ponto

1. **`RunService.Heartbeat` rawequal a `scheduler.Heartbeat`** — confirmado por teste próprio
   (`RunService.spec.luau`, testes 1 e 2) e por leitura de `behavior/RunService.luau:102-103`
   (`Runtime.Instance.SetPropertyRaw(instance, "Heartbeat", scheduler.Heartbeat)` — instalação
   direta da mesma referência, sem wrapper). Teste "conectar + StepOnce dispara com deltaTime real"
   passou (`receivedDt == 1/30`).
2. **`RenderStepped`**: ler não erra (testado, devolve o objeto), `Connect`/`Once`/`Wait` erram —
   os três verbos testados separadamente em `RejectingSignal.spec.luau` (5/5) com a substring exata
   "RenderStepped event can only be used from local scripts" confirmada em `RunService.spec.luau`
   (teste dedicado, mais o teste que confirma AUSÊNCIA do prefixo `[LuauBench]`).
3. **`PreRender`**: testado ativamente sob 10x `StepOnce` — conecta sem erro, nunca dispara. Ver
   nota de processo abaixo (não é defeito de código).
4. **`IsServer()==true`, `IsClient()==false`, `IsStudio()==false`**: confirmado, teste chama os
   quatro (`IsRunning()==true` também).
5. **`Players:GetPlayers()` → `{}`** (confirmado `#result == 0`, não `nil`), `LocalPlayer` → `nil`
   sem erro, `PlayerAdded` conectável sem erro — todos confirmados por teste.
6. **Escrever sobre `Heartbeat` erra** "is an event of RunService and cannot be reassigned" —
   confirmado por teste e por leitura de `Instance.luau:696/721` (mesma família de mensagem usada
   em todo o runtime).
7. **`BindToRenderStep` erra `[LuauBench]`** — confirmado; mensagem bate exatamente com
   `ClassBuilder.luau:58` (`makeUnsimulatedMethodStub`).
8. **`RejectingSignal.spec.luau`** cobre `Connect`/`Once`/`Wait` errando com a mensagem do
   construtor (3 testes separados) e `DisconnectAll` no-op (1 teste) — rodei os 5/5, todos
   exercitam o comportamento de verdade (pcall + casamento de substring), não apenas instanciam.
   Bônus: teste de que duas mensagens diferentes produzem erros diferentes (não há estado global
   vazado entre instâncias).
9. **`FrameNumber`/`Misprediction` fora do schema** — confirmado no `generated/classes/RunService.luau`
   (ausentes do `Schema`) e por teste que verifica a mensagem "is not a valid member of RunService"
   SEM o prefixo `[LuauBench]` (teste distingue os dois casos explicitamente).
10. **`RunService:Pause()` erra como membro inexistente** — confirmado: `Pause` não está em
    `MethodNames` do gerado (filtrado por Security/Capabilities), teste confirma "Pause is not a
    valid member of RunService" e ausência de `[LuauBench]`.
11. **Comentário da decisão "produção (RCC), não bug do Studio"** presente no cabeçalho de
    `RejectingSignal.luau` (linhas 10-19) E no cabeçalho de `behavior/RunService.luau` (linhas
    26-35), nos dois pontos exatos que o pedido cobrava.
12. **Regressão total**: rodei os 8 specs de `runtime` individualmente — 7+57+16+29+12+7+9+6 =
    **143/143**, batendo com o relatado. Rodei os specs de `services` — Context 3, ClassBuilder 9,
    StarterPlayer 3, RejectingSignal 5, Integration 14, RunService 11, Players 8, Index 4, init 7 =
    **64/64**, também batendo. Nenhum spec pré-existente foi alterado além dos 3 diffs abaixo.
13. **`git diff --stat` em `src/services/generated/` e `src/runtime/`**: saída vazia — zero edição
    confirmada nos dois diretórios protegidos. Diff real desta tarefa: 3 arquivos modificados
    (`Integration.spec.luau`, `behavior/Index.luau`, `behavior/Index.spec.luau` — todos aditivos,
    lidos linha a linha, nenhuma remoção de cobertura existente) + 6 arquivos novos
    (`RejectingSignal.luau`/`.spec`, `behavior/RunService.luau`/`.spec`, `behavior/Players.luau`/
    `.spec`).

## Qualidade adicional verificada

- `luau-lsp analyze --platform=standard` limpo nos 9 arquivos do território (só o aviso genérico
  "no definitions file provided by client", irrelevante).
- Zero ocorrência real de `any` — as únicas 3 ocorrências da palavra são em comentários
  explicando por que `any` foi evitado.
- Tipo de retorno `Runtime.Signal<...unknown>` de `RejectingSignal.new` confere estruturalmente
  com `Signal<T...>` de `src/runtime/Signal.luau:34-39` (Connect/Once/Wait/DisconnectAll) — não é
  um tipo inventado, é uma instanciação legítima do genérico já existente.
- `ClassBuilder.Build` confirmado (leitura + `ClassBuilder.spec.luau` 9/9) validando
  `behavior.Methods ⊆ MethodNames` — nenhuma superfície inventada por `RunService.luau`/
  `Players.luau` passaria batido: os 4 métodos de `RunService` (`IsServer/IsClient/IsStudio/
  IsRunning`) e os 3 de `Players` (`GetPlayers/GetPlayerByUserId/GetPlayerFromCharacter`) estão
  todos em `MethodNames` dos respectivos `generated/classes/*.luau`, que por sua vez vêm do dump
  fixado (commit `28360dea`).

## Nota de processo (não bloqueante, não é defeito de código)

`task-services-007` (pesquisa concluída antes desta tarefa) recomendou, por analogia estrutural
(marcado como inferência, não confirmação empírica), estender o tratamento `RejectingSignal` de
`RenderStepped` também a `PreRender`, e fechou dizendo explicitamente: *"PreRender fica para o
arquiteto decidir quando task-services-004 for revisado"* — ou seja, esta revisão. Não encontrei,
em `.claude/agents-memory/arquiteto-services-2026-09-05.md` nem em nenhum outro arquivo de
memória, uma decisão do arquiteto posterior a essa pesquisa resolvendo o ponto. O coder implementou
exatamente o que a versão ATUAL da tarefa/desenho manda (`PreRender` intocado, nunca dispara — "não
há evidência de que erre, errar sem confirmação falha por comissão") — isso é a decisão certa para
`coder-services` tomar sozinho, porque regra 02/00 são explícitas: simplificação de fidelidade é
decisão do arquiteto, não do coder. **Recomendação**: repassar à thread principal para que o
arquiteto feche esse ponto explicitamente (confirmar a decisão atual ou revisá-la), antes de tratar
a leva 1 de `services` como definitivamente fechada — não é motivo para reprovar esta tarefa.

## Veredito

APROVADO. Os 13 pontos do pedido de revisão foram confirmados por execução real de teste e leitura
de código, não por relato do coder. Nenhuma edição indevida em `generated/` ou `runtime/`.
Regressão 143 (runtime) + 64 (services) intacta. Único item em aberto é de decisão arquitetural
(PreRender), não de qualidade de código desta tarefa.
