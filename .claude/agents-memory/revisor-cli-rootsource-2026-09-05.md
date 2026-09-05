# Revisão — task-cli-018 (Source/SourcePath/$properties da raiz de projeto)

Data: 2026-09-05. Read-only. Ceticismo extra pedido explicitamente — nada do self-report do coder foi aceito sem reprodução própria.

## Metodologia

Não confiei no relatório de `coder-cli-task-cli-018-2026-09-05.md`. Reproduzi eu mesmo:

1. Li `.claude/tasks.json` (`task-cli-018`, descrição + acceptance completos) e `arquiteto-cli-2026-09-05.md` "Decisão 15" inteira (linhas 1077-1282).
2. Li o diff real (`git diff`) de `TreePlanner.luau`, `TreeMaterializer.luau`, `Messages.luau`, `TreePlanner.spec.luau`, `TreeMaterializer.spec.luau` — não apenas o relatório do coder.
3. Rodei `lune run` em **todos** os `.spec.luau` do repositório, um por um, e somei os números eu mesmo (não usei o número do coder).
4. Escrevi e rodei **3 probes temporários próprios** (fora de `src/cli/`, na raiz do repo, apagados ao final — `git status --short` confirma zero resíduo) para reproduzir contra o projeto real do usuário e contra dois cenários sintéticos.
5. Rodei `luau-lsp analyze` eu mesmo nos 5 arquivos tocados.

## 1. Suítes — números exatos (contados por mim, não pelo coder)

Contei **33 arquivos `.spec.luau`** no repositório (coder alegou "29 suítes" — número incorreto, ver achado BAIXO abaixo), todos executados individualmente via `lune run <arquivo>`:

| Território | Arquivos | Testes |
|---|---|---|
| `src/cli/` | 15 | **193/193** |
| `src/runtime/` | 8 | **166/166** |
| `src/services/` | 10 | **88/88** |
| **Total** | **33** | **447/447** |

100% verde. Nenhuma regressão. Os 7 testes novos que o coder alega (6 em `TreePlanner.spec.luau`, 1 em `TreeMaterializer.spec.luau`) — confirmei contando os blocos `test(...)` novos no diff: **número correto**.

## 2. Verificação end-to-end contra `AnimeFallen` real (read-only)

Escrevi um probe próprio (`_revisor_probe_rootsource.luau`, raiz do repo, apagado depois) que roda `TreePlanner.Plan` + `TreeMaterializer.Materialize` direto contra `C:\Users\hakor\Documents\Roblox-Games\AnimeFallen\default.project.json` (nunca modifiquei nada nessa pasta).

Achado inicial: minha primeira busca (por `"ProfileStore"`/`"Jecs"` com essa capitalização) não achou nada — os nomes reais materializados são **minúsculos** (`profilestore`, `jecs`, `promise`, `fusion`, `sera`), porque é assim que os arquivos do Wally se chamam neste projeto (`ServerPackages/_Index/ddashdev_profilestore@1.0.4/profilestore.luau` + pasta irmã `profilestore/` com `default.project.json` dentro). Refiz a busca case-insensitive e confirmei, com bytes exatos batendo com o relatório do coder:

```
profilestore materializado: ClassName=ModuleScript, Source bytes=64588
jecs materializado:         ClassName=ModuleScript, Source bytes=109448
promise materializado:      ClassName=ModuleScript, Source bytes=60896
fusion (Packages):          Source bytes=2850
sera (Packages):            Source bytes=56
```

Todos batem exatamente com os números do relatório do coder. As duas únicas falhas de `Materialize` nesta rodada real (`materialize/invalid-property` em `Lighting.Technology`, `materialize/service-not-simulated` em `SoundService`) são as mesmas que o coder relatou, pré-existentes, sem relação com esta task. **Confirmado: o bug ALTO está corrigido de verdade, não só nos testes do coder.**

## 3. As três fixtures de raiz aninhada — verificadas

Inspecionei os `.project.json` das três fixtures novas (`nested-project-root-is-file`, `nested-project-root-is-init-dir`, `nested-project-root-is-plain-folder`) — reproduzem fielmente as três formas reais encontradas nos pacotes Wally do usuário (raiz-é-arquivo como ProfileStore/Jecs; raiz-é-pasta-com-`init.*` como Promise/Sera/Fusion; raiz-é-pasta-sem-`init.*`). Os 27/27 testes de `TreePlanner.spec.luau` (que incluem os 6 novos) passaram na minha execução independente.

## 4. `$properties` da raiz aninhada + precedência — verificado com probe próprio

Rodei fixture `nested-project-root-properties-merge` com um probe meu (sem usar o spec do coder):

```
FromPackage = true   (só na raiz do pacote — sobrevive, correto)
FromOuter   = true   (só no nó externo — aplicado, correto)
Shared      = fromOuter  (chave repetida — EXTERNO vence, comportamento já shipado preservado)
```

Confirmado.

## 5. Warning `plan/root-source-ignored` — verificado com probe próprio

Fixture `root-source-ignored` (`{"$className": "DataModel", "$path": "algo.lua"}`), probe independente:

```
[warning] plan/root-source-ignored: the project root at "tree" resolved to "DataModel",
but its "$path" also produced script source from ".../algo.lua" -- a DataModel has no
"Source" property, so the file's contents were ignored. (Field=$path)
RootClassName = DataModel
```

Sem `plan/class-name-conflict` junto. Confirmado que o warning dispara de verdade — e confirmado que **só dispara por causa da exceção** descrita no achado do coder (ver seção 7).

## 6. Regressão em nós que já tinham `Source`

Nenhuma. `git diff` mostra que o ramo NÃO-aninhado de `resolveCore` (arquivo/pasta comum) não foi tocado — `source`/`sourcePath` continuam vindo exatamente de onde vinham. A suíte completa (447/447) e o probe contra `AnimeFallen` real confirmam.

## 7. A exceção em `plan/class-name-conflict` — ponto mais delicado, avaliado com profundidade

Esta é a parte que pedia ceticismo extra, e onde a reprodução independente **encontrou algo que o coder não tinha visto**.

### 7.1 — A exceção é necessária?

Sim, no sentido em que o coder descreveu: sem alguma mudança na checagem `pathClassName ~= nil and pathClassName ~= "Folder"`, o cenário `{"$className": "DataModel", "$path": "algo.lua"}` cai sempre em `plan/class-name-conflict` antes de chegar no ponto que produziria `Source`, tornando `plan/root-source-ignored` código morto — reproduzi isso revertendo mentalmente a condição contra o comportamento documentado e confirmei com o probe que, COM a exceção, o warning dispara (seção 5). Uma alternativa sem tocar a checagem existente (ex.: computar `Source` num ramo totalmente paralelo, sem passar pela guarda de conflito) exigiria duplicar a resolução de classificação de `$path`, o que é pior. Então: sim, tocar essa checagem era necessário.

### 7.2 — A exceção é estreita o suficiente? **NÃO — achei um furo real.**

A exceção está gated em `isRoot`:

```luau
local rootDataModelSourceException = isRoot and explicitClassName == "DataModel"
```

Mas `isRoot=true` é passado **incondicionalmente toda vez que `planProjectTree` é chamado** (`TreePlanner.luau:1218`) — e `planProjectTree` é chamado tanto para a raiz de TOPO (uma vez, por `TreePlanner.Plan`) quanto **recursivamente para a raiz de CADA projeto aninhado** (dentro do próprio ramo de projeto aninhado de `resolveCore`, linha 873: `planProjectTree(nestedProject, ...)`). Ou seja, `isRoot` significa "raiz de QUALQUER resolução de projeto", não "raiz do `InstancePlan` inteiro" — são dois conceitos diferentes que o código atual não distingue.

A Decisão 15 (Parte 2) discute esse cenário **só para a raiz de TOPO** ("raiz de topo... `{"$className": "DataModel", "$path": "algo.lua"}`... Aí, e só aí, warning"). Ela nunca examina o que acontece se um projeto **aninhado** declarar isso na própria raiz.

**Reproduzi o furo com um fixture sintético meu** (`_revisor_edge_fixture/`, apagado depois): um projeto aninhado cujo `default.project.json` próprio é `{"$className": "DataModel", "$path": "algo.lua"}`, referenciado via `$path` de um `ReplicatedStorage.Pkg` no projeto externo. Resultado real:

```
=== PLAN ===
(zero diagnósticos)
RootClassName: DataModel
ReplicatedStorage :: ReplicatedStorage
  Pkg :: DataModel | Source bytes = 39      <-- PlanNode NÃO-raiz com ClassName "DataModel"!

=== MATERIALIZE ===
[error] materialize/invalid-class: Could not create "tree.ReplicatedStorage.Pkg" as
"DataModel": [LuauBench] DataModel exists in the Roblox API Dump (...) but is not
simulated by LuauBench yet
Pkg: instância NÃO criada (subárvore pulada)
```

Ou seja: a exceção deixa um `PlanNode` **comum** (não a raiz do plano inteiro) nascer com `ClassName = "DataModel"`, **sem nenhum diagnóstico no `Plan`** (o warning `plan/root-source-ignored` só é emitido em `TreePlanner.Plan` para o `rootResolution` do projeto de TOPO — não há checagem equivalente para quando isso acontece dentro do ramo de projeto aninhado de `resolveCore`). O problema só aparece depois, no `Materialize`, como `materialize/invalid-class` — um diagnóstico **genérico e mais confuso** ("DataModel not simulated yet", quando na real o problema é outro: uma raiz de pacote declarando uma classe sem sentido para esse contexto) em vez do `plan/class-name-conflict` original (que ao menos nomeia o conflito real: `$className` vs `$path`).

**Isto não é uma regressão de nenhum projeto real hoje** — confirmei que nenhum pacote Wally do usuário faz isso, e nenhuma fixture existente cobre esse caminho (o próprio coder já tinha verificado isso, corretamente). E **não é uma falha grave**: não há crash, não há corrupção de estado, não há instância fantasma criada (a defesa em profundidade de `TreeMaterializer.createInstance` — `Services.new` rejeitando classe não coberta/abstrata — pega o caso e produz um `Diagnostic`, subárvore pulada, exatamente a disciplina de "nunca crash, nunca silencioso" da regra 00). Mas é um **efeito colateral real, não documentado, fora do que a Decisão 15 examinou**: a guarda `plan/class-name-conflict` — que existe para pegar exatamente esse tipo de conflito de configuração em QUALQUER nó — fica mais fraca para todo `isRoot` de projeto aninhado, não só para a raiz de topo do plano inteiro.

### 7.3 — Devia ter ido para o arquiteto antes?

Na minha avaliação, **sim, esse ponto específico deveria ter uma decisão formal do arquiteto antes de fechar a task** — não é uma consequência mecânica óbvia de leitura cuidadosa da Decisão 15. A Decisão 15 fala explicitamente de "raiz de TOPO" na Parte 2; ela nunca examina o que uma raiz de projeto ANINHADO faz com essa mesma combinação. O coder teve o instinto certo de sinalizar isso para revisão (o comentário no código e o relatório são honestos e fáceis de encontrar), mas a auditoria que o coder fez ("busquei em todas as fixtures... nenhuma existe") só prova ausência de regressão em fixtures EXISTENTES — não prova que o escopo da exceção está correto. Uma auditoria mais profunda (que fiz agora) mostra que o mecanismo escolhido (reutilizar o `isRoot` genérico) é estruturalmente mais largo do que o cenário único que a Decisão 15 descreveu.

**Correção recomendada**, caso o arquiteto decida que o escopo atual é largo demais: passar um parâmetro adicional e distinto (ex.: `isOutermostRoot: boolean`) por `resolveCore`/`planProjectTree`, verdadeiro só na chamada feita por `TreePlanner.Plan` e falso na chamada recursiva dentro do ramo de projeto aninhado (`resolveCore:873`), e trocar a condição da exceção para `isOutermostRoot and explicitClassName == "DataModel"` em vez de `isRoot and ...`. Isso resolveria o cenário documentado sem abrir a guarda para qualquer raiz de projeto aninhado.

Alternativa mais barata, se o arquiteto preferir não mexer na assinatura: aceitar o comportamento atual como está (já não crasha, já produz diagnóstico, é um cenário sem nenhuma instância real conhecida) e documentar explicitamente essa divergência como aceita — mas isso é uma decisão de escopo que caberia ao arquiteto declarar, não ao coder decidir sozinho nem ao revisor aprovar calado.

## 8. `--!strict` / sem `any` novo

Confirmado por mim: os 5 arquivos tocados têm `--!strict` na primeira linha. `grep -n "\bany\b"` nos três arquivos de produção só encontra a palavra dentro de comentários que **explicam por que não é um `any`** (`TreePlanner.luau:354`, `TreeMaterializer.luau:235`) — nenhum tipo `any` real introduzido. `luau-lsp analyze --platform=standard --settings=".luaurc"` nos 5 arquivos: **exit 0, zero diagnósticos**, rodado por mim independentemente.

## Achados

**[MÉDIO] TreePlanner.luau:968 (`resolveCore`)**
Problema: a exceção `isRoot and explicitClassName == "DataModel"` que salva o warning `plan/root-source-ignored` de ser código morto usa o `isRoot` genérico, que é verdadeiro tanto para a raiz de TOPO do `InstancePlan` quanto para a raiz de QUALQUER projeto aninhado (`planProjectTree` é recursivo e sempre passa `isRoot=true`) — mais largo do que o cenário único que a Decisão 15 (Parte 2) descreve e testa.
Cenário: um pacote Wally (ou qualquer projeto aninhado) cujo próprio `default.project.json` declara `{"$className": "DataModel", "$path": "<algo>"}` na raiz → hoje passa pela checagem `plan/class-name-conflict` sem erro nem warning no `Plan` (reproduzido: zero diagnósticos), nasce como `PlanNode.ClassName = "DataModel"` no meio da árvore, e só falha depois, no `Materialize`, com um diagnóstico genérico (`materialize/invalid-class`, "DataModel ... not simulated yet") em vez do diagnóstico correto e mais claro (`plan/class-name-conflict`, que nomearia o conflito real de configuração). Não crasha, não corrompe estado (confirmado: `createInstance` rejeita e pula a subárvore), e não afeta nenhum projeto real conhecido hoje.
Correção: threading de um flag distinto (`isOutermostRoot`, verdadeiro só na chamada de `TreePlanner.Plan`) em vez de reusar `isRoot`, OU decisão explícita do arquiteto aceitando o escopo atual como está. Não bloqueante para o valor central da task (Parte 1, a correção do bug ALTO, está sólida), mas bloqueante para considerar a Parte 2 fechada sem ressalva.

**[BAIXO] Relatório do coder — contagem de suítes**
Problema: coder relatou "29 suítes" — contagem real é **33 arquivos `.spec.luau`** (15 cli + 8 runtime + 10 services), todos verdes.
Cenário: nenhum — é imprecisão de relatório, não de código (mesmo padrão de ressalva não bloqueante já visto em `task-cli-017`).
Correção: nenhuma ação de código; só precisão no próximo relatório.

## O que verifiquei e não achei problema

- Bug ALTO (Parte 1, propagação de `Source`/`SourcePath`/`Properties` da raiz de projeto aninhado): corrigido de verdade, verificado por mim contra `AnimeFallen` real com bytes exatos batendo.
- `RootProperties` (Parte 2): aplicado no `game` na ordem certa (depois de `materialize/root-not-datamodel`, antes dos `Roots`), reusando `applyProperties`/`materialize/invalid-property` — verificado com fixture real e probe próprio.
- `Messages.PlanRootSourceIgnored`: texto correto, cita `DataModel` e o `sourcePath`, nunca traduzido, condiz com a família de mensagens do território.
- Nenhuma regressão em nó que já tinha `Source` (447/447 specs verdes + probe real).
- `--!strict`, zero `any` novo, `luau-lsp analyze` limpo (verificado por mim).
- Nenhum arquivo fora de `src/cli/` tocado (`git status --short` confirma).
- As 6 fixtures novas são fiéis às formas reais encontradas nos pacotes Wally do usuário.
- 7 testes novos, contagem correta.

## Veredito

**APROVADO COM RESSALVAS**

A Parte 1 (o bug ALTO em si — raiz de projeto aninhado perdendo `Source`/`SourcePath`/`Properties`, que quebrava `ProfileStore`/`Jecs`/`Promise`/`Sera`/`Fusion`) está corrigida, testada e verificada por mim de ponta a ponta contra o projeto real do usuário — sem ressalva. Pode ir para produção como está.

A Parte 2 (raiz de topo) tem dois pedaços: `RootProperties` e a mensagem de warning estão corretos e testados — sem ressalva. Mas o mecanismo escolhido para tornar `plan/root-source-ignored` alcançável (a exceção em `plan/class-name-conflict` gated por `isRoot`) é **mais largo do que a Decisão 15 examinou**, e minha reprodução confirma um efeito colateral real (ainda que de baixo risco/hipotético hoje) em raiz de projeto ANINHADO, não só de topo. **Recomendo explicitamente escalar esse ponto específico para o `arquiteto`** antes de marcar `task-cli-018` como `done` — seja para aprovar formalmente o escopo atual, seja para pedir o refinamento com um flag `isOutermostRoot` distinto de `isRoot`. O coder já tinha o instinto certo de pedir essa revisão; a resposta a esse pedido não pode ser "os testes passam", porque passam mesmo com o escopo mais largo do que o pretendido.
