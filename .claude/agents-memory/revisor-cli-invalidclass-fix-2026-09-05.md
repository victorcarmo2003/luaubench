# Revisão task-cli-011 — vazamento de path/linha interna em materialize/invalid-class

Data: 2026-09-05. Revisor: revisor-cli. Task movida de `done` para `review` pelo usuário antes desta
revisão (sinal de atenção redobrada, sem self-report aceito às cegas) — tudo abaixo foi reproduzido
por este revisor, não copiado do relato do coder.

## Escopo revisado

Diff não commitado (`git diff`) em:
- `src/cli/TreeMaterializer.luau`
- `src/cli/Messages.luau`
- `src/cli/TreeMaterializer.spec.luau`

## Verificação item a item

### 1. Regressão total — rodada por mim, spec por spec

Rodei `lune run` em TODOS os 30 arquivos `*.spec.luau` sob `src/**` individualmente (não confiei em
número agregado do coder) e somei manualmente:

- CLI: Args 13, Diagnostics 7, JsonValue 8, Messages 10, ModuleLoader 12, OutputFormatter 13,
  ProjectFile 17, RunCommand 11, ScriptEnvironment 6, ScriptRunner 7, SyncRules 28,
  TreeMaterializer 10, TreePlanner 17, UnsimulatedGlobals 5, init 7 → **171/171**
- Runtime: ClassRegistry 29, DataModel 12, Instance 63, Integration 9, Sandbox 20, Scheduler 16,
  Signal 7, init 6 → **162/162**
- Services: ClassBuilder 9, Context 3, Integration 14, RejectingSignal 5, behavior/Index 4,
  behavior/Players 8, behavior/RunService 11, behavior/StarterPlayer 3, init 16 → **73/73**

Total = **406/406**, batendo exatamente com o alegado. Nenhum teste falhou, nenhum pulado.

### 2. `stripEngineErrorLocation` aplicada no ponto certo — confirmado por leitura do arquivo real

`TreeMaterializer.luau:282` (dentro de `createInstance`, ramo `if not ok then` do
`pcall(Services.new(...))`):

```
Message = Messages.MaterializeInvalidClass(node.NodePath, node.ClassName, stripEngineErrorLocation(tostring(resultOrError))),
```

Antes do diff (confirmado via `git diff`) era `tostring(resultOrError)` cru. É exatamente o ponto
que o achado ALTO de `revisor-cli-pathleak-fix-2026-09-05.md` apontou. Aplicação real, não só
alegada.

### 3. Reprodução end-to-end com binário real — fixture descartável, path/linha confirmados ausentes

Criei fixture descartável fora do repo (`/tmp/luaubench-review-fixture-cli011/default.project.json`)
com `"ReplicatedStorage": { "Typo": { "$className": "Frmae" } }`.

- **Pós-fix** (`lune run src/cli/main.luau run <fixture> --no-color`):
  ```
  error: [materialize/invalid-class] Could not create "tree.ReplicatedStorage.Typo" as "Frmae": Unable to create an Instance of type "Frmae" (node: tree.ReplicatedStorage.Typo)
  ```
  Sem caminho absoluto, sem `TreeMaterializer:NNN:`. Exit code 2 (erro de projeto, correto — não é
  0, não é o código de "erro de script").

- **Pré-fix**, via `git stash push -- src/cli/TreeMaterializer.luau src/cli/Messages.luau
  src/cli/TreeMaterializer.spec.luau` (reversão real dos três arquivos do diff, não um mock) + mesmo
  comando:
  ```
  error: [materialize/invalid-class] Could not create "tree.ReplicatedStorage.Typo" as "Frmae": D:\UserData\Documents\GitHub\luaubench\src\cli\TreeMaterializer:252: Unable to create an Instance of type "Frmae" (node: tree.ReplicatedStorage.Typo)
  ```
  Vaza o caminho absoluto de instalação + linha interna, exatamente como descrito no achado
  original.

- `git stash pop` restaurou o diff; reexecutei o mesmo comando pós-pop e confirmei que a mensagem
  limpa voltou (sem regressão da restauração). Fixture apagada (`rm -rf`) depois.

### 4. Comentário do cabeçalho — lido, não só alegado

`TreeMaterializer.luau:51-61` hoje diz explicitamente que o comentário anterior "afirmava que isso
bastava para 'nunca vazar' e estava ERRADO" e explica a causa raiz (`error(msg, 2)` em
`Services.new`, mesmo mecanismo do `__newindex`). Não é mais a alegação incorreta original.
`Messages.luau:331-341` tem o mesmo tipo de correção no comentário local da função. Confirmado por
leitura direta, texto consistente com o `result` da task.

### 5. Caça ativa de um terceiro caso — NADA ENCONTRADO no padrão pedido, dois pontos de dureza estrutural anotados

Levantei TODOS os `pcall` em `src/cli/*.luau` (excluindo specs) via grep e li o contexto de cada um:

| Arquivo:linha | O que envolve | Categoria |
|---|---|---|
| `JsonValue.luau:116` | `serde.decode` | erro nativo do Lune (I/O/parse), não `error(msg,2)` de `runtime`/`services` |
| `ModuleLoader.luau:182` | `candidate:IsA(...)` | só produz boolean `ok`/`isModuleScript`, mensagem nunca repassada ao usuário |
| `ModuleLoader.luau:368` | `Runtime.Sandbox.Load` | erro de COMPILAÇÃO do módulo do usuário — location correta é o chunk do usuário (`moduleFullName`), comportamento correto e intencional |
| `ModuleLoader.luau:397` | execução do corpo do módulo do usuário | mesma categoria — erro do script do usuário, atribuição ao próprio script é o comportamento fiel ao Roblox |
| `ProjectFile.luau:380` | `fs.readFile` | erro de I/O do Lune sobre o PRÓPRIO arquivo do projeto do usuário — path exibido é o do projeto, não instalação do LuauBench |
| `TreePlanner.luau:382,714` | `fs.readFile`/`fs.readDir` | mesma categoria de `ProjectFile.luau:380` |
| `TreeMaterializer.luau:194` (`applyProperties`) | `__newindex` real | JÁ CORRIGIDO (task-cli-010) |
| `TreeMaterializer.luau:268` (`createInstance`) | `Services.new` | JÁ CORRIGIDO (task-cli-011, este diff) |

Nenhum `pcall` fora dos dois já corrigidos embrulha uma chamada de API de `runtime`/`services` que
usa `error(msg, 2)` e repassa a mensagem crua ao usuário. Cobertura completa dos 8 `pcall` reais do
território (mais os dois de spec, fora do escopo).

**Dois pontos correlatos, sem `pcall` nenhum (não é o padrão pedido, mas mesma família de risco —
`error(msg, N)` de `runtime` atribuído ao call site interno do `cli`), analisados por reachability e
NÃO reproduzidos como bug vivo:**

- `TreeMaterializer.luau:289` — `instance.Parent = parent` fora de `pcall`. `setParent`
  (`Instance.luau:176-259`) levanta com `error(msg, 3)` em 3 casos (instância destruída, Parent
  inválido, auto-parenteamento/parenteamento cíclico) — nível 3 aponta para o call site externo ao
  `__newindex`, ou seja, este mesmo módulo. Se disparasse, seria uma quebra TOTAL do comando (nada
  em `RunCommand.luau` embrulha a chamada a `TreeMaterializer.Materialize` em `pcall` — confirmado
  por grep), pior que um vazamento formatado: um `error()` cru subindo até `main.luau`. Analisei os
  quatro guardas de `setParent` contra a forma como `materializeNode`/`createInstance` constroem a
  árvore: `createInstance` SEMPRE cria uma `Instance` NOVA a cada nó (nunca reaproveita), o `parent`
  passado é SEMPRE um ancestral já materializado (nunca `nil`, nunca a própria instância, nunca um
  descendente — a instância nova não tem filhos ainda no momento do `.Parent =`), e `TreePlanner` já
  previne ciclo de projeto aninhado (fixtures `nested-project-cycle`/`nested-project-cycle-triple`
  confirmam isso rio acima). Conclusão: os quatro guardas de `setParent` são estruturalmente
  inalcançáveis a partir de QUALQUER `InstancePlan` que `TreePlanner.Plan` possa produzir, incluindo
  entrada de usuário maliciosa/malformada — só um `InstancePlan` montado à mão que também violasse a
  própria disciplina de construção de `TreeMaterializer` chegaria lá. Não é um bug vivo hoje; é uma
  ausência de `pcall` que a própria filosofia de "defesa em profundidade" do cabeçalho do arquivo
  seria inconsistente em não ter, dado que outros caminhos igualmente "só alcançáveis à mão" JÁ são
  defendidos (`Name ~= ClassName`, etc.). Achado BAIXO, não bloqueante, registrado para o board
  decidir se vale o custo de blindar mesmo assim.
- `ScriptRunner.luau:132-134` — `readable.Enabled == false` fora de `pcall`, mesmo padrão de cast de
  fronteira de `applyProperties`. Só alcançável se uma instância de `ClassName == "Script"` não
  tivesse `Enabled` no `ClassSchema` — que dependeria de um bug em `services` (API Dump real sempre
  declara `Enabled` em `BaseScript`), fora do território deste diff. Não reproduzido, não é um caso
  vivo do padrão pedido.

Nenhum dos dois é o "terceiro caso" que a task pediu para caçar (que é especificamente
"`pcall` que captura e não usa `stripEngineErrorLocation`") — são ausência de `pcall`, categoria
adjacente, e ambos inalcançáveis pela superfície de entrada real (`.project.json` do usuário) hoje.
Reporto por transparência, não como bloqueio.

### 6. `--!strict` / `any` — confirmado

Todos os três arquivos do diff mantêm `--!strict` na primeira linha. `grep -i '\bany\b'` sobre as
linhas ADICIONADAS do diff não retornou nenhuma ocorrência de código com `any` (só prosa em
comentário, nenhuma anotação de tipo `any`).

### 7. `git status` — limpo de resíduos

Fixture de reprodução vivia inteiramente em `/tmp` (fora do repositório) e foi apagada
(`rm -rf`) após uso. `git status --porcelain` antes e depois da minha sessão de reprodução mostra
exatamente os mesmos 4 arquivos modificados que já estavam sob revisão
(`.claude/tasks.json`, `src/cli/Messages.luau`, `src/cli/TreeMaterializer.luau`,
`src/cli/TreeMaterializer.spec.luau`) — nenhum arquivo novo, nenhum resíduo do `git stash`/`pop`.

## Veredito

APROVADO

Todas as alegações do coder foram reproduzidas de forma independente (não aceitas por relato):
número exato de testes (406/406, somado por mim spec a spec), aplicação real do fix no ponto certo,
reprodução do bug ANTES e confirmação da correção DEPOIS via binário real com fixture descartável,
correção real do comentário de cabeçalho, zero `any` novo, `git status` limpo. Caça ativa ao terceiro
caso não encontrou nenhuma ocorrência viva do padrão (`pcall` + `error(msg,2)` de `runtime`/`services`
sem strip) fora dos dois já corrigidos — cobertura completa dos 8 `pcall` reais do território. Dois
pontos correlatos sem `pcall` (`TreeMaterializer.luau:289`, `ScriptRunner.luau:132-134`) foram
analisados e são estruturalmente inalcançáveis hoje; registrados como achado BAIXO não bloqueante
para o board decidir sobre blindagem preventiva, não como reprovação.
