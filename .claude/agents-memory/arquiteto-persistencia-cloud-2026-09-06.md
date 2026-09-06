# Persistência local do "cloud" — Arquitetura

**Data:** 2026-09-06 · **Arquiteto** · Desenho completo, nenhuma linha de código escrita.

### Propósito

Estado "cloud" simulado (hoje: `DataStoreService`) sobrevive entre execuções sucessivas de `luaubench run` no mesmo projeto, enquanto a árvore de `Instance`/scripts continua sendo reconstruída do zero a cada execução.

---

## 0. Resumo executivo (leia isto antes de qualquer coisa)

Cinco decisões carregam o desenho inteiro:

1. **`services` NÃO ganha `@lune/fs`.** O contrato de injeção já registrado em 2026-09-05 (`Types.DataStorePersistence`) é o desenho certo e é mantido, com um nome mais amplo (`CloudPersistence`). O ponto único de filesystem mora em **`cli`** (`src/cli/CloudStore.luau`). Nenhuma invariante da regra 00 é violada — ver §2 para o raciocínio completo, incluindo por que `@lune/net` dentro de `HttpService.luau` **não** é precedente para isso.
2. **JSON cru NÃO é um contêiner válido para o domínio de valor que o LuauBench já aceita.** Medido empiricamente contra `@lune/serde` (Lune 0.10.5) nesta sessão: `NaN`/`inf` viram `null` **sem erro**, array esparso perde elementos **sem erro**, e tabela com chave numérica que não começa em 1 **erra no encode**. Um snapshot "JSON do valor cru" corromperia dado em silêncio — exatamente o que a invariante 2 proíbe. Por isso o desenho define um **envelope tagueado** (§4), total sobre o domínio de `Value.CheckSerializable`.
3. **Um arquivo só**, `.luaubench/cloud/datastore.json`, com nome de store e chave como *chaves de objeto JSON*, nunca como componente de caminho — path traversal impossível por construção (argumento herdado do desenho de 2026-09-05, preservado de propósito).
4. **Escrita coalescida na fronteira de tique do scheduler**, não a cada escrita. O gancho já existe e já é de `cli`: `shouldContinue` de `Scheduler:Run`. Justificado por medição (§6) — snapshot inteiro custa 1 ms a 46 ms dependendo do tamanho, e uma escrita síncrona por chamada tornaria um laço de escrita quadrático.
5. **`MessagingService` fica só em memória** (fiel: o Roblox real não tem mensagem pendente) e **`MemoryStoreService` fica fora desta leva** (a classe nem existe ainda; TTL/volátil por natureza). Ver §7 e §8.

**Gap descoberto de raspão, fora do escopo mas bloqueante para o valor da feature:** `DataModel.RunBindToCloseCallbacks` existe em `runtime` e **nunca é chamado por `cli`** (confirmado por grep em `src/cli/**`). Hoje `game:BindToClose` registra callbacks que jamais disparam. Como a gravação final do ProfileStore mora exatamente ali, a persistência entregaria menos do que promete sem isso. Tarefa própria, território `cli`, paralela a tudo — §11, `task-cli-031`.

---

## 1. O que existe hoje (verificado no código, não de memória)

| Fato | Onde | Consequência para este desenho |
|---|---|---|
| `Types.DataStorePersistence` **não existe como tipo** — só como bloco de código dentro do desenho de 2026-09-05 e como menção no cabeçalho de `Store.luau` | `.claude/agents-memory/arquiteto-services-2026-09-05.md:1019`; `src/services/datastore/Store.luau:7` | Nada a refatorar; é declaração nova, e posso ajustar o nome/forma sem quebrar consumidor nenhum |
| `services` **nunca** faz `require("@lune/fs")` em código de produção (só `HttpService.spec.luau`, que é teste) | grep em `src/services/**` | A invariante está intacta hoje. Mantê-la é barato |
| `Store.new()` é module-local em `GlobalDataStore.luau`, singleton de processo, com histórico append-only por chave | `src/services/behavior/GlobalDataStore.luau:~95` | O ponto de carga/descarga é este `store` único — um só `Import`/`Export` cobre `GlobalDataStore`/`DataStore`/`OrderedDataStore` inteiros |
| `Store` **não** expõe nada de bulk (só `Get`/`Set`/`Update`/`Remove`/`GetVersion`/`ListVersions`/`ListKeys`) | `src/services/datastore/Store.luau:100-158` | Precisa de `Export`/`Import` novos — §5 |
| `versionCounter` nasce em `0` a cada `Store.new()`; `Version` é `"%013d-%010d"` (ms + contador), com a garantia declarada de que **ordem lexicográfica == ordem de inserção** | `Store.luau:190-196` | **Restaurar o contador no `Import` é obrigatório**, senão a garantia quebra em silêncio na 2ª execução — §5, achado |
| `Value.CheckSerializable` **aceita** `NaN`/`inf`/`-inf` (correção deliberada da task-services-028) e aceita qualquer tabela com chaves só-string **ou** só-número (esparsa, negativa, fracionária inclusive) | `Value.luau:174-231` + cabeçalho | Define o domínio que o formato em disco precisa cobrir sem perda — §4 |
| Duas pesquisas se contradizem sobre `NaN`: `pesquisa-datastore-2026-09-05.md:138` diz "não suportado, erra"; `pesquisa-services-leva2-pendencias` (posterior, doc oficial de Open Cloud) diz que a Engine API aceita | ambos em `.claude/agents-memory/` | A **posterior venceu e está no código**. O desenho segue o código. Se uma pesquisa futura reverter, o envelope continua correto (ele só precisa ser total sobre o que o validador aceitar) |
| Retenção de versão de 30 dias **está confirmada** por pesquisa | `pesquisa-datastore-2026-09-05.md:127` | Base para a poda de histórico — §5, não é número inventado |
| `Scheduler:Run` consulta `shouldContinue` **duas vezes por tique** (topo do laço e depois de `tick()`) | `src/runtime/Scheduler.luau:449-470` | Gancho de fronteira de tique **já existe e já é de `cli`** (`RunCommand.buildShouldContinue`) — nenhuma API nova de `runtime` |
| `DataModel.RunBindToCloseCallbacks` existe mas **nenhum chamador em `cli`** | `src/runtime/DataModel.luau:338`; grep em `src/cli/**` | Gap real — §11, `task-cli-031` |
| Padrão de injeção `cli → services` já estabelecido: `BootstrapOptions.AllowHttp`/`OnHttpRequest` → lido **só** via `Context.*` | `Types.luau:63-99`, `Context.luau:87-134` | O canal de persistência copia esse padrão exatamente. Zero invenção |
| `@lune/serde` (0.10.5) suporta **só** `json`, `yaml`, `toml`. Sem msgpack, sem base64. Tem `hash`/`hmac`/`compress` | probe empírico desta sessão | JSON é a escolha; base64 não está disponível de graça — §4 usa hex para o caso raro |
| `@lune/fs` **não tem append** (`readFile`/`writeFile`/`move`/`copy`/`metadata`/…) | probe empírico desta sessão | Log append-only está descartado: toda escrita é read-modify-write do arquivo inteiro. É o que força a coalescência de §6 |
| Decisão 10 de `cli`: `luaubench.toml` reservado, não criado; nunca dentro do `.project.json` (Rojo usa `deny_unknown_fields`) | `arquiteto-cli-2026-09-05.md:320-328` | Não conflita: `.luaubench/` é diretório de **estado**, não de **configuração** — §3 |

---

## 2. Decisão 1 — Onde o `@lune/fs` mora: em `cli`, não em `services`

A tarefa despachante pediu "um ponto de acesso único a `@lune/fs` dentro de `services` (ex. `src/services/CloudPersistence.luau`)". **Recomendo não fazer isso**, e o motivo não é purismo:

**a) `services` não tem como saber o caminho sozinho.** O diretório de persistência é relativo ao `.project.json` que `ProjectFile.Locate` resolveu — informação que só `cli` tem. Um `CloudPersistence.luau` dentro de `services` teria que **receber o caminho de `cli` de qualquer jeito**. Comparando as duas formas do mesmo acoplamento:

```luau
-- forma A (fs em services): cli passa um caminho, services faz I/O
Services.Bootstrap({ …, CloudDir = "/abs/path/.luaubench/cloud" })

-- forma B (fs em cli): cli passa um port, services não faz I/O
Services.Bootstrap({ …, CloudPersistence = CloudStore.Open(projectRoot) })
```

B é estritamente mais forte: mesmo número de parâmetros, `services` deixa de tocar disco, e o teste de `services` injeta um port em memória sem tocar `fs` nem criar diretório temporário.

**b) `@lune/net` em `HttpService.luau` NÃO é precedente para `@lune/fs` em `DataStoreService`.** A distinção é real e vale registrar, porque um revisor vai perguntar:

| | `HttpService` → `@lune/net` | persistência → `@lune/fs` |
|---|---|---|
| A I/O **é** a semântica da classe simulada? | Sim — `RequestAsync` é literalmente uma requisição de rede; sem rede não há o que simular | Não — `DataStore` no Roblox não tem conceito nenhum de arquivo. O arquivo é detalhe de implementação do LuauBench |
| Quem decide o destino? | O **script do usuário** (a URL vem do script) | O **projeto** (o caminho vem de onde o `.project.json` está) — conceito que `services` desconhece por desenho |
| O portão é injetado por `cli`? | Sim (`AllowHttp`) | Sim (presença do port) |

Ou seja: `net` está em `services` porque o destino é do script; `fs` fica em `cli` porque o destino é do projeto. Coerente, não arbitrário.

**c) O contrato já estava registrado nesta forma** desde 2026-09-05 (`arquiteto-services-2026-09-05.md`, L2.1.2: *"`services` nunca chama `@lune/fs`. Quem decide caminho, formato em disco, `.gitignore` e política de erro de I/O é `cli`"*). Reverter isso exigiria uma razão nova, e não há.

> **Conclusão: nenhuma invariante da regra 00 precisa ser violada nesta feature.** Não há nada a autorizar com o usuário aqui. Se o usuário ainda assim preferir `fs` dentro de `services`, é uma decisão dele — mas ela custa o item (a) acima e não compra nada.

**Ponto único de `fs`, então, é `src/cli/CloudStore.luau`** — o único módulo do projeto inteiro autorizado a ler/escrever dentro de `.luaubench/`. Auditável por um grep de uma linha.

---

## 3. Decisão 2 — Layout em disco

```
<raiz do projeto do usuário>/          (a pasta que contém o .project.json resolvido)
├── default.project.json
├── .luaubench/                        ← criado na 1ª execução que precisar gravar
│   ├── .gitignore                     ← conteúdo: "*"  (§9)
│   └── cloud/
│       └── datastore.json             ← todo o estado de DataStoreService
└── src/
```

**Por que `.luaubench/` e não um arquivo solto:** reserva um lugar para todo estado local futuro (`cloud/memorystore.json`, cache de dump, artefatos de execução) sem precisar de uma decisão nova por artefato. Diretório oculto por ponto é a convenção do ecossistema (`.git`, `.rokit`, `.vscode`).

**Por que isso não conflita com a Decisão 10 de `cli`:** aquela decisão vetou criar um **formato de configuração** (`luaubench.toml`) antes de existir algo para configurar. `.luaubench/` não configura nada — é estado produzido pela ferramenta. Ortogonal. O nome `luaubench.toml` continua reservado e não usado.

**Âncora do caminho:** o diretório fica ao lado do **`.project.json` que `ProjectFile.Locate` devolveu**, nunca de `process.cwd()`. Consequência que importa: `luaubench run caminho/para/projeto` a partir de qualquer cwd atinge sempre o mesmo arquivo. `cli` já tem esse caminho absoluto no passo 2 do pipeline.

**Sub-pasta `cloud/`, e não tudo solto em `.luaubench/`:** separa "estado que o usuário talvez queira versionar/inspecionar" de artefatos futuros de execução, e deixa `memorystore.json` cair ao lado sem redesenho.

### Formato do documento

JSON via `@lune/serde` (`encode("json", doc, true)` — pretty, para o arquivo ser legível e diffável). Zero dependência nova.

```jsonc
{
  "SchemaVersion": 1,
  "Kind": "luaubench-datastore",
  "SavedAt": 1757164800123,          // ms desde epoch, @lune/datetime — só informativo
  "Stores": {
    // chave = storeId opaco de Store.luau, com o  escapado pelo próprio JSON
    "PlayerDataglobal": {
      "Name": "PlayerData",           // redundante de propósito: legibilidade humana
      "Scope": "global",
      "Keys": {
        "Player_123": {
          "CreatedTime": 1757164700000,
          "Versions": [
            {
              "Version": "1757164700000-0000000001",
              "UpdatedTime": 1757164700000,
              "UserIds": [123],
              "Metadata": {},
              "Tombstone": false,
              "Value": { "Coins": 100, "Inventory": ["sword"] }   // envelope, §4
            }
          ]
        }
      }
    }
  }
}
```

**Um arquivo, não um por store.** Considerei arquivo por `(name, scope)` — reduz o custo de re-encode ao store sujo. Descartei por duas razões concretas:
- **Path traversal volta.** `name`/`scope` são strings arbitrárias de até 50 caracteres vindas do script do usuário. Virar nome de arquivo exigiria percent-encoding estrito, e aí o pior caso (50 bytes × 3) estoura os 260 caracteres de `MAX_PATH` do Windows — plataforma primária deste projeto. Resolver isso exigiria hash + índice reverso: complexidade real, para um ganho que a medição de §6 diz não ser necessário.
- **`Name`/`Scope` como chave de objeto JSON nunca alcança o filesystem.** É a mesma garantia estrutural que o desenho de 2026-09-05 já tinha escolhido.

**`SchemaVersion` desde o dia 1.** Documento com `SchemaVersion` desconhecido (maior que o suportado) é **recusado com erro claro**, nunca ignorado nem sobrescrito — perder o estado do usuário por causa de um downgrade de versão do LuauBench seria destruição silenciosa de dado.

---

## 4. Decisão 3 — O envelope de valor (a parte tecnicamente crítica)

### O problema, medido

Domínio que `Value.CheckSerializable` **aceita hoje**: `boolean`; `string` (bytes arbitrários); `number` (qualquer double, incluindo `NaN`/`±inf`); `table` acíclica com chaves **ou** todas string **ou** todas número (qualquer número: negativo, fracionário, esparso).

Comportamento medido de `serde.encode("json", …)` em Lune 0.10.5 (probe rodado nesta sessão, reproduzível):

| Valor Luau (aceito pelo validador) | JSON produzido | Veredicto |
|---|---|---|
| `0/0`, `math.huge`, `-math.huge` | `null` — **sem erro** | **Corrupção silenciosa.** `NaN` volta como `nil` na próxima execução |
| `{[1]=1, [3]=3}` | `[1]` — **sem erro** | **Corrupção silenciosa.** O elemento `[3]` some |
| `{[2]="a"}` | erro `invalid type: integer 2, expected a string key` | Erro tardio, no save, para uma escrita que **já foi aceita** em memória |
| `{[-1]="a"}`, `{[1.5]="a"}` | mesmo erro | idem |
| string com byte `0xFF` | erro `invalid type: byte array` | idem |
| `{}` | `{}` → volta tabela vazia | ok |
| `{["1"]="a"}` | `{"1":"a"}` → chave volta **string** | ok |
| `3.0` vs `3` | ambos `3` | ok (Luau não distingue) |
| `1234567890123` | exato | ok |

Os dois primeiros são o motivo de existir esta seção. Note que a corrupção seria uma divergência **do LuauBench em relação a ele mesmo** (o valor lido na execução 2 difere do escrito na execução 1) — pior que uma divergência em relação ao Roblox, e impossível de defender sob a invariante 2.

`{[123456] = perfil}` (dicionário indexado por `UserId`) é um padrão **comum** em código Roblox real e cai direto na terceira linha da tabela: erro no save de uma escrita que passou. Não é um caso de laboratório.

### O envelope: plain quando dá, tagueado quando precisa

Regra de codificação de um valor `v`:

| Caso | Emite |
|---|---|
| `boolean` | JSON boolean |
| `number` finito | JSON number |
| `number` não-finito | `{"$":"n","v":"nan"\|"inf"\|"-inf"}` |
| `string` UTF-8 válida (`utf8.len(s) ~= nil`) | JSON string |
| `string` com byte inválido | `{"$":"s","hex":"ff00…"}` |
| `table` densa `1..n` sem buracos, `n == #t == contagem de chaves` | JSON array (elementos recursivos) |
| `table` só com chaves string, **nenhuma delas igual a `"$"`** | JSON object (valores recursivos) |
| qualquer outra `table` (numérica esparsa/negativa/fracionária/não iniciando em 1, ou dicionário que contenha a chave `"$"`) | `{"$":"m","e":[[k,v],[k,v],…]}` — `k` e `v` ambos recursivos |

Regra de decodificação, simétrica e **sem ambiguidade**: um JSON object **com** a chave `"$"` é sempre um envelope tagueado; **sem** ela é sempre um dicionário de chaves string. É por isso que a linha do dicionário exige "nenhuma chave igual a `"$"`" — um dicionário do usuário que contenha `"$"` cai no formato `"m"`, e o decodificador nunca precisa adivinhar.

Notas:
- **`hex` em vez de base64** porque `@lune/serde` não expõe base64 (verificado) e hex são ~10 linhas de Luau. O caso é raríssimo; legibilidade > densidade.
- **`nil` não é representável e não precisa ser:** chave inexistente é ausência do registro; tabela Luau não guarda `nil`.
- **Precedente, não invenção:** a doc oficial de Open Cloud (já citada no cabeçalho de `Value.luau`) representa não-finitos exatamente assim, com tag — `{"t":"numeric","v":"nan"}`. Estamos na mesma família de solução, com nomes próprios do LuauBench, e o envelope vive fora do namespace de qualquer classe do dump (regra 00 satisfeita).

### Invariante testável (é o acceptance da tarefa)

> Para **todo** valor `v` que `Value.CheckSerializable(v) == nil`, vale `DeepEqual(Decode(Decode_json(Encode_json(Encode(v)))), v)`.

Property test com gerador cobrindo as 8 linhas da tabela acima, mais os 5 casos hostis medidos (`NaN`, `inf`, esparso, `{[2]=…}`, byte inválido). Se um caso não round-tripar, o encoder está incompleto — não é opinião, é falha de teste.

---

## 5. Decisão 4 — O que é serializado por chave, e a poda de histórico

**Persiste o `KeyRecord` inteiro**: `CreatedTime` + o array `Versions` completo (cada versão com `Version`, `UpdatedTime`, `UserIds`, `Metadata`, `Tombstone`, `Value` envelopado). Não só o estado corrente.

Por quê: `GetVersionAsync`/`ListVersionsAsync` são simulados hoje (task-services-019) e o ProfileStore os usa em `ProfileVersionQuery`. Salvar só a versão corrente faria `ListVersionsAsync` devolver 1 item depois de um restart — divergência gratuita, quando o custo de guardar o histórico é o mesmo arquivo.

**Poda por idade, 30 dias.** `pesquisa-datastore-2026-09-05.md:127` confirma: "versões antigas continuam acessíveis **por 30 dias**". Então descartar, no `Export`, toda versão **não-corrente** com `UpdatedTime` mais velho que 30 dias é *fidelidade*, não economia — e limita o crescimento do arquivo em projeto de vida longa. A versão **corrente** nunca é podada, mesmo velha (senão a chave sumiria).

> **Limitação declarada:** a poda por idade **não** limita crescimento *dentro* de 30 dias. Um projeto que rode um laço de 100 mil escritas por dia produz um arquivo grande. Deliberadamente **não** estou inventando um teto de N versões por chave — seria um número sem fonte, e a invariante 1 proíbe. Fica registrado como candidato a tarefa futura *se* alguém observar o problema de verdade.

### Achado: o contador de versão precisa ser restaurado no `Import`

`Store.luau` gera `Version` como `string.format("%013d-%010d", updatedTime, versionCounter)` e **declara no cabeçalho** que a largura fixa existe para que "a ordem lexicográfica de `Version` bata com a ordem de inserção".

`Store.new()` começa com `versionCounter = 0`. Numa 2ª execução que carrega um arquivo, o contador reiniciaria em 1 — e uma versão nova escrita no mesmo milissegundo de uma versão antiga com contador maior **ordenaria antes dela**. A garantia documentada quebra em silêncio, e `ListVersionsAsync` passa a mentir sobre a ordem.

**`Store.Import` obrigatoriamente faz `versionCounter = max(contador de toda versão carregada) + 1`.** Isso é acceptance da tarefa, não detalhe de implementação. (Colisão exata da string `Version` também fica impossível, de quebra.)

### API nova em `Store.luau`

```luau
export type StoredVersion = {
    Version: string,
    Value: unknown,                       -- valor Luau cru; envelopar/desenvelopar é de quem serializa
    UpdatedTime: number,
    UserIds: { number },
    Metadata: { [string]: unknown },
    Tombstone: boolean,
}

export type StoredKey = { CreatedTime: number, Versions: { StoredVersion } }

export type Snapshot = { [string]: { [string]: StoredKey } }   -- [storeId][key]

-- Estado inteiro, deep-copiado (mesma disciplina de DEEP COPY do módulo). Aplica a poda de
-- 30 dias descrita acima. Não conhece JSON, não conhece disco.
Export: (self: Store) -> Snapshot,

-- Substitui o estado inteiro. Restaura versionCounter = max(visto) + 1 (achado acima).
-- Recusa com erro claro um snapshot malformado — nunca aceita parcialmente.
Import: (self: Store, snapshot: Snapshot) -> (),

-- Marcado por toda mutação (Set/Update/Remove); zerado por quem persistiu. É o que permite
-- pular a serialização quando nada mudou desde o último flush.
IsDirty: (self: Store) -> boolean,
ClearDirty: (self: Store) -> (),
```

`Store.luau` continua **sem saber o que é JSON, arquivo ou caminho** — a mesma fronteira de responsabilidade que o cabeçalho dele já declara.

---

## 6. Decisão 5 — Quando ler e quando escrever

### Leitura: uma vez, no bootstrap, antes de qualquer script

Passo 7 do pipeline de `RunCommand` (`Services.Bootstrap`) passa o port. `services` chama `CloudPersistence.Load()` **dentro do `Bootstrap`**, decodifica e faz `store:Import(...)`. Termina antes do passo 10 (`ScriptRunner.Run`), então o primeiro `GetAsync` do primeiro script já enxerga o estado da execução anterior. Sem carga preguiçosa: é um arquivo só, custo medido de 0,5 ms a 44 ms de decode uma única vez por processo.

### Escrita: marca suja síncrona, flush coalescido por tique

A tarefa despachante pediu para decidir entre "persistir imediatamente a cada escrita" e "debounce/batch". **Medi antes de decidir** (snapshot realista tipo ProfileStore, `os.clock`, 50 iterações por ponto, Lune 0.10.5, Windows):

| Chaves | JSON | `serde.encode` | `fs.writeFile` | encode+write | +escrita atômica (tmp+move) |
|---:|---:|---:|---:|---:|---:|
| 10 | 5,3 KiB | 0,51 ms | 0,63 ms | **0,98 ms** | 2,29 ms |
| 100 | 53,7 KiB | 4,26 ms | 3,29 ms | **7,01 ms** | 6,99 ms |
| 1000 | 540,8 KiB | 44,42 ms | 6,93 ms | **46,24 ms** | 48,05 ms |

Duas leituras que decidem o desenho:
- **O custo é dominado pelo `encode`, não pelo I/O** (44 ms vs 7 ms em 540 KiB). Otimizar "só escreve se mudou" precisa evitar o *encode*, não só o *write*.
- **`@lune/fs` não tem append** (verificado), então toda escrita é o arquivo inteiro. Persistir de forma síncrona a cada `SetAsync` torna um laço de N escritas **O(N²)**: 1000 escritas num store de 1000 chaves ≈ 46 segundos. Inaceitável para uma ferramenta cujo argumento de venda é ser mais rápida que dar F5 no Studio.

**Decisão:**
1. Toda mutação bem-sucedida (`Set`/`Update`/`Remove`, portanto `SetAsync`/`UpdateAsync`/`RemoveAsync`/`IncrementAsync` e o caminho de `OrderedDataStore`) marca **suja** — O(1), síncrono, dentro do fluxo de `AsyncCall.Yield` já existente. Custo desprezível, nenhum I/O.
2. O flush real acontece na **fronteira de tique do scheduler**, dentro do `shouldContinue` que `RunCommand.buildShouldContinue` **já** constrói e que `Scheduler:Run` **já** consulta duas vezes por tique (`Scheduler.luau:449-470`). **Nenhuma API nova de `runtime`.** Se não está sujo, o callback não faz nada — nem encode.
3. Flush **forçado** (síncrono, ignora coalescência) em três pontos, todos em `cli`: depois de `scheduler:Run` retornar; depois de `RunBindToCloseCallbacks` (quando `task-cli-031` existir); e no caminho de saída por `--timeout`.

**Trade-off declarado:** a janela de durabilidade é **um tique de scheduler** (~16 ms). Um `kill -9` no meio de um tique perde as escritas daquele tique. Para um ambiente de debug local isso é o trade certo — a alternativa custa O(N²) e ninguém está tratando isto como banco de dados. **Está declarado, não é silencioso.**

**Escrita atômica:** `writeFile(tmp)` + `move(tmp, final, {overwrite = true})`. A medição mostra que isso custa ~1,3 ms extra no caso pequeno e **nada** nos casos médio/grande (dentro do ruído). Preço trivial para nunca deixar um `datastore.json` truncado se o processo morrer no meio da gravação. Adotado.

### Política de erro de I/O (de `cli`, conforme a Decisão 1)

- **Falha ao ler** (arquivo corrompido, JSON inválido, `SchemaVersion` desconhecido): erro de projeto claro apontando o arquivo, exit 2, **e o arquivo não é sobrescrito** — o usuário decide se apaga. Nunca "começa do zero em silêncio", que apagaria estado real dele.
- **Falha ao escrever** (disco cheio, permissão, caminho somente-leitura): um `warning` por execução, não um erro fatal e **não** uma linha por tique. O script do usuário continua rodando com o estado em memória — perder persistência não deve derrubar a execução.
- **`.luaubench/` não existe:** criado sob demanda, na primeira gravação. Uma execução que só lê nunca cria diretório nenhum no projeto do usuário.

---

## 7. Decisão 6 — `MessagingService`: fica em memória (fiel)

**Decisão: nenhuma persistência.** Não é economia de escopo, é fidelidade.

No Roblox real `MessagingService` é pub/sub efêmero: `PublishAsync` entrega apenas a quem já está inscrito *naquele momento*. **Não existe mensagem pendente, não existe fila, não existe backlog.** Persistir "mensagens pendentes" entre execuções seria inventar um comportamento que a classe real não tem, dentro do namespace da classe real — proibido pela regra 00, invariante 1.

O pedido original do usuário menciona "os messagingservices pendentes". Interpretação honesta: o modelo mental é razoável (é o que uma fila de mensagens costuma fazer), mas mapeia para um conceito que o Roblox não tem. O jeito de servir a intenção sem mentir é **observabilidade**, não persistência.

**Extensão deliberada aprovada (fora do namespace simulado):** `--verbose` passa a imprimir uma linha por `PublishAsync`, no stderr, com **tópico e tamanho em bytes — nunca o corpo da mensagem**. Precedente exato, mesmo canal, mesma forma: `OnHttpRequest` / `Messages.HttpRequestAuditLine` (task-services-026 / task-cli-026).

```luau
-- em Types.BootstrapOptions (ao lado de OnHttpRequest)
OnMessagePublished: ((topic: string, byteSize: number) -> ())?,
-- lido só via Context.NotifyMessagePublished, nunca de BootstrapOptions direto
```

- **Não** é propriedade, método ou evento de `MessagingService` — o script do usuário não alcança isso de jeito nenhum.
- **Nenhum arquivo novo.** Deliberadamente não estou propondo `.luaubench/messages.log`: ninguém pediu um arquivo, e inventar formato de log antes de existir demanda é exatamente o erro que a Decisão 10 de `cli` já evitou uma vez.
- Corpo da mensagem nunca sai — mesma regra que barra corpo/headers na auditoria de HTTP.

---

## 8. Decisão 7 — `MemoryStoreService`: fora desta leva

**Decisão: não entra.** Três razões, em ordem de peso:

1. **A classe não existe.** Não há `behavior/MemoryStoreService.luau`, não há nada gerado com comportamento, não há pesquisa concluída. Desenhar a persistência de uma classe antes de a classe existir é decidir no vácuo.
2. **MemoryStore é volátil por natureza.** É armazenamento com TTL, pensado para coordenação efêmera entre servidores (filas, sorted maps, locks). Persistir estado com TTL entre execuções separadas por horas ou dias **produziria um comportamento menos fiel**, não mais: na próxima execução tudo já teria expirado no Roblox real. Fazer certo exige simular expiração contra relógio de parede na carga — o que só faz sentido depois de a semântica de TTL existir e estar testada.
3. **Pesquisa pendente.** `.claude/agents-memory/pesquisa-memorystore-persistencia-2026-09-06.md` **não existia no disco** quando escrevi isto. Os limites de TTL (máximo, default, granularidade), a superfície exata (`MemoryStoreQueue`/`SortedMap`/`HashMap`) e o comportamento de expiração estão **NÃO CONFIRMADOS** por mim.

**Ordem recomendada:** leva própria para `MemoryStoreService` fiel em memória (com TTL simulado contra o relógio do scheduler) → **depois** decidir persistência, com a pesquisa em mãos.

**O que este desenho já deixa pronto para isso:** `.luaubench/cloud/` aceita um `memorystore.json` irmão sem redesenho, e o port `CloudPersistence` (§10) é **por documento nomeado**, não fixo em DataStore — `Load("datastore")` / `Save("datastore", …)`. Acrescentar MemoryStore depois é passar outro nome, zero mudança de contrato.

---

## 9. Decisão 8 — `.gitignore`: o LuauBench nunca edita arquivo do usuário

**Decisão: `.luaubench/` se auto-ignora.** Ao criar o diretório pela primeira vez, `CloudStore` escreve `.luaubench/.gitignore` com o conteúdo `*`.

Efeito: o git do usuário passa a ignorar todo o conteúdo de `.luaubench/` (inclusive o próprio `.gitignore`), **sem que o LuauBench encoste no `.gitignore` da raiz dele**. Editar um arquivo versionado do usuário sem ele pedir seria intrusivo e potencialmente conflitante com o fluxo de trabalho dele; escrever dentro do nosso próprio diretório não é.

**Comunicação:** na execução que criar o diretório, uma linha informativa no stderr (string em `Messages.luau`, como toda saída de `cli`), aproximadamente:

> `luaubench: created .luaubench/ for simulated cloud state (DataStore). It is git-ignored by default; delete .luaubench/.gitignore if you want to commit it.`

Uma vez, só na criação — nunca a cada execução. E ela também diz como **desfazer** o padrão, para quem quiser versionar o estado como fixture de time.

---

## 10. Contrato entre territórios

### `services` expõe (o que `cli` chama)

```luau
-- src/services/Types.luau  (acrescenta; nada existente muda)

-- Porta de persistência do estado "cloud". Implementada por `cli` (src/cli/CloudStore.luau) --
-- `services` NUNCA chama @lune/fs. `document` é um nome lógico ("datastore" hoje;
-- "memorystore" numa leva futura), nunca um caminho: quem transforma nome em caminho é `cli`.
export type CloudPersistence = {
    -- Devolve o documento serializado, ou nil se nunca existiu. ERRA (nunca devolve nil) se o
    -- arquivo existe mas está ilegível -- perder estado do usuário em silêncio é proibido.
    Load: (document: string) -> string?,
    -- Grava atomicamente. Pode errar; quem chama trata (services degrada para warning via cli).
    Save: (document: string, contents: string) -> (),
}

export type BootstrapOptions = {
    scheduler: Runtime.Scheduler,
    dataModel: Runtime.DataModel,
    AllowHttp: boolean?,
    AllowHttpLocal: boolean?,
    OnHttpRequest: ((method: string, host: string) -> ())?,

    -- NOVO. `nil` == sem persistência nenhuma (comportamento de hoje, e o que `--no-persist`
    -- produz). Lido só via Context.GetCloudPersistence -- nenhum behavior/*.luau lê daqui.
    CloudPersistence: CloudPersistence?,
    -- NOVO (§7). `nil` == sem auditoria. Só (topic, byteSize) -- nunca o corpo.
    OnMessagePublished: ((topic: string, byteSize: number) -> ())?,
}
```

```luau
-- src/services/init.luau  (superfície pública de `services`, o que `cli` enxerga)

-- Grava se houver algo sujo; no-op silencioso se não houver, ou se nenhum port foi injetado.
-- `cli` chama isto na fronteira de tique e nos flushes forçados. Devolve `true` se gravou.
-- NUNCA propaga erro de I/O: erro vira `false` + a mensagem, para `cli` decidir o que imprimir.
Services.FlushCloudState: () -> (boolean, string?)

-- Estado corrente (para o sumário final: "cloud state saved to .luaubench/cloud").
Services.HasPendingCloudState: () -> boolean
```

`Services.Bootstrap` passa a, ao final do registro: se `CloudPersistence ~= nil`, chamar `Load("datastore")`, decodificar e `store:Import(...)`. Falha de decode **propaga** — `cli` transforma em erro de projeto (exit 2).

### `cli` expõe (o que `cli` constrói)

```luau
-- src/cli/CloudStore.luau -- ÚNICO módulo de `cli` que toca .luaubench/. Único `require("@lune/fs")`
-- desta feature no projeto inteiro.

export type Store = Services.CloudPersistence   -- estruturalmente compatível, sem cast

-- `projectRoot` é o diretório do .project.json resolvido por ProjectFile.Locate (NUNCA cwd).
-- Não toca o disco aqui: o diretório só nasce na primeira gravação.
-- `onFirstCreate` é chamado uma vez, se e quando `.luaubench/` for criado (§9, a linha informativa).
CloudStore.Open: (projectRoot: string, onFirstCreate: (path: string) -> ()) -> Store
```

### Quem chama primeiro

```
RunCommand.Execute
 ├─ passo 3: ProjectFile.Read      → projectPath (absoluto)
 ├─ passo 6: Scheduler.new / DataModel.new
 ├─ NOVO:    cloud = if options.NoPersist then nil else CloudStore.Open(dirOf(projectPath), …)
 ├─ passo 7: Services.Bootstrap({ …, CloudPersistence = cloud })   ← LÊ o arquivo aqui
 ├─ passo 10: ScriptRunner.Run       (scripts já enxergam o estado da execução anterior)
 ├─ passo 11: scheduler:Run(shouldContinue)
 │              └─ shouldContinue: deadline de --timeout  AND ALSO  Services.FlushCloudState()
 ├─ NOVO:    DataModel.RunBindToCloseCallbacks(game, scheduler)    ← task-cli-031
 ├─ NOVO:    Services.FlushCloudState()                            ← flush final forçado
 └─ passo 12: sumário
```

> `shouldContinue` é um predicado consultado por seu **valor de retorno**; usá-lo também como gancho de efeito colateral é legítimo aqui (`cli` é o dono dele) mas **precisa estar comentado no código**, senão parece acidente. Vai no acceptance de `task-cli-030`.

### Grafo de dependência (inalterado)

`runtime` ← `services` ← `cli`. `runtime` não ganha nada. `services` não ganha dependência nova nenhuma (nem `fs`, nem `serde` — o encode do documento fica em `services/datastore/Snapshot.luau` usando… **espera**: o encode JSON precisa de `@lune/serde`).

**Resolvido:** `services` **já** usa `@lune/serde` hoje (`behavior/HttpService.luau:289`, `JSONEncode`/`JSONDecode`). Não é dependência nova, e `serde` é puro (string→string), sem I/O — não fere nada. O envelope (`Snapshot.luau`) fica em `services`, junto do domínio de valor que ele precisa conhecer; só o `fs` fica em `cli`. Fronteira limpa: **`services` decide o que os bytes significam, `cli` decide onde os bytes moram.**

---

## 11. Divisão por território

| Território | O que constrói | Contrato com o vizinho |
|---|---|---|
| `services` | `datastore/Snapshot.luau` (envelope + documento); `Store.Export`/`Import`/`IsDirty`; `Types.CloudPersistence`; `Context.GetCloudPersistence`/`NotifyMessagePublished`; marca-suja em `GlobalDataStore`; `Services.FlushCloudState` | Recebe o port por `BootstrapOptions`. Nunca `@lune/fs`, nunca caminho |
| `cli` | `CloudStore.luau` (único `fs`); `--no-persist`; flush no `shouldContinue` + flush final; mensagens em `Messages.luau`; `RunBindToCloseCallbacks` | Passa `CloudPersistence` no `Bootstrap`; chama `Services.FlushCloudState` |
| `runtime` | **Nada.** | — |
| `valuetypes` | **Nada.** | — |
| `testador` | Cenário de duas execuções contra o mesmo projeto-fixture | Read-only em `src/**` |

### Tarefas propostas (para o `planejador` refinar)

| ID | Agente | Título | Depende de | Onda |
|---|---|---|---|---|
| `task-services-029` | `coder-services` | `datastore/Snapshot.luau`: envelope de valor + documento, com property test de round-trip | — | 51 |
| `task-cli-029` | `coder-cli` | `CloudStore.luau`: ponto único de `fs`, `.luaubench/` sob demanda, escrita atômica, auto-`.gitignore` | — | 51 |
| `task-cli-031` | `coder-cli` | Chamar `DataModel.RunBindToCloseCallbacks` depois de `scheduler:Run` (gap pré-existente) | — | 51 |
| `task-services-030` | `coder-services` | `Store.Export`/`Import`/`IsDirty`/`ClearDirty` + restauração do `versionCounter` + poda de 30 dias | — | 51 |
| `task-services-031` | `coder-services` | Fiação: `Types.CloudPersistence`, `Context`, marca-suja em `GlobalDataStore`, load no `Bootstrap`, `Services.FlushCloudState` | 029, 030 | 52 |
| `task-cli-030` | `coder-cli` | `--no-persist`, `CloudStore.Open` no pipeline, flush no `shouldContinue` + final, mensagens | 029(cli), 031(services) | 53 |
| `task-services-032` | `coder-services` | `OnMessagePublished` em `MessagingService` (§7) — **sem** persistência | — | 51 |
| `task-test-cloud-001` | `testador` | Cenário de duas execuções: escreve, sai, reabre, confirma persistência; e `--no-persist` não persiste | todas | 54 |

**Paralelismo real** (não inventado): onda 51 tem quatro tarefas independentes em **dois** territórios que não compartilham arquivo — `coder-services` (029, 030, 032) e `coder-cli` (029-cli, 031) rodam em paralelo. O resto é genuinamente sequencial: não adianta fiar antes de existir o que fiar.

---

## 12. Fidelidade vs. pragmatismo

| Área | Status |
|---|---|
| Valor round-tripa idêntico entre execuções | **Exato**, e é invariante testada (§4) |
| Histórico de versão sobrevive a restart | **Exato**, com poda de 30 dias fiel à retenção documentada |
| `Version` mantém ordem lexicográfica == ordem de inserção entre execuções | **Exato**, via restauração do contador (§5) |
| Ordenação de `OrderedDataStore` depois de restart | **Exato** — deriva do valor, que round-tripa |
| Durabilidade | **Aproximação declarada:** janela de um tique (~16 ms). Justificada por medição (§6) |
| Estado "cloud" é por projeto, não por lugar/universo | **Aproximação declarada:** `PlaceId`/`UniverseId` não entram na chave. O LuauBench é um processo, um lugar. Se um dia simular `PlaceId` variável, o layout já suporta um nível a mais sem quebrar `SchemaVersion` |
| Mensagem de `MessagingService` entre execuções | **Não existe — e é fiel** (§7) |
| `MemoryStoreService` | **Fora desta leva** (§8) |
| Throttle/budget/erro transitório de DataStore | Inalterado — continua não simulado, decisão de 2026-09-05 |
| Concorrência entre dois `luaubench run` simultâneos no mesmo projeto | **Não tratada.** Último a gravar vence. Sem lock de arquivo. Ver §13 |

---

## 13. Riscos e decisões

1. **Duas execuções simultâneas no mesmo projeto** (dois terminais, ou watch mode futuro) fazem last-write-wins e uma perde o trabalho da outra. Não estou propondo lock: exigiria um arquivo de lock, política de lock morto e detecção de processo, para um cenário que ninguém relatou. **Registrado, não resolvido.** Se aparecer, a solução natural é um `.luaubench/cloud/.lock` com PID.
2. **Arquivo corrompido** (edição manual, crash antigo, merge de git): erro claro apontando o arquivo, exit 2, **sem sobrescrever**. Nunca "recomeça do zero".
3. **`SchemaVersion` futuro** (usuário rodou uma versão nova do LuauBench e voltou para uma antiga): recusa com erro nomeando a versão encontrada e a suportada. Nunca lê "na esperança".
4. **`while true do end` sem yield** trava o processo antes de qualquer flush; as escritas do tique corrente se perdem. Já é limitação conhecida do scheduler (`--timeout` não é watchdog), agora com uma consequência a mais — **documentada**, não nova.
5. **`services` degrada, nunca derruba:** falha de gravação vira `false` + mensagem para `cli`; o script continua. Falha de *leitura* é fatal, porque continuar significaria fingir que o estado do usuário não existe.
6. **Escrita atômica** (`tmp` + `move`) protege contra arquivo truncado. Custo medido: irrelevante.
7. **Contradição de pesquisa sobre `NaN`** (§1): o desenho segue o código atual e é **indiferente** ao desfecho — o envelope só precisa ser total sobre o que o validador aceitar em cada momento.
8. **Pendências de pesquisa** (`pesquisador`, nenhuma bloqueia começar):
   - **`MemoryStoreService`** — superfície, TTL, expiração. **NÃO CONFIRMADO.** Bloqueia a leva dele, não esta.
   - **Chave numérica em DataStore real** — o Roblox real preserva `{[123]="a"}` com chave numérica no round-trip, ou converte para string? `Value.luau` hoje aceita e o LuauBench preserva. **NÃO CONFIRMADO**; se o Roblox converter, é divergência a declarar em `Value.luau`, **não** no formato de persistência (o envelope preserva o que a simulação decidir).
   - **Retenção de 30 dias** — confirmada por pesquisa (`pesquisa-datastore-2026-09-05.md:127`), mas por fonte secundária. Boa o bastante para a poda; vale um carimbo primário quando alguém passar por perto.

---

## 14. O que deliberadamente NÃO fazer agora

- **Arquivo por store, hashing de nome, índice reverso.** Um arquivo resolve, e a medição prova que o custo é aceitável. Complexidade sem ganho.
- **Log append-only / WAL.** `@lune/fs` não tem append (verificado); toda escrita é o arquivo inteiro de qualquer forma.
- **Teto de N versões por chave.** Número sem fonte. A poda por idade tem fonte.
- **Persistir `MessagingService`.** Inventaria comportamento que a classe real não tem (§7).
- **`MemoryStoreService`, em qualquer forma.** A classe nem existe (§8).
- **Compressão** (`serde.compress` existe). O arquivo deixaria de ser inspecionável e diffável — que é metade do valor de ter um arquivo. Reconsiderar só se alguém reclamar de tamanho de verdade.
- **`--cloud-dir` / `--persist-format` / `--cloud-reset`.** Só `--no-persist` tem necessidade demonstrada (CI, cenários determinísticos do `testador`, reprodução do zero). Apagar estado é `rm -rf .luaubench/`; não precisa de flag.
- **`luaubench.toml`.** Continua reservado e não usado. `.luaubench/` é estado, não configuração.
- **Lock entre processos concorrentes.** §13.1.
- **Editar o `.gitignore` da raiz do usuário.** §9 resolve sem tocar arquivo dele.
