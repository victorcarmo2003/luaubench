# task-cli-034 — RunCommand.spec.luau instável (processo real) — investigação e fix

**Data:** 2026-09-06 · `coder-cli` · Território: `src/cli/RunCommand.spec.luau` + `src/cli/fixtures/run-e2e/http-audit/server/Main.server.lua` (comentário). `RunCommand.luau` (produção) **não foi tocado**.

## Causa raiz nº 1 (confirmada, corrigida) — recursos fixos compartilhados entre execuções CONCORRENTES deste mesmo spec

Antes desta correção, dois recursos eram **fixos e compartilhados entre processos**:
- A porta `47210` do `net.serve` local do teste `http-audit`.
- A raiz de scratch `%TEMP%/luaubench-runcommand-persist-spec/` (com nomes de caso também fixos: `roundtrip`, `write-failure`, `corrupted`, etc.) da PARTE 3/4.

Rodando o arquivo **uma instância de cada vez**, isso nunca falha (confirmado: 15 execuções seriais seguidas, 15/15 verdes, antes de qualquer mudança). O problema só aparece quando **duas ou mais instâncias do mesmo spec rodam concorrentemente** — cenário rotineiro neste projeto (regra 05: `coder-cli`/`revisor-cli`/`testador` disparados em paralelo o tempo todo, mais de um frequentemente verificando o mesmo comando ao mesmo tempo).

**Reproduzido ao vivo** (`for i in 1 2 3; do (lune run src/cli/RunCommand.spec.luau) & done; wait`): 2 das 3 instâncias falharam na chamada de `net.serve` do teste `http-audit` com:
```
Only one usage of each socket address (protocol/network address/port) is normally permitted. (os error 10048)
```
Isso explica por que a instabilidade nunca foi exclusiva do `http-audit` (achado do revisor de task-cli-035 sobre a PARTE 4 de persistência): qualquer teste que dependa de um caminho ou porta fixos está exposto à mesma classe de corrida — duas instâncias concorrentes escrevendo/apagando (`fs.removeDir`+`fs.writeDir`) o mesmo diretório de caso (`write-failure`, etc.) colidem exatamente do mesmo jeito, só que como corrida de arquivo em vez de porta.

### Fix aplicado

- `PROCESS_UNIQUE_SUFFIX` — sorteado uma vez por processo via `math.random(100000, 999999)`, sem `math.randomseed` explícito (confirmado empiricamente que o Luau já semeia `math.random` de forma distinta por processo: 4 processos `lune` concorrentes chamando `math.random(1, 1e9)` sem seed explícito produziram 4 valores diferentes — chamar `math.randomseed` com `os.time()`/`os.clock()` poderia na verdade REDUZIR essa entropia entre processos iniciados no mesmo segundo).
- `SCRATCH_ROOT = {TEMP}/luaubench-runcommand-spec-{PROCESS_UNIQUE_SUFFIX}` — raiz única por processo para TUDO que este spec gera (projeto dinâmico de `http-audit` + scratch da PARTE 3/4), removida inteira ao final.
- `http-audit`: porta agora escolhida dinamicamente (`startLocalHttpServer`, tenta até 25 candidatas aleatórias em 40000-59999, reagindo a falha de bind imediatamente via `pcall`+retry, nunca sleep) — e o projeto executado é uma cópia MUTÁVEL gerada em `SCRATCH_ROOT/http-audit` (`freshHttpAuditProject`) com a porta embutida no script, já que o fixture estático não podia mais ter a porta fixa e o sandbox do script não recebe variável de ambiente (regra 00). O fixture estático original (`src/cli/fixtures/run-e2e/http-audit/`) continua versionado como referência de formato, com o comentário atualizado para não afirmar mais uma porta fixa combinada com o spec.

### Verificação

- 8 instâncias concorrentes do spec completo: 8/8 com "31/31 testes passaram" (antes do fix: 2/3 falhavam).
- 6 instâncias concorrentes (rodada separada): 6/6 verdes.

## Causa raiz nº 2 (encontrada durante a investigação, FORA do território de `cli`) — `HttpService:GetAsync` falha esporadicamente e o erro escapa do pipeline normal

Depois de corrigir a causa nº 1, ainda restava flakiness **mesmo em execuções seriais** (sem concorrência nenhuma): 2 falhas em 20 execuções seriais, sempre no teste `http-audit`, sempre com a MESMA assinatura: `stdout` do processo filho contém só as duas linhas de sumário (`"1 Script(s) executed..."` / `"0 error(s), 0 warning(s)."`), sem a linha `"got body: ..."` esperada — e sem nenhuma linha `error ServerScriptService.Main:...` no meio.

Isolei o cenário **fora deste spec** (script mínimo com só `net.serve` local + `net.request` de um processo `lune` novo, em loop) e confirmei:

1. `HttpService:GetAsync` (`src/services/behavior/HttpService.luau:1255/1353`) falha esporadicamente com `"the request could not be completed"` — taxa medida entre ~5% (2/40) e ~20% por tentativa dependendo da carga da máquina no momento, **às vezes em rajadas de 2-3 falhas seguidas** (não estritamente independente).
2. Uma checagem de prontidão determinística (`net.tcp.connect("127.0.0.1", port)` bem-sucedida IMEDIATAMENTE antes de spawnar o processo filho) **não elimina a falha** — descarta "servidor local ainda não subiu" como causa.
3. **O mais grave:** quando a falha acontece no fixture REAL (sem `pcall`, exatamente como está commitado), o erro **escapa do pipeline normal de formatação/contagem** que qualquer outro erro de script usa (`error ServerScriptService.Main:2: ...` + `ErrorCount>=1`, confirmado comparando com o teste `module-error`). Em vez disso, sai como um dump CRU de stack nativo do Lune:
   ```
   [Stack Begin]
       Script '[C]' - function 'error'
       Script 'src\services\behavior\HttpService', Line 1255
       Script 'src\services\behavior\HttpService', Line 1353
       Script 'DataModel.ServerScriptService.Main', Line 2
       Script 'src\runtime\Sandbox', Line 549
   [Stack End]
   ```
   com o sumário final ainda dizendo `"0 error(s), 0 warning(s)."` e exit code `0` — ou seja, um erro real acontece e o resultado reportado ao usuário é "sucesso", exatamente a classe de bug que a regra 00 (fidelidade/nunca silencioso) e a regra 04 (nunca stack trace cru) proíbem.

**Isto é um bug real de `services`/`runtime`** (o erro de `HttpService:GetAsync`, sob esta condição específica, não propaga pelo mesmo caminho de `ThreadError`/`Sandbox` que outros erros de script usam) — **fora do território desta tarefa** (`src/cli/`) para corrigir. Não toquei `RunCommand.luau` nem `src/services/`/`src/runtime/`.

### Mitigação aplicada (no teste, não na causa)

`MAX_ROUNDTRIP_ATTEMPTS = 8`: o teste `http-audit` repete o round-trip inteiro (bind em nova porta aleatória a cada tentativa + spawn do processo filho) até 8 vezes, parando na primeira que produzir o corpo esperado. Nunca um `sleep` — reage à falha real, com teto. Isto NÃO mascara uma regressão de verdade: se o contrato quebrar sistematicamente (`GetAsync` sempre falhando, ou a linha de auditoria `[http] GET ...` sumindo), TODAS as 8 tentativas falham do mesmo jeito e a asserção final roda sem rede de segurança nenhuma. Só a falha rara/transitória documentada acima é absorvida.

### Recomendação para o orquestrador

Abrir uma tarefa nova para `coder-services`/`coder-runtime` investigar por que o erro de `HttpService:GetAsync` (falha real de rede, `src/services/behavior/HttpService.luau:1353`) não é capturado pelo mesmo `ThreadError`/ligação de sandbox que outros erros de script usam quando a falha ocorre nesta condição específica — resultando em stack trace cru vazando e `"0 error(s)"` falso no sumário. Não investiguei a causa exata dentro de `services`/`runtime` (fora do território), só confirmei o sintoma e que ele é reproduzível isoladamente, sem nenhuma dependência deste spec de CLI.

## Verificação final

- **40 execuções SERIAIS consecutivas** (duas levas de 20): **40/40 verdes** (`31/31 testes passaram` em cada uma).
- **8 instâncias CONCORRENTES**: 8/8 verdes (mais uma leva de 6/6 verdes, feita antes).
- **Suíte completa de `src/cli/` (16 arquivos)**: todos verdes, zero regressão (Args 18/18, CloudStore 9/9, Diagnostics 7/7, JsonValue 8/8, Messages 16/16, ModuleLoader 12/12, OutputFormatter 13/13, ProjectFile 17/17, RunCommand 31/31, ScriptEnvironment 8/8, ScriptRunner 7/7, SyncRules 33/33, TreeMaterializer 28/28, TreePlanner 38/38, UnsimulatedGlobals 6/6, init 7/7).
- `luau-lsp analyze --platform=standard --settings=".luaurc" src/cli/RunCommand.spec.luau`: zero diagnósticos novos — só o diagnóstico pré-existente e já documentado em `RunCommand.luau:470` (fora do diff desta task, já confirmado pré-existente pelo revisor de task-cli-035).
- `--!strict` mantido, zero `any` (única ocorrência da palavra é dentro de uma mensagem de erro em inglês, "any of {N} candidate ports").

## Arquivos tocados

- `src/cli/RunCommand.spec.luau` (modificado) — `PROCESS_UNIQUE_SUFFIX`/`SCRATCH_ROOT`, `startLocalHttpServer`, `freshHttpAuditProject`, retry do round-trip de `http-audit`, `PERSIST_SCRATCH_ROOT` agora sob `SCRATCH_ROOT`, limpeza final unificada.
- `src/cli/fixtures/run-e2e/http-audit/server/Main.server.lua` (comentário atualizado — não afirma mais porta fixa combinada com o spec; arquivo continua estático/versionado como referência, não é mais executado diretamente pelo teste).
