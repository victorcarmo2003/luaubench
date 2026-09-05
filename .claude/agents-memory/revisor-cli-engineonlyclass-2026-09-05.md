# Revisão — task-cli-024 (`plan/engine-only-class` no `TreePlanner`)

Data: 2026-09-05. Revisor: `revisor-cli` (read-only). Nada aceito por self-report — todo achado
abaixo foi reproduzido por mim, nesta sessão, com evidência de comando. Task tinha aviso de
"confusão de agentes duplicados" — revisão extra cuidadosa, incluindo checar se algo de fora de
`src/cli/` vazou pra dentro do escopo desta task.

## Contexto lido por inteiro antes de revisar

- `.claude/tasks.json`, `task-cli-024` (descrição + acceptance completos, linhas 1558-1578).
- `.claude/agents-memory/arquiteto-cli-2026-09-05.md`, **Decisão 17** inteira (linhas 1478-1744):
  a guarda de 4 condições, a tabela `IsAbstract`/`Covered`/`IsService` que fecha a armadilha do
  `IsAbstract` cru, `RUNTIME_OWNED_CLASSES`, a tabela "Comportamento resultante" com os 11
  cenários, e a seção "Riscos"/"O que deliberadamente NÃO fazer agora".
- Diff completo (não commitado, working tree) de: `src/cli/TreePlanner.luau`, `src/cli/RunCommand.luau`,
  `src/cli/Messages.luau`, `src/cli/TreePlanner.spec.luau`, `src/cli/TreeMaterializer.spec.luau`, e as
  2 fixtures novas (`engine-only-class-instance/`, `nested-project-root-engine-only-class/`).
- `git log --oneline` confirmou `task-services-014` (`Services.IsEngineOnlyClass`) já está
  **commitada** (`0aff50b`) como dependência fechada; `git diff -- src/services/init.luau` deu
  **vazio** — confirma que esta task não a tocou.

## O que eu reproduzi (evidência)

### 1. `lune run` em todas as 34 suítes de `cli`/`runtime`/`services` — rodadas por mim, uma por
   uma, sem usar o número do coder

```
src/cli/*.spec.luau (15 arquivos) ................ 15/15 suítes verdes
src/runtime/*.spec.luau (9 arquivos) .............. 9/9 suítes verdes
src/services/**/*.spec.luau (10 arquivos) ......... 10/10 suítes verdes
```

Os quatro números específicos que o coder citou, todos batem exatamente:

- `TreePlanner.spec.luau` → **38/38**
- `TreeMaterializer.spec.luau` → **18/18**
- `RunCommand.spec.luau` → **11/11**
- `services/init.spec.luau` → **24/24**

Zero `[FAIL]` em qualquer suíte, nas duas rodadas completas que fiz (uma logo no início da revisão,
outra ao final, depois de ver que outros agentes estavam mexendo em paralelo em `src/runtime`/
`src/valuetypes` — sem impacto nas suítes de `cli`). **Nota de precisão do self-report:** o coder
disse "30 suítes" — o total real de arquivos `.spec.luau` em `cli`+`runtime`+`services` é 34 (15+9+10).
Não é um problema de correção (todas verdes, os 4 números específicos citados batem byte a byte),
só uma contagem total imprecisa no relatório — achado BAIXO, sem ação necessária além de registrar.

### 2. Guarda real em `resolveCore` (`src/cli/TreePlanner.luau:1130-1179`)

Lida linha a linha. Ordem confirmada: bloco `isServiceRoot` (:1130-1144) → guarda nova
(:1146-1179) → bloco de `$properties` (:1181+). `isOutermostRoot` foi içado para :1070 (antes do
ramo `explicitClassName ~= nil`, que começa em :1072) — é expressão pura (`isRoot`,
`normalizePath(currentProjectFilePath)`, `ctx.OutermostProjectFilePath`, nenhum dos três muda entre
a posição antiga e a nova), sem mudança de valor. Confirmei também que o ramo "3) Projeto aninhado"
(:957-1045) retorna **antes** de chegar em `isOutermostRoot`/na guarda nova — um nó com `$path`
apontando para um projeto aninhado nunca passa pela guarda ele mesmo; é a **raiz resolvida do
projeto aninhado** (chamada recursiva de `resolveCore` via `planProjectTree`, com `parentClassName
= nil` sempre — confirmado em `planProjectTree`, :1379) que passa pela guarda. Rastreei isso à mão
contra a fixture nova de projeto aninhado (seção 3, abaixo) e bate.

As 4 condições, exatas:

```lua
local isEngineFixedChild = parentClassName ~= nil and options.IsEngineFixedChild(parentClassName, name, finalClassName)
local isEligibleForEngineOnlyGuard = not isOutermostRoot and not isServiceRoot and not isEngineFixedChild
if isEligibleForEngineOnlyGuard and options.IsEngineOnlyClass(finalClassName) then
```

Confere exatamente com a Decisão 17 ("Guarda decidida (4 condições, uma por ramo real)").

### 3. Os 5 cenários do acceptance — reproduzidos por mim com as fixtures novas, e também com um
   probe independente usando `services` REAL (não `FAKE_OPTIONS`)

`TreePlanner.spec.luau` usa `FAKE_ENGINE_ONLY_CLASSES`/`fakeIsEngineFixedChild` (correto — o módulo
é desenhado para não depender de `services`, Decisão 3). Para não aceitar isso como prova suficiente
de integração real, escrevi um probe fora de `src/cli/` (`_revisor_probe_engineonly.luau`, raiz do
repo, apagado ao final — `git status --short` confirma zero resíduo) requerendo `src/cli/TreePlanner`
+ `src/services` de verdade, chamando `TreePlanner.Plan` com `Services.IsServiceClass`/
`IsEngineFixedChild`/`IsEngineOnlyClass` reais, **antes de `Services.Bootstrap`** (mesma garantia que
a Decisão 17 exige). Resultado:

```
[engine-only-class-instance] plan == nil: true, plan/engine-only-class presente: true
   NodePath=tree.ReplicatedStorage.Bad Field=$className
   Message="tree.ReplicatedStorage.Bad" declares the class "Instance", which the Roblox API Dump
   tags as NotCreatable -- only the engine creates instances of it, never a project node. ...

[nested-project-root-engine-only-class] plan == nil: true, plan/engine-only-class presente: true
   NodePath=tree Field=$className FilePath=.../nested-project-root-engine-only-class/pkg/default.project.json
   Message="tree" declares the class "DataModel", ... "DataModel" is only valid as the root of the
   outermost project.

[basic (regressao)]                 plan/engine-only-class ausente (correto)
[fixed-children (regressao)]        plan/engine-only-class ausente (correto)
[root-source-ignored (regressao)]   plan/engine-only-class ausente (correto)
[nested-project-root-datamodel-conflict (regressao)]  plan/engine-only-class ausente,
   plan == nil (via plan/class-name-conflict, guarda anterior) -- correto
```

Os 5 cenários do acceptance batem: (a) raiz de projeto aninhado `DataModel` sem `init.*` → guarda
nova com `FilePath` do `.project.json` **aninhado** (`pkg/default.project.json`, não o do topo) —
esse é o ganho real sobre `materialize/invalid-class`, confirmado byte a byte; (b) `$className:
"Instance"` num nó comum → mesma família de `Diagnostic`; (c) regressão raiz de topo `DataModel`
sem `init.*` continua passando; (d) regressão `basic`/`fixed-children` continuam sem o novo
diagnóstico; (e) regressão `nested-project-root-datamodel-conflict` continua em
`plan/class-name-conflict` (guarda anterior dispara antes).

### 4. "Mudança de fase" em `TreeMaterializer.spec.luau` — investigado com ceticismo, é real e a
   defesa em profundidade continua alcançável

O teste antigo (`"$className" explícito com Name divergente ('MyScripts') sob StarterPlayer..."`)
foi **adaptado, não removido**: em vez de `planFixture("fixed-child-name-mismatch")` (que agora
seria barrado em `TreePlanner.Plan` antes de chegar no `Materialize`), o teste monta um
`InstancePlan` **à mão**, literal, com `Roots = {{ Name="StarterPlayer", ClassName="StarterPlayer",
IsServiceRoot=true, Children = {{ Name="MyScripts", ClassName="StarterPlayerScripts", ... }} }}` e
chama `TreeMaterializer.Materialize` **direto** sobre essa tabela — nunca via `TreePlanner.Plan`.
Rodei esse teste isolado (`lune run src/cli/TreeMaterializer.spec.luau`, teste
"Materialize (defesa em profundidade...)") e confirmei que ele **ainda passa** e ainda exercita o
`pcall(Services.new)` real dentro de `TreeMaterializer.createInstance` — não é teste morto: o
`InstancePlan` sintético é malformado do jeito que só um chamador direto de `Materialize` (bypassando
`Plan`) produziria, exatamente o cenário que a defesa em profundidade existe para cobrir (Decisão 17,
"O que deliberadamente NÃO fazer agora": "não mover a guarda para `TreeMaterializer` nem remover de
lá a defesa em profundidade"). Um segundo teste novo, logo abaixo, prova que o caminho normal
(`planFixture` de verdade) agora é barrado mais cedo com `plan/engine-only-class`, e explicitamente
assert que `materialize/invalid-class` **não** aparece mais para esse caminho. Os dois testes juntos
provam exatamente a mudança de fase que o coder alegou, sem lacuna de cobertura.

### 5. Achado do ciclo case-insensitive do Windows — reproduzido, não é regressão

Rodei o teste isolado (`nested-project-cycle-case-insensitive/CaseA`) e confirmei `PASS`, `plan ==
nil`, `elapsedSeconds < 10` (sem hang). Tracei a lógica à mão contra o código real:

- `CaseA` (outermost) → `Vendor: {$path: "../CaseB"}` → projeto aninhado real, resolve `CaseB` como
  `Folder` (não dispara a guarda nova: `Folder` não é `IsEngineOnlyClass`).
- Dentro de `CaseB`, `Back: {$path: "../casea"}` (minúsculo) resolve, por case-insensitivity do NTFS,
  para o **mesmo arquivo físico** de `CaseA`, mas como **string** (`normalizePath` não faz lowercase
  — limitação já declarada no cabeçalho do arquivo) o caminho resultante é `.../casea/default.project.json`,
  que **não bate** com a entrada `CaseA` (maiúscula) já presente no `cycleGuard` nem com
  `ctx.OutermostProjectFilePath` (também maiúscula, semeada na primeira chamada).
- Isso faz `resolveCore` processar a raiz de `casea` como se fosse um projeto aninhado **novo**
  (não capturado pelo `cycleGuard` pré-existente, que é comparação de string exata). Essa raiz nova
  tem `parentClassName = nil` (toda raiz de `planProjectTree` é chamada assim — confirmei em
  `planProjectTree`, `:1379`), então `isEngineFixedChild = false`; `isOutermostRoot` compara a forma
  minúscula contra a forma maiúscula salva — `false`; `$className: "DataModel"` explícito ($mesmo
  conteúdo de arquivo, é literalmente `CaseA/default.project.json` revisitado) → a guarda nova
  dispara **imediatamente** nessa segunda entrada, **antes** de `casea` chegar a expandir `Vendor` de
  novo (que precisaria de mais ~2 saltos para o `cycleGuard` antigo fechar o ciclo do jeito que
  fechava antes desta task).
- Resultado: converge em menos saltos, com `plan/engine-only-class` em vez de
  `plan/nested-project-cycle`, mas **continua** um `error`, **continua** impedindo o hang
  (`elapsedSeconds < 10` confirmado), e a causa raiz (comparação de string sensível a case) é
  exatamente a limitação **já declarada** no cabeçalho do arquivo antes desta task — não uma
  descoberta nova nem uma regressão de comportamento. A explicação do coder é coerente com o código
  real; a mudança está documentada tanto no comentário do spec quanto (segundo o coder) no relatório
  da task.

### 6. `RunCommand.luau` injeta as três funções corretas

```lua
local plan = TreePlanner.Plan(project, {
    IsServiceClass = Services.IsServiceClass,
    IsEngineFixedChild = Services.IsEngineFixedChild,
    IsEngineOnlyClass = Services.IsEngineOnlyClass,
}, bag)
```

Confirmado no arquivo real (`src/cli/RunCommand.luau:144-149`), antes de `Services.Bootstrap`
(passo 7, mais abaixo no mesmo arquivo) — ordem exigida pela Decisão 17 ("PURA... SEGURA de chamar
ANTES de `Services.Bootstrap`").

### 7. `grep` por `NewEngineInstance(` em `src/cli/**`

```
src/cli/TreeMaterializer.spec.luau:116: -- Grep pela SINTAXE DE CHAMADA ("NewEngineInstance(", ...
src/cli/TreeMaterializer.spec.luau:123: assert(string.find(source, "NewEngineInstance(", 1, true) == nil, ...)
```

As duas únicas ocorrências são a **string literal dentro do próprio teste que verifica a ausência**
— nenhuma chamada real. Regra intacta.

### 8. `--!strict` sem `any`

Todos os 5 arquivos tocados (`TreePlanner.luau`, `RunCommand.luau`, `Messages.luau`,
`TreePlanner.spec.luau`, `TreeMaterializer.spec.luau`) começam com `--!strict`. `grep -n '\bany\b'`
só encontra a palavra dentro de comentários (`"não é um any"`, `"sem any"`) — nenhuma anotação de
tipo `any` introduzida. `luau-lsp analyze --platform=standard --settings=".luaurc"` nos 5 arquivos:
**exit 0, zero diagnósticos**.

### 9. `Messages.PlanEngineOnlyClass` e `Services.IsEngineOnlyClass` — não alteradas por engano

- `Services.IsEngineOnlyClass` (de `task-services-014`, já commitada em `0aff50b`): `git diff --
  src/services/init.luau` deu **vazio** — zero alteração nesta task. Fórmula confirmada em disco:
  `entry ~= nil and entry.IsAbstract and (entry.Covered or RUNTIME_OWNED_CLASSES[className] == true)`,
  idêntica à Decisão 17.
- `Messages.PlanEngineOnlyClass` é **nova nesta task** (não "de tarefa anterior" — a Decisão 17
  já previa que ela seria escrita por `task-cli-024`, item (2) da descrição da task). Texto
  conferido byte a byte contra a Decisão 17: frase base idêntica, frase extra de `"DataModel"`
  dentro da mesma função (um só `Code`, nunca um ramo na guarda) — exatamente como especificado em
  "Não criar `Code` separado para `DataModel`".

## Achados

**[BAIXO] Relatório do coder — contagem de suítes imprecisa**
Problema: o coder reportou "100% verde nas 30 suítes de cli/runtime/services", mas o total real de
arquivos `.spec.luau` nesses três territórios é 34 (15 cli + 9 runtime + 10 services).
Cenário: quem confia no número "30" sem recontar pode subestimar a superfície de teste do projeto.
Correção: nenhuma ação de código — só precisão de relatório. Os quatro números específicos que
importam para esta task (`TreePlanner` 38/38, `TreeMaterializer` 18/18, `RunCommand` 11/11,
`services/init` 24/24) estão corretos e foram reproduzidos por mim de forma independente.

**[INFO] Working tree com mudanças não commitadas de outras tasks, fora do escopo desta revisão**
Durante a revisão, `git status` mostrou (além dos arquivos de `task-cli-024`) `src/runtime/
ClassRegistry.luau`, `DataModel.luau`, `Instance.luau`, `init.luau` modificados com conteúdo de
`task-runtime-033`/`task-runtime-034` (BindToClose, JobId/PlaceId/GameId/PlaceVersion) e, mais
tarde, arquivos novos de `src/valuetypes/` — nenhum relacionado a `task-cli-024`, nenhum tocando
`src/cli/`. Confirma o aviso de "confusão de agentes duplicados": há trabalho concorrente de outras
tasks no mesmo working tree, ainda não commitado. Não é um problema desta task (os diffs de
`src/cli/` que revisei são estáveis e isolados — reconferi `git diff --stat` nos 5 arquivos ao final
da revisão e bateu exatamente com o início), mas quem for commitar `task-cli-024` deve usar `git add`
nos arquivos específicos (nunca `git add -A`), para não empacotar por acidente trabalho incompleto
de `runtime`/`valuetypes` no mesmo commit.

Nenhum achado GRAVE ou ALTO. A guarda está na posição certa, as 4 condições batem exatamente com a
Decisão 17, as 5 exigências do acceptance foram reproduzidas com fixtures reais e com um probe
usando `services` de verdade (não só `FAKE_OPTIONS`), a mudança de fase em `TreeMaterializer.spec`
preserva a defesa em profundidade real, o achado do ciclo case-insensitive é coerente com o código e
não é regressão, `RunCommand` injeta certo, `NewEngineInstance` continua nunca chamado por `cli`,
`--!strict` sem `any` confirmado com `luau-lsp analyze` limpo, e nada de `services`/`runtime` foi
alterado por esta task.

## Veredito

APROVADO
