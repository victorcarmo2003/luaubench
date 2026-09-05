# Revisão task-runtime-011 — ThreadBroker.RegisterCleanup/RunCleanups + Scheduler:Cancel

Escopo revisado: `src/runtime/ThreadBroker.luau`, `src/runtime/Scheduler.luau`, `src/runtime/Scheduler.spec.luau`. Diff conferido via `git diff` contra HEAD (arquivos eram pré-existentes, task-011 só adiciona trechos — nada removido/reescrito fora do que o coder declarou).

## Verificação empírica (rodei eu mesmo, `/c/Users/hakor/.rokit/bin/lune`)

1. **Regressão dos 4 specs do território, sem alterar Signal.luau/Instance.luau** (ambos intocados — confirmado por `git status`, não aparecem como modificados):
   - `Scheduler.spec.luau`: 16/16 (12 antigos + 4 novos de task-011)
   - `Signal.spec.luau`: 6/6
   - `Instance.spec.luau`: 33/33 — cresceu de 24→33 por **task-runtime-016** (SetClassMethods, escrita protegida sobre método/sinal/ClassName), não por esta tarefa. Confirmado: nenhum diff em Instance.luau/Instance.spec.luau nesta leva, e os 9 testes novos são todos sobre `SetClassMethods`/proteção de escrita, tema alheio a task-011.
   - `Integration.spec.luau`: 9/9, arquivo aparece modificado no `git status` mas por causa de **task-runtime-012** (rodando em paralelo), não desta tarefa — task-011 não toca esse arquivo.

2. **`grep coroutine.resume`** em `src/runtime/`: chamadas reais (não comentário) só em `Scheduler.luau:226` (ponto único, `resumeThread`) e `ThreadBroker.luau:126`/`131` (fallback standalone, documentado). As duas outras ocorrências (`Instance.spec.luau:277`, `Signal.spec.luau:140`) são testes de caixa-branca sobre coroutine crua não-gerida, esperado. Nenhum ponto novo introduzido.

3. **Script de verificação ad-hoc** (escrito e rodado por mim, depois apagado — não fica no repo):
   - `ThreadBroker.RegisterCleanup`/`RunCleanups` direto (sem Scheduler): duas limpezas na mesma thread, a primeira `error()` de propósito — `pcall(RunCleanups)` retorna `ok=true` (não propaga) e a segunda limpeza roda. Confirmado.
   - `Scheduler:Cancel`: instrumentei uma limpeza que lê `coroutine.status(co)` durante a própria execução — observei `"suspended"`, nunca `"dead"`. Ou seja, `RunCleanups` roda **antes** de `coroutine.close`, então não há janela em que a limpeza execute com o handle já fechado. Ordem em `Cancel` (`removeFromQueues` → `liveThreads=nil` → `ThreadBroker.Release` → `RunCleanups` → `coroutine.close`) é segura porque nenhuma limpeza de produção (`Disconnect` de uma `Connection`) depende do estado da própria coroutine — só de `Signal` alheio.
   - Simetria em `resumeThread`/`IsAlive`: thread que termina naturalmente (via `Spawn` síncrono e via `Delay` + `StepOnce`) roda `RunCleanups` uma única vez no ponto de poda por morte. Uma chamada **subsequente e indevida** de `Cancel` sobre essa mesma thread já morta não duplica a execução — confirmado com contador (`cleanupRunCount` ficou em 1 nos dois casos). Isso decorre diretamente de `RunCleanups` fazer `cleanups[co] = nil` **antes** de iterar (`ThreadBroker.luau:197-206`): qualquer segunda chamada encontra `list == nil` e retorna sem efeito.

4. **`--!strict` / zero `any`**: `luau-lsp analyze --platform=standard` limpo (exit 0, zero diagnósticos) nos três arquivos. `grep -E '\bany\b'` só encontra a palavra dentro de comentários que documentam a ausência de `any` (ex: "nunca `any`, regra 01") — nenhuma ocorrência como anotação de tipo.

## Achados

Nenhum. A infraestrutura entregue por esta tarefa (`RegisterCleanup`/`RunCleanups`, o encadeamento em `Cancel`/`resumeThread`/`IsAlive`, o desregistro idempotente, o isolamento por `pcall` individual) está correta, testada e sem regressão, dentro do escopo que a tarefa se propôs a cobrir.

## Nota sobre o escopo não coberto (não é achado desta tarefa)

Confirmo que a limitação declarada pelo coder é real e está corretamente documentada em ambos os arquivos (comentário de topo de `ThreadBroker.luau`, seção "PENDÊNCIA DECLARADA", e no cabeçalho de `Scheduler.luau`): `Instance.luau` (WaitForChild ramo B) e `Signal.luau` (`Wait`, listener interno) ainda não chamam `ThreadBroker.RegisterCleanup` nos dois pontos de produção que de fato vazam `Connection` hoje. Isso é **exatamente** o que ficou fora do território desta tarefa e virou `task-runtime-020` — não é motivo de reprovação aqui, é a pendência que a task-020 precisa fechar. O vazamento real continua aberto até lá.

## Veredito

**APROVADO** — para o que esta tarefa entrega (a infraestrutura `ThreadBroker.RegisterCleanup`/`RunCleanups` + integração em `Scheduler:Cancel`/`resumeThread`/`IsAlive`). O vazamento de produção em si permanece aberto e depende de `task-runtime-020`.
