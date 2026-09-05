# Revisão de FECHAMENTO — `TreePlanner.luau` + `TreePlanner.spec.luau` + `Messages.luau` (task-cli-003)

Data: 2026-09-05. Segunda rodada, após reprovação em `revisor-cli-treeplanner-2026-09-05.md`
(GRAVE: ciclo de projeto aninhado via `..` nunca detectado, path cresce sem limite; MÉDIO:
`$className` descartado em silêncio quando `$path` resolve pra projeto aninhado). Read-only,
nenhum arquivo do território foi editado.

Lidos por completo: `TreePlanner.luau` inteiro (1192 linhas), `TreePlanner.spec.luau` inteiro (541
linhas), `Messages.luau` inteiro, `SyncRules.luau` inteiro, `git diff` de `Messages.luau`, todas as
fixtures novas de ciclo/className-ignored do coder.

## Verificação independente (rodada por mim, com fixtures PRÓPRIAS, não as do coder)

Escrevi um driver + fixtures fora de `src/cli/` (`_scratch_review_cycle_fix/`, removido por
completo ao final — `git status` confirma zero resíduo) e rodei tudo de verdade via `lune run`
(binário `lune 0.10.5` de `~/.rokit/bin`), com `timeout` do SO como proteção extra nos casos onde
eu não tinha certeza a priori se terminava:

1. **Ciclo real de 2 projetos, topologia própria** (`moduleA` --`$path:"..\\moduleB"` (barra
   invertida deliberada)--> `moduleB` --`$path:"../moduleA"`--> `moduleA`, nomes de nó
   `Imported`/`ReturnLink`, nada reaproveitado do coder): diagnóstico dispara IMEDIATAMENTE,
   mensagem com 202 caracteres, cadeia `moduleA -> moduleB -> moduleA`, zero `..` na mensagem.
   **OK — bate exatamente com o que a tarefa pediu.**
2. **Ciclo de 4 projetos** (`n1->n2->n3->n4->n1`, todos via `$path:"../nN"`): diagnóstico dispara,
   cadeia cita os 5 arquivos na ordem certa (confirmado por posição de substring), zero `..` na
   mensagem. Prova que a correção generaliza para profundidade diferente de 2 e 3 (a fixture do
   coder só cobre 2 e 3). **OK.**
3. **Auto-referência REAL** (não a degenerada `$path:""` da fixture antiga): raiz de um projeto tem
   um nó `Loop: {"$path": "../proj"}` apontando pra sua PRÓPRIA pasta via `..` genuíno — exercita o
   seeding de `cycleGuard` com `normalizePath(project.FilePath)` (`TreePlanner.luau:1154`), não só
   o caso de dois projetos distintos. Dispara imediato, cadeia `proj -> proj`. **OK — este caminho
   de código (seed do próprio root) não estava coberto por nenhum teste do coder nem pela minha
   lista original de cenários; testei por iniciativa própria.**
4. **`normalizePath`, quatro casos de borda**, observados indiretamente via o candidate path
   ecoado nas mensagens de `plan/required-path-not-found` (todos os 4 `$path` do fixture apontam
   pra algo inexistente de propósito):
   - `"sub/./missingA"` → mensagem cita `sub/missingA`, sem `/./`. **OK.**
   - `"sub/x/../missingB"` → mensagem cita `sub/missingB`, sem `x`, sem `..`. **OK.**
   - `"../../../../../../../../../../missingC"` (10 níveis, mais do que a profundidade real do
     path de teste) → clampa em `D:/missingC`, path válido, sem `..`, sem crash. **OK — a alegação
     "não quebra nem produz caminho inválido" do coder está confirmada, não só lida no código.**
   - `"sub\\y\\..\\missingD"` (barra invertida) → mensagem cita `sub/missingD`, sem `\`, sem `y`.
     Comparado lado a lado com o caso `/./`: os dois convergem pra `sub/` na mesma forma. **OK.**
5. **`$className` + `$path` de projeto aninhado, fixture própria** (`Outer/Widget`
   `$className:"Part"` + `$path:"inner"`, `inner/default.project.json` com raiz `$className:
   "Model"` — nomes e classes diferentes da fixture do coder, que usa `Something`/`Model`/`pkg`/
   `Folder`): `ClassName` final vem do projeto aninhado (`Model`), diagnóstico
   `plan/nested-project-class-name-ignored` presente, `Severity="warning"`,
   `NodePath="tree.Widget"`, `Field="$className"`, mensagem cita o valor descartado (`Part`). **OK
   — replica o comportamento com fixture independente.**
6. **Regressão completa**: rodei os 8 specs de `src/cli/` um a um —
   `Args 13/13 + Diagnostics 7/7 + JsonValue 8/8 + Messages 10/10 + ProjectFile 17/17 + SyncRules
   28/28 + TreePlanner 17/17 + init 5/5 = 105/105`, bate com o relatado.
7. `git status --short` mostra `Args.spec.luau`, `Diagnostics.spec.luau`, `JsonValue.spec.luau`,
   `Messages.spec.luau`, `ProjectFile.spec.luau`, `init.spec.luau` **ausentes da lista de
   modificados** — prova definitiva (não inferência) de que os 60 testes pré-existentes desses
   módulos não foram tocados nesta rodada. `SyncRules.luau`/`SyncRules.spec.luau` continuam
   untracked desde a rodada anterior, conteúdo idêntico ao já revisado (mesmas 5 formas de
   `ClassifyFile`/7 de `ClassifyDir`, mesma ordem, mesma extensão `"Ignored"`).
8. `git diff -- src/cli/Messages.luau`: **puramente aditivo** — todo o diff é linhas `+` a partir
   da penúltima linha do arquivo (`return Messages` continua sendo a última linha, nada acima dela
   foi alterado). `Messages.spec.luau` roda 10/10 sem alteração. **Confirmado, não só lido.**
9. `grep -n '\bany\b'` em `TreePlanner.luau`/`TreePlanner.spec.luau`/`Messages.luau`: única
   ocorrência é dentro de um comentário (linha 312 do `.luau`, mesmo achado de tooling já
   documentado). `luau-lsp analyze --platform=standard` nos dois arquivos isolados: **exit 0,
   zero diagnóstico**. Rodando o território `cli` inteiro junto: único erro é o gotcha de
   `require` de `init.spec.luau` já registrado na revisão anterior — sem relação com esta correção.

## Julgamento da pendência declarada (item 7 da tarefa)

Testei a pendência mais preocupante das três declaradas (case-insensitivity do Windows) na prática,
em vez de só aceitar a declaração: montei `CaseA`/`CaseB` onde `CaseA` referencia `CaseB` com case
CORRETO e `CaseB` referencia de volta `"../CASEA"` (case ERRADO, mesmo diretório físico no NTFS).
Resultado real (com `timeout` de proteção, caso não terminasse): **termina em 4 saltos**, não
trava, não estoura pilha, não cresce sem limite — a cadeia reportada
(`CaseA -> CaseB -> CASEA -> CaseB`) é um pouco confusa (não deixa óbvio que `CASEA` É `CaseA`),
mas o comando falha com erro claro, não trava o processo. A razão estrutural: `normalizePath` não
faz lowercase, mas cada segmento errado só "contamina" a comparação enquanto está no topo da pilha
de componentes — o próximo `..` que passa por cima dele o descarta, e como o outro lado do ciclo
(`CaseB`) está sempre grafado com o case correto (mesmo conteúdo de arquivo relido), a comparação
de string eventualmente bate. Isso é bem mais fraco que o achado GRAVE original (que disparava em
QUALQUER `..` comum, sem precisar de nenhum typo de case do usuário).

**Veredito sobre a pendência: aceitável adiar, não bloqueia.** Razões:
- O GRAVE original era sobre o padrão `..` NORMAL de referência de pacote — coberto e fechado.
- Case-insensitivity exige um typo deliberado de case do PRÓPRIO usuário num `$path` que já
  funciona sem esse typo — vetor bem mais estreito, e na topologia testada ainda assim termina.
- É documentada explicitamente no cabeçalho do arquivo (regra 00 satisfeita: divergência nunca
  silenciosa) — não é um bug escondido, é uma aproximação declarada com o motivo técnico exato
  (API `fs` do Lune 0.10.5 não expõe realpath/canonicalização).
- Symlink não foi testável na prática nesta rodada (exigiria privilégio elevado no Windows pra
  criar), mas o mesmo argumento de "fs do Lune não expõe realpath" se aplica e está documentado.

Ainda assim, **recomendo abrir uma tarefa futura dedicada** para o limite duro de profundidade
como rede de segurança independente — não porque a topologia testada falhou (não falhou), mas
porque não tenho garantia de que TODA topologia com case-mismatch termina tão rápido (uma cadeia
mais longa com o segmento errado nunca sendo "sobrescrito" por um `..` subsequente é concebível). É
defesa em profundidade, não um requisito para fechar ESTA tarefa.

## O que verifiquei e não achei problema (não repetir)

- `resolveCore`/`planChildrenOf`/`planChildNode`/`planProjectTree`: assinatura tipada completa,
  sem `any`, tipos internos (`CoreResolution`, `ChildSpec`, `TargetClassification`) coerentes com
  o resto do módulo.
- `normalizePath` (linhas 182-215): aceita `/` e `\`, preserva prefixo de drive Windows (`C:/`),
  UNC (`//`), raiz POSIX (`/`), colapsa `.`/`..` por álgebra de string pura (sem tocar
  filesystem), `..` além da raiz é descartado sem quebrar — tudo confirmado por execução, não só
  leitura.
- Ponto de aplicação (linha 612): `normalizePath(joinPath(containerFolderPath, pathNode.Path))` —
  único ponto onde `$path` vira caminho absoluto, então todo caminho derivado (source, filhos de
  pasta, `nestedProjectFilePath`) herda a forma canônica, como o comentário promete.
- Seed do `cycleGuard`/`cycleChain` em `TreePlanner.Plan` (linha 1154) também normalizado — sem
  isso, o teste de auto-referência real (item 3 acima) teria falhado; confirmei que não falha.
- `Messages.PlanNestedProjectClassNameIgnored` — assinatura, mensagem, e uso no chamador
  (`TreePlanner.luau:841-850`) consistentes; é aditiva, não colide com nenhuma mensagem existente.
- `TreePlanner.spec.luau`: os 3 testes novos de ciclo/className-ignored fazem asserções fortes
  (contagem de ocorrências de `default.project.json` na cadeia, ausência de `..` na mensagem,
  ordem A→B→A por posição de substring) — não são testes fracos que só checam "não é nil".

## Veredito

**APROVADO.**

O GRAVE original (ciclo de projeto aninhado via `$path` relativo com `..` nunca detectado, path
crescendo sem limite) está fechado — reproduzi o cenário exato que motivou a reprovação (dois
projetos vendorizados se referenciando via `..`) com fixture própria, mais uma topologia de
profundidade 4 e uma auto-referência real, todas as três detectando o ciclo imediatamente, sem
crescimento de path, com cadeia correta na mensagem. O MÉDIO (`$className` descartado em silêncio)
está fechado — reproduzi com fixture própria, warning novo dispara com Severity/NodePath/Field/
valor descartado corretos. `normalizePath` foi verificada em todos os casos de borda pedidos,
incluindo um que a tarefa não pediu explicitamente (auto-referência via `..` genuíno no seed do
próprio root). `Messages.luau` é comprovadamente só aditivo (`git diff`), `Messages.spec.luau`
10/10. Regressão 105/105, com prova via `git status` (não inferência) de que os 60 testes
pré-existentes fora do escopo não foram tocados. A pendência declarada (limite duro de
profundidade, case-insensitivity, symlinks) foi investigada na prática para o caso mais plausível
(case-insensitivity do Windows) e não bloqueia — é mais estreita que o GRAVE original, está
documentada, e a topologia testada termina sem travar. Recomendo tarefa futura pro limite duro de
profundidade como defesa em profundidade, não como bloqueio.

`task-cli-003` pode ser fechada.
