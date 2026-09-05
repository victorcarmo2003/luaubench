# Revisão — task-cli-001 (esqueleto do território `cli`)

Data: 2026-09-05. Revisor: `revisor-cli`. Escopo: `src/cli/main.luau`, `init.luau`, `Args.luau`,
`Messages.luau`, `Diagnostics.luau` + os 4 `.spec.luau` correspondentes. Primeira implementação do
território — base sobre a qual `task-cli-002` em diante constrói.

Lido antes de revisar: `.claude/tasks.json` (task-cli-001, description + acceptance completos),
`.claude/agents-memory/arquiteto-cli-2026-09-05.md` inteiro (Decisões 1-14, "Módulos", "Contrato
entre territórios"). Nada adivinhado.

Ambiente: `lune 0.10.5` (`C:\Users\hakor\.rokit\bin\lune`), `luau-lsp 1.69.0`.

## O que foi verificado ativamente (não apenas lido)

1. `lune run src/cli/main.luau --help` → exit 0, texto de ajuda completo (as três flags,
   `--watch`, `--help`, `--version`).
2. `lune run src/cli/main.luau --version` → exit 0, `luaubench 0.1.0` +
   `Roblox API Dump: 0.737.0.7371584 (commit 28360dea...)` — confirmado vindo de
   `Services.GetDumpVersion()`, não de literal fixo (o teste `init.spec.luau` compara contra a
   mesma fonte).
3. `lune run src/cli/main.luau` (sem args, comando "run" implícito) → exit 2, mensagem de
   "pipeline ainda não implementado" — **não finge sucesso**.
4. `lune run src/cli/main.luau run --watch` → exit 2, motivo técnico real (Lune 0.10.5 sem
   watcher, regra 04 proíbe polling) — nunca "flag desconhecida".
5. Rodei os 4 specs eu mesmo, um por um: `Args.spec.luau` 13/13, `Diagnostics.spec.luau` 7/7,
   `Messages.spec.luau` 9/9, `init.spec.luau` 5/5 — total 34/34, batendo com o relatório do coder.
6. `luau-lsp analyze --platform=standard` limpo (exit 0, zero diagnósticos) em `main.luau`,
   `init.luau`, `Args.luau`, `Messages.luau`, `Diagnostics.luau` e nos 4 specs individualmente.
7. Reproduzi o "achado de tooling" documentado no cabeçalho de `init.spec.luau`: copiei o arquivo
   para `ZZZNotInit.spec.luau` (fora do commit) e `luau-lsp analyze` deu limpo — confirma que o
   "Unknown require" é falso-positivo por causa do nome começar com "init", não um erro real.
   Apagado depois do teste.
8. Gotcha de `require` (ponto 7 do pedido): criei `src/_revisor_probe/probe.luau` (fora do
   commit) com `local Cli = require("../cli"); print(Cli.Main({"--version"}).ExitCode)` — rodou e
   imprimiu `0`, confirmando que um consumidor de fora de `src/cli/` usa `require("../cli")`
   corretamente. Testei também o inverso: um arquivo dentro de `src/cli/` fazendo
   `require("./init")` (em vez de `require("./")`) — falha com
   `could not resolve child component "init" (ambiguous)`, confirmando que o aviso no cabeçalho
   ("NUNCA `require('./init')`") é real e não hipotético. Ambos os probes removidos depois do teste.
9. `git status`/`git diff --stat`: os únicos arquivos rastreados modificados são `.claude/tasks.json`
   e `src/runtime/Sandbox.luau`/`Sandbox.spec.luau` — este último é de uma tarefa paralela
   (`task-runtime-025`/`026`, Sandbox.Load + whitelist), não de `coder-cli`. Todo o resto novo é
   `?? src/cli/*` (9 arquivos) + 1 memória de outro agente. `coder-cli` não tocou `runtime`/`services`.
10. Zero ocorrências de `any` nos 9 arquivos; `--!strict` na primeira linha de todos os 9.
11. Grep por string literal fora de `Messages.luau`: nenhuma string com inicial maiúscula (padrão
    de prosa) encontrada em `main.luau`/`init.luau`/`Args.luau`/`Diagnostics.luau`. Todo `print`/
    `stdio.ewrite` nesses arquivos passa por `Messages.*` ou por `command.Message` (que já vem de
    `Messages` via `Args.luau`).

## Achados

**[ALTO] Diagnostics.luau:105-119**
Problema: quatro rótulos de localização ("node", "field", "file", "project") estão em texto
literal dentro de `Diagnostics.luau`, não em `Messages.luau` — violação direta do acceptance do
board ("nenhuma string voltada ao usuário fora de Messages.luau") e do próprio comentário de
cabeçalho do arquivo (linha 14-15: "nenhuma string literal voltada ao usuário aparece neste
arquivo por fora de Messages").

```luau
if diagnostic.NodePath ~= nil then
    table.insert(segments, Messages.LocationSegment("node", diagnostic.NodePath))
end
if diagnostic.Field ~= nil then
    table.insert(segments, Messages.LocationSegment("field", diagnostic.Field))
end
if diagnostic.FilePath ~= nil then
    table.insert(segments, Messages.LocationSegment("file", diagnostic.FilePath))
end
if diagnostic.ProjectPath ~= nil then
    table.insert(segments, Messages.LocationSegment("project", diagnostic.ProjectPath))
end
```

`Messages.LocationSegment(label, value)` monta `` `{label}: {value}` ``, então esses quatro
literais aparecem palavra por palavra na linha final que o usuário lê (confirmado rodando
`Diagnostics.spec.luau`: a linha renderizada contém `node: tree.ReplicatedStorage.Modules`,
`field: $properties.Gravty`, etc.). Não são identificadores estáveis como `Code` (que é
propositalmente não traduzido, para o teste asserir sem casar texto) — são palavras de prosa em
inglês que fazem parte da frase que o usuário vê.

Cenário: o usuário aciona a "Decisão que precisa do usuário" do desenho (trocar o idioma dos
diagnósticos do CLI de inglês para pt-BR) → editar só `Messages.luau`, como a Decisão 13 promete
("reverter é editar um arquivo"), NÃO é suficiente — `node`/`field`/`file`/`project` continuam em
inglês porque vivem em `Diagnostics.luau`. A promessa de reversibilidade a custo de um arquivo,
que é a única mitigação registrada para a "única ambiguidade real de regra" do desenho, fica falsa
na prática.

Correção: mover os quatro rótulos para `Messages.luau` (ex.: `Messages.NodeLabel()`,
`Messages.FieldLabel()`, `Messages.FileLabel()`, `Messages.ProjectLabel()`, ou uma única função
`Messages.LocationLabel(kind: "node"|"field"|"file"|"project"): string`), e `Diagnostics.luau`
passa a chamar `Messages.LocationSegment(Messages.LocationLabel("node"), diagnostic.NodePath)` em
vez do literal cru. Correção pequena e mecânica, não deveria bloquear a leva seguinte, mas precisa
entrar antes ou junto de `task-cli-002` (que vai gerar `Diagnostic`s de verdade em volume).

## Não encontrado / verificado sem achado

- `Args.Parse`: os 13 casos do acceptance (run/version/help explícito e implícito, as 3 flags,
  `--timeout` sem valor, `--timeout` não-numérico, flag desconhecida, `--watch` com motivo técnico)
  — todos passam, testados por mim rodando o spec e por leitura do código de `parseRunArgs`.
- `Diagnostics.Bag`: acumula e conta por severidade corretamente, `All()` devolve cópia defensiva
  (testado com mutação da cópia).
- `Diagnostics.Render`: com/sem cor produz a linha certa (confirmado byte ANSI `\27` presente só
  quando `useColor=true`); os dois "achados de tooling" documentados no arquivo (tabela indexada
  por união de literais confundindo o luau-lsp 1.69.0, e narrowing perdido em segunda chamada de
  `stdio.color` na mesma função) são reais e contornados corretamente — `luau-lsp analyze` limpo
  confirma que os contornos funcionam, e o comentário não afirma nada não verificado.
- Nenhuma string de usuário fora de `Messages.luau` além do achado ALTO acima.
- `run` não finge sucesso: `ExitCode=2` sempre que o pipeline real não existe.
- Gotcha de `require` documentado corretamente e confirmado empiricamente nas duas direções.
- `--!strict`, zero `any`, nos 9 arquivos.
- Regressão: `coder-cli` não tocou nenhum arquivo de `runtime`/`services` (confirmado via
  `git status`/`git diff --stat`; a única mudança em `runtime` no working tree é de uma tarefa
  paralela de `coder-runtime`, não desta tarefa).

Nota de escopo (não é achado): o pedido de revisão menciona "confira que `--no-color`/`NO_COLOR`
realmente desligam a cor". Nesta tarefa (task-cli-001) isso não é uma lacuna — `Diagnostics.Render`
recebe `useColor: boolean` já resolvido, e a decisão de combinar `command.NoColor` + variável de
ambiente `NO_COLOR` em um único `useColor` pertence a um módulo que ainda não existe
(`OutputFormatter.luau`/`RunCommand.luau`, Decisão 13 do desenho, tarefas seguintes). `init.luau`
desta tarefa nunca chama `Diagnostics.Render` (não há pipeline ainda), então não há wiring para
testar. Confirmei que a peça que existe (`Render(diagnostic, useColor)`) funciona nos dois valores
do parâmetro.

## Veredito

APROVADO COM RESSALVAS — um achado ALTO (rótulos de localização fora de `Messages.luau`, violando
um acceptance explícito do board e o próprio comentário de cabeçalho do arquivo). Correção pequena
e isolada; não bloqueia o uso do esqueleto por `task-cli-002`, mas deve ser corrigida antes que o
volume de diagnósticos reais cresça (ou a decisão de idioma do usuário chegar e descobrir que
"editar um arquivo" não bastou).
