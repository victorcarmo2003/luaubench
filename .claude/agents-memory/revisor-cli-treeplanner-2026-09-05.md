# Revisão — `SyncRules.luau` + `TreePlanner.luau` (task-cli-003)

Data: 2026-09-05. Escopo: `src/cli/SyncRules.luau`, `src/cli/TreePlanner.luau`, `src/cli/SyncRules.spec.luau`,
`src/cli/TreePlanner.spec.luau`, `src/cli/fixtures/tree-planner/**`. Read-only, nenhum arquivo do
território foi editado.

Lidos por completo antes da revisão: `.claude/tasks.json` (task-cli-003, descrição inteira),
`.claude/agents-memory/arquiteto-cli-2026-09-05.md` (Decisões 3, 4, 6, 7, 8 e "Módulos"),
`.claude/agents-memory/pesquisa-formato-projeto-rojo-2026-09-05.md` (seções 1-6), e o código-fonte
completo de `SyncRules.luau`, `TreePlanner.luau`, `ProjectFile.luau`, `JsonValue.luau`,
`Diagnostics.luau`, os dois specs, e todas as 12 fixtures de `fixtures/tree-planner/`.

## Verificação independente (rodada por mim, não só lida)

- `lune run` em todos os 8 specs de `src/cli/`: **103/103** confirmado (13 Args + 7 Diagnostics + 8
  JsonValue + 10 Messages + 17 ProjectFile + 5 init = 60 regressão; + 28 SyncRules + 15 TreePlanner
  = 43 novos).
- `grep -n '\bany\b'` em `SyncRules.luau`/`TreePlanner.luau`/specs: zero ocorrências fora de um
  comentário explicativo (TreePlanner.luau:247).
- `luau-lsp analyze --platform=standard` em `SyncRules.luau` e `TreePlanner.luau` (isolados e junto
  com o resto de `src/cli/`): limpo, exit 0. O único erro que aparece ao analisar o território
  inteiro junto é o gotcha de `require` de `init.spec.luau` já documentado em memória anterior — não
  tem relação com esta tarefa.
- Escrevi minhas próprias fixtures e um script driver **fora de `src/cli/`** (`_scratch_review_treeplanner/`,
  removido ao final da revisão — não ficou nenhum artefato no repo) para testar cenários que as
  fixtures do coder não cobrem, todos rodados de verdade via `lune run` com timeout de proteção:
  1. Integração real (não só `SyncRules` isolado) de `Combat.server.lua` → `Script` nunca
     `ModuleScript`, dentro de um `Plan` completo. **OK.**
  2. Integração real de `default.project.json` vencendo `init.luau` na MESMA pasta (pasta com os
     dois presentes: o `init.luau` era um "decoy" que devolvia uma string; confirmei que o `Source`
     resultante é `nil` e que a árvore vem do projeto aninhado, não do `init.luau`). **OK.**
  3. Os dois conflitos de `ClassName` pedidos: (a) `$className` explícito + `$path` resolvendo
     `Folder` + nome batendo com Service → `$className` explícito vence TUDO (nem vira Folder, nem
     vira Service); (b) `$path` resolvendo `Folder` sem `$className`, nome batendo com Service, sob
     a raiz → Service vence o Folder. **Ambos OK**, batem com Decisão 4.
  4. **Ciclo real `A → B → A` com dois arquivos de projeto distintos** (não a auto-referência
     degenerada `$path: ""` que é o único caso coberto pela fixture do coder) — **FALHA, ver GRAVE
     abaixo.**
  5. `$properties` na forma "totalmente qualificada" do Rojo (`{"Type": "Vector3", "Value": [1,2,3]}`,
     um OBJETO, não um array) → warning e pula, propriedade primitiva irmã continua entrando. **OK.**
  6. Arquivo `.rbxm` real (fake, mas com a extensão certa) → warning citando o caminho, nó excluído
     do plano. **OK.**
  7. Um teste adicional que fiz por conta própria ao notar a assimetria do código (não estava na
     lista original): `$className` explícito + `$path` apontando para um projeto aninhado → **FALHA,
     ver MÉDIO abaixo.**

## Achados

```
[GRAVE] src/cli/TreePlanner.luau:141-150, 727-756
Problema: a proteção de ciclo de projeto aninhado usa strings de caminho NÃO normalizadas como
chave do cycleGuard, então qualquer ciclo real que passe por um segmento ".." (o jeito normal de um
$path referenciar "para cima") nunca é detectado.
Cenário: dois projetos Rojo distintos se referenciam via $path relativo (ex.: A/default.project.json
tem um nó "Vendor": {"$path": "../b"}, e B/default.project.json tem "Back": {"$path": "../a"} — um
padrão plausível de pacote vendorizado ou monorepo, não algo exótico). Rodei isso de verdade:
TreePlanner.Plan NÃO devolve o diagnóstico "plan/nested-project-cycle" esperado. Em vez disso, ele
recursa ~5000 vezes (reabrindo e reparseando os DOIS arquivos de projeto a cada volta, refazendo
JSON decode e o walk do filesystem inteiro de cada um), construindo um path cada vez mais comprido
("a/../b/../a/../b/..." repetido) até o path chegar a ~25000 caracteres e o SO finalmente recusar
abrir o arquivo — e o erro final que o usuário vê é um "project/file-not-readable" citando um path
de 25 KB ilegível, não a mensagem de ciclo com a cadeia. Root cause: `joinPath` (linha 141) é
concatenação de string pura, sem colapsar ".."/"." — o path usado como chave do cycleGuard nunca
canonicaliza, então dois caminhos que apontam pro MESMO arquivo em disco (um com ".." resolvido
mentalmente, outro sem) são strings diferentes aos olhos de `cycleGuard[nestedProjectFilePath]`
(linha 728). O único teste do coder para isso (`fixtures/tree-planner/nested-project-cycle`, "Loop":
{"$path": ""}) só passa porque é uma auto-referência degenerada cuja string final calha de bater
com o path original sem envolver nenhum "..": é um teste fraco que não exercita o mecanismo real.
Isso NÃO trava para sempre (o SO eventualmente recusa o path longo) nem estourei pilha do Luau
nesta rodada (Windows, ~5000 níveis) — mas depende inteiramente de um limite acidental do SO/
filesystem, não de nada que o código garanta; um projeto aninhado com mais conteúdo em cada nível
faria CADA uma das ~5000 voltas reandar a árvore inteira de novo (não é O(ciclo), é muito pior), e em
outro SO/filesystem com limite de path diferente (ou nenhum) o comportamento poderia ser um hang de
vários minutos ou efetivamente travar o comando. É exatamente o cenário que a tarefa pediu para
testar ("A referencia B que referencia A de volta — não trava nem estoura pilha") e é a ÚNICA
recursão não-limitada do território, declarada como proteção "obrigatória" no desenho.
Correção: normalizar o path (colapsar segmentos ".."/"." antes de usar como chave — não precisa de
acesso a filesystem, é álgebra de string sobre os componentes) antes de gravar/consultar o
cycleGuard, E adicionar um limite duro de profundidade de recursão como rede de segurança
independente (ex.: erro claro "projeto aninhado excede N níveis" além de N=50) — cobre também o caso
em que a normalização de string não basta (symlink, diferença de maiúscula/minúscula em path
case-insensitive do Windows), já que a API `fs` do Lune 0.10.5 confirmada no desenho não expõe
canonicalização/realpath.
```

```
[MÉDIO] src/cli/TreePlanner.luau:727-786
Problema: um nó com `$className` explícito CUJO `$path` resolve para um projeto aninhado tem o
`$className` do usuário silenciosamente descartado, sem nenhum Diagnostic — inconsistente com o
tratamento irmão (filhos nomeados no mesmo caso, linhas 758-766, que geram
"plan/nested-project-children-ignored").
Cenário: `.project.json` com um nó `"Something": {"$className": "Model", "$path": "pkg"}` onde
`pkg/` contém um `default.project.json` próprio com `"$className": "Folder"`. Rodei de verdade:
`Something.ClassName` sai como `"Folder"` (a raiz do projeto aninhado), o `"Model"` do usuário
desaparece, e `bag:All()` tem ZERO diagnostics — nem erro, nem warning, nem info. Comparando com o
código: o branch de projeto aninhado (linha ~727) é tomado assim que `nestedProjectFilePath ~= nil`,
sem checar `explicitClassName` em nenhum momento; o `return` de CoreResolution na linha 774-785 fixa
`ClassName = nestedRootClassName` incondicionalmente. É o mesmo tipo de "informação do usuário
descartada" que o código já reconhece e avisa para filhos nomeados (linha 758-766) — só não fez o
mesmo para `$className`. Não está nas "APROXIMAÇÕES DECLARADAS" do cabeçalho do arquivo (linhas
31-42), que lista só duas aproximações e não esta.
Correção: quando `explicitClassName ~= nil` E o nó resolve para projeto aninhado, emitir um
Diagnostic de warning nomeando o nó e citando que "$className" foi ignorado em favor da raiz do
projeto aninhado (mesmo padrão de `Messages.PlanNestedProjectChildrenIgnored`) — ou, se a decisão de
produto for permitir a sobrescrita, aplicar `explicitClassName` em vez de `nestedRootClassName`
nesse caso. De qualquer forma, nunca em silêncio.
```

## O que verifiquei e não achei problema (não repetir em cima)

- Ordem de `ClassifyFile` (5 formas) e `ClassifyDir` (7 formas) — testes diretos do coder + minha
  integração real via `TreePlanner.Plan` batem: `.server.lua` nunca cai em `.lua`, `default.project.json`
  vence `init.luau` mesmo quando os dois coexistem na mesma pasta.
- Precedência de `ClassName` (Decisão 4) nos dois sentidos de conflito, testada com fixtures
  próprias, ver acima.
- `$path` obrigatório ausente → erro nomeando nó/campo/caminho (`plan/required-path-not-found`);
  `$path` `{optional}` ausente → `Diagnostic` severidade `"info"`, nunca erro, nó omitido.
- Meta files: `<nome>.meta.json` aplica `properties`; `init.meta.json` aplica `properties`+`className`
  só quando a pasta resolveu para `Folder` puro; tentativa de sobrescrever `className` numa pasta que
  já resolveu via `init.luau` (não é Folder puro) → erro `plan/meta-class-name-conflict` — fixture
  `meta-class-conflict` confirma isso rodando.
- `$properties`: primitivo entra no plano; array E objeto (as duas formas ambíguas do Rojo) viram
  warning e são pulados, nunca gravam a tabela crua, nunca erro duro.
- Arquivo `Unsupported` (testei com `.model.json` do coder e `.rbxm` próprio) sempre vira warning
  citando o caminho real, nunca desaparece calado.
- `TreePlanner.luau` não importa `../runtime` nem `../services` (grep próprio, além do teste do
  coder) e `TreePlanner.spec.luau` roda sozinho via `lune run`, sem `DataModel`/`Bootstrap`/
  `ClassRegistry` em lugar nenhum do processo.
- Regressão: os 60 testes pré-existentes de `task-cli-001`/`002` (`Args`, `Diagnostics`, `JsonValue`,
  `Messages`, `ProjectFile`, `init`) continuam 60/60, arquivos desses módulos intocados.
- `--!strict` no topo dos dois arquivos; zero `any` real (só a palavra dentro de um comentário);
  `luau-lsp analyze` limpo.
- Pendências que o coder já declarou (merge de `$path`-para-projeto-aninhado com filhos nomeados;
  projeto aninhado nunca `IsServiceRoot`) — conferi que são exatamente o que o código faz e que estão
  documentadas no cabeçalho do arquivo; não são achados novos.

## Veredito

**REPROVADO.**

O achado GRAVE é bloqueante: a proteção de ciclo — explicitamente chamada de "obrigatória" e "a
única recursão não-limitada do território" no próprio desenho — não funciona para o caso real que a
tarefa pediu para testar (dois projetos se referenciando via `$path` relativo com `..`), só para a
auto-referência degenerada que a fixture do coder cobre. Em produção isso vira, na melhor hipótese,
um erro final incompreensível citando um path de dezenas de milhares de caracteres depois de milhares
de reparsings desperdiçados, e na pior hipótese (SO/filesystem com limite de path maior ou ausente,
ou projeto aninhado com mais conteúdo por nível) um hang ou estouro de pilha de verdade — exatamente
o que a tarefa pediu para excluir. Precisa de correção (normalizar path antes do cycleGuard + limite
duro de profundidade como rede de segurança) e reteste com um fixture de ciclo A→B→A de dois arquivos
antes de reenviar para revisão. O achado MÉDIO (className descartado em silêncio ao lado de um
`$path` de projeto aninhado) deve ser corrigido na mesma rodada, já que é a mesma classe de bug
(informação do usuário descartada sem diagnostic) e o padrão de correção já existe no próprio arquivo
como referência (linha 758-766).
