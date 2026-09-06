# Revisão task-runtime-038 — DataModel.RunBindToCloseCallbacks(onCallbackError)

## Escopo verificado

`src/runtime/DataModel.luau`, `src/runtime/DataModel.spec.luau`. Território limpo confirmado via
`git status --porcelain` (só esses 2 arquivos mudam dentro de `src/runtime/`; mudanças em
`src/services/**`/`tools/**` são do agente concorrente `task-services-019-fix`, território
diferente, sem overlap).

## Suíte de testes (reproduzida, não aceita por self-report)

`lune run` em cada um dos 9 specs de `src/runtime/`, individualmente:

| Arquivo | Resultado |
|---|---|
| ClassRegistry.spec.luau | 33/33 |
| DataModel.spec.luau | 29/29 |
| Instance.spec.luau | 64/64 |
| Integration.spec.luau | 9/9 |
| Sandbox.spec.luau | 25/25 |
| Scheduler.spec.luau | 16/16 |
| Signal.spec.luau | 8/8 |
| TypeNameResolver.spec.luau | 4/4 |
| init.spec.luau | 7/7 |
| **Total** | **195/195** — bate exatamente com o alegado |

`luau-lsp analyze` (platform standard e roblox) nos 2 arquivos: zero diagnósticos. `--!strict`
presente nos dois, zero ocorrência de `any` (grep).

## Reproduções independentes da corrida (scripts descartáveis, fora do repo/apagados depois)

1. **Prova de que a correção era necessária, não só cautela**: montei duas variantes usando o
   `Scheduler` real — (a) conecta `ThreadError` DEPOIS do laço de `Spawn` (a primeira versão que
   o coder diz ter tentado), (b) conecta ANTES + auto-registro via `coroutine.running()` (o padrão
   atual). Callback erra SINCRONAMENTE, sem yield. Resultado: (a) captura 0 erros — o listener
   perde o erro porque ele já disparou e terminou de propagar antes do `Connect` rodar; (b) captura
   1 erro. Confirma que a corrida é real e que o fix resolve exatamente o caso extremo (erro
   síncrono, sem yield) — não é só o caso já coberto pelo spec, que também usa erro síncrono sem
   yield no teste "onCallbackError FORNECIDO" (linha 559-577 do spec).

2. **Cenário exato do bug original (task-cli-033)**: script chamando `DataModel.RunBindToCloseCallbacks`
   de verdade (módulo real, não recriado), com 2 threads ALHEIAS (`scheduler:Spawn` direto, fora da
   função) suspensas em `scheduler:Wait` e retomadas+errando DURANTE a janela (callback de
   `BindToClose` também yielda para manter a janela aberta), mais 1 callback de `BindToClose` que
   erra de verdade. Resultado: `ThreadError` cru do Scheduler disparou 3x (2 alheias + 1 própria) —
   prova que o erro alheio realmente ocorre na janela e não é engolido globalmente — mas
   `onCallbackError` disparou exatamente 1x, com a mensagem certa (a do callback próprio). Filtro
   por identidade de thread funciona como alegado.

3. **Múltiplos callbacks, um erra (item 7 do pedido — não há spec dedicado exatamente para esta
   combinação: os specs cobrem "múltiplos callbacks sem erro" e "erro único com onCallbackError"
   separadamente, nunca as duas juntas)**: 3 callbacks registrados, o do meio erra sincronamente,
   os outros dois yieldam e completam. Resultado: os dois callbacks que não erraram rodaram até o
   fim (flags setadas), `onCallbackError` disparou exatamente 1x com a mensagem do callback certo.
   Regressão de task-runtime-033 confirmada intacta.

4. Reconferi por leitura o desconecte do listener (linhas 401-413 e 454-460 de `DataModel.luau`) e
   o teste correspondente ("desconecta seu próprio listener...", linha 622-640 do spec) — passou
   na suíte. Não achei necessidade de reproduzir por script separado além do que o spec já cobre
   fielmente (a lógica é direta: `if errorConnection ~= nil then errorConnection:Disconnect() end`
   sempre executa antes do `return`).

5. Comparei o padrão implementado (`ownThreads` + connect-antes-do-spawn + auto-registro via
   `coroutine.running()` dentro da própria coroutine) linha a linha contra `Sandbox.luau` (`buildTaskGlobal.spawn`,
   linhas 233-278, e `Sandbox.Run`, linhas 500-554) — é genuinamente o mesmo padrão replicado, não
   uma aproximação.

## Achados

Nenhum GRAVE/ALTO/MÉDIO. Um ponto BAIXO, não bloqueante:

- **BAIXO** `DataModel.luau:389` — `ownThreads` é uma tabela comum (`{}`), sem `__mode = "k"` como
  o mesmo padrão em `Sandbox.luau` usa. Na prática não é uma falha: `ownThreads` e o
  `errorConnection` são estritamente locais à chamada síncrona de `RunBindToCloseCallbacks`
  (a função bloqueia em `scheduler:Run(anyStillAlive)` até todas as threads morrerem e desconecta
  o listener antes de retornar), então não há vazamento de memória de fato — é só uma
  inconsistência estilística com o padrão-irmão, sem cenário de falha concreto. Não gera achado
  reportável por si (regra do time: "achado precisa de cenário de falha concreto").

## Veredito

APROVADO. Todos os 9 itens do checklist pedido foram reproduzidos independentemente com resultado
idêntico ao alegado pelo coder; nenhuma divergência encontrada entre o self-report e a realidade
observada.
