# Revisão `revisor-cli` — task-cli-002 (JsonValue.luau + ProjectFile.luau)

Data: 2026-09-05. Território: `src/cli/`. Read-only, nenhum arquivo do território foi alterado nesta revisão.

Insumos lidos por completo antes de revisar: `.claude/tasks.json` (task-cli-002, description + acceptance), `.claude/agents-memory/arquiteto-cli-2026-09-05.md` (Decisões 2 e 14, seção "Módulos" para `JsonValue.luau`/`ProjectFile.luau`), `.claude/agents-memory/pesquisa-formato-projeto-rojo-2026-09-05.md` (formato real do Rojo v7.7.0).

## Metodologia

Não confiei no relatório do coder. Rodei os testes eu mesmo (`lune` em `~/.rokit/bin`), escrevi fixtures adversariais próprias fora de `src/cli/` (`.scratch-revisor/`, apagadas ao final) e um script de probe temporário (`_revisor_probe.luau`, `_probe2.luau`, `_probe3.luau`, todos apagados ao final — `git status` confirma zero resíduo) para atacar diretamente os pontos críticos do pedido, além de rodar `luau-lsp analyze`.

## Verificações e resultado

1. **JSONC funciona de verdade.** `JsonValue.spec.luau` testa comentário `//`/`/* */` + vírgula sobrando — passou. Fixture `jsonc-comments/default.project.json` (extensão `.json`, não `.jsonc`) com comentário no meio da linha + vírgula sobrando — `ProjectFile.spec.luau` confirma que decodifica igual. Reproduzi com fixture própria adicional (dupla vírgula fora de posição válida) — corretamente rejeitada como `project/malformed-json` citando "Unexpected token in object on line 3 column 41", sem stack trace.

2. **Campo de topo desconhecido vira erro nomeando a chave.** Confirmado com fixture do coder (`unknownField`) E com fixture própria usando o nome exato `"luaubench": {...}` (o ponto mais crítico, ver #9) — ambos rejeitados com `project/unknown-field`, mensagem citando a chave e listando as 14 chaves válidas.

3. **`tree` ausente vira erro nomeando o campo.** Confirmado (`missing-tree` fixture, `Diagnostic.Field == "tree"`).

4. **JSON malformado sempre vira `Diagnostic` com caminho do arquivo, nunca stack trace cru.** Tentei ativamente quebrar: chave sem aspas (achado, ver abaixo), vírgula dupla, arquivo vazio, JSON válido mas raiz é array, JSON truncado (chave nunca fechada), lixo binário puro (bytes inválidos UTF-8), path inexistente, path apontando para um diretório em vez de arquivo. Todos os oito casos produziram `Diagnostic` limpo (`project/malformed-json`, `project/invalid-root` ou `project/file-not-readable`), nenhum com `stack traceback` ou frame `[C]:` vazando. `pcall` em `JsonValue.Decode`/`ProjectFile.Read` cobre honestamente a fronteira do `serde`/`fs`.

5. **`Locate` acha `default.project.json`** a partir de diretório e de `cwd`, cai para `.jsonc` quando só ela existe — confirmado pelos 4 testes do coder (`ProjectFile.spec.luau`), reproduzidos aqui via `lune run`.

6. **`PathNode` nas duas formas** (string obrigatória e `{optional: "..."}`) parseado corretamente — confirmado no fixture `valid-minimal` (`ReplicatedStorage.$path == "shared"` vira `Kind="required"`; `ServerScriptService.$path == {optional="server"}` vira `Kind="optional"`).

7. **Warnings corretos, e silêncio correto nos campos aceitos.** `globIgnorePaths`/`syncRules`/`emitLegacyScripts:false`/`$id` geram warning cada um (fixture `warnings`, 4/4 confirmados). Testei separadamente (fixture própria) que `$schema`, `servePort`, `serveAddress`, `serveAllowedHosts`, `servePlaceIds`, `blockedPlaceIds`, `placeId`, `gameId`, `syncbackRules` juntos num único projeto produzem **ZERO diagnósticos** — nem erro nem warning. Bate exatamente com a Decisão 14.

8. **`$ignoreUnknownInstances` aceito em silêncio** — confirmado (fixture dedicada, zero diagnósticos).

9. **`deny_unknown_fields` barra `"luaubench": {...}` de verdade** — testado com o nome exato do campo (não só um nome genérico inventado pelo coder). Rejeitado corretamente com `project/unknown-field` citando "luaubench". Este era o ponto mais crítico do desenho (regra 04 corrigida nesta sessão) e está implementado corretamente.

10. **`Messages.luau` não vaza string solta.** Diff (`git diff HEAD -- src/cli/Messages.luau`) confirma que a mudança é estritamente append-only, no fim do arquivo, antes de `return Messages` — nenhuma linha pré-existente tocada. Grep por literais de string em `JsonValue.luau`/`ProjectFile.luau` mostra que toda prosa de usuário passa por `Messages.*`; os literais que sobram são comentários, `Code` estáveis (`project/...`, `json/...`), segmentos de path (`"tree"`, `"name"`) e valores de `Severity` — nunca uma mensagem final construída na mão.

11. **Zero `any` real.** Grep por `\bany\b` em todo `src/cli/` (incluindo specs) só acha ocorrências dentro de blocos de comentário (`--[[ ]]`/`--`) em `JsonValue.luau` e `ProjectFile.luau`, explicando por que `any` foi eliminado. Nenhum `.luau` do território usa `any` como tipo.

12. **Regressão intacta.** Rodei os seis specs de `src/cli/` individualmente: `Args.spec.luau` 13/13, `Diagnostics.spec.luau` 7/7, `Messages.spec.luau` 10/10, `init.spec.luau` 5/5 (total 35, igual a task-cli-001), mais `JsonValue.spec.luau` 8/8 e `ProjectFile.spec.luau` 17/17 (novos, total 60/60). `luau-lsp analyze --platform=standard` limpo em `JsonValue.luau`+`ProjectFile.luau` isolados e em conjunto com o resto do território (os dois `TypeError` que aparecem ao analisar o diretório inteiro são o achado de tooling **pré-existente e já documentado** do `require` estilo-diretório de `init.spec.luau` — alheio a esta tarefa, confirmado lendo o arquivo).

## Achados

**BAIXO — discrepância no relatório do coder, não no código.** O `result` da task-cli-002 no board diz "10 mensagens novas adicionadas em Messages.luau". O diff real (`git diff HEAD -- src/cli/Messages.luau`) mostra **14** funções novas: `MalformedJson`, `JsonTypeMismatch`, `ProjectPathNotFound`, `ProjectFileNotFound`, `ProjectFileNotReadable`, `ProjectInvalidRoot`, `ProjectUnknownField`, `ProjectMissingField`, `ProjectEmitLegacyScriptsFalse`, `ProjectGlobIgnorePathsUnsupported`, `ProjectSyncRulesUnsupported`, `ProjectNodeIdUnsupported`, `ProjectUnknownDollarKey`, `ProjectInvalidPathValue`. Não afeta corretude nem a promessa de append-only (confirmada) — só a contagem no relatório está errada. Não bloqueia.

**BAIXO/informativo — divergência de fidelidade não documentada (achado novo, fora do pedido original).** `serde.decode("jsonc", ...)` do Lune 0.10.5 é **mais permissivo** que o parser JSONC real do Rojo: aceita chave de objeto sem aspas (estilo JSON5, ex. `{ name: "X" }`), algo que a pesquisa confirmada (`pesquisa-formato-projeto-rojo-2026-09-05.md`) só testa para `//`, `/* */` e vírgula sobrando. Consequência prática: um `.project.json` com chave sem aspas seria **rejeitado pelo `rojo serve`/`build` real** mas **aceito silenciosamente pelo LuauBench** — é uma divergência de comportamento com o Roblox/Rojo real que a regra 00 pede para declarar explicitamente, e hoje não está declarada em lugar nenhum (nem no código, nem no desenho do arquiteto). Não é um bug introduzido por `coder-cli` — é uma propriedade do `serde` do Lune que ninguém tinha motivo de checar antes desta revisão adversarial — mas fica registrada para o `arquiteto`/`pesquisador` decidirem se vale a pena um comentário de divergência em `JsonValue.luau` (a bibliotecar list de "jsonc" do Lune claramente implementa um superset ainda maior do que JSONC puro). Não bloqueia esta tarefa.

Nenhum achado ALTO ou GRAVE.

## Veredito

APROVADO
