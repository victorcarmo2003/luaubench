# Pesquisa — 6 pendências da leva 2 de `services` (task-services-028)

Fecha a lista "Pendências para o `pesquisador`" de `.claude/agents-memory/arquiteto-services-2026-09-05.md`, seção final (linhas 1388-1396). Nenhum item bloqueia trabalho já feito; todos existem para `revisor-services` aprovar a leva com conhecimento de causa.

Método: fonte primária sempre que existir (Markdown/YAML brutos do repositório `Roblox/creator-docs`, buscados via `curl`/`gh api` — nunca via ferramenta de fetch com resumo por IA, para evitar a própria causa da divergência relatada). Onde só há evidência de comunidade (DevForum), digo isso explicitamente e cito a thread. Nada abaixo foi preenchido por inferência sem marcação.

---

## 1. Fórmula numérica do budget de DataStore por tipo de requisição

**Fonte primária, lida linha a linha**: `error-codes-and-limits.md` baixado por `curl` direto (não por ferramenta de resumo) em 2026-09-05, commit `main` do momento (arquivo alterado pela última vez em `23280f5c`, 2026-08-11, confirmado por `gh api repos/Roblox/creator-docs/commits`). 1005 linhas, sha256 conferido localmente.

**Achado-chave: a divergência das duas pesquisas anteriores quase certamente vem de o documento ter DUAS tabelas de limite diferentes, fáceis de confundir.**

### Tabela A — "Experience Limits" (linhas 484-559): por EXPERIÊNCIA inteira, todos os servidores somados

| Tipo (Standard) | Fórmula (requests/min) |
|---|---|
| Read | `300 + concurrentUsers × 40` |
| Write | `300 + concurrentUsers × 20` |
| List | `300 + concurrentUsers × 2` |
| Remove | `300 + concurrentUsers × 40` |

(Ordered data stores usa os mesmos 4 valores.) `concurrentUsers` aqui é o total de jogadores conectados na experiência inteira (todos os servidores), e o texto confirma: "Game server and Open Cloud **share** a budget."

### Tabela B — "Server limits" (linhas 795-886): por SERVIDOR individual — **esta é a que importa**

O próprio documento amarra explicitamente esta tabela a `GetRequestBudgetForRequestType`/`SetRateLimitForRequestType` (linha 797: *"Each server has a configurable rate limit for each request type, based on the number of players in that server. [...] Use `GetRequestBudgetForRequestType()` to confirm the number of data store requests that the current server can make at any given time."*).

**Standard data stores:**

| `DataStoreRequestType` | Requests/min |
|---|---|
| `StandardRead` | `60 + numPlayers × 40` |
| `StandardWrite` | `60 + numPlayers × 40` |
| `StandardList` | `5 + numPlayers × 2` |
| `StandardRemove` | `60 + numPlayers × 40` |
| `RemoveVersionAsync` (Deprecated) | `5 + numPlayers × 2` |

**Ordered data stores:**

| `DataStoreRequestType` | Requests/min |
|---|---|
| `OrderedRead` | `60 + numPlayers × 40` |
| `OrderedWrite` | `30 + numPlayers × 5` |
| `OrderedList` | `5 + numPlayers × 2` |
| `OrderedRemove` | `30 + numPlayers × 5` |

**Conclusão para a decisão já tomada (L2.1.4):** o desenho do arquiteto já estava certo na forma (`baseLimit + perPlayerLimit × numPlayers`, zero jogadores no LuauBench ⇒ orçamento mínimo, decisão de não simular mantida) — só faltavam os números exatos, que agora estão acima caso um dia exista modo de throttle opt-in. **Não uso os números da Tabela A por engano**: é a armadilha mais provável para quem lê rápido, porque as duas tabelas têm formato idêntico e aparecem na mesma página, com `concurrentUsers` (tabela A) vs `numPlayers` (tabela B) sendo a única distinção textual.

Bônus confirmado na mesma leitura: throttle esgotado cai numa fila de 30 requisições por tipo (`Set`/`Ordered set`/`Get`/`Ordered get`), erro 301-306 quando a fila estoura; throughput por chave é `25 MB/min` (leitura) e `4 MB/min` (escrita) nos últimos 60s; storage é `500 MB + 1 MB × lifetime user count`. Nenhum destes é usado na decisão atual, ficam registrados caso sejam úteis depois.

**Fonte:** https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/cloud-services/data-stores/error-codes-and-limits.md (fetch direto por `curl`, 2026-09-05).

---

## 2. Mensagem de erro para valor não serializável em `SetAsync`/`UpdateAsync`

### Achado que corrige uma premissa já codificada: **NaN e infinito NÃO são recusados pelo motor real — são aceitos**

A documentação oficial de Open Cloud (`https://create.roblox.com/docs/cloud/guides/data-stores`) afirma, sobre o formato de resposta de Open Cloud: *"Data store entries written through the Engine API can contain non-finite Luau numbers. Because JSON can't represent these numbers, Open Cloud responses replace them with tagged JSON objects in the returned entry value"* — com os três casos documentados: `inf` → `{"m": null, "t": "numeric", "v": "inf"}`, `-inf` → `{"m": null, "t": "numeric", "v": "-inf"}`, `nan` → `{"m": null, "t": "numeric", "v": "nan"}`.

Isso significa: **`SetAsync`/`UpdateAsync` chamados pela Engine API (o caso do LuauBench) aceitam `NaN`/`inf`/`-inf` sem erro.** Só o Open Cloud (JSON) precisa de uma representação especial porque JSON não tem `NaN`/`Infinity`. **A tabela L2.1.3 do desenho ("Valor não serializável: chave mista, função, Instance, thread, NaN, inf → Recusado com erro") está incorreta para NaN e inf especificamente — isso não veio de leitura do `error-codes-and-limits.md` (que não menciona NaN/inf em lugar nenhum, confirmado por grep no arquivo bruto), foi inferência por analogia com os outros tipos não serializáveis.** Função, `thread`, `Instance` continuam corretamente recusados (ver abaixo). Chave mista é um erro à parte, não do mesmo eixo (ver abaixo).

**Fonte:** https://create.roblox.com/docs/cloud/guides/data-stores (doc oficial Open Cloud, seção sobre valores numéricos não-finitos).

### Família de erro confirmada por evidência empírica (comunidade, não doc oficial) para os tipos que continuam recusados

A tabela oficial de códigos de erro (`error-codes-and-limits.md`, linhas 22-45) dá só o **template**, sem a substituição de `X`:
- `103` `ValueNotAllowed` → `"Can't allow **X** in DataStore."`
- `104` `CantStoreValue` → `"Can't store **X** in DataStore."`

A substituição real de `X` foi confirmada por múltiplas threads independentes do DevForum, quotadas ao vivo pelos próprios autores (não paráfrase de IA — refetchei cada thread pedindo a citação literal):

| Valor / situação | String observada | Thread |
|---|---|---|
| `Instance` como valor de topo | `"104: Cannot store Instance in data store. Data stores can only accept valid UTF-8 characters"` | https://devforum.roblox.com/t/cannot-store-instance-in-data-store-data-stores-can-only-accept-valid-utf-8-characters/1916905 |
| `CFrame` (nome antigo `CoordinateFrame`) como valor de topo | `"Cannot store CoordinateFrame in data store."` | https://devforum.roblox.com/t/datastores-cannot-store-instance-when-not-attempting-to-store-an-instance/1641868 |
| `function`/`Instance` **aninhado** dentro de array | `"104: Cannot store Array in DataStore"` | https://devforum.roblox.com/t/datastores-passing-invalid-table-values-should-produce-more-descriptive-errors/176368 (autor `buildthomas`) |
| `function`/`Instance` **aninhado** dentro de dicionário | `"104: Cannot store Dictionary in DataStore"` | idem |
| `double`/decimal em `OrderedDataStore` | `"103: double is not allowed in data stores."` | https://devforum.roblox.com/t/103-double-is-not-allowed-in-data-stores/1167054 |
| `Array` (tabela numérica) em `OrderedDataStore` | `"103: Array is not allowed in data stores"` | https://devforum.roblox.com/t/103-array-is-not-allowed-in-data-stores-solved/494978 |
| `Dictionary` em `OrderedDataStore` | `"103: Dictionary is not allowed in data stores."` | https://devforum.roblox.com/t/103-dictionary-is-not-allowed-in-data-stores/2131938 |

**Leitura importante para quem for escrever a mensagem aproximada do LuauBench**: o próprio erro do motor real, quando o valor inválido está **aninhado dentro de uma tabela**, nomeia o **contêiner** ("Array"/"Dictionary"), não o valor culpado de verdade (função/Instance) — é exatamente a reclamação que motivou a thread de feature request. Reproduzir isso fielmente significa que a mensagem do LuauBench para `SetAsync(key, {minhaFuncao})` deveria nomear `"Array"`, não `"function"`.

**Tabela com chave mista** (ex.: `{1,2,3, nome="x"}`) gera uma mensagem **fora da família 103/104**, sem código numérico visível nas citações encontradas: `"Cannot convert mixed or non-array tables: keys must be strings"` (variante próxima também vista: `"Cannot convert non-array or mixed tables: keys must be strings"`) — ambas quotadas na mesma thread de feature request acima, por dois autores diferentes (`buildthomas` e `SteadyOn`). **NÃO CONFIRMADO**: se essa mensagem é idêntica hoje (a thread é de 2016) — nenhuma confirmação recente encontrada.

**`function`/`thread` como valor de TOPO (não aninhado) direto em `SetAsync`**: **NÃO CONFIRMADO** — não encontrei citação ao vivo de alguém passando uma função pura como valor de `SetAsync` (só aninhada em tabela). Por analogia com o padrão `103: <tipo> is not allowed in data stores.` confirmado para `double`/`Array`/`Dictionary`, a forma esperada seria `"103: function is not allowed in data stores."`, mas isso é extrapolação minha, não evidência — não usar como confirmado.

---

## 3. `RegisterCollisionGroup` com nome já registrado, e restrição cliente/servidor

**Fonte primária**: YAML bruto de referência oficial, baixado direto do repositório `Roblox/creator-docs` (`content/en-us/reference/engine/classes/{PhysicsService,WorldRoot}.yaml`) — é o texto que alimenta `create.roblox.com/docs/reference/engine/classes/...`, mas em texto puro, sem o JS que esconde a descrição atrás de "Show details" (que impediu o WebFetch normal de ler a página renderizada).

### Nome duplicado: **NÃO CONFIRMADO pela doc oficial — e a ausência é o próprio achado**

A descrição oficial completa de `RegisterCollisionGroup` (idêntica em `PhysicsService.yaml` e `WorldRoot.yaml`) é:
> "Registers a new collision group [in this world] with the given name. The name cannot be `"Default"`."

Isso é **tudo**. Não há frase "throws a runtime error in the following circumstances" como existe para `UnregisterCollisionGroup` e `RenameCollisionGroup` (ver abaixo) — ou seja, a documentação **não declara** o que acontece com nome duplicado, nem para um lado nem para outro. Evidência fraca de comunidade, na direção de **erra** (não idempotente): um guia de terceiros (`gamertagmythras.com/blog/roblox/roblox-collision-physics-guide`) recomenda "Wrap it in a check or a `pcall` if a script might run twice" — só faz sentido como recomendação se a segunda chamada puder falhar. **Não é uma citação de erro ao vivo, é uma recomendação defensiva de um blog não-oficial.** Mantenho `NÃO CONFIRMADO`, mas registro que a evidência disponível pende para "erra", não para "idempotente" — o oposto da escolha atual do desenho (L2.5.1: "registrar nome duplicado não erra (idempotente)"). Recomendo ao `revisor-services` reabrir esse ponto especificamente, não como "confirmado", mas como "premissa sem base documental e com sinal fraco na direção contrária".

### Restrição cliente/servidor: **parcialmente confirmada pela doc oficial — e é desigual entre os 8 métodos**

Confirmado nos dois YAMLs (`PhysicsService.yaml` e `WorldRoot.yaml`, texto idêntico nas duas classes):

| Método | Doc diz explicitamente "erra se chamado do cliente"? |
|---|---|
| `UnregisterCollisionGroup` | **Sim** — "If the reserved name `"Default"` is provided **or** if the method is called from a client, it will throw an error." |
| `RenameCollisionGroup` | **Sim** — "This method will throw a runtime error in the following circumstances: [...] The method is called from a client." |
| `RegisterCollisionGroup` | **Não menciona** (só proíbe o nome `"Default"`) |
| `CollisionGroupSetCollidable` | **Não menciona** (só "throws an error if either of the groups is unregistered") |
| `IsCollisionGroupRegistered`, `GetRegisteredCollisionGroups`, `GetMaxCollisionGroups`, `CollisionGroupsAreCollidable` | Não menciona (métodos de leitura) |

Evidência de comunidade (não oficial, DevForum + um agregador de terceiros `robloxapi.github.io`) diz que a família inteira de mutação (incluindo `RegisterCollisionGroup`/`CollisionGroupSetCollidable`) também é server-only, com o texto de erro citado ao vivo **"This API can only be used on the server!"** — mas a citação ao vivo mais direta que encontrei é para o método **antigo e depreciado** `CreateCollisionGroup`, não para `RegisterCollisionGroup` (thread: https://devforum.roblox.com/t/how-would-i-create-a-collision-group-on-the-client/1249986). Um resumo de busca (não uma citação direta de thread) afirma o mesmo texto também para `RegisterCollisionGroup`/`CollisionGroupSetCollidable`, mas não consegui reproduzir isso com uma citação verbatim de uma thread específica para esses dois métodos.

**Conclusão**: `UnregisterCollisionGroup`/`RenameCollisionGroup` são **oficialmente confirmados** como server-only, com erro ao chamar do cliente. `RegisterCollisionGroup`/`CollisionGroupSetCollidable` têm evidência de comunidade forte mas não uma citação oficial ou verbatim direta — marco como **NÃO CONFIRMADO OFICIALMENTE, com sinal forte de comunidade na direção "também é server-only"**. O dump (`Security: None`, sem tag formal de client/server) não ajuda a decidir isso — a restrição parece ser um `IsServer()` checado no código C++, não um eixo do dump.

**Confirmado de bônus**: `GetMaxCollisionGroups() == 32` e o grupo `"Default"` pré-registrado que "cannot be renamed or deleted" já estavam corretos na doc oficial de `collisions.md`, batendo com o que o desenho já assumia.

**Fontes**: `PhysicsService.yaml` e `WorldRoot.yaml` (raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/), lidos linha a linha; https://devforum.roblox.com/t/how-would-i-create-a-collision-group-on-the-client/1249986; https://gamertagmythras.com/blog/roblox/roblox-collision-physics-guide.

---

## 4. `Lighting.ClockTime` fora de `[0, 24)` e zero-padding de `TimeOfDay`

**Fonte primária**: `Lighting.yaml` bruto (mesmo repositório).

### `ClockTime` fora de faixa: **CONFIRMADO POR EVIDÊNCIA DE COMUNIDADE — não é wrap, é reset/clamp para 0** (contradiz a implementação já commitada em `task-services-024`)

A doc oficial não descreve o comportamento de escrita direta em `ClockTime` fora de `[0,24)` (só descreve o que a propriedade *é*). Duas fontes de comunidade, anos e contextos diferentes, concordam no mesmo comportamento:

- Thread de feature request "ClockTime above 24 should apply a modulo of 24" (2018, https://devforum.roblox.com/t/clocktime-above-24-should-apply-a-modulo-of-24/179818): *"When you set ClockTime to 24 or above, the property will automatically reset back to 0."* — o próprio título do pedido ("deveria aplicar módulo") prova que o comportamento da época **não era módulo/wrap**.
- Thread mais recente sobre tween com valor negativo (https://devforum.roblox.com/t/how-to-tween-lightingclocktime-that-is-a-negative-number/845960): *"I've tried it, no you cannot set it to negative even with a loop. It will just bring it back to 0."*

As duas apontam para **reset a 0** (não wrap, não clamp para o limite mais próximo, não erro) tanto para valores `< 0` quanto `>= 24`. **Isto diverge da decisão já implementada em `task-services-024`** (arquiteto registrou "wrap... comentado como aproximação de boa-fé" para escrita direta em `ClockTime`). Sinalizo para `revisor-services`: a fidelidade real parece ser "reset a 0", não "wrap" — mas ambas as fontes são comunidade (não doc oficial, não testado por mim ao vivo), e a mais antiga tem quase 8 anos (o comportamento pode ter mudado desde então, embora a segunda thread, mais recente, relate o mesmo). Não decido a correção sozinho — só reporto a divergência com fonte.

**Contraste confirmado oficialmente**: `SetMinutesAfterMidnight` **wrapeia mesmo**, isso é doc oficial e bate com o que já estava assumido: *"It also allows values greater than 24 hours to be given that correspond to times in the next day."* (`Lighting.yaml`, descrição de `SetMinutesAfterMidnight`). Ou seja, há uma real assimetria documentada: `SetMinutesAfterMidnight` avança para o dia seguinte (wrap), enquanto escrever `ClockTime`/`TimeOfDay` diretamente parece resetar a 0 (evidência de comunidade). As duas vias share o mesmo estado interno segundo a doc, então essa assimetria é estranha mas é o que as fontes dizem — registrado, não resolvido aqui.

### Zero-padding de `TimeOfDay` na leitura: **NÃO CONFIRMADO — evidência de comunidade contraditória entre si**

- A favor de **sem zero-padding** na hora (ex. `"8:00:00"`): múltiplos resumos de busca mencionam esse formato em uso, mas nenhum vem de uma citação verbatim de uma thread específica que eu tenha conseguido reabrir e confirmar — são inferências do buscador sobre o conteúdo agregado das threads, não uma citação isolada e verificável.
- A favor de **com zero-padding** (ex. `"05:00:00"`): uma citação de código real, de um usuário nomeado, funciona apenas se a hora for zero-padded — `Local Hours = tonumber(string.sub(Lighting.TimeOfDay, 1, 2)) -- Gets the hours, turns 05 --> 5` (https://devforum.roblox.com/t/trying-to-get-ampm-based-on-timeofday/263322). `string.sub(str, 1, 2)` só extrai a hora corretamente se ela sempre ocupar 2 caracteres — para uma hora de um dígito sem padding (`"8:00:00"`), isso pegaria `"8:"`, que `tonumber` não converte para `8` de forma limpa.

**Concluo NÃO CONFIRMADO, com a balança pendendo para "com zero-padding"** (evidência de código funcional citado de uma pessoa nomeada > resumo de busca sem citação isolável). A escolha já implementada em `task-services-024` (zero-padding) é a que tem, na minha leitura, o sinal mais forte a favor — mas não é uma confirmação, é uma leitura de evidência imperfeita. Recomendo manter como está e não reverter sem teste ao vivo em Studio.

**Fontes**: `Lighting.yaml` (raw, oficial); https://devforum.roblox.com/t/clocktime-above-24-should-apply-a-modulo-of-24/179818; https://devforum.roblox.com/t/how-to-tween-lightingclocktime-that-is-a-negative-number/845960; https://devforum.roblox.com/t/trying-to-get-ampm-based-on-timeofday/263322.

---

## 5. Texto verbatim: `HttpService` com HTTP desabilitado, e `SoundService:PlayLocalSound` no servidor

### `HttpService` com HTTP desabilitado: **NÃO CONFIRMADO — nenhuma citação verbatim encontrada**

Nem `HttpService.yaml` (oficial) nem `content/en-us/cloud-services/http-service.md` (oficial, lido em raw) trazem o texto exato do erro — ambos só descrevem *que* os três métodos "aren't enabled by default" e *como* habilitar, nunca a string de erro. Busquei mais de 6 variantes de frase no DevForum (incluindo o texto de título de threads que soa como citação, ex. "HTTP requests are not enabled error (but they are)") e não consegui abrir nenhuma que reproduzisse a string entre aspas, verbatim, de um post real. **Não uso a paráfrase comum ("Http requests are not enabled. Enable them in the game settings...") porque não a vi citada ao vivo em lugar nenhum** — é conhecimento ambiente/genérico, exatamente o tipo de coisa que a regra do projeto probe preencher sem evidência. Fica `NÃO CONFIRMADO`; a mensagem hoje adotada no LuauBench deve continuar marcada como aproximação de boa-fé, não como string real.

### `SoundService:PlayLocalSound` no servidor: **CONFIRMADO por citação ao vivo — muda a decisão de B.5.5**

String exata, confirmada por duas fontes independentes que reproduzem a mesma citação de um autor nomeado (`Megaificent`) em thread do DevForum:

> **"SoundService:PlayLocalSound only works on a client."**

**Fonte**: https://devforum.roblox.com/t/playlocalsound-not-working-when-ontouched-event-is-triggered/562930 (citação reproduzida ao vivo, atribuída ao autor original do post).

**Isto muda o que o arquiteto registrou em L2.5.3**: a decisão documentada foi "não recebe `RejectingSignal`-equivalente: a pesquisa só achou relato de comunidade, sem string verbatim" — **agora existe uma string verbatim, citada de uma thread específica com autoria**. Não é doc oficial (a doc oficial de `SoundService.yaml` não menciona nenhuma restrição de cliente/servidor para `PlayLocalSound`), mas é o mesmo padrão de evidência (DevForum com citação atribuída) que o projeto já aceitou para outras aproximações de boa-fé no restante do desenho (ex.: a evidência de `MessagingService` ecoar localmente, em L2.3.1, também vem só de DevForum). Devolvo isso para o `revisor-services`/`arquiteto` decidirem se essa nova evidência muda o veredito de "regra B.5.5 não se aplica" — não decido isso sozinho, só reporto o fato novo.

---

## 6. `GetGlobalDataStore()`: `ClassName` real — `"GlobalDataStore"` ou `"DataStore"`?

**CONFIRMADO: `"DataStore"`, e o dump fixado do projeto já está certo.**

Duas fontes concordam:

1. **O próprio dump fixado do projeto** (`.cache/api-dump/28360dea4b90b35dc3fe9f829baae64fb6c50e75.json`, lido diretamente): `DataStoreService.GetGlobalDataStore` tem `ReturnType: { Category: "Class", Name: "DataStore" }`.
2. **Histórico de versão do dump**, via `robloxapi.github.io/ref/class/DataStoreService.html` (projeto de terceiros que rastreia o histórico de todas as versões do dump oficial, changelog por versão): o tipo de retorno de `GetGlobalDataStore` mudou **duas vezes**:
   - `Instance` → `GlobalDataStore` na versão `v0.483.0.424775` (2021-06-14);
   - `GlobalDataStore` → **`DataStore`** na versão `v0.638.0.6380612` (2024-08-13).

Como o dump fixado do LuauBench é da versão `0.737.0.7371584` — bem posterior a `0.638` — o valor correto e atual é **`DataStore`**, confirmando que **não é uma pegadinha tipo Enum Name/Value**: é uma mudança real de tipo de retorno que o próprio Roblox fez em 2024, e o dump fixado já reflete o estado pós-mudança corretamente. A decisão "seguir o dump" no desenho (L2.1.7) está certa e não precisa de ressalva adicional.

**Fontes**: dump local `.cache/api-dump/28360dea....json` (`DataStoreService.GetGlobalDataStore.ReturnType`); https://robloxapi.github.io/ref/class/DataStoreService.html (histórico de versão do `ReturnType`).

---

## Resumo para quem só quer a tabela

| # | Pergunta | Status |
|---|---|---|
| 1 | Fórmula de budget | **Confirmado.** Duas tabelas distintas no doc — a que importa (server, `GetRequestBudgetForRequestType`) é `numPlayers`-based: Read/Write/Remove Standard e Read Ordered = `60+40n`; List Standard/Ordered e RemoveVersion = `5+2n`; Write/Remove Ordered = `30+5n`. Decisão de não simular mantida. |
| 2 | Mensagem de valor não serializável | **Parcial.** Família 103/104 confirmada por citação viva para `Array`/`Dictionary`/`Instance`/`CFrame`/`double`. **NaN/inf NÃO são recusados de verdade — correção necessária na tabela L2.1.3.** Chave mista tem mensagem própria, fora do padrão 103/104. `function`/`thread` de topo: não confirmado. |
| 3 | `RegisterCollisionGroup` duplicado / client-server | **Não confirmado** (nome duplicado — doc silencia, sinal fraco de comunidade aponta para "erra", oposto da decisão atual). Client-restrição **confirmada oficialmente só para Unregister/Rename**; Register/SetCollidable só têm sinal de comunidade. |
| 4 | `ClockTime` fora de faixa / zero-padding | **Não confirmado oficialmente.** Comunidade aponta "reset a 0" (não wrap) para ClockTime direto — diverge da implementação já commitada. Zero-padding: evidência mista, levemente a favor do que já foi implementado. |
| 5 | Erro HTTP desabilitado / `PlayLocalSound` servidor | HTTP: **não confirmado**, nenhuma citação viva encontrada. `PlayLocalSound`: **confirmado** — `"SoundService:PlayLocalSound only works on a client."`, muda a leitura de B.5.5. |
| 6 | `GetGlobalDataStore()` ClassName | **Confirmado**: `"DataStore"`, mudou de `GlobalDataStore` para `DataStore` na v0.638 (2024-08-13); dump fixado (v0.737) já reflete isso corretamente. |

## Achados que merecem atenção do `revisor-services` (fora do escopo de "responder a pergunta")

1. **NaN/inf são aceitos pelo motor real, não recusados** — a tabela de fidelidade L2.1.3 precisa de correção textual (não é código ainda, é o próprio desenho).
2. **`ClockTime` escrito fora de `[0,24)` pode ser "reset a 0" em vez de "wrap"** no motor real — a implementação de `task-services-024` já commitada usa wrap. Sinal de comunidade, não prova definitiva; decisão de reabrir ou não é do `arquiteto`/`revisor-services`.
3. **Há agora citação verbatim para o erro de `PlayLocalSound` no servidor** — reabre a pergunta de L2.5.3 sobre se B.5.5 se aplica.
4. **Nome de collision group duplicado**: sinal fraco (blog não-oficial) aponta para "erra", oposto da decisão "idempotente" já registrada — não é prova, mas é um contraponto que valia registrar.
