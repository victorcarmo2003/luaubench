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

---

## Correção 2026-09-05 (2) — `IsAbstract` bloqueava `GetService` de toda Service real

`task-services-003` esbarrou num bug de `runtime`, não de `services`: `ClassRegistry.new` rejeitava `IsAbstract` incondicionalmente, e como toda `Service` do dump carrega `NotCreatable` (traduzido corretamente por este desenho para `IsAbstract = true`), `DataModel:GetService` erava para **toda** Service real.

**Decisão completa, diagnóstico e lista de mudanças:** `.claude/agents-memory/arquiteto-runtime-2026-09-04.md`, seção **"Revisão pós-integração 2026-09-05 (4) — `NotCreatable` vs. abstrata: dois construtores em `ClassRegistry`"**. Tarefa: `task-runtime-023`.

O que muda para **este** desenho de `services`:

- A superfície `runtime -> services` da seção "Contrato entre territórios" ganha uma linha:
  `Runtime.ClassRegistry.NewEngineInstance(className: string, name: string?): Instance` — mesma assinatura de `.new`, sem a guarda de `NotCreatable`. **Único uso legítimo em `services`:** um `Behavior.Initialize` criando filho fixo da própria classe (hoje: `StarterPlayer` -> `StarterPlayerScripts`/`StarterCharacterScripts`, ambos `NotCreatable` **e** `IsService = false`, logo inalcançáveis por `GetService`).
- `Services.new` **não muda** — já barra `IsAbstract` antes de chamar `ClassRegistry.new`, e continua sendo o ponto de enforcement do gate voltado ao script.
- `Types.GeneratedClass.IsAbstract` **não é renomeado agora**. O nome está errado (o dump só tem `NotCreatable`); o renome fica de carona na leva 3 (tipos de valor), que já reescreve os arquivos gerados. Ver o gatilho registrado no desenho do runtime.
- Os testes-gatilho que `task-services-003` deixou em `src/services/Integration.spec.luau` falhando de propósito devem **inverter** para asserção normal quando `task-runtime-023` fechar — trabalho de `coder-services`, na retomada de `task-services-003`.

---

## Decisão de fidelidade 2026-09-05 (3) — `RunService.PreRender` fica conectável (fecho de `task-services-008`)

Fecha a pendência aberta em **B.4** e deferida por `task-services-007`. Citável do código como **"B.5"**.

### B.5.1 Decisão

**`RunService.PreRender` NÃO recebe `RejectingSignal`.** Continua exatamente como está: existe no schema, é conectável, nunca dispara. `RenderStepped` continua sendo o **único** membro da leva 1 que erra ao conectar.

A recomendação de `task-services-007` (tratar por analogia estrutural com `RenderStepped`) foi lida integralmente e **não é acatada** — ela veio explicitamente marcada como *inferência, não confirmação empírica*, e três fatos abaixo pesam contra ela. Isto não é reversão da decisão B: B continua valendo sem alteração para `RenderStepped`.

### B.5.2 O enquadramento correto: `PreRender` nunca foi "o irmão poupado de `RenderStepped`"

Este é o ponto que dissolve a aparente incoerência e que a pesquisa não enquadrou assim.

**B.2** já estabeleceu um balde inteiro de superfície client-only deliberadamente **não varrida** nesta leva: `UserInputService`, `GuiService`, `Players.LocalPlayer` e afins — tudo isso existe e não faz nada, sem erro. `RenderStepped` é uma **exceção recortada desse balde**, justificada por evidência direta de um erro duro de engine em RCC (thread de 14/set/2024, com staff reconhecendo o não-erro do Studio como bug).

`PreRender` pertence ao balde, não à exceção. Manter a exceção do tamanho exato da evidência que a sustenta é a política já escrita; estendê-la por semelhança de nome seria alargá-la por analogia — exatamente o movimento que B.4 pré-comprometeu a não fazer. A decisão de hoje **aplica** a regra existente em vez de abrir uma nova.

### B.5.3 Três fatos que pesam contra a analogia

**1. A analogia tem um contraexemplo com citação ao vivo — e a própria pesquisa o traz.**
`BindToRenderStep` carrega na doc oficial a **mesma frase** de restrição ("As it is linked to the client's rendering process, it can only be called on the client") e, em jogo publicado real, **falha em silêncio, sem erro** (DevForum `182636`, citado na seção 1 do relatório). Ou seja: temos prova viva de que a frase "is client-side, can only be used in X" **não implica** erro em runtime. A pesquisa reconheceu isso e contornou com a distinção `Event` × `Function`; mas a única evidência *empírica* que possuímos sobre o que aquela frase significa aponta para silêncio. Evidência documental cujo poder preditivo já foi falsificado uma vez não sustenta uma mudança de comportamento por comissão.

**2. O portão conhecido de `RenderStepped` é uma checagem legada, não o mecanismo moderno.**
A mensagem de `RenderStepped` (`"...can only be used from local scripts"`) é de 2014 — hardcoded, anterior ao sistema de Capabilities. `PreRender` entrou por volta de 2021, na era moderna, e no dump fixado `28360dea` declara `Capabilities: ["Basic"]`: **nenhum portão declarado**. Isso não prova ausência de checagem (a de `RenderStepped` também não aparece no dump), mas destrói a premissa implícita da analogia — a de que os dois compartilham um mecanismo. Não há evidência nenhuma de que a checagem legada tenha sido religada ao nome novo, e o histórico de rollout por feature flag de `PreRender` (seção 1, "Incerto") sugere um caminho de código menos endurecido, não mais.

**3. A doc oficial migrou a frase de `RenderStepped` para `PreRender`** — a pesquisa apresentou isso como argumento *a favor* de errar. Ele é mais fraco do que parece: a frase descreve **onde o evento é útil** (só dispara sob render, que só existe no cliente), afirmação verdadeira para os dois nomes e para `BindToRenderStep`, e que no caso vivo conhecido corresponde a silêncio. Documentação mudando de lugar é evento de documentação, não de runtime — a própria seção 3 do relatório faz essa ressalva para a hipótese da família de erro e ela vale igual aqui.

### B.5.4 Assimetria de custo, medida contra o `cli` que existe hoje

Fato que a pesquisa não tinha e que decide a margem: **`src/cli/ScriptRunner.luau` nunca executa `LocalScript`** (`SkippedLocalScripts` no `RunSummary`; LuauBench é servidor). Logo, dentro do LuauBench, só há dois caminhos até `PreRender:Connect()`:

| Caminho | Se errarmos (comissão) | Se mantivermos (omissão) |
|---|---|---|
| `Script` de servidor conectando direto | Erro em código que no Roblox real é conexão morta — ganho pequeno e real | Conexão morta, igual ao Roblox real |
| `ModuleScript` compartilhado (ex.: `ReplicatedStorage`) que conecta sem guarda e é `require`d do servidor | **Crash no meio do `require`**, derrubando em cascata todo consumidor a jusante daquele módulo — código que no Roblox real carrega sem incidente, se `PreRender` de fato não errar | Módulo carrega, conexão morta |

O caminho bem escrito (`if RunService:IsClient() then`) é seguro nos dois cenários — `IsClient()` devolve `false` e o ramo nunca é tomado. A exposição de um `LocalScript` conectando `PreRender` é **zero**, porque ele nunca roda.

Duas consequências:

- O ganho da mudança é quase nulo — a incoerência "um nome erra, o outro não" é praticamente inobservável, já que exige um `Script` de servidor tocando os dois.
- O prejuízo é concreto e não-local: falha em cascata no `require`, o pior formato de erro que este runtime pode produzir, em código que roda limpo no Studio.

Comissão custa mais que omissão, e o ganho não paga. É a mesma conta da **Decisão 3** ("em caso de dúvida: incluir") e do princípio de B.4, aplicada com números.

### B.5.5 A regra que isto fixa

Estender `RejectingSignal` a um membro exige **evidência direta de erro naquele membro** — citação de erro real, ao vivo. Analogia estrutural, semelhança de nome e frase de documentação **não** bastam, porque já temos um caso (`BindToRenderStep`) em que os três apontaram para erro e a realidade era silêncio. Vale para toda a superfície client-only do balde de B.2, não só para `PreRender`.

### B.5.6 O que reabre esta decisão

Uma citação ao vivo de `RunService.PreRender:Connect()` num `Script` de servidor em produção (RCC) reportando erro. A pesquisa buscou especificamente e não achou. Pesquisa documental já se esgotou aqui (seção 1, "Incerto"): o que fecha é smoke test contra servidor Roblox publicado — mesmo caminho já registrado para o texto exato do erro de `RenderStepped` (seção 3 do relatório). **Até lá, a pendência está fechada, não em aberto:** nenhum agente precisa revisitá-la sem evidência nova desse tipo específico.

### B.5.7 Consequência para o código (vira `task-services-012`)

Nada de comportamento muda. `src/services/behavior/RunService.luau` e `RunService.spec.luau` estão **corretos como estão** — o único trabalho é textual: os comentários hoje descrevem a falta de evidência como pendência viva ("não há evidência de que erre", tom de questão aberta) e devem passar a citar **B.5** como decisão fechada, com o motivo curto (contraexemplo `BindToRenderStep` + custo de cascata no `require`) e o gatilho de reabertura de B.5.6. Detalhe na tarefa.

### B.5.8 Correções ao texto acima

| Trecho | Situação |
|---|---|
| B.4, item `RunService.PreRender` ("Vai para as pendências novas") | **fechado** por B.5 — deixa de ser pendência; a justificativa passa de "não há evidência" para o ledger de B.5.3/B.5.4 |
| "Pendências novas para o `pesquisador`", item 1 | **respondida e decidida**: pesquisa não confirmou; decisão é manter |
| Recomendação 1 do relatório `pesquisa-prerender-capabilities-2026-09-05.md` | **não acatada**, com motivo registrado em B.5.3 — o relatório continua válido como levantamento; só a recomendação é recusada |

---

# Leva 2 de `services` — data management, rede e cobertura mínima (fecho de `task-services-013`)

Data: 2026-09-05. Continuação da prioridade de cobertura da regra 03: o **Grupo 1** (árvore básica) está 100% coberto e fechado; esta seção decide os **Grupos 2, 3 e 4**. Citável do código como **"L2"** (ex.: `-- ver arquiteto-services-2026-09-05.md, L2.3`).

Nada aqui substitui as decisões 1–6 nem as seções A/B/B.5 acima — o pipeline do gerador, o filtro de emissão de quatro eixos, o formato do `MemberDescriptor`, a regra de idioma dos erros e a política de `RejectingSignal` continuam valendo sem alteração. Esta seção só adiciona.

## Insumos factuais desta seção

Quatro pesquisas rodaram em paralelo antes de qualquer decisão (nenhum fato abaixo é de memória):

| Relatório | Cobre |
|---|---|
| `.claude/agents-memory/pesquisa-datastore-2026-09-05.md` | as 16 classes da família DataStore no dump + semântica oficial (`Roblox/creator-docs`, YAML bruto) + leitura do código-fonte real do ProfileStore |
| `.claude/agents-memory/pesquisa-http-messaging-2026-09-05.md` | `HttpService`/`MessagingService` no dump + doc oficial + eco local do `MessagingService` + `net.request` do Lune 0.10.5 rodado de verdade |
| `.claude/agents-memory/pesquisa-tweenservice-2026-09-05.md` | `TweenService`/`TweenBase`/`Tween`/`TweenInfo` + os 3 enums + semântica de `Create`/`Play`/`Cancel`/`Completed` |
| `.claude/agents-memory/pesquisa-lighting-sound-physics-2026-09-05.md` | `Lighting`/`SoundService`/`PhysicsService` + acoplamento `ClockTime`/`TimeOfDay` + registro de grupos de colisão |

Além deles, extraí eu mesmo do `Full-API-Dump.json` do commit fixado (`.cache/api-dump/28360dea….json`, 8 006 149 bytes, bate com o lock) a superfície já **passada pelo filtro de A.4** de todas as classes desta leva — marcado abaixo como **[dump 09-05d]**.

---

## L2.0 — Três mecanismos transversais que esta leva cria

As três decisões abaixo valem para **todos** os serviços desta leva e precisam existir antes do primeiro deles. Sem elas, cada classe reinventaria a mesma coisa de um jeito ligeiramente diferente.

### L2.0.1 — `src/services/AsyncCall.luau`: o único ponto de yield de `services`

Toda a leva 3 do plano de cobertura é feita de métodos com a tag `Yields` no dump (`GetAsync`, `SetAsync`, `UpdateAsync`, `RemoveAsync`, `PublishAsync`, `SubscribeAsync`, `RequestAsync`, `AdvanceToNextPageAsync`, …). No Roblox eles suspendem a thread chamadora; no LuauBench a única primitiva de suspensão é `Scheduler:Wait(seconds)`, que **erra em português se chamada de fora de uma thread gerida** (`Scheduler.luau`, `Scheduler.Wait`) — uma mensagem de engenharia interna que jamais pode vazar para o Output do usuário.

Módulo novo, extensão do LuauBench e portanto **fora do namespace simulado de qualquer classe real** (regra 00), ao lado de `RejectingSignal.luau`:

```luau
--!strict
-- Ponto ÚNICO de suspensão de `services`. Todo método com a tag `Yields` no dump passa por aqui.
-- `label` é o nome qualificado do método real (ex.: "GlobalDataStore:GetAsync") e só aparece na
-- mensagem de erro do caso patológico abaixo.
function AsyncCall.Yield(label: string): ()
```

Comportamento:
1. `Context.GetScheduler():Wait(0)` — **um passo de scheduler, latência simulada zero**.
2. Se a thread corrente não é gerida pelo Scheduler, `AsyncCall.Yield` captura o erro e o retraduz para uma mensagem `[LuauBench]` em inglês, em nível 3 (culpa o call site do script), nunca a string em português do `runtime`.

**Por que latência zero, e não uma latência "realista".** `Scheduler.Run` avança o relógio por `os.clock()` real (`Scheduler.luau`) — `task.wait(n)` custa `n` segundos de parede de verdade. Injetar 50–200 ms por chamada de DataStore transformaria um cenário de ProfileStore com dezenas de operações em dezenas de segundos de espera por execução de `luaubench run`, e introduziria variação de tempo em testes que devem ser determinísticos. O valor de simular latência é pegar bug de corrida; o custo é tornar a ferramenta lenta e os testes instáveis. **Um passo de scheduler é o mínimo honesto**: o ponto de suspensão existe de verdade (outra thread roda no meio, `task.wait` concorrente intercala, código que assume atomicidade entre a leitura e a escrita quebra aqui como quebraria no Roblox), só não custa tempo de parede.

**Divergência declarada:** nenhuma chamada async do LuauBench tem latência de rede. Uma corrida que só se manifesta com centenas de milissegundos de janela não é reproduzida. Um modo `--async-latency <ms>` é extensão futura registrada, nunca uma propriedade dentro da classe simulada.

**Consequência para a liveness do scheduler:** `Wait(0)` enfileira a thread em `self.waiting`, logo `Scheduler.IsAlive` continua verdadeiro e o laço principal a acorda no tique seguinte. Nenhuma chamada async pode "perder" a thread do usuário.

### L2.0.2 — Estado privado de `services`: propriedade raw fora do schema

`InstanceMeta.__index`, passo 5 (`Instance.luau`): no modo estrito, uma chave que **não está no schema** nunca chega a `data.properties` — cai na resolução de filho e depois no erro `is not a valid member of`. Combinado com a Decisão 6, item 2 (`GetPropertyRaw`/`SetPropertyRaw` **nunca** consultam o schema), isso significa que:

> **Uma propriedade raw cuja chave não existe no schema da classe é estado privado de `services`, invisível e inalcançável para o script do usuário.**

É o mesmo canal que `cli` já usa para `Script.Source` (que está fora do schema por `Capabilities.Read == ["PluginOrOpenCloud"]`, A.4). Esta leva o generaliza e o **nomeia**, porque quatro classes precisam dele: `DataStore`/`OrderedDataStore` (qual store lógico esta instância endereça), `Pages` (o cursor e o buffer), `DataStoreKeyInfo` (o metadata e os userIds), `Tween` (o alvo, o alpha corrente e o estado de playback).

Regra dura, cobrável em revisão: **toda chave usada como estado privado começa com `_LuauBench`** (ex.: `_LuauBenchStoreId`). Motivo: garante colisão zero com qualquer nome de membro que uma versão futura do dump venha a introduzir naquela classe — que é o único jeito de este canal virar um bug silencioso.

Serviço que é **singleton** (`DataStoreService`, `HttpService`, `MessagingService`, `PhysicsService`, `SoundService`) **não usa este canal**: guarda estado em `local` de módulo do próprio `behavior/<X>.luau`. Isso é legítimo e não é uma variável global disfarçada — a invariante "um processo por execução do LuauBench, sem reset" já está documentada em `ClassRegistry.luau` e em `Context.luau`, e um Service tem exatamente uma instância por processo. Fica **registrado como gatilho**: se um dia existir watch mode que reinicie o `DataModel` sem reiniciar o processo, este é um dos pontos que voltam ao arquiteto (o mesmo gatilho que `ClassRegistry` já declara).

### L2.0.3 — `ClassRegistry.NewEngineInstance` ganha um terceiro chamador legítimo

A lista fechada de chamadores hoje (cabeçalho de `ClassRegistry.luau` e de `runtime/init.luau`) tem dois itens: `DataModel.GetService` e `Behavior.Initialize` criando **filho fixo** da própria classe. Esta leva precisa de um terceiro, e ele não cabe em nenhum dos dois:

> **3. `services`, dentro de um `Behavior.Methods`, para construir um objeto do motor que o método real devolve e que não é filho de ninguém.**

Casos desta leva: `DataStoreService:GetDataStore` → `DataStore` (`NotCreatable`, `IsService == false`, `Parent == nil`); `GlobalDataStore:GetAsync` → `DataStoreKeyInfo`; `DataStore:ListVersionsAsync` → `DataStoreVersionPages`; `TweenService:Create` → `Tween`.

Não há via alternativa: `ClassRegistry.new` recusa `IsAbstract` (é a política voltada ao script, que deve continuar recusando `Instance.new("DataStore")` — fiel ao Roblox), e `GetService` só alcança classe com a tag `Service`. É exatamente a mesma situação que `task-runtime-023` já resolveu para `StarterPlayerScripts`, num contexto novo.

**Trabalho para `coder-runtime`:** emendar a lista fechada nos dois cabeçalhos. É mudança de comentário, zero código — mas a lista se declara fechada, então ampliá-la sem registro tornaria a invariante letra morta.

---

## L2.1 — `DataStoreService`: store local em memória, fidelidade de contrato total, fidelidade operacional zero

O caso de uso central do projeto (`CLAUDE.md`) e o único cenário do `testador` que ainda imprime `[SKIP]`.

### L2.1.1 — Local-first não é o eixo da decisão aqui

A tarefa enquadra `DataStoreService` como tensão com a invariante 6. Não é: **não existe API pública que permita a um processo fora do Roblox ler ou escrever o DataStore de um jogo**. A superfície equivalente (Open Cloud) é outro produto, com outra autenticação, outro modelo de chave e outro formato — implementá-la seria construir um cliente de Open Cloud e chamá-lo de `DataStoreService`, o que **inventaria comportamento fora do dump** (invariante 1) além de mandar dado do usuário para fora (invariante 6). Não há decisão a tomar: **o store é local**. O que sobra para decidir é *onde ele mora* e *quanto do contrato real ele honra*.

### L2.1.2 — Onde o dado mora: memória nesta leva; persistência é contrato injetado, nunca `fs` dentro de `services`

**Nesta leva: só memória, vivo enquanto o processo vive.** É o que o cenário `datastore-profilestore-pattern.scenario.luau` já antecipa como suficiente ("mesmo que só durante o processo") e é o que desbloqueia o ProfileStore inteiro, cuja sessão nasce e morre dentro de uma execução.

Persistência entre execuções é desejável (iterar em watch mode sem perder progresso; inspecionar o JSON salvo) e **fica registrada com o contrato já fechado**, para ninguém improvisar depois:

```luau
-- em src/services/Types.luau, quando a leva de persistência chegar
export type DataStorePersistence = {
    Load: () -> string?,      -- devolve o snapshot serializado, ou nil se não existir
    Save: (snapshot: string) -> (),
}
export type BootstrapOptions = { scheduler: …, dataModel: …, dataStorePersistence: DataStorePersistence? }
```

**`services` nunca chama `@lune/fs`.** Quem decide caminho, formato em disco, `.gitignore` e política de erro de I/O é `cli` — é ele que já conhece a raiz do projeto do usuário e é ele que tem a superfície de configuração (`luaubench.toml`, reservado pela Decisão 10 do desenho de `cli`). Esta separação não é cerimônia: sem ela, `services` passaria a ler caminho do disco e a leva seguinte descobriria que a decisão de path foi tomada no lugar errado.

**O snapshot é uma string JSON, e isso é fidelidade, não atalho.** O Roblox só aceita valor serializável no DataStore — tabela com chave mista, função, `Instance`, `thread`, `NaN` e `inf` são recusados (doc oficial `error-codes-and-limits.md`). O validador que a simulação precisa ter de qualquer jeito (L2.1.4) é exatamente o que torna o snapshot serializável de graça.

**Path traversal, tratado por construção:** o snapshot é **um arquivo só**, com nome de store e chave como *chaves de objeto JSON*, nunca como componentes de caminho. Uma chave `"../../.ssh/id_rsa"` vinda de um script do usuário não pode alcançar o filesystem porque nunca vira caminho.

### L2.1.3 — O que é simulado com fidelidade exata

| Contrato | Decisão |
|---|---|
| `GetDataStore(name, scope, options)` **memoizado** por `(name, scope)` | **Sim.** Doc oficial: "subsequent calls return the same object". Duas chamadas devolvem a **mesma** `Instance`. Sem isso, um script que compara `store1 == store2` diverge |
| `GetAsync` → `(value, keyInfo)` | **Sim**, dois valores. Chave inexistente → `(nil, nil)` |
| `SetAsync` → string de versão | **Sim** |
| `UpdateAsync(key, transform)` — transform recebe `(oldValue, keyInfo)`, devolve `(newValue, userIds?, metadata?)`, `nil` **aborta** a escrita, retorno `(newValue, newKeyInfo)` | **Sim, integralmente.** É o único método que o ProfileStore usa para toda escrita e leitura transacional — se algo tem de estar impecável nesta leva, é este |
| A transform **não pode yieldar** | **Validado e erra.** Ver L2.1.5 |
| `RemoveAsync` → `(valorAnterior, keyInfo)` + tombstone (versões antigas continuam legíveis) | **Sim** |
| `IncrementAsync` → valor já incrementado; erra se o valor corrente não é número | **Sim** |
| Deep copy na leitura **e** na escrita | **Sim.** No Roblox o valor é serializado; mutar a tabela devolvida por `GetAsync` não afeta o store. Sem cópia profunda o LuauBench criaria um alias silencioso e **esconderia** uma classe inteira de bug real |
| Limites: nome/chave/scope ≤ 50 chars; valor ≤ 4 194 304 bytes | **Sim.** Validados e erram |
| Valor não serializável (chave mista, função, `Instance`, `thread`, `NaN`, `inf`) | **Recusado com erro.** Mensagem exata do Roblox NÃO CONFIRMADA → aproximação de boa-fé na família Roblox, comentada como tal |
| Versionamento (`GetVersionAsync`, `ListVersionsAsync`, `DataStoreVersionPages`) | **Sim**, na sub-leva B — o ProfileStore usa em `ProfileVersionQuery` |
| `DataStoreOptions:SetExperimentalFeatures({v2 = true})` | **Aceita sem erro** (no-op). O ProfileStore chama isso **sempre**; errar aqui derruba a lib no primeiro `GetDataStore` |
| Cache local de leitura de 4 s (`DataStoreGetOptions.UseCache`) | **Não implementado, e isso é fiel.** O cache é por servidor e só é observável quando **outro** servidor muda a chave; num processo único, escrita e leitura compartilham a mesma fonte, então um cache write-through é indistinguível de não ter cache. `UseCache` entra no schema (é propriedade criável) e é aceito e ignorado |

### L2.1.4 — Onde a simulação para de propósito

| Área | Decisão e por quê |
|---|---|
| **Throttling / budget** | **`GetRequestBudgetForRequestType` devolve uma constante grande e fixa; nada throttla; `SetRateLimitForRequestType` é aceito e ignorado.** Três razões, nesta ordem: (1) a fórmula real é `baseLimit + perPlayerLimit × numPlayers` e o LuauBench tem **zero jogadores** por decisão já tomada (`Players.GetPlayers() == {}`) — simular a fórmula daria o orçamento **mínimo** e faria estourar código que roda folgado em produção: falha por comissão, o modo de falha que a Decisão 3 combate; (2) os números exatos da fórmula vieram **NÃO CONFIRMADOS** da pesquisa (dois fetches da mesma página oficial divergiram) e a regra 00 proíbe adivinhar; (3) o ProfileStore — a lib que define este caso de uso — **não chama `GetRequestBudgetForRequestType` uma única vez**. Devolver constante **grande** e não `math.huge` nem `0` é deliberado: código que faz `while budget < N do task.wait() end` prossegue de imediato (determinístico), e código que faz aritmética com o valor não recebe infinito |
| **Erro transitório** (throttle, 502, timeout de serviço) | **Nunca injetado.** Seria não-determinismo dentro de um banco de teste. Um modo de injeção de falha (`--datastore-chaos`) é extensão futura registrada — **fora** do namespace da classe (regra 00) |
| **"Studio sem API access" / "jogo não publicado"** | **Nunca simulado.** O LuauBench sempre tem acesso ao próprio store. Detalhe que fecha a questão: a sondagem do ProfileStore (`SetAsync` num `pcall`, checando as substrings `"403"`/`"must publish"`/`"ConnectFail"`) só roda **se `IsStudio()` for verdadeiro**, e o LuauBench declara `IsStudio() == false` desde a leva 1 — a sondagem nem é alcançada |
| **Replicação entre servidores** | Não existe. Um processo, um servidor |
| **`AutomaticRetry` / `LegacyNamingScheme`** | **Fora do schema pelo filtro de A.4** (`LocalUserSecurity`) **[dump 09-05d]** — um script comum não os vê no Roblox real. Nada a decidir |
| **`ListDataStoresAsync`, `BatchGetAsync`, `GetVersionAtTimeAsync`, `RemoveVersionAsync`, `OnUpdate`** | Ficam com o stub `[LuauBench] … is not simulated by LuauBench yet` do `ClassBuilder`. Nenhum é usado pelo ProfileStore; `OnUpdate` é `Deprecated` no dump |

### L2.1.5 — Detectar a transform que yielda

A doc oficial é literal: *"The callback function cannot yield."* No LuauBench, uma transform que chama `task.wait` **funcionaria** — a thread estaciona no scheduler e volta depois. Isso é a pior categoria de divergência possível: código que **passa no banco e falha em produção**. A simulação roda a transform em `coroutine.create` + `coroutine.resume`; se a coroutine não estiver `dead` depois do resume, `coroutine.close` e erro na família Roblox citando a proibição. Custo: uma coroutine por `UpdateAsync`; o traceback do erro *dentro* da transform é recuperado com `debug.traceback(co)` antes do `close`, para não piorar o diagnóstico que o usuário recebe.

### L2.1.6 — Módulos

```
src/services/datastore/Value.luau        -- validação (serializável? tamanho? chave ≤ 50?) + deep copy. Sem Instance, sem I/O.
src/services/datastore/Store.luau        -- o store em memória: (storeId, key) -> { value, version, createdTime, updatedTime, userIds, metadata, tombstone }. Sem Instance.
src/services/InstanceState.luau          -- estado privado por instância, chaves _LuauBench* (L2.0.2)
src/services/AsyncCall.luau              -- L2.0.1
src/services/behavior/DataStoreService.luau
src/services/behavior/GlobalDataStore.luau   -- GetAsync/SetAsync/UpdateAsync/RemoveAsync/IncrementAsync (herdados por DataStore e OrderedDataStore)
src/services/behavior/DataStore.luau         -- GetVersionAsync/ListVersionsAsync/ListKeysAsync
src/services/behavior/OrderedDataStore.luau  -- GetSortedAsync
src/services/behavior/DataStoreKeyInfo.luau  -- GetMetadata/GetUserIds
src/services/behavior/DataStoreSetOptions.luau / DataStoreIncrementOptions.luau -- Get/SetMetadata
src/services/behavior/DataStoreOptions.luau  -- SetExperimentalFeatures (no-op)
src/services/behavior/Pages.luau             -- GetCurrentPage/AdvanceToNextPageAsync/IsFinished
```

`Value.luau` e `Store.luau` **não conhecem `Instance`** de propósito: são dado puro, testáveis sem `Bootstrap`, e é onde mora toda a regra que a regra 03 chama de "o como".

### L2.1.7 — Classes a acrescentar em `tools/coverage.luau`

`DataStoreService`, `GlobalDataStore`, `DataStore`, `OrderedDataStore`, `DataStoreKeyInfo`, `DataStoreSetOptions`, `DataStoreOptions`, `DataStoreGetOptions`, `DataStoreIncrementOptions`, `Pages`, `DataStorePages`, `DataStoreKeyPages`, `DataStoreListingPages`, `DataStoreVersionPages`, `DataStoreObjectVersionInfo`, `DataStoreInfo`. O fecho de superclasses é automático (Decisão 1) — nenhuma dessas tem superclasse fora da lista, exceto `Pages`, que já está.

**Ambiguidade registrada:** o dump declara `GetGlobalDataStore() -> DataStore` **[dump 09-05d]**, embora o nome sugira `GlobalDataStore`. **Decisão: seguir o dump** — as duas fábricas devolvem `ClassName == "DataStore"`. `DataStore` herda `GlobalDataStore`, então `:IsA("GlobalDataStore")` continua verdadeiro; só um `ClassName == "GlobalDataStore"` literal divergiria, e a fonte de verdade do projeto é o dump, não a intuição do nome. Comentado no código como tal.

### L2.1.8 — Dependência dura: `game:BindToClose` é de `runtime`

O ProfileStore usa `game:BindToClose` para descarregar sessões no encerramento, com um `while … do task.wait() end` esperando os jobs terminarem. Sem ele, o passo 4 do cenário do `testador` (persistir e reabrir) nunca fecha.

`BindToClose` é membro do `DataModel` (`Function BindToClose(function)`, `Security None` **[dump 09-05d]**) e depende do ciclo de vida do `Scheduler` — **fica em `runtime`**, como o desenho já decidia na seção "Riscos e decisões". Semântica exigida: `Scheduler.Run` não pode considerar o trabalho terminado antes de rodar os callbacks registrados **e de esperar que eles retornem**, inclusive quando eles próprios yieldam. Tarefa de `coder-runtime`, pré-requisito do cenário (não da implementação do store).

---

## L2.2 — `HttpService`: a rede é opt-in de quem roda o LuauBench, exatamente como é opt-in do dono do lugar no Roblox

Esta é a decisão de mais peso da leva, e ela se resolve por um fato do dump, não por juízo de valor.

### L2.2.1 — O dump já responde quem pode ligar a rede

```
HttpEnabled: bool
  Security     = { Read = "None", Write = "LocalUserSecurity" }
  Capabilities = { Read = ["Network"] }
  Default      = "false"
```
**[dump 09-05d]**, com `GetHttpEnabled`/`SetHttpEnabled` fora do alcance de script comum pelo mesmo eixo.

Pela regra de emissão de A.4 (passo 5: `Security.Write ~= "None"` ⇒ incluído com `ReadOnly = true`), a consequência é direta e não é escolha minha: **no Roblox real, um script pode LER `HttpEnabled` e não pode ESCREVÊ-LO.** A rede é ligada pelo **dono do lugar**, nas configurações do jogo, fora do código. E o default é `false`.

O LuauBench tem uma correspondência óbvia para "dono do lugar": **a pessoa que digita `luaubench run`**. Logo:

- `HttpEnabled` entra no schema como `ReadOnly`, semeado `false`;
- `luaubench run --allow-http` o coloca em `true` (via `SetPropertyRaw`, a via de engenharia que ignora o schema);
- sem a flag, `GetAsync`/`PostAsync`/`RequestAsync` erram com a família real de "HTTP desabilitado", **que é o que o Roblox faz num lugar recém-criado**.

### L2.2.2 — Por que isto não fere a invariante 6, e o que de fato a feriria

A invariante 6 diz: *"O LuauBench não envia script, asset nem dado do projeto do usuário para nenhum serviço externo."* O sujeito é **o LuauBench**. Ela proíbe a ferramenta de fazer telemetria, de mandar código para análise remota, de subir o projeto para lugar nenhum — decisões tomadas *pela ferramenta*, sem o usuário pedir.

`HttpService:PostAsync(url, corpo)` é o **script do usuário**, escrito por ele, executando o que ele escreveu para executar. A regra 00 é explícita sobre qual é o critério: *"a superfície exposta ao script é a que o Roblox real exporia"*. O Roblox real expõe rede pelo `HttpService`. Recusar rede seria **divergir do Roblox** (regra 00, invariante 2) e transformar num "não simulado" a metade da API que existe justamente para falar com serviços externos — webhook de Discord, API de analytics, backend próprio, tudo que os 37 usos medidos de `HttpService` do recon podem conter.

O que **feriria** a invariante 6, e continua proibido: o LuauBench mandar qualquer coisa por conta própria; qualquer telemetria; qualquer "modo online" que não seja a chamada literal que o script fez.

O que resta é a invariante 7 ("script do usuário é código arbitrário"), e é ela que justifica o **portão** — não o bloqueio. Um `.project.json` clonado de um repositório desconhecido não deve ganhar acesso à rede da máquina do desenvolvedor só por ser executado uma vez. O portão default-off resolve isso **sendo simultaneamente o comportamento mais fiel possível**: no Roblox, um lugar novo também tem HTTP desligado.

### L2.2.3 — Duas sub-levas com riscos muito diferentes

| Sub-leva | Conteúdo | Rede | Fidelidade |
|---|---|---|---|
| **A** | `JSONEncode`, `JSONDecode`, `UrlEncode`, `GenerateGUID`, `HttpEnabled` (ReadOnly, `false`) e os três métodos de rede errando "HTTP não habilitado" | **Nenhuma** | **Exata** — é literalmente um lugar Roblox com HTTP desligado |
| **B** | `GetAsync`/`PostAsync`/`RequestAsync` de verdade, atrás de `--allow-http`, sobre `net.request` do Lune | Real | Alta, com as ressalvas de L2.2.5 |

A sub-leva A entrega a maior parte do valor com risco zero e sem nenhuma decisão pendente. Ela vai junto com o Grupo 3; a B é tarefa separada, e é a única do desenho inteiro que abre uma superfície de rede.

### L2.2.4 — Endurecimento que o Roblox não tem, e por que ele é correto aqui

Com `--allow-http` ligado, o LuauBench é **mais restritivo** que o Roblox em um ponto, deliberadamente: **destinos de loopback, link-local e faixas privadas (`127.0.0.0/8`, `::1`, `169.254.0.0/16`, `10/8`, `172.16/12`, `192.168/16`) são recusados**, a menos que uma segunda opção explícita (`--allow-http-local`) seja passada.

O modelo de ameaça é genuinamente diferente: um servidor Roblox roda num datacenter e não alcança a rede doméstica de ninguém; o LuauBench roda **na máquina do desenvolvedor**, onde `http://127.0.0.1:*` e `http://169.254.169.254/` (metadata de nuvem) são alvos reais que não existem no Roblox. Manter a fidelidade nesse ponto específico seria copiar uma permissão cujo contexto não se aplica.

Divergência declarada nos dois sentidos: um script que fala com um backend local de desenvolvimento — caso legítimo e comum — precisa da segunda flag; e `--allow-http-local` é registrado no relatório e no `--help`, nunca implícito.

`--verbose` passa a imprimir uma linha por requisição de saída (método + host, nunca corpo). É a versão auditável do local-first: o usuário consegue ver o que o script dele mandou para fora.

### L2.2.5 — Fidelidade vs. pragmatismo em HTTP

| Item | Decisão |
|---|---|
| Forma de `RequestAsync` — entrada `{Url, Method, Headers, Body, Compress, Timeout}`, saída `{Success, StatusCode, StatusMessage, Headers, Body}` | **Exata** (doc oficial, `HttpService.yaml`) |
| `Timeout` da entrada | **Aceito e ignorado.** `net.request` do Lune 0.10.5 **não tem timeout configurável** (verificado rodando). Divergência declarada; implementar por cima exigiria cancelamento, fora desta leva |
| Host inexistente / falha de DNS | O Lune **lança**; a simulação captura e traduz para a família Roblox. Nunca vaza `os error 11001` cru |
| `JSONDecode` de JSON inválido | **Erra** (doc oficial), como o Lune já faz. Mensagem retraduzida |
| `JSONEncode` com `inf`/`NaN` | O Roblox aceita e **produz JSON inválido de propósito**. Se `serde.encode` do Lune recusar, a divergência é declarada em vez de silenciada |
| `JSONEncode` com referência cíclica | **Erra**, como o Roblox |
| Domínios `roblox.com` bloqueados; erro "só do servidor" no cliente | **Não** implementados: confirmados só por DevForum, não por doc oficial, e o LuauBench é sempre servidor. Registrados |
| Limite de 500 req/min | **Não** simulado — mesma conta da L2.1.4: não-determinismo em troca de quase nada |
| `GetSecret` / `CreateWebStreamClient` | Sobrevivem ao filtro **[dump 09-05d]** mas ficam com o stub `[LuauBench] … not simulated yet` |

---

## L2.3 — `MessagingService`: o eco local é fiel, não é uma concessão

Superfície mínima **[dump 09-05d]**: só `PublishAsync(topic, message)` e `SubscribeAsync(topic, callback)`, ambos `Yields`. Nenhuma propriedade, nenhum evento — o recebimento é um **callback Luau puro**, não um `RBXScriptSignal`.

### L2.3.1 — A pergunta decisiva, respondida

*"Num jogo com um único servidor, o servidor que publica recebe a própria mensagem?"* A doc oficial não trata do assunto; **dois threads independentes do DevForum confirmam que sim**, um deles com sintoma observado (efeito disparando no próprio servidor que publicou) e a correção aplicada sendo filtrar por `game.JobId` — evidência empírica, não inferência.

**Consequência: um LuauBench de processo único é uma simulação fiel de um jogo Roblox com exatamente um servidor.** `PublishAsync` num tópico que este processo assina **deve** entregar. Não é um atalho para tornar a API testável; é o comportamento correto.

Isso resolve um dilema que não precisou ser resolvido: se o Roblox excluísse o remetente, uma assinatura no LuauBench nunca dispararia, e uma API que nunca entrega nada é exatamente o "stub silencioso que finge funcionar" que a regra 03 proíbe. A evidência dispensou a escolha.

### L2.3.2 — Semântica

| Item | Decisão |
|---|---|
| Entrega ao próprio processo | **Sim**, a todos os callbacks inscritos naquele tópico |
| Formato entregue | `{ Data = <mensagem>, Sent = <unix em segundos> }` — nomes de chave confirmados na doc oficial |
| Momento da entrega | **Assíncrono**: `PublishAsync` yielda um passo (`AsyncCall.Yield`) e os callbacks são despachados via `Scheduler:Spawn`, um por callback. Nunca síncrono dentro do `PublishAsync` — no Roblox a entrega passa pela rede, e entregar de forma síncrona faria código com reentrância passar aqui e falhar lá |
| Erro dentro de um callback | Não derruba o publisher nem o processo: cada callback é sua própria thread do Scheduler, e o erro sai por `ThreadError` como qualquer outro (regra 02) |
| `SubscribeAsync` → `RBXScriptConnection` | Devolve uma `Runtime.Connection`; `:Disconnect()` cancela a assinatura |
| Limites (1 kB por mensagem, tópico de 1–80 chars) | **Validados e erram** — são limites de contrato, determinísticos e baratos |
| Limites de taxa (`600 + 240×jogadores` publish/min, `20 + 8×jogadores` assinaturas) | **Não** simulados — mesma conta de L2.1.4, agravada pelo fato de o LuauBench ter zero jogadores |
| Ordem de entrega entre múltiplos assinantes | Ordem de inscrição, documentada como **aproximação** — o Roblox não garante ordem |
| Cross-server | **Não existe.** Um processo, um servidor. Divergência já aceita pelo projeto |

### L2.3.3 — Dependência descoberta: `game.JobId`

O padrão real para evitar reprocessar o próprio eco é comparar `message.Data.JobId` com `game.JobId`. Hoje `game` é uma instância **leniente** (sem schema) e `game.JobId` devolve `nil` — o que faz `nil ~= nil` ser falso e, por acidente, o filtro funcionar. Depender de um acidente é pior do que não ter a propriedade.

**Tarefa pequena de `coder-runtime`:** `DataModel` passa a expor `JobId` (string), `PlaceId`/`GameId` (int64) e `PlaceVersion` (int) — todos `Security None` e `ReadOnly` no dump **[dump 09-05d]** — com valores fixos por processo (`JobId` = um GUID gerado uma vez; `PlaceId`/`GameId` = `0`, que é o que o Roblox usa num lugar não publicado). São propriedades do `DataModel`, cuja implementação já é responsabilidade estrutural de `runtime` (mesma justificativa de `GetService`/`BindToClose`).

---

## L2.4 — `TweenService`: bloqueada, e o bloqueio é menor do que parecia

### L2.4.1 — A dependência exata

A tarefa pergunta se `TweenService` depende de `task-runtime-031` (tipos de valor) ou se cabe uma leva mínima. A resposta é mais precisa do que "depende":

**`TweenService` depende de exatamente dois itens da leva de tipos de valor — `Enum`/`EnumItem` e `TweenInfo` — e de mais nada.** Não depende de `Vector3`, nem de `CFrame`, nem de `Color3`.

Por quê: a lista oficial fechada de tipos tweenáveis é `number`, `boolean`, `CFrame`, `Rect`, `Color3`, `UDim`, `UDim2`, `Vector2`, `Vector2int16`, `Vector3`, `EnumItem`. **`number` e `boolean` já existem** — um `TweenService` que só interpola número é útil de verdade (`Transparency`, `Volume`, `Value`, `Gravity`). O que impede não é o alvo da interpolação, é a **entrada**: `Create(instance, tweenInfo, propertyTable)` exige um `TweenInfo`, e `TweenInfo.new` exige `Enum.EasingStyle`/`Enum.EasingDirection`; `TweenBase.PlaybackState` e o argumento de `Completed` são `EnumItem`. Hoje `TweenInfo` e `Enum` estão os dois em `src/cli/UnsimulatedGlobals.luau` e erram com mensagem `[LuauBench]` nomeada.

### L2.4.2 — Não existe leva 1 mínima que valha a pena

A sugestão da tarefa (um `Tween` que só dispara `Completed` depois do tempo, sem interpolar) **não é alcançável**: o script não consegue construir o `TweenInfo` que `Create` exige, então nunca chega a `TweenService`. Adiantar um `TweenService` parcial só pioraria o diagnóstico — hoje `game:GetService("TweenService")` erra `[LuauBench] TweenService exists in the Roblox API Dump but is not simulated by LuauBench yet`, que é **exatamente a mensagem certa**, e `TweenInfo.new` erra nomeando a lacuna real. Um serviço meio-implementado trocaria dois erros precisos por um comportamento que parece funcionar.

**Decisão: `TweenService` não entra nesta leva. Fica bloqueada por `task-runtime-031`, com a dependência declarada como `Enum`/`EnumItem` + `TweenInfo`, não como "os 22 tipos".**

### L2.4.3 — Dois requisitos que esta seção manda para `task-runtime-031`

O desenho de tipos de valor está sendo feito em paralelo. Dois pedidos concretos, para não ter retrabalho:

1. **Priorizar `Enum`/`EnumItem` + `TweenInfo` na leva 1 daquele desenho.** São o que desbloqueia `TweenService` inteiro, e `Enum` também desbloqueia `GetRequestBudgetForRequestType`, `ListVersionsAsync(sortDirection)` e `PostAsync(contentType)` desta leva.
**Estado no board, verificado ao fechar esta seção:** o desenho de tipos de valor já virou território próprio (`src/valuetypes/`, agente `coder-valuetypes`) e tarefas — `task-valuetypes-003` cobre `Enum` + o gerador de enums na **leva 1** daquele plano. **`TweenInfo` está na leva 2 de lá e ainda não tem tarefa.** Ou seja: das duas dependências de `TweenService`, uma já está no board e a outra não. É `TweenInfo` que fica no caminho crítico, e é por isso que o pedido 1 acima é concreto e não retórico.

2. **Cada tipo interpolável precisa expor um contrato de interpolação documentado** (uma operação `lerp(a, b, alpha)` ou equivalente, definida no próprio módulo do tipo). `TweenService` **não** deve reimplementar interpolação por tipo — se ele conhecer a fórmula de `Vector3`, a fórmula passa a existir em dois lugares.

### L2.4.4 — Semântica já fixada, para quando destravar (não construir agora)

| Item | Fato |
|---|---|
| Validação (propriedade inexistente, tipo incompatível, tipo não tweenável) acontece em **`Create`**, não em `Play` | 3 famílias de erro confirmadas por citação |
| `TweenInfo.new(time=1, easingStyle=Quad, easingDirection=Out, repeatCount=0, reverses=false, delayTime=0)` | Doc oficial, batendo com o `Default` bruto de `Tween.TweenInfo` no dump |
| `Cancel()` congela no valor corrente e zera o progresso; `Play()` depois reinicia do zero; `Pause()`+`Play()` retoma | Confirmado |
| `Completed(playbackState)` dispara em conclusão (`Completed`) **e** em `Cancel()` (`Cancelled`); **não** em `Pause()` | Confirmado |
| `RepeatCount = -1` → laço infinito, `Completed` nunca dispara | Confirmado |
| `RepeatCount` são repetições **extras** (`0` toca uma vez) | Confirmado |
| Passo de atualização | Ligar em `RunService.Heartbeat` (o único relógio real do LuauBench). O passo exato do Roblox **NÃO CONFIRMADO** → aproximação declarada |
| Fórmulas de easing | **Não reproduzíveis com fidelidade garantida** (a melhor reprodução aberta admite ~2 casas). `Linear` é exato; as outras 10 entram como **aproximação declarada**, com a divergência no comentário |
| Alvo destruído no meio do tween | Não erra nem derruba (convergência de relatos, sem fonte oficial) — comportamento a documentar como aproximação |
| Tipos com valor ainda não simulado (`Vector3`, `CFrame`, …) | Enquanto o tipo não existir, `Create` erra com `[LuauBench]` nomeando a lacuna — nunca com a mensagem de "tipo não tweenável" do Roblox, que mentiria |

---

## L2.5 — Grupo 4: `PhysicsService`, `Lighting`, `SoundService` — e um achado que muda onde o Grupo 4 mora

A regra 03 pede "cobertura mínima de API, comportamento simplificado e documentado" para o Grupo 4. A pesquisa mostrou que os três não são iguais: **um deles é 100% simulável com fidelidade exata, outro tem exatamente um núcleo de estado que vale simular, e o terceiro é dado morto.** Tratá-los com a mesma régua seria errar dos dois lados.

### L2.5.1 — Achado: os grupos de colisão pertencem ao `WorldRoot`, não ao `PhysicsService`

`WorldRoot` — superclasse de `Workspace`, **já gerada na leva 1** pelo fecho automático — declara sua **própria cópia scriptável** dos oito métodos de grupo de colisão **[dump 09-05d]**:

```
RegisterCollisionGroup(name)            UnregisterCollisionGroup(name)
IsCollisionGroupRegistered(name)        RenameCollisionGroup(from, to)
GetRegisteredCollisionGroups()          GetMaxCollisionGroups()
CollisionGroupSetCollidable(a, b, c)    CollisionGroupsAreCollidable(a, b)
```
Todos `Security None`, `Capabilities ["Physics"]` (concedível, logo **dentro** do schema por A.4), escopados **por instância de mundo** — `WorldModel.UseWorkspaceCollisionGroups` **[dump 09-05d]** só existe porque o escopo é por mundo. A doc oficial já marca os métodos homônimos de `PhysicsService` como *superseded by `WorldRoot`* (sem tag `Deprecated` formal no dump ainda).

**Consequência de arquitetura:** o registro de grupos de colisão é **estado do `WorldRoot`**, e `PhysicsService` é a vista legada sobre o registro do `Workspace`. Escrever o estado dentro de `behavior/PhysicsService.luau` e depois fazer `Workspace` consultá-lo inverteria a relação real.

**Decisão:**
- `src/services/CollisionGroups.luau` — o registro, dado puro, sem `Instance`: nomes registrados, matriz de colidibilidade par a par, limite de 32.
- `src/services/behavior/WorldRoot.luau` — **novo**, os oito métodos, com um registro **por instância** (canal de estado privado de L2.0.2). É a **primeira vez que `Workspace` ganha comportamento de verdade**.
- `src/services/behavior/PhysicsService.luau` — os mesmos métodos, **delegando ao registro da instância de `Workspace`** obtida via `Context.GetDataModel():GetService("Workspace")`. É o modelo fiel (uma verdade só), e o que faz `PhysicsService:RegisterCollisionGroup("X")` seguido de `workspace:IsCollisionGroupRegistered("X")` devolver `true`, como no Roblox.

Fatos confirmados que a simulação honra exatamente: **`GetMaxCollisionGroups() == 32`**; o grupo **`"Default"` já vem registrado**; **dois grupos recém-registrados colidem entre si por padrão**. Não confirmados e portanto tratados pelo princípio da Decisão 3 ("em dúvida, incluir/permitir", falhar por omissão e não por comissão): registrar nome duplicado **não erra** (idempotente) e não há restrição cliente/servidor. Os dois viram comentário no código e pendência de pesquisa, não invenção.

Os 7 métodos `Deprecated` de `PhysicsService` (`CreateCollisionGroup`, `GetCollisionGroupId`, `GetCollisionGroupName`, `GetCollisionGroups`, `RemoveCollisionGroup`, `SetPartCollisionGroup`, `CollisionGroupContainsPart`) **ficam com o stub `[LuauBench] … not simulated yet`**: estão no schema (regra da Decisão 3 — `Deprecated` entra), mas os que dependem de `BasePart` (`SetPartCollisionGroup`, `CollisionGroupContainsPart`) exigiriam a classe `BasePart`, que não é coberta, e os de id numérico expõem um modelo de id que o Roblox moderno abandonou. Sinalizado no relatório da tarefa, conforme a regra 03 pede.

**`PhysicsService` é o Grupo 4 com maior retorno e nenhuma aproximação:** zero propriedades, quinze funções, tudo dado puro. Não há física simulada em lugar nenhum disto — grupo de colisão é bookkeeping, e o LuauBench o reproduz **exatamente**.

### L2.5.2 — `Lighting`: um núcleo de estado acoplado, o resto é dado inerte

`Lighting` já está coberta desde a leva 1 (20 propriedades no schema, sem `Behavior`). O que falta é **o único acoplamento real da classe**, hoje divergente em silêncio: escrever `Lighting.ClockTime = 6` deixa `TimeOfDay` valendo `"14:00:00"`.

Confirmado por doc oficial: **`ClockTime`, `TimeOfDay` e `Get`/`SetMinutesAfterMidnight` são três vistas do mesmo estado.** Os defaults do dump já são coerentes entre si (`ClockTime = 14`, `TimeOfDay = "14:00:00"` **[dump 09-05d]**), então a semeadura de `ClassRegistry.new` já nasce certa — só as escritas divergem.

**Decisão: `behavior/Lighting.luau` (novo) mantém as três vistas sincronizadas**, com uma única fonte interna em minutos. `TimeOfDay` aceita escrita curta (`"11:00"`) e `SetMinutesAfterMidnight` faz **wrap** acima de 24 h — os dois confirmados. Zero-padding na leitura e wrap na escrita direta em `ClockTime` **não confirmados** → adotar a forma canônica `HH:MM:SS` com zero-padding e wrap, comentado como aproximação de boa-fé.

`LightingChanged(skyChanged: bool)` passa a disparar nas mudanças de propriedade **exceto** `GlobalShadows`, `FogColor`, `FogStart` e `FogEnd` — exclusão **documentada oficialmente**, e uma pegadinha que só um LuauBench fiel reproduz.

`GetMoonPhase()` devolve **`0.75` sempre** — é o valor real do motor hoje, confirmado; fidelidade de graça. `GetSunDirection`/`GetMoonDirection` devolvem `Vector3` e **não têm fórmula pública**: permanecem com o stub `[LuauBench] … not simulated yet` mesmo depois de `Vector3` existir. Divergência declarada, não uma dívida que a leva de tipos de valor quita.

Todo o resto de `Lighting` (`Ambient`, `Brightness`, `FogColor`, …) continua o que já é: **dado que guarda e devolve, sem render nenhum.** Já declarado na tabela de fidelidade da leva 1; nada muda.

### L2.5.3 — `SoundService`: superfície e nada mais, deliberadamente

17 membros sobrevivem ao filtro (13 propriedades, 4 funções, zero eventos). Para o público-alvo declarado do LuauBench — lógica pura, data manager, state machine — `SoundService` é **irrelevante**, e a pesquisa confirmou isso ao procurar uso real.

**Decisão: cobertura de superfície, sem `Behavior` próprio.** As propriedades guardam e devolvem (dado morto, como `Lighting`); os quatro métodos ficam com o stub `[LuauBench] … not simulated yet` do `ClassBuilder`.

Duas notas que **não** viram exceção:
- `PlayLocalSound` é client-only e erra no servidor real. **Não recebe `RejectingSignal`-equivalente**: a regra B.5.5 exige *citação ao vivo de erro naquele membro* para recortar uma exceção do balde de superfície client-only, e a pesquisa só achou relato de comunidade, sem string verbatim. O stub `[LuauBench]` já erra alto; trocar o texto sem evidência seria alargar a exceção por analogia — exatamente o que B.5 proibiu.
- **Discrepância dump × doc:** `RespectFilteringEnabled` tem `Default = "false"` no dump e `true` na doc oficial. **Decisão: o dump vence** — é a fonte única do projeto (regra 03), o valor gerado é `false`, e a discrepância fica registrada aqui e no relatório do gerador. Nenhum agente "corrige" um `Default` gerado à mão.

`SoundService` entra em `tools/coverage.luau` só para que `game:GetService("SoundService")` pare de errar e a árvore de um projeto real materialize; é a definição literal de "cobertura mínima".

---

## Divisão por território

| Território | O que constrói nesta leva | Contrato com o vizinho |
|---|---|---|
| `runtime` (`src/runtime/`) | (a) `DataModel:BindToClose(fn)` + a espera dos callbacks no encerramento do `Scheduler`; (b) `DataModel.JobId`/`PlaceId`/`GameId`/`PlaceVersion` com valores fixos por processo; (c) emenda da lista fechada de chamadores de `NewEngineInstance` (só comentário) | Continua sem conhecer nome de Service e sem ler o dump. Nada em (a)/(b) depende de `services` |
| `services` (`src/services/` + `tools/coverage.luau`) | `AsyncCall`, `InstanceState`, `CollisionGroups`, `datastore/{Value,Store}`, os `behavior/*` novos, as classes novas em `coverage.luau` e a regeração de `generated/**` | Consome só `require("../runtime")`. Expõe a `cli` só `require("../services")` — nenhuma superfície pública nova, exceto o que a flag de HTTP exige |
| `cli` (`src/cli/`) | `--allow-http` e `--allow-http-local` em `Args.Command`; repasse a `Services.Bootstrap`; linha de auditoria por requisição em `--verbose`; `Messages.luau` para os textos novos | Nunca requer `generated/`/`behavior/`; nunca toca `tools/` |

`cli` só entra na sub-leva B de HTTP. Todo o resto é `runtime` + `services`, e dentro de `services` as tarefas são **sequenciais** (mesmo território) — o paralelismo desta fase é entre territórios, como na leva 1.

## Ordem de leva sugerida

| Leva | Conteúdo | Por quê nesta posição |
|---|---|---|
| **1** | `runtime`: `BindToClose` + `JobId`/`PlaceId`/`GameId` + emenda do comentário de `NewEngineInstance`. Em paralelo, `services`: `AsyncCall` + `InstanceState` | Pré-requisitos duros. Nenhum serviço desta leva pode ser escrito antes de `AsyncCall`, e o cenário do ProfileStore não fecha sem `BindToClose` |
| **2** | `services`: **DataStore núcleo** — `coverage.luau` + regeração + `datastore/{Value,Store}` + `DataStoreService`/`GlobalDataStore`/`DataStoreKeyInfo` + as três classes de options | É o caso de uso central do `CLAUDE.md` e o único `[SKIP]` do `testador` |
| **3** | `services`: **DataStore v2** — `DataStore` (`GetVersionAsync`/`ListVersionsAsync`/`ListKeysAsync`) + família `Pages`; e `OrderedDataStore`/`GetSortedAsync` como tarefa irmã | Fecha o que o `ProfileVersionQuery` do ProfileStore usa. `OrderedDataStore` é leaderboard, valor real mas fora do caminho crítico |
| **4** | `services`: `MessagingService` inteiro; `HttpService` **sub-leva A** (JSON/GUID/UrlEncode + `HttpEnabled` falso + os três métodos de rede errando) | Ambos pequenos, sem dependência nova, risco zero. `HttpService` sub-leva A é fidelidade exata |
| **5** | `services`: `WorldRoot` + `PhysicsService` + `Lighting`; `SoundService` só como superfície | Grupo 4. Independentes de tudo acima — podem trocar de posição com a leva 4 sem custo |
| **6** | `HttpService` **sub-leva B** (rede real) — `services` + `cli` juntos | Única superfície de rede do projeto; merece uma leva só dela e revisão dedicada |
| **7** | `testador`: cenário do ProfileStore de `[SKIP]` para verde, com o `ProfileStore.luau` real | Depois de 2+3+1; é o teste de aceitação de todo o desenho |
| **bloqueada** | `TweenService` + `Tween`/`TweenBase` | Depende de `Enum`/`EnumItem` + `TweenInfo` de `task-runtime-031`. Não entra em nenhuma leva desta seção |

**Tarefas criadas no board (17), na ordem das levas acima:**

| Leva | Onda | Tarefas |
|---|---|---|
| 1 | 44 | `task-runtime-033` (BindToClose) · `task-runtime-034` (JobId/PlaceId/GameId) · `task-runtime-035` (comentário de `NewEngineInstance`) · `task-services-016` (`AsyncCall` + `InstanceState`) |
| 2 | 45 | `task-services-017` (coverage + geração + `Value`/`Store`) · `task-services-018` (`DataStoreService`/`GlobalDataStore`/`DataStoreKeyInfo`/options) · `task-services-028` (pesquisa das 6 pendências, em paralelo) |
| 3 | 46 | `task-services-019` (DataStore v2 + `Pages`) · `task-services-020` (`OrderedDataStore`) |
| 4 | 47 | `task-services-021` (`MessagingService`) · `task-services-022` (`HttpService` sub-leva A) |
| 5 | 48 | `task-services-023` (`CollisionGroups`/`WorldRoot`/`PhysicsService`) · `task-services-024` (`Lighting`) · `task-services-025` (`SoundService`) |
| 6 | 49 | `task-services-026` (`HttpService` sub-leva B) · `task-cli-026` (as duas flags + auditoria) |
| 7 | 50 | `task-services-027` (cenário ProfileStore real, agente `testador`) |

## Fidelidade vs. pragmatismo — resumo desta leva

| Área | Fidelidade |
|---|---|
| Superfície de membro das classes novas | **Exata** — gerada do dump fixado, mesmo filtro de quatro eixos de A.4 |
| Contrato de `GetAsync`/`SetAsync`/`UpdateAsync`/`RemoveAsync`/`IncrementAsync` (aridade, ordem, `nil` abortando, `keyInfo`) | **Exato** |
| Memoização de `GetDataStore` por `(name, scope)` | **Exata** (doc oficial) |
| Deep copy na leitura e na escrita do DataStore | **Exata** — sem ela o LuauBench esconderia bug real |
| Validação de limite (50 chars, 4 MiB, valor serializável) | **Exata** em comportamento; **mensagem** de erro é aproximação de boa-fé |
| Persistência entre execuções | **Não existe nesta leva.** Store vive e morre com o processo. Contrato de injeção já fechado (L2.1.2) |
| Budget / throttling de DataStore | **Não simulados.** `GetRequestBudgetForRequestType` devolve constante grande e fixa. Motivo em L2.1.4 |
| Erro transitório de DataStore | **Nunca injetado** (determinismo) |
| Transform de `UpdateAsync` que yielda | **Detectada e erra** — divergência que passaria no banco e falharia em produção |
| `HttpService` sem `--allow-http` | **Exata** — é um lugar Roblox com HTTP desligado, que é o default do Roblox |
| `HttpService` com `--allow-http` | Rede real. Sem `Timeout` (Lune 0.10.5 não oferece); sem bloqueio de `roblox.com`; sem limite de 500/min |
| `HttpService` e destinos locais/privados | **Mais restritivo que o Roblox**, de propósito (L2.2.4). Segunda flag para liberar |
| `MessagingService` num processo | **Fiel** a um jogo com um servidor: o publisher recebe o próprio eco (evidência empírica) |
| `MessagingService` entre servidores | **Não existe.** Um processo, um servidor |
| Ordem de entrega entre assinantes | **Aproximação** (ordem de inscrição); o Roblox não garante ordem |
| Grupos de colisão (`WorldRoot`/`PhysicsService`) | **Exatos** — 32 grupos, `"Default"` pré-registrado, colidem por padrão. Nenhuma física simulada, e nenhuma é necessária |
| `Lighting.ClockTime`/`TimeOfDay`/minutos | **Acoplados**, como no Roblox. Formato de leitura com zero-padding: aproximação |
| `Lighting.LightingChanged` | **Fiel**, incluindo as quatro propriedades que **não** o disparam |
| `Lighting.GetSunDirection`/`GetMoonDirection` | **Nunca simulados** — sem fórmula pública. Stub `[LuauBench]` permanente |
| `Lighting.GetMoonPhase` | **Exato** (`0.75`) |
| `SoundService` | **Superfície e nada mais.** Propriedades guardam e devolvem; métodos erram alto |
| Latência de toda API `Yields` | **Zero** (um passo de scheduler). Divergência declarada em L2.0.1 |
| `TweenService` | **Ausente**, com erro nomeado — bloqueada por `Enum` + `TweenInfo` |

## Riscos e decisões

- **A superfície de rede é o único risco novo de segurança do projeto inteiro.** Mitigações, todas obrigatórias: default off (que é também o default do Roblox), flag explícita, segunda flag para destinos locais/privados, linha de auditoria em `--verbose`, e revisão dedicada da sub-leva B por `revisor-services` **e** `revisor-cli`. Nada disso é opcional.
- **`GetRequestBudgetForRequestType` devolvendo constante pode mascarar um bug de throttle real do usuário.** Aceito, e o motivo está em L2.1.4: a alternativa (simular a fórmula com zero jogadores) quebraria código que funciona em produção — falha por comissão, que este projeto já decidiu ser pior que falha por omissão.
- **Store só em memória some entre execuções.** Aceito nesta leva, com o contrato de persistência já fechado para não ser improvisado depois. Declarado no relatório e no comentário do módulo, nunca silencioso.
- **`AsyncCall.Yield` sem latência não reproduz corrida de janela larga.** Declarado; `--async-latency` fica registrado como extensão futura, fora do namespace da classe.
- **Estado de singleton em `local` de módulo** (`DataStoreService`, `HttpService`, `MessagingService`) depende da invariante "um processo, sem reset". Mesmo gatilho já registrado por `ClassRegistry`: watch mode que reinicie o `DataModel` sem reiniciar o processo volta ao arquiteto.
- **Assinatura viva de `MessagingService` não mantém o `Scheduler` vivo.** `luaubench run` termina quando não há mais trabalho pendente, mesmo com assinaturas abertas — divergência declarada (no Roblox o servidor continua de pé). Sem isso, um `SubscribeAsync` solto travaria a CLI para sempre.
- **`_LuauBench*` como prefixo de estado privado** é o que impede colisão com um membro futuro do dump. Critério de revisão explícito: chave de estado privado sem o prefixo é reprovada.
- **Regenerar `generated/**` toca ~30 arquivos de uma vez.** Mesma disciplina da leva 1: ninguém edita à mão dentro de `generated/`, e `revisor-services` reprova qualquer diff manual lá.
- **`.project.json` inválido** — território de `cli`, inalterado. O que esta leva acrescenta é que `GetService("DataStoreService")`/`("HttpService")`/`("MessagingService")`/`("PhysicsService")`/`("SoundService")` param de errar `[LuauBench] … not simulated yet` e passam a devolver instância — nenhuma outra classe muda de estado.

## O que deliberadamente NÃO fazer agora

- **Não** implementar `TweenService`/`Tween`/`TweenBase` — bloqueadas por `Enum`/`EnumItem` + `TweenInfo`.
- **Não** persistir o DataStore em disco nesta leva, e **nunca** chamar `@lune/fs` de dentro de `services`.
- **Não** simular budget, throttling, fila de requisições, nem erro transitório de DataStore.
- **Não** simular "Studio sem API access" nem "jogo não publicado" — o LuauBench sempre tem acesso ao próprio store.
- **Não** implementar `ListDataStoresAsync`, `BatchGetAsync`, `GetVersionAtTimeAsync`, `RemoveVersionAsync`, `OnUpdate`.
- **Não** dar rede por padrão, e **não** implementar rede sem as duas flags e a linha de auditoria.
- **Não** implementar bloqueio de `roblox.com` nem o erro client-only de `HttpService` — confirmados só por fonte secundária, e o LuauBench é sempre servidor.
- **Não** dar a `PlayLocalSound` tratamento de `RejectingSignal` — regra B.5.5 exige citação ao vivo, que não existe.
- **Não** simular `GetSunDirection`/`GetMoonDirection` nem depois de `Vector3` existir.
- **Não** "corrigir" o `Default` de `RespectFilteringEnabled` para bater com a doc — o dump é a fonte única.
- **Não** implementar `WorldModel`/`UseWorkspaceCollisionGroups`, nem os 7 métodos `Deprecated` de `PhysicsService`.
- **Não** criar `luaubench.toml` — as duas flags de HTTP cabem em `Args.Command`, e a Decisão 10 de `cli` continua valendo.

## Pendências para o `pesquisador` (nenhuma bloqueia; todas antes de `revisor-services` aprovar)

1. Fórmula numérica do budget de DataStore, lida linha a linha do Markdown bruto oficial (dois fetches divergiram). Só importa se um dia houver modo de throttle opt-in.
2. Mensagem exata para valor não serializável em `SetAsync`/`UpdateAsync` (`NaN`, função, `Instance`, chave mista).
3. `RegisterCollisionGroup` com nome já registrado: erra ou é idempotente? E há restrição cliente/servidor?
4. `Lighting.ClockTime` escrito fora de `[0, 24)`: wrap, clamp ou erro? E `TimeOfDay` lido tem zero-padding?
5. Texto verbatim do erro de `HttpService` com HTTP desabilitado, e do erro de `PlayLocalSound` no servidor (este último decide se B.5.5 se aplica).
6. `GetGlobalDataStore()` devolve `ClassName == "GlobalDataStore"` ou `"DataStore"` no motor real? (O dump diz `DataStore`; seguimos o dump.)

