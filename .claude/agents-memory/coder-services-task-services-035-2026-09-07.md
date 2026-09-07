# task-services-035 — Gerador: toda Property do dump entra no schema; Security/Tags decidem ScriptVisible, não existência

**Data:** 2026-09-07
**Dump fixado:** `MaximumADHD/Roblox-Client-Tracker @ 28360dea4b90b35dc3fe9f829baae64fb6c50e75` (Roblox `0.737.0.7371584`)
**Depende de:** task-runtime-039 (confirmado concluído e commitado, `9c10e31 feat(runtime): add ScriptVisible axis to MemberDescriptor` — `Runtime.MemberDescriptor.ScriptVisible: boolean?` já existe em `src/runtime/Instance.luau`, e `__index`/`__newindex` tratam `ScriptVisible == false` como ausente).

## Arquivos

**Modificados:**
- `tools/generate-services.luau` — `classifySchemaMember` bifurcado; emissão do descritor; nova seção de relatório.
- `tools/generate-services.spec.luau` — 2 testes existentes reescritos (a semântica mudou de "ausente" para "load-only"), 5 testes novos dedicados à classificação.
- `src/services/generated/**` (30 arquivos: `Index.luau`, `Manifest.luau` + 28 `classes/*.luau`) — regenerado via `lune run tools/generate-services`.

## Classe(s) impactada(s)

Todas as 17 classes do fecho que ganharam Property load-only nova: `Workspace` (48), `StarterPlayer` (24), `Instance` (15), `Model` (11), `LuaSourceContainer` (7), `WorldRoot` (7), `Players` (6), `StarterGui` (6), `SoundService` (4), `ModuleScript` (3), `RunService` (3), `DataStoreService` (2), `Lighting` (2), `PVInstance` (2), `Folder` (1), `Script` (1), `ServerScriptService` (1) — total **143**, batendo exatamente com os números do desenho (`arquiteto-rojo-properties-2026-09-07.md`, §2 e task description). Confirmado por script Node independente contra o dump pinado antes de tocar o gerador (mesma metodologia da pesquisa) e depois cruzado contra a saída real.

## O que mudou

`classifySchemaMember` (agora com `type SchemaClassification` carregando `scriptVisible: boolean` e `scriptInvisibleReason: string?` novos):

- Ramo **Property**: `included = true` SEMPRE. Os antigos passos 2/3 (que excluíam do schema por `NotScriptable`/`Security.Read` elevado/tag `WriteOnly`/capability reservada em `required_read`) agora retornam `included = true, scriptVisible = false` com o motivo anotado. Passos 4-8 (inalterados) continuam decidindo `readOnly` exatamente como antes, com `scriptVisible = true`.
- Ramo **Event/Callback**: regra **literalmente inalterada** — os mesmos passos 2/3 continuam retornando `included = false` (ausente do schema). Verificado por `git diff` no `src/services/generated/**`: toda linha `Kind = "Event"` removida tem uma linha `Kind = "Event"` idêntica adicionada (mesmo nome, só ganhou `ScriptVisible = true`) — nenhum Event novo entrou, nenhum saiu. Contagem de Event/Callback no schema do fecho: **24 antes, 24 depois** (mesmo conjunto, confirmado via `git diff` nome-a-nome, não só pela contagem).
- `classifyMethodMember`: **intocada** (não editada).

Emissão (`generateClassFile`):
- `scriptVisible == false` → `Default = "nil"` literal sempre, **sem chamar `computeDefault`** (decisão deliberada documentada no cabeçalho do arquivo gerado — nunca ler como "o dump não tinha Default").
- `ValueType`/`ValueCategory` sempre emitidos via `valueTypeFieldLiterals` (já era incondicional, não mudou), inclusive para entradas invisíveis.
- `ScriptVisible = true/false` emitido literal em **todo** descritor Property/Event/Callback do schema.
- Entrada `scriptVisible == false` **nunca** entra em `typeFieldLines` (guard mudou de `if not NATIVE_COVERED...` para `if classification.scriptVisible and not NATIVE_COVERED...`) — nunca aparece no `export type` público.
- Nova seção de relatório: "Property no schema porém INVISÍVEIS ao script (load-only)" — contagem por classe + lista `Classe.Membro (motivo)`, motivo em `{NotScriptable, Security.Read, WriteOnly, "capability reservada: <nome>"}`.
- `schemaExcludedByCapability` continua populado do mesmo jeito (mesmas 4 entradas: `Script.Source`, `ModuleScript.Source`, `RunService.FrameNumber`, `RunService.Misprediction`) — o texto do cabeçalho do print foi ajustado para deixar explícito que, para os 3 `Property`, "excluído" agora significa "load-only", enquanto o `Event` (`Misprediction`) continua de fato ausente.

## Verificação do critério de pronto (aceite do board)

- `src/services/generated/classes/Lighting.luau`: `["Technology"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "Technology", ValueCategory = "Enum", ScriptVisible = false }` — bate exatamente. Confirmado que `"Technology"` NÃO aparece no bloco `export type Lighting`.
- `Workspace.FilteringEnabled`: `ScriptVisible = true, ReadOnly = true` — confirmado (só `Security.Write` é elevado no dump, `Security.Read = None`).
- Nenhum `Event`/`Callback` novo no schema (24 = 24, nome-a-nome via `git diff`).
- Nenhum `MethodNames` mudou (`git diff` nos blocos `MethodNames = { ... }` de todas as 30 arquivos: zero linha `+`/`-` de conteúdo).
- Relatório do gerador imprime a seção nova (rodei `lune run tools/generate-services` e capturei a saída) — bate 100% com os números do desenho, por classe e no total (143).
- `tools/generate-services.spec.luau` cobre a classificação nova: 2 testes dedicados (`Lighting.Technology` — Security.Read elevado → `included=true, scriptVisible=false`; `RunService.RobloxGuiFocusedChanged` — Event com `Security=RobloxScriptSecurity` → continua ausente) + 3 testes complementares (`Workspace.CollisionGroups` — NotScriptable; `Workspace.FilteringEnabled` — continua visível; export type nunca ganha campo load-only; contagem de Event idêntica).
- `--!strict`, sem `any`: confirmado por `luau-lsp analyze` (zero erro/warning nos dois arquivos) e por grep manual (nenhuma ocorrência de `any` fora de comentário).

## Testes rodados (resultado real)

- `lune run tools/generate-services` — geração OK, relatório conferido linha a linha contra os números do desenho.
- `lune run tools/generate-services.spec.luau` — **26/26 passaram** (21 pré-existentes ajustados/mantidos + 5 novos).
- `luau-lsp analyze --platform=standard` em `tools/generate-services.luau`, `tools/generate-services.spec.luau`, e em **todo** `src/services/**/*.luau` (não-spec, ~90 arquivos via `find`) — zero erro/warning.
- Determinismo: rodei o gerador duas vezes seguidas e comparei sha256 de todo `src/services/generated/**` — **idêntico byte-a-byte**.
- Suíte completa de `src/services/**/*.spec.luau` (29 arquivos, todos rodados individualmente): **todos passaram**, exceto uma flakiness pré-existente e **não relacionada** — ver "Divergência observada" abaixo.
- Suíte completa de `src/cli/**/*.spec.luau` (16 arquivos), incluindo os citados na seção "Atenção" da tarefa: `TreeMaterializer.spec.luau` (28/28), `ModuleLoader.spec.luau` (12/12), `ScriptRunner.spec.luau` (7/7), `init.spec.luau` (7/7), `RunCommand.spec.luau` (31/31) — todos passaram. Confirma que `Script.Source`/`ModuleScript.Source` virarem load-only (presentes, `ScriptVisible=false`) **não** quebrou `TreeMaterializer.SetPropertyRaw` nem `ModuleLoader`/`ScriptRunner.GetPropertyRaw` — os dois caminhos continuam ignorando o schema por desenho, exatamente como esperado.

## Divergência observada (não relacionada a esta tarefa, reportada por transparência)

- `src/services/behavior/HttpService.spec.luau`, teste "RequestAsync contra host inexistente ERRA com mensagem TRADUZIDA": **flaky pré-existente**, falha intermitentemente (~1 em 3 execuções) numa resolução DNS real contra um domínio `.invalid`. Não toquei em `HttpService.luau`/`behavior/**` nesta tarefa; reproduzi a falha e o sucesso alternando em execuções consecutivas sem nenhuma mudança de código — é dependência de rede/DNS do ambiente, não uma regressão desta tarefa. Fora do meu território para investigar/corrigir.
- `src/cli/RunCommand.luau:470`, `luau-lsp analyze`: `TypeError: Function only returns 1 value, but 2 are required here` (destructure de `pcall(bootstrapServices)`). Arquivo **fora do meu território** (`src/cli/`), não editado por mim — presente no estado atual do repositório (commits mais recentes de `coder-cli`/trabalho paralelo). Reporto para a thread principal rotear a `coder-cli` se ainda não estiver sendo tratado.

## Fidelidade / decisões declaradas

- `Default = nil` para toda entrada load-only é uma decisão deliberada (não uma limitação do dump) — documentada no comentário inline do gerador (não há necessidade de tocar no cabeçalho `FILE_HEADER` dos arquivos gerados individualmente, já que a decisão vive no PRÓPRIO gerador, fonte única, e o comentário do `export type` de cada classe já explica por que `unknown`/campos ausentes não são "esquecimento").
- Nenhuma extensão de superfície além do que o dump já tinha — só mudou ONDE a linha de corte entre "existe" e "existe mas invisível" é traçada, conforme o desenho do arquiteto validado por pesquisa contra o Rojo real.
- Zero mudança em `classifyMethodMember`/`MethodNames` e zero mudança na regra de `Event`/`Callback` — confirmado mecanicamente (diffs nome-a-nome), não só por inspeção visual.

## Próximo da sequência

`task-cli-038` (coder-cli) depende desta tarefa — pode prosseguir: `Runtime.ClassRegistry.GetFlattenedSchema` já devolve as entradas load-only (nenhuma API nova em `runtime`), e `TreeMaterializer.applyProperties` pode passar a resolver contra o schema achatado (incluindo invisíveis) em vez do caminho leniente atual.
