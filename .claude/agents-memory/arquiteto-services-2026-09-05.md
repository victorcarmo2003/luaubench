# `services` — Arquitetura

Data: 2026-09-05. Território novo, desenhado do zero sobre o `runtime` já fechado (14 tarefas, todos os módulos aprovados).

Insumos que este desenho consome e não repete:
- `.claude/agents-memory/arquiteto-runtime-2026-09-04.md` — contrato de `runtime` (as três revisões pós-integração incluídas).
- `.claude/agents-memory/pesquisa-api-dump-membros-2026-09-04.md` — modelo real de membro do dump.
- `.claude/agents-memory/pesquisa-instance-member-access-2026-09-04.md` — família de erro de acesso a membro.
- Recon de uso real do `testador`: `ReplicatedStorage`(296) / `RunService`(196) / `Players`(154) / `HttpService`(37) / `CollectionService`(32) / `DataStoreService`(24, quase sempre via ProfileStore) / `TweenService`(14) / `Workspace`(8).
- Verificação de dump/Lune feita nesta sessão (pesquisador, 2026-09-05) — fatos citados ao longo do texto como **[verificado 09-05]**.

---

## Propósito

Transformar o Roblox API Dump oficial em classes simuladas registradas no `ClassRegistry` do `runtime`, separando de forma dura o que é **gerado do dump** (a superfície: nomes, tipos, escrituralidade, herança) do que é **escrito à mão** (o comportamento), sem que `runtime` conheça nome de classe e sem reparsear o dump a cada `luaubench run`.

---

## Fatos externos fixados nesta sessão

Base factual do desenho; nenhum item abaixo é de memória.

| Fato | Valor | Fonte |
|---|---|---|
| Commit do dump | `28360dea4b90b35dc3fe9f829baae64fb6c50e75` | pesquisa 09-04, reconfirmado 09-05 |
| Versão Roblox | `0.737.0.7371584` (mensagem do commit) | idem |
| `version-guid.txt` | `version-9fe94fb0e9d84c25` | pesquisa 09-04 |
| Tamanho do `Full-API-Dump.json` | **8 006 149 bytes** (7,64 MiB) | **[verificado 09-05]** download real por URL fixada por SHA, 2 métodos independentes |
| URL reproduzível | `https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/<SHA>/Full-API-Dump.json` | **[verificado 09-05]** HTTP 200 |
| Chaves do objeto raiz | `Classes`, `Enums`, `Version` — **só essas três** | **[verificado 09-05]** |
| `Version` do dump | `1` (versão do **esquema**, não do Roblox) | **[verificado 09-05]** |
| Contagens | 916 classes, 629 enums; 4038 Property, 3258 Function, 1087 Event, 18 Callback | 09-04 + 09-05 |
| Chaves de topo de uma classe | `Members`, `MemoryCategory`, `Name`, `Superclass` (100%) + `Tags` (ausente em 293/916) | **[verificado 09-05]** |
| Tags de classe | `NotCreatable` 553, `NotReplicated` 340, **`Service` 334**, `Deprecated` 48, `NotBrowsable` 31, `PlayerReplicated` 1, + 15 tags-objeto | **[verificado 09-05]** |
| `"Settings"` como tag de classe | **não existe** (0 ocorrências) — era nome de classe, não tag | **[verificado 09-05]**, corrige leitura anterior |
| Lune 0.10.5: `serde.decode("json", s)` / `fs.readFile`/`writeFile`/`writeDir` / `net.request({url,method}).body: string` | todos existem e funcionam | **[verificado 09-05]** rodados de verdade |
| Custo de ler+decodificar o dump inteiro no Lune | `fs.readFile` 0,0089s + `serde.decode` 0,1865s ≈ **0,2s** | **[verificado 09-05]** medido |
| `Workspace.Superclass` | **`WorldRoot`** — *não* `Instance`, *não* `Model` direto | **[verificado 09-05]** |
| `StarterGui.Superclass` | **`BasePlayerGui`** | **[verificado 09-05]** |
| `ReplicatedStorage` | `Members: []` (zero membros próprios), `Superclass: "Instance"`, `Tags: ["NotCreatable","Service"]` | **[verificado 09-05]** |
| Raiz real da hierarquia | `Object` (`Superclass == "<<<ROOT>>>"`); `Instance.Superclass == "Object"` | pesquisa 09-04 |

**Consequência dos 0,2s:** decodificar o dump em runtime seria *tecnicamente* viável, mas continua rejeitado — ver "Decisão 1".

---

## Decisão 1 — Pipeline do gerador

### O que foi decidido

**Gerador dev-time em Lune que emite `.luau` reais committados.** O `luaubench run` do usuário final nunca vê o dump, nunca chama `serde`, nunca faz I/O de dados de API.

- Gerador: `tools/generate-services.luau`, script Lune (mesmo runtime do projeto — invariante 3 preservada, zero dependência nova).
- Invocação: `lune run tools/generate-services` (dev-time, manual, nunca em `luaubench run` nem em CI de release).
- Entrada: `tools/api-dump.lock.json` (versão fixada) + `tools/coverage.luau` (lista de classes-alvo, editada à mão).
- Saída: `src/services/generated/**`, 100% sobrescrito a cada execução.

### Alternativas rejeitadas

| Alternativa | Por que não |
|---|---|
| Parsear o dump a cada `luaubench run` | 0,2s + 8 MB de I/O por invocação, e o binário standalone do `lune build` teria de carregar um arquivo de dados externo — quebra a premissa de executável autocontido (invariante 4). Regra 01 já proíbe explicitamente. |
| Emitir JSON pré-processado lido em runtime | Mesmo problema de arquivo externo no binário, mais um formato intermediário para manter. Ganha só velocidade que o `.luau` committado já dá de graça. |
| Um `.luau` por classe para as 916 | 916 arquivos e ~30k linhas geradas para cobrir 22 classes de verdade. Custo de repositório e de revisão sem retorno. |
| Um único `.luau` com todas as classes | Diff ilegível, carrega tudo para usar 5 classes, conflito garantido entre tarefas. |
| Copiar campo a campo à mão | Proibido pela regra 03. |

### Fecho transitivo automático

O gerador **não** aceita a lista de cobertura como final: ele computa o **fecho de superclasses** andando `Superclass` no dump até `Instance`. `Workspace` é a prova de que isso não é opcional — `Workspace.Superclass == "WorldRoot"` **[verificado 09-05]**, não `Model` como seria intuitivo, e `ClassRegistry.resolveClassChain` erra alto se um elo não estiver registrado. Ninguém escreve essa cadeia à mão.

Normalização obrigatória na emissão:
- `Superclass == "Object"` → o gerador **para em `Instance`**. `Object` nunca é emitido como classe; `Instance` é a raiz simulada do LuauBench (`ClassRegistry.resolveClassChain` já termina em `"Instance"`).
- Os membros que o dump declara em `Object` (`ClassName`, `Name`, `Parent`, `Changed`, `className`, `IsA`, …) são responsabilidade de `runtime/Instance.luau`, que já os implementa à mão. **O gerador dobra os membros de `Object` dentro do schema emitido de `Instance`** e emite no relatório a lista de membros de `Object`/`Instance` que `Instance.luau` não cobre — para que a lacuna seja visível, nunca silenciosa.

### Separação gerado × à mão

Regra dura, cobrável em revisão: **o gerador nunca escreve fora de `src/services/generated/`, e nenhum humano/agente edita dentro de `src/services/generated/`.**

Cada arquivo gerado abre com:
```
-- ARQUIVO GERADO por tools/generate-services.luau — NÃO EDITAR À MÃO.
-- Roblox API Dump: MaximumADHD/Roblox-Client-Tracker @ 28360dea4b90b35dc3fe9f829baae64fb6c50e75
-- Versão Roblox: 0.737.0.7371584 | esquema do dump: Version 1
-- Regenerar: lune run tools/generate-services
```

---

## Decisão 2 — Versão do dump fixada e onde ela vive

**Fixar `28360dea4b90b35dc3fe9f829baae64fb6c50e75` / `0.737.0.7371584` agora.** É a versão que a pesquisa de `task-runtime-017` já inspecionou e que foi rebaixada e reconfirmada nesta sessão; fixar outra obrigaria a repetir toda a análise de membro sem ganho.

Registro em três lugares, com papéis distintos (regra 03 exige versão fixada e registrada):

1. **`tools/api-dump.lock.json`** — a fonte da verdade, committada:
```json
{
  "source": "MaximumADHD/Roblox-Client-Tracker",
  "commit": "28360dea4b90b35dc3fe9f829baae64fb6c50e75",
  "robloxVersion": "0.737.0.7371584",
  "versionGuid": "version-9fe94fb0e9d84c25",
  "dumpSchemaVersion": 1,
  "url": "https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/28360dea4b90b35dc3fe9f829baae64fb6c50e75/Full-API-Dump.json",
  "sizeBytes": 8006149,
  "sha256": "<preenchido pelo gerador na primeira execução>",
  "fetchedAt": "2026-09-05"
}
```
O gerador **verifica** `sizeBytes` e `sha256` do que baixou e **aborta** se divergirem. Trocar de versão do dump é editar este arquivo — decisão explícita, nunca automática (regra 03).

2. **Cabeçalho de todo arquivo gerado** — para que qualquer diff mostre contra qual dump aquele código foi produzido.

3. **`src/services/generated/Manifest.luau`** — constantes `DumpCommit` / `DumpVersion` legíveis em runtime, expostas por `Services.GetDumpVersion()`. É o que permite ao `cli` imprimir a versão do dump em `luaubench --version` e o que faz uma mensagem de erro de classe não coberta dizer *contra qual dump* ela é conhecida.

**O `Full-API-Dump.json` NÃO é committado.** 8 MB de blob reproduzível por URL fixada por SHA **[verificado 09-05]**. O gerador baixa para `.cache/api-dump/<commit>.json` (adicionar `.cache/` ao `.gitignore`) e reusa se o sha256 bater. Risco declarado: se o repositório upstream desaparecer, a *regeração* fica bloqueada — o *build* não, porque o gerado é committado. Mitigação prevista, não construída agora: anexar o dump ao GitHub Release.

---

## Decisão 3 — Formato do descritor de membro

### Rejeito as duas opções da pesquisa; adoto uma terceira

**Opção A** (`{Default, ReadOnly}`, filtro do gerador em `Security.Read == "None" and Security.Write == "None"`) tem um defeito aritmético concreto: `Security.Read == "None"` em 2828 propriedades e `Security.Write == "None"` em 2769 — as **~59 propriedades legíveis por script comum mas com escrita elevada** seriam excluídas inteiras, e o script perderia uma leitura que ele tem no Roblox real.

**Opção B** (`{Default, Readable, Writable}`) emite um campo morto: `Readable == false` significa "trate como se não existisse", que é exatamente o que *não estar no schema* já expressa, com um campo a menos e sem terceiro estado. E ainda não resolve evento/callback.

### Adotado

```luau
-- em src/runtime/Instance.luau, reexportado por src/runtime/init.luau
export type MemberKind = "Property" | "Event" | "Callback"

export type MemberDescriptor = {
    Kind: MemberKind,
    Default: unknown,   -- JÁ PARSEADO pelo gerador (número/bool/string reais), nunca a string bruta do dump
    ReadOnly: boolean,  -- do ponto de vista de um Script/LocalScript comum
}

export type ClassSchema = { [string]: MemberDescriptor }
```

`Kind` existe por um fato do dump, não por elegância: **1087 `Event` + 18 `Callback`** precisam morar no mesmo espaço de nomes que as `Property` (o `__index` de uma Instance não distingue), mas se comportam diferente na escrita — evento erra com *"is an event of X and cannot be reassigned"* (a aproximação que `Instance.luau` já usa para os 5 sinais fixos), enquanto `Callback` (`bindableFunction.OnInvoke = f`) é **assinável por design**. Um `ReadOnly` booleano sozinho daria a mensagem errada para evento e o comportamento errado para callback.

Renomeio deliberado de `PropertyDescriptor` (nome provisório em `task-runtime-018`) para **`MemberDescriptor`**: um tipo que descreve evento e callback não pode se chamar "Property". Custo zero — `task-runtime-018` ainda não virou código. Pelo mesmo motivo, `ClassDescriptor.Properties` → **`ClassDescriptor.Schema`**, coerente com `ClassSchema`/`SetClassSchema`.

### Regra de emissão do gerador (a projeção dos 3 eixos do dump em 2 estados)

Para cada membro `Property`/`Event`/`Callback` que a classe **declara** (nunca os herdados — o achatamento é do `ClassRegistry`):

| Condição no dump | Resultado |
|---|---|
| tag `NotScriptable` **OU** `Security.Read ~= "None"` **OU** tag `WriteOnly` | **excluído do schema** — para um script comum esse membro não existe |
| tag `ReadOnly` **OU** `Security.Write ~= "None"` | incluído, `ReadOnly = true` |
| `Kind == "Event"` | incluído, `ReadOnly = true` (sempre) |
| `Kind == "Callback"` | incluído, `ReadOnly = false` |
| resto | incluído, `ReadOnly = false` |

Justificativa da projeção: os três eixos independentes do dump (`Security{Read,Write}`, tag `ReadOnly`, tag `NotScriptable`) colapsam **sem perda observável** em duas categorias porque o LuauBench não simula identidade nem `Capabilities` — não existe thread com `PluginSecurity` aqui. Divergência declarada: um plugin ou CoreScript real veria mais superfície do que o LuauBench expõe. Isso é uma escolha de escopo, não um bug.

### Princípio do gerador em caso de dúvida: **incluir**

Um schema permissivo demais falha por omissão (deixa passar um typo — a divergência que já existe hoje). Um schema restritivo demais falha por comissão (**quebra código válido do usuário com um erro barulhento**). O segundo é muito pior. Consequências diretas:

- **`Deprecated` (157 propriedades) entra no schema.** Excluir faria `part.BrickColor` errar em código legado que funciona no Roblox real. Distinção que a regra 03 pede: *entrar no schema* (o nome existe, ler não erra) ≠ *implementar comportamento* (não é feito). O gerador lista as deprecated emitidas no relatório.
- **`Hidden` (926) entra no schema.** Tag independente de `NotScriptable`; a leitura do LuauBench é que `Hidden` esconde do Property window do Studio, não do script. **Não confirmado** — vai para a tarefa de pesquisa; incluir é o lado seguro enquanto isso.

### `Default` parseado por `ValueType`

O gerador traduz a string do dump (sempre string, confirmado 09-04) por `ValueType.Category`:

| `ValueType.Category` | `Default` emitido |
|---|---|
| `Primitive` (`bool`/`int`/`int64`/`float`/`double`/`string`) | valor Luau real (`true`, `100`, `16`, `"Block"`…) |
| `Class` | **sempre `nil`** — 100% dos casos são sentinela `__api_dump_*` (confirmado 09-04) |
| `Enum` | `nil` **nesta fase** (não há `Enum` simulado; emitir a string mentiria: `part.Shape == Enum.PartType.Block` falharia) |
| `DataType` (Vector3/CFrame/Color3/UDim2/…) | `nil` **nesta fase** (não há tipos de valor simulados) |
| qualquer sentinela `__api_dump_*` | `nil` |

Os dois `nil` "desta fase" são **divergência declarada**: `part.Size` devolve `nil` em vez de `Vector3.new(4,1,2)`. O gerador emite no relatório a contagem e a lista dessas propriedades por classe, para que a dívida seja mensurável. Impacto na leva 1 é baixo: as classes escolhidas são dominadas por primitivos e por `Class` (que já é `nil` de verdade).

---

## Decisão 4 — Como `task-runtime-018` entra, e o buraco que ela abriria sozinha

**Resposta curta: o schema entra na primeira leva. Não há "primeira leva sem schema".** Mas ela **não pode entrar sozinha** — e essa é a descoberta mais importante deste desenho.

### O buraco: `__index` não resolve filho por nome

`InstanceMeta.__index` (Instance.luau:493-539) resolve, nesta ordem: `ClassName`/`Name`/`Parent` → sinais fixos → métodos base → métodos de classe → `data.properties[key]`. **Não existe nenhuma busca entre os filhos.**

No Roblox real, `ReplicatedStorage.Modules.Combat` é o padrão mais frequente do ecossistema inteiro: acesso a membro que resolve para um **filho** quando não é membro da classe. Hoje o LuauBench devolve `nil` — divergência silenciosa, já ruim.

Ligar o modo estrito de `task-runtime-018` **sem** resolver isso transforma essa divergência silenciosa em **erro barulhento em código perfeitamente válido**: `ReplicatedStorage.Modules` passaria a erguer `"Modules is not a valid member of ReplicatedStorage"`. Seria um regresso, não um avanço — e a primeira leva de `services` é exatamente o que ligaria o modo estrito.

### Decisão: duas tarefas de `runtime`, nesta ordem

1. **`task-runtime-021` (nova) — resolução de filho por nome.** Ganho puro no modo leniente de hoje (`nil` → o filho), testável sozinha, sem depender de schema nenhum. Pré-requisito estrito de 018.
2. **`task-runtime-018` (existente) — schema/modo estrito**, com o formato da Decisão 3 e as extensões da Decisão 6.

### Ordem final de `__index` (contrato fechado)

```
1. ClassName / Name / Parent
2. sinais fixos de Instance (Changed, ChildAdded, ChildRemoved, AncestryChanged, Destroying)
3. métodos base de Instance (tabela Methods)
4. métodos da classe concreta (data.classMethods)
5. classSchema ~= nil  E  classSchema[key] ~= nil  ->  return data.properties[key]
      (pode ser nil legitimamente — é o caso que motivou o schema inteiro)
6. classSchema == nil  E  data.properties[key] ~= nil  ->  return data.properties[key]   (leniente)
7. FindFirstChild(key) não-recursivo  ->  devolve o filho se existir            <- NOVO (021)
8. classSchema ~= nil -> ERRO `{key} is not a valid member of {ClassName} "{GetFullName()}"`
   classSchema == nil -> return nil (leniente, comportamento de hoje)
```

Membro vence filho (passos 5/6 antes do 7): é a semântica do Roblox — `workspace.Name` é a propriedade, mesmo havendo um filho chamado `Name`; `FindFirstChild("Name")` é a saída para o filho. **Assumida, não confirmada nesta sessão** — vai para a tarefa de pesquisa, com a ordem documentada no ponto exato do código (mesmo protocolo que `task-runtime-002` usou para a ordem de eventos de reparenting).

### Ordem final de `__newindex`

```
1. Parent -> setParent
2. Name -> setName
3. ClassName -> ERRO (string confirmada: "Unable to assign property ClassName. Property is read only")
4. sinal fixo -> ERRO (aproximação de boa-fé, já em uso)
5. método base -> ERRO (idem)
6. método de classe -> ERRO (idem)
7. classSchema ~= nil e schema[key] ~= nil:
      Kind == "Event"                -> ERRO "... is an event of {ClassName} and cannot be reassigned"
      Kind == "Property" e ReadOnly  -> ERRO "Unable to assign property {key}. Property is read only" (CONFIRMADA)
      senão                          -> properties[key] = value + Changed:Fire(key)
8. classSchema ~= nil e fora do schema -> ERRO "is not a valid member of"
9. classSchema == nil -> properties[key] = value + Changed:Fire(key)   (leniente, hoje)
```

Nota: escrever sobre um nome que hoje é **filho** e não membro (`rs.Modules = 1`) cai em 8 e erra — coerente com o Roblox real, que também não deixa criar membro por atribuição.

### Por que o schema pode ser gradual sem risco

`ClassSchema` é **opt-in por classe**: `ClassDescriptor.Schema == nil` ⇒ instância leniente. Isso já estava no desenho de 018 e é o que permite:
- classes geradas da leva 1 → estritas;
- raiz do `DataModel` (criada por `runtime` fora do registry) → leniente;
- instâncias de `NewBase` direto nos specs → lenientes, todos os testes atuais intactos.

Não existe interruptor global. Cada classe fica estrita no momento em que é gerada, e nenhuma outra é afetada.

---

## Decisão 5 — Escopo da primeira leva

Critério de corte: **o mínimo que faz um projeto Rojo real carregar e um script de servidor rodar de ponta a ponta**, priorizado pelo uso medido do `testador` e pela regra 03, **excluindo tudo que exija tipos de valor (`Vector3`/`CFrame`/`TweenInfo`) ou `Enum`** — que são um sistema próprio e não cabem aqui.

### Classes cobertas (com schema, registro e comportamento)

| Grupo | Classes | Por quê |
|---|---|---|
| Base | `Instance` (abstrata, só schema) | fornece `Archivable` e o resto dos membros de `Object`/`Instance` ao achatamento; sem ela o modo estrito erraria em membro válido |
| Contêineres da árvore Rojo | `ReplicatedStorage`, `ServerStorage`, `ServerScriptService`, `ReplicatedFirst`, `StarterPack`, `Folder` | `ReplicatedStorage` é o #1 medido (296); `Folder` está em todo `.project.json` |
| GUI/Player containers | `StarterGui` (+ `BasePlayerGui`), `StarterPlayer` (+ `StarterPlayerScripts`, `StarterCharacterScripts`) | regra 03 prioridade 1; `StarterGui.Superclass == "BasePlayerGui"` **[verificado 09-05]** |
| Scripts | `LuaSourceContainer` (abstrata), `BaseScript` (abstrata), `Script`, `LocalScript`, `ModuleScript` | **`cli` não consegue montar a árvore sem elas** — bloqueio duro |
| Mundo | `Workspace` (+ `WorldRoot`, `Model`, `PVInstance` — fecho automático) | `workspace` é global obrigatório; `Workspace.Superclass == "WorldRoot"` **[verificado 09-05]** |
| Ambiente | `Lighting` | contêiner presente em todo projeto; só dados, nenhum render |
| Comportamento real | `RunService` | #2 medido (196), e é a ponte com o `Scheduler` |
| Comportamento mínimo | `Players` | #3 medido (154); custa pouco e desbloqueia todo bootstrap |

≈ 22 classes, ~15 arquivos gerados novos por rodada do gerador. Cabe numa leva.

### Manifesto completo — as outras 894

O `Manifest.luau` cobre **as 916**, com `{Superclass, IsService, IsAbstract, Covered}` e nada mais. É leve (~920 linhas) e serve a um propósito único e não-negociável (regra 03: "Service não coberto ainda não é stub silencioso"): **distinguir três erros que hoje seriam um só.**

| Situação | Mensagem |
|---|---|
| `Instance.new("Frmae")` — não está no dump | `Unable to create an Instance of type "Frmae"` — família Roblox, **aproximação de boa-fé** (string real não confirmada), comentada no código |
| `Instance.new("Workspace")` — `NotCreatable` | mesma mensagem — é o que o Roblox real faz para classe não-criável |
| `Instance.new("Frame")` — no dump, ainda não simulada | `[LuauBench] Frame exists in the Roblox API Dump (0.737.0.7371584) but is not simulated by LuauBench yet` |
| `workspace:Raycast(...)` — método no dump, sem implementação | `[LuauBench] Workspace:Raycast() exists in the Roblox API Dump but is not simulated by LuauBench yet` |

**Regra de idioma dos erros** (extensão da decisão já tomada na revisão (3) do runtime): erro com contraparte no Roblox real usa a família/formato do Roblox, em inglês, sem prefixo. Erro **sem** contraparte real — só existe porque o LuauBench é incompleto — usa inglês **com prefixo `[LuauBench]`**, para nunca ser confundido com uma mensagem do motor. Erro de engenharia interna (uso errado da API por `services`/`cli`) continua em português.

### Levas seguintes (registradas, não construídas)

- **Leva 2 — data managers (o caso de uso central do usuário):** `Players` completo + `Player`; `DataStoreService` + `GlobalDataStore`/`DataStore`/`OrderedDataStore` em memória; `game:BindToClose` (ver Riscos); `HttpService` (`JSONEncode`/`JSONDecode`/`GenerateGUID` reais via `@lune/serde`; `RequestAsync`/`GetAsync` como decisão de segurança própria — regra 00 proíbe dar rede irrestrita ao script); `CollectionService`. Isto é o que faz o cenário `datastore-profilestore-pattern.scenario.luau` sair de `[SKIP]`.
- **Leva 3 — tipos de valor:** `Vector3`/`Vector2`/`CFrame`/`Color3`/`UDim`/`UDim2`/`TweenInfo` + `Enum`/`EnumItem` gerados dos 629 enums do dump; só então `TweenService` e os `Default` de `DataType`/`Enum` deixam de ser `nil`.

---

## Módulos

### Território `services` — ferramentas (dev-time)

- **`tools/api-dump.lock.json`** — versão fixada do dump. Dados na Decisão 2. Sem código.

- **`tools/coverage.luau`** — lista de classes-alvo, **editada à mão**; a única entrada humana do gerador.
  ```luau
  --!strict
  -- Classes que o gerador deve emitir. O FECHO de superclasses é calculado automaticamente
  -- pelo gerador — não liste WorldRoot/Model/PVInstance aqui, eles entram sozinhos.
  local Coverage: { string } = { "Instance", "ReplicatedStorage", ..., "RunService", "Players" }
  return Coverage
  ```
  - Depende de: nada. Usado por: `tools/generate-services.luau`.

- **`tools/generate-services.luau`** — o gerador. Script Lune executável (`lune run tools/generate-services`), **nunca** requerido por `src/`.
  ```luau
  -- Pipeline, na ordem:
  -- 1. lê tools/api-dump.lock.json
  -- 2. baixa (net.request) para .cache/api-dump/<commit>.json se ausente; valida sizeBytes+sha256, aborta se divergir
  -- 3. serde.decode("json", ...) -> { Classes, Enums, Version }
  -- 4. valida Version == 1 (esquema); aborta com erro claro se o esquema mudou
  -- 5. calcula o fecho de superclasses de tools/coverage.luau (para em "Instance"; ignora "Object")
  -- 6. emite src/services/generated/Manifest.luau (as 916)
  -- 7. emite src/services/generated/classes/<X>.luau para cada classe do fecho
  -- 8. emite src/services/generated/Index.luau (requires literais — o Lune não faz require dinâmico)
  -- 9. imprime RELATÓRIO: deprecated emitidas, defaults não representáveis por classe,
  --    membros de Object/Instance não cobertos por runtime/Instance.luau, classes puladas
  ```
  - Depende de: `@lune/fs`, `@lune/net`, `@lune/serde`, `@lune/process` — todos **[verificados 09-05]**. Nunca de `src/runtime/` nem de `src/services/` (exceto `tools/coverage.luau`).
  - Usado por: humano/`coder-services`, jamais por `luaubench run`.

### Território `services` — código de produção

- **`src/services/Types.luau`** — módulo folha, só tipos. Existe para quebrar o ciclo `generated/classes/X` → `ClassBuilder` → `generated/Index` → `generated/classes/X`.
  ```luau
  --!strict
  local Runtime = require("../runtime")

  -- O que o gerador emite por classe. Espelha o dump 1:1, sem comportamento.
  export type GeneratedClass = {
      ClassName: string,
      Superclass: string,             -- já normalizado (Object -> para em Instance)
      IsService: boolean,             -- tag de classe "Service"
      IsAbstract: boolean,            -- tag de classe "NotCreatable"
      Schema: Runtime.ClassSchema,    -- Property/Event/Callback que ESTA classe declara
      MethodNames: { string },        -- Function que ESTA classe declara
  }

  -- O que o autor humano escreve por classe. Nunca gerado.
  export type Behavior = {
      Methods: { [string]: unknown }?,                   -- chaves DEVEM estar em GeneratedClass.MethodNames
      Initialize: ((instance: Runtime.Instance) -> ())?, -- roda DEPOIS do Initialize gerado
  }

  export type BootstrapOptions = {
      scheduler: Runtime.Scheduler,
      dataModel: Runtime.DataModel,
  }
  ```
  - Depende de: `../runtime` (só tipos). Usado por: todo o resto de `services`.

- **`src/services/Context.luau`** — o `Scheduler`/`DataModel` do processo corrente, para que o `Initialize` de uma classe (que só recebe `instance`) alcance o scheduler.
  ```luau
  --!strict
  -- Mesma invariante já documentada em ClassRegistry.luau: um processo por execução do
  -- LuauBench, sem reset. `cli` chama Set* uma vez, no bootstrap, antes de qualquer GetService.
  function Context.Set(options: Types.BootstrapOptions): ()
  function Context.GetScheduler(): Runtime.Scheduler  -- erra claro se Bootstrap não foi chamado
  function Context.GetDataModel(): Runtime.DataModel  -- idem
  function Context.IsSet(): boolean
  ```
  - Rejeitado: efeito colateral de `require` para popular o contexto — frágil, intestável, e o desenho do runtime já pagou o preço de contratos implícitos três vezes.
  - Depende de: `Types.luau`, `../runtime`. Usado por: `behavior/RunService.luau`, `init.luau`.

- **`src/services/ClassBuilder.luau`** — converte `GeneratedClass` + `Behavior` em `Runtime.ClassDescriptor`. É onde a invariante 1 da regra 00 deixa de ser regra de revisão e vira código.
  ```luau
  --!strict
  function ClassBuilder.Build(generated: Types.GeneratedClass, behavior: Types.Behavior?): Runtime.ClassDescriptor
  ```
  Faz, nesta ordem:
  1. **Valida que toda chave de `behavior.Methods` existe em `generated.MethodNames`.** Se não, erro alto no load: `método '{X}' não existe em '{Class}' segundo o Roblox API Dump {versão}` (português — é erro de engenharia do LuauBench, não observável pelo script). **Isto é a invariante "nenhum agente inventa superfície de API" verificada mecanicamente, uma vez por classe, no carregamento.**
  2. Para cada nome em `MethodNames` **sem** implementação, instala um stub que erra `[LuauBench] {Class}:{Method}() exists in the Roblox API Dump but is not simulated by LuauBench yet`. Regra 03: nunca stub silencioso, nunca `nil`.
  3. `table.freeze` na tabela de métodos (exigência de `Instance.SetClassMethods`).
  4. Compõe `Initialize`: nada gerado precisa criar Signals (ver Decisão 6 — quem cria é `ClassRegistry.new` ao semear o schema); o `Initialize` do descriptor é simplesmente `behavior.Initialize`, ou `nil`.
  5. Devolve `{ClassName, SuperClassName, IsAbstract, IsService, Methods, Schema, Initialize}`.
  - Depende de: `Types.luau`, `../runtime`. Usado por: `init.luau`.

- **`src/services/generated/Manifest.luau`** — GERADO. As 916 classes, leves.
  ```luau
  export type ManifestEntry = { Superclass: string, IsService: boolean, IsAbstract: boolean, Covered: boolean }
  local Manifest = {
      DumpCommit = "28360dea4b90b35dc3fe9f829baae64fb6c50e75",
      DumpVersion = "0.737.0.7371584",
      Classes = { --[[ 916 entradas ]] } :: { [string]: ManifestEntry },
  }
  ```
  - Usado por: `init.luau` (`Services.new`, `Services.IsKnownClass`, `Services.GetDumpVersion`).

- **`src/services/generated/classes/<ClassName>.luau`** — GERADO, um por classe do fecho. Devolve um `Types.GeneratedClass` **e** exporta o tipo Luau da classe.
  ```luau
  --!strict
  -- ARQUIVO GERADO ... NÃO EDITAR À MÃO
  local Runtime = require("../../../runtime")
  local Types = require("../../Types")

  -- Tipo público da classe. ValueType não representável nesta fase -> `unknown` (nunca `any`),
  -- o que obriga o consumidor a estreitar — honesto, e regra 01 respeitada.
  export type Workspace = Runtime.Instance & {
      Gravity: number,
      CurrentCamera: Runtime.Instance?,
      GlobalWind: unknown,  -- Vector3, não simulado nesta fase
      Raycast: (self: Workspace, origin: unknown, direction: unknown, params: unknown?) -> unknown,
  }

  local Generated: Types.GeneratedClass = {
      ClassName = "Workspace",
      Superclass = "WorldRoot",
      IsService = true,
      IsAbstract = true,   -- tag NotCreatable
      Schema = {
          Gravity = { Kind = "Property", Default = 196.2, ReadOnly = false },
          CurrentCamera = { Kind = "Property", Default = nil, ReadOnly = false },
          -- ...
      },
      MethodNames = { "Raycast", "BreakJoints", "MoveTo", --[[ ... ]] },
  }
  table.freeze(Generated.Schema)
  return Generated
  ```

- **`src/services/generated/Index.luau`** — GERADO. Mapa `ClassName -> GeneratedClass` com **requires literais** (o `require` do Lune resolve estaticamente; não há require dinâmico por string).

- **`src/services/behavior/<ClassName>.luau`** — À MÃO, só para classes que têm comportamento. Devolve um `Types.Behavior`.

- **`src/services/behavior/Index.luau`** — À MÃO. Mapa `ClassName -> Behavior`. Não é gerado de propósito: é a lista curada do que tem comportamento, e o gerador nunca deve poder apagá-la.

- **`src/services/init.luau`** — ponto de entrada público único. `cli` requer **só** este arquivo.
  ```luau
  --!strict
  export type BootstrapOptions = Types.BootstrapOptions

  -- Registra todas as classes cobertas no Runtime.ClassRegistry. Idempotente (guarda local):
  -- ClassRegistry.Register erra em duplicata e não tem reset.
  function Services.Register(): ()

  -- Register() + Context.Set(). É a única coisa que `cli` precisa chamar antes de GetService.
  function Services.Bootstrap(options: BootstrapOptions): ()

  -- O `Instance.new` que `cli` injeta em extraGlobals do Sandbox. Diferencia os 3 casos de erro
  -- da Decisão 5 — é aqui, e não em runtime, que "não existe no dump" ≠ "existe e não simulado".
  function Services.new(className: string, name: string?): Runtime.Instance

  function Services.IsKnownClass(className: string): boolean          -- está no dump?
  function Services.IsSimulatedClass(className: string): boolean      -- está coberta?
  function Services.GetDumpVersion(): { Commit: string, Version: string }
  ```

---

## Contrato entre territórios

### `runtime` → `services` (o que `services` consome; nada mais)

```luau
local Runtime = require("../runtime")

Runtime.ClassRegistry.Register(descriptor: Runtime.ClassDescriptor): ()
Runtime.ClassRegistry.new(className: string, name: string?): Runtime.Instance
Runtime.ClassRegistry.Get(className: string): Runtime.ClassDescriptor?
Runtime.ClassRegistry.IsRegistered(className: string): boolean
Runtime.Instance.GetPropertyRaw(instance, name): unknown
Runtime.Instance.SetPropertyRaw(instance, name, value): ()
Runtime.Signal.new<T...>(): Runtime.FireableSignal<T...>   -- (ver nota abaixo)
-- tipos: Runtime.Instance, Runtime.ClassDescriptor, Runtime.Scheduler, Runtime.DataModel,
--        Runtime.Signal<T...>, Runtime.Connection, Runtime.MemberKind, Runtime.MemberDescriptor,
--        Runtime.ClassSchema
```

Três consequências para o `runtime` (tarefas próprias, ver Divisão por território):

1. **`ClassDescriptor` ganha `Schema: ClassSchema?`** (task-runtime-018, renomeado de `Properties`).
2. **`init.luau` passa a reexportar `MemberKind`, `MemberDescriptor`, `ClassSchema`.** `SetClassSchema` **não** é reexportada — mesma decisão e mesma razão de `NewBase`/`SetClassChain`/`SetClassMethods`: `ClassRegistry.new` é o único chamador legítimo, na ordem que garante a validação.
3. **`init.luau` passa a reexportar o tipo `FireableSignal<T...>`** — `services` precisa disparar eventos de classe (`Players.PlayerAdded`), e hoje só `Signal<T...>` (sem `Fire`) é reexportado. Sem isso, `services` teria de fazer um cast cego. Tarefa de `coder-runtime`.

### `services` → `cli`

```luau
local Services = require("../services")

Services.Bootstrap({ scheduler = scheduler, dataModel = game })  -- PRIMEIRO, sempre
Services.new(className, name)          -- vira extraGlobals.Instance = { new = Services.new }
Services.IsKnownClass / IsSimulatedClass / GetDumpVersion
```

`cli` **nunca** requer `src/services/generated/**` nem `src/services/behavior/**` — só `require("../services")`.

**Source de Script:** `Script.Source` é `PluginSecurity` no dump, logo **excluída do schema** pela Decisão 3 — fiel ao Roblox, onde um script comum não lê `script.Source`. `cli` grava e lê o código-fonte por `Runtime.Instance.SetPropertyRaw(inst, "Source", texto)` / `GetPropertyRaw`, que **não passam pelo schema** (ver Decisão 6).

### Quem chama primeiro (sequência de bootstrap de `cli`)

```
1. local Runtime  = require("../runtime")
2. local Services = require("../services")
3. local scheduler = Runtime.Scheduler.new()
4. local game      = Runtime.DataModel.new()
5. Services.Bootstrap({ scheduler = scheduler, dataModel = game })   -- registra as classes
6. game:GetService("ReplicatedStorage") ... (populado a partir do .project.json)
7. Runtime.Sandbox.Run{ extraGlobals = { game = game,
                                         workspace = game:GetService("Workspace"),
                                         Instance = { new = Services.new },
                                         script = <a Instance do script> }, ... }
8. scheduler:Run(shouldContinue)
```

Passo 5 **antes** de qualquer `GetService` é invariante de `cli`, não imposta por `runtime` (que não conhece a ordem) — exatamente como o desenho do runtime já previa.

---

## Fluxo de dados

**Dev-time (raro, manual):**
```
Full-API-Dump.json @ 28360dea (8 MB, baixado por URL fixada por SHA, sha256 verificado)
   -> tools/generate-services.luau  (serde.decode, ~0,2s)
   -> fecho de superclasses de tools/coverage.luau
   -> src/services/generated/{Manifest, Index, classes/*}.luau  (committados)
   + relatório impresso (deprecated, defaults não representáveis, membros de Object descobertos)
```

**Runtime (todo `luaubench run`):**
```
require("../services")                    -- carrega .luau já compilado; zero JSON, zero I/O
   -> Services.Bootstrap
   -> para cada classe coberta: ClassBuilder.Build(generated, behavior)
        - valida behavior.Methods ⊆ MethodNames        (erro alto se inventarem membro)
        - completa MethodNames faltantes com stub-que-erra
   -> Runtime.ClassRegistry.Register(descriptor)
   -> cli popula a árvore a partir do .project.json:  ClassRegistry.new(className, name); .Parent = ...
        - ClassRegistry.new: resolveClassChain -> NewBase -> SetClassChain -> SetClassMethods
                             -> SetClassSchema -> semeia defaults + cria Signal por evento -> Initialize
   -> script do usuário vê: game.ReplicatedStorage.Modules.Combat, workspace.Gravity,
      RunService.Heartbeat:Connect(...), Instance.new("Folder")
```

---

## Decisão 6 — Extensões que `task-runtime-018` precisa absorver

Além do rename (`MemberDescriptor`/`ClassSchema`/`ClassDescriptor.Schema`), o schema traz três exigências que o desenho original de 018 não previa. Todas caem em `runtime`, todas são pequenas:

1. **`ClassRegistry.new` cria um `Signal.new()` fresco por instância para cada entrada com `Kind == "Event"`**, no mesmo passo em que semeia os defaults. Motivo: um `Signal` é por instância e não pode vir do `Default` (que é compartilhado por classe, numa tabela congelada). Fazer isso no runtime, uniformemente, evita que cada classe de `services` lembre de criar os próprios sinais — e torna um evento de classe indistinguível dos 5 sinais fixos do ponto de vista do script.
   `services` dispara via `Runtime.Instance.GetPropertyRaw(instance, "PlayerAdded") :: Runtime.FireableSignal<...>`.

2. **`GetPropertyRaw`/`SetPropertyRaw` NUNCA consultam o schema.** São a via de engenharia, abaixo do enforcement — é o que permite `services` instalar o `Heartbeat` do Scheduler sobre uma entrada `ReadOnly`, e `cli` guardar `Source` numa propriedade que o script não pode ler. Precisa estar escrito no código, não subentendido.

3. **`SetClassSchema` NÃO rejeita colisão com a superfície fixa de `Instance`** — diferente de `SetClassMethods`, que rejeita. Motivo: o schema de `Instance` legitimamente contém `Name`/`Parent`/`ClassName`/`Changed`, e `__index`/`__newindex` os tratam nos passos 1-2, antes de olhar o schema. A validação de `SetClassSchema` cobre só congelamento e forma (`Kind` válido, `ReadOnly` booleano).

E o achatamento do schema segue a mesma disciplina já construída para `Methods` em `ClassRegistry` (cadeia de trás para frente, classe mais concreta vence, cache lazy por `ClassName`, `table.freeze`). Os **19 pares de redeclaração real** confirmados no dump (`BoolValue.Changed` com assinatura diferente de `Object.Changed`, `CollectionService.AddTag` com um parâmetro a mais que `Instance.AddTag`) provam que essa política importa de verdade.

---

## Divisão por território

| Território | O que constrói | Contrato com o vizinho |
|---|---|---|
| `runtime` (`src/runtime/`) | **task-runtime-021** (novo): resolução de filho por nome em `__index`/`__newindex`. **task-runtime-018** (existente, ampliada): `MemberKind`/`MemberDescriptor`/`ClassSchema`, `SetClassSchema`, `ClassDescriptor.Schema`, modo estrito, semeadura de defaults, criação de Signal por evento. **task-runtime-022** (novo): reexportar `MemberKind`/`MemberDescriptor`/`ClassSchema`/`FireableSignal` em `init.luau`. | Continua sem conhecer nome de classe e sem ler o dump. Ganha a *capacidade* de aplicar um schema; quem produz o schema é `services`. |
| `services` (`src/services/` + `tools/generate-services.luau` + `tools/api-dump.lock.json` + `tools/coverage.luau`) | Gerador, manifesto, dados gerados por classe, `ClassBuilder`, `Context`, comportamento à mão, `init.luau` | Consome só `require("../runtime")`. Expõe a `cli` só `require("../services")`. |
| `cli` (`src/cli/`) | (fora desta leva) bootstrap na ordem acima, injeção de `Instance.new`/`game`/`workspace`, `Source` via `Get/SetPropertyRaw` | Nunca requer `generated/`/`behavior/`; nunca toca `tools/`. |

**`tools/` pertence a `coder-services`.** O gerador é indivisível do território que ele produz; `coder-cli` não escreve lá. Declarado para preservar a não-sobreposição da regra 05.

**Paralelismo real:** dentro de `services` as tarefas são **sequenciais** (mesmo território, mesmos arquivos). O paralelismo desta fase é *entre* territórios: `coder-runtime` (021/018/022) e `pesquisador` rodam ao lado de `coder-services`. Não existe um "coder-gerador" separado — mesmo agente, tarefas diferentes, uma de cada vez.

---

## Fidelidade vs. pragmatismo

Toda aproximação da primeira leva, explicitamente:

| Área | Fidelidade |
|---|---|
| Superfície de membro (nomes, tipos, escrituralidade, herança) | **Exata** — gerada do dump oficial, versão fixada, verificada por sha256 |
| Achatamento de herança | **Exato** — cadeia real do dump, classe mais concreta vence (19 casos reais de redeclaração cobertos) |
| Método no dump sem implementação | Superfície existe, chamada **erra alto e claro** com `[LuauBench]`. Nunca `nil`, nunca silencioso |
| Classe no dump não coberta | `Instance.new` erra distinguindo "não existe no Roblox" de "existe e não simulada" |
| Identidade / `Security` / `Capabilities` | **Não simuladas.** Membro `NotScriptable` ou `Security.Read ~= "None"` simplesmente não existe no LuauBench. Um plugin/CoreScript real veria mais |
| `Default` de `Enum` e `DataType` (Vector3/CFrame/…) | **`nil` nesta fase.** `part.Size` devolve `nil`, não `Vector3.new(4,1,2)`. Contado e listado no relatório do gerador |
| Propriedades `Deprecated` | **No schema** (ler/escrever não erra), **sem comportamento**. Excluir quebraria código legado válido |
| Propriedades `Hidden` | **No schema.** Leitura assumida ("esconde do Studio, não do script") — **não confirmada**, na tarefa de pesquisa |
| `Script.Source` | **Fora do schema** (é `PluginSecurity`) — fiel: script comum não lê `Source`. `cli` usa `Get/SetPropertyRaw` |
| `RunService.Heartbeat`/`Stepped` | Ligados ao Signal **real** do Scheduler (mesma instância, sem proxy). Mas o relógio é o do laço do LuauBench, não vsync 60Hz — divergência já registrada no desenho do runtime |
| `RunService.RenderStepped` | **Existe no schema e nunca dispara.** Sem render. Aliasar para `Heartbeat` foi **rejeitado**: fabricaria frames de render inexistentes e faria código de render rodar à toa |
| `RunService:IsServer()/IsClient()/IsStudio()` | **`true`/`false`/`false`** — o LuauBench se apresenta como **servidor rodando**. Escolha deliberada: o uso medido é dominado por lógica de servidor (ProfileStore, DataStore). Um `--client` futuro é tarefa própria, não implícito aqui |
| `Players.GetPlayers()` / `LocalPlayer` | `{}` / `nil`; `PlayerAdded`/`PlayerRemoving` existem e **nunca disparam**. É a verdade — não há jogadores. Não é stub: é o resultado correto de um mundo sem jogadores |
| `Workspace.Terrain` / `.CurrentCamera` | **`nil`** — `Terrain` puxaria `BasePart` inteira; `Camera` fica para a leva de render. Divergência declarada |
| `Lighting` | Todas as propriedades guardam e devolvem valor; **nada é renderizado**. `Lighting.Ambient = x` é um dado morto |
| Ordem membro-vence-filho em `__index` | **Assumida**, comentada no ponto exato do código, pendente de `pesquisador` — mesmo protocolo de `task-runtime-002` |
| Mensagem de `Instance.new` para classe inexistente | **Aproximação de boa-fé** na família Roblox; string real não confirmada |

---

## Riscos e decisões

- **Ligar o modo estrito antes da resolução de filho por nome quebraria todo projeto Rojo real.** É o risco número um deste desenho e a razão de `task-runtime-021` existir e preceder `task-runtime-018`. Se as duas forem despachadas fora de ordem, `ReplicatedStorage.Modules` passa a errar. **`revisor-runtime` deve reprovar 018 se 021 não estiver `done`.**
- **Schema incompleto erra por comissão.** Uma propriedade que o filtro excluiu por engano vira erro barulhento em código válido. Mitigações: princípio "em dúvida, incluir" (Decisão 3); relatório do gerador listando o que foi excluído e por quê; `Deprecated`/`Hidden` incluídos. Aceito com essas três redes.
- **`ClassBuilder` valida `behavior.Methods ⊆ MethodNames` no load, não em revisão.** É a invariante 1 da regra 00 virando código: um agente que inventar `DataStoreService:Foo()` recebe erro no `require`, não um comportamento fantasma aprovado por descuido. Custo: uma varredura por classe no bootstrap. Aceito.
- **Regenerar apaga trabalho manual, se alguém editar `generated/`.** Mitigação: cabeçalho em todo arquivo, diretório separado, e critério de revisão explícito (`revisor-services` reprova qualquer diff manual em `generated/`).
- **Upstream do dump pode sumir.** O *build* não depende (o gerado é committado); só a *regeração*. Mitigação prevista e não construída: anexar o dump ao GitHub Release.
- **`Version: 1` do esquema do dump pode mudar.** O gerador valida e **aborta** com erro claro se `Version ~= 1`, em vez de gerar lixo silenciosamente.
- **`.project.json` inválido** — território de `cli`. O que `services` garante: uma classe pedida por `cli` que não existe ou não é simulada produz erro nomeado e distinguível (Decisão 5), nunca `nil` silencioso, para que `cli` consiga apontar o nó problemático do projeto.
- **Script que trava (`while true do end`)** — risco já registrado e aceito no desenho do runtime; `services` não altera nada. `ClassBuilder` não introduz laço novo no caminho quente.
- **`game:BindToClose`** (necessário para ProfileStore, leva 2) é membro do `DataModel`, cuja implementação vive em `src/runtime/DataModel.luau`, e depende do ciclo de vida do `Scheduler`. **Decisão: fica em `runtime`**, como `GetService`/`FindService` já ficam — `DataModel`, como `Instance`, é a classe do Roblox que `runtime` codifica por ser estrutural. Tarefa de `coder-runtime` na leva 2, não de `services`.
- **`ClassRegistry` não tem reset** (invariante documentada). `Services.Register()` é idempotente por guarda local. Se um dia existir watch mode que invalide o cache de `require`, isso volta ao arquiteto — como a própria invariante já prevê.

---

## O que deliberadamente NÃO fazer agora

- **Não** gerar dados completos das 916 classes — só o fecho da cobertura. O manifesto leve cobre o resto.
- **Não** construir `Vector3`/`CFrame`/`Color3`/`UDim2`/`TweenInfo` nem `Enum`/`EnumItem` (629 enums). Leva 3.
- **Não** implementar `TweenService` — depende de `TweenInfo` + `Enum`, e são 14 usos medidos.
- **Não** implementar a classe `Player` nesta leva. `Players` entra com comportamento mínimo e honesto.
- **Não** dar rede ao script do usuário: `HttpService:RequestAsync`/`GetAsync` ficam para a leva 2 **com decisão de segurança própria** (regra 00 é explícita). `JSONEncode`/`JSONDecode`/`GenerateGUID` não tocam rede e entram lá sem essa discussão.
- **Não** criar `Workspace.Terrain` nem `Workspace.CurrentCamera`.
- **Não** simular `Security`/`Capabilities`/identidade de thread, nem a terceira família de erro (`"lacking capability ..."`).
- **Não** aliasar `RenderStepped` para `Heartbeat`.
- **Não** gerar os `Initialize` — comportamento é sempre à mão (regra 03: o dump dá o "o quê", nunca o "como").
- **Não** commitar o `Full-API-Dump.json`.
- **Não** rodar o gerador em CI de release nem em `luaubench run`.
- **Não** criar um agente separado para o gerador — `coder-services` cuida de tudo, em tarefas sequenciais.

---

## Pendências para o `pesquisador` (uma tarefa, quatro perguntas)

Nenhuma bloqueia o início; todas precisam ser respondidas antes de `revisor-services` aprovar a leva.

1. Ordem **membro vs. filho** em `__index` no Roblox real, e o que acontece com colisão (`workspace.Name` havendo um filho chamado `Name`). Escrita sobre nome que é filho.
2. String exata de `Instance.new` para classe inexistente e para classe `NotCreatable`.
3. Propriedade com tag `Hidden` (sem `NotScriptable`) é acessível por script comum?
4. `script.Source` lido de um `Script` comum: erra com "is not a valid member of", com mensagem de identidade/capability, ou devolve string vazia? E `RunService.RenderStepped` no servidor real — existe, erra, ou existe e nunca dispara?

---

## Revisão pós-pesquisa 2026-09-05 — `Capabilities` e `RenderStepped`

Gatilho: `task-services-006`, relatório `.claude/agents-memory/pesquisa-member-vs-child-2026-09-05.md`. Duas contradições reais com este desenho (mais uma inconsistência interna encontrada ao reescrever a regra). Esta seção **substitui** os trechos listados em "Correções ao texto acima (4)"; o resto do desenho continua válido.

Os fatos desta seção foram **re-verificados por inspeção direta** nesta revisão, não herdados do relatório: o `Full-API-Dump.json` do commit fixado `28360dea` foi baixado de novo (8 006 149 bytes, bate com o lock) e o `content/en-us/scripting/capabilities.md` do `Roblox/creator-docs` foi baixado e lido. Marcados abaixo como **[verificado 09-05b]**.

### Pendências 1, 2 e 3: fechadas sem mudança

- **Membro vence filho** — **confirmado por fonte oficial** (`creator-docs`, `Instance.yaml`, seção `FindFirstChild`: *"When using the dot operator, properties take precedence over children if they share a name."*). A ordem de `__index` da Decisão 4 (membro nos passos 5/6, filho no 7) está certa. `task-runtime-021` segue como desenhada; o comentário no código deixa de dizer "assumido" e passa a citar a fonte.
- **Mensagem de `Instance.new`** — mantida como aproximação de boa-fé de alta confiança; o comentário "string não confirmada byte-a-byte" continua obrigatório.
- **`Hidden`** — **confirmado acessível por script comum** (3 fontes convergentes, incl. `Attachment.Position` no próprio dump). As 926 propriedades continuam entrando no schema. Nenhuma mudança.

---

### A. `Capabilities` é um quarto eixo do dump, e a Decisão 3 não o enxergava

#### A.1 Formato real do campo [verificado 09-05b]

`Capabilities` **não tem um formato só** — depende do `MemberType`:

| `MemberType` | Formato de `Capabilities` | Ocorrências | Sem a chave |
|---|---|---|---|
| `Property` | objeto `{Read: {string}}` ou `{Read: {string}, Write: {string}}` | 2464 só com `Read`, 353 com `Read`+`Write` | 1221 |
| `Function` | **array plano** `{string}` | 1780 | 1478 |
| `Event` | **array plano** `{string}` | 636 | 451 |
| `Callback` | **array plano** `{string}` | 13 | 5 |

Consequências para o gerador, todas obrigatórias:
- a chave `Capabilities` pode **estar ausente** (não `null`) — mesma disciplina já exigida para `Tags`;
- em `Property`, a subchave `Write` pode estar ausente com `Read` presente;
- tipar isso em Luau exige duas formas distintas (`{Read: {string}?, Write: {string}?}` vs `{string}`), não uma só;
- **múltiplos nomes na lista são conjunção (E), não disjunção** — a doc oficial descreve o erro como *"the first capability that is missing"*, e `Workspace.Gravity` tem `Write: ["Basic","Physics"]` (precisa dos dois). O gerador testa **interseção** com o conjunto reservado, o que é correto sob semântica E.

40 nomes distintos de capability aparecem no dump [verificado 09-05b].

#### A.2 A leitura ingênua ("qualquer nome fora de `Basic` é restritivo") está errada e seria catastrófica

O relatório de pesquisa já suspeitava disso; a inspeção fecha a questão com contraexemplos que são exatamente as classes da leva 1 [verificado 09-05b]:

| Membro | `Security` | `Capabilities` | Acessível por script comum? |
|---|---|---|---|
| `Lighting.Ambient` (e as outras 22 de `Lighting`) | `None`/`None` | `Read: ["Environment"]` | óbvio que sim |
| `Players.GetPlayers` / `Players.PlayerAdded` | `None` | `["Players"]` | óbvio que sim |
| `Instance.Clone` | `None` | `["CreateInstances"]` | óbvio que sim |
| `Player.Kick`, `Players.BanAsync` | `None` | `["Players","Consequences"]` | óbvio que sim |
| `MessagingService.PublishAsync` | `None` | `["ServerCommunication"]` | óbvio que sim |
| `Workspace.Gravity` | `None`/`None` | `Write: ["Basic","Physics"]` | óbvio que sim |

Excluir por "não é `Basic`" apagaria **`Lighting` inteiro, `Players` inteiro e quase todo `StarterPlayer`** do schema — a falha por comissão mais cara possível. Rejeitado.

#### A.3 O critério correto: capability **não concedível**, não "capability não-`Basic`"

A doc oficial (`creator-docs`, `content/en-us/scripting/capabilities.md`) enumera **as capabilities que existem para serem concedidas a um container sandboxed** — 41 nomes, em quatro grupos (`Execution control`, `Instance access control`, `Script functionality control`, `Engine API access control`) [verificado 09-05b]. E declara que o sistema é *"all-or-nothing"* por padrão: um script **não** sandboxed detém implicitamente o conjunto concedível inteiro.

Cruzando os 40 nomes do dump com os 41 nomes da doc [verificado 09-05b]:

- **no dump e na doc:** 37 nomes → **concedíveis**, um script comum os tem, membro **entra** no schema.
- **na doc e não no dump:** `AccessOutsideWrite`, `LoadString`, `RunClientScript`, `RunServerScript` — são capabilities de *script*, não de membro. Coerente: nunca aparecem em membro.
- **no dump e NÃO na doc:** `InternalTest`, `PluginOrOpenCloud`, `RemoteCommand` — **três nomes, e só três.**

Esses três não são categorias de sandboxing: são **portões de identidade/motor**, fora do conjunto que um script comum detém. Confirmado empiricamente para `PluginOrOpenCloud` pela citação literal de erro real do relatório (`"The current thread cannot read 'Source' (lacking capability PluginOrOpenCloud)"`), e coerente com o que `InternalTest` (56 funções internas: `CustomLog.GetLogPath`, `AnalyticsService.GetDurationLoggerTimestamp`) e `RemoteCommand` (`RemoteCommandService`) nomeiam.

Nota sobre a lista sugerida no relatório do pesquisador: `Plugin`, `RobloxScript`, `RobloxEngine` e `CapabilityControl` **não** servem como reservadas — os três primeiros têm **zero ocorrências** no campo `Capabilities` deste dump (são valores do eixo `Security`, não deste), e `CapabilityControl` **está** na doc, é concedível (`Instance.Sandboxed`/`Instance.Capabilities` são escritos por script comum). A lista fechada é a de três nomes acima.

#### A.4 Regra de emissão do gerador — versão que substitui a tabela da Decisão 3

Definições, para um membro que a classe **declara** (herdado é achatamento do `ClassRegistry`, não do gerador):

```
required_read  = Property ? (Capabilities.Read  ?? {}) : (Capabilities ?? {})
required_write = Property ? (Capabilities.Write ?? {}) : (Capabilities ?? {})
Reserved       = { "InternalTest", "PluginOrOpenCloud", "RemoteCommand" }   -- de tools/capabilities.lock.json
```

Avaliada **em ordem**, primeiro casamento vence:

| # | Condição no dump | Resultado |
|---|---|---|
| 1 | um nome em `required_read ∪ required_write` que **não está** em `grantable ∪ reserved` | **ABORTA a geração** — nomeia a capability e os membros afetados |
| 2 | tag `NotScriptable` **OU** `Security.Read ~= "None"` **OU** tag `WriteOnly` | **excluído do schema** |
| 3 | `required_read ∩ Reserved ~= {}` | **excluído do schema** ← NOVO |
| 4 | `required_write ∩ Reserved ~= {}` (com `read` livre) | incluído, `ReadOnly = true` ← NOVO |
| 5 | tag `ReadOnly` **OU** `Security.Write ~= "None"` | incluído, `ReadOnly = true` |
| 6 | `Kind == "Event"` | incluído, `ReadOnly = true` (sempre) |
| 7 | `Kind == "Callback"` | incluído, `ReadOnly = false` |
| 8 | resto | incluído, `ReadOnly = false` |

O passo 4 tem **zero casos neste dump** [verificado 09-05b] — está especificado por robustez, para que uma versão futura do dump não caia num buraco da regra. O passo 1 é a rede que impede que um nome novo de capability entre calado: abortar é o mesmo protocolo já usado para `Version ~= 1` (Decisão 2), e o gerador é dev-time e raro — o custo de um humano classificar um nome novo é baixo, o de uma exclusão silenciosa errada é alto.

**Impacto medido do eixo novo [verificado 09-05b]:** 87 membros excluídos no dump inteiro (de ~8 400 que têm o campo). Na leva 1, **exatamente quatro**:

| Membro | Motivo |
|---|---|
| `Script.Source` | `Read: ["PluginOrOpenCloud"]` |
| `ModuleScript.Source` | idem |
| `RunService.Misprediction` (Event) | `["Basic","PluginOrOpenCloud"]` |
| `RunService.FrameNumber` | `Read: ["Basic","InternalTest"]` |

`LocalScript.Superclass == "Script"` [verificado 09-05b] — `LocalScript` herda `Source` e cai na mesma exclusão pelo achatamento. Nada a fazer.

#### A.5 Onde a lista vive: `tools/capabilities.lock.json` (arquivo novo)

Proveniência diferente da do dump (doc, não dump) ⇒ arquivo próprio, ao lado de `tools/api-dump.lock.json`:

```json
{
  "source": "Roblox/creator-docs",
  "path": "content/en-us/scripting/capabilities.md",
  "url": "https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/scripting/capabilities.md",
  "fetchedAt": "2026-09-05",
  "grantable": ["AccessOutsideWrite","Animation","AssetCreateUpdate","AssetManagement","AssetRead","Audio","AvatarAppearance","AvatarBehavior","Basic","CSG","CapabilityControl","Capture","Chat","Consequences","CreateInstances","DataStore","DynamicGeneration","Environment","Groups","Input","LegacySound","LoadOwnedAsset","LoadString","LoadUnownedAsset","Logging","Material","Monetization","Network","Physics","PlatformAvatarEditing","Players","PromptExternalPurchase","RemoteEvent","RunClientScript","RunServerScript","ScriptGlobals","SensitiveInput","ServerCommunication","Social","Teleport","UI"],
  "reserved": ["InternalTest","PluginOrOpenCloud","RemoteCommand"],
  "note": "grantable = capabilities que a doc oficial enumera como concedíveis a um container sandboxed; um script NÃO sandboxed as detém todas (sistema all-or-nothing). reserved = nomes que aparecem no Capabilities do dump mas NÃO na doc — portões de identidade/motor que nenhum script comum detém. Classificar um nome novo é decisão humana explícita: o gerador aborta em vez de adivinhar."
}
```

A URL aponta para `main` (não fixada por SHA) de propósito: a reprodutibilidade vem **deste arquivo committado**, não do fetch — o gerador **nunca** baixa a doc, só lê o `.json`. Divergência declarada: se a Roblox adicionar uma capability concedível nova, o gerador aborta até um humano atualizar este arquivo; é o comportamento desejado.

#### A.6 O que **não** muda

O LuauBench continua **sem simular `Capabilities` em runtime**: não há identidade de thread, não há container sandboxed, não existe a família de erro `"lacking capability ..."`. O que mudou é só que o **gerador dev-time lê o campo para decidir emissão**. Um plugin/CoreScript/thread OpenCloud real continua vendo mais superfície que o LuauBench — divergência já declarada, agora com o eixo certo.

---

### B. `RunService.RenderStepped`: LuauBench simula a **produção (RCC)**, não o bug do Studio

#### B.1 Decisão

**Conectar em `RunService.RenderStepped` erra no LuauBench.** "Existe e nunca dispara" era o comportamento de um **bug reconhecido do Studio** (ticket aberto pela Roblox, citado no relatório), não o do Roblox real — e o LuauBench já se declara `IsStudio() == false` e `IsServer() == true`. Manter o comportamento antigo seria imitar exatamente o ambiente que a própria simulação diz não ser. A regra 00 ("fidelidade com o Roblox real é o objetivo") decide sozinha aqui.

#### B.2 Isto **não** abre o escopo de contexto client/server

O LuauBench não modela `RunContext` e **não vai modelar nesta leva**. Ele é um servidor, sempre — decisão já tomada e já declarada. Sendo o contexto uma **constante deste build**, "erra ao conectar" é um valor fixo, não uma consulta a um subsistema que não existe. Nada de client/server entra agora.

Limitação aceita e declarada: APIs client-only em geral (`UserInputService`, `GuiService`, `Players.LocalPlayer` e afins) **não** são varridas nem tratadas nesta leva — só `RenderStepped`, que é o único caso da leva 1 com evidência. Quando um `--client` existir, é a `message` do mecanismo abaixo que passa a ser condicional, num ponto só.

#### B.3 Mecanismo: `src/services/RejectingSignal.luau` (módulo novo)

Extensão do LuauBench, portanto **fora do namespace simulado de qualquer classe real** (regra 00) — vive em módulo próprio de `services`, nunca em `runtime` (que não pode conhecer classe por nome) e nunca em `generated/`.

```luau
--!strict
-- Um Signal que existe, é legível como propriedade, e RECUSA conexão.
-- Serve à superfície client-only enquanto o LuauBench é servidor fixo.

-- Estruturalmente um Runtime.Signal<...>: Connect/Once/Wait erram com `message`
-- em nível 2 (culpa o call site do script do usuário, convenção de Instance.luau);
-- DisconnectAll é no-op.
function RejectingSignal.new(message: string): Runtime.Signal<...unknown>
```

`ConnectParallel` não existe no `Signal` do runtime e **não** é inventado aqui. O tipo de retorno é `Signal<...unknown>` de propósito: o valor é guardado por `SetPropertyRaw`, que recebe `unknown` — não há alvo tipado a satisfazer, então não é preciso pack genérico nem cast cego. Se o Luau ainda assim recusar a construção, passar por `:: unknown ::` é aceitável **com comentário**; `any` continua proibido.

`behavior/RunService.luau` instala no `Initialize`, sobre a entrada do schema, via `Runtime.Instance.SetPropertyRaw(instance, "RenderStepped", RejectingSignal.new(...))`. A ordem funciona sem nada novo: `ClassRegistry.new` semeia o `Signal` do evento **antes** de chamar `Initialize` (Decisão 6), então o `Initialize` só sobrescreve.

**Ler** `RunService.RenderStepped` **não erra** — devolve o objeto. É `:Connect`/`:Once`/`:Wait` que erram. É o modelo honesto do que o motor checa (a mensagem real diz "event can only be **used** from local scripts", e a checagem é na conexão).

Mensagem, pela regra de idioma dos erros (Decisão 5 — tem contraparte real ⇒ família Roblox, inglês, **sem** prefixo `[LuauBench]`):

```
RenderStepped event can only be used from local scripts
```

Comentada no código como **aproximação de boa-fé**: o texto vem de bug trackers de 2014–2024 (Anaminus/roblox-bug-tracker #636 e #365, ROBLOX/Studio-Tools #14), não de um teste ao vivo em 2026 — mesmo protocolo da mensagem de `Instance.new`.

#### B.4 O que deliberadamente **não** recebe o mesmo tratamento

- **`RunService.PreRender`** (o nome moderno de `RenderStepped`, presente no dump [verificado 09-05b]): continua **existindo e nunca disparando**. Não há evidência de que ele erre no servidor, e o princípio da Decisão 3 vale aqui igual — errar sem confirmação é falhar por **comissão** (quebra código válido), o pior dos dois lados. Vai para as pendências novas.
- **`RunService:BindToRenderStep`/`UnbindFromRenderStep`**: continuam com o stub `[LuauBench] ... is not simulated by LuauBench yet` do `ClassBuilder`. Já erram alto; a única diferença seria o texto, e não há evidência para trocar.
- **Aliasar `RenderStepped` para `Heartbeat`**: continua rejeitado. Esta decisão é o oposto disso.

---

### C. Consistência achada ao reescrever a regra: o filtro nunca era aplicado a `MethodNames`

A Decisão 3 dizia *"para cada membro `Property`/`Event`/`Callback`"*. `MethodNames` vem dos membros `Function`, e **nenhum filtro era aplicado a eles** — `Players.CreateLocalPlayer` (`LocalUserSecurity`), `RunService:Pause`/`Run` (`PluginSecurity`), `Workspace:Set3dRenderingEnabled` (`RobloxScriptSecurity`) entrariam em `MethodNames` e ganhariam um stub `[LuauBench] ... not simulated yet`, sugerindo ao usuário que um dia serão simulados. No Roblox real um script comum **não vê** esses métodos: erram como membro inexistente.

**Correção:** os passos 1, 2 e 3 da tabela de A.4 valem também para `Function` → o membro simplesmente **não entra em `MethodNames`**. Os passos 4–8 não se aplicam (método não tem escrituralidade).

**Impacto medido [verificado 09-05b]:** dump inteiro — 1502 funções mantidas, 1691 excluídas por `Security`, 65 por capability reservada. Leva 1 — 143 mantidas, **60 excluídas por `Security`, 0 por capability**; as maiores contribuições são `RunService` (17 de 28), `Workspace` (11 de 18), `WorldRoot` (11 de 38), `Players` (12 de 36).

Consequência observável: `RunService:Pause()` erra `Pause is not a valid member of RunService` em vez de `[LuauBench] ... not simulated yet`. É a mensagem correta — é o que o Roblox real diz para um script comum.

---

### Correções ao texto acima (4) — o que esta seção substitui no desenho original

| Trecho original | Situação |
|---|---|
| Decisão 3, tabela "Regra de emissão do gerador" | **substituída** pela tabela de A.4 (+ eixo `Capabilities`, + passo de abort, + aplicação a `Function`) |
| Decisão 3, "os três eixos independentes do dump (`Security{Read,Write}`, tag `ReadOnly`, tag `NotScriptable`)" | **corrigido**: são **quatro** eixos — `Capabilities` é o quarto |
| Decisão 3, "porque o LuauBench não simula identidade nem `Capabilities`" | **precisado**: o *runtime* continua não simulando; o *gerador* passa a ler o campo (A.6) |
| Contrato `services` → `cli`: *"`Script.Source` é `PluginSecurity` no dump"* | **factualmente errado** — `Security` é `None`/`None`; o portão é `Capabilities.Read == ["PluginOrOpenCloud"]`. **A conclusão prática não muda**: fora do schema, `cli` usa `Get/SetPropertyRaw` |
| Fidelidade vs. pragmatismo, linha `Script.Source` | mesma correção de justificativa; conclusão intacta |
| Fidelidade vs. pragmatismo, linha `RunService.RenderStepped` ("existe no schema e nunca dispara") | **substituída** por B: existe no schema, **conectar erra**; `PreRender` é que fica como "existe e nunca dispara" |
| Fidelidade vs. pragmatismo, linha "Propriedades `Hidden` — não confirmada" | **confirmada**; deixa de ser pendência |
| Fidelidade vs. pragmatismo, linha "Ordem membro-vence-filho — assumida" | **confirmada por fonte oficial**; deixa de ser pendência |
| "NÃO fazer agora": *"Não simular `Security`/`Capabilities`/identidade de thread"* | **continua valendo em runtime**, com a ressalva de A.6 |
| "NÃO fazer agora": *"Não aliasar `RenderStepped` para `Heartbeat`"* | **continua valendo** |
| Módulos de `services` | **+ `src/services/RejectingSignal.luau`** (B.3) |
| Ferramentas de `services` | **+ `tools/capabilities.lock.json`** (A.5) |

### Pendências novas para o `pesquisador` (`task-services-007`, três perguntas — não bloqueiam)

1. `RunService.PreRender` conectado do lado servidor em produção real: erra como `RenderStepped` ou conecta e nunca dispara? (Decide se B.4 muda.)
2. `InternalTest` e `RemoteCommand` bloqueiam mesmo um script comum não-sandboxed? Uma citação de erro real com qualquer um dos dois fecha o critério de A.3; hoje ele é sustentado por `PluginOrOpenCloud` + ausência na doc oficial. (Decide se `RunService.FrameNumber` fica fora do schema.)
3. Texto atual (2026) da recusa de `RenderStepped` no servidor — a família está documentada, o texto exato não foi visto ao vivo. Confirmar se ainda é `"RenderStepped event can only be used from local scripts"` ou se migrou para o formato de capability.
