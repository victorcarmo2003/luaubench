# Revisão — task-cli-020 (Decisão 16: restringir `plan/class-name-conflict` à raiz do projeto MAIS EXTERNO)

Data: 2026-09-05. Read-only. Ceticismo extra pedido explicitamente — sou o próprio `revisor-cli`
que achou o furo original em `revisor-cli-rootsource-2026-09-05.md` (seção 7.2); nada do
self-report do coder foi aceito sem reprodução própria (aliás, o board ainda mostra `task-cli-020`
em `in-progress`, sem `result` do coder — a mudança de código, porém, já está completa no working
tree e foi isso que revisei).

## Metodologia

1. Li `.claude/tasks.json` (`task-cli-020` e `task-cli-018` completos), a Decisão 16 inteira
   (`arquiteto-cli-2026-09-05.md:1286-1475`) e meu próprio relatório anterior
   (`revisor-cli-rootsource-2026-09-05.md`, achado MÉDIO seção 7).
2. Li o `git diff` real de `TreePlanner.luau`/`TreePlanner.spec.luau` (não apenas a descrição da
   task) e o fixture novo `nested-project-root-datamodel-conflict/` byte a byte.
3. Rodei `lune run` em **todos os 33 `.spec.luau`** do repositório eu mesmo, um por um, somando os
   números manualmente (não usei o número do coder).
4. Escrevi **5 probes independentes** (fora de `src/cli/`, na raiz do repo e no scratchpad,
   apagados ao final — `git status --short` confirma zero resíduo) reproduzindo cada um dos 8
   pontos pedidos, incluindo um fixture sintético MEU (não o do coder) para o cenário original, um
   cenário de 3 níveis de aninhamento, e uma variação de caminho sujo diferente da que o coder já
   testou.
5. Rodei `luau-lsp analyze` eu mesmo nos dois arquivos tocados.
6. Rodei o pipeline completo (`TreePlanner.Plan` + `TreeMaterializer.Materialize`) contra
   `C:\Users\hakor\Documents\Roblox-Games\AnimeFallen\default.project.json` real, sem modificar
   nada lá.

## 1. Suítes — números exatos (contados por mim)

| Território | Arquivos | Testes |
|---|---|---|
| `src/cli/` | 15 | **195/195** (`TreePlanner.spec.luau` sozinho: 29/29 — 27 antigos + 2 novos) |
| `src/runtime/` | 8 | **166/166** |
| `src/services/` | 10 | **88/88** |
| **Total** | **33** | **449/449** |

Bate exatamente com a alegação do coder (era 447 na revisão anterior, +2 novos em
`TreePlanner.spec.luau`, zero regressão). 100% verde.

## 2. O diff em si — bate com o desenho da Decisão 16, linha por linha

Li o `git diff` completo de `TreePlanner.luau` (só esse arquivo de produção mudou, confirmado por
`git status --short`: `M src/cli/TreePlanner.luau`, `M src/cli/TreePlanner.spec.luau`,
`?? src/cli/fixtures/tree-planner/nested-project-root-datamodel-conflict/` — nada mais, nem
`Messages.luau` como a Decisão 16 exigia):

- `PlanContext` (`:117-125`) ganhou exatamente o campo `OutermostProjectFilePath: string` com o
  comentário prescrito pela Decisão 16 (explica por que mora no `ctx` e não em parâmetro).
- `TreePlanner.Plan` (`:1257-1268`): a linha `normalizePath(project.FilePath)` subiu para antes da
  construção do `ctx`, exatamente como pedido — `normalizePath` é pura, e o único consumidor
  seguinte (`cycleGuard`/`cycleChain`) continua recebendo o mesmo valor (li o restante da função,
  nada mudou ali).
- `resolveCore` (`:965-985`): `local isOutermostRoot = isRoot and normalizePath(currentProjectFilePath) == ctx.OutermostProjectFilePath`
  seguido de `local rootDataModelSourceException = isOutermostRoot and explicitClassName == "DataModel"`
  — condição literal da Decisão 16, dentro do bloco `if explicitClassName ~= nil then` (então
  `normalizePath` só roda quando o nó declara `$className` E `isRoot` é `true`, custo desprezível).
- Comentário `:961-972` ajustado (não reescrito) conforme pedido: "Só na raiz do projeto MAIS
  EXTERNO (`isOutermostRoot`)" no lugar de "Só na RAIZ (`isRoot`)", e referência à Decisão 16 no
  lugar de "reportado para revisão do arquiteto".
- **`isRoot` mantém o significado e uso originais em todo o resto do arquivo** — confirmei com
  `grep -n isRoot`: só aparece nas declarações de parâmetro (`:582`/`:628`, assinatura de
  `resolveCore`, **inalterada**, ainda 12 parâmetros posicionais — a variante do parâmetro extra
  que eu tinha sugerido foi corretamente REJEITADA pelo arquiteto, e o código confirma que não foi
  aplicada) e no uso pré-existente em `:686` (`$path` opcional ausente na raiz → erro em vez de
  info) — não tocado, como a Decisão 16 mandava.
- Nenhuma assinatura de `resolveCore`/`planChildrenOf`/`planChildNode`/`planProjectTree` mudou (li
  as quatro declarações antecipadas, `:574-618`, e as definições reais — idênticas ao que já
  existia, só o corpo interno de `resolveCore`/`Plan` mudou).

## 3. Meus 5 probes independentes (todos passaram)

Escrevi `_revisor_probe_outermost.luau` (raiz do repo) requerendo os módulos reais de `src/cli/`
via `require("./src/cli/...")`, e `_revisor_probe_animefallen.luau` para o teste contra o projeto
real — ambos apagados ao final (`git status --short` confirma).

**Probe 1 — reprodução do achado original com fixture PRÓPRIA (não a do coder).** Construí do zero
(em `scratchpad/probe1_original_bug/`) o mesmo cenário sintético que descrevi na revisão anterior:
projeto externo com `Pkg: {"$path": "pkg"}`, e `pkg/default.project.json` com
`{"$className":"DataModel","$path":"algo.lua"}` na própria raiz. Resultado:

```
[error] plan/class-name-conflict NodePath=tree Field=$className
plan == nil? true
plan/root-source-ignored found? false
```

**O furo que eu mesmo reportei está fechado de verdade** — antes da correção (comportamento
documentado na Decisão 16 e na minha revisão anterior) isso passava com **zero diagnóstico** no
`Plan` e só falhava depois no `Materialize` com `materialize/invalid-class` (mensagem enganosa,
"DataModel not simulated yet"). Agora volta a ser `plan/class-name-conflict`, erro correto,
`Plan` devolve `nil`.

**Probe 2 — `root-source-ignored` (raiz de TOPO real do repo, não fixture minha).** Rodei
`ProjectFile.Read` + `TreePlanner.Plan` direto na fixture `src/cli/fixtures/tree-planner/root-source-ignored/`
que já existe no repo (não escrevi nada nela). Resultado: `[warning] plan/root-source-ignored`,
**nenhum** `plan/class-name-conflict`, `Plan` devolve um `InstancePlan` não-nil. Regressão da
Decisão 15 descartada.

**Probe 3 — 3 níveis de aninhamento (A → X → C), cenário que nem o coder nem o fixture novo
testam (o fixture do coder só tem 2 níveis: outer → pkg).** Construí `scratchpad/probe3_threelevel/`:
`A` (outermost, `$className: DataModel` com um filho `PkgX: {"$path":"x"}`) → `X` (projeto aninhado
nível 1, raiz `Folder`, só passa adiante com `PkgC: {"$path":"c"}`) → `C` (projeto aninhado nível
2, raiz `{"$className":"DataModel","$path":"algo.lua"}`, o mesmo padrão problemático). Resultado:

```
[error] plan/class-name-conflict NodePath=tree Field=$className
plan == nil? true
```

Confirma que a exceção **não** vale para nenhuma raiz aninhada, **não importa a profundidade** —
o mecanismo (comparação de string contra `ctx.OutermostProjectFilePath`, sem contador de
profundidade nenhum no código) generaliza corretamente além do caso de profundidade 1 que o
fixture do coder cobre. Combinado com o fixture do coder (profundidade 1) e este probe
(profundidade 2), a leitura do código (a condição não tem nenhuma noção de "nível", só de
"é o mesmo arquivo do topo?") deixa claro que qualquer profundidade se comporta igual.

**Probe 4 — caminho sujo com variação DIFERENTE da do coder.** O coder testou
`\` + inserção de um segmento `.` antes do nome do arquivo. Testei
`.../root-source-ignored/some-other-dir/../default.project.json` — um segmento `..` que precisa
ser **removido do stack** (`table.remove(stack)` em `normalizePath`), caminho de código diferente
do `.` (que é só "não faz nada"). Resultado: `plan ~= nil`, sem erro, `plan/root-source-ignored`
disparando, `plan/class-name-conflict` ausente — a raiz de topo continua reconhecida como
`outermost` mesmo com o `..` colapsado.

**Probe 5 — letra de drive em caixa diferente (Windows).** O código documenta explicitamente
(`normalizePath`, comentário `:213-215`) que **não** faz lowercase de letra de drive —
"case-insensitivity do filesystem do Windows é uma limitação declarada, não coberta aqui". Testei
invertendo a caixa de `project.FilePath` (`D:/...` → `d:/...`) e confirmei que a comparação da
task-cli-020 **continua funcionando** neste caso — não por robustez geral contra case, mas porque
`ctx.OutermostProjectFilePath` e o `currentProjectFilePath` do nó de topo vêm **da mesma string
literal** (`project.FilePath`, sem segunda fonte independente) — é uma auto-comparação, imune a
qualquer forma "suja" que a mesma string tenha. **Isto não é uma robustez nova da task-cli-020**,
é uma consequência estrutural de onde o campo é lido (uma vez só, no topo) — documentado aqui para
que ninguém confunda "passou no teste de case" com "normalizePath ficou case-insensitive". A
limitação em si é pré-existente, já declarada no código, e fora do escopo desta task (a Decisão 16
não promete resolvê-la, e não deveria).

## 4. `isRoot` — todos os outros usos, verificados por leitura + grep

`grep -n isRoot src/cli/TreePlanner.luau` devolve exatamente 5 ocorrências: o comentário novo da
Decisão 16 (`:123`), as duas declarações de parâmetro (`:582` assinatura antecipada, `:628`
definição real — mesma coisa, texto idêntico), o uso pré-existente em `:686` (li o bloco `:664-699`
inteiro: `$path` opcional ausente na raiz vira erro `plan/missing-class-name` em vez do info
`plan/optional-path-omitted` — **não tocado**, comportamento idêntico ao de antes do diff), e a
nova derivação `isOutermostRoot = isRoot and ...` em `:973`. Nenhum outro lugar do arquivo lê ou
decide algo a partir de `isRoot` além desses pontos.

## 5. `--!strict` / sem `any` novo / nada fora de `src/cli/`

`head -1` dos dois arquivos: `--!strict` na primeira linha, confirmado. `grep -n '\bany\b'` em
`TreePlanner.luau` só encontra a palavra dentro de um comentário pré-existente (não relacionado a
este diff, linha 359, já presente antes da task-cli-020) que explica por que aquele tipo NÃO é um
`any` — nenhum `any` real novo. `luau-lsp analyze --platform=standard --settings=".luaurc"` nos
dois arquivos: **exit 0, zero diagnósticos**, rodado por mim. `git status --short` mostra só
`TreePlanner.luau`, `TreePlanner.spec.luau`, o fixture novo, e `.claude/tasks.json` (mudança de
`column` para `in-progress`, bookkeeping do board, não código) — nada fora de `src/cli/`.

## 6. Fixture novo do coder — inspecionado, fiel à descrição da task

`src/cli/fixtures/tree-planner/nested-project-root-datamodel-conflict/`:
- `default.project.json` (outer): `{"$className":"DataModel","Something":{"$path":"pkg"}}`.
- `pkg/default.project.json` (projeto aninhado): `{"$className":"DataModel","$path":"algo.lua"}`.
- `pkg/algo.lua`: comentário explicando o propósito do fixture + `return "should-never-be-loaded"`.

Reproduz exatamente o cenário que descrevi no achado original (projeto externo com nó cujo `$path`
aponta pra pasta com `default.project.json` próprio, projeto aninhado com
`{"$className":"DataModel","$path":"algo.lua"}` na raiz). O teste correspondente em
`TreePlanner.spec.luau` verifica `plan == nil`, `plan/class-name-conflict` com `Severity == "error"`
e `NodePath == "tree"`, e ausência de `plan/root-source-ignored` — todos os três pontos que
reproduzi de forma independente no meu Probe 1 batem.

O segundo teste novo (caminho não-canônico) também foi lido e reproduzido por mim de forma
independente (Probe 4, com uma variação diferente) — o teste do coder está correto: constrói o
`FilePath` sujo (`\` + `.` redundante) via `string.gsub`, monta um `ProjectFile.Project` novo com
os outros campos copiados do original, e confirma `plan/root-source-ignored` sem
`plan/class-name-conflict`.

## 7. Regressão contra pacotes Wally REAIS (`AnimeFallen`) — confirmado, sem regressão

Rodei o pipeline completo (`TreePlanner.Plan` → `Runtime.Scheduler.new()`/`DataModel.new()` →
`Services.Bootstrap` → `TreeMaterializer.Materialize`) contra
`C:\Users\hakor\Documents\Roblox-Games\AnimeFallen\default.project.json` de verdade (nunca
modifiquei nada lá). Os tamanhos de `Source` batem **exatamente** com os que reportei na revisão
anterior de `task-cli-018`:

```
profilestore: Source bytes = 64588
jecs:         Source bytes = 109448
promise:      Source bytes = 60896
fusion:       Source bytes = 2850
sera:         Source bytes = 56
```

As duas únicas falhas de `Materialize` nesta rodada (`materialize/invalid-property` em
`Lighting.Technology`, `materialize/service-not-simulated` em `SoundService`) são as mesmas
pré-existentes, sem relação com esta task, já vistas na revisão anterior. **O fix original da
task-cli-018 (Parte 1) continua de pé — task-cli-020 não regrediu nada aqui.**

## Achados

Nenhum. Não encontrei nenhum problema novo, nenhuma lacuna não documentada, nenhuma divergência
entre o código e a Decisão 16.

## O que verifiquei e não achei problema

- 449/449 specs (33 arquivos), contados por mim, batendo com a alegação do coder.
- O furo MÉDIO que eu mesmo reportei (`revisor-cli-rootsource-2026-09-05.md`, seção 7.2) está
  fechado — reproduzido com fixture própria, não a do coder.
- `root-source-ignored` (raiz de topo real) sem regressão.
- Generalização para profundidade 2 de aninhamento (não só profundidade 1, que é tudo que o
  fixture novo cobre) — testado por mim, confirma que o mecanismo é depth-agnostic por desenho
  (comparação de string, sem contador de nível).
- Robustez contra `..` (variação diferente da do coder) e contra letra de drive em caixa diferente
  (limitação pré-existente e já declarada no código — não piorou nem foi silenciosamente
  "corrigida" por engano; seria motivo de suspeita se tivesse mudado esse comportamento sem dizer).
- `isRoot` mantém o mesmo significado e os mesmos usos em todo o resto do arquivo, incluindo
  `:686` — nenhuma sobrecarga de semântica reintroduzida.
- Assinaturas de `resolveCore`/`planChildrenOf`/`planChildNode`/`planProjectTree` inalteradas —
  a variante do parâmetro extra (que eu tinha sugerido na revisão anterior) foi corretamente
  descartada pelo arquiteto em favor do campo em `PlanContext`, e o código confirma que essa
  decisão foi seguida à risca.
- `--!strict`, zero `any` novo, `luau-lsp analyze` limpo.
- Nada fora de `src/cli/` tocado (além do bookkeeping de `.claude/tasks.json`).
- Fixture novo fiel à descrição da task e ao meu achado original.
- Nenhuma regressão contra os pacotes Wally reais do usuário (`AnimeFallen`) — bytes de `Source`
  idênticos aos da revisão anterior.

## Veredito

**APROVADO**

Fecha `task-cli-020` e, por consequência, `task-cli-018` (que ficava em `review` esperando
exatamente esta correção de escopo). O mecanismo escolhido pelo arquiteto (campo aditivo
`PlanContext.OutermostProjectFilePath`, em vez do parâmetro `isOutermostRoot` que eu tinha
sugerido) foi implementado exatamente como desenhado na Decisão 16, com zero mudança de
assinatura, zero arquivo fora de `src/cli/` tocado, e o furo que eu mesmo encontrei na revisão de
`task-cli-018` está fechado de verdade — reproduzido com um fixture sintético independente do meu,
não só confiando no fixture/teste que o coder escreveu. Testei além do que a task pedia
(profundidade 2 de aninhamento, uma segunda variação de caminho sujo, letra de drive) e não achei
nenhum efeito colateral novo.
