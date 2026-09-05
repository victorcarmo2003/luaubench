# coder-services — task-services-010 — EngineFixedChildren.luau + Services.IsEngineFixedChild

## Arquivos

**Criados:**
- `src/services/EngineFixedChildren.luau` — módulo folha novo.
- `src/services/EngineFixedChildren.spec.luau` — spec dedicado (regra 01).

**Modificados:**
- `src/services/behavior/StarterPlayer.luau` — `Initialize` passou a iterar `EngineFixedChildren.Of("StarterPlayer")`, passando `child.Name` explicitamente a `NewEngineInstance` (antes passava `nil`).
- `src/services/init.luau` — nova função pública `Services.IsEngineFixedChild(parentClassName, name, className): boolean`, delegando a `EngineFixedChildren.Is`; cabeçalho atualizado (lista "ÚNICA superfície que cli enxerga" + require novo).
- `src/services/init.spec.luau` — dois blocos de teste novos: (1) `Services.IsEngineFixedChild` ANTES de `Bootstrap`, incluindo os 5 casos de guarda do acceptance via a superfície pública; (2) TESTE DE COERÊNCIA pós-`Bootstrap` contra `game` real.

Nenhum arquivo fora de `src/services/` tocado (confirmado por `git status --porcelain`). `.claude/tasks.json` aparece modificado (`todo` -> `in-progress`) mas essa mudança já estava presente quando a tarefa foi lida no início desta sessão — não fiz nenhuma edição nesse arquivo.

## Desenho seguido

`.claude/agents-memory/arquiteto-cli-2026-09-05.md`, seção "Revisão pós-implementação 2026-09-05 (task-cli-015) — filho fixo do motor: adotar, não criar", subseções "Onde vive a lista fechada" e "Módulos". Implementação segue o pseudocódigo do desenho quase literalmente (Of/Is, tabela `ENGINE_FIXED_CHILDREN` com a única chave `StarterPlayer`, `Services.IsEngineFixedChild` delegando 1:1).

## Superfície coberta

- `EngineFixedChildren.EngineFixedChild` (export type: `{ Name: string, ClassName: string }`).
- `EngineFixedChildren.Of(parentClassName): { EngineFixedChild }` — nunca `nil`.
- `EngineFixedChildren.Is(parentClassName, name, className): boolean` — trio completo.
- `Services.IsEngineFixedChild(parentClassName, name, className): boolean` — nova função pública, pura, segura pré-`Bootstrap`.
- `EngineFixedChildren.Of` **não** é reexportado por `init.luau` (fica interno ao território `services`, conforme exigido).

## Superfície NÃO coberta

- Nenhuma entrada para `Workspace`/`Terrain` — deliberado (`Covered=false` no manifesto, sem `behavior/Workspace.luau`; declarar aqui faria `cli` procurar um filho que o motor nunca cria).
- Nenhuma API de criação nova em `Services` — confirmado por leitura da superfície pública (`grep "^function Services\."` em `init.luau`): `Register`, `Bootstrap`, `IsKnownClass`, `IsSimulatedClass`, `GetDumpVersion`, `IsServiceClass`, `GetSimulatedServiceClasses`, `IsEngineFixedChild`, `new` — só `new` cria, e já existia antes desta tarefa.

## Fidelidade

Divergência declarada no cabeçalho de `EngineFixedChildren.luau`: no Roblox real, `StarterPlayerScripts`/`StarterCharacterScripts` são propriedade do motor e não podem ser destruídos por um script; no LuauBench a instância é uma `Runtime.Instance` simulada comum — `Destroy()`/reparent funcionam normalmente. Aceito nesta fase (implementar a proteção exigiria conceito novo em `runtime`, fora do desenho desta tarefa).

Duas listas fechadas continuam existindo por design, não por duplicação: `src/cli/SyncRules.FIXED_CHILD_CLASS_NAMES` (o que o Rojo real infere) e `EngineFixedChildren` (o que o motor simulado de fato pré-cria) — `Workspace -> Terrain` só existe na primeira.

## Testes

Todos rodados agora via `lune run`, nesta máquina:

- `src/services/EngineFixedChildren.spec.luau`: 9/9 (Of ordenado, Of `{}` para chave desconhecida, Is true para as 2 entradas reais, TESTE DE GUARDA com os 5 trios do acceptance — todos `false`).
- `src/services/init.spec.luau`: 18/18 (inclui `IsEngineFixedChild` antes de `Bootstrap` com os 5 casos de guarda pela superfície pública + TESTE DE COERÊNCIA pós-`Bootstrap` contra `game:GetService("StarterPlayer"):FindFirstChild(...)`).
- `src/services/behavior/StarterPlayer.spec.luau`: 3/3 (sem alteração, continua passando com o `Initialize` reescrito).
- `src/services/Integration.spec.luau`: 14/14 (seções 1b/6 — arquivo NÃO alterado, regressão confirmada).
- Regressão completa de `src/services/*.spec.luau` (10 arquivos): todos verdes.
- Regressão completa de `src/runtime/*.spec.luau` (8 arquivos): todos verdes.
- Regressão completa de `src/cli/*.spec.luau` (15 arquivos): todos verdes (nenhum arquivo de `cli` tocado, como esperado).

`luau-lsp analyze --platform=standard --settings=".luaurc"`:
- `EngineFixedChildren.luau`, `EngineFixedChildren.spec.luau`, `behavior/StarterPlayer.luau`: **zero diagnósticos**.
- `init.luau` (analisado no próprio caminho real): **zero diagnósticos**.
- `init.spec.luau`: reproduz os DOIS achados de tooling já documentados no próprio cabeçalho do arquivo (bug de `luau-lsp` 1.69.0 disparado pelo nome "init.spec.luau" — cascata de "Unknown require"/"Unknown type"; e o TypeError isolado no único `Runtime.Sandbox.Run` do arquivo, também já documentado e aceito para `src/runtime/init.spec.luau`). Confirmado empiricamente NESTA tarefa com a mesma técnica de cópia renomeada do arquivo já usada por `coder-services` em tarefas anteriores: uma cópia (`ZZZinit.spec.luau`) reproduz só o segundo achado (Sandbox.Run) — a cascata de "Unknown require" desaparece, e nenhum erro novo aparece no bloco de teste que acrescentei (linhas finais do arquivo). Nenhum diagnóstico novo introduzido por esta tarefa; cópias de teste removidas depois da verificação.

Zero `any` nos arquivos tocados/criados (confirmado por grep).
