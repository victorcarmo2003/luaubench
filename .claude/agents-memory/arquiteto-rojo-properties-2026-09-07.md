# `$properties` do Rojo vs. Security do dump — Arquitetura da correção (task-cli-037)

**Data:** 2026-09-07
**Entrada obrigatória:** `.claude/agents-memory/pesquisa-rojo-properties-security-2026-09-07.md` (pesquisa concluída, fonte verificada — Rojo 7.7.0 real + `rbx_reflection` v7.0.0 + teste empírico contra `Tiktok/default.project.json`).
**Dump fixado:** `MaximumADHD/Roblox-Client-Tracker @ 28360dea4b90b35dc3fe9f829baae64fb6c50e75` (Roblox `0.737.0.7371584`), `tools/api-dump.lock.json`.

---

## Propósito

Separar, em toda a pilha, o eixo "esta propriedade EXISTE na classe" (usado para hidratar o DataModel a partir do `.project.json`) do eixo "o script do usuário enxerga esta propriedade" (restrito por `Security`/`Tags`/`Capabilities`) — hoje colapsados num só, o que derruba o template padrão do `rojo init`.

---

## 1. Diagnóstico preciso (confirmado por leitura de código, não hipótese)

Três lugares implementam hoje UM eixo só:

| Local | Linha | O que faz hoje |
|---|---|---|
| `tools/generate-services.luau`, `classifySchemaMember` | 402-460 | Passo 2: `NotScriptable` OU `Security.Read ~= "None"` OU tag `WriteOnly` → `included = false`. A propriedade **não existe** no `ClassSchema` gerado. Passo 3: `required_read ∩ reserved` → também excluída. |
| `src/runtime/Instance.luau`, `InstanceMeta.__index`/`__newindex` | 629-697 / 750-797 | Instância ESTRITA: chave fora do `classSchema` → `"X is not a valid member of Y"` em LEITURA e ESCRITA. Chave no schema com `ReadOnly = true` → `"Unable to assign property X. Property is read only"`. |
| `src/cli/TreeMaterializer.luau`, `applyProperties` | 418-456 | Escreve `$properties` por `writable[key] = value` — o **mesmo** `__newindex` que valida escrita de script — e converte o erro do `pcall` em `materialize/invalid-property`. |

Consequência medida no template literal do `rojo init` (`Tiktok/default.project.json`):
- `Lighting.$properties.Technology` → `Security.Read = Security.Write = RobloxScriptSecurity` → nunca chega ao schema → `"Technology is not a valid member of Lighting"`.
- `Workspace.$properties.FilteringEnabled` → `Security.Write = PluginSecurity` → schema com `ReadOnly = true` → `"Property is read only"`.

A pesquisa provou que o `rojo build` real **não consulta nenhum desses eixos**: `src/resolution.rs::find_descriptor` só procura o NOME na cadeia de classes e só lê `property.data_type`; `src/snapshot_middleware/project.rs` só trata `"Name"`/`"Parent"` como caso especial (`log::warn!` + `continue`) e insere qualquer outra chave direto no `HashMap<Ustr, Variant>` do DOM. `scriptability` (o equivalente colapsado de `Security`) e `PropertySerialization` (`CanLoad`/`CanSave`) existem no `rbx_reflection` e **nunca são lidos nesse caminho**.

**Portanto o modelo correto não é "trocar o gate de `Security` por um gate de `Serialization`" — é não ter gate nenhum no caminho de carga, e mover o gate de `Security` para onde ele de fato pertence: o acesso por script.**

---

## 2. Escopo do impacto — medido no dump inteiro, não estimado

Fecho de superclasses de `tools/coverage.luau`: **45 classes**, **258 membros `Property`**.

| Situação hoje | Qtd |
|---|---|
| No schema, graváveis por script | 82 |
| No schema, `ReadOnly` (22 por tag `ReadOnly`, 11 por `Security.Write` elevado) | 33 |
| **Fora do schema** (passo 2: 95 `NotScriptable`, 71 `Security.Read` elevado — com sobreposição —, 1 `WriteOnly`) | 140 |
| **Fora do schema** (passo 3: capability reservada em `Read`) | 3 |

As **143 propriedades hoje ausentes**, por classe:
`Workspace` 48 · `StarterPlayer` 24 · `Instance` 15 · `Model` 11 · `LuaSourceContainer` 7 · `WorldRoot` 7 · `Players` 6 · `StarterGui` 6 · `SoundService` 4 · `ModuleScript` 3 · `RunService` 3 · `DataStoreService` 2 · `Lighting` 2 · `PVInstance` 2 · `Folder` 1 · `Script` 1 · `ServerScriptService` 1.

Os 3 casos de capability reservada: `Script.Source` e `ModuleScript.Source` (`PluginOrOpenCloud`), `RunService.FrameNumber` (`InternalTest`).

Verificações de segurança feitas **contra o dump**, não por suposição:
- **Zero colisão** entre os 143 nomes novos e a superfície fixa de `Instance` (`ClassName`/`Name`/`Parent`, os 5 sinais, os métodos base) — nenhuma entrada nova pode sombrear método/sinal.
- **Zero colisão** entre os 143 nomes novos e qualquer `MethodNames` de qualquer classe do fecho.
- `Event`: 31 hoje excluídos por `Security`/`Tags`. `Callback`: 0. **Nenhum dos dois muda** neste desenho (ver §5, resposta à pergunta 4).

**Veredito sobre "cirúrgico vs. redesenho da tabela A.4":** a tabela de emissão de 4 eixos continua válida como está para `Event`, `Callback` e `Function` (`classifyMethodMember` intocada). Só o ramo `Property` bifurca: o que era "excluída" vira "presente, porém invisível ao script". É uma mudança **de um eixo**, não da tabela inteira.

---

## 3. Decisão de desenho

### D1 — Um único descritor, dois eixos (não dois schemas)

`Runtime.MemberDescriptor` ganha **um** campo:

```luau
-- src/runtime/Instance.luau
export type MemberDescriptor = {
	Kind: MemberKind,
	Default: unknown,
	ReadOnly: boolean,
	ValueType: string?,
	ValueCategory: MemberValueCategory?,

	-- NOVO (task-runtime-039). Eixo de EXISTÊNCIA x eixo de ACESSO POR SCRIPT.
	-- `nil` ou `true` = o script do usuário enxerga este membro (padrão; todo ClassSchema escrito
	-- antes desta tarefa continua válido sem edição — aditivo puro, mesma disciplina de
	-- ValueType/ValueCategory).
	-- `false` = o membro EXISTE estruturalmente na classe (está no Roblox API Dump) mas é
	-- INVISÍVEL ao script: ler ou escrever produz exatamente a mesma resposta que uma chave
	-- ausente do schema produziria ("X is not a valid member of Y"). Serve ao caminho de
	-- HIDRATAÇÃO (`$properties` de um projeto Rojo), que no Rojo real nunca consulta
	-- Security/Scriptability.
	ScriptVisible: boolean?,
}
```

Por que `ScriptVisible` e não `ScriptAccessible`: `ReadOnly` já é o eixo de ESCRITA por script; `ScriptVisible` é o eixo de EXISTÊNCIA para o script. Nomes distintos evitam que um leitor futuro ache que os dois codificam a mesma coisa.

Correspondência 1:1 com o `rbx_reflection::Scriptability` que o Rojo real embute (útil como conferência cruzada, e é literalmente o modelo da implementação de referência — uma tabela de propriedades só, com atributos por propriedade):

| `rbx_reflection::Scriptability` | LuauBench |
|---|---|
| `None` | `ScriptVisible = false` |
| `Read` | `ScriptVisible = true`, `ReadOnly = true` |
| `ReadWrite` | `ScriptVisible = true`, `ReadOnly = false` |

**Alternativa rejeitada:** uma segunda tabela por classe (`LoadableProperties`) separada do `Schema`. Rejeitada porque (a) duplicaria `ValueType`/`ValueCategory` de 115 propriedades ou criaria uma tabela "delta" que todo consumidor teria que lembrar de consultar em segundo lugar; (b) divergiria do modelo da implementação de referência (`rbx_reflection` tem UMA tabela de propriedades com atributos, não duas); (c) `cli` já resolve descritor por `Runtime.ClassRegistry.GetFlattenedSchema` — com D1 não precisa de nenhuma API nova.

### D2 — Regra de emissão do gerador (revisão do ramo `Property` da tabela A.4)

`classifySchemaMember` passa a devolver:

```luau
type SchemaClassification = {
	included: boolean,
	scriptVisible: boolean,   -- NOVO
	readOnly: boolean,
	excludedByCapability: boolean,
}
```

Ordem de avaliação, primeiro casamento vence (só o ramo `Property` muda):

1. `MemberType == "Property"` → **`included = true` SEMPRE** (toda `Property` da classe no dump entra no schema).
   - `NotScriptable` OU `Security.Read ~= "None"` OU tag `WriteOnly` OU `required_read ∩ reserved ~= {}` → `scriptVisible = false`, `readOnly = false` (irrelevante), `excludedByCapability` mantém o valor de hoje para o relatório.
   - Senão → `scriptVisible = true` e os passos 4/5 decidem `readOnly` **exatamente como hoje** (`required_write ∩ reserved`, tag `ReadOnly`, `Security.Write ~= "None"`).
2. `MemberType == "Event"` / `"Callback"` → **regra literalmente inalterada** (passos 2/3 continuam EXCLUINDO do schema; `scriptVisible = true` para os que sobrevivem).
3. `classifyMethodMember` (`Function`/`MethodNames`) → **inalterada**.

Emissão para uma entrada `scriptVisible = false`:
- `Default = nil` sempre — não chamar `computeDefault`. Motivo: o valor é inalcançável por leitura de script e é sobrescrito pela hidratação quando o projeto o define; emitir default real obrigaria a chamar construtor de `ValueTypes`/`enumDefault` no load de classes que hoje nem importam `valuetypes`, com risco de erro alto no load em troca de zero benefício observável. **Registrado no cabeçalho do arquivo gerado como decisão deliberada** (nunca deixar o leitor achar que o dump traz `nil`).
- `ValueType`/`ValueCategory` **SEMPRE emitidos** — é exatamente o dado de que `cli` precisa para decodificar `$properties` (`Lighting.Technology` é `Category = "Enum"`, `Name = "Technology"`).
- **NUNCA** entra em `typeFieldLines` (o `export type` público da classe). Emitir faria o checker Luau aceitar `lighting.Technology` em código de usuário que erra em runtime — divergência estática/dinâmica inaceitável.
- `ScriptVisible = false` emitido literal no descritor; `ScriptVisible = true` emitido literal também (o gerador nunca depende do default `nil`, só schemas escritos à mão em `.spec` dependem).

Relatório do gerador ganha uma seção: `Property presentes no schema porém INVISÍVEIS ao script (load-only)`, com contagem por classe e o motivo (`NotScriptable` / `Security.Read` / `WriteOnly` / capability reservada) — é o que torna a mudança auditável a cada regeneração.

### D3 — Runtime: "invisível" é indistinguível de "ausente", por construção

Em `InstanceMeta.__index` (passo 5) e `InstanceMeta.__newindex` (passos 7/8), a resolução do descritor passa a ser:

```luau
local descriptor = classSchema[key]
if descriptor ~= nil and descriptor.ScriptVisible == false then
	descriptor = nil -- invisível ao script == ausente do schema, para TODOS os efeitos
end
```

...e **todo o resto dos dois caminhos fica byte-a-byte igual**. Isso garante, por construção:
- a resolução de FILHO por nome (passo 7 de `__index`) continua rodando na mesma posição relativa (um filho chamado `Technology` continua resolvendo);
- a mensagem final é a MESMA string já confirmada contra o Roblox real (`"{key} is not a valid member of {ClassName} \"{FullName}\""`);
- o modo LENIENTE não é tocado.

`Instance.SetClassSchema`:
- validação de forma aceita `ScriptVisible` `boolean` ou `nil`; qualquer outro tipo → erro alto (mesma família das validações de `Kind`/`ReadOnly`);
- **não semeia** `Default` nem `Signal` para entrada com `ScriptVisible == false` — a memória por instância fica idêntica à de hoje (as 143 entradas novas não custam nada por instância; a tabela de schema é uma só por classe, congelada e compartilhada).

`Instance.GetPropertyRaw`/`SetPropertyRaw` continuam **exatamente** como estão: já são a via de engenharia que nunca consulta o schema (é por ela que `cli` já guarda `Script.Source` e que `services` já escreve sobre entradas `ReadOnly`). **Nenhuma API nova em `runtime`.**

### D4 — CLI: `$properties` é HIDRATAÇÃO, não escrita de script

`TreeMaterializer.applyProperties` passa a distinguir os dois caminhos:

**Caminho A — instância ESTRITA (tem `ClassSchema`; todo nó real do projeto):**

1. `Name` / `Parent` / `ClassName` → `Diagnostic` `warning`, código `materialize/structural-property-ignored`, e **skip**.
   - `Name`/`Parent`: paridade literal com o Rojo real (`project.rs`: `log::warn!` + `continue`). Hoje o LuauBench RENOMEIA a instância por `$properties.Name` — divergência do Rojo que esta tarefa fecha.
   - `ClassName`: no LuauBench é estado estrutural fora de `data.properties` (assim como `Name`/`Parent`); gravar raw criaria estado morto e silencioso. No `rbx_dom` `ClassName` nem é propriedade — é a classe da instância.
2. Resolver o descritor no schema achatado (`findMemberDescriptor`, que agora enxerga também as load-only).
   - descritor `nil` → `Diagnostic` `error`, `materialize/invalid-property`, mensagem **construída pelo `cli`** (`Messages.MaterializePropertyNotAMember`) com a mesma frase do runtime (`"X is not a valid member of Y"`) — não mais colhida de um `pcall`.
   - descritor com `Kind ~= "Property"` (Event/Callback) → `Diagnostic` `error`, `materialize/invalid-property`, `Messages.MaterializePropertyNotAProperty`. **É a barreira dura que garante que nenhum evento vira gravável por projeto.**
3. Decodificação — **inalterada** (`resolvePropertyValue`, `ValueTypes.Decode.FromRojoJson`, os três diagnósticos existentes).
4. Escrita — `Runtime.Instance.SetPropertyRaw(instance, key, value)`. Ignora `ReadOnly` e ignora `ScriptVisible`, exatamente como o `rojo build` ignora `scriptability`/`serialization`. Sem `pcall`: depois das validações de (1)-(3) não sobra caminho de erro real (mesmo critério já usado para `instance.Parent = parent` em `createInstance`, documentado lá).

**Caminho B — instância LENIENTE (só `game`/DataModel, `IsRegistered == false`):** caminho de HOJE, intocado (`writable[key] = value` dentro de `pcall` + `materialize/invalid-property` via `MaterializePropertyAssignmentFailed`). Ver divergência DV-2 em §4.

### D5 — Sem gate de `Serialization`, sem o caminho do plugin

Não implementar `Serialization.CanLoad`/`CanSave` como gate: a pesquisa provou que o Rojo real não o consulta em nenhum dos dois caminhos, e que `Workspace.FilteringEnabled` (`CanLoad = false`, `Deprecated`, `Hidden`, `NotReplicated`) é escrita com sucesso, exit 0, zero avisos até em `-vv`. Não implementar a checagem de `scriptability` do `plugin/src/Reconciler/setProperty.lua`: é o análogo de "Studio aplicando ao vivo", não de `rojo build` — e o `TreeMaterializer` é batch/offline.

---

## 4. Fidelidade vs. pragmatismo — divergências DECLARADAS

| # | Divergência | Por quê / onde documentar |
|---|---|---|
| DV-1 | Valor hidratado numa propriedade invisível fica só no DOM: o script não lê, e **nenhum comportamento simulado reage a ele** (`Lighting.Technology = Voxel` não muda render nenhum porque não há render). | Regra 02 (fidelidade cede onde exigiria render/física). Comentário em `applyProperties` + relatório. |
| DV-2 | `$properties` na raiz `game` (DataModel, leniente) continua no caminho antigo — `PlaceId`/`JobId`/`GameId`/`PlaceVersion` continuam recusadas com `"Property is read only"`. O Rojo real aceitaria. | São estado do HOST (o LuauBench é quem os define), não do projeto. Divergência deliberada e pequena; abrir isso é decisão do usuário, não desta tarefa. Comentário em `applyProperties`. |
| DV-3 | `ValueType` da leva 2 de `valuetypes` (Rect/NumberRange/TweenInfo/...) continua `warning` + skip (`materialize/property-type-not-simulated`). O Rojo real escreveria. | Divergência JÁ declarada (task-cli-025), mantida sem mudança. |
| DV-4 | Classe não simulada continua `error` antes de qualquer `$properties`. | Divergência JÁ declarada, mantida. |
| DV-5 | `$properties.Name`/`.Parent` passam a ser **warning + skip**. Isso **fecha** uma divergência (hoje renomeiam) e é paridade exata com o Rojo. `ClassName` entra na mesma regra por analogia estrutural, sem contraparte literal no Rojo. | Comentário citando `project.rs` linhas 234-260. |
| DV-6 | `$properties.Source` num `Script`/`ModuleScript` passa a ser aceito e **sobrescreve** o `Source` vindo do `$path` (a escrita de `node.Source` roda antes de `applyProperties`, `TreeMaterializer.luau:626-632`). O Rojo real também aceita `Source` em `$properties`. | Não concede poder novo (o `$path` do próprio projeto já traz código arbitrário). Teste obrigatório fixando a precedência. |
| DV-7 | `Event`/`Callback` com `Security` elevado continuam **ausentes** do schema (não viram load-only invisíveis). | `$properties` só carrega `Property`; `rbx_reflection` nem modela eventos. Emitir Event invisível custaria um `Signal` por instância sem nenhum consumidor. Declarado no cabeçalho do gerador. |

Não-divergência que vale registrar: **o eixo de script não muda em nada.** Se hoje o script não lê `Lighting.Technology`, depois desta leva ele continua não lendo, com a mesma mensagem. Se algum dia se confirmar (pesquisa) que o Roblox real deixa um `Script` comum ler `Technology`, isso é uma tarefa separada de `Security` — não entra aqui.

---

## 5. Resposta direta às 4 perguntas da tarefa

1. **Onde mora a distinção:** no `MemberDescriptor` (território `runtime`), como o campo `ScriptVisible`. O `ClassSchema` passa a ser o eixo ESTRUTURAL (tudo que a classe tem no dump, para `Property`); `ScriptVisible` é o eixo de ACESSO POR SCRIPT; `ReadOnly` continua sendo o eixo de ESCRITA POR SCRIPT. `TreeMaterializer` ignora os dois últimos e escreve por `SetPropertyRaw`.
2. **`ReadOnly` continua bloqueando runtime, mas não `$properties`:** sim, exatamente isso — e **sem nenhuma exceção adicional**. Fidelidade 100% ao `rojo build`: bypass total de `Security`, `ReadOnly` e `Serialization` na hidratação. As únicas recusas são (a) nome que não existe como `Property` na cadeia de classes, (b) `Name`/`Parent`/`ClassName` (warning+skip, paridade Rojo), (c) valor não decodificável / value type ainda não simulado (divergências DV-3 já declaradas).
3. **Escopo:** 143 propriedades em 17 das 45 classes do fecho passam a existir como load-only (números e motivos em §2). É correção **cirúrgica no eixo `Property`** — `Event`/`Callback`/`Function` da tabela A.4 ficam intocados. Não há redesenho do eixo Security/Capabilities como um todo.
4. **`Event`/`Callback`:** nenhuma brecha aberta, por **duas** barreiras independentes: (i) o gerador nunca emite Event/Callback invisível (D2, item 2) — o universo de load-only é 100% `Property`; (ii) `applyProperties` recusa explicitamente qualquer descritor com `Kind ~= "Property"` antes de chegar em `SetPropertyRaw` (D4, caminho A, passo 2). Uma barreira sozinha já bastaria; as duas juntas são defesa em profundidade, no mesmo espírito das defesas já existentes em `createInstance`. Métodos (`MethodNames`) nunca estão no schema, então caem na recusa "não é membro" — e ficou verificado contra o dump que **nenhum** dos 143 nomes novos colide com método/sinal/superfície fixa.

---

## 6. Divisão por território

| Território | O que constrói | Contrato com o vizinho |
|---|---|---|
| `runtime` | Campo `ScriptVisible` em `MemberDescriptor`; `__index`/`__newindex` tratam `false` como ausente; `SetClassSchema` valida o campo e não semeia default de invisível. | **Expõe** para `services`: o campo no `export type MemberDescriptor` (aditivo, `nil` == visível). **Expõe** para `cli`: `GetFlattenedSchema` passando a devolver também as entradas invisíveis; `Instance.SetPropertyRaw` já público, sem mudança. |
| `services` | `classifySchemaMember` bifurca o ramo `Property`; emissão de `ScriptVisible` + `ValueType`/`ValueCategory` sem `Default` e sem campo no `export type` público; nova seção no relatório; regeneração de `src/services/generated/**`. | **Consome** `Runtime.MemberDescriptor.ScriptVisible`. **Entrega** para `cli`: descritores de load-only visíveis via `GetFlattenedSchema`. |
| `cli` | `applyProperties` com caminho de hidratação (guard estrutural, validação contra schema achatado, `SetPropertyRaw`); 3 mensagens novas; caminho leniente preservado. | **Consome** `Runtime.ClassRegistry.GetFlattenedSchema` + `Runtime.Instance.SetPropertyRaw`. Não importa nada interno de `services`. |

Grafo inalterado: `services` → `runtime`, `cli` → (`runtime`, API pública de `services`). Nenhuma dependência nova, nenhum módulo novo, nenhuma API nova em `runtime`.

---

## 7. Fluxo de dados (fim a fim, com o caso do `Tiktok`)

```
Full-API-Dump.json (28360dea)
  └─ tools/generate-services.luau  classifySchemaMember
       ├─ Lighting.Technology     Security.Read=RobloxScriptSecurity
       │    → { Kind="Property", Default=nil, ReadOnly=false,
       │        ScriptVisible=false, ValueType="Technology", ValueCategory="Enum" }
       └─ Workspace.FilteringEnabled  Security.Write=PluginSecurity
            → { Kind="Property", Default=nil, ReadOnly=true,
                ScriptVisible=true, ValueType="bool", ValueCategory="Primitive" }
  └─ src/services/generated/classes/{Lighting,Workspace}.luau  (Schema)
  └─ ClassBuilder → Runtime.ClassRegistry.Register → SetClassSchema
       (invisível: entra no schema, NÃO semeia default)

default.project.json (rojo init)
  └─ ProjectFile → TreePlanner  (PlanNode.Properties, forma bruta do JSON)
  └─ TreeMaterializer.applyProperties
       ├─ "Technology" = "Voxel"   → descritor existe (Kind=Property) → Decode Enum
       │                            → SetPropertyRaw  →  data.properties.Technology = Enum.Technology.Voxel
       └─ "FilteringEnabled" = true → boolean primitivo, descritor existe
                                    → SetPropertyRaw  →  data.properties.FilteringEnabled = true

Script do usuário
  ├─ lighting.Technology       → ScriptVisible=false → "Technology is not a valid member of Lighting ..."  (igual a hoje)
  ├─ workspace.FilteringEnabled → true                                                                     (igual a hoje)
  └─ workspace.FilteringEnabled = false → "Unable to assign property FilteringEnabled. Property is read only" (igual a hoje)
```

---

## 8. Riscos e decisões

- **R1 — consumidor futuro esquece `ScriptVisible`.** Os 3 consumidores atuais de schema (`__index`, `__newindex`, `SetClassSchema` do `runtime`; `findMemberDescriptor` do `cli`) são todos tocados nesta leva. Mitigação: teste em `runtime` que prova a neutralidade observável (uma entrada invisível é indistinguível de uma chave ausente, em leitura E escrita, inclusive com filho de mesmo nome presente) + comentário no `export type`.
- **R2 — diff gigante em `src/services/generated/**`.** 143 linhas novas de schema espalhadas por 17 arquivos gerados. Revisor precisa saber que é 100% gerado; a revisão real é do gerador + do relatório, não do diff.
- **R3 — `Workspace` ganha 48 entradas.** Tabela de schema por classe, congelada e compartilhada; sem seeding por instância. Custo: carregamento de uma tabela literal maior. Aceito e declarado.
- **R4 — hidratação dispara `Changed`.** `SetPropertyRaw` dispara `Changed`, exatamente como o `__newindex` de hoje já dispara — **nenhuma mudança de comportamento**. Nenhum script do usuário rodou ainda nesse ponto; um `behavior/` que conectasse `Changed` no `Initialize` já veria o mesmo hoje.
- **R5 — `.project.json` inválido / propriedade inexistente.** Continua `Diagnostic` por propriedade (nunca derruba o nó nem a árvore), agora com mensagem construída pelo `cli` em vez de colhida de `pcall`. `HasErrors` e exit code seguem a mesma regra de hoje.
- **R6 — `$properties.Source`.** Passa a ser aceito e sobrepõe o arquivo (DV-6). Teste obrigatório fixando a precedência para que ninguém a mude por acidente.

---

## 9. O que deliberadamente NÃO fazer agora

1. **Não** implementar gate por `Serialization.CanLoad`/`CanSave` — o Rojo real não tem (pesquisa, seções 2-4).
2. **Não** reproduzir o caminho do plugin (`setProperty.lua`, checagem de `scriptability` + `Error.UnwritableProperty`) — é o análogo de "Studio ao vivo", não de `rojo build`.
3. **Não** implementar aliases/`SerializesAs`/`PropertyMigration` do `rbx_reflection` (`Workspace.StreamingEnabledAlias` e os outros entram como propriedades comuns invisíveis).
4. **Não** mexer no eixo de `Security` de `Event`/`Callback`/`Function`.
5. **Não** abrir `$properties` na raiz `game` para `PlaceId`/`JobId`/`GameId`/`PlaceVersion` (DV-2).
6. **Não** pesquisar/alterar agora se o Roblox real deixa um `Script` comum LER `Lighting.Technology` — é uma pergunta do eixo de script, independente deste bug; vira tarefa de `pesquisador` se algum dia importar.
7. **Não** simular comportamento para as 143 propriedades hidratadas (elas são dado morto por desenho, DV-1).

---

## 10. Tarefas registradas no board

| ID | Agente | Depende de | Escopo |
|---|---|---|---|
| `task-runtime-039` | `coder-runtime` | — | `ScriptVisible` em `MemberDescriptor`; neutralidade em `__index`/`__newindex`; `SetClassSchema` (validação + não semear invisível); specs de neutralidade. |
| `task-services-035` | `coder-services` | `task-runtime-039` | Bifurcação do ramo `Property` em `classifySchemaMember`; emissão (`ScriptVisible`, `Default=nil`, `ValueType` sim, `export type` não); nova seção no relatório; regeneração completa. |
| `task-cli-038` | `coder-cli` | `task-services-035` | `applyProperties` de hidratação; guard `Name`/`Parent`/`ClassName`; 3 mensagens novas; caminho leniente preservado; specs. |
| `task-test-rojo-properties-001` | `testador` | `task-cli-038` | Cenário fim a fim com o template do `rojo init` (`Tiktok`) rodando limpo, mais os 3 projetos reais de `C:\Users\hakor\Documents\Roblox-Games`. |

Sequência obrigatória (regra 05): `coder-runtime` → `coder-services` → `coder-cli` → `testador`. `revisor-*` de cada território ao fim da respectiva leva.
