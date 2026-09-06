# Revisão — task-cli-025 (ponte cli: $properties decodificado, globals de valor, UnsimulatedGlobals derivado)

Território: `src/cli/` (read-only). Nada tocado fora dele por esta tarefa (ver seção 10, achado sobre `.claude/tasks.json`/`src/services/` no git status, não atribuível a esta task).

## Metodologia — tudo abaixo foi reproduzido por mim, não aceito do self-report

1. Li `.claude/tasks.json` (task-cli-025 completo), `.claude/agents-memory/arquiteto-valuetypes-2026-09-05.md` §3.4 (subseção cli) e §7 (Decisão 5).
2. Li os 6 arquivos de produção inteiros (`TreePlanner.luau`, `TreeMaterializer.luau`, `ScriptEnvironment.luau`, `UnsimulatedGlobals.luau`, `RunCommand.luau` diff, `Messages.luau`).
3. Rodei `lune run` em cada um dos 15 `*.spec.luau` de `src/cli/` individualmente.
4. Construí fixtures próprias fora do repo e rodei `lune run src/cli/main.luau run <fixture>` de ponta a ponta (não só specs) para os cenários centrais do acceptance.
5. Escrevi e rodei dois scripts de verificação Luau temporários na raiz do repo (deletados logo em seguida, `git status` confirmado limpo depois) para checar programaticamente a interseção Catalog/UnsimulatedGlobals e o comportamento isolado do `TreePlanner`.

## 1. Specs de `src/cli/` — 100% confirmado

Rodei os 15 arquivos individualmente (`lune run src/cli/<Nome>.spec.luau`). Todos passaram, contagem por arquivo:

Args 13/13, Diagnostics 7/7, JsonValue 8/8, Messages 10/10, ModuleLoader 12/12, OutputFormatter 13/13, ProjectFile 17/17, RunCommand 12/12, ScriptEnvironment 8/8, ScriptRunner 7/7, SyncRules 33/33, TreeMaterializer 22/22, TreePlanner 38/38, UnsimulatedGlobals 6/6, init 7/7.

**Total: 213/213 testes, 15/15 arquivos, zero falha.**

## 2. Caso central (Lighting.Ambient → Color3 / Baseplate.Position → Vector3), via `luaubench run` real

Fixture própria (fora do repo) com classes REAIS (não a classe fictícia usada pelo spec de `TreeMaterializer`):
`Lighting.Ambient = [0.5,0.5,0.5]`, `Workspace.InsertPoint = [0.5,0.5,0.5]`.

```
lune run src/cli/main.luau run <fixture>
ServerScriptService.Main: Ambient typeof=Color3 tostring=0.5, 0.5, 0.5
ServerScriptService.Main: InsertPoint typeof=Vector3 tostring=0.5, 0.5, 0.5
... OK ...
EXIT=0
```

Confirmado de ponta a ponta (parse → plan → materialize → sandbox → script), não só chamando `Decode` isolado.

## 3. Tipo leva 2 (não simulado) — warning, nunca erro fatal, nunca escreve cru

Mesma fixture, adicionei `ReplicatedStorage.BadModule` (`ModuleScript`) com `$properties.LinkedSource = [1,2,3]` (`ContentId`, `DataType`, `Simulated=false`). Resultado real via `luaubench run`:

```
warning: [materialize/property-type-not-simulated] [LuauBench] "$properties.LinkedSource" at "tree.ReplicatedStorage.BadModule" resolves to the value type "ContentId", which is not simulated by LuauBench yet -- it was skipped.
```

Script confirmou `badModule.LinkedSource == nil` (default do schema preservado, nunca a array crua `[1,2,3]`). Execução do resto da árvore e do script continuou normalmente (ExitCode não travou nele).

## 4. `$properties` malformado — `materialize/undecodable-property`, nunca crash/valor-lixo

Mesma fixture, `Workspace.GlobalWind = [1,2]` (Vector3 exige array de 3):

```
error: [materialize/undecodable-property] Could not decode "$properties.GlobalWind" at "tree.Workspace" as "Vector3": Vector3 espera um array de 3 números, recebeu array de tamanho 2 (node: tree.Workspace, field: GlobalWind)
```

Cita nó + propriedade + motivo devolvido pelo `Decode`, exatamente como a Decisão 5 pede. Script confirmou `game.Workspace.GlobalWind == nil` (não escreveu a array crua). Resto da árvore/script rodou normalmente.

## 5. `UnsimulatedGlobals` ∩ `Catalog.SimulatedNames()` — vazio, confirmado programaticamente

Script temporário (`ValueTypes.Catalog.SimulatedNames()` vs. `UnsimulatedGlobals.Build()`):

```
SimulatedNames count: 7
UnsimulatedGlobals.Build() count: 28
Overlap count: 0
```

Os 7 nomes da leva 1 (Vector3/Vector2/Color3/CFrame/UDim/UDim2/Enum) estão marcados `Simulated=true` e ausentes de `UnsimulatedGlobals.Build()`.

## 6. `TreePlanner` não decide mais nada sobre tipo — confirmado isoladamente

Chamei `TreePlanner.Plan` sozinho (sem `TreeMaterializer`) sobre a fixture com `Workspace.GlobalWind = [1,2]` (forma "estranha", tamanho errado pra qualquer DataType real):

```
Diagnostics do bag apos Plan: 0
PlanNode.Properties.GlobalWind (bruto): table  -- {1, 2} intacto
```

Zero diagnostic de `TreePlanner` relacionado a tipo de propriedade — `plan/non-primitive-property` está de fato removido (grep confirma: só aparece em comentário/spec de regressão, nenhuma emissão viva) e o valor atravessa intacto como a `Decisão 5` exige.

## 7. Limitação declarada (schema achatado não exposto) — ACHADO MÉDIO

A decisão de **não duplicar** o algoritmo de achatamento de `ClassRegistry` dentro de `cli` é arquiteturalmente correta — reimplementar herança em `cli` divergiria silenciosamente do algoritmo interno real, exatamente o tipo de risco que a regra 00 proíbe. **Isso eu aprovo como está.**

Só que a justificativa registrada ("nenhuma classe hoje coberta por `services` precisa de herança para uma propriedade DataType/Enum") **é factualmente incorreta, e verificável hoje, não hipotética**:

- `Instance.Capabilities` (`SecurityCapabilities`, `DataType`, leva 2) é declarada só no schema PRÓPRIO de `Instance` — **toda classe concreta do sistema** (Workspace, Lighting, ReplicatedStorage, Folder, etc.) a herda sem redeclará-la. Testei ao vivo: `$properties.Capabilities = [1,2,3]` num `ReplicatedStorage` comum produz `materialize/property-shape-unknown` ("no known Property schema entry... for this class"), NUNCA `materialize/property-type-not-simulated` — mesmo a propriedade sendo perfeitamente identificável (é `SecurityCapabilities`, leva 2) se o schema fosse achatado.
- `BaseScript.LinkedSource` (`ContentId`, `DataType`, leva 2) é herdada por `Script`/`LocalScript` (os dois tipos de nó mais comuns de QUALQUER projeto Rojo real) — `Script.luau`/`LocalScript.luau` geradas têm `Schema = {}` vazio, `LinkedSource` só existe no schema próprio de `BaseScript`. Mesmo efeito.
- O próprio comentário do spec novo confirma isso indiretamente: precisou inventar uma classe FICTÍCIA (`TreeMaterializerSpecPart`) pra sequer conseguir testar `materialize/property-type-not-simulated`, porque "nenhuma classe REAL hoje coberta por services tem uma propriedade não-simulada com forma de array" NA PRÓPRIA CLASSE — o que é o sintoma exato da limitação, não uma coincidência.

**Impacto real, avaliado**: nunca crash, nunca escreve valor cru (o comportamento seguro se mantém nos dois diagnósticos) — a diferença é só a PRECISÃO da mensagem. Mas é uma mensagem enganosa hoje, não daqui a uma tarefa futura: um projeto real que declare `$properties.Capabilities`/`$properties.LinkedSource` em QUALQUER classe recebe "LuauBench não conseguiu determinar o tipo" quando na verdade LuauBench SABE o tipo (`SecurityCapabilities`/`ContentId`) e só não o simula ainda — informação estritamente melhor que está sendo descartada por uma limitação de API interna.

**Recomendação**: não é bloqueante (severidade MÉDIA, não ALTA/GRAVE — nunca corrompe nem falha silenciosamente na pior forma), mas (a) corrigir a redação da limitação declarada (no código e no board) para não subestimar o alcance atual — já é uma lacuna viva, não só uma "futura classe tipo Part herdando Position" — e (b) considerar priorizar, numa tarefa de `runtime`, expor `ClassRegistry` achatado publicamente (ex.: `ClassRegistry.GetFlattenedSchema(className): ClassSchema` ou equivalente) mais cedo do que "pendência futura" sugere, já que `Capabilities` sozinha afeta 100% das classes simuladas.

## 8. `Runtime.TypeNameResolver.Set(ValueTypes.TypeNameOf)` — confirmado ao vivo

Mesmo `luaubench run` da seção 2: `typeof(Vector3.new(1,2,3))` dentro do script real devolveu `"Vector3"` (não `"userdata"`/`"table"`), e `tostring` bateu com o formato Roblox (`"0.5, 0.5, 0.5"`/`"1, 2, 3"`). Fixture do próprio coder (`run-e2e/value-types`) também roda e passa via `RunCommand.spec.luau` (teste novo, `ExitCode == 0`).

## 9. `--!strict` / zero `any`

Os 6 arquivos de produção (`TreePlanner.luau`, `TreeMaterializer.luau`, `ScriptEnvironment.luau`, `UnsimulatedGlobals.luau`, `RunCommand.luau`, `Messages.luau`) têm `--!strict` na primeira linha. Grep por `\bany\b` só encontra ocorrências dentro de COMENTÁRIOS explicando por que um cast por `unknown` NÃO é um `any` disfarçado — nenhum `:: any` real em código executável.

## 10. Território limpo

`git diff --stat` do que pertence a task-cli-025 toca só os 6 arquivos de produção + 6 specs + 2 fixtures novas, todos em `src/cli/`. O `git status` do repo mostra TAMBÉM `src/services/behavior/*`/`src/services/datastore/*` e `.claude/tasks.json` modificados — investiguei: pertencem a `task-services-019` (comentário no próprio diff cita a tarefa) e a uma mudança de coluna de `task-services-020` feita pelo agente concorrente rodando em paralelo (nota de concorrência do pedido) — **nenhuma linha de `runtime/`, `valuetypes/` ou o restante de `services/` foi tocada por task-cli-025**. Nenhum resíduo dos meus scripts de verificação temporários ficou no repo (removidos e `git status` reconferido).

## Veredito

**APROVADO COM RESSALVAS**

Um achado MÉDIO (seção 7): a limitação declarada sobre schema achatado é uma decisão arquitetural correta (não duplicar `ClassRegistry` em `cli`), mas a justificativa de que "nenhuma classe hoje precisa disso" é factualmente incorreta e demonstrável (`Instance.Capabilities` afeta todas as classes; `BaseScript.LinkedSource` afeta `Script`/`LocalScript`) — o gap já é real hoje, produzindo uma mensagem de diagnóstico menos precisa (`property-shape-unknown` em vez de `property-type-not-simulated`) para qualquer projeto que declare essas propriedades via `$properties`. Nunca causa crash, corrupção ou escrita de valor cru — a ressalva é sobre a precisão do diagnóstico e a exatidão do relatório da tarefa, não sobre segurança/corretude funcional.

Todo o resto do acceptance foi reproduzido e confirmado pessoalmente: 213/213 testes, ambiguidade Color3/Vector3 resolvida corretamente via `luaubench run` real, tipo leva 2 sempre warning `[LuauBench]` nunca fatal, forma malformada sempre `undecodable-property` citando motivo, `UnsimulatedGlobals`/`Catalog` sem interseção, `TreePlanner` comprovadamente cego a tipo, `typeof` correto de ponta a ponta, `--!strict` sem `any` real, território limpo.
