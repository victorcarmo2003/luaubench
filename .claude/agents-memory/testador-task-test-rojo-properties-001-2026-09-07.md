# Testador — task-test-rojo-properties-001 (2026-09-07)

Território: `tests/scenarios/` (exclusivo). Read-only em `src/**` e em `C:\Users\hakor\Documents\Roblox-Games`.

Leitura obrigatória feita antes de começar: `.claude/tasks.json` (task-test-rojo-properties-001) e `.claude/agents-memory/arquiteto-rojo-properties-2026-09-07.md` (desenho completo da leva task-runtime-039 → task-services-035 → task-cli-038).

## O que foi entregue

### 1. Cenário novo: `tests/scenarios/rojo-init-template-hydration.scenario.luau`

Dois testes:

- **Teste 1 (Tiktok real, subprocesso)** — roda `lune run src/cli/main.luau run <Tiktok> --no-color --timeout 5` contra `C:\Users\hakor\Documents\Roblox-Games\Tiktok\default.project.json` (read-only). Assert central: `materialize/invalid-property` nunca aparece no stderr, e nenhuma das 3 propriedades (`Technology`/`FilteringEnabled`/`RespectFilteringEnabled`) aparece perto de `"is not a valid member"`. Confirma que o script real do servidor roda (`Hello world, from server!`). Documenta o único achado remanescente (não relacionado): `Part`/Baseplate ainda não simulado (`materialize/invalid-class`, território `services`).
- **Teste 2 (fixture sintética, script real)** — fixture nova `tests/scenarios/fixtures/rojo-init-template-hydration/` (mesmos 3 pares `$properties` do Tiktok, sem `Baseplate`/`Part`, isolada de propósito da parede de cobertura não relacionada). O script (`src/server/init.server.luau`) faz 4 verificações e prova, com um script real dentro do sandbox, a garantia arquitetural D3/D4 do desenho:
  1. `workspace.FilteringEnabled` lê `true` (hidratado, apesar de `Security.Write=PluginSecurity`).
  2. `workspace.FilteringEnabled = false` **ainda erra** por script (`"Property is read only"`) — prova que a hidratação bypassar `ReadOnly` não afrouxou o enforcement de escrita por SCRIPT.
  3. `Lighting.Technology` **continua inatingível** por script (mesma mensagem `"is not a valid member of Lighting"` de uma chave ausente) — prova que `ScriptVisible=false` não foi afrouxado.
  4. `SoundService.RespectFilteringEnabled` lê `true` normalmente (property comum).

Achado de precisão registrado no cenário: `RespectFilteringEnabled` **nunca precisou** do fix desta leva — `Security.Read=Security.Write=None` no dump para essa propriedade específica (confirmado em `.claude/agents-memory/pesquisa-lighting-sound-physics-2026-09-05.md`). O que bloqueava o template antes era `SoundService` como **classe** não simulada — fechado numa leva anterior e independente (commit `ad83d97`, `feat(services): add SoundService`). Só `Lighting.Technology` (Security.Read elevado) e `Workspace.FilteringEnabled` (Security.Write elevado + ReadOnly) de fato dependiam do mecanismo `ScriptVisible` desta leva.

Ambos os testes passam hoje (`lune run tests/scenarios/rojo-init-template-hydration.scenario.luau` → `2/2 ... 0 falharam`, exit 0).

### 2. Reexecução de `real-roblox-games-pipeline-smoke.scenario.luau` — antes/depois

Rodei o binário real contra os 3 projetos e comparei com o estado documentado nos comentários (pré-existentes, e no contexto passado pelo orquestrador):

| Projeto | Antes (documentado) | Depois (medido agora) | Diagnóstico |
|---|---|---|---|
| Tiktok | 3 erros: `Lighting.Technology` inválida, `SoundService` não simulado, `Workspace.FilteringEnabled` read-only (mais o Baseplate/Part) → total efetivamente **2 erros de propriedade + Part** no comentário mais recente do arquivo | **1 erro**: só `Part`/Baseplate (`materialize/invalid-class`) | `1 error(s), 0 warning(s)`, ExitCode 2 |
| Panic - CHESSS | 1 erro: `HttpService` não registrada, citando `MatchmakingService:4`, ExitCode 2 | **Avançou mais longe**: `HttpService` já simulado (leva independente, task-services-026), agora erra em `Instance.new("RemoteEvent")` dentro de `ReplicatedStorage.Shared.Chess.Network:49`, ExitCode **1** (erro de SCRIPT, não de projeto — nenhum `Diagnostic` de projeto restante) | `1 error(s), 0 warning(s)` |
| TheGame | `plan/required-path-not-found` (Wally Packages/ServerPackages ausentes), ExitCode 2, ~777ms | **Inalterado** — mesmos 2 diagnósticos `plan/required-path-not-found`, ExitCode 2, ~6.7s de wall-clock (inclui overhead de processo; sem sinal de regressão de performance na medição interna) | 2 erros de projeto |

**Zero regressão nova encontrada.** A queda de erros do Tiktok (Lighting.Technology, Workspace.FilteringEnabled) é exatamente o efeito esperado da leva. A mudança no CHESS (HttpService → RemoteEvent) é de uma leva **anterior e independente** (HttpService passou a ser simulado antes desta rodada) — não relacionada a `$properties`/Security, documentada como tal.

Os comentários/asserts do arquivo **já estavam desatualizados antes desta leva** (confirmado rodando o binário real contra o estado atual: `[FAIL]` em 2 dos 3 testes antes de eu corrigir) — exatamente o aviso que o orquestrador já tinha registrado. Corrigi:
- Header: nova seção "ATUALIZAÇÃO 2026-09-07" explicando o que mudou e por quê (separando o que é desta leva do que não é).
- Teste 'Tiktok': assertions de `SoundService`/`FilteringEnabled` como erros trocadas por assertions de AUSÊNCIA desses diagnósticos + assert positivo de que `materialize/invalid-property` nunca mais aparece.
- Teste 'Panic - CHESSS': reescrito para o achado atual (`RemoteEvent`, ExitCode 1, linha `ReplicatedStorage.Shared.Chess.Network:49`), com o porquê do ExitCode ter mudado de 2 para 1 documentado (erro de script vs. erro de projeto, conforme a política de `RunCommand.Execute`).
- Teste 'TheGame': inalterado (já estava correto).

`lune run tests/scenarios/real-roblox-games-pipeline-smoke.scenario.luau` → `3/3 ... 0 falharam`, exit 0.

### 3. Achado colateral corrigido (fora do pedido explícito, mas no mesmo território e diretamente entrelaçado): `value-types-real-project.scenario.luau`

Ao reexecutar tudo, este outro cenário (não citado explicitamente na tarefa, mas testa as MESMAS 3 propriedades do template Tiktok) também estava `[FAIL]` em 2/2 testes, por 2 causas **totalmente independentes** desta leva:
- Mesma obsolescência de `SoundService`/`FilteringEnabled` já corrigida no smoke test.
- Um bug de Enum via `$properties` (documentado no próprio arquivo como "achado 3, bug real, território cli") já tinha sido corrigido por uma task **anterior e independente** (`9ea5cef fix(cli): decode Enum via \$properties instead of writing raw string`, task-cli-027 — confirmado via `git log`). O teste ainda esperava `[FIXTURE-FAIL]`/`7/8`; a fixture na verdade já passa `8/8`.

Corrigi as assertions e o comentário do cabeçalho, deixando claro que essas duas causas são de fora desta leva (rastreadas via `git log`/pesquisa nos `agents-memory`, não suposição). `lune run tests/scenarios/value-types-real-project.scenario.luau` → `2/2 ... 0 falharam`, exit 0.

### 4. Verificação de território completo

Rodei os 12 arquivos `.scenario.luau` de `tests/scenarios/` de ponta a ponta — todos passam, exit 0 em todos. Nenhum outro cenário tocava as propriedades desta leva.

## Arquivos tocados (todos dentro do território exclusivo)

- `tests/scenarios/rojo-init-template-hydration.scenario.luau` (novo)
- `tests/scenarios/fixtures/rojo-init-template-hydration/default.project.json` (novo)
- `tests/scenarios/fixtures/rojo-init-template-hydration/src/server/init.server.luau` (novo)
- `tests/scenarios/real-roblox-games-pipeline-smoke.scenario.luau` (atualizado — asserts desatualizados de Tiktok/CHESS)
- `tests/scenarios/value-types-real-project.scenario.luau` (atualizado — asserts desatualizados de Tiktok + achado 3, colateral)
- `.claude/tasks.json` (task-test-rojo-properties-001 → `done`, campo `result` preenchido)

Nenhum arquivo em `src/**` foi tocado (confirmado — só leitura via `Read`/`Grep`/execução de `lune run`). Nenhum arquivo em `C:\Users\hakor\Documents\Roblox-Games` foi tocado (só leitura via `Bash`/`cat`).

## Recomendação

- **Nenhum achado GRAVE novo.** A leva `task-runtime-039`/`task-services-035`/`task-cli-038` funciona exatamente como desenhado, ponta a ponta, contra o projeto real.
- Achado incidental de baixo risco, não bloqueante: o `Panic - CHESSS` agora falha com `ExitCode 1` em vez de `2` — isso é uma mudança de COMPORTAMENTO observável do CLI (erro de script tem prioridade de exibição diferente de erro de projeto) que reflete progresso real (mais uma classe simulada), não um bug. Nenhuma ação necessária.
- Backlog de cobertura (não urgente, território `services`, já era conhecido): `Part`/Baseplate e `RemoteEvent` ainda não simulados — ambos acionam a mensagem padrão "not simulated yet", não crash. Continuam sendo a próxima parede natural de cobertura para quem for expandir `services`.
