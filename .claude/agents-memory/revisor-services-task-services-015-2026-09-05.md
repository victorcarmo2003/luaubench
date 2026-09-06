# Revisão — task-services-015 (ponte services: ValueType/ValueCategory + defaults reais)

Data: 2026-09-05. Revisor: `revisor-services`. Read-only, nada editado.

Território revisado: `tools/generate-services.luau`, `tools/generate-services.spec.luau`,
`src/services/generated/classes/*.luau` (40 classes), `src/services/generated/Index.luau`/
`Manifest.luau`. Confirmado por `git diff --stat`/`git status`: NENHUM arquivo fora desse conjunto
foi tocado (zero diff em `src/runtime/`, `src/cli/`, `src/valuetypes/`, `tools/generate-enums.luau`).
As mudanças em `src/services/behavior/DataStore*`/`GlobalDataStore*`/`Index.*` pertencem à
task-services-018 (outro coder rodando em paralelo) — fora do escopo desta revisão, não avaliadas.

## Verificações reproduzidas (não aceitei nenhuma alegação sem rodar)

1. `lune run tools/generate-services.spec.luau` → **17/17 passou**, rodado por mim.
2. `lune run tools/generate-services` rodado **duas vezes** por mim (com snapshot intermediário em
   `.../scratchpad/gen-run1` e `gen-run2`); `diff -rq` entre as duas saídas → **vazio** (idempotência
   byte-a-byte real, não alegada).
3. `Lighting.luau` inspecionado ao vivo: `Ambient`/`ColorShift_Bottom`/`ColorShift_Top`/`FogColor`/
   `OutdoorAmbient`/`ShadowColor` (6 Color3) todos com `Default = ValueTypes.Color3.new(...)`;
   `LightingStyle` com `Default = enumDefault("LightingStyle", "Realistic")`. Nenhum `nil` restante
   nesses campos.
4. `Model.luau`: `WorldPivot` com `Default = ValueTypes.CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)`
   (identidade, 12 componentes). `StarterPlayer.luau`: 7 propriedades Enum
   (`CameraMode`/`DevCameraOcclusionMode`/`DevComputerCameraMovementMode`/
   `DevComputerMovementMode`/`DevTouchCameraMovementMode`/`DevTouchMovementMode`/
   `LuaCharacterController`) todas com `enumDefault(...)` real.
5. Script próprio (`Runtime.Scheduler.new()` + `Runtime.DataModel.new()` +
   `Services.Bootstrap` + `game:GetService("Lighting"/"StarterPlayer")` + `Services.new("Model")`,
   caminho de produção real, não in-process de fachada) confirmou EM EXECUÇÃO:
   `typeof(lighting.Ambient) == "userdata"`, `tostring == "0.5, 0.5, 0.5"`,
   `tostring(lighting.LightingStyle) == "Enum.LightingStyle.Realistic"`,
   `tostring(model.WorldPivot) == "0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1"`,
   `tostring(starterPlayer.CameraMode) == "Enum.CameraMode.Classic"`. Nunca tabela crua
   (`type(ambient) ~= "table"` confirmado). Script apagado depois (não commitado).
6. `grep` por `NumberRange.new|TweenInfo.new|Faces.new|Axes.new|Rect.new|BrickColor.new|...` em
   `src/services/generated/` → **vazio**. Nenhum default de leva 2 inventado. Caso extra verificado:
   `Workspace.GlobalWind`/`InsertPoint` (ValueType `Vector3`, já simulado) continuam `Default = nil`
   — confirmei contra o dump bruto que o `Default` real ali é a sentinela
   `"__api_dump_class_not_creatable__"`, não uma falha do parser.
7. Gramática do `UDim2` (`{scale,offset},{scale,offset}`) confirmada contra o dump bruto: 14
   propriedades reais no dump (`ImageButton.TileSize`, `ScrollingFrame.CanvasSize`,
   `UIGridLayout.CellPadding` etc., nenhuma no fecho de 40 classes atual). Reproduzi a lógica exata
   de `parseCommaNumbers`/`gmatch("{(.-)}")`/`numbersToArgs` do gerador num script sintético próprio
   contra 5 exemplos reais do dump + 1 caso malformado → todos corretos (inclusive rejeição correta
   do malformado). Ordem `UDim2.new(xScale,xOffset,yScale,yOffset)` também confirmada contra
   `src/valuetypes/types/UDim2.luau` (mesma convenção `f[1..4]`/`Format`).
8. `grep -r "require.*services" src/valuetypes/` → só 1 falso-positivo (comentário citando o ID da
   task, não um `require` real). Grafo confirmado acíclico. `require("../../../valuetypes")`
   presente em exatamente 11 arquivos gerados, todos consistentes: nenhum "require morto" (arquivo
   que requer mas não usa `ValueTypes.`) nem "require faltando" (usa `ValueTypes.`/`enumDefault` sem
   requerer) — verifiquei por varredura própria nos 40 arquivos. Caminho relativo (`src/*/generated/
   classes/X.luau` → `../../../valuetypes` → `src/valuetypes`) resolve corretamente (confirmado pela
   execução real do item 5).
9. `--!strict` no topo dos dois arquivos confirmado. `grep -w any` só encontra ocorrências dentro de
   comentários (citando a regra "nunca `any`"), zero uso real de `any` como tipo.
10. Território limpo confirmado por `git status`/`git diff --stat`: só os arquivos do escopo desta
    tarefa + `.claude/tasks.json` (mudança de coluna `todo`→`in-progress`, esperado) + os arquivos de
    `behavior/DataStore*`/`Index.*` da task-services-018 concorrente (não avaliados, não misturados
    na análise).
11. Suíte completa rodada por mim, arquivo por arquivo (`lune run <spec>`):
    `src/runtime/*.spec.luau` (9 arquivos) — todos verdes (29/29, 25/25, 64/64, 9/9, 22/22, 16/16,
    8/8, 4/4, 6/6). `src/services/*.spec.luau` fora de `behavior/DataStore*`/`Index.*`
    (`AsyncCall`, `ClassBuilder`, `Context`, `EngineFixedChildren`, `InstanceState`, `Integration`,
    `RejectingSignal`, `behavior/Lighting`, `behavior/Players`, `behavior/RunService`,
    `behavior/StarterPlayer`, `init.spec`, `datastore/Store`, `datastore/Value`) — todos verdes,
    zero regressão. `behavior/DataStore*.spec.luau`/`behavior/Index.spec.luau` deliberadamente NÃO
    rodados (território do outro coder em edição concorrente agora).

## Achados

Nenhum GRAVE/ALTO. Um achado BAIXO:

```
[BAIXO] tools/generate-services.luau (branch UDim2 de computeDataTypeDefaultExpr)
Problema: a gramática UDim2 (extensão que o coder acrescentou por conta própria, fora da tabela 0.6
do desenho original) não tem NENHUMA cobertura automatizada — não há propriedade UDim2 viva no
fecho atual das 40 classes, e as funções de parsing são locais ao script (não um módulo), então
generate-services.spec.luau não consegue testá-las isoladamente (o próprio spec documenta essa
limitação no comentário acima do teste "ValueType/ValueCategory aparecem em toda Property").
Cenário de falha: uma atualização futura do dump ou uma refatoração do gmatch/parseCommaNumbers
quebra silenciosamente o parsing de UDim2, e nada no CI/spec detecta -- só apareceria quando uma
classe com UDim2 default entrar no fecho coberto, potencialmente muito depois da regressão.
Correção: não bloqueia esta tarefa (verifiquei a lógica manualmente contra 5 exemplos reais do dump
+ 1 caso malformado, todos corretos -- ver item 7 acima), mas registrar como dívida técnica: quando
uma classe leva-2/3 com UDim2 REAL entrar em coverage.luau, adicionar teste de integração dedicado
(mesmo padrão do teste de Color3/CFrame/Enum já existente).
```

## Veredito

**APROVADO**

Todas as 11 verificações pedidas foram reproduzidas por mim (não aceitei nenhum self-report):
17/17 do spec do gerador, idempotência byte-a-byte real entre duas rodadas, defaults reais
confirmados por inspeção do código gerado E por execução end-to-end (`Services.Bootstrap` →
`game:GetService` → propriedade real, não `nil`, não tabela crua), nenhum default de leva 2
inventado (grep vazio + caso de sentinela investigado e confirmado legítimo), gramática UDim2
validada contra o dump bruto e contra a implementação real de `ValueTypes.UDim2`, grafo de
dependência acíclico confirmado, `--!strict`/zero `any` confirmado, território limpo confirmado, e
zero regressão em toda a suíte de `runtime`/`services` que não pertence à task concorrente.
