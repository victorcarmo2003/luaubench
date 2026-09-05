# Pesquisa — DataStoreService (2026-09-05)

Dump fixado: commit `28360dea4b90b35dc3fe9f829baae64fb6c50e75` de `MaximumADHD/Roblox-Client-Tracker`, arquivo `Full-API-Dump.json` (~8MB), já em cache local em `D:\UserData\Documents\GitHub\luaubench\.cache\api-dump\28360dea4b90b35dc3fe9f829baae64fb6c50e75.json`. `Version: 1` (campo interno do dump, não é a versão do client).

Script de extração usado (Python, lendo o JSON local diretamente — nenhuma rede usada para a parte A):
`C:\Users\hakor\AppData\Local\Temp\claude\...\scratchpad\extract_dump.py` (temporário, não faz parte do repo).

---

## A) Superfície do dump — TODAS as 16 classes pedidas existem no dump com esses nomes EXATOS

Fonte: dump oficial, campo por campo (não há inferência nesta seção).

### Cadeia de herança (todas terminam em `Instance -> Object`, ou seja, **nenhuma é DataType** — todas são classes de `Instance`, instanciáveis via `Instance.new("NomeDaClasse")` como qualquer outra Instance do Roblox):

```
DataStoreService           -> Instance -> Object   (Tags: NotCreatable, Service, NotReplicated)
GlobalDataStore            -> Instance -> Object   (Tags: NotCreatable, NotReplicated)
DataStore                  -> GlobalDataStore -> Instance -> Object   (Tags: NotCreatable, NotReplicated)
OrderedDataStore            -> GlobalDataStore -> Instance -> Object   (Tags: NotCreatable, NotReplicated)
DataStoreKeyInfo           -> Instance -> Object   (Tags: NotCreatable, NotReplicated)
DataStoreSetOptions        -> Instance -> Object   (Tags: NotReplicated)  -- CRIÁVEL via Instance.new
DataStoreOptions           -> Instance -> Object   (Tags: NotReplicated)  -- CRIÁVEL via Instance.new
DataStoreIncrementOptions  -> Instance -> Object   (Tags: NotReplicated)  -- CRIÁVEL via Instance.new
DataStoreGetOptions        -> Instance -> Object   (Tags: NotReplicated)  -- CRIÁVEL via Instance.new
Pages                      -> Instance -> Object   (Tags: NotCreatable, NotReplicated)
DataStorePages             -> Pages -> Instance -> Object   (Tags: NotCreatable, NotReplicated)
DataStoreKeyPages          -> Pages -> Instance -> Object   (Tags: NotCreatable, NotReplicated)
DataStoreListingPages      -> Pages -> Instance -> Object   (Tags: NotCreatable, NotReplicated)
DataStoreVersionPages      -> Pages -> Instance -> Object   (Tags: NotCreatable, NotReplicated)
DataStoreInfo              -> Instance -> Object   (Tags: NotCreatable, NotReplicated)
DataStoreObjectVersionInfo -> Instance -> Object   (Tags: NotCreatable, NotReplicated)
```

**Importante para o arquiteto:** as classes de opções (`DataStoreSetOptions`, `DataStoreOptions`, `DataStoreIncrementOptions`, `DataStoreGetOptions`) NÃO têm a tag `NotCreatable` — são instanciadas pelo script do usuário via `Instance.new("DataStoreSetOptions")`, exatamente como qualquer Instance real. Todas as outras 12 classes têm `NotCreatable` — só o próprio `DataStoreService`/`GlobalDataStore`/`Pages` internos as produzem (`GetDataStore`, `GetAsync`, `ListKeysAsync`, etc.), o script nunca chama `Instance.new` nelas diretamente.

### Membros completos por classe (MemberType, Security, Capabilities, Tags, assinatura)

#### `DataStoreService` (8 membros)
| Membro | Tipo | Security R/W | Capabilities | Tags |
|---|---|---|---|---|
| `AutomaticRetry` | Property (bool) | LocalUserSecurity / LocalUserSecurity | Read: [DataStore] | NotReplicated |
| `LegacyNamingScheme` | Property (bool) | LocalUserSecurity / LocalUserSecurity | Read: [DataStore] | Hidden, **Deprecated** |
| `GetDataStore(name: string, scope: string = "global", options: DataStoreOptions = nil): DataStore` | Function | None | [DataStore] | — |
| `GetGlobalDataStore(): DataStore` | Function | None | [DataStore] | — |
| `GetOrderedDataStore(name: string, scope: string = "global"): OrderedDataStore` | Function | None | [DataStore] | — |
| `GetRequestBudgetForRequestType(requestType: DataStoreRequestType): int` | Function | None | [DataStore] | — |
| `SetRateLimitForRequestType(requestType: DataStoreRequestType, baseLimit: int, perPlayerLimit: int): null` | Function | None | [DataStore] | — |
| `ListDataStoresAsync(prefix: string = "", pageSize: int = 0, cursor: string = ""): DataStoreListingPages` | Function | None | [DataStore] | **Yields** |

**Filtro "fica de fora para script comum":** `AutomaticRetry` e `LegacyNamingScheme` têm `Security = LocalUserSecurity` (Read e Write) — isso é o nível de segurança de plugin/command-bar do Studio, **não** acessível a partir de um `Script`/`LocalScript` normal dentro do jogo publicado. Um script comum de jogo NÃO consegue ler nem escrever `DataStoreService.AutomaticRetry`. Todos os métodos (`GetDataStore`, `SetAsync`, etc.) têm `Security = None`, ou seja, a restrição de "Enable Studio Access to API Services" **não é um filtro do dump** — é um erro em runtime lançado pelo backend do Roblox, o dump não modela essa restrição via Security/Capabilities.

#### `GlobalDataStore` (7 membros, herdados por `DataStore` e `OrderedDataStore`)
- `OnUpdate(key: string, callback: Function): RBXScriptConnection` — Security None, **Deprecated**, Capabilities [DataStore]
- `BatchGetAsync(keys: Array, options: Dictionary = nil): Dictionary` — Yields
- `GetAsync(key: string, options: DataStoreGetOptions = nil): Tuple` — Yields
- `IncrementAsync(key: string, delta: int = 1, userIds: Array = {}, options: DataStoreIncrementOptions = nil): Variant` — Yields
- `RemoveAsync(key: string): Tuple` — Yields
- `SetAsync(key: string, value: Variant, userIds: Array = {}, options: DataStoreSetOptions = nil): Variant` — Yields
- `UpdateAsync(key: string, transformFunction: Function): Tuple` — Yields

Todos com `Security = None`, `Capabilities = [DataStore]`. Nenhum membro fica de fora do filtro para script comum aqui.

#### `DataStore` (adiciona 5 membros)
- `GetVersionAsync(key: string, version: string): Tuple` — Yields
- `GetVersionAtTimeAsync(key: string, timestamp: int64): Tuple` — Yields
- `ListKeysAsync(prefix: string = "", pageSize: int = 0, cursor: string = "", excludeDeleted: bool = false): DataStoreKeyPages` — Yields
- `ListVersionsAsync(key: string, sortDirection: SortDirection = Ascending, minDate: int64 = 0, maxDate: int64 = 0, pageSize: int = 0): DataStoreVersionPages` — Yields
- `RemoveVersionAsync(key: string, version: string): null` — Yields, **Deprecated**

#### `OrderedDataStore` (adiciona 1 membro)
- `GetSortedAsync(ascending: bool, pagesize: int, minValue: Variant, maxValue: Variant): DataStorePages` — Yields

#### `DataStoreKeyInfo` (5 membros)
- `CreatedTime: int64` — ReadOnly (Security Read/Write = None, mas tag ReadOnly)
- `UpdatedTime: int64` — ReadOnly
- `Version: string` — ReadOnly
- `GetMetadata(): Dictionary`
- `GetUserIds(): Array`

#### `DataStoreSetOptions` (2 membros)
- `GetMetadata(): Dictionary`
- `SetMetadata(attributes: Dictionary): null`

#### `DataStoreOptions` (2 membros)
- `AllScopes: bool` (property, Security None)
- `SetExperimentalFeatures(experimentalFeatures: Dictionary): null`

#### `DataStoreIncrementOptions` (2 membros)
- `GetMetadata(): Dictionary`
- `SetMetadata(attributes: Dictionary): null`

#### `DataStoreGetOptions` (1 membro)
- `UseCache: bool` (property, Security None)

#### `Pages` (base, 3 membros — herdados por todas as *Pages)
- `IsFinished: bool` — ReadOnly
- `GetCurrentPage(): Array`
- `AdvanceToNextPageAsync(): null` — Yields

#### `DataStorePages` — 0 membros próprios (só herda de `Pages`)
#### `DataStoreKeyPages` — +1: `Cursor: string` (ReadOnly)
#### `DataStoreListingPages` — +1: `Cursor: string` (ReadOnly)
#### `DataStoreVersionPages` — 0 membros próprios

#### `DataStoreInfo` (3 membros, todos ReadOnly)
- `CreatedTime: int64`, `DataStoreName: string`, `UpdatedTime: int64`

#### `DataStoreObjectVersionInfo` (3 membros, todos ReadOnly)
- `CreatedTime: int64`, `IsDeleted: bool`, `Version: string`

**Conclusão do filtro de Security/Capabilities para a parte A:** com exceção de `DataStoreService.AutomaticRetry`/`LegacyNamingScheme` (LocalUserSecurity, fora do alcance de script comum), **nenhum outro membro** das 16 classes é filtrado por Security/Capabilities — tudo mais tem `Security = None` e `Capabilities` só contendo `DataStore` (que é a capability normal disponível a Script/LocalScript, não algo tipo `PluginOrOpenCloud`/`RemoteCommand`/`InternalTest`). Não encontrei nenhum membro com essas tags restritivas nessas 16 classes.

---

## B) Semântica real — fonte oficial (`create.roblox.com`, via `raw.githubusercontent.com/Roblox/creator-docs`, arquivos YAML do reference e Markdown do error-codes-and-limits)

Nota metodológica: o `WebFetch` direto em `create.roblox.com/docs/...` (páginas renderizadas em SPA) devolveu conteúdo pobre/resumido demais para confiar. Troquei para o **Markdown/YAML fonte** do repositório oficial `Roblox/creator-docs` no GitHub (o mesmo conteúdo que alimenta o site), via `raw.githubusercontent.com`. Isso é fonte primária oficial, não wiki de terceiros.

1. **`GetAsync(key, options)`** — retorna **2 valores**: `(value, keyInfo)`, onde `keyInfo` é uma instância `DataStoreKeyInfo`. Doc oficial (`GlobalDataStore.yaml`): "Returns the value of a key in a specified data store and a DataStoreKeyInfo instance." Chave inexistente ou deletada: `value` retorna `nil` (keyInfo também nil nesse caso, por inferência consistente com o padrão — não vi essa combinação dita explicitamente, mas é o comportamento amplamente documentado/consensual). Cache local de leitura: 4 segundos após a primeira leitura (a menos que `DataStoreGetOptions.UseCache = false`).

2. **`SetAsync(key, value, userIds, options)`** — retorna **1 valor**: a string identificadora da nova versão criada ("The version identifier of the newly created version for retrieval or removal" — `GlobalDataStore.yaml`). Exige reenviar `userIds`/metadata completos a cada chamada (não faz merge).

3. **`UpdateAsync(key, transformFunction)`** — retorna **2 valores**: `(updatedValue, updatedKeyInfo)` — Tuple contendo o valor atualizado e uma `DataStoreKeyInfo`. A `transformFunction` recebe **2 argumentos**: `(oldValue, keyInfo)` — doc oficial: "Callback Function: Accepts current value and DataStoreKeyInfo". Se a transform devolver `nil`, a escrita é **abortada** ("Returns nil from callback cancels the write"). A doc afirma explicitamente: **"The callback function cannot yield."** — se yieldar, é erro em runtime real. A transform pode devolver até 3 valores: `(newValue, userIds?, metadata?)`. `UpdateAsync` também tem retry automático interno do Roblox quando outro servidor mexeu na chave entre leitura e escrita ("Automatically retries if another server updates the key between retrieval and write").

4. **Demais métodos** (fonte: YAML oficial de `DataStore.yaml`/`OrderedDataStore.yaml`):
   - `RemoveAsync(key)` → Tuple `(valorAntesDeRemover, keyInfo)` (ou nil se já estava deletado). Cria uma versão "tombstone"; `GetAsync` subsequente retorna nil, mas versões antigas continuam acessíveis por 30 dias via `ListVersionsAsync`/`GetVersionAsync`. Em `OrderedDataStore` a remoção é permanente (sem tombstone).
   - `IncrementAsync(key, delta, userIds, options)` → retorna o **valor já incrementado** (não a versão).
   - `GetVersionAsync(key, version)` → Tuple `(valorNaquelaVersão, keyInfo)`.
   - `ListVersionsAsync(key, sortDirection, minDate, maxDate, pageSize)` → `DataStoreVersionPages`, cada item é um `DataStoreObjectVersionInfo`.
   - `ListKeysAsync(prefix, pageSize, cursor, excludeDeleted)` → `DataStoreKeyPages`.
   - `GetSortedAsync(ascending, pagesize, minValue, maxValue)` → `DataStorePages`; cada item da página é `{key=..., value=...}`. `pagesize` default 50, máximo documentado 100 (via busca, não vi essa parte no YAML — **marcar como não 100% confirmado por fonte primária**, veio de resumo do WebFetch).

5. **Limites documentados** (fonte: `error-codes-and-limits.md` oficial, via raw GitHub):
   - Nome do data store, nome da chave (`key`) e `scope`: **máximo 50 caracteres cada**.
   - Valor (dado serializado): **máximo 4.194.304 bytes (4 MiB)** por chave.
   - Metadata: valor de cada atributo até 250 caracteres; total de metadata combinado até 300 caracteres.
   - Tipos permitidos: o valor é serializado (JSON internamente); tabelas com chave mista (string+número) e valores não serializáveis (função, `Instance`, `thread`, `NaN`, `inf`) **não são suportados** e causam erro (mensagem de erro exata **NÃO CONFIRMADA** por fonte primária — DevForum menciona "Serialized value converted byte size exceeds max size" mas não achei a mensagem exata para tipo inválido / NaN / função na doc oficial).

6. **Throttling/budget** (fonte: `error-codes-and-limits.md` oficial):
   - `Enum.DataStoreRequestType` usado por `GetRequestBudgetForRequestType`. Itens confirmados no dump/doc: `GetAsync`, `SetIncrementAsync`, `UpdateAsync`, `GetSortedAsync`, `SetIncrementSortedAsync`, `OnUpdate`, além dos agregados `ListAsync`, `GetVersionAsync`, `RemoveVersionAsync`, `StandardRead/Write/List/Remove`, `OrderedRead/Write/List/Remove`.
   - Fórmulas por minuto documentadas na página oficial (por servidor, dependendo do número de jogadores no servidor — **os dois `WebFetch` da mesma página oficial retornaram números ligeiramente diferentes entre si**, então marco os números específicos como **NÃO TOTALMENTE CONFIRMADO** — recomendo ler o Markdown bruto na íntegra antes de hardcodar constantes na simulação. Padrão geral confirmado: `baseLimit + perPlayerLimit × numPlayers`, crescendo com jogadores no servidor, com "Get"/"Read" tendo o maior multiplicador, "List" o menor.
   - Ao estourar o budget: doc afirma existência de uma **fila de throttling com limite de ~30 requisições**; ao estourar a fila, a chamada falha com **erro** (códigos na faixa 301-306 mencionados em fontes secundárias — não vi essa faixa exata no Markdown oficial, **NÃO CONFIRMADO** por fonte primária direta, apenas por resumo). Não é uma fila infinita nem um simples warning — é falha reportada ao script (pcall captura um erro).
   - `SetRateLimitForRequestType` (confirmado no dump E no YAML oficial) permite o desenvolvedor sobrescrever a fórmula `baseLimit + perPlayerLimit * numPlayers` por tipo de requisição — exceto para `UpdateAsync` e `OnUpdate`, que a doc diz não serem configuráveis.

7. **`DataStoreService.AutomaticRetry`** — existe no dump (`Property`, `bool`, `LocalUserSecurity`). Descrição oficial completa **não encontrada** na doc atual (não achei um YAML/página com texto descritivo para essa property específica — pode ter sido removida da doc pública). Há um DevForum antigo ("Datastores: Automatic Retry", 2018) que descreve a feature original. Um comentário de usuário (DevForum, não oficial) afirma que hoje "DataStores não respeitam mais essa property" — **NÃO CONFIRMADO por fonte primária**, tratar como suspeita a validar antes de implementar comportamento condicionado a essa flag.

8. **Erro em Studio sem "Enable Studio Access to API Services"**: mensagem exata **NÃO TOTALMENTE CONFIRMADA por fonte primária/oficial** (não é documentada com string literal em `create.roblox.com`). Evidência forte de DevForum (relatos de usuários, citando o console real):
   - Variante mais antiga/comum: contém o texto **"403"** e "Cannot write to DataStore from studio if API access is not enabled" (citada em múltiplos threads de DevForum e Scripting Helpers).
   - Variante mais nova observada por usuários: `"DataStoreService: StudioAccessToApisNotAllowed: Studio access to APIs is not allowed. API: GetAsync, Data Store: Cash"` (thread DevForum de 2024).
   - **Fato relevante confirmado no código-fonte do ProfileStore** (ver seção C): o próprio ProfileStore detecta essa condição fazendo `pcall` em um `SetAsync` de sondagem e checando se a mensagem de erro contém a **substring `"403"`** — ou seja, a lib real depende de string matching frágil, não de um código de erro estruturado. Isso é um dado concreto (comportamento real de uma lib de produção), mesmo que a string completa não esteja 100% cravada.
   - Ponto em que é lançado: na primeira chamada **Async** (ex.: `GetAsync`/`SetAsync`), não em `GetDataStore` — `GetDataStore` nunca falha por causa dessa configuração (confirma isso o próprio dump: `GetDataStore` não tem `Yields`, é síncrono e só constrói o objeto; quem yielda e pode falhar são os métodos `*Async`).

9. **Jogo não publicado / servidor local**: mesma família de erro, mas com texto diferente. Evidência (DevForum, não oficial, mas citada por múltiplos threads independentes de forma consistente): mensagem contendo **"must publish"** (ex.: "You must publish this place to the web to access DataStore..."). Confirmado indiretamente pelo ProfileStore, que faz `string.find(message, "must publish", 1, true)` no mesmo `pcall` de sondagem — ou seja, a lib trata "Studio sem API access" e "jogo não publicado" como duas substrings diferentes a checar na mesma mensagem de erro. **String literal exata: NÃO CONFIRMADA por fonte primária.**

10. **`GetDataStore(name, scope, options)` com nome inválido/vazio/grande**: doc oficial não detalha o comportamento de erro exatamente (mensagem específica **NÃO CONFIRMADA**), mas os limites de 50 caracteres (item 5) implicam erro de validação para nome/escopo acima disso. **Identidade**: confirmado pela doc oficial — "subsequent calls return the same object" (`DataStoreService.yaml`, `GetDataStore`) — ou seja, duas chamadas com mesmo `name`+`scope`+`options` retornam a **MESMA instância** (memoizado internamente pelo Roblox), não instâncias novas. Isso é uma decisão de arquitetura relevante: o LuauBench precisa memoizar por `(name, scope)` também.

---

## C) ProfileStore — código-fonte real (`MadStudioRoblox/ProfileStore`, branch `main`, arquivo único `ProfileStore.luau`, 2242 linhas)

Baixado de `https://raw.githubusercontent.com/MadStudioRoblox/ProfileStore/main/ProfileStore.luau` (é o sucessor oficial recomendado do antigo `ProfileService`, mesmo autor/organização "MadStudioRoblox"; não usei o ProfileService legado).

Métodos de DataStore chamados **de verdade** no código (grep + leitura de trechos):

- `DataStoreService:GetDataStore(store_name, nil, options)` — `options` é um `DataStoreOptions` real (`Instance.new("DataStoreOptions")`) com `options:SetExperimentalFeatures({v2 = true})` chamado sempre (linha 1305-1306, 1319, 1328). **Decisivo:** o LuauBench precisa simular `DataStoreOptions:SetExperimentalFeatures` aceitando esse formato de tabela sem erro, mesmo que não faça nada de fato (opt-in para "v2 API" do Roblox).
- `profile_store.data_store:GetAsync(profile_key)` — usado só para leitura "view mode" (sem lock de sessão).
- `profile_store.data_store:GetVersionAsync(profile_key, version)` — idem, para ler versão específica.
- `profile_store.data_store:UpdateAsync(profile_key, transform_function)` — **é o ÚNICO método usado para toda escrita/leitura transacional real** (load de sessão E save). ProfileStore **nunca chama `SetAsync` para salvar perfil de jogador** (só chama `SetAsync` uma vez, como sondagem de saúde da conexão — ver abaixo). Isso é decisivo: a simulação de `UpdateAsync` precisa estar impecável; `SetAsync` sozinho não é o caminho crítico do caso de uso central do projeto.
- `self.data_store:RemoveAsync(profile_key)` — usado em `ProfileStore:WipeProfileAsync`.
- `self.profile_store.data_store:ListVersionsAsync(self.profile_key, self.sort_direction, self.min_date, self.max_date)` — usado em `ProfileVersionQuery` (sem `pageSize`, usa default).
- `self.query_pages:GetCurrentPage()`, `self.query_pages.IsFinished`, `self.query_pages:AdvanceToNextPageAsync()` — uso de `Pages`/`DataStoreVersionPages` exatamente conforme a API do dump.
- **Sondagem de saúde/permissão** (linha 2078-2081): `DataStoreService:GetDataStore("____PS"):SetAsync("____PS", os.time())` dentro de um `pcall`, só em `IsStudio == true`. É o ÚNICO uso de `SetAsync` em todo o arquivo. A partir do resultado, decide o estado global `DataStoreState: "NotReady"|"NoInternet"|"NoAccess"|"Access"`, checando substrings `"ConnectFail"`, `"403"`, `"must publish"` na mensagem de erro (linhas 2083-2098).
- **NÃO usa** `GetRequestBudgetForRequestType` em nenhum lugar do arquivo (confirmado por grep — zero ocorrências). ProfileStore **não faz introspecção de budget**; trata todo erro de forma genérica com retry.
- **NÃO usa** `IncrementAsync`, `BatchGetAsync`, `ListKeysAsync`, `GetSortedAsync`, `OnUpdate`, `GetVersionAtTimeAsync`, `RemoveVersionAsync`, `ListDataStoresAsync` — fora do escopo do que a lib precisa.
- **Metadata**: não usa `DataStoreSetOptions`/`SetMetadata()` — em vez disso, devolve o metadata como **3º valor de retorno da própria `transformFunction`** passada para `UpdateAsync` (`return latest_data, latest_data.UserIds, latest_data.RobloxMetaData` — linha 588), aproveitando o contrato nativo de `UpdateAsync(transformFunction) -> (value, userIds?, metadata?)`. Confirma que a simulação de `UpdateAsync` precisa aceitar e repassar esse 3º valor de retorno da transform.
- `transform_function` interna do ProfileStore (linha 521) só declara `function(latest_data)` — um único parâmetro — mas a chamada real do Roblox (`profile_store.data_store:UpdateAsync(profile_key, transform_function)`, linha 625) invoca essa função recebendo `(oldValue, keyInfo)` do backend real; ProfileStore simplesmente ignora o 2º argumento. **Implicação para a simulação:** o LuauBench precisa passar `keyInfo` como 2º argumento para a transform mesmo que a lib não o use — outros consumidores de `UpdateAsync` podem depender dele.
- `game:BindToClose(function() ... end)` — usado (linhas 2199, 2208) para salvar todos os perfis ativos no encerramento do servidor, com um loop `while ... do task.wait() end` esperando jobs de save/load terminarem. **Decisivo:** `game:BindToClose` precisa existir e realmente atrasar o encerramento simulado do processo até o callback retornar, senão o teste de "salva no shutdown" do ProfileStore nunca passa no LuauBench.
- `RunService.Heartbeat:Connect(...)` — usado para o loop de autosave (a cada `AUTO_SAVE_PERIOD = 300` segundos, dividido entre os perfis ativos) e para a máquina de "critical state" (`CRITICAL_STATE_ERROR_COUNT = 5` erros em `CRITICAL_STATE_ERROR_EXPIRE = 120` segundos aciona `IsCriticalState`). Depende de `Heartbeat` disparando em intervalos "reais" de tempo de jogo — `os.clock()` é usado para medir os intervalos, não um contador de frames.
- **Retry/backoff**: usa `task.wait(exp_backoff)` com `exp_backoff` iniciando em `1` e dobrando a cada falha (`exp_backoff = math.min(20, exp_backoff * 2)`, ou `math.min(8, ...)` durante shutdown) — backoff exponencial simples baseado em `task.wait`, não em `os.clock`/sleep bloqueante. **Decisivo para o `runtime`:** `task.wait(n)` precisa respeitar aproximadamente o tempo pedido via scheduler (não pode ser instantâneo nem bloqueante de SO), porque a lógica de retry do ProfileStore depende de tempo real passando entre tentativas.
- Constantes de timing relevantes para cenários de teste: `AUTO_SAVE_PERIOD = 300`, `LOAD_REPEAT_PERIOD = 10`, `FIRST_LOAD_REPEAT = 5`, `START_SESSION_TIMEOUT = 120`, `CRITICAL_STATE_ERROR_COUNT = 5`, `CRITICAL_STATE_ERROR_EXPIRE = 120`, `CRITICAL_STATE_EXPIRE = 120`.

### Resumo do que a simulação de DataStoreService PRECISA acertar para o ProfileStore funcionar no LuauBench
1. `GetDataStore` memoizado por `(name, scope)`, síncrono, nunca lança erro de permissão.
2. `UpdateAsync` — assinatura completa `(oldValue, keyInfo) -> (newValue, userIds?, metadata?)`, aborta escrita se `newValue == nil`, não pode yieldar (ou o LuauBench documenta que não valida isso e diverge), retorna `(newValue, newKeyInfo)`.
3. `SetAsync` só precisa funcionar minimamente (é usado 1x como sondagem — mas outros scripts do usuário podem depender dele para casos fora do ProfileStore).
4. `GetAsync`, `RemoveAsync`, `ListVersionsAsync` + `Pages`/`DataStoreVersionPages`/`GetCurrentPage`/`IsFinished`/`AdvanceToNextPageAsync`.
5. `DataStoreOptions:SetExperimentalFeatures` precisa aceitar chamada sem erro.
6. `game:BindToClose` realmente atrasando o "fim" do processo simulado.
7. `RunService.Heartbeat` disparando em cadência de tempo real (não por frame de render).
8. `task.wait(n)` com decorrer de tempo real aproximado (scheduler, não travar a thread do SO).
9. Mensagem de erro de "API access desabilitado"/"não publicado" **não precisa ser byte-a-byte idêntica ao Roblox real** para o ProfileStore funcionar (ele só testa substrings `"403"`/`"must publish"`/`"ConnectFail"`) — mas se o LuauBench quiser simular fielmente o cenário "sem API access", a mensagem simulada deveria conter uma dessas substrings para não confundir uma lib real rodando por cima.

---

## Itens marcados NÃO CONFIRMADO (não inventar, resolver antes de codificar comportamento dependente deles)

- Fórmula exata do budget (`baseLimit + perPlayerLimit × numPlayers`) por tipo de requisição — dois fetches da mesma página oficial retornaram números diferentes entre si. **Ação recomendada:** ler o Markdown bruto de `https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/cloud-services/data-stores/error-codes-and-limits.md` diretamente (linha a linha, não resumido por IA) antes de hardcodar qualquer constante numérica na simulação.
- Faixa de códigos de erro (301-306, 101-107) — só vista em fontes secundárias, não confirmada no Markdown oficial diretamente.
- String exata da mensagem de erro para "Studio sem API access" e "jogo não publicado" — corroborada por múltiplos DevForum + pelo comportamento do próprio ProfileStore (checagem de substring), mas sem confirmação em fonte primária com a string completa/atual.
- Se `AutomaticRetry` ainda tem efeito real hoje, ou é vestigial — não encontrei descrição atual na doc oficial.
- Tipo de erro exato para valor não serializável (`NaN`, função, `Instance`, tabela com chave mista) em `SetAsync`/`UpdateAsync` — comportamento (erro) é conhecido, mensagem exata não.
- Página máxima documentada de `GetSortedAsync` (mencionado "100" só por resumo de fetch, não visto na fonte primária diretamente).
