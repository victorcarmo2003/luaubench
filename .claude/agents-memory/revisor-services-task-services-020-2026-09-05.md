# Revisão — task-services-020 (OrderedDataStore + GetSortedAsync)

Data: 2026-09-05. Revisor: `revisor-services`. Read-only, tudo reproduzido pelo revisor (nenhum self-report do coder aceito sem verificação).

## Método de verificação

1. Rodei os 24 specs de `src/services/**` no estado ATUAL (com a tarefa): **284/284 passaram** (soma manual dos contadores por arquivo: 3+9+3+9+7+14+5+13+6+8+4+12+7+19+12+19+19+11+8+11+3+30+28+24 = 284).
2. Medi o BASELINE de verdade: `git stash push -- GlobalDataStore.luau Index.luau Index.spec.luau` (mudanças rastreadas) + mover `OrderedDataStore.luau`/`.spec.luau` para fora do diretório temporariamente (arquivos novos, não rastreados). Rodei os 22 specs restantes: **265/265 passaram**. Restaurei tudo (`git stash pop` + mover os arquivos de volta) e confirmei `git diff --stat`/`git status` idênticos ao estado inicial.
3. Resultado: 284 = 265 + 19, **exatamente** a alegação do coder. Zero regressão confirmada por medição, não por confiança no relatório.
4. Testei a alegação de impossibilidade estrutural criando um script descartável (`_review_probe_020.luau`, deletado depois) chamando `ClassBuilder.Build(OrderedDataStoreGenerated, { Methods = { SetAsync = function() end } })` diretamente. Resultado: `error: método 'SetAsync' não existe em 'OrderedDataStore' segundo o Roblox API Dump 0.737.0.7371584`. **Confirmado, não é suposição do coder.**
5. Testei a mensagem exata de `GetVersionAsync` num `OrderedDataStore` real (via outro probe descartável, deletado): `GetVersionAsync is not a valid member of OrderedDataStore "OrderedDataStore"` — família nativa `Instance.luau` (`{key} is not a valid member of {ClassName} "{GetFullName}"`), a mesma usada pelo Roblox real (`"HumanoidRootPart is not a valid member of Model..."`).
6. `git diff --stat` / `git status` confirmam escopo limitado a `.claude/tasks.json` (não tocado por este agent — a única mudança nele é do `task-cli-028-fix`, agente concorrente, sem overlap) + `src/services/behavior/{GlobalDataStore,Index,Index.spec}.luau` (modificados) + `src/services/behavior/{OrderedDataStore,OrderedDataStore.spec}.luau` (novos). Nada em `runtime/`, `valuetypes/`, `tools/`, `generated/`.

## Achados

Nenhum achado GRAVE ou ALTO. Dois achados MÉDIO/BAIXO, nenhum bloqueante.

**[BAIXO] `src/services/behavior/GlobalDataStore.luau` (RemoveAsync, comentário L325-344)**
Problema: a "remoção permanente" de `OrderedDataStore` é garantida por AUSÊNCIA de método alcançável (nenhum caminho de leitura de histórico), não por ausência real de tombstone — `Store.Remove` (módulo compartilhado) continua gravando o tombstone por baixo, igual a `GlobalDataStore`/`DataStore`.
Cenário de falha: se uma tarefa futura algum dia acrescentar `GetVersionAsync`/`ListVersionsAsync` (ou qualquer leitura de histórico) à cadeia de `OrderedDataStore` sem revisitar esta decisão, a garantia de "permanente" quebra silenciosamente, porque o dado nunca foi de fato apagado.
Correção: nenhuma ação agora — é decisão documentada e razoável dado que a tarefa não autoriza tocar `datastore/Store.luau` (módulo compartilhado, fora do território). Só registrar como gatilho para quando/se `OrderedDataStore` ganhar member de histórico — o coder já deixou isso comentado no código, o que é suficiente.

**[BAIXO] `src/services/behavior/OrderedDataStore.spec.luau`**
Problema: não há teste explícito para `pagesize <= 0` ou negativo (o código trata via `pagesize > 0` antes de usar o default, mas só `nil` é exercitado no teste 7).
Cenário de falha: nenhum — é lacuna de cobertura, não bug observado.
Correção: opcional, não bloqueia aprovação.

## Itens verificados sem achado

- Ordenação ascendente/descendente, filtro `minValue`/`maxValue` (inclusive nas pontas, incluindo negativo/zero), paginação completa com `pagesize` — todos os 19 testes rodados e passando, cobrindo os cenários pedidos no despacho.
- Validação de inteiro em `SetAsync`/`UpdateAsync`/`IncrementAsync` só em `OrderedDataStore` (positivo/negativo/zero aceitos, fracionário/string/NaN/infinito rejeitados com mensagem citando "must be integers").
- Regressão confirmada: `DataStore`/`GlobalDataStore` comuns continuam aceitando valor fracionário sem erro (teste "REGRESSÃO", linha 387 do spec) — a validação não vazou.
- `storeId` inclui o `Kind` (`"DataStore"`/`"OrderedDataStore"`/`"GlobalDataStore"`) como parte da chave (`DataStoreService.luau`, `computeStoreId`) — confirmei que isso ISOLA completamente os dados: `GetDataStore("X")` e `GetOrderedDataStore("X")` endereçam stores DIFERENTES no `Store.luau` compartilhado. Reforça a garantia de "remoção permanente" (não há via alternativa de acessar o mesmo dado por um `DataStore` comum).
- `Index.luau` registra 13 entradas (confirmado por teste dedicado e por contagem manual do mapa).
- `--!strict` presente e nenhum `any` real nos 4 arquivos tocados + 2 novos (grep confirmado).
- Desempate alfabético por `key`: não é invenção isolada — já é o padrão estabelecido em `datastore/Store.luau` (`ListKeys`, task-019) para o mesmo tipo de ambiguidade de ordem. Julgamento razoável e consistente.
- Não exigir positividade: acceptance/despacho da tarefa só confirmam "inteiro"; não inventar uma restrição de sinal sem fonte é o lado seguro (evita falha por comissão, mesmo princípio já usado em outras decisões do arquiteto nesta leva).
- `pagesize` default 50 sem teto de 100: instrução explícita do despacho da tarefa ("aceitar sem impor o teto e comentar") — seguida à risca.
- Desvio de território (validação de inteiro em `GlobalDataStore.luau` em vez de `OrderedDataStore.luau`): estruturalmente forçado por `ClassBuilder.Build`, confirmado por reprodução direta (item 4 acima). Bem documentado nos dois arquivos, gated corretamente por `self.ClassName == "OrderedDataStore"`, sem duplicar lógica.

## Veredito

**APROVADO**
