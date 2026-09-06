# Revisão — task-cli-028-fix (resolvePropertyValue trata string sempre como primitivo)

Território: `src/cli/TreeMaterializer.luau`, `src/cli/TreeMaterializer.spec.luau`,
`src/cli/fixtures/tree-materializer/value-types/default.project.json`. Tudo reproduzido pelo
revisor, nenhum self-report aceito sem verificação direta.

## O que foi reproduzido de verdade

1. **216/216 confirmado independentemente**, rodando `lune run` em cada um dos 15 specs de
   `src/cli/` separadamente (não só o agregado): Args 13/13, Diagnostics 7/7, JsonValue 8/8,
   Messages 10/10, ModuleLoader 12/12, OutputFormatter 13/13, ProjectFile 17/17, RunCommand 12/12,
   ScriptEnvironment 8/8, ScriptRunner 7/7, SyncRules 33/33, TreeMaterializer 25/25, TreePlanner
   38/38, UnsimulatedGlobals 6/6, init 7/7. Soma = 216.

2. **Bug reproduzido de verdade, não só lido no diff.** `git stash push --keep-index --
   src/cli/TreeMaterializer.luau` reverteu SÓ a produção pro estado HEAD (pré-fix), mantendo o
   spec/fixture novos. Rodando `TreeMaterializer.spec.luau` contra essa versão antiga: 22/25
   passam, e o teste 23 (`CameraMode`) quebra com
   `assert` na linha 1324 — `typeof devolveu "string"` — exatamente a corrupção de tipo
   alegada. `git stash pop` restaurou o fix; rodei de novo e os 25/25 passaram. `git diff --stat`
   depois do pop confirma que o arquivo voltou byte-a-byte ao estado antes do stash (28 linhas
   inseridas, igual ao antes). Prova real de causa-efeito, não confiança no relato do coder.

3. **`StarterPlayer.CameraMode = "LockFirstPerson"` confirmado virando `EnumItem` real**: o teste
   novo (linhas 1297-1334) checa `typeof ~= "string"`, `ValueTypes.TypeNameOf == "EnumItem"`,
   `tostring == "Enum.CameraMode.LockFirstPerson"` e `== Enum.CameraMode.LockFirstPerson`
   (identidade, não só valor) — todos passam. Confirmei que `CameraMode`/`DevCameraOcclusionMode`
   são propriedades REAIS de `StarterPlayer` (não inventadas pelo teste): grep em
   `src/services/generated/classes/StarterPlayer.luau` mostra
   `ValueType = "CameraMode"/"DevCameraOcclusionMode"`, `ValueCategory = "Enum"`, default
   `enumDefault("DevCameraOcclusionMode", "Zoom")` — bate exatamente com o que o teste espera
   ficar preservado no caso de item inválido.

4. **`DevCameraOcclusionMode = "NotARealItem"` confirmado**: gera
   `materialize/undecodable-property` citando `"NotARealItem"` e o `NodePath` de `StarterPlayer`,
   `Severity = "error"`, e a propriedade fica com o Default real do schema
   (`Enum.DevCameraOcclusionMode.Zoom`), nunca `nil` nem a string inválida.

5. **Regressão `Folder.Name = "RenamedViaProperties"`** (string sem `MemberDescriptor` de Enum —
   caso "Name" é tratado pela base de `Instance`, sem Kind=="Property"/ValueCategory=="Enum" no
   schema achatado consultado): continua indo pelo caminho primitivo direto, sem nenhum
   Diagnostic, renomeando de verdade a Instance. Confirmado rodando o teste.

6. **`boolean`/`number` continuam indo direto, sem pagar `findMemberDescriptor`/`Decode`** —
   verifiquei isso de duas formas: (a) leitura de código, `rawKind == "boolean" or rawKind ==
   "number"` retorna ANTES de qualquer chamada a `findMemberDescriptor` (linhas 296-298); (b)
   escrevi um script Lua temporário (`src/cli/_review_tmp_check.luau`, deletado logo depois —
   `git status` confirma zero resíduo) registrando uma classe fictícia com propriedade `Speed`
   (number, `ValueCategory="Primitive"`) e `Flag` (boolean, idem), materializei via
   `TreeMaterializer.Materialize` de verdade e confirmei `typeof(Speed)=="number"`,
   `typeof(Flag)=="boolean"`, valores crus (`42.5`/`true`) sem erro nenhum no bag. A premissa do
   coder é factualmente correta: `Decode.luau` — lido inteiro — confirma `dataTypeDecoders` só
   aceitam `table` (via `asNumberArray`, que rejeita qualquer coisa que não seja `table` logo na
   primeira linha) e `decodeEnum` só aceita `string` — nenhum decodificador aceita
   boolean/number como forma ambígua.

7. **`findMemberDescriptor` chamado uma única vez** — linha 303, reusado tanto para decidir
   `isEnumProperty` (caso string) quanto para o branch de array/objeto que já usava esse
   descriptor antes desta correção. Sem chamada duplicada.

8. **`--!strict` presente nos dois `.luau`, zero `any` real** — única ocorrência da palavra `any`
   em `TreeMaterializer.luau` é dentro de um comentário ("nunca um `any` disfarçado"), não um tipo.
   Fixture é JSON, não se aplica.

9. **Território limpo** — `git status`/`git diff --stat` mostram só os 3 arquivos esperados
   modificados em `src/cli/`. `.claude/tasks.json` também aparece modificado, mas o diff
   (conferido) só toca `task-services-021`/`task-services-027` (`todo`→`in-progress`), de agentes
   concorrentes rodando em paralelo (`MessagingService`/cenário ProfileStore) — nada do
   `task-cli-028-fix` em si foi tocado por mim, e nada fora do território de `cli` foi alterado
   pelo coder-cli. Único arquivo não-rastreado remanescente (`tests/scenarios/_probe-temp.luau`) é
   do `testador` concorrente, fora do escopo desta revisão.

## Achado (não bloqueante, mas registrado)

**[BAIXO] `src/cli/TreeMaterializer.luau:288-293` (comentário) / `src/valuetypes/Decode.luau`**
Problema: a premissa "nenhuma forma ambígua do `Decode` usa boolean/number, e só `Enum` usa
`string`" é verdadeira apenas para a leva 1 de `dataTypeDecoders` (`Vector3`/`Vector2`/`Color3`/
`CFrame`/`UDim`/`UDim2`, todos via array). O próprio arquiteto já registrou como pergunta EM
ABERTO (`.claude/agents-memory/arquiteto-valuetypes-2026-09-05.md:907`) se algum `DataType` real
do Rojo é serializado como string (`BrickColor = "Bright red"`?) — não pesquisado ainda. Se um dia
`BrickColor` (ou outro `DataType`) ganhar suporte com forma-string, `resolvePropertyValue` vai
tratar essa string como primitiva pura (porque o gate `isEnumProperty` só dispara para
`ValueCategory=="Enum"`, não para `ValueCategory=="DataType"`) — reabrindo a MESMA classe de bug
para esse tipo específico, silenciosamente.
Cenário: leva 2 implementa `BrickColor` com decodificador de string em `Decode.luau`, mas ninguém
lembra de generalizar o gate em `TreeMaterializer`; `Part.BrickColor = "Bright red"` vira string
Lua crua de novo.
Correção: não é bloqueante agora (BrickColor não está na leva 1, e `Part`/`BasePart` nem estão
cobertos por `services` ainda — não há caminho de execução real hoje). Quando a pergunta em aberto
do arquiteto for resolvida, generalizar o gate para `descriptor.Kind == "Property" and
(descriptor.ValueCategory == "Enum" or (descriptor.ValueCategory == "DataType" and <tipo aceita
string>))`, ou documentar explicitamente por que não é preciso. Vale um comentário adicional aqui
apontando essa dependência futura entre `Decode.luau` e este gate, para não ficar esquecido.

## Veredito
APROVADO
