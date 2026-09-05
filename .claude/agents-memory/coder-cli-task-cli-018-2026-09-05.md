# [task-cli-018] Propagar Source/SourcePath/$properties da raiz de projeto (aninhado e de topo)

## Arquivos

**Modificados:**
- `src/cli/TreePlanner.luau` — tipo `RootResolution` (interno), `copyPlanProperties`, `planProjectTree` devolve `(RootResolution?, {PlanNode})`, ramo de projeto aninhado de `resolveCore` repassa `Source`/`SourcePath`/`Properties` da raiz aninhada, `InstancePlan.RootProperties` (campo aditivo), warning `plan/root-source-ignored` em `TreePlanner.Plan`, exceção estreita na checagem `plan/class-name-conflict` (ver "Achado" abaixo).
- `src/cli/Messages.luau` — `Messages.PlanRootSourceIgnored(nodePath, sourcePath)`.
- `src/cli/TreeMaterializer.luau` — `applyProperties` muda de `(instance, node: PlanNode, bag)` para `(instance, properties, nodePath, bag)`; `TreeMaterializer.Materialize` aplica `plan.RootProperties` no `game` logo após a checagem `materialize/root-not-datamodel`.
- `src/cli/TreeMaterializer.spec.luau` — `RootProperties = {}` adicionado aos 8 `InstancePlan` montados à mão; +1 teste (`RootProperties` aplicado no `game`, via fixture real).
- `src/cli/TreePlanner.spec.luau` — +6 testes (3 formas de raiz de projeto aninhado, merge de `$properties`, `InstancePlan.RootProperties` de topo, warning `plan/root-source-ignored`).

**Criados (fixtures):**
- `src/cli/fixtures/tree-planner/nested-project-root-is-file/` (+ `pkg/`)
- `src/cli/fixtures/tree-planner/nested-project-root-is-init-dir/` (+ `pkg/src/`)
- `src/cli/fixtures/tree-planner/nested-project-root-is-plain-folder/` (+ `pkg/src/`)
- `src/cli/fixtures/tree-planner/nested-project-root-properties-merge/` (+ `pkg/`)
- `src/cli/fixtures/tree-planner/root-source-ignored/`
- `src/cli/fixtures/tree-materializer/root-properties/`

## Comando(s)/fluxo

Nenhuma mudança de comando — a correção é inteiramente dentro de `TreePlanner.Plan`/`TreeMaterializer.Materialize`, consumidas por `RunCommand` sem alteração de assinatura pública.

## API de runtime/services consumida

Nenhuma API nova. `TreeMaterializer.Materialize` reusa `Runtime.Instance` (estrutural: `game: Runtime.DataModel` já é aceito onde `Runtime.Instance` é esperado, `DataModel = Instance & {...}`) — mesmo padrão já usado para `materializeNode(root, game, game, ...)`.

## PARTE 1 — bug ALTO (nested project perdendo Source) — CONFIRMADO CORRIGIDO

`planProjectTree` (`TreePlanner.luau`) agora devolve um `RootResolution {ClassName, Source, SourcePath, Properties}` em vez de só `ClassName`. O ramo de projeto aninhado de `resolveCore` usa `nestedRoot.Source`/`nestedRoot.SourcePath` (antes: `nil` literais) e inicia `nestedProperties` com uma cópia de `nestedRoot.Properties` antes de aplicar o `$properties` do nó externo por cima (externo continua vencendo em chave repetida — comportamento já shipado, preservado e testado).

**Verificação end-to-end contra o projeto REAL do usuário** (`C:\Users\hakor\Documents\Roblox-Games\AnimeFallen\default.project.json`, read-only, dois scripts probe temporários criados e apagados em `src/cli/_task018_probe.luau`/`_task018_probe2.luau` — `git status` confirma zero resíduo):

- `TreePlanner.Plan` real sobre o projeto inteiro: **todos** os pacotes Wally testados agora materializam com `Source` populado — `ProfileStore` (64588 bytes), `Jecs` (109448 bytes), `Promise` (60896 bytes), `Fusion` (2850 bytes), `Sera` (56 bytes), `lync` (11346 bytes) e dezenas de módulos filhos deles. Zero diagnósticos de erro relacionados a esta correção (só os 4 warnings pré-existentes e não relacionados: `$properties.Ambient` sendo array, e 3x `wally.toml` não suportado).
- `TreeMaterializer.Materialize` real + `game:FindFirstChild` navegando até `ServerPackages._Index["ddashdev_profilestore@1.0.4"].profilestore` e lendo `Runtime.Instance.GetPropertyRaw(instance, "Source")`: **64588 bytes**, não vazio. `require(ServerPackages.ProfileStore)` deixa de devolver módulo vazio.
- As 2 falhas de `Materialize` observadas nesta rodada real (`materialize/invalid-property` em `Lighting.Technology`, `materialize/service-not-simulated` em `SoundService`) são **pré-existentes, sem relação com esta task** (cobertura de propriedade/Service fora da leva atual) — não regressões.

Suítes existentes de `cli`/`runtime`/`services` (29 arquivos `.spec.luau`, todos rodados via `lune run`) permanecem 100% verdes — nenhum nó que já tinha `Source` mudou de valor.

## PARTE 2 — raiz de topo (RootProperties + warning) — implementada, com um achado

`InstancePlan.RootProperties` (campo aditivo) é preenchido por `TreePlanner.Plan` a partir do `$properties` da raiz de topo, e `TreeMaterializer.Materialize` aplica isso no `game` via a mesma `applyProperties`/`materialize/invalid-property` que qualquer `PlanNode` já usa — testado com fixture real (`tree-materializer/root-properties`) e confirmado.

### Achado — a checagem `plan/class-name-conflict` pré-existente tornaria `plan/root-source-ignored` código morto

A Decisão 15 descreve `{"$className": "DataModel", "$path": "algo.lua"}` como o único caminho de entrada pro warning `plan/root-source-ignored` ("a classe explícita vence e sobra um Source sem destino"). Rastreei `resolveCore` (a checagem de conflito já existente, `plan/class-name-conflict`, testada desde antes desta task): "$className explícito + $path que resolve pra algo diferente de Folder" **sempre** erra ali, e retorna `nil` **antes** de chegar no ponto que devolveria `Source` — nenhum `$path` que produz `Source` (Script/LocalScript/ModuleScript, arquivo simples ou pasta com `init.*`) jamais resolve pra `Folder`, que é a única exceção tolerada. Ou seja: **sem alguma mudança, o cenário que a Decisão 15 descreve para o warning é inalcançável por qualquer `.project.json` legal.**

Confirmei isso rodando a fixture literal do acceptance (`{"$className": "DataModel", "$path": "algo.lua"}`) contra o código **antes** de eu tocar a checagem de conflito: o diagnóstico real era `plan/class-name-conflict`, nunca `plan/root-source-ignored`.

**Decisão que tomei:** adicionei uma exceção ESTREITA em `resolveCore` (`TreePlanner.luau`, comentário citando task-cli-018 no próprio ponto) — só quando `isRoot == true` **e** `explicitClassName == "DataModel"`, a checagem de conflito não dispara mais, e a raiz segue como "classe explícita vence" (texto literal da Decisão 15), deixando o `Source` computado sem destino para o warning novo tratar. **Verificado seguro por três vias:** (1) a condição exige `isRoot`, então nenhum nó não-raiz é afetado — a fixture/teste `class-name-conflict` (não-raiz) continua verde; (2) busquei em **todas** as fixtures do repositório (`tree-planner`, `tree-materializer`, `run-e2e`) por um `.project.json` cuja raiz combine `$className: "DataModel"` com `$path` — nenhuma existe, então nenhum teste hoje dependia do erro disparando nesse ponto; (3) as 3 suítes completas (`cli`/`runtime`/`services`, 29 arquivos) continuam 100% verdes depois da mudança.

Isto é uma leitura de **comportamento**, não uma mudança de **contrato de tipo** (`PlanNode`/`InstancePlan` continuam exatamente como a Parte 1 especificou, "sem mudança de contrato") — mas é uma decisão que ultrapassa o texto literal da task ("SEM mudança de contrato" não mencionava tocar `plan/class-name-conflict"). Sinalizando explicitamente para `arquiteto`/`revisor-cli` escrutinarem esse ponto específico — o comentário no código (`TreePlanner.luau`, na checagem de `finalClassName`) está redigido para ser fácil de encontrar e reverter caso a decisão seja diferente.

Sem essa exceção, eu teria duas opções piores: (a) implementar o warning como código morto e escrever um teste que mostra que ele NUNCA dispara (tecnicamente honesto, mas não cumpre o acceptance), ou (b) não implementar o warning e reportar só a inconsistência. Escolhi a via que deixa a Parte 2 genuinamente funcional, documentada, e reversível a um comentário.

## API faltante

Nenhuma. Toda a correção ficou dentro de `src/cli/` usando só a API pública de `runtime`/`services` já existente.

## Verificação

- `lune run` em **todas** as 29 suítes `.spec.luau` de `src/cli/`, `src/runtime/`, `src/services/`: **100% verdes**, incluindo os 6 testes novos de `TreePlanner.spec.luau` (27/27) e o teste novo de `TreeMaterializer.spec.luau` (17/17).
- `luau-lsp analyze --platform=standard --settings=".luaurc"` em todos os arquivos de `src/cli/` exceto `init.spec.luau`: **exit 0, zero diagnósticos**. `init.spec.luau` (arquivo que eu **não** toquei) dispara o falso-positivo de tooling já documentado no cabeçalho de `src/runtime/init.luau` para qualquer arquivo `init.*` analisado isoladamente — não é regressão desta task.
- Zero `any` introduzido (grep confirmado — as duas ocorrências da palavra em `TreePlanner.luau`/`TreeMaterializer.luau` são dentro de comentário, não de tipo).
- Verificação **end-to-end contra pacotes Wally reais** do usuário (`AnimeFallen`, read-only) via dois probes temporários em `src/cli/_task018_probe*.luau`, apagados ao final (`git status` confirma resíduo zero) — ver "PARTE 1" acima para os números exatos.
- `git status --short` ao final: só os 5 arquivos modificados + 6 diretórios de fixture novos, nada em `src/runtime/`/`src/services/`.

## Pendências

- **Exceção em `resolveCore` (achado acima) precisa de sign-off do arquiteto/revisor-cli** — implementei porque sem ela a Parte 2 é código morto e o acceptance explicitamente pede o teste do warning, mas é uma leitura de comportamento sobre uma guarda já testada, fora do "sem mudança de contrato" literal da Parte 1. Comentário no código aponta exatamente onde reverter se a decisão for outra.
- `$path` absoluto quebrando com erro cru do SO (`TreePlanner.luau:633` na numeração anterior) — pendência já registrada na Decisão 15, deliberadamente **fora** do escopo desta task, não tocada.
- Precedência real do Rojo quando o nó externo e a raiz do projeto aninhado declaram a MESMA chave em `$properties` — mantive "externo vence" (comportamento já shipado, agora coberto por teste dedicado); a Decisão 15 já registra isto como ponto para o `pesquisador` confirmar contra o código-fonte do Rojo, não bloqueante.
