# task-cli-038 — `$properties` do Rojo vira HIDRATAÇÃO (SetPropertyRaw), não escrita de script

**Data:** 2026-09-07
**Território tocado:** `src/cli/TreeMaterializer.luau`, `src/cli/Messages.luau`, `src/cli/TreeMaterializer.spec.luau`, mais 3 fixtures novas em `src/cli/fixtures/tree-materializer/` e a fixture `properties` existente atualizada.
**Depende de (concluídas e commitadas):** task-runtime-039 (`Runtime.MemberDescriptor.ScriptVisible`), task-services-035 (schema gerado inclui toda `Property` do dump, load-only marcadas `ScriptVisible=false`).

## O que foi feito

`TreeMaterializer.applyProperties` agora bifurca por instância (decisão tomada uma vez por nó, via `Runtime.ClassRegistry.IsRegistered(instance.ClassName)`):

**CAMINHO A — instância ESTRITA** (todo nó real do projeto):
1. `Name`/`Parent`/`ClassName` → `Diagnostic` warning `materialize/structural-property-ignored`, SKIP. Paridade literal com `rojo build` (`project.rs:234-260`). Fecha a divergência em que `$properties.Name` antes RENOMEAVA a instância.
2. Resolve o descritor via `findMemberDescriptor` (schema achatado, que agora também enxerga as entradas load-only de task-services-035). `nil` → error `materialize/invalid-property` com `Messages.MaterializePropertyNotAMember` (mesma frase do runtime — "X is not a valid member of Y" — construída pelo cli, citando `instance.ClassName`/`instance:GetFullName()`, não mais colhida de `pcall`). `Kind ~= "Property"` (Event/Callback) → error `materialize/invalid-property` com `Messages.MaterializePropertyNotAProperty` — barreira dura que garante que nenhum evento vira gravável por projeto (testado com `Instance.ChildAdded`, exemplo literal do desenho).
3. Decodificação INALTERADA (`resolvePropertyValue`/`ValueTypes.Decode.FromRojoJson`, os 3 diagnósticos existentes).
4. Escrita por `Runtime.Instance.SetPropertyRaw`, dentro de `pcall` + `stripEngineErrorLocation` (ver "CORREÇÃO DE REVISÃO", abaixo) — ignora `ReadOnly` E `ScriptVisible`, exatamente como o `rojo build` real ignora `scriptability`/`serialization`.

**CAMINHO B — instância LENIENTE** (só `game`/DataModel): intocado — `writable[key] = value` dentro de `pcall` + `MaterializePropertyAssignmentFailed`, exatamente como antes. `PlaceId`/`JobId`/`GameId`/`PlaceVersion` continuam recusadas (DV-2, comentada no código).

Divergências DV-1 (dado morto invisível), DV-5 (Name/Parent/ClassName skip), DV-6 (`$properties.Source` sobrescreve o `$path`) declaradas em comentário no cabeçalho de `TreeMaterializer.luau` e reproduzidas por teste.

## CORREÇÃO DE REVISÃO (regressão real, não cosmética)

O revisor achou que a escrita final de A4 (`Runtime.Instance.SetPropertyRaw`) rodava SEM `pcall` — mas `SetPropertyRaw` dispara `Changed:Fire(key)` de forma SÍNCRONA (`Instance.luau`), que pode invocar um listener que `services` já conectou no bootstrap (`behavior/Lighting.luau`, o listener de `TimeOfDay`, que chama `parseTimeOfDay` e `error()`a pra qualquer string malformada). `resolvePropertyValue` (A3) só valida FORMA — `"not-a-real-time-boom"` é uma `string` válida pro decode de uma propriedade `string` comum, então o listener É alcançado. `Signal.Fire` (`Signal.luau`) isola cada listener com `pcall` individual, mas RE-LANÇA o primeiro erro depois do laço quando a thread chamadora não é gerida pelo `ThreadBroker` — exatamente o caso de `Materialize` rodando antes do `scheduler:Run`. Sem proteção, esse erro escapava cru até `luaubench run`, derrubando o processo inteiro com stack trace cru vazando o caminho de instalação em disco — reabrindo a classe de vazamento que task-cli-010/011 já tinham fechado.

**Reproduzi o bug isoladamente antes de aplicar o fix** (revert temporário do `pcall`, rodei o teste novo, confirmei o crash citando literalmente `[LuauBench] Lighting.TimeOfDay: "not-a-real-time-boom" não bate com nenhum formato reconhecido...` propagando cru até o `assert` do teste; restaurei o fix, teste voltou a passar).

**Fix:** a escrita de A4 agora roda dentro do MESMO padrão de `pcall`+`stripEngineErrorLocation` já usado 2x no arquivo (Caminho B, `pcall(Services.new(...))` em `createInstance`) — nenhuma lógica nova, reuso direto. Erro vira `Diagnostic` `materialize/invalid-property` normal via `Messages.MaterializePropertyAssignmentFailed` (a mesma mensagem já usada no Caminho B para esse propósito), sem vazar path.

**Teste de regressão novo:** `TreeMaterializer.spec.luau`, fixture nova `fixtures/tree-materializer/behavior-listener-error/` (`Lighting.$properties.TimeOfDay = "not-a-real-time-boom"`) — confirma que `Materialize` não crasha (`pcall` próprio do teste, mesmo protocolo do teste task-cli-027), que vira `Diagnostic` `materialize/invalid-property` citando `Lighting`/o valor malformado, e que a mensagem não vaza caminho absoluto de disco nem chunk interno (mesma bateria de asserts do teste task-cli-010).

## Mudanças de comportamento (esperadas, verificadas)

- `$properties.Name`/`.Parent`/`.ClassName` não têm mais NENHUM efeito estrutural (antes, `Name` renomeava a instância de verdade).
- `$properties` numa Property real-porém-`ReadOnly` (ex.: fixture `properties`, `className` legado; `Workspace.FilteringEnabled` no template Tiktok) agora **materializa com sucesso**, sem `Diagnostic` — antes produzia `materialize/invalid-property` ("Property is read only").
- `$properties` numa Property load-only (`ScriptVisible=false`, ex.: `Lighting.Technology`) agora **materializa com sucesso** e é legível via `Runtime.Instance.GetPropertyRaw` — antes o schema nem tinha a entrada, e o valor era descartado com `materialize/property-shape-unknown`.
- Para uma instância ESTRITA, um nome de propriedade **inexistente** com valor não-primitivo (array/objeto) agora produz `materialize/invalid-property` (`NotAMember`) em vez do genérico `materialize/property-shape-unknown` — a guarda A2 roda ANTES de qualquer decodificação, para qualquer forma de valor. `property-shape-unknown` continua existindo, mas só é alcançável pelo CAMINHO B (raiz `game`/DataModel) e por uma inconsistência interna defensiva (`ValueType`/`ValueCategory` nil com `Kind=="Property"`, teoricamente inalcançável com o gerador atual).

## Verificação

- `lune run src/cli/TreeMaterializer.spec.luau`: **33/33 passaram** (6 testes novos: 2 para `Lighting.Technology`/`Workspace.FilteringEnabled`, 1 para `Name`/`Parent`/`ClassName` juntos, 1 para `$properties.Source` sobrescrevendo `$path`, 1 para "Mystery"/nome inexistente virando `invalid-property`, 1 de regressão pra correção de revisão — `Lighting.TimeOfDay` malformado; 3 testes existentes reescritos — `properties` fixture principal, o teste de vazamento de path (task-cli-010), e o teste de `Name`/rename do fixture `value-types`).
- Suíte completa de `src/cli/` (16 arquivos `.spec.luau`, incluindo Args/Messages/RunCommand/TreePlanner/init/ScriptRunner/ModuleLoader/OutputFormatter/ProjectFile/Diagnostics/CloudStore/JsonValue/ScriptEnvironment/UnsimulatedGlobals/SyncRules): **todas verdes**, rodada de novo depois do fix de revisão.
- `luau-lsp analyze --platform=standard --settings=".luaurc"` em `TreeMaterializer.luau`/`Messages.luau`/`TreeMaterializer.spec.luau`: **zero diagnósticos**. (Uma checagem mais ampla em `src/cli/*.luau` mostra 4 erros pré-existentes em `RunCommand.luau`/`init.spec.luau`, nenhum dos dois tocado por esta tarefa — mesmo falso-positivo de tooling já documentado em `coder-cli-task-cli-018-2026-09-05.md`.)
- Pipeline real (`ProjectFile.Read` → `TreePlanner.Plan` → `TreeMaterializer.Materialize`) rodado contra `C:\Users\hakor\Documents\Roblox-Games\Tiktok\default.project.json` (READ-ONLY, script de verificação temporário criado e apagado depois, nunca comitado) **duas vezes** (antes e depois do fix de revisão): **1 diagnostic total** nas duas rodadas, `materialize/invalid-class` para `Workspace.Baseplate` ("Part" não simulado — bug pré-existente fora do escopo desta tarefa, já catalogado em `real-roblox-games-pipeline-smoke.scenario.luau`). **Zero `materialize/invalid-property`**, zero crash — confirma que o bug que travava o template do `rojo init` está fechado e que o fix de revisão não regrediu nada.

## API de runtime/services consumida

- `Runtime.ClassRegistry.IsRegistered(className): boolean` — decide CAMINHO A vs B, uma vez por nó.
- `Runtime.ClassRegistry.GetFlattenedSchema` (via `findMemberDescriptor`, já existente) — agora enxerga as entradas `ScriptVisible=false` (task-services-035).
- `Runtime.Instance.SetPropertyRaw(instance, name, value): ()` — via de escrita nova do Caminho A (nunca lançava erro nos casos alcançáveis; confirmado por leitura de código, sem `pcall`).
- `Runtime.MemberDescriptor.{Kind, ScriptVisible}` — `Kind` decide a barreira A2; `ScriptVisible` nunca é lido diretamente por `cli` (só indiretamente, via a entrada existir ou não no schema achatado).
- `instance:GetFullName()` (já em uso no arquivo) — usado para construir `Messages.MaterializePropertyNotAMember` com a mesma frase do runtime.

## API faltante

Nenhuma. Todo o desenho usa API pública já exposta por `runtime`/`services` de tarefas anteriores (task-runtime-039, task-services-035, task-runtime-036/`GetFlattenedSchema`).

## Pendências

- `task-test-rojo-properties-001` (testador, depende desta) ainda precisa rodar o cenário formal em `tests/scenarios/` contra os 3 projetos reais e comparar Diagnostics antes/depois — não fiz isso aqui (fora do meu território), só a verificação pontual acima.
- `task-services-036` (propagar comentário de `Default=nil` deliberado nos arquivos gerados) está em andamento por outro agente em paralelo (`src/services/generated/**`/`tools/generate-services.luau` apareceram modificados no `git status` durante esta tarefa) — não é meu território, não toquei.
