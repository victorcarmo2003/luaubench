# Revisão — task-services-019 (DataStore v2 + família Pages)

Revisor: `revisor-services` (read-only). Nenhum self-report do coder foi aceito sem reprodução própria — todos os itens abaixo foram reproduzidos independentemente.

## Metodologia

1. Lido `.claude/tasks.json` (task-services-019) e `.claude/agents-memory/arquiteto-services-2026-09-05.md` (L2.0.1–L2.1.8).
2. Lidos os 4 arquivos novos (`DataStore.luau`/`.spec.luau`, `Pages.luau`/`.spec.luau`) e o diff completo dos 5 modificados (`GlobalDataStore.luau`, `Store.luau`/`.spec.luau`, `Index.luau`/`.spec.luau`).
3. Rodada a suíte COMPLETA de `src/services/**` (23 arquivos `.spec.luau`) via `lune run`.
4. Criado um `git worktree --detach HEAD` (commit `79d1343`, ANTES desta tarefa) para estabelecer a baseline real de 233 testes, sem tocar a árvore de trabalho principal (onde `task-cli-025` está ativo em paralelo).
5. Escrito um script de verificação PRÓPRIO (não reusa `DataStore.spec.luau`), copiado temporariamente para a raiz do repo, executado, e apagado logo em seguida — cobre GetVersionAsync, ListVersionsAsync (minDate/maxDate), ListKeysAsync (prefix/excludeDeleted), paginação completa (união sem duplicar/pular), sortDirection omitido/presente, e o cross-check GlobalDataStore↔DataStore sobre o mesmo `Store`.
6. Inspecionado o `Full-API-Dump.json` pinado (`tools/api-dump.lock.json`, commit `28360dea...`) diretamente via Python para confirmar `DataStoreKey`, `Yields` tags, e o schema de `Cursor`/`DataStoreObjectVersionInfo`.
7. `luau-lsp analyze` nos 10 arquivos tocados (código + specs).
8. `git status`/`git diff --stat` para confirmar território limpo.

## Resultados

### 1. Regressão — 265/265 exato

Baseline (worktree em `79d1343`, antes da task): **233/233**, confirmado rodando a suíte de `src/services/**` inteira ali.
Atual (árvore de trabalho): **265/265**, confirmado rodando os mesmos 23 arquivos.
Delta = +32, decomposto e conferido:
- `Index.spec.luau`: 10 → 12 testes (+2)
- `Store.spec.luau`: 24 → 30 testes (+6)
- `DataStore.spec.luau`: novo, 13 testes
- `Pages.spec.luau`: novo, 11 testes
- Total: 2+6+13+11 = 32. **Bate exatamente com a soma alegada.**

### 2. GetVersionAsync / ListVersionsAsync (minDate/maxDate) / ListKeysAsync (prefix/excludeDeleted)

Reproduzido em script próprio, independente do `DataStore.spec.luau`:
- `GetVersionAsync` de versão existente devolve `(value, keyInfo)` corretos; de versão inexistente devolve `(nil, nil)`. OK.
- `ListVersionsAsync` com `maxDate` no passado distante (1ms) filtra tudo; com `minDate` no passado distante não filtra nada; com `minDate` no futuro distante filtra tudo. OK.
- `ListKeysAsync` com `prefix` filtra corretamente (`"user_"` → só as 2 chaves que casam); `excludeDeleted=true` exclui a chave tombstoned, `excludeDeleted=false` inclui. OK.

### 3. Fluxo completo de paginação — sem duplicar nem pular

17 chaves escritas, `pageSize=5` → exatamente 4 páginas (5+5+5+2); a união de todos os itens de todas as páginas tem exatamente 17 elementos únicos, todas as 17 chaves esperadas presentes, nenhuma duplicada. `AdvanceToNextPageAsync` chamado depois de `IsFinished == true` ERRA (`"already the last page"`) — não é no-op silencioso. Confirmado independentemente.

### 4. sortDirection omitido vs. presente

Omitido: não erra (usa Ascending). Presente com string (`"Descending"`) e com boolean (`true`) — ambos ERRAM com `[LuauBench]` citando `sortDirection`. Confirmado que QUALQUER valor não-nil erra, não só valores "errados".

### 5. GlobalDataStore.luau — os 3 exports novos são adição pura

Diff mostra 23 inserções / 4 remoções, e as 4 remoções são só reescrita do COMENTÁRIO do bloco `return` (não de código). `local store`/`local storeIdOf`/`local keyInfoOrNil` já existiam nas linhas 51/56/70 do arquivo, ANTES do diff — o `return` só passou a expor essas 3 referências já existentes. `GlobalDataStore.spec.luau` (arquivo intocado nesta tarefa) continua 19/19 — nenhuma regressão.

### 6. Store.luau — ListVersions/ListKeys são funções novas

Diff confirma: `GetVersion`/`Set`/`Get`/`Update`/`Remove` (task-017) não têm nenhuma linha alterada; `ListVersions`/`ListKeys` são blocos 100% novos, anexados ao fim do `Store.new()`. `Store.spec.luau`: 30/30 (24 antigos + 6 novos, todos passando).

### 7. DataStore.luau/Pages.luau reusam o MESMO Store singleton

Confirmado por teste próprio: `SetAsync` (herdado de GlobalDataStore) seguido de `GetVersionAsync` (DataStore) enxerga a MESMA escrita; `GetDataStore` com o mesmo nome memoiza (mesma instância `Instance`); uma segunda referência memoizada também vê os dados. Nenhum segundo `Store.new()` — confirmado por leitura direta (`local store = GlobalDataStoreBehavior.Store :: Store.Store` em `DataStore.luau`, sem `Store.new()` em lugar nenhum de `behavior/`).

### 8. Achado de escopo — `DataStoreKey` como string em vez de Instance

**Confirmado como limitação GENUÍNA do gerador/formato do dump, não descuido do coder:**
- `DataStoreKey` EXISTE no dump pinado (`Superclass = "Instance"`, tags `["NotCreatable", "NotReplicated"]`, único membro `KeyName` string com `Capabilities.Read = ["DataStore"]`) — confirmado lendo o JSON diretamente.
- `Pages:GetCurrentPage()`/`DataStore:ListKeysAsync()` no dump têm `ReturnType = { Category: "Group", Name: "Array" }` — **sem nenhuma parametrização de item**, confirmado lendo o JSON diretamente.
- `tools/generate-services.luau`: a função `luauReturnType` mapeia QUALQUER `Group/Array` para `{ unknown }` — não há informação no dump para fazer melhor. O fecho de classes (`closureSet`, linhas ~250-277) só caminha por `tools/coverage.luau` (seed manual) + cadeia de `Superclass` — NUNCA por `ValueType` de membro/retorno, nem mesmo para `Category == "Class"` singular. Ou seja: mesmo se o dump parametrizasse o item do Array, o gerador atual ainda não descobriria a classe sozinho — precisaria estar em `coverage.luau`.
- **Nota**: a própria lista de classes L2.1.7 do arquiteto (que o coder de task-018 já seguiu) NÃO incluía `DataStoreKey` — a omissão já vinha do planejamento, não é uma falha nova do coder de task-019. O coder corretamente NÃO tocou `tools/`/`generated/` (fora do território desta tarefa) e documentou extensivamente a divergência no cabeçalho de `DataStore.luau`, pedindo roteamento de uma tarefa dedicada.
- **Ação recomendida**: abrir uma tarefa `coder-services` que toque `tools/coverage.luau` + `generated/` para adicionar `DataStoreKey` (e ensinar o gerador a reconhecer o padrão "Array que na prática devolve uma Class relacionada", ou aceitar hardcode pontual). Até lá, `ListKeysAsync` diverge do Roblox real (strings em vez de `DataStoreKey.KeyName`) — divergência DECLARADA, mas ainda uma lacuna de fidelidade que a regra 00 pede para eventualmente fechar.

### 9. `--!strict` / zero `any` / lint

Todos os 8 arquivos de código+spec tocados têm `--!strict` na primeira linha. `grep -n "\bany\b"` não encontrou nenhuma ocorrência nos 5 arquivos de código (`DataStore.luau`, `Pages.luau`, `GlobalDataStore.luau`, `Store.luau`, `Index.luau`). `luau-lsp analyze` sobre os 10 arquivos: exit 0, zero diagnósticos.

### 10. Território limpo

`git status`/`git diff --stat` restrito a `src/services/`: exatamente os 5 modificados + 4 novos esperados. Nada em `src/runtime/`, `src/valuetypes/`, `tools/`, `generated/`. (Mudanças concorrentes em `src/cli/**` pertencem a `task-cli-025`, rodando em paralelo, fora do escopo desta revisão — confirmadas como território diferente.)

## Verificações extras de fidelidade (dump direto)

- `DataStore:GetVersionAsync`/`ListVersionsAsync`/`ListKeysAsync` e `Pages:AdvanceToNextPageAsync` têm tag `Yields` no dump — uso de `AsyncCall.Yield` em todos os quatro é fiel, não decorativo.
- `DataStoreVersionPages`/`DataStorePages`: `Members = []` (sem `Cursor`, herdam só de `Pages`) — `hasCursorProperty = false` está correto.
- `DataStoreKeyPages`/`DataStoreListingPages`: `Members = ["Cursor"]` — `hasCursorProperty = true` está correto para `DataStoreKeyPages` (única usada nesta tarefa).
- `DataStoreObjectVersionInfo`: exatamente `CreatedTime`(int64)/`IsDeleted`(bool)/`Version`(string), todos `ReadOnly` — bate exatamente com o que `buildVersionItems` escreve via `SetPropertyRaw`.

## Achados

**MÉDIO** — `src/services/behavior/DataStore.luau:46-59` (cabeçalho) / `buildKeyItems` (linha ~138-150)
Problema: itens de `ListKeysAsync`/`DataStoreKeyPages:GetCurrentPage()` são strings cruas, não instâncias `DataStoreKey` (que existem no dump mas não são geradas).
Cenário de falha: um script que faz `for _, k in pages:GetCurrentPage() do print(k.KeyName) end` (uso real e razoável, espelhando a doc oficial) quebra no LuauBench com "attempt to index a string value", mesmo sendo código válido no Roblox real.
Correção: tarefa dedicada tocando `tools/coverage.luau` + `generated/classes/DataStoreKey.luau` (fora do território desta task, já reportado pelo coder) — adicionar `DataStoreKey` ao coverage e, em `buildKeyItems`, trocar a string crua por `Runtime.ClassRegistry.NewEngineInstance("DataStoreKey")` com `SetPropertyRaw(item, "KeyName", entry.Key)`.

Nenhum outro achado GRAVE/ALTO/BAIXO. Toda alegação do coder foi reproduzida e bateu.

## Veredito

**APROVADO COM RESSALVAS** — o código entregue é correto, fiel ao dump, sem regressão, e a única lacuna (`DataStoreKey`) já está honestamente declarada e corretamente fora do território da tarefa. A ressalva é só para garantir que a lacuna vire uma tarefa de acompanhamento, não para bloquear o merge desta.
