# Revisão task-cli-030 — persistência local do "cloud" em `cli`

**Data:** 2026-09-06 · `revisor-cli` · Read-only, tudo reproduzido pessoalmente (processos `lune` reais em `%TEMP%`, nunca aceito self-report).

## Veredito

**APROVADO COM RESSALVAS**

Um achado ALTO (vazamento de path interno em duas mensagens de erro), zero GRAVE. Todo o resto do acceptance foi reproduzido com evidência de disco/processo real e bate exatamente com o que o coder alegou.

---

## O que verifiquei e como (evidência reproduzida, não lida)

### 1. As 16 suítes de `src/cli/*.spec.luau`

Rodei `lune run` em cada uma das 16 (não só as 4 alegadas mudadas). Todas verdes, números batendo exatamente com o coder:

Args 18/18, CloudStore 9/9, Diagnostics 7/7, JsonValue 8/8, Messages 16/16, ModuleLoader 12/12, OutputFormatter 13/13, ProjectFile 17/17, RunCommand 28/28, ScriptEnvironment 8/8, ScriptRunner 7/7, SyncRules 33/33, TreeMaterializer 28/28, TreePlanner 38/38, UnsimulatedGlobals 6/6, init 7/7.

### 2. Persistência real entre PROCESSOS SEPARADOS (não in-process)

O `RunCommand.spec.luau` (PARTE 3, linha 448) faz esse roundtrip chamando `RunCommand.Execute` duas vezes **no mesmo processo Lune** — como `GlobalDataStoreBehavior.Store` é singleton módulo-local do processo, essa forma não prova nada sobre o `Load`/`Import` funcionarem de verdade (o valor já estaria em memória mesmo se a leitura do disco estivesse quebrada). Por isso reproduzi com **dois processos `lune` de verdade**, em `%TEMP%/.../persist-verify`:

- Processo 1: `SetAsync("Key1", "hello-from-real-process-1")` → saiu 0, `.luaubench/cloud/datastore.json` criado com o valor certo no JSON.
- Processo 2 (processo NOVO, script reescrito para `GetAsync` + `assert`): leu `"hello-from-real-process-1"` corretamente. `assert` no script do usuário teria derrubado o processo (exit ≠ 0) se o valor estivesse errado — não derrubou.

Confirmado: persistência é real em disco, não um artefato de processo compartilhado.

### 3. `--no-persist`

Dois cenários, processo real:
- Com `--no-persist` + `SetAsync`: `.luaubench/` nunca criado.
- Com `--no-persist` + documento `datastore.json` **pré-existente** (semeado à mão com um valor sentinela) + `GetAsync`: script confirmou `nil` (nunca leu o sentinela), e hash MD5 do arquivo antes/depois idêntico (não tocado).

### 4. `FlushCloudState` não custa nada quando o Store está limpo (crítico)

Script **só-leitura** (`GetAsync` em loop, sem nenhum `SetAsync`) rodando `while true do task.wait() end` com `--timeout 1.0` contra um projeto com `.luaubench/cloud/datastore.json` **pré-existente** de uma execução anterior real. O script executou 660 iterações de `shouldContinue` (contadas pelo próprio print). Comparei `mtime`/hash MD5 do arquivo antes e depois: **idênticos** (`Modify: 2026-09-06 15:04:57...` inalterado apesar do `Access` ter mudado por causa da leitura do `GetAsync`/bootstrap). Prova por evidência de disco, não por inspeção de código, que nenhum `Save`/encode ocorre quando `Store:IsDirty() == false`.

### 5. Linha informativa de criação, uma vez, stderr

Confirmado com dois processos `lune` reais sobre o mesmo projeto: 1ª execução imprime a linha (`"...luaubench: created..."`, menciona `git-ignored`) no stderr; 2ª execução sobre o MESMO diretório não repete (grep por `.luaubench` no stderr da 2ª: vazio).

### 6. Arquivo corrompido: exit 2, aponta o caminho, arquivo intacto

Dois cenários reproduzidos (processo real):
- JSON malformado (`Snapshot.DecodeDocument` falha): exit 2, mensagem cita o caminho exato, hash do arquivo antes/depois idêntico.
- `datastore.json` é um DIRETÓRIO em vez de arquivo (`CloudStore.Load` falha): mesmo resultado — exit 2, caminho citado, nada sobrescrito.

Script nunca rodou em nenhum dos dois casos (`"SHOULD NEVER RUN"` ausente do stdout).

### 7. Falha de escrita: UM warning por execução, exit inalterado

Obstruí `.luaubench` com um ARQUIVO (em vez de diretório) e rodei um script com loop de 40 `SetAsync`+`task.wait()` sob `--timeout 1.0` (dezenas de fronteiras de tique, portanto dezenas de tentativas de `FlushCloudState`). Resultado: exatamente **1** ocorrência de `[cloud/save-failed]` no stderr, `0 error(s), 1 warning(s)`, exit code 0, e o print final do script (`"script finished despite persistence failing"`) apareceu — confirma que o script seguiu rodando com o estado em memória.

### 8. Comentário sobre `shouldContinue` como gancho de efeito colateral

Presente e inequívoco em `RunCommand.luau:292-307` (função `buildShouldContinue`), citando literalmente a frase do desenho do arquiteto ("...precisa estar comentado no código, senão parece acidente"). Não é um comentário genérico — nomeia a decisão, o motivo e a fonte.

### 9. `--!strict` / zero `any`

Confirmado nos 10 arquivos do território tocado (8 do diff + CloudStore.luau/spec da tarefa irmã). As duas únicas ocorrências da palavra `any` no diff são comentários dizendo explicitamente "sem `any`" — não há anotação de tipo `any` em lugar nenhum.

### 10. Território limpo

`git status` mostra exatamente os 8 arquivos esperados para task-cli-030 (`Args.luau`/`.spec`, `Messages.luau`/`.spec`, `RunCommand.luau`/`.spec`, `init.luau`/`.spec`). `CloudStore.luau`/`.spec` são não-rastreados (`??`) — pertencem à tarefa irmã `task-cli-029`, fora do diff desta tarefa. Conferi o diff de `init.luau`/`init.spec.luau`: cada um ganhou exatamente 2-3 linhas (repassar `NoPersist = command.NoPersist` e o campo espelho no teste de `Cli.RunProject`) — justificativa real (o tipo `RunCommand.RunOptions.NoPersist` é obrigatório, não opcional; qualquer `RunOptions` construído em `init.luau`/`init.spec.luau` PRECISA do campo), não escopo inflado.

### 11. `OnMessagePublished`/`--verbose` do MessagingService

**Fora de escopo genuíno desta tarefa** — o texto de `task-cli-030` (descrição e acceptance) fala só de persistência de DataStore; não menciona MessagingService em lugar nenhum. Confirmei em `.claude/tasks.json` que não existe nenhuma tarefa `coder-cli` (nem nova, nem pendente) para consumir `OnMessagePublished`/`Context.NotifyMessagePublished` — diferente do par `task-cli-026`/`task-services-026` (HTTP audit), que teve as DUAS pontas planejadas. `task-services-032` ("MessagingService: auditoria OnMessagePublished em --verbose") está com coluna `done`, mas o `RunCommand.Execute` (linha ~417-426, chamada a `Services.Bootstrap`) não passa `OnMessagePublished` — é um hook morto hoje. Isso é uma lacuna real do BOARD (o arquiteto criou o lado `services` sem o par `cli`), não um defeito de `task-cli-030`. Recomendo ao orquestrador abrir uma tarefa nova (`task-cli-033` ou similar) espelhando exatamente o padrão de `OnHttpRequest`/`Messages.HttpRequestAuditLine` — não bloqueia esta revisão.

---

## Achado

### [ALTO] src/cli/RunCommand.luau:251 (função `firstLineOf`) e :449 (uso em `Messages.CloudStateUnreadable`)

**Problema:** o wrapper `firstLineOf` de `RunCommand.luau` só corta a mensagem de erro na primeira quebra de linha — não remove o prefixo `caminho:linha: ` que o `error(msg, level)` nativo do Luau antepõe quando `level ~= 0`. Isso vaza o caminho absoluto de instalação do LuauBench (`D:\UserData\Documents\GitHub\luaubench\src\services:335:` / `...\src\cli\CloudStore:227:`) direto na mensagem de erro/warning mostrada ao usuário final.

**Cenário:** usuário roda `luaubench run` contra um projeto cujo `.luaubench/cloud/datastore.json` está corrompido (JSON inválido, ou virou um diretório por acidente). Reproduzido ao vivo, dois jeitos:

```
error: [cloud/state-unreadable] Could not load the simulated cloud state (DataStoreService) from "...datastore.json":
D:\UserData\Documents\GitHub\luaubench\src\services:335: Snapshot.DecodeDocument: invalid JSON: key must be a
string at line 1 column 23 -- the file was left untouched; ...
```

```
error: [cloud/state-unreadable] Could not load the simulated cloud state (DataStoreService) from "...datastore.json":
D:\UserData\Documents\GitHub\luaubench\src\cli\CloudStore:227: CloudStore: could not read cloud document "datastore"
at "..." expected a file, found a dir. -- the file was left untouched; ...
```

E também no caminho de falha de ESCRITA (`Messages.CloudStateSaveFailed`, `err` vindo de `Services.FlushCloudState` em `src/services/init.luau:357/401`, que tem o MESMO problema — só corta newline, não o prefixo de localização):

```
warning: [cloud/save-failed] Could not save the simulated cloud state ... to "...datastore.json":
D:\UserData\Documents\GitHub\luaubench\src\cli\CloudStore:170: CloudStore: could not create "..." :
Cannot create a file when that file already exists. (os error 183) -- the script keeps running ...
```

Isto é exatamente a MESMA classe de vazamento que este projeto já identificou e corrigiu uma vez (`revisor-cli-pathleak-fix-2026-09-05.md`, achado ALTO original) — a correção estabelecida é `TreeMaterializer.stripEngineErrorLocation` (`src/cli/TreeMaterializer.luau:228`), usada nos dois pontos daquele arquivo onde um erro de `runtime`/`services` cruza um `pcall` para virar mensagem de usuário. O próprio cabeçalho de `Messages.CloudStateUnreadable` (`Messages.luau:594-598`) AFIRMA seguir "o mesmo protocolo de `MaterializeInvalidClass`" — mas o protocolo real de `MaterializeInvalidClass` inclui `stripEngineErrorLocation`, e o `firstLineOf` de `RunCommand.luau`/`services/init.luau` não aplica equivalente nenhum. Contradição entre o comentário e o código.

Os testes existentes (`Messages.spec.luau:147-155`) não pegam isso porque testam `Messages.CloudStateUnreadable`/`CloudStateSaveFailed` com strings de erro JÁ LIMPAS (`"unsupported SchemaVersion 99"`, `"permission denied"`) — nunca com o erro real que `Snapshot.DecodeDocument`/`CloudStore` de fato produzem via `error(msg, 2)`/`error(msg)`. Só apareceu ao reproduzir o pipeline inteiro contra um processo real.

**Correção:** extrair (ou reexportar de `TreeMaterializer.luau`) uma função equivalente a `stripEngineErrorLocation` e aplicá-la em `RunCommand.luau` (linha 449, antes de `Messages.CloudStateUnreadable`) e em `services/init.luau` (linha ~401, antes de devolver `err` de `Services.FlushCloudState`) — ou aplicar no lado `cli` já que é `cli` quem decide o texto final (`makeFlushCloudState` já recebe o `err` cru de `Services.FlushCloudState`, dá pra limpar ali mesmo em vez de duplicar em `services`).

---

## O que NÃO é problema (verificado, não é achado)

- `hasWarned` compartilhado entre os 3 usos do gancho de flush: confirmado por evidência (1 warning com dezenas de tentativas).
- Flush forçado nos dois pontos (pós-`scheduler:Run`, pós-`RunBindToCloseCallbacks`): código presente e comentado; não testei separadamente o caminho de `BindToClose` com persistência (fora do pedido desta revisão, e já coberto por `task-cli-031`/`032` em revisão anterior).
- Exit codes 0/1/2 preservados em todos os cenários de persistência testados.
