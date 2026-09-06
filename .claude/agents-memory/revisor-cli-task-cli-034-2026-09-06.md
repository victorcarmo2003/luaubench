# Revisão task-cli-034 — RunCommand.spec.luau instável (processo real)

**Data:** 2026-09-06 · `revisor-cli` · Read-only. Todas as evidências abaixo foram reproduzidas
por mim, não aceitas do self-report do `coder-cli` (`.claude/agents-memory/coder-cli-task-cli-034-2026-09-06.md`).

## Território

`git diff HEAD --stat -- src/` mostra só 2 arquivos:
- `src/cli/RunCommand.spec.luau`
- `src/cli/fixtures/run-e2e/http-audit/server/Main.server.lua`

`src/cli/RunCommand.luau` (produção) tem diff vazio contra HEAD — confirmado intocado. Território limpo (item 8: OK).

## Verificações reproduzidas

**1. 15 execuções seriais** — rodei eu mesmo (`lune run src/cli/RunCommand.spec.luau`, 15x seguidas): **15/15 verdes**, `31/31 testes passaram` em cada uma.

**2. Concorrência (crítico)** — rodei 4 instâncias concorrentes de verdade (processos paralelos via `&`/`wait`) em uma leva e mais 6 concorrentes em outra: **10/10 verdes**, `31/31` cada. Nenhuma falha de `os error 10048` nem de scratch colidindo.

**3. `PROCESS_UNIQUE_SUFFIX`/`SCRATCH_ROOT` distintos por processo** — extraí o padrão `luaubench-runcommand-spec-<N>` do log de cada uma das 4 instâncias concorrentes: `527724`, `986674`, `405065`, `592205` — quatro valores diferentes, não hardcoded. Confirma o item 3.

**4. Porta dinâmica com retry** — li `startLocalHttpServer` (`RunCommand.spec.luau:379-393`): `MAX_ATTEMPTS = 25`, candidata `math.random(40000, 59999)` sorteada a cada tentativa, `pcall(net.serve, ...)`, retorna na primeira que bindar, erro só depois de esgotar as 25. Nenhuma porta fixa no caminho executado — a porta 47210 só sobrevive como comentário/referência no fixture estático (`src/cli/fixtures/run-e2e/http-audit/server/Main.server.lua`), que não é mais executado diretamente (confirmado lendo `freshHttpAuditProject`, que gera a cópia mutável com a porta embutida via `HTTP_AUDIT_PROJECT_ROOT = {SCRATCH_ROOT}/http-audit`).

**5. Achado nº2 (`HttpService:GetAsync` esporádico, fora do território) — reproduzido de forma independente**: escrevi um script isolado (não reaproveitando código do spec) que sobe `net.serve` local + roda `lune run src/cli/main.luau run <projeto>` fazendo `GetAsync` contra ele, em loop de 40 rodadas seriais, sem nenhuma concorrência. Resultado: **1/40 falhas**, com a MESMA assinatura descrita pelo coder:
```
[Stack Begin]
    Script '[C]' - function 'error'
    Script '...\src\services\behavior\HttpService', Line 1255
    Script '...\src\services\behavior\HttpService', Line 1353
    Script 'DataModel.ServerScriptService.Main', Line 3
    Script '...\src\runtime\Sandbox', Line 549
[Stack End]
```
com stdout ainda dizendo `"0 error(s), 0 warning(s)."` e exit code 0. Confirma que o achado é real (taxa consistente com a faixa 5-20% relatada, não isolada/fabricada) e que o bug é genuinamente em `src/services/behavior/HttpService.luau` (propagação de erro de rede) + `src/runtime/Sandbox.luau` (linha 549, não capturando pelo mesmo caminho de `ThreadError`) — fora do território `cli`. **Recomendo abrir task nova para `coder-services`/`coder-runtime`** — concordo com a recomendação do coder.

**6. Retry do teste não mascara regressão sistêmica** — lido o loop (`RunCommand.spec.luau:429-457`): só quebra cedo em sucesso (`reachedExpectedBody`); se `GetAsync` falhasse SEMPRE, as 8 tentativas rodariam até o teto e `finalResult` carregaria a última falha. O assert final (`string.find(result.stdout, "got body: " .. RESPONSE_BODY, ...)`, linha ~462) falharia corretamente mesmo que `result.code == 0` (o próprio bug do achado nº2 faz o exit code ficar 0 mesmo em falha) — a asserção de conteúdo do body é quem realmente guarda contra regressão sistêmica, e ela não tem como ser satisfeita por acidente. Mitigação é honesta, não mascara.

**7. `--!strict` / zero `any`** — `head -1` confirma `--!strict`. Único hit de `any` no arquivo é dentro de uma mensagem de erro em inglês (`"could not bind ... to any of {N} candidate ports"`), não um tipo. `luau-lsp analyze --platform=standard --settings=".luaurc" src/cli/RunCommand.spec.luau` não produziu nenhum diagnóstico novo — só o pré-existente em `RunCommand.luau:470` (arquivo intocado por esta task, já documentado como pré-existente).

**8. Território** — ver acima, confirmado limpo.

**Extra — suíte completa `src/cli/` (16 arquivos)**: rodei todos, zero regressão, contagens batem exatamente com o relatado pelo coder (Args 18/18, CloudStore 9/9, Diagnostics 7/7, JsonValue 8/8, Messages 16/16, ModuleLoader 12/12, OutputFormatter 13/13, ProjectFile 17/17, RunCommand 31/31, ScriptEnvironment 8/8, ScriptRunner 7/7, SyncRules 33/33, TreeMaterializer 28/28, TreePlanner 38/38, UnsimulatedGlobals 6/6, init 7/7).

## Ressalva menor (não bloqueia)

`PROCESS_UNIQUE_SUFFIX` depende de `math.random` sem `math.randomseed` explícito para garantir unicidade entre processos — é uma garantia probabilística (~1/900000 de colisão por par), não estrita. Validado empiricamente por mim (4 valores distintos em 4 processos concorrentes, mais os testes do próprio coder) e o raciocínio de não usar `os.time()`/`os.clock()` como seed (granularidade de 1s reduziria entropia) é correto. Risco residual baixíssimo, aceitável, mas vale registrar caso apareça uma colisão rara no futuro — não é motivo de reprovação.

## Veredito

APROVADO
