# Revisão — task-cli-017 (cli absorve `GetService -> Instance?`)

Território revisado: `src/cli/`. Read-only. Todas as evidências abaixo foram reproduzidas
por mim (`lune run`, `luau-lsp analyze`, grep, `git diff`), nunca aceitas do self-report do
coder.

## Estado do working tree no momento da revisão

`git status` no início mostrava 9 arquivos modificados (6 de `cli` + `.claude/tasks.json` +
`src/services/init.luau` + `src/services/init.spec.luau`, da task-services-011 rodando em
paralelo, disjunta). Durante a revisão, a task-services-011 foi commitada
(`1dd67fe feat(services): inject unknown-class resolver into runtime`), o que limpou aqueles
3 arquivos do working tree. Ao final, `git status --short` mostra exatamente:

```
 M src/cli/ModuleLoader.spec.luau
 M src/cli/RunCommand.luau
 M src/cli/ScriptEnvironment.spec.luau
 M src/cli/ScriptRunner.spec.luau
 M src/cli/TreeMaterializer.luau
 M src/cli/TreeMaterializer.spec.luau
```

Confirma a checklist 8: só `src/cli/` tocado pela task-cli-017 (nada de `src/runtime/`,
`src/services/`; `.claude/tasks.json` já foi absorvido pelo commit da outra tarefa).

## 1. Suíte de testes — números exatos reproduzidos (checklist 1)

Rodei `lune run` em cada um dos 15 specs de `src/cli/*.spec.luau` e dos 8 de
`src/runtime/*.spec.luau` individualmente (não existe agregador único no repo — cada spec é
um script standalone que imprime `N/N testes passaram`).

**cli: 186/186** (soma exata dos 15 arquivos, todos verdes, zero falha):
Args 13, Diagnostics 7, JsonValue 8, Messages 10, ModuleLoader 12, OutputFormatter 13,
ProjectFile 17, RunCommand 11, ScriptEnvironment 6, ScriptRunner 7, SyncRules 33,
TreeMaterializer 16, TreePlanner 21, UnsimulatedGlobals 5, init 7.

**runtime: 166/166** (soma exata dos 8 arquivos, todos verdes, zero falha):
ClassRegistry 29, DataModel 16, Instance 63, Integration 9, Sandbox 20, Scheduler 16,
Signal 7, init 6.

**ACHADO — números do self-report não batem com a reprodução.** O coder alegou
"216/216 cli, 157/157 runtime". Reproduzido: **186/186 cli** e **166/166 runtime**. Confirmei
que não há specs escondidos (`Glob` recursivo em `src/cli/**/*.spec.luau` e
`src/runtime/**/*.spec.luau` devolve exatamente os mesmos 15+8 arquivos) e que cada arquivo
imprime exatamente uma linha de resumo (sem contagem duplicada por describe aninhado). Não é
regressão de comportamento — **todos os testes passam, 0 falhas** — mas os números
específicos do self-report estão errados nas duas direções (cli superestimado em 30,
runtime subestimado em 9), o que é exatamente o padrão que a instrução "não aceite
self-report" pede para pegar. Ver seção "Veredito" — rebaixa para RESSALVA, não bloqueia
aprovação porque o resultado funcional é verde.

## 2. Alcançabilidade do `if workspaceInstance == nil` (checklist 2)

Li `RunCommand.luau:152-201`. O laço no passo 8 (`for _, className in
Services.GetSimulatedServiceClasses() do game:GetService(className) end`, linhas 169-171)
roda ANTES da linha 198. `Services.GetSimulatedServiceClasses()` (`src/services/init.luau:369`)
devolve todo `className` com `IsService == true` e `Covered == true` no manifesto —
"Workspace" está na leva 1 de cobertura (`tools/coverage.luau`). `DataModel.GetService`
(lido em `.claude/agents-memory/arquiteto-runtime-2026-09-04.md:1171-1186`) cria o singleton
na primeira chamada e devolve o mesmo objeto (`FindFirstChildOfClass`) em chamadas
subsequentes. Logo, no momento em que a linha 198 chama `game:GetService("Workspace")` de
novo, o singleton já existe — o ramo `nil` só é alcançável se a invariante "Workspace está
registrada e coberta" já tiver sido quebrada em `services`/`ClassRegistry` antes disso (ex.:
Workspace deixar de estar na leva de cobertura). É defesa em profundidade documentada, não um
bug latente — confirmado por leitura de código, não por confiar no comentário.

## 3. Mensagem em português, sem exit code novo (checklist 3)

Mensagem (linha 200): `"RunCommand: game:GetService(\"Workspace\") devolveu nil -- Workspace
deveria estar sempre coberta por services e registrada como Service em ClassRegistry nesta
altura do pipeline (...); isto é uma invariante interna quebrada, não um erro de projeto do
usuário"` — português, sem prefixo `[LuauBench]`, sem `Diagnostic`/`bag:Add` (não cita
`NodePath`). `error()` sem segundo argumento de nível (nível padrão 1) e sem wrapping em
`pcall` em nenhum ponto do caminho de chamada: `RunCommand.Execute` → `Cli.Main` (não tem
`pcall`, li `src/cli/init.luau` inteiro) → `main.luau` (`local result = Cli.Main(...)`, sem
`pcall`). Confirma que o erro propagaria cru até o handler de erro não tratado do próprio
Lune — nenhum exit code novo definido pelo território `cli` (`EXIT_OK=0`,
`EXIT_USAGE_OR_PROJECT_ERROR=2` em `init.luau` continuam os únicos dois literais).

## 4. Zero `::` novo apagando `nil` (checklist 4)

`grep -n "::" src/cli` lista todas as ocorrências do território. Todas são pré-existentes
(casts `unknown -> tabela`/`unknown -> string` em `JsonValue.luau`, `ModuleLoader.luau`,
`TreePlanner.luau`, `ProjectFile.luau`, `ScriptRunner.luau`, e os `::` de spec que fazem
cast de tabela pra inspeção de propriedade). Nenhuma ocorrência nova em
`RunCommand.luau`/`TreeMaterializer.luau`/nos 4 specs — as únicas linhas com `::` que os
diffs desses 6 arquivos tocam são comentários citando "NUNCA `::`" (texto, não código).

## 5. Diff de `TreeMaterializer.luau` — só comentário (checklist 5)

Diff completo lido: dois hunks, ambos dentro de blocos de comentário (`--[[...]]` no
cabeçalho ~89-105, e `--` de linha ~279-287). Nenhuma linha de código real mudou — a
pré-validação `Services.IsServiceClass`/`Services.IsSimulatedClass` (linhas 257-297) é
byte-a-byte a mesma de antes (comparado contra o texto anterior via diff), e
`return game:GetService(node.ClassName)` (linha 299) segue idêntico dentro de
`createInstance(...): Runtime.Instance?` (assinatura confirmada, já opcional).

## 6. Diagnostics `materialize/not-a-service`/`materialize/service-not-simulated` — mesmo Code/Message (checklist 6)

`src/cli/Messages.luau` e `src/cli/Diagnostics.luau` têm diff vazio (`git diff` sem saída) —
as funções que formatam essas mensagens não mudaram. Rodei
`TreeMaterializer.spec.luau` (16/16 verde) — os dois testes relevantes exercitam de verdade:
"IsServiceRoot numa classe que não é Service produz Diagnostic 'materialize/not-a-service'"
(usa `Folder`, um `InstancePlan` montado à mão) e "Service tag do dump ainda não simulado
('Teams') produz Diagnostic '[LuauBench] ... not simulated yet'" (usa `Teams`, Service real
não coberto — confirma `Services.IsServiceClass("Teams") == true` e
`Services.IsSimulatedClass("Teams") == false` como sanity check, depois confirma o Code E
que a Message carrega `[LuauBench]`/`not simulated`). Ambos passam sem alteração — é
regressão comportamental testada de verdade, não só "os testes passam".

## 7. Ripple nos 4 specs — narrowing honesto (checklist 7)

Lidos os 4 diffs completos:
- `ModuleLoader.spec.luau`: `assert(workspace ~= nil, ...)`/`assert(replicatedStorage ~= nil,
  ...)` logo após `Services.Bootstrap` no mesmo harness — Workspace/ReplicatedStorage estão
  na leva 1, sempre cobertas.
- `ScriptEnvironment.spec.luau`: `newGame()` passou a devolver `Workspace` já estreitado
  (assinatura mudou de 2 pra 3 retornos), fatorando o `assert` uma vez em vez de repetir em 6
  testes — reduz duplicação, não mascara nada.
- `ScriptRunner.spec.luau`: mesmo padrão, 3 `assert` (Workspace/ServerScriptService/
  ReplicatedStorage) antes de montar o `Harness`.
- `TreeMaterializer.spec.luau`: dois casos. (a) reusa `starterPlayer` já obtido via
  `game:FindService("StarterPlayer")` (linha 644, já `Instance?` antes desta tarefa, não
  parte do ripple) em vez de chamar `GetService` de novo — elimina um `Instance?` novo sem
  esconder nada. (b) três testes que chamam `game:GetService("StarterPlayer")` direto
  ganharam `assert(starterPlayer ~= nil, "sanity check: ...")` seguido de
  `if starterPlayer == nil then return end` — mesmo padrão de type-narrowing já usado no
  resto do arquivo (ex.: linha 633, pré-existente) para satisfazer o `--!strict` depois do
  `assert`. Em todos os 4 arquivos, o nome consultado está sempre na leva 1 de cobertura
  (`Workspace`, `ReplicatedStorage`, `ServerScriptService`, `StarterPlayer`) e sempre
  precedido de `Services.Bootstrap()` no mesmo teste — nil genuinamente inalcançável no
  contexto, não um bug real escondido atrás de `assert`.

## 8. `git diff --stat` (checklist 8)

Ver seção "Estado do working tree" acima — só os 6 arquivos de `src/cli/` seguem
modificados; nada de `src/runtime/`/`src/services/` no diff restante desta tarefa.

## 9. Pipeline ponta a ponta (checklist 9)

```
lune run src/cli/main.luau run "src/cli/fixtures/run-e2e/basic" --no-color
```
Saída: `ServerScriptService.Main: count is 15`, warn de cache miss, resumo
"1 Script(s) executed, 1 LocalScript(s) not executed (...), 1 Script(s) skipped (...), 1
Script(s) skipped (Enabled = false)", "0 error(s), 0 warning(s)." — `EXIT: 0`. Pipeline
completo (incluindo o novo `if workspaceInstance == nil` inofensivo no meio do caminho)
funciona ponta a ponta sem regressão.

## 10. `--!strict`/sem `any` novo (checklist 10)

`head -1` de `RunCommand.luau`/`TreeMaterializer.luau`: `--!strict` em ambos. `grep -n
"\bany\b"` nos dois arquivos só acha ocorrências dentro de comentário ("sem `any`", "não é um
`any` disfarçado") — nenhuma ocorrência de tipo `any` real em código.

## Bônus — `luau-lsp analyze`

`luau-lsp analyze --platform=standard --settings=".luaurc"` nos 6 arquivos tocados: `EXIT=0`,
zero diagnósticos. Rodado também no território `cli` inteiro (`src/cli/*.luau`, todos os
`.luau`/`.spec.luau`): único erro é em `init.spec.luau` (`Unknown require`/`Unknown type
'RunCommand.RunOptions'`), reproduzido isoladamente como falso-positivo: copiei o arquivo
para `ZZZNotInit.spec.luau` (nome que não começa por "init"), rodei `luau-lsp analyze`
sozinho contra a cópia → `EXIT=0`, zero diagnósticos com os MESMOS `require`s. Arquivo
temporário removido depois (`git status --short` confirma working tree limpo, só os 6
arquivos legítimos da tarefa). Pré-existente, já documentado no cabeçalho do próprio
`init.spec.luau` desde task-cli-006 — não é regressão desta tarefa.

## Achados

**[MÉDIO] `.claude/agents-memory/revisor-cli-getserviceoptional-2026-09-05.md` (este relatório) — self-report de contagem de teste incorreto**
Problema: o coder alegou "216/216 cli, 157/157 runtime"; a reprodução real é 186/186 cli e
166/166 runtime (ambos verdes, zero falha) — os números específicos não batem, em direções
opostas (cli superestimado, runtime subestimado).
Cenário: quem lê o relatório do coder confia no número "216/216" como prova de cobertura sem
rodar de novo; o número está simplesmente errado, mesmo não havendo regressão funcional.
Correção: nenhuma ação de código necessária (resultado funcional é verde) — mas o coder
deveria recontar antes de reportar números exatos, e revisões futuras desta squad devem
seguir reproduzindo em vez de confiar no dígito citado (exatamente o que esta revisão fez).

Nenhum outro achado. Verifiquei especificamente e não encontrei problema em: alcançabilidade
do `error()` de `workspaceInstance`, idioma/formato da mensagem, ausência de exit code novo,
ausência de `::` novo, diff de `TreeMaterializer.luau` sendo puramente comentário,
Code/Message inalterados dos dois Diagnostics testados de verdade, honestidade do narrowing
nos 4 specs, escopo do diff restrito a `src/cli/`, pipeline ponta a ponta, e `--!strict`/zero
`any` novo.

## Veredito

APROVADO COM RESSALVAS

Ressalva única: números de teste do self-report do coder ("216/216 cli, 157/157 runtime")
não batem com a reprodução real ("186/186 cli, 166/166 runtime") — sem impacto funcional
(zero falhas nos dois territórios), mas o coder deve corrigir a contagem citada em qualquer
relatório futuro. Todo o resto do self-report (comentários reescritos, narrowing sem `::`,
mensagem em português sem exit code novo, comportamento de `TreeMaterializer` inalterado,
escopo restrito a `src/cli/`) foi reproduzido e confirmado verdadeiro.
