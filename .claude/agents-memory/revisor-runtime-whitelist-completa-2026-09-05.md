# Revisão — task-runtime-026 (whitelist completa do Sandbox)

Data: 2026-09-05. Arquivos revisados: `src/runtime/Sandbox.luau`, `src/runtime/Sandbox.spec.luau` (diff real confirmado via `git diff HEAD` — só esses dois arquivos + `.claude/tasks.json` mudaram em `src/runtime/`; `Instance.luau` não foi tocado).

Contexto lido antes da revisão: `.claude/tasks.json` (task-runtime-026), `.claude/agents-memory/arquiteto-cli-2026-09-05.md` Decisão 12, `src/runtime/Scheduler.luau`, `src/runtime/Instance.luau` (trecho de `InstanceMeta`/`internals`).

Verificação executada eu mesmo (binário `lune` de `C:\Users\hakor\.rokit\bin\lune`, nunca só relato do coder):

- `lune run src/runtime/Sandbox.spec.luau` → 13/13, processo inteiro em 0.319s (confirma que `wait(0.05)` não é sleep de SO — se fosse, o processo teria levado >0.05s só nesse teste, e o teste cobre três esperas encadeadas).
- Todos os specs de `src/runtime/*.spec.luau` rodados individualmente: ClassRegistry 29, DataModel 12, Instance 57, Integration 9, Sandbox 13, Scheduler 16, Signal 7, init 6 → soma **149**, bate exatamente com o relatado.
- Todos os specs de `src/services/**/*.spec.luau`: 9+3+14+5+16+4+8+11+3 → soma **73**, bate exatamente.
- Nenhum spec pré-existente foi alterado (confirmado por `git diff --stat`: só `Sandbox.luau`/`Sandbox.spec.luau` mudaram em `src/runtime/`).
- `grep -n '\bany\b'` nos dois arquivos: única ocorrência de código real é a linha 392 (cast de fronteira pré-existente de `LoadOptions.environment`, já documentado antes desta tarefa — não é `any` novo). Resto são menções em comentário.
- `luau-lsp analyze --platform=standard src/runtime/Sandbox.luau` sem erros reportados.
- Ative tentativa de escape com 3 probes próprios fora de `src/runtime/` (removidos ao final, árvore de trabalho limpa):
  1. `getmetatable("")` + `rawset` na metatable de string, tentando sequestrar `string.__index` globalmente (efeito em TODO o processo, não só na Instance) — **bloqueado pelo próprio Luau**: `setmetatable("", ...)` erra `table expected, got string`, e a metatable de string já vem como tabela `readonly` (`rawset` nela erra `attempt to modify a readonly table`). Sem escape aqui.
  2. Superfície de `buffer` enumerada via `pairs(buffer)`: só `copy/create/fill/fromstring/len/read*/write*/tostring`, todas operações em memória própria do script — sem I/O, biblioteca padrão do Luau, nenhuma função escondida.
  3. `newproxy(true)` + `getmetatable` + tentar setar `__gc`: a atribuição não erra, mas não há evidência de o finalizer rodar (comportamento inconclusivo, não vale como achado sem mais investigação — Luau notoriamente não roda `__gc` de userdata criado em Lua por segurança).
  4. **rawset/rawget diretamente sobre uma `Instance` real** (via `Instance.NewBase`, injetada por `extraGlobals`, simulando `game`/`workspace`/`script` que `cli` vai passar) — **ESCAPE CONFIRMADO, achado novo abaixo.**

---

## Achados

### [GRAVE] Sandbox.luau:308-311 × Instance.luau:782 — `rawset`/`rawget` liberados nesta tarefa permitem corromper QUALQUER Instance compartilhada, sem tocar `getmetatable`/`setmetatable`, e sem que travar `__metatable` (o fix cogitado para task-runtime-027) resolva nada

**Problema:** `Instance.new`/`NewBase` cria a instância como `setmetatable({}, InstanceMeta)` — uma tabela Luau **vazia**, com todo o estado real (`Name`, `Parent`, propriedades, métodos) guardado à parte, em `internals[instance]` (`Instance.luau:135-136`), nunca como campo bruto da própria tabela. `rawset(instance, chave, valor)` grava a chave DIRETO na tabela crua da Instance, sem passar por `InstanceMeta.__newindex` (que valida schema/read-only) e sem precisar de `getmetatable`/`setmetatable` — é ortogonal ao achado já documentado no cabeçalho de `Sandbox.luau`. Pior: depois desse `rawset`, toda leitura NORMAL (`instance.Nome`, sintaxe de ponto comum) passa a devolver o valor forjado, porque o Luau só invoca `__index` quando a chave está ausente da tabela crua — uma vez que `rawset` grava a chave, ela deixa de estar ausente, e `__index` nunca mais é consultado para aquela chave, PARA QUALQUER código que segure a mesma referência (não é efeito isolado ao script atacante). Isso alcança até MÉTODOS herdados (`Destroy`, `WaitForChild`, etc.) e os próprios objetos de evento (`Changed`, `ChildAdded`...). No Roblox real isso é estruturalmente impossível: `rawset`/`rawget` exigem uma tabela Lua como primeiro argumento; `rawset(workspace, "Name", "x")` erra `table expected, got Instance` porque Instance é userdata.

**Cenário de falha (reproduzido empiricamente, script de prova roda e é apagado depois):**
```lua
-- Dentro do Sandbox, com `target` = uma Instance real (o que `cli` vai passar como game/workspace/script)
rawset(target, "Name", "HIJACKED-VIA-RAWSET")
target.Name --> "HIJACKED-VIA-RAWSET" (leitura normal, __index nem é chamado)

rawset(target, "Destroy", function() end)  -- substitui o método real por um no-op
target:Destroy()  -- não destrói nada de verdade, silenciosamente

-- Do lado de FORA do sandbox (outro script, ou o próprio `cli`/`services` segurando a
-- mesma referência de `target`):
target.Name --> continua "HIJACKED-VIA-RAWSET"
```
Confirmado que a corrupção é visível fora da thread que a causou (mesma referência, output do probe: `HOST: root.Name agora (via runtime, mesma referencia): HIJACKED-VIA-RAWSET`).

**Por que isso NÃO é coberto pelo achado já documentado (getmetatable/setmetatable) nem seria resolvido pela mitigação sugerida (`InstanceMeta.__metatable` travado):** `rawset`/`rawget` **ignoram metatables inteiramente** — é exatamente para isso que existem. Travar `__metatable` bloqueia `getmetatable(instancia)`/`setmetatable(instancia, novaMeta)`, mas não tem nenhum efeito sobre `rawset(instancia, chave, valor)`, que nunca consulta a metatable. É um segundo vetor, independente, aberto pela MESMA adição desta tarefa (`rawget`/`rawset` entraram juntos com `setmetatable`/`getmetatable` na whitelist).

**Evidência de que o fix é barato e já tem precedente no próprio arquivo:** `Instance.SetClassMethods`/`Instance.SetClassSchema` já exigem que suas tabelas compartilhadas cheguem `table.freeze`-adas antes de instalar (`Instance.luau:838`, `:903` — mensagem de erro explícita cobrando isso). A tabela POR INSTÂNCIA (`local self = setmetatable({}, InstanceMeta)`, `Instance.luau:782`) é a única que ficou de fora dessa disciplina — e como ela é e sempre será vazia (todo campo real vive em `internals`), `table.freeze(self)` antes de retornar não quebraria nenhuma leitura/escrita legítima via `__index`/`__newindex` (que nunca tocam a tabela crua), só bloquearia `rawset` direto nela, com o mesmo erro `attempt to modify a readonly table` que já vimos acontecer com a metatable (readonly) de string.

**Correção (fora do escopo desta tarefa — é `Instance.luau`, mesma pendência de acompanhamento que `task-runtime-027`, mas precisa ser tratada COMO PARTE dela, não como segunda rodada, porque a mitigação de `__metatable` sozinha não fecha isto):**
1. `table.freeze(self)` no ponto de criação da Instance (`Instance.luau:782`, e qualquer outro `setmetatable({}, InstanceMeta)` equivalente), fechando o vetor `rawset`.
2. Travar `InstanceMeta.__metatable` (já cogitado para task-runtime-027), fechando o vetor `getmetatable`/`setmetatable`.
3. As duas são necessárias — nenhuma sozinha cobre a outra. Recomendo atualizar o escopo de task-runtime-027 (ou abrir uma tarefa irmã) para deixar isso explícito, para o próximo `coder-runtime` não implementar só a trava de `__metatable` e fechar a tarefa achando que resolveu o RISCO RESIDUAL DECLARADO por inteiro.

---

## Confirmações (não são achados, são checagem do que o coder relatou)

- **Fixture OOP com `setmetatable`/`__index`** (padrão `Counter.new`/`Counter:increment` estilo ProfileStore) roda e acumula estado real dentro do Sandbox — reproduzido, 13/13 passa incluindo este teste.
- **`getmetatable`/`rawget`/`rawset`/`rawequal`/`rawlen`/`newproxy`/`buffer`** presentes e funcionalmente corretos (não só `typeof(...) == "function"`) — teste do coder já exercita comportamento real (`rawget` ignora `__index`, `rawequal` compara identidade, `buffer.writeu8`/`readu8` fazem round-trip, `newproxy(true)` devolve `userdata`); reproduzi independentemente com probes próprios e bate.
- **`os.date`/`os.difftime` presentes; `os.getenv`/`os.exit`/`os.remove`/`os.rename`/`os.tmpname` ausentes** — confirmado, inclusive tentando alcançá-los ativamente nos meus próprios probes (nenhum caminho alternativo encontrado, ex.: não há `os.getenv` escondido atrás de `os.date`/`os.difftime`, os dois são funções isoladas capturadas por upvalue).
- **`wait`/`spawn`/`delay`/`tick`/`time` roteiam pelo Scheduler**, nunca sleep de SO: `lune run` do spec inteiro (13 testes, incluindo 3 avanços de `StepOnce` para resolver um `wait(0.05)`) terminou em 0.319s de processo total — se fosse sleep real, só esse teste levaria ≥50ms de tempo de parede bloqueante, e o teste em si trava a asserção em cada `StepOnce` (`waitCompleted` só vira `true` depois do terceiro `StepOnce`, nunca antes). Confirmado por leitura de código: `env.wait = taskGlobal.wait`, `env.spawn = taskGlobal.spawn`, `env.delay = taskGlobal.delay` (Sandbox.luau:340-342) são literalmente a MESMA closure de `buildTaskGlobal` que `task.wait`/`task.spawn`/`task.delay` usam (Sandbox.luau:161-193) — não há segunda implementação em lugar nenhum.
- **Divergência de timing do `spawn` legado (documentada, não corrigida) — aceitável como está.** O comentário em Sandbox.luau:325-339 admite que, no Roblox real, `spawn` legado não roda imediatamente (deferido ao próximo resumption cycle), diferente de `task.spawn` (síncrono até o primeiro yield) — e que essa nuance não foi confirmada por pesquisador nesta tarefa. Como o próprio board (task-runtime-026) pede explicitamente "rotear pelo `options.scheduler` exatamente como `task.*` já faz hoje" (ou seja, aliases 1:1 são o critério de aceite, não uma reimplementação de timing), e a divergência está documentada com honestidade (regra 00) em vez de escondida ou adivinhada, considero isso **aceitável como está** — não é motivo de reprovação. Fica como nota de fidelidade para quando/se alguém for atrás do timing exato do `spawn` legado.
- **Isolamento de host intacto** para a whitelist expandida: `fs`/`net`/`process`/`serde`/`io`/`require`/`debug` continuam `nil` mesmo com `rawget`/`newproxy`/`buffer` liberados — testei ativamente tentar alcançar `os.getenv` via metatable de string (bloqueado pelo próprio Luau, tabela readonly) e enumerar toda a superfície de `buffer` (só operações em memória, zero I/O). Nenhum caminho novo até o host além do já documentado (Instance) e do que reportei acima (rawset/rawget sobre Instance).
- **O coder NÃO tentou corrigir o achado de `getmetatable`/`setmetatable`** — confirmado por `git diff HEAD`: `Instance.luau` não aparece na lista de arquivos modificados, só `Sandbox.luau`/`Sandbox.spec.luau`/`.claude/tasks.json`. O achado foi só documentado (cabeçalho do módulo + comentário pontual em `buildEnvironment`) e virou task-runtime-027, como relatado.
- **Regressão total: 149 runtime + 73 services, nenhum spec pré-existente alterado** — confirmado rodando cada arquivo individualmente (não só confiando no número relatado).

## Veredito

**APROVADO COM RESSALVAS.**

A tarefa em si (completar a whitelist conforme a Decisão 12 do arquiteto, sem tocar `Instance.luau`, documentando o achado conhecido) foi executada corretamente: 13/13 testes reais, zero regressão, zero `any` novo, cada adição comentada com a justificativa exigida, isolamento de host (`fs`/`net`/`process`/`serde`/`io`/`require`) intacto e testado ativamente. O coder não tentou consertar `Instance.luau`, como instruído.

A ressalva é o achado GRAVE acima: `rawget`/`rawset` — adicionados NESTA MESMA tarefa — abrem um sexto vetor de escape (corrupção de qualquer Instance compartilhada, sem depender de `getmetatable`/`setmetatable`) que o próprio coder não detectou e que **não é fechado** pela mitigação já cogitada para task-runtime-027 (travar `__metatable`). Isso não bloqueia o merge desta tarefa — o critério declarado da task-runtime-026 é "não conceder acesso ao HOST", e `rawset` sobre uma Instance não toca `fs`/`net`/`process` — mas precisa entrar no escopo de task-runtime-027 (ou uma tarefa irmã) antes que `cli` comece a injetar `game`/`workspace`/`script` de verdade no Sandbox, porque nesse ponto o vetor deixa de ser teórico.
