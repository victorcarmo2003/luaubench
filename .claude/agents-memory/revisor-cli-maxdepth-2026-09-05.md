# Revisão — `task-cli-008` (limite duro de profundidade em `TreePlanner`)

Data: 2026-09-05. Read-only, nenhum arquivo de `src/cli/` foi editado. Self-report do coder **não
foi aceito por afirmação** — todo item abaixo foi reproduzido de verdade (specs rodados por mim,
reprodução independente própria fora de `src/cli/`, sondagem de pilha nativa própria), com
evidência de execução, não só leitura.

Estado do working tree confirmado via `git status --porcelain` antes de começar:
```
M src/cli/Messages.luau
M src/cli/TreePlanner.luau
M src/cli/TreePlanner.spec.luau
?? src/cli/fixtures/tree-planner/nested-project-cycle-case-insensitive/
```
Bate exatamente com o declarado — nenhum arquivo fora do escopo tocado (item 8 fechado).

## 1. Regressão total de `cli` — rodei eu mesmo (`lune 0.10.5`, `~/.rokit/bin/lune`)

Rodei os 15 arquivos `*.spec.luau` de `src/cli/` um a um (`lune run src/cli/<Nome>.spec.luau`):

| Arquivo | Resultado |
|---|---|
| Args | 13/13 |
| Diagnostics | 7/7 |
| JsonValue | 8/8 |
| Messages | 10/10 |
| ModuleLoader | 12/12 |
| OutputFormatter | 13/13 |
| ProjectFile | 17/17 |
| RunCommand | 11/11 |
| ScriptEnvironment | 6/6 |
| ScriptRunner | 7/7 |
| SyncRules | 33/33 |
| TreeMaterializer | 17/17 |
| TreePlanner | **31/31** (era 29 — bate com a alegação do coder) |
| UnsimulatedGlobals | 5/5 |
| init | 7/7 |

Soma: **197/197**, zero falha, confirmada duas vezes por métodos diferentes (soma manual da linha
`N/N testes passaram` de cada spec, e `grep -c "^\[PASS\]"` por arquivo — os dois bateram em 197).

**Achado BAIXO**: o coder relatou "**198/198** specs de cli". A contagem real e reproduzida é
**197/197**. Não é uma falha de teste (zero teste falhou, os 197 são 100% verdes) — é um erro
aritmético no self-report (o incremento de TreePlanner, 29→31, está correto; o total agregado
está errado por 1). Não bloqueia porque não há impacto funcional, mas o board não deveria herdar
o número errado — corrigir para 197/197 ao fechar a task.

## 2. Mecanismo do contador de profundidade — lido e confirmado por execução

Tracei a thread do parâmetro `depth: number` nas 4 assinaturas mutuamente recursivas
(`resolveCore`, `planChildrenOf`, `planChildNode`, `planProjectTree`, `TreePlanner.luau:613-655`):

- `TreePlanner.Plan` chama `planProjectTree(project, cycleGuard, cycleChain, 0, ctx)` — semente
  em `0` (linha 1338).
- `planProjectTree` passa `depth` (sem incrementar) tanto pro `resolveCore` da própria raiz quanto
  pro `planChildrenOf` dos filhos da raiz.
- `planChildrenOf` incrementa **+1** em CADA filho ao chamar `planChildNode(..., depth + 1, ...)`
  (linha 1222) — tanto para filhos descobertos via `fs.readDir` quanto para filhos só declarados
  em `$path`/JSON (o merge de `specs`/`order` trata os dois de forma uniforme, então o limite
  também protege contra uma árvore JSON patologicamente funda sem nenhuma pasta real por trás).
- `planChildNode` repassa o mesmo `depth` recebido pro `resolveCore` e pro `planChildrenOf`
  seguinte (nunca reincrementa duas vezes por nó).
- Ao entrar num projeto aninhado (`$path` resolve a outro `.project.json`), `resolveCore` chama
  `planProjectTree(nestedProject, ..., depth + 1, ctx)` (linha ~931) — um nível extra pela
  transição de projeto, tratado pela MESMA constante, nunca resetado a `0`.
- **Nunca amarrado a `cycleGuard`/`cycleChain`/path** — é um `number` puro passado por parâmetro,
  confirmado por leitura completa do fluxo (sem uso de `#cycleChain` ou string de path em nenhum
  ponto do contador).
- Checagem (`TreePlanner.luau:679-688`) é literalmente a PRIMEIRA linha executável de
  `resolveCore` depois de `local bag`/`local options` — antes de QUALQUER `fs.isFile`/`fs.isDir`/
  `fs.readDir` (confirmado lendo até a primeira chamada de `fs.*`, linha 723). Bate com a alegação
  "checado antes de qualquer I/O".

## 3. Reprodução independente (própria, fora de `src/cli/`, removida por completo depois)

Não confiei só no spec do coder. Escrevi um driver próprio (`_scratch_revisor_maxdepth/driver.luau`,
fixture com nomes/estrutura diferentes: `IndependentMaxDepthProbe`, pastas `g0`..`g9` em vez de
`lvl`), gerei **500 pastas reais** em `%TEMP%` (300 acima do limite), rodei contra os módulos reais
de `src/cli/` (sem tocar nada dentro do território):

```
Gerando 500 níveis reais de pasta em disco...
Geração concluída.
pcall ok = true
elapsed = 0.128s
Plan retornou nil? true
  [error] plan/max-depth-exceeded: "tree.Payload.g1.g2.g3...g0" exceeded the maximum tree depth
  LuauBench allows (200 levels...) ...
```

Confirmado: erro claro, `pcall` nunca precisou capturar um erro cru (o próprio `Plan` já devolve
`nil` + diagnostic), tempo de execução trivial (0.13s, não hang), `NodePath` no diagnostic reflete
corretamente os 500 segmentos reais da árvore gerada. Diretório de scratch e script apagados ao
final — `git status --porcelain` confirmou zero resíduo.

## 4. Sondagem da pilha nativa do Lune (item 4 — validação independente, não só aceitação por leitura)

Escrevi um segundo script descartável (`stack-probe.luau`, fora do repositório) com 3 funções
mutuamente recursivas de forma equivalente a `resolveCore -> planChildrenOf -> planChildNode ->
resolveCore` (variáveis locais tipadas, tabela por nível, uma closure em `planChildrenOfLike`,
mesmo "formato" da recursão real, embora não seja bytecode idêntico). Testei cetos crescentes com
`pcall`:

```
ceiling=1000:  OK
ceiling=3000:  OK
ceiling=5000:  OK
ceiling=7000:  ESTOUROU perto de depth=6665
ceiling=8000..20000: ESTOUROU perto de depth=6665 (mesmo ponto, consistente)
```

Meu resultado (~6665) é a mesma ordem de grandeza da alegação do coder (~5000) — não idêntico
(minha réplica é mais leve que `resolveCore` real, que tem mais variáveis/branches/chamadas a
`SyncRules`/alocação de `CoreResolution`, então o limite real provavelmente fica um pouco abaixo
do meu número sintético, plausivelmente mais perto do ~5000 alegado). **Aceito a alegação**: a
metodologia é sólida e minha sondagem independente corrobora a ordem de grandeza — de qualquer
forma, mesmo no pior caso (se o real for só ~3000, o piso que já observei sem estourar), `200`
ainda fica **>15x abaixo**. Margem confirmada como real, não só teórica.

`pcall` capturou o "stack overflow" nativo sem derrubar o processo em todos os casos — reforça que
mesmo sem o contador, um `pcall` em volta de `TreePlanner.Plan` seria uma rede de segurança
mínima; o contador é o que dá a mensagem CLARA (regra 04) em vez de um erro genérico de pilha.

## 5. Case-insensitivity — confirmado que fecha pelo mecanismo ANTIGO, não pelo novo

Rodei o spec novo (`TreePlanner.spec.luau`, teste "duas pastas diferindo só em maiúscula/minúscula
...") como parte do 31/31 acima — passou. Fixture lida por completo:

- `CaseA/default.project.json`: `Vendor.$path = "../CaseB"`.
- `CaseB/default.project.json`: `Back.$path = "../casea"` (case errado, mesmo diretório físico).

Resultado observado (via a assertiva do teste, que exige `plan/nested-project-cycle` presente e
`plan/max-depth-exceeded` ausente): bate com o que o revisor anterior já tinha medido manualmente
em `.claude/agents-memory/revisor-cli-cycle-fix-2026-09-05.md` ("termina em 4 saltos... via
`cycleGuard`"). **Isto é uma correção factual da premissa da task, não um desvio**: a
`description`/`acceptance` de `task-cli-008` (linha 1011 de `tasks.json`) supunha que o cenário de
case-insensitivity precisaria do novo limite para não travar; a investigação ORIGINAL que motivou
a task (mesmo arquivo de memória, seção "Julgamento da pendência declarada") já tinha demonstrado
que esse cenário específico converge sozinho via `cycleGuard` em poucos saltos — a recomendação de
limite duro ali era para o vetor NÃO coberto (pasta comum/symlink), não para "consertar" a
case-insensitivity. O coder leu essa nuance corretamente e o teste novo documenta isso
explicitamente (comentário grande, linhas 950-967 de `TreePlanner.spec.luau`) em vez de fingir que
o novo limite cobre algo que não cobre. Correto.

## 6. Toque em `Messages.luau` — avaliado, não é desvio

Li `Messages.luau:1-8` (cabeçalho real, não a citação do coder): confirma literalmente a regra
invocada — *"TODAS as strings voltadas ao usuário do território `cli` vivem neste arquivo -- nenhum
outro módulo de `src/cli/` constrói uma mensagem literal por conta própria (regra 04 + desenho
..., Decisão 13)"*. A justificativa do coder **procede** — não é uma regra inventada
retroativamente para justificar sair do escopo.

Verificação de que é puramente aditivo:
- `git diff -- src/cli/Messages.luau`: as 9 linhas adicionadas são um comentário + uma função nova
  (`PlanMaxDepthExceeded`) inserida entre duas funções existentes; nenhuma linha pré-existente foi
  alterada.
- `Messages.spec.luau` **não está na lista de arquivos modificados** (`git status --porcelain`) —
  os 10/10 testes pré-existentes de `Messages` continuam intocados e passando (confirmado na
  tabela do item 1).
- Não colide com nenhum código/mensagem existente (nome de função novo, código de diagnostic novo
  `plan/max-depth-exceeded`, não reaproveita nenhuma constante).

**Posição sobre o desvio de território**: não trato isto como desvio real. `coder-cli` tem
`src/cli/` inteiro como território (não uma sub-alocação por arquivo) — a granularidade de
"restringir a `TreePlanner.luau` + specs" está na DESCRIÇÃO da task, não numa regra de
orquestração que proíba tocar outro arquivo do próprio território quando a convenção documentada
do módulo exige isso. Há precedente direto e já revisado no mesmo arquivo: a revisão de fechamento
de `task-cli-003` (`revisor-cli-cycle-fix-2026-09-05.md`, itens 8 e "O que verifiquei") aprovou
exatamente o mesmo padrão (`Messages.PlanNestedProjectCycle`/`PlanNestedProjectClassNameIgnored`
adicionadas por uma task focada em `TreePlanner`) pela mesma razão. Não deveria ter sido tarefa
separada nem pedido explícito prévio — exigir isso a cada nova mensagem de erro criaria fricção
sem ganho (o próprio módulo é declarado "folha", sem risco de ciclo, exatamente para permitir esse
tipo de extensão pontual). Nota de processo, não bloqueio: seria bom a `description` de tasks
futuras desse tipo já mencionar explicitamente "e a mensagem nova vai em `Messages.luau`, por
convenção do módulo" para não parecer um desvio a cada revisão.

## 7. `--!strict` / sem `any` novo

`head -1` dos três arquivos confirma `--!strict` em todos. `grep -n '\bany\b'` nos três arquivos
tocados: única ocorrência é um comentário pré-existente em `TreePlanner.luau:389` (fala de
"widening estrutural (não é um `any`...)", nada a ver com este diff — não está nas linhas
adicionadas). Zero `any` novo, tipagem de `depth: number` explícita nas 4 assinaturas.

## 8. Nenhum arquivo fora do declarado

`git status --porcelain` (reproduzido no topo deste relatório) mostra exatamente `Messages.luau`,
`TreePlanner.luau`, `TreePlanner.spec.luau` modificados + a fixture nova untracked. Nada em
`src/runtime/`, `src/services/`, ou resto de `src/cli/`.

## O que não foi possível verificar 100% (limitação aceita, não bloqueio)

- Symlink/junction real: `@lune/fs` 0.10.5 não expõe criação de link simbólico (confirmado por
  leitura da API disponível — não há função de symlink em `@lune/fs`), então o vetor citado como
  motivador do limite (symlink apontando pra ancestral) não foi reproduzido literalmente por mim
  nem pelo coder. Documentado explicitamente como limitação no comentário do módulo — satisfaz a
  regra 00 (divergência declarada, não silenciosa). Aceitável.
- Número exato "~5000" do coder não foi replicado byte a byte (minha sondagem deu ~6665 numa
  réplica mais leve) — mas a ordem de grandeza bate e a margem de segurança (200 vs. milhares) é
  robusta mesmo no cenário mais conservador que consegui medir.

## Veredito

**APROVADO.**

Toda alegação do coder foi reproduzida de forma independente, não só lida: 197/197 specs de `cli`
rodados por mim (não 198 como relatado — achado BAIXO, corrigir o número no board, sem impacto
funcional), contador de profundidade rastreado e confirmado correto nas 4 funções mutuamente
recursivas via leitura de código E reprodução com fixture própria (500 níveis reais, erro claro,
0.13s, sem hang, sem stack overflow cru), sondagem própria da pilha nativa do Lune corrobora a
ordem de grandeza da margem de segurança alegada (200 vs. milhares), case-insensitivity confirmada
como fechada pelo mecanismo pré-existente (`cycleGuard`) e não pelo novo limite — consistente com o
que o revisor anterior já tinha medido, não um desvio da task. O toque em `Messages.luau` é
justificado por uma regra real e pré-existente do próprio módulo, é puramente aditivo (confirmado
por diff e por `Messages.spec.luau` intocado/10-10), e replica um padrão já aprovado nesta mesma
base de código — não deveria ter sido bloqueado por tarefa separada. `--!strict` sem `any` novo
confirmado. Nenhum arquivo fora do declarado.

Nenhum achado GRAVE/ALTO/MÉDIO. Um BAIXO (contagem total do self-report, 198 vs. 197 real — corrigir
o número ao fechar a task, sem re-trabalho de código necessário).
