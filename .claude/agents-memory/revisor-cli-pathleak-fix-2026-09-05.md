# Revisão — task-cli-010 (vazamento de path absoluto/linha interna em erro de `$properties` inválido)

Data: 2026-09-05
Escopo: `src/cli/TreeMaterializer.luau`, `src/cli/Messages.luau`, `src/cli/TreeMaterializer.spec.luau` (diff da task-cli-010).
Metodologia: nada do self-report do coder foi aceito sem reprodução própria — todos os itens abaixo foram reexecutados por mim (thread do revisor), incluindo rodar a suíte completa, testar o regex isoladamente, reverter o fix via `git stash` para confirmar que o teste novo falha sem ele, e rodar `luaubench run` real contra projetos descartáveis.

## 1. Regressão total — reproduzida

Rodei `lune run` em todos os 32 arquivos `.spec.luau` de `src/` (mais `tools/generate-services.spec.luau`, fora do total de 405) individualmente e conferi:

- `cli`: 170/170 (Args 13, Diagnostics 7, JsonValue 8, Messages 10, ModuleLoader 12, OutputFormatter 13, ProjectFile 17, RunCommand 11, ScriptEnvironment 6, ScriptRunner 7, SyncRules 28, **TreeMaterializer 9**, TreePlanner 17, UnsimulatedGlobals 5, init 7)
- `runtime`: 162/162
- `services`: 73/73
- Total: **405/405**, nenhuma ocorrência de `FAIL` em nenhum arquivo (grep dedicado).

Números batem exatamente com o alegado pelo coder.

## 2/3. `stripEngineErrorLocation` — padrão confirmado por teste isolado

Implementação (`TreeMaterializer.luau:144-150`):
```lua
local function stripEngineErrorLocation(rawError: string): string
	local rest = string.match(rawError, "^.-:%d+: (.*)$")
	if rest == nil then
		return rawError
	end
	return rest
end
```

Escrevi um script descartável (`'.cache/repro-strip.luau`, apagado depois) exercitando 7 casos adversariais diretamente contra a função, incluindo:
- Caso real completo (`D:\...\TreeMaterializer:136: Gravty is not a valid member of Folder ...`) → corta certo, só o prefixo de localização sai.
- Mensagem contendo `field: Gravty` sem prefixo de localização → preservada intacta (sem falso positivo).
- Prefixo real + falso horário `5:00` embutido no restante da mensagem → só o prefixo é cortado, `5:00` sobrevive.
- Path Windows sozinho sem número de linha (`D:\...\file.luau: something`) → não casa nada (`:` seguido de `\`/letra nunca casa `%d+`), devolve intacto.
- Sem prefixo de localização nenhum → devolve original.
- Caso extremo hipotético com um `:123:` embutido ANTES do prefixo real → `.-` não-guloso para no PRIMEIRO, deixando o prefixo real de localização intocado no resto (nunca trunca a mensagem real do motor — o efeito é "não confundido" mas sempre erra para o lado seguro, nunca corta demais).

Todos os 7 casos passaram exatamente como o coder alega. O algoritmo está correto: `.-` não-guloso ancorado em `^` garante o PRIMEIRO `:<dígitos>: ` e não um `: ` qualquer.

## 4. Teste novo reproduz a falha ANTES do fix — confirmado

`git stash push -- src/cli/TreeMaterializer.luau src/cli/Messages.luau` (mantendo o spec novo intocado, pois ele não estava no stash) e rodei `lune run src/cli/TreeMaterializer.spec.luau`:

```
D:\...\TreeMaterializer.spec:309: mensagem de 'Gravty' NÃO deveria conter um caminho absoluto de
disco (letra:\), achou: Could not apply "$properties.Gravty" at "tree.ReplicatedStorage.BadProps":
D:\UserData\Documents\GitHub\luaubench\src\cli\TreeMaterializer:136: Gravty is not a valid member
of Folder "DataModel.ReplicatedStorage.BadProps"
```
Exit code 1, script aborta no 4º teste (o `test()` wrapper deste arquivo não faz `pcall` — comportamento pré-existente, igual a outros specs do projeto). Confirma que o teste novo é fiel ao bug relatado. `git stash pop` restaurou o fix; rodei de novo → 9/9 passando.

## 5/6. Reprodução end-to-end via CLI real — confirmado, mensagens acionáveis

Criei um projeto descartável fora do repo (`/tmp/luaubench-repro-cli010`, removido ao final) com `$properties: {Gravty: 10, className: "Hacked"}` num `Folder`, e rodei o binário real:

```
lune run src/cli/main.luau run "/tmp/luaubench-repro-cli010" --no-color
```
```
error: [materialize/invalid-property] Could not apply "$properties.Gravty" at "tree.ReplicatedStorage.BadProps": Gravty is not a valid member of Folder "DataModel.ReplicatedStorage.BadProps" (node: tree.ReplicatedStorage.BadProps, field: Gravty)
error: [materialize/invalid-property] Could not apply "$properties.className" at "tree.ReplicatedStorage.BadProps": Unable to assign property className. Property is read only (node: tree.ReplicatedStorage.BadProps, field: className)
...
EXIT: 2
```
Nenhuma das duas mensagens finais contém caminho de disco nem `TreeMaterializer:NNN:`. Ambas preservam o texto real do motor ("is not a valid member of...", "Property is read only") — continuam acionáveis, não viraram mensagem genérica. `exit code 2` confirma que o comando não falha silenciosamente.

## 7. Mecanismo mora em `TreeMaterializer.luau`, não em `Messages.luau` — justificado

`Messages.luau` (cabeçalho, linhas 18-20) é explícito: "Sem lógica de ramificação além de formatação simples... qualquer decisão sobre O QUE mostrar é de quem chama". `stripEngineErrorLocation` é uma decisão (SE cortar um prefixo via regex), não formatação — mora corretamente fora de `Messages.luau`, no mesmo padrão que `OutputFormatter.tryReattributeModuleError` já usa pela mesma razão. A justificativa de não reaproveitar `tryReattributeModuleError` também confere: aquela função casa o marcador `%[string "(.-)"%]:(%d+): (.*)$` (formato de chunk `[string "..."]` do Lune, usado por `loadstring`/Sandbox), enquanto o erro aqui vem de um módulo `require`ido normalmente, cujo chunk name é o PATH do arquivo direto (`D:\...\TreeMaterializer:136:`), sem o marcador `[string "..."]`. São formatos de marcador realmente diferentes — reaproveitar a função existente não casaria nada.

## 8. `--!strict` / sem `any` — confirmado

Os três arquivos (`TreeMaterializer.luau`, `Messages.luau`, `TreeMaterializer.spec.luau`) começam com `--!strict`. Único hit de `any` no diff é dentro de um COMENTÁRIO pré-existente (linha 172, "nunca um `any` disfarçado"), não um tipo. Nenhum tipo `any` real no diff.

## 9. `git status` limpo — confirmado

Removi meu script de reprodução (`.cache/repro-strip.luau`) e o projeto descartável em `/tmp`. `git status --porcelain=v1 -uall` mostra só os 3 arquivos do diff revisado (`Messages.luau`, `TreeMaterializer.luau`, `TreeMaterializer.spec.luau`). Sem resíduo.

## 10. Regressão de comportamento pré-existente — confirmado sem mudança inesperada

O teste pré-existente da fixture "properties" (linhas ~245-276, não tocado por este diff) continua checando só a PRESENÇA de "Gravty"/"read only" na mensagem (nunca a AUSÊNCIA de path) — continua passando porque o strip preserva o texto real do motor. Nenhum outro spec do projeto toca `stripEngineErrorLocation`/`applyProperties`/`MaterializePropertyAssignmentFailed`.

## Achado adicional (não coberto pelo self-report, encontrado por reprodução própria)

**[ALTO] `src/cli/TreeMaterializer.luau:251-262` (não tocado por este diff)**
Problema: o MESMO mecanismo de vazamento corrigido para `$properties` (erro `error(msg, 2)` de dentro de um `pcall` neste módulo, apontando o call site para o próprio `TreeMaterializer.luau`) também afeta a segunda `pcall` do arquivo — `pcall(function(): unknown return Services.new(node.ClassName, node.Name) end)` (linha 251-253) — cujo resultado de erro (`tostring(resultOrError)`) é passado CRU para `Messages.MaterializeInvalidClass` (linha 259), sem passar por `stripEngineErrorLocation`.

Cenário: usuário escreve um `"$className"` com typo (ex.: `"Frmae"` em vez de `"Frame"`) em qualquer nó do `.project.json`. Reproduzi de ponta a ponta com `lune run src/cli/main.luau run <projeto>`:
```
error: [materialize/invalid-class] Could not create "tree.ReplicatedStorage.Bad" as "Frmae": D:\UserData\Documents\GitHub\luaubench\src\cli\TreeMaterializer:252: Unable to create an Instance of type "Frmae" (node: tree.ReplicatedStorage.Bad)
```
O caminho absoluto de instalação do LuauBench (`D:\UserData\Documents\GitHub\luaubench\src\cli\TreeMaterializer:252:`) vaza exatamente como no bug original de `$properties` — mesma categoria, mesma regra 04 violada.

O comentário do cabeçalho do arquivo (linhas 41-53, pré-existente, não tocado por esta task) afirma "`Services.new` já devolve mensagens de ótima qualidade... este módulo só embrulha em `pcall` e cita o `NodePath`, nunca reconstrói a mensagem" — essa afirmação está desatualizada/incorreta à luz do próprio diagnóstico que motivou task-cli-010: `Services.new` (`src/services/init.luau:336`/`347`/`353`) também usa `error(msg, 2)`, então o call site também aponta para dentro de `TreeMaterializer.luau`, com o mesmo efeito colateral.

Correção: aplicar `stripEngineErrorLocation(tostring(resultOrError))` também na linha 259 (ou extrair o strip para antes do `tostring`/`bag:Add` de ambos os pontos), e atualizar o comentário do cabeçalho que afirma o contrário. Recomendo abrir uma task nova (`task-cli-011` ou correção-de-revisão) em vez de bloquear esta, já que o acceptance de task-cli-010 foi escrito especificamente para `$properties` (nome inexistente/somente-leitura) e foi cumprido à risca — mas o "espírito" da correção (fechar a categoria de vazamento de path/linha interna) ficou incompleto dentro do próprio arquivo tocado.

## Veredito

APROVADO COM RESSALVAS

O fix de task-cli-010 é correto, bem testado e reproduzido com sucesso para o escopo exato do acceptance (`$properties` inválido: nome inexistente e propriedade somente-leitura). Regressão total intacta (405/405), `--!strict` sem `any`, mecanismo no módulo certo, teste novo comprovadamente pego o bug antes do fix. A ressalva é o achado ALTO acima: a mesma classe de vazamento (path absoluto + linha interna) continua presente e reproduzível em `materialize/invalid-class` (`$className` inválido), no mesmo arquivo, um `pcall` acima do que foi corrigido — não bloqueia esta task pontual, mas deveria virar uma task de correção-de-revisão imediata para não deixar a categoria "vazamento de path interno" meio-fechada.
