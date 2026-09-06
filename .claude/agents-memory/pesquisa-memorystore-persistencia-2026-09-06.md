# Pesquisa — MemoryStoreService e persistência local (2026-09-06)

Dump fixado: mesmo usado pelo restante do projeto — commit `28360dea4b90b35dc3fe9f829baae64fb6c50e75` de `MaximumADHD/Roblox-Client-Tracker`, arquivo `Full-API-Dump.json`, cache local `D:\UserData\Documents\GitHub\luaubench\.cache\api-dump\28360dea.json` (mesmo conteúdo do arquivo `28360dea4b90b35dc3fe9f829baae64fb6c50e75.json`, `Version: 1` interno do dump). Extração via script Python lendo o JSON local diretamente (sem rede) para a Parte 1.

Fonte oficial de comportamento: Markdown/YAML fonte do repositório `Roblox/creator-docs` (o mesmo conteúdo que alimenta `create.roblox.com`), obtidos via `raw.githubusercontent.com` — fonte primária oficial, não wiki de terceiros. Fetches feitos diretamente com `curl` (conteúdo bruto lido por mim, não resumido por sub-modelo) sempre que o limite numérico era crítico; usei `WebFetch` (resumo por modelo pequeno) só para descrição textual de comportamento, e re-confirmei os números críticos com `curl` bruto depois.

---

## Pergunta 1 — Superfície REAL de MemoryStoreService e classes relacionadas

Fonte: dump oficial (campo por campo, sem inferência) + YAML oficial `Roblox/creator-docs/content/en-us/reference/engine/classes/*.yaml` + páginas de guia `content/en-us/cloud-services/memory-stores/*.md`.

### Classes encontradas no dump (6, não 4 — duas a mais do que a pergunta citava)

```
MemoryStoreService             -> Instance -> Object   (Tags: Service)
MemoryStoreSortedMap           -> Instance -> Object   (Tags: NotCreatable, NotReplicated)
MemoryStoreQueue               -> Instance -> Object   (Tags: NotCreatable, NotReplicated)
MemoryStoreHashMap             -> Instance -> Object   (Tags: NotCreatable, NotReplicated)
MemoryStoreHashMapPages        -> Pages -> Instance -> Object   (Tags: NotCreatable, NotReplicated)
MemoryStoreDistributedCounter  -> Instance -> Object   (Tags: NotCreatable, NotReplicated)
```

Todas são classes de `Instance` (como `DataStoreService`/`DataStore`), não `DataType`. `MemoryStoreService` tem tag `Service` (obtido via `GetService`), as demais são `NotCreatable` — só produzidas pelos métodos `Get*` de `MemoryStoreService`, nunca via `Instance.new`.

**Achado extra não pedido explicitamente pela pergunta, mas parte da "superfície real":** `MemoryStoreDistributedCounter` existe no dump (contador distribuído com `GetAsync()/IncrementAsync(delta, expiration)`), mas **não encontrei página de guia oficial dedicada** em `content/en-us/cloud-services/memory-stores/` para essa classe (fetch de `distributed-counter.md` e da YAML de referência retornou 404; a página-índice `memory-stores/index.md` só lista "three primitive data structures: sorted map, queue, hash map" — o contador distribuído não é mencionado nem no guia geral). **NÃO CONFIRMADO por doc de guia** — só a assinatura do dump é confiável aqui; comportamento (ex.: se afeta a mesma memory quota, se satura o mesmo request-unit budget) é inferido por analogia, não confirmado.

### Membros completos (MemberType/Security/Tags do dump + assinatura)

#### `MemoryStoreService` (4 métodos, todos `Security=None`, sem propriedades/eventos)
| Método | Assinatura | Tags |
|---|---|---|
| `GetSortedMap` | `(name: string): MemoryStoreSortedMap` | — |
| `GetQueue` | `(name: string, invisibilityTimeout: int = 30): MemoryStoreQueue` | — |
| `GetHashMap` | `(name: string): MemoryStoreHashMap` | — |
| `GetDistributedCounter` | `(name: string): MemoryStoreDistributedCounter` | — |

Doc oficial (YAML): nome é **global no jogo** — chamadas repetidas com mesmo `name` acessam a mesma estrutura de dado, de qualquer script/lugar do mesmo jogo (mesmo padrão de "identidade memoizada" que `DataStoreService:GetDataStore` já documentado na pesquisa de DataStore).

#### `MemoryStoreSortedMap` (6 métodos, todos `Security=None`, `Tags=[Yields]`)
| Método | Assinatura (dump) | Retorno documentado (guia oficial) |
|---|---|---|
| `SetAsync` | `(key: string, value: Variant, expiration: int64, sortKey: Variant): bool` | `bool` — `true` se sobrescreveu, `false` se criou novo. `sortKey` opcional; se fornecido, tem precedência sobre `key` na ordenação; deve ser número (int/float) ou string. |
| `GetAsync` | `(key: string): Tuple` | `(value, sortKey)` — `nil` se a chave não existir. |
| `UpdateAsync` | `(key: string, transformFunction: Function, expiration: int64): Tuple` | `(newValue, newSortKey)` — retry automático interno em caso de conflito de concorrência; aborta se a callback devolver `nil`; para de tentar e retorna conflito ao atingir o máximo de retries (número exato de retries **NÃO CONFIRMADO**). |
| `RemoveAsync` | `(key: string): null` | remove a chave. |
| `GetRangeAsync` | `(direction: SortDirection, count: int, exclusiveLowerBound: Variant, exclusiveUpperBound: Variant): Array` | array de itens no intervalo (bounds exclusivos, formato `{key, sortKey}`); `count` documentado com **máximo 200** (fonte: fetch resumido da doc — ver nota de confiança abaixo). |
| `GetSizeAsync` | `(): int` | número total de itens armazenados na sorted map. |

#### `MemoryStoreQueue` (4 métodos, todos `Security=None`, `Tags=[Yields]`)
| Método | Assinatura (dump) | Semântica documentada |
|---|---|---|
| `AddAsync` | `(value: Variant, expiration: int64, priority: double = 0): null` | Insere item; prioridade maior é lido primeiro; mesma prioridade segue ordem FIFO de inserção. |
| `ReadAsync` | `(count: int, allOrNothing: bool = false, waitTimeout: double = -1): Tuple` | `count` máximo **100** (fonte: fetch resumido, ver nota abaixo). `allOrNothing=false`: devolve o que estiver disponível; `=true`: só devolve se `count` itens estiverem disponíveis, senão nada. `waitTimeout=-1` = espera indefinida (doc confirma via `curl` bruto: `ReadAsync` faz polling a cada **2 segundos**, consumindo 1 request-unit adicional por 2s de espera — ver Pergunta 2). Retorna `(arrayDeValores, id)` onde `id` é usado por `RemoveAsync`. Torna os itens lidos **invisíveis** por `invisibilityTimeout` segundos (padrão 30s, configurável em `GetQueue`) — se não removidos dentro desse prazo, voltam a ficar visíveis para outro `ReadAsync` (mecanismo de "at-least-once", não "exactly-once"). |
| `RemoveAsync` | `(id: string): null` | Remove item(ns) lido(s) por `ReadAsync`. Se chamado após o `invisibilityTimeout` expirar, **não tem efeito** (confirmado em `queue.md`, ver Pergunta 2 sobre invisibility). |
| `GetSizeAsync` | `(excludeInvisible: bool = false): int` | Tamanho da fila; `excludeInvisible=true` omite itens correntemente invisíveis. |

#### `MemoryStoreHashMap` (5 métodos, todos `Security=None`, `Tags=[Yields]`)
| Método | Assinatura (dump) | Semântica documentada |
|---|---|---|
| `SetAsync` | `(key: string, value: Variant, expiration: int64): bool` | `true` se sobrescreveu, `false` se criou. |
| `GetAsync` | `(key: string): Variant` | valor ou `nil`. |
| `UpdateAsync` | `(key: string, transformFunction: Function, expiration: int64): Variant` | Se a chave não existir, `transformFunction` recebe `nil`; se a função devolver `nil`, cancela a atualização; retry automático até sucesso, `nil` da callback, ou limite de retries (retorna conflito). **Nota confirmada por fonte primária (`hash-map.md` bruto):** "the system automatically retries the operation until one of these three happens: the operation succeeds, the callback function returns `nil`, or the maximum number of retries is reached." Consome **mínimo 2 request units** por chamada (ver Pergunta 2). |
| `RemoveAsync` | `(key: string): null` | remove a chave. |
| `ListItemsAsync` | `(count: int): MemoryStoreHashMapPages` | pagina itens; `count` documentado com faixa válida **1–200** (exemplo oficial usa 32); cada item de página é `{key=..., value=...}`, sem garantia de ordenação. |

#### `MemoryStoreHashMapPages` (herda de `Pages`)
Zero membros próprios no dump — herda `IsFinished: bool` (ReadOnly), `GetCurrentPage(): Array`, `AdvanceToNextPageAsync(): null` de `Pages`, mesmo padrão já documentado para `DataStorePages`/`DataStoreKeyPages` na pesquisa de DataStore.

#### `MemoryStoreDistributedCounter` (2 métodos, `Security=None`, `Tags=[Yields]`)
| Método | Assinatura (dump) |
|---|---|
| `GetAsync` | `(): int64` |
| `IncrementAsync` | `(delta: int64, expiration: int64): int64` — retorna o valor **já incrementado**. |

Comportamento detalhado (semântica de conflito concorrente, se tem TTL igual às outras 45 dias, budget de request-unit) **NÃO CONFIRMADO** — sem página de guia oficial encontrada (ver nota acima).

### TTL/expiração — mecanismo exato (fonte primária, `memory-stores/index.md` bruto, seção "Observability" > tabela de status codes client-side)

Confirmado **por string literal do erro documentado**, não por inferência:

> `InvalidExpirationTime` — "The field 'expiration' time must be between **0** and **3,888,000**."

Ou seja: `expiration` é sempre em **segundos**, mínimo **0**, máximo **3.888.000 segundos = 45 dias**. Esse limite se aplica a `MemoryStoreQueue:AddAsync`, `MemoryStoreSortedMap:SetAsync`/`UpdateAsync`, `MemoryStoreHashMap:SetAsync`/`UpdateAsync` (todos exigem `expiration` explícito no dump — **nenhum desses métodos tem valor default de `expiration`**, script precisa sempre informar). Confirmado também em prosa por `sorted-map.md`/`hash-map.md` bruto: "The maximum expiration time is 3,888,000 seconds (45 days)." Doc geral (`memory-stores/index.md`) confirma que o **default sugerido no guia** para exemplos de `AddAsync`/`SetAsync` é 45 dias, mas isso é o valor de exemplo do guia — a API real **não tem default**, o dump exige o argumento.

### Replicação/compartilhamento entre servidores — CONFIRMADO por fonte oficial

`memory-stores/index.md` (bruto): `MemoryStoreService` é "a high throughput and low latency data service that provides fast in-memory data storage **accessible from all servers in a live session**." Os 3 (ou 4, contando o counter) tipos de dado são descritos como "primitive data structures **shared across servers** for quick processing". Isso é **fato real do Roblox confirmado por fonte primária**, não invenção: MemoryStore é compartilhado entre TODOS os servidores do mesmo universo/jogo (não é estado local de um servidor), exatamente como o usuário descreveu na pergunta. Mesma fonte confirma explicitamente a volatilidade: "Memory Stores are suitable for **frequent and ephemeral data that change rapidly and don't need to be durable**, because they are faster to access and **vanish when reaching the maximum lifetime**."

**Nota de confiança:** os itens marcados "fonte: fetch resumido" acima (máximo 200 em `GetRangeAsync`, máximo 100 em `ReadAsync`, faixa 1-200 em `ListItemsAsync`) vieram de um `WebFetch` com resumo por modelo pequeno sobre a YAML de referência — não foram re-confirmados por `curl` bruto linha a linha como os limites de expiração/tamanho foram. Tratar como **confiança alta, mas não crua** (mesmo padrão de ressalva que a pesquisa de DataStore já usou para números extraídos por resumo).

---

## Pergunta 2 — Limites e budget de MemoryStore

Fonte primária, `curl` bruto (conteúdo lido por mim, não resumido): `content/en-us/cloud-services/memory-stores/index.md`, `hash-map.md`, `sorted-map.md`, `queue.md`, `per-partition-limits.md` do repositório `Roblox/creator-docs`.

### Tamanho de item
- **Hash map**: chave até **128 caracteres**, valor até **32 KB** (erro `ItemValueSizeTooLarge` — "Value size exceeds limit (32 KB)").
- **Sorted map**: chave até **128 caracteres**, valor até **32 KB**, `sortKey` até **128 caracteres**.
- **Queue**: **NÃO CONFIRMADO** um limite de tamanho por item individual documentado explicitamente na página oficial de queue (`queue.md` não menciona um número de KB por item, ao contrário de hash map/sorted map) — só o limite agregado de estrutura (abaixo) se aplica.

### Limite de tamanho/contagem por estrutura de dado (sorted map e queue — NÃO se aplica a hash map, que é particionado)
- Máximo de **1.000.000 itens** por sorted map ou queue (`DataStructureItemsOverLimit`).
- Máximo de **100 MB** de tamanho total (incluindo chaves, no caso de sorted map) por sorted map ou queue (`DataStructureMemoryOverLimit`).

### Quota de memória (nível de jogo/universo, não por servidor)
- Fórmula: **64 KB + 1,2 KB × [número de usuários]**. Aplicada no nível do **jogo** (todos os servidores do universo somados), não por servidor.
- Ao entrar jogador: quota extra disponível **imediatamente**. Ao sair jogador: quota **não** reduz imediatamente — janela de retenção de **8 dias** antes de reavaliar para baixo.
- Ao estourar a quota: requisições que **aumentam** o tamanho falham (`TotalMemoryOverLimit`); requisições que diminuem ou mantêm o tamanho continuam funcionando.

### Budget de requisições (request units) — três camadas confirmadas
1. **Nível de jogo/universo**: **1.000 + 120 × [usuários concorrentes]** request units por minuto (erro ao estourar: `TotalRequestsOverLimit`).
2. **Nível de estrutura de dado individual** (sorted map/queue específico): **100.000 request units por minuto** (erro: `DataStructureRequestsOverLimit`).
3. **Nível de partição** (afeta principalmente hash maps, que são distribuídos em múltiplas partições): limite **NÃO documentado com número fixo** — a doc (`per-partition-limits.md`, bruto) diz explicitamente que "the exact limit fluctuates based on internal values and how the automatic partitioning process distributes your data" e que o número "50,000 RPM" citado no texto é um **exemplo hipotético ilustrativo**, não um valor real ("consider an example per-partition limit of..."). Erro ao estourar: `PartitionRequestsOverLimit`. **NÃO CONFIRMADO** — não hardcodar esse número na simulação.

### Custo por chamada em request units (a maioria das chamadas custa 1 unit; exceções documentadas)
- `MemoryStoreSortedMap:GetRangeAsync()` — custa 1 unit por item retornado (mínimo 1, mesmo se vazio).
- `MemoryStoreQueue:ReadAsync()` — custa por item retornado, **mais 1 unit adicional a cada 2 segundos de espera** (relevante para `waitTimeout`).
- `MemoryStoreHashMap:UpdateAsync()` — mínimo **2 units**.
- `MemoryStoreHashMap:ListItemsAsync()` — custa `[partições escaneadas] + [itens retornados]` units.

### Tabela de erros confirmada (útil para o `arquiteto` desenhar os erros simulados)
Do próprio doc oficial (`memory-stores/index.md`, seção Observability):
`Success`, `DataStructureMemoryOverLimit` (100MB), `DataUpdateConflict` (conflito de escrita concorrente), `AccessDenied`, `InternalError`, `InvalidRequest`, `DataStructureItemsOverLimit` (1M), `NoItemFound` (retornado por `ReadAsync`/`UpdateAsync` de sorted map quando não há item — `ReadAsync` faz polling a cada 2s até achar), `DataStructureRequestsOverLimit` (100k RU/min), `PartitionRequestsOverLimit`, `TotalRequestsOverLimit`, `TotalMemoryOverLimit`, `ItemValueSizeTooLarge` (32KB). Erros client-side adicionais: `UnpublishedPlace` ("You must publish this place to use MemoryStoreService."), `InvalidClientAccess` ("MemoryStoreService must be called from server." — **MemoryStoreService é server-only**, diferente de DataStoreService que não tem essa restrição explícita no dump), `InvalidExpirationTime` (0–3.888.000), `TransformCallbackFailed`, `RequestThrottled`, `UpdateConflict` (máximo de retries excedido).

### Isolamento Studio vs. produção — CONFIRMADO
`memory-stores/index.md` bruto: "The data in `MemoryStoreService` is isolated between Studio and production, so changing the data in Studio doesn't affect production behavior." (mesmo padrão de isolamento que já vale para o DataStore real, relevante para o `arquiteto` decidir se o LuauBench precisa simular esse isolamento também).

---

## Pergunta 3 — DataStore: escrita bem-sucedida é durável POR ESCRITA, não por encerramento de sessão

**CONFIRMADO por fonte oficial primária**, com uma ressalva sobre o que a doc NÃO afirma explicitamente.

### O que a doc confirma diretamente
`content/en-us/cloud-services/data-stores/player-data-purchasing.md` (bruto, `Roblox/creator-docs`):
- "Player data is stored **in memory on the server** and is only read from and written to the underlying data stores **when necessary**." — ou seja, o risco de perda existe justamente enquanto o dado só está na RAM do servidor, ainda **não** escrito no DataStore.
- "On a periodic loop, the server writes each player's data to the data store (provided it is safe to save)." — o autosave existe para **minimizar a janela de dado não-persistido**, não porque uma escrita já confirmada pudesse ser desfeita depois.
- `BindToClose` existe especificamente para garantir que escritas pendentes **terminem antes do processo do servidor encerrar** — doc do `DataModel.yaml`: "When you use `DataStoreService`, you should also use `BindToClose` to bind a function saving all unsaved data to DataStores. This prevents data loss if the server shuts down unexpectedly." O ponto central: o dado só é perdido se o servidor cair **antes** da chamada `*Async` retornar sucesso — não depois.

### O que a doc NÃO afirma com uma frase-garantia explícita do tipo "escrita é imediatamente durável"
Não encontrei, em `error-codes-and-limits.md` nem em `data-stores/index.md`, uma sentença literal do tipo "a successful write is immediately persisted/durable". A doc trata o tema de forma indireta: fala de escritas como "network calls that might occasionally fail" (recomenda `pcall`) e alerta que "**a failed write call... does not always guarantee that the backend write did not occur**" (`error-codes-and-limits.md`) — essa frase, lida com cuidado, na verdade reforça a conclusão pedida: mesmo quando o **servidor de jogo** não recebe confirmação (timeout/erro de rede), o **backend do Roblox** pode já ter processado e persistido a escrita — ou seja, a duração/persistência acontece no backend assim que ele processa a requisição, independente do que acontece depois com a conexão do servidor de jogo ou o próprio processo do servidor.

### Conclusão para o arquiteto
Combinando as duas fontes: a garantia real do Roblox é "escrita que o backend processou com sucesso está persistida no serviço, ponto" — o padrão de arquitetura recomendado pela própria Roblox (autosave periódico + `BindToClose`) só existe para reduzir a janela de dado que **ainda não foi enviado/confirmado**, nunca para proteger contra perda de uma escrita já confirmada. **Isso sustenta a decisão de que a camada de persistência local do LuauBench deve persistir em disco NA CHAMADA de escrita simulada (SetAsync/UpdateAsync/RemoveAsync bem-sucedida), não em algum hook de encerramento do processo `luaubench run`** — replicando fielmente essa semântica. Fontes: [player-data-purchasing.md](https://create.roblox.com/docs/cloud-services/data-stores/player-data-purchasing), [error-codes-and-limits.md](https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits), YAML de `DataModel.BindToClose`.

---

## Pergunta 4 — Formato de serialização local (`@lune/serde`)

Não é pesquisa de API do Roblox — é fato de runtime do Lune. Fonte primária: `types.d.luau` do crate `lune-std-serde`, obtido via `raw.githubusercontent.com/lune-org/lune/v0.10.5/crates/lune-std-serde/types.d.luau` — **tag exata `v0.10.5`, a mesma versão pinada em `rokit.toml`** (`lune = "lune-org/lune@0.10.5"`), não a doc "latest" (que já mostra formatos futuros como `zstd`/`hash`/`hmac` que só existem a partir de versões específicas — confirmado via `CHANGELOG.md`: `jsonc` chegou na 0.10.4, `zstd` na 0.10.2; ambos já estão dentro da 0.10.5 pinada, então **estão disponíveis**).

### O que `@lune/serde` oferece de fato na versão pinada (0.10.5)
- **`serde.encode(format: EncodeDecodeFormat, value: any, pretty: boolean?): string`** / **`serde.decode(format: EncodeDecodeFormat, encoded: buffer | string): any`**
  `EncodeDecodeFormat = "json" | "jsonc" | "yaml" | "toml"` — **4 formatos de serialização estrutural**, não só JSON.
- **`serde.compress(format: CompressDecompressFormat, s: buffer | string, level: number?): string`** / **`serde.decompress(format, s): string`**
  `CompressDecompressFormat = "brotli" | "gzip" | "lz4" | "zlib" | "zstd"` — 5 formatos de compressão.
- **`serde.hash(algorithm: HashAlgorithm, message: string | buffer): string`** / **`serde.hmac(algorithm, message, secret): string`**
  `HashAlgorithm` inclui `md5`, `sha1`, `sha224/256/384/512`, `sha3-224/256/384/512`, `blake3`.

**Correção de um achado incorreto no meio da pesquisa:** um primeiro fetch (via `WebFetch` resumido pela doc "latest" do site `lune-org.github.io`) alegou que `@lune/serde` também suporta formato `XML`. **Verifiquei contra o código-fonte real (`types.d.luau` + árvore de arquivos do repo na tag `v0.10.5`, via `git tree` da API do GitHub) e XML NÃO existe** — nem no `EncodeDecodeFormat`, nem como pasta de teste (`tests/serde/` só tem `json/`, `jsonc/`, `toml/`, `hashing/`, `compression/` — sem `xml/`, sem `yaml/` como pasta de teste dedicada mas presente no type). Registro isso porque ilustra por que resumos de doc precisam ser re-confirmados contra a fonte crua antes de virar decisão de arquitetura — exatamente a prática que a regra do projeto pede.

### Já usado no projeto — reaproveitar em vez de introduzir formato novo
Confirmado por grep em `src/`:
- `src/cli/JsonValue.luau:117` — `serde.decode("jsonc", text)` (parsing do `.project.json`/sourcemap do Rojo).
- `src/services/behavior/HttpService.luau:872,893` — `serde.encode("json", input)` / `serde.decode("json", input)` (implementação de `HttpService:JSONEncode`/`JSONDecode`).
- Nenhum uso de `toml`, `yaml`, `serde.compress`, `serde.hash`/`hmac` ainda no projeto — `serde.compress("gzip", ...)` é mencionado só como comentário/possibilidade futura em `HttpService.luau:167` (fora de escopo da tarefa que o criou), não implementado.

### Recomendação objetiva para o arquiteto (fato, não decisão de arquitetura — a decisão é dele)
- **JSON** (`serde.encode("json", ...)`/`serde.decode("json", ...)`) é o único formato de serialização estrutural **já em uso ativo** no projeto (HttpService e parsing do Rojo) — reaproveitar o mesmo formato para o snapshot local de DataStore/MemoryStore evita introduzir uma segunda biblioteca de serialização e mantém consistência com o que já existe.
- Se a persistência local precisar de arquivos legíveis/editáveis à mão por um dev (ex.: debug), `toml`/`yaml` são alternativas nativas do mesmo módulo, sem custo de dependência nova — mas nenhuma delas tem precedente de uso no projeto ainda; introduzir uma seria decisão nova, não continuidade.
- Compressão (`gzip`/`zstd`/etc.) está disponível nativamente se o volume de dados local justificar, mas **não há decisão nem uso prévio no projeto** — tratar como opção em aberto, não fato já decidido.

---

## Itens marcados NÃO CONFIRMADO (não inventar, resolver antes de codificar)

- Comportamento completo de `MemoryStoreDistributedCounter` (TTL igual às outras 45 dias? mesmo budget de request-unit? conflito concorrente em `IncrementAsync`?) — sem página de guia oficial encontrada, só a assinatura do dump é confiável.
- Número exato do "máximo de retries" antes de `UpdateAsync` (sorted map/hash map) retornar conflito — doc confirma que existe um limite, não o número.
- `GetRangeAsync` "máximo 200" e `ReadAsync`/`ListItemsAsync` "máximo 100"/"1-200" — vieram de fetch resumido da YAML de referência, não re-verificados por `curl` bruto linha a linha (diferente dos limites de tamanho/expiração, que foram).
- Limite de tamanho por item individual em `MemoryStoreQueue` — página oficial de queue não documenta um número de KB por item (só o limite agregado de 100MB/1M itens da estrutura).
- Limite numérico fixo do "per-partition throttling limit" — documentação afirma explicitamente que não há um número fixo público; "50.000 RPM" citado no texto é exemplo hipotético, não valor real.
- Frase-garantia explícita e literal do tipo "uma escrita bem-sucedida de DataStore é imediatamente durável" — não encontrada verbatim; a conclusão da Pergunta 3 é inferência bem fundamentada a partir de duas fontes primárias (comportamento de `BindToClose`/autosave + a ressalva sobre escrita-falha-não-garantir-que-não-ocorreu), não uma citação direta única.
