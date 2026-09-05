# Revisão FINAL — task-services-003 (fechamento da leva 1)

Data: 2026-09-05. Território revisado: `src/services/behavior/` (incluindo `StarterPlayer.luau`
novo), `src/services/init.luau`, `src/services/Integration.spec.luau`. Contexto lido antes de
revisar: `.claude/tasks.json` (task-services-003, description/note/acceptance completos),
`.claude/agents-memory/arquiteto-services-2026-09-05.md` (Decisão 5), `.claude/agents-memory/
arquiteto-runtime-2026-09-04.md` (seção "Revisão pós-integração 2026-09-05 (4)").

Todos os 10 itens pedidos pelo orquestrador foram checados rodando código de verdade (binário
Lune de sempre, `/c/Users/hakor/.rokit/bin/lune`), não apenas lendo os testes do coder. Escrevi um
script de verificação independente (`scratch-revisor-services-check.luau`, executado a partir da
raiz do repo e depois apagado) que exercita os cenários usando a árvore REAL
(`game:GetService("ReplicatedStorage"/"Workspace")`), em vez dos substitutos (`Folder` solto) que
o `Integration.spec.luau` do coder usa por não poder usar `ReplicatedStorage` na primeira passada —
hoje esses substitutos são só uma escolha de não-duplicação, não mais uma necessidade, já que
`GetService` está desbloqueado.

## O que foi verificado, e como

1. **`game:GetService(...)` para as 9 Services** (ReplicatedStorage/ServerStorage/
   ServerScriptService/ReplicatedFirst/StarterPack/StarterGui/StarterPlayer/Lighting/Workspace):
   confirmado singleton correto, `Name == ClassName`, `rawequal(service.Parent, game)`, segunda
   chamada devolve o MESMO objeto (`rawequal`). Rodado via `Integration.spec.luau` seção "1b" (já
   existente) E via script próprio, direto contra `game:GetService`.

2. **`Instance.new`/`ClassRegistry.new`**: `Runtime.ClassRegistry.new("Folder", ...)` funciona;
   `Runtime.ClassRegistry.new("Workspace", ...)` ERRA com a mensagem nova de `task-runtime-023`
   ("... não é criável por script (tag NotCreatable ...); construção interna do motor usa
   ClassRegistry.NewEngineInstance") — confirma que a via pública protege mesmo com
   `NewEngineInstance` existindo. `Services.new("Workspace")` erra com a família Roblox
   ('Unable to create an Instance of type "Workspace"'), sem prefixo `[LuauBench]`.

3. **Folder parentado em `ReplicatedStorage` REAL** (via `GetService`, não substituto): `rs.Modules`
   resolve para o filho, `rs.Modules.Combat` resolve encadeado em 2 níveis a partir da raiz real.

4. **Modo estrito sobre `ReplicatedStorage` real**: ler nome fora do schema (`rs.Frobnicate`) erra
   "is not a valid member of"; ler `Archivable` (herdado de `Instance`, `Default = nil`) devolve
   `nil` sem erro; escrever `rs.ClassName = "Whatever"` erra
   "Unable to assign property ClassName. Property is read only" (string confirmada).

5. **Método sem implementação vs. excluído por Security**: `rs:Clone()` (em `MethodNames` sem
   `Behavior`) erra com prefixo `[LuauBench]`; `workspace:Set3dRenderingEnabled(false)` (excluído
   do schema/`MethodNames` na origem pelo filtro de Security/Capabilities do gerador) erra "is not
   a valid member of", SEM o prefixo `[LuauBench]` — a distinção que a revisão de 2026-09-05 do
   board pede.

6. **`StarterPlayer` nasce com os 2 filhos**: `game:GetService("StarterPlayer").Parent` é `game`
   (setado por `DataModel.GetService`, não pelo `Initialize`); `StarterPlayerScripts`/
   `StarterCharacterScripts` existem via `FindFirstChildOfClass`, ambos com `Parent` igual ao
   `StarterPlayer` (`rawequal` confirmado nos dois). Lido `behavior/StarterPlayer.luau` linha a
   linha: o `Initialize` só faz `filho.Parent = instance` duas vezes — nunca toca
   `instance.Parent`. Confirmado também por `behavior/StarterPlayer.spec.luau` (3/3) e pela seção
   "6" reescrita de `Integration.spec.luau`.

7. **`script.Source` erra**: `Services.new("Script", "S1").Source` erra
   `'Source is not a valid member of Script "MyScript"'` (o formato de membro inexistente do
   LuauBench — nunca string vazia, nunca o código real). Divergência de família de mensagem
   comentada no próprio teste do coder (`Integration.spec.luau`, seção 5) E no cabeçalho de
   `init.luau`: Roblox real erraria por capability (`"The current thread cannot read 'Source'
   (lacking capability PluginOrOpenCloud)"`), LuauBench erra por "not a valid member of" — declarado,
   nunca silencioso. `Runtime.Instance.SetPropertyRaw`/`GetPropertyRaw` confirmados funcionando
   sem passar pelo schema (gravei `"return 42"`, li de volta igual, e confirmei que `.Source` via
   schema continua errando depois do `SetPropertyRaw`).

8. **`git diff --stat` HEAD**: zero edição em `src/services/generated/**` e zero edição em
   `src/runtime/**` nesta retomada. O diff de trabalho toca só `.claude/tasks.json`,
   `src/services/Integration.spec.luau`, `src/services/behavior/Index.luau`,
   `src/services/behavior/Index.spec.luau`, `src/services/init.luau`, mais os dois arquivos novos
   (`behavior/StarterPlayer.luau` e seu spec). O fix de `task-runtime-023` em
   `src/runtime/ClassRegistry.luau`/`DataModel.luau`/`init.luau` já está commitado (`b7c8171 fix
   (runtime): separate NotCreatable (script) from engine construction`), fora do diff desta
   retomada — confirmado lendo `git log --oneline` e o próprio `ClassRegistry.luau`.

9. **Testes-gatilho reescritos, não apagados**: `git diff HEAD -- src/services/Integration.spec.luau`
   mostra a seção "6" (antes "BLOQUEIO CONHECIDO", dois testes que afirmavam de propósito o
   comportamento ERRADO com `pcall`+mensagem antiga `"'X' é abstrata, não pode ser instanciada"`)
   virando dois testes de caminho feliz: `game:GetService('StarterPlayer')` nasce com os filhos, e
   a via pública (`ClassRegistry.new`) continua rejeitando `StarterPlayerScripts`, agora com a
   mensagem NOVA de `task-runtime-023`. Nada foi deletado silenciosamente — o histórico do arquivo
   confirma a reescrita linha a linha.

10. **Regressão total**: rodei cada `.spec.luau` individualmente via `lune run`.
    - Runtime: `ClassRegistry` 29/29, `DataModel` 12/12, `Instance` 57/57, `Integration` 9/9,
      `Sandbox` 7/7, `Scheduler` 16/16, `Signal` 7/7, `init` 6/6 → **143/143**, batendo com o
      relatado.
    - Services: `ClassBuilder` 9/9, `Context` 3/3, `Integration` 14/14, `init.spec` 7/7,
      `behavior/Index` 2/2, `behavior/StarterPlayer` 3/3 → **38/38**, batendo com o relatado.

## Checagens de qualidade adicionais

- `--!strict` presente em todo `.luau` tocado (behavior/, init.luau, specs).
- Zero ocorrência de `any` fora de comentário (`grep -n "\bany\b"` em `src/services/**` só bate
  em texto de comentário explicando "nunca any").
- `luau-lsp analyze --platform=standard` limpo nos 6 arquivos tocados desta retomada
  (`behavior/StarterPlayer.luau`, `behavior/Index.luau`, `behavior/StarterPlayer.spec.luau`,
  `behavior/Index.spec.luau`, `init.luau`, `Integration.spec.luau`) — nenhum erro/warning de tipo.
- `NewEngineInstance` confirmado reexportado por `src/runtime/init.luau` (linha 149) e coberto por
  teste próprio em `init.spec.luau`.
- Lista fechada de chamadores legítimos de `NewEngineInstance` (documentada no cabeçalho de
  `ClassRegistry.luau`) bate exatamente com o uso real: `DataModel.GetService` (chamador #1) e
  `behavior/StarterPlayer.luau` (chamador #2) — nenhum terceiro call site apareceu em
  `src/services/**` ou `src/runtime/**` (`grep -rn NewEngineInstance` confirma só esses dois +
  os specs).

## Achados

Nenhum. Não encontrei propriedade/evento/método inventado fora do dump, nem stub silencioso, nem
divergência não declarada. As mensagens de erro batem com a família certa (Roblox sem prefixo para
o que tem contraparte real, `[LuauBench]` para o que não tem, português para erro de engenharia
interna do LuauBench). A separação `ClassRegistry.new` (via pública, com guarda de `NotCreatable`)
vs. `ClassRegistry.NewEngineInstance` (via do motor, sem guarda) está corretamente restrita: nenhum
caminho alcançável pelo script do usuário chega em `NewEngineInstance` sem passar por
`Services.new`/`ClassRegistry.new` antes.

## Veredito

APROVADO. Fecha `task-services-003` de vez — a primeira leva inteira de classes reais de
`services` (contêineres da árvore Rojo, Scripts, Workspace/Lighting, mais o desbloqueio de
`GetService` via `task-runtime-023`) está íntegra, testada e fiel ao Roblox API Dump referenciado
(commit `28360dea...`, versão `0.737.0.7371584`).
