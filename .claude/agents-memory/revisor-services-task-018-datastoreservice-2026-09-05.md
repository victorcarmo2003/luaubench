# Revisão task-services-018 — DataStoreService + GlobalDataStore + DataStoreKeyInfo + 3 classes de options

Revisor: `revisor-services` (read-only). Nada aceito por self-report — todo item abaixo foi reproduzido pelo próprio revisor.

## Escopo revisado

- `src/services/behavior/DataStoreService.luau` (+ `.spec.luau`)
- `src/services/behavior/GlobalDataStore.luau` (+ `.spec.luau`)
- `src/services/behavior/DataStoreKeyInfo.luau` (+ `.spec.luau`)
- `src/services/behavior/DataStoreOptions.luau` (+ `.spec.luau`)
- `src/services/behavior/DataStoreSetOptions.luau` (+ `.spec.luau`)
- `src/services/behavior/DataStoreIncrementOptions.luau` (+ `.spec.luau`)
- `src/services/behavior/Index.luau` / `Index.spec.luau` (modificados)

## Verificações reproduzidas (não aceitas por alegação)

1. **`lune run` em todos os 21 specs de `src/services/`**: todos passaram, **0 regressão**. Total 230 testes (`3+9+3+9+7+14+5+6+8+4+12+7+19+10+16+8+11+3+24+28+24`). Os 6 specs novos somam exatamente **56 testes** (6+8+4+12+7+19), batendo com a alegação do coder.
2. **`SetReadOnlyRawProperties` NÃO reexportada por `src/runtime/init.luau`**: confirmado por grep direto — só `GetPropertyRaw`/`SetPropertyRaw` aparecem nas linhas 189-193 de `init.luau`. A função `Instance.SetReadOnlyRawProperties` existe em `src/runtime/Instance.luau` mas não é alcançável por `services`. A alegação do coder está correta, e o comentário em `DataStoreKeyInfo.luau` documenta a decisão com precisão (inclusive nota que, mesmo se exportada, `SetReadOnlyRawProperties` seria o mecanismo ERRADO aqui, por ser limitada a instância LENIENTE, e `DataStoreKeyInfo` é ESTRITA). `SetPropertyRaw` é de fato a via certa, e o teste `DataStoreKeyInfo.spec.luau` prova que a proteção `ReadOnly` continua funcionando via o schema comum (escrever `CreatedTime`/`Version` erra com "Property is read only").
3. **Memoização**: reproduzido em script isolado — `GetDataStore` com mesmo `(name,scope)` devolve mesma instância; scope diferente devolve instância diferente; `GetOrderedDataStore` com mesmo nome que `GetDataStore` devolve instância DIFERENTE (ClassNames `DataStore` vs `OrderedDataStore` corretos); `GetGlobalDataStore()` memoizado e devolve `ClassName == "DataStore"` (confirmado contra `.claude/agents-memory/pesquisa-services-leva2-pendencias-2026-09-05.md`, seção 6: o dump fixado do projeto — v0.737 — já reflete a mudança de `GlobalDataStore` para `DataStore` ocorrida na v0.638; decisão do arquiteto de seguir o dump está certa e o código a implementa fielmente); `GetGlobalDataStore()` nunca colide com `GetDataStore("")` (namespaces de cache distintos).
4. **`GetAsync`/`SetAsync`**: chave inexistente → `(nil,nil)`; `SetAsync` devolve string; `GetAsync` subsequente devolve valor correto + `keyInfo` não-nil. Confirmado.
5. **`UpdateAsync`**: happy path (transform recebe `(oldValue, keyInfo)`, retorno `(newValue, newKeyInfo)`); abort com `nil` não muda o valor armazenado; **yield real dentro da transform ERRA** — testado com `require("@lune/task").wait(0)` de verdade dentro da transform (não só `coroutine.yield()` cru) e com `coroutine.yield()` direto, ambos corretamente detectados e abortados via o mecanismo `coroutine.create`+`resume`+`status`. Mensagem cita "yield" e não trava o processo.
6. **`RemoveAsync`**: devolve valor anterior + keyInfo; `GetAsync` depois devolve `nil`. O tombstone usa `Store.Remove` (já aprovado em task-017) — mecanismo de histórico (`Store.GetVersion`) existe mas não é exposto por método `*Async` nesta tarefa (fica para task-019/`GetVersionAsync`, fora do território); consistente com o board.
7. **`IncrementAsync`**: acumula corretamente (parte de 0, soma delta em chamadas seguintes); erra se o valor corrente não é número.
8. **Deep copy ponta a ponta**: `SetAsync` com uma tabela, mutação da tabela original depois de `SetAsync`, e mutação do retorno de `GetAsync` — nenhuma das duas vaza para o store. Confirmado.
9. **`DataStoreOptions:SetExperimentalFeatures({v2=true})`**: não erra.
10. **Propagação de metadata**: `SetAsync` com `DataStoreSetOptions:SetMetadata(...)` reflete corretamente em `keyInfo:GetMetadata()` de uma leitura subsequente.
11. **`--!strict`/zero `any`**: confirmado nos 6 arquivos de comportamento (header `--!strict` presente) e grep não encontrou `\bany\b` fora de comentário em nenhum dos 6 + specs. `luau-lsp analyze` limpo (exit 0, zero diagnósticos) nos 14 arquivos da tarefa.
12. **Território limpo**: `git status`/`git diff --stat` mostram só os 12 arquivos novos + 2 modificados (`Index.luau`/`Index.spec.luau`) esperados. Nada em `runtime/`, `cli/`, `valuetypes/`, `tools/`, `generated/`.
13. **`behavior/Index.luau`**: 10 entradas confirmadas (contagem real via loop), as 6 novas classes corretamente mapeadas; `Index.spec.luau` reflete exatamente essa contagem e testa `Methods`/`Initialize` presente/ausente por classe. Consistente com o registro central "discoverable" exigido pela regra 03 (nenhum `if ClassName == "X"` em `runtime`/`cli`).

## Opinião sobre o design de cache/store module-local (item 13 do pedido)

Razoável e consistente com o desenho já aprovado em L2.0.2: `DataStoreService`/`GlobalDataStore` são singletons de processo, e a arquitetura já registra explicitamente esse desenho para TODOS os Services singleton desta leva (`HttpService`/`MessagingService`/`PhysicsService`/`SoundService` também usarão o mesmo padrão). O coder testou explicitamente a consequência do design (duas `DataModel`/`Bootstrap` diferentes no mesmo processo enxergam o MESMO cache de `(name,scope)`→Instance) em vez de escondê-la. O único risco (watch mode reiniciando `DataModel` sem reiniciar o processo) já está registrado como gatilho de revisão futura pelo próprio arquiteto — não é uma lacuna desta tarefa. Não bloqueante.

## Achados

**MÉDIO** — `src/services/behavior/GlobalDataStore.luau:256` (mensagem de erro de `IncrementAsync` para valor não-numérico).
Problema: a string `"{key} is not a number and cannot be incremented"` é inventada e usada como se fosse a família Roblox confirmada, mas nenhuma pesquisa (`pesquisa-datastore-2026-09-05.md`, `pesquisa-services-leva2-pendencias-2026-09-05.md`) confirma esse texto — diferente do padrão que o próprio módulo `datastore/Value.luau` segue rigorosamente (toda mensagem sem fonte confirmada é comentada como "aproximação de boa-fé... string exata NÃO CONFIRMADA"). Aqui a mensagem não tem esse aviso, nem no código nem no `GlobalDataStore.spec.luau:344` (que a fixa via `string.find` como se fosse a string real).
Cenário de falha: um script real faz `pcall(IncrementAsync)` e compara a mensagem de erro contra o texto real do Roblox (para telemetria/log, por exemplo) — se a string real divergir, o teste do usuário passa no LuauBench e falha em produção, exatamente a categoria de bug que a regra 00 e a "regra de idioma dos erros" do projeto existem para prevenir.
Correção: adicionar o mesmo comentário de "aproximação de boa-fé, string NÃO CONFIRMADA" usado em `Value.luau`/`DataStoreSetOptions.luau`, e idealmente registrar a pendência para o `pesquisador` fechar em uma leva futura. Não bloqueia esta tarefa (comportamento — "erra" — está correto e é o que o acceptance pede), mas é uma inconsistência de disciplina que os outros arquivos da mesma tarefa (`DataStoreSetOptions.luau`, `DataStoreIncrementOptions.luau`) seguem corretamente e este não.

Nenhum outro achado. Verificado e sem problema:
- Fidelidade ao dump (ClassName de `GetGlobalDataStore`, `ReadOnly` de `DataStoreKeyInfo`, ausência de `Yields` em `GetDataStore`/`GetOrderedDataStore`/`GetGlobalDataStore`, ausência de propriedade nos schemas de `DataStoreSetOptions`/`DataStoreIncrementOptions`) — todos conferidos linha a linha contra `generated/classes/*.luau`.
- Cobertura declarada: `ListDataStoresAsync` continua com o stub `[LuauBench]` do `ClassBuilder`, testado explicitamente.
- Contrato com `runtime`: nenhum acesso a estrutura interna fora de `GetPropertyRaw`/`SetPropertyRaw`/`ClassRegistry.NewEngineInstance` (via públicas já documentadas em L2.0.3).
- Nenhuma dependência circular, nenhum `if ClassName == X` em `runtime`/`cli`.

## Veredito

**APROVADO COM RESSALVAS** — a ressalva (MÉDIO) é sobre disciplina de documentação de uma mensagem de erro não confirmada, não sobre comportamento incorreto. Não bloqueia merge; recomendo corrigir o comentário em uma tarefa pequena de follow-up ou na próxima vez que `GlobalDataStore.luau` for tocado.
