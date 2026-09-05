# Revisão — task-runtime-025 (`Sandbox.Load`)

Data: 2026-09-05. Arquivos revisados: `src/runtime/Sandbox.luau`, `src/runtime/Sandbox.spec.luau`, `src/runtime/init.luau`, `src/runtime/init.spec.luau`. Território: `src/runtime/`. Read-only.

Metodologia: leitura linha a linha dos 4 arquivos, execução real de todos os specs com o binário Lune (`C:\Users\hakor\.rokit\bin\lune.exe`), e 3 scripts de auditoria descartáveis (criados, rodados e removidos — `git status` confirmado limpo ao final, nenhum resíduo) para verificar comportamento não coberto (ou coberto só parcialmente) pelos specs comitados.

## Verificação dos 7 pontos pedidos

1. **Reuso real da whitelist**: confirmado por leitura. `Sandbox.Load` (linha 499) e `Sandbox.Run` (linha 431) chamam literalmente a mesma função `buildEnvironment(options, ownThreads)` — não há segunda definição. `SandboxChunkOptions` é `= SandboxOptions` (alias direto, não tipo espelhado à mão), então os dois nunca podem divergir de assinatura em silêncio.

2. **Isolamento**: `fs`/`net`/`process`/`serde`/`io`/`require` cru confirmados ausentes dentro de um chunk carregado via `Load` (teste comitado + reconfirmado). `getmetatable`/`setmetatable`/`rawset`/`rawget` sobre uma Instance real: escrevi um script de auditoria (`_audit_load.luau`, removido depois) que cria uma Instance de verdade via `ClassRegistry.new`, passa por `extraGlobals` para um chunk de `Sandbox.Load`, e tenta `getmetatable`/`setmetatable`/`rawset` sobre ela. Resultado: `setmetatable`/`rawset` falham com `"table expected, got userdata"` (a correção de task-runtime-027 em `Instance.luau` — proxy userdata com `__metatable` travado — se aplica igualmente dentro de `Sandbox.Load`, porque é uma propriedade da própria Instance, não do Sandbox). `getmetatable` devolve o sentinel `"The metatable is locked"`, nunca a metatable real. Confirmado: o fechamento de task-runtime-027 cobre `Load` de graça, sem precisar de nada específico neste arquivo.

3. **Retorno do chunk**: teste comitado cobre só o caso de tabela (`Sandbox.spec.luau:602-619`). Escrevi `_audit_returns.luau` (removido depois) cobrindo módulo que retorna uma função (chamável, resultado correto) e módulo que retorna 3 valores (`a, b, c = chunkFn()`, todos preservados). Os dois passam. **Achado de cobertura, não de comportamento** — ver lista abaixo.

4. **Erro de execução e de compilação**: os dois testados separadamente no spec comitado (linhas 621-659), os dois propagam via `pcall` normal, os dois com `#records == 0` (nenhum `OutputRecord`). Reconfirmado rodando o spec.

5. **`task.wait` suspende a thread chamadora**: teste comitado (`Sandbox.spec.luau:661-693`) chama `chunkFn()` de dentro de um `scheduler:Spawn`, confirma que a atribuição a `waitCompleted` só acontece depois de `scheduler:StepOnce(0.06)` — nunca antes, nunca por sleep de SO. Comportamento correto e a asserção é ativa (não apenas checa o valor final).

6. **Pendência documentada (erro em `task.spawn` assíncrono dentro de um chunk `Load`ado nunca vira `OutputRecord`)**: **reproduzi de propósito** com `_audit_pending.luau` (removido depois), simulando o cenário real: um `Script` rodando via `Sandbox.Run` chama um `fakeRequire()` que usa `Sandbox.Load` + chama o chunk na thread corrente (exatamente o padrão que `cli/ModuleLoader.luau` vai usar); o módulo requerido faz `task.spawn(function() error(...) end)`. Resultado: **0 `OutputRecord`s gerados** — o erro desaparece de verdade, não é hipotético. Ver julgamento de risco abaixo.

7. **Regressão total**: rodei cada `*.spec.luau` de `src/runtime/` e `src/services/` individualmente:
   - runtime: ClassRegistry 29, DataModel 12, Instance 63, Integration 9, Sandbox 20, Scheduler 16, Signal 7, init 6 → **162/162**.
   - services: ClassBuilder 9, Context 3, Integration 14, RejectingSignal 5, behavior/Index 4, behavior/Players 8, behavior/RunService 11, behavior/StarterPlayer 3, init 16 → **73/73**.
   Bate exatamente com o relatado pelo coder. Nenhum teste pré-existente foi alterado (`git diff HEAD --stat` nos 4 arquivos mostra só adição de linhas em `Sandbox.luau`/`Sandbox.spec.luau`/`init.luau`; `init.spec.luau` sem diff nenhum).

## Achados

**[MÉDIO] Sandbox.luau (cabeçalho, linhas 117-127) / task-cli-005 no board**
Problema: a pendência "erro dentro de `task.spawn` assíncrono num chunk carregado via `Sandbox.Load` nunca gera `OutputRecord`" é real e reproduzível no cenário de uso pretendido (não é só teórica), mas só está registrada em comentário de código e no campo `result` de `task-runtime-025` — a descrição de `task-cli-005` (que implementa `ModuleLoader.luau`, o consumidor real) não lista isto como item de aceite explícito, só referencia "Decisões 5 e 12" do arquiteto por cima.
Cenário de falha concreto (reproduzido): `ServerScriptService.Main` (via `Sandbox.Run`) chama `require(ModuloX)`; `ModuloX` (carregado via `Sandbox.Load`, chamado na thread corrente) faz `task.spawn(function() error("bug") end)` no próprio corpo. Resultado medido: zero `OutputRecord`, nenhuma linha no Output — o erro do script do usuário desaparece silenciosamente para sempre, sem crash, sem stack trace, sem nada. Isso é o oposto do objetivo central do projeto (paridade com o Output do Studio, regra 00/invariante 2).
Correção: antes de `task-cli-005` ser dado como concluído, promover esta pendência a item de aceite explícito nesse task (ou abrir uma task dedicada) — decidir se `ModuleLoader.luau` precisa repassar/agregar `ownThreads` do Script de origem para o(s) módulo(s) que ele `require`ia transitivamente, ou alguma outra forma de não perder o erro. Não bloqueia a aprovação de `task-runtime-025` isoladamente (o desenho do arquiteto pediu explicitamente para não resolver aqui), mas é risco real e crescente enquanto ninguém o assumir formalmente no board.

**[BAIXO] Sandbox.spec.luau:602-619**
Problema: o teste "chamar o chunk devolve o valor de retorno do módulo" só cobre retorno de tabela. Função e múltiplos valores (padrões comuns de `ModuleScript` real) não têm teste comitado.
Cenário de falha: se um futuro refactor do cast de fronteira (`(luau.load(...) :: unknown) :: () -> ...unknown`) ou de qualquer wrapper introduzido depois só preservar o primeiro valor de retorno, nenhum teste comitado pegaria a regressão para função ou múltiplos valores — só quebraria em produção. (Verifiquei manualmente com script descartável: hoje os dois casos funcionam corretamente.)
Correção: adicionar 2 casos de teste a `Sandbox.spec.luau` (módulo que retorna uma função chamável; módulo que retorna múltiplos valores).

**[BAIXO] init.spec.luau**
Problema: nenhum teste em `init.spec.luau` chama `Runtime.Sandbox.Load` — só `Runtime.Sandbox.Run` é exercitado através do agregador. O próprio objetivo declarado deste arquivo (cabeçalho: "nenhum cenário aqui precisa alcançar Sandbox... por fora dele") fica parcialmente furado: a reexportação de `Load` (linha 172 de `init.luau`, `Load = SandboxModule.Load`) está correta por leitura, mas sem nenhuma asserção que a exercite via `Runtime.Sandbox.Load` especificamente.
Cenário de falha: um typo futuro em `init.luau` (ex.: esquecer a linha `Load = SandboxModule.Load` numa refatoração da tabela `Sandbox`) não seria pego por nenhum teste comitado — `Sandbox.spec.luau` continuaria passando (usa `require("./Sandbox")` direto), e `init.spec.luau` nunca toca `Runtime.Sandbox.Load`.
Correção: adicionar um teste mínimo em `init.spec.luau` chamando `Runtime.Sandbox.Load(...)` (nem que seja só confirmando que devolve uma função chamável), consistente com o padrão que o arquivo já segue para as outras reexportações.

## Não encontrado / verificado sem achado

- `--!strict` presente nos 4 arquivos; nenhum `any` fora dos boundary casts documentados (mesmo precedente já usado em `Sandbox.Run`/`Instance.luau`/`ThreadBroker.luau` para a fronteira externa `luau.load`/`LoadOptions.environment`).
- `ownThreads`/`ThreadError`: confirmado que `Sandbox.Load` não registra thread nem se inscreve — erro síncrono do corpo do chunk propaga por `pcall` puro, nunca duplica `OutputRecord`.
- `Sandbox.Run` sem regressão: teste dedicado comitado + reconfirmado rodando.
- Nenhuma dependência nova de `cli`/`services` vazando para dentro de `runtime`; `Sandbox.luau` só depende de `@lune/luau` e `./Scheduler`, como antes.

## Veredito

APROVADO COM RESSALVAS

Ressalvas (nenhuma bloqueia esta task, mas devem ser endereçadas antes/durante `task-cli-005`):
1. Promover a pendência do `task.spawn` assíncrono dentro de `require` a item de aceite explícito de `task-cli-005` (ou task dedicada) — risco real, confirmado reproduzível, não apenas hipotético.
2. Cobrir retorno de função e múltiplos valores em `Sandbox.spec.luau`.
3. Cobrir `Runtime.Sandbox.Load` (via agregador) em `init.spec.luau`.
