# Revisão task-cli-029 — CloudStore.luau / CloudStore.spec.luau

**Data:** 2026-09-06 · **Revisor:** revisor-cli · Read-only, nada editado.

Arquivos revisados: `src/cli/CloudStore.luau`, `src/cli/CloudStore.spec.luau` (ambos novos).
Desenho de referência: `.claude/agents-memory/arquiteto-persistencia-cloud-2026-09-06.md` (seções 2, 3, 9, 10).

Todas as verificações abaixo foram **reproduzidas por mim**, não aceitas por self-report do coder. Ambiente: Lune 0.10.5 (confirmado via `lune --version`), Windows.

## Evidência reproduzida

1. **`lune run src/cli/CloudStore.spec.luau`** → `8/8 testes passaram`. Confere com o alegado.
2. **Suíte completa de `src/cli/`** — rodei cada um dos 16 arquivos `*.spec.luau` individualmente (`Args`, `CloudStore`, `Diagnostics`, `JsonValue`, `Messages`, `ModuleLoader`, `OutputFormatter`, `ProjectFile`, `RunCommand`, `ScriptEnvironment`, `ScriptRunner`, `SyncRules`, `TreeMaterializer`, `TreePlanner`, `UnsimulatedGlobals`, `init`). Todos passaram, exit code 0, soma de 232 asserções, zero falha/regressão. **Discrepância factual no self-report:** o coder alegou "17 arquivos"; contei (Glob, inclusive recursivo) **16** arquivos `.spec.luau` em `src/cli/`. Não é um problema de código — é uma imprecisão no relatório do coder.
3. **`Open` nunca toca o disco** — criei um dir temp vazio, chamei `Open`, `onFirstCreate` não disparou, dir continuou vazio. Confirmado.
4. **Primeira `Save`**: cria `.luaubench/`, `.luaubench/cloud/`, `.luaubench/.gitignore` com conteúdo **exato** `"*"` (`string.format("%q", …)` conferido), dispara `onFirstCreate` exatamente 1x. Segunda `Save` na mesma execução não dispara de novo. Um **novo** `Open` sobre o mesmo diretório já existente (simulando 2ª execução de `luaubench run`) também não dispara. Confirmado.
5. **`Load`**: documento nunca salvo → `nil`, sem criar nada em disco. Substituí o arquivo esperado por um **diretório** com o mesmo nome → `Load` **ERRA** (não `nil`, não crash genérico), mensagem de uma linha (`string.find(msg, "\n") == nil`), citando o nome do documento. Confirmado.
6. **Escrita atômica**: 20 `Save`s sucessivos não deixam `.tmp` órfão, conteúdo final sempre íntegro. Fui além do pedido: **forcei uma falha real no meio de um `Save`** substituindo o arquivo final por um diretório antes de uma nova gravação — `fs.move` falhou de fato ("Access is denied", depois "Cannot create a file when that file already exists" em outra variação), o erro propagou limpo (uma linha, sem stack trace), e o `.tmp` foi removido pelo cleanup best-effort. Confirmado, com evidência mais forte que o teste do próprio coder.
7. **`document` malicioso**: `"../evil"`, `"../../evil"`, `"sub/evil"`, `"sub\\evil"`, `".."`, `"."`, `""`, mais adicionei `"back\\slash"`, `"a.b"`, `"a/b/c"` — todos recusados, tanto em `Save` quanto em `Load`, **sem tocar disco** (raiz do projeto ficou vazia, nenhum `.luaubench/`, nenhum `evil`/`sub` fora de `cloud/`). Confirmado.
8. **Caminho ancorado em `projectRoot`**: rodei o binário `lune.exe` diretamente (fora do shim do Rokit) a partir de `C:\Users\hakor` — um cwd genuinamente diferente do repositório e até de outro drive — e confirmei que o documento apareceu em `projectRoot` (`C:/.../case7-project/.luaubench/cloud/datastore.json`), nunca relativo ao cwd do processo. Mais forte que o teste do coder, que sempre roda a partir da raiz do repo.
9. **`--!strict` em ambos os arquivos**; único hit de `\ban\y\b`(any) no arquivo é dentro de um comentário explicando que evitaram `any` — zero uso real. Rodei `luau-lsp analyze` nos dois arquivos com o `.luaurc` do projeto (alias `lune` resolvido): **zero erros/avisos de tipo**. Confirmado.
10. **Território limpo**: `git status` mostra só `CloudStore.luau` e `CloudStore.spec.luau` como novos para esta feature; os demais arquivos modificados (`Args.luau`, `Messages.luau`, `RunCommand.luau`, `init.luau`, `src/services/**`) pertencem à tarefa concorrente `task-cli-026` e a agentes de `services`, sem overlap com os 2 arquivos revisados. Confirmado.
11. **Único `require("@lune/fs")` de produção introduzido pela feature**: grep em `src/cli/**` mostra `require("@lune/fs")` também em `ProjectFile.luau` e `TreePlanner.luau` — mas ambos **não aparecem no `git status`** (arquivos limpos, não tocados por esta tarefa), confirmando que já existiam de tarefas anteriores. A alegação do coder ("único introduzido pela feature", não "único do projeto inteiro") é precisa. Confirmado.

## Achado novo (não alegado pelo coder)

**[MÉDIO] `src/cli/CloudStore.luau:154`**
Problema: `hasEnsuredDirectory = true` é setado **antes** do `pcall(fs.writeDir(cloudDir))` (linhas 166-171) resolver, então uma falha real na criação do diretório trava a flag em `true` permanentemente para o resto do processo.
Cenário: primeira `Save` falha ao criar `.luaubench/cloud/` (ex.: obstrução transitória — outro processo com lock, permissão, antivírus). O erro é propagado corretamente (não é ignorado). Mas se a obstrução for removida e uma `Save` posterior (próximo tique do scheduler, no fluxo real de `task-cli-030`) for tentada, `ensureDirectoryExists` retorna imediatamente sem tentar `fs.writeDir` de novo — a tentativa seguinte falha de um jeito diferente e menos claro (erro apontando pro `.tmp` de escrita, "path specified not found", em vez de "could not create directory"), porque o diretório de fato nunca foi criado.
Reproduzido por mim: bloqueei `.luaubench` com um arquivo no lugar do diretório, chamei `Save` (falhou como esperado), removi o arquivo bloqueador, chamei `Save` de novo no MESMO `Store` — continuou falhando, agora com mensagem diferente, confirmando que a criação do diretório nunca foi retentada.
Correção: só marcar `hasEnsuredDirectory = true` depois de confirmar `writeDirOk == true` (mover a atribuição pra depois do `if not writeDirOk then error(...) end`, ou só setar dentro do branch de sucesso).
Não é GRAVE: nunca falha em silêncio, nunca corrompe dado, sempre erra. É um gap de robustez — uma falha transitória vira permanente pelo resto da execução do `luaubench run`, sem chance de auto-recuperação, o que importa numa ferramenta cujo modelo de persistência depende de flush repetido a cada tique ao longo de uma sessão longa.

## Veredito

```
APROVADO COM RESSALVAS
```

Todas as 10 verificações pedidas passaram com evidência própria, incluindo os dois testes que fui além do escrito no board (falha real de `move`, cwd genuinamente diferente via binário direto). A ressalva é o achado MÉDIO acima (flag `hasEnsuredDirectory` sticky-após-falha) — não bloqueia merge, mas deveria virar um fix pequeno e óbvio antes ou logo depois de `task-cli-030` fiar o flush por tique, já que é exatamente esse fluxo repetido que vai expor o problema na prática. Também vale registrar a imprecisão do self-report (16, não 17, arquivos de spec em `src/cli/` — não afeta o resultado, mas para não repassar o número errado adiante).
