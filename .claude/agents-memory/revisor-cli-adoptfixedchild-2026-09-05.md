# Revisão `task-cli-016` — TreeMaterializer adota filho fixo do motor (StarterPlayerScripts/StarterCharacterScripts)

Data: 2026-09-05. Revisor: `revisor-cli`. Read-only. Nenhum arquivo do território foi editado — o
único artefato criado durante a revisão foi um script de verificação temporário
(`__revisor_verify_task_cli_016.luau`, na raiz do repo, apagado ao final — `git status` confirma
zero resíduo) usado para reproduzir as alegações do coder de forma independente, sem reaproveitar
`TreeMaterializer.spec.luau`.

Protocolo seguido: NÃO aceitei o self-report do coder em nenhum ponto. Todo item do pedido foi
reproduzido por mim, com evidência.

## Insumos lidos por completo

- `.claude/tasks.json`, `task-cli-016` (descrição + acceptance completos) e `task-services-010`
  (dependência já `done`/`APROVADO`).
- `.claude/agents-memory/arquiteto-cli-2026-09-05.md`, seção "Revisão pós-implementação 2026-09-05
  (task-cli-015) — filho fixo do motor: adotar, não criar", inteira (linhas 766–1074).
- `src/cli/TreeMaterializer.luau` (arquivo inteiro, 425 linhas), `src/cli/Messages.luau` (diff),
  `src/cli/TreeMaterializer.spec.luau` (arquivo inteiro, 952 linhas), as duas fixtures novas
  (`fixed-children/`, `fixed-child-name-mismatch/`).
- `tests/scenarios/real-roblox-games-pipeline-smoke.scenario.luau` (arquivo inteiro).

## Item a item

**1. Regressão total — 34 specs, zero falha.**
Rodei os 34 `*.spec.luau` do repo (`find src -name "*.spec.luau"`), um por um, via `lune run`.
Todos saíram com exit 0 e "N/N testes passaram". Confirma a alegação do coder byte a byte —
inclusive o número exato (34), que já reflete `task-services-010` mesclada antes desta task.

**2. Estrutura de três ramos mutuamente exclusivos em `createInstance`.**
Li o arquivo inteiro (não só o diff). Confirmado: é uma cadeia de `if ... then ... return ... end`
sequencial — ramo 1 (`node.IsServiceRoot`), ramo 2
(`Services.IsEngineFixedChild(parent.ClassName, node.Name, node.ClassName)`), ramo 3 (resto,
incondicional no final da função). Cada ramo que entra retorna incondicionalmente — não há "tenta
os três e vê qual pega". A exclusividade mútua entre ramo 1 e ramo 2 é garantida estruturalmente
(`IsServiceRoot` só é `true` quando o pai do nó, na árvore planejada, é o `DataModel` — Decisão 4 do
arquiteto; `EngineFixedChildren` só declara `StarterPlayer` como chave, nunca `DataModel`), então
nenhum nó pode cair nos dois ao mesmo tempo. Verifiquei essa garantia lendo a lógica de
`IsServiceRoot` implícita no comportamento observado (Service só nasce sob `DataModel`) e a tabela
fechada de `EngineFixedChildren` (task-services-010, já aprovada).

**3. `.Parent` não é tocado no ramo de adoção.**
Confirmado por leitura literal (linhas 294–328 de `TreeMaterializer.luau`): o ramo faz
`parent:FindFirstChild(node.Name)`, dois `if` de defesa em profundidade que retornam `nil` cedo, e
`return existing` — nenhuma atribuição a `.Parent` em nenhum caminho do ramo.

**4–9. Bateria de comportamento — reproduzida com script próprio, independente do spec do coder.**
Escrevi `__revisor_verify_task_cli_016.luau` na raiz do repo (chamando `require("./src/runtime")`,
`require("./src/cli/TreeMaterializer")` etc. diretamente — nunca importou o spec do coder) e rodei
com `lune run`. 30 checks, todos `[OK]`, `0 FALHA(S)`, exit 0:

- Item 4 (identidade real): `rawequal(adotado, game:GetService('StarterPlayer'):FindFirstChild('StarterPlayerScripts'))`
  e o mesmo para `StarterCharacterScripts` — `true` nos dois. Confirma adoção, não cópia.
- Item 5 (repro do bug de duplicação): contagem de filhos chamados `StarterPlayerScripts` dentro de
  `StarterPlayer` == exatamente 1, idem para `StarterCharacterScripts`. `2` scripts materializados
  (`Camera`+`Equip`).
- Item 6 (zero evento espúrio): conectei `ChildAdded`/`ChildRemoved` em `StarterPlayer` e
  `AncestryChanged` nos dois filhos fixos **antes** de chamar `Materialize` (usando a mesma fixture,
  com o singleton já existente) — zero evento disparado durante a adoção.
- Item 7 (Name divergente): fixture `fixed-child-name-mismatch` (`MyScripts` com `$className:
  "StarterPlayerScripts"` sob `StarterPlayer`) cai no ramo normal, produz
  `materialize/invalid-class` com a mensagem real "Unable to create an Instance of type
  \"StarterPlayerScripts\"" — **nenhum** diagnóstico de adoção dispara.
- Item 8 (Terrain não regride): reusei a fixture já existente
  `src/cli/fixtures/tree-planner/fixed-children/` (Workspace/Terrain) — `Terrain` continua errando
  `materialize/invalid-class` com `[LuauBench] Terrain ... not simulated by LuauBench yet`, e
  `StarterPlayer` na MESMA fixture é adotado sem erro (os dois ramos coexistem sem interferência).
- Item 9 (defesa em profundidade de verdade): reproduzi manualmente os dois diagnósticos novos
  manipulando o singleton real via API pública (`Destroy()` no filho pré-criado, depois um
  `Services.new("Folder", "StarterPlayerScripts")` como impostor) alimentando um `PlanNode` montado
  à mão — os dois diagnósticos disparam. Confirmei também que a fixture REAL (via
  `TreePlanner.Plan` de verdade) **nunca** alcança esses dois códigos — são mesmo só alcançáveis por
  fora do caminho normal, como alegado.

**10. Binário real contra jogos reais.**
Rodei `lune run src/cli/main.luau run "<path>" --timeout 3` contra os dois projetos reais em
`C:\Users\hakor\Documents\Roblox-Games` (read-only, nada editado):

- `Tiktok`: erros finais são `Lighting.Technology` (propriedade inválida),
  `SoundService` (não simulado), `Workspace.FilteringEnabled` (somente-leitura),
  `Workspace.Baseplate` como `Part` (não simulado). **Zero menção a `StarterPlayerScripts`.**
- `Panic - CHESSS`: erros finais são `HttpService` não registrada (erro de runtime, dentro do
  script real do usuário) e `SoundService` não simulado. **Zero menção a `StarterPlayerScripts`.**

Confirmei também, via `grep` nos dois `default.project.json`, que os dois projetos **de fato**
referenciam `StarterPlayer`/`StarterPlayerScripts` — não é um caso trivial de ausência do nó.

**11. Escopo do diff.**
`git diff --stat`: só 4 arquivos — `.claude/tasks.json` (bookkeeping de coluna `todo`→`in-progress`,
sem mudança de conteúdo de task), `src/cli/Messages.luau`, `src/cli/TreeMaterializer.luau`,
`src/cli/TreeMaterializer.spec.luau`, mais as 2 fixtures novas (untracked). Nenhum diff em
`SyncRules.luau`, `src/runtime/**`, `src/services/**`. `grep -rn "NewEngineInstance(" src/cli/`
devolve só as duas ocorrências dentro do próprio `TreeMaterializer.spec.luau` — uma no comentário
explicando o teste, uma dentro da string do `assert` que verifica a ausência. Zero chamada real.

**12. `--!strict` / zero `any`.**
Os 3 arquivos abrem com `--!strict`. `grep "\bany\b"` só acha uma ocorrência, dentro de um
comentário em `applyProperties` explicando que o cast por `unknown` **não** é um `any` disfarçado.
`luau-lsp analyze --platform=standard --settings=".luaurc"` nos 3 arquivos: `EXIT=0`, zero
diagnósticos (só os avisos de config já esperados: "No definitions file provided by client").

**13. Cenário do `testador` — confirmado, com uma imprecisão no relato.**
Li `tests/scenarios/real-roblox-games-pipeline-smoke.scenario.luau` inteiro. A asserção das linhas
127–130 (`materialize/invalid-class` + `StarterPlayerScripts` no stderr do Tiktok) é exatamente a
que ficaria obsoleta — e rodei o cenário de verdade (`lune run tests/scenarios/....scenario.luau`)
para confirmar, em vez de inferir: **falha de fato**, com a mensagem
`esperava "StarterPlayerScripts" citado agora por "materialize/invalid-class" ...`. Isso é
comportamento CORRETO, não regressão — a asserção testava exatamente o sintoma do bug que esta task
corrige (StarterPlayerScripts errando via `materialize/invalid-class`), e agora não erra mais porque
foi corretamente adotado.

Achado à parte (BAIXO, fora do território `cli`, não bloqueia esta revisão): o relato repassado a
mim ("fica 2/3, só esse teste falha") é impreciso. O `test()` helper deste scenario não usa `pcall`
— um `assert` que falha lança um erro não capturado que **derruba o script inteiro**. Rodei e
confirmei: `EXIT=1`, **zero** `[PASS]` impresso (nem sequer o resumo final aparece) — os testes de
`Panic - CHESSS` e `TheGame` nem chegam a rodar, não é "2 passam, 1 falha". O diagnóstico de fundo
do coder está certo (assert obsoleto, consequência esperada do fix, não é regressão do `cli`), mas a
caracterização numérica está errada. `tests/scenarios/` é território do `testador`, e `coder-cli`
corretamente não tocou nele — mas o scenario fica quebrado (crash duro) até alguém do território
`testador` atualizar a asserção. Recomendo sinalizar ao usuário/orquestrador para disparar
`testador` numa tarefa curta de manutenção.

## Achados

Nenhum achado GRAVE/ALTO/MÉDIO dentro do território `cli` (código revisado). Um achado BAIXO fora
do território, listado acima (item 13) — não bloqueia esta task, é uma tarefa de manutenção para
`testador`.

## Veredito

**APROVADO.**

Todas as 13 verificações pedidas foram reproduzidas independentemente (script próprio para os itens
comportamentais, binário real contra os 2 jogos, `lune run` em todos os 34 specs, `luau-lsp
analyze`, grep de escopo). A decisão de arquitetura (adotar, nunca criar) foi implementada
exatamente como desenhada: três ramos mutuamente exclusivos, zero toque em `.Parent` no ramo de
adoção (zero evento espúrio confirmado por teste próprio), identidade real confirmada por
`rawequal`, defesa em profundidade genuinamente inalcançável pelo caminho normal, zero regressão em
`SyncRules`/`runtime`/`services`, zero chamada a `NewEngineInstance` em `cli`, `--!strict` sem `any`
novo, e o bloqueio real em jogos reais (`StarterPlayerScripts`) confirmado eliminado contra os dois
projetos do usuário.
