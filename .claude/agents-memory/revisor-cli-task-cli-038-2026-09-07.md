# revisor-cli — task-cli-038 ($properties vira HIDRATAÇÃO via SetPropertyRaw)

**Data:** 2026-09-07
**Território revisado:** `src/cli/TreeMaterializer.luau`, `src/cli/Messages.luau`, `src/cli/TreeMaterializer.spec.luau`, fixtures `load-only-properties/`, `structural-properties/`, `source-override/` (novas) + `properties/` (atualizada), todos em `src/cli/fixtures/tree-materializer/`.
**Método:** nada aceito por self-report. Todo achado abaixo foi reproduzido por mim, nesta sessão (specs rodadas de verdade, `luau-lsp analyze` rodado de verdade, pipeline real contra o projeto Tiktok rodado de verdade, dois scripts de verificação independentes escritos por mim, executados e apagados — nunca comitados, nunca fixture, fora do território de qualquer coder).

## Checklist do pedido — o que confirmei

1. **Bifurcação Caminho A / Caminho B.** Li `applyProperties` inteira (`TreeMaterializer.luau:474-581`). `git diff` isolado nesse trecho confirma que o Caminho B (leniente, só `game`/DataModel) é BYTE-A-BYTE o código antigo — só o comentário acima de `local writable = ...` mudou de texto, nenhuma linha de código foi tocada. Caminho A é inteiramente novo: `STRUCTURAL_PROPERTY_NAMES` (skip com warning) → `findMemberDescriptor` (nil → `invalid-property`/NotAMember; `Kind ~= "Property"` → `invalid-property`/NotAProperty) → `resolvePropertyValue` (inalterada) → `Runtime.Instance.SetPropertyRaw` sem `pcall`.
2. **Name/Parent/ClassName não têm mais efeito estrutural.** Escrevi um `.project.json` próprio (fora das fixtures do coder) com `Name`/`Parent`/`ClassName`/`ChildAdded`/nome inexistente no mesmo nó, materializei via `ProjectFile.Read → TreePlanner.Plan → TreeMaterializer.Materialize` chamados diretamente por mim. Confirmado: `instance.Name`/`.ClassName`/`.Parent` continuam os originais, exatamente 3 warnings `materialize/structural-property-ignored`.
3. **Antes desta task, `$properties.Name` renomeava de verdade.** Confirmado por duas fontes independentes: (a) `git show HEAD:src/cli/TreeMaterializer.luau` mostra a função antiga escrevendo TODA chave via `writable[key] = value` dentro de `pcall`, sem nenhum caso especial para `Name`/`Parent`/`ClassName`; (b) `src/runtime/Instance.luau:739-744` mostra que `__newindex` trata `Name` como campo de identidade real, gravável, que chama `setName`/`data.name = newName` — ou seja, o caminho antigo (que ia direto pro `__newindex` real) de fato renomeava.
4. **`$properties.Technology = "Voxel"` num `Lighting`.** Reproduzido no meu script: zero `Diagnostic` para o campo `Technology`, `Runtime.Instance.GetPropertyRaw(lighting, "Technology")` devolve um `EnumItem` real (`ValueTypes.TypeNameOf == "EnumItem"`, `tostring == "Enum.Technology.Voxel"`).
5. **Escrita/leitura de SCRIPT continua bloqueada.** Reproduzido no meu script: `workspace.FilteringEnabled = false` (via acesso de script simulado, cast `unknown -> {[string]:unknown}`) erra citando `"read only"`; `lighting.Technology` erra citando `"is not a valid member of"` tanto em leitura quanto em escrita.
6. **Event / nome inexistente.** Reproduzido: `$properties.ChildAdded = true` → `materialize/invalid-property` citando `"Event"`; `$properties.TotallyBogusName = 10` → `materialize/invalid-property` citando `"is not a valid member of"`.
7. **Precedência de `Source`.** Reproduzido com fixture própria: `$properties.Source` sobrescreve o conteúdo vindo de `$path` — `GetPropertyRaw(script, "Source")` devolve o valor de `$properties`, não o do arquivo em disco.
8. **Pipeline real contra o Tiktok.** Rodei eu mesmo: `lune run src/cli/main.luau run "C:\Users\hakor\Documents\Roblox-Games\Tiktok\default.project.json" --timeout 3 --verbose` (read-only, nada editado). Saída: **1 error apenas**, `materialize/invalid-class` para `Workspace.Baseplate` ("Part" não simulado). **Zero `materialize/invalid-property`.** Confirmei também que `"Part"` não aparece em nenhum arquivo de `tools/` — bate com a alegação de que é lacuna pré-existente, fora de escopo.
9. **16 specs de `src/cli/`.** Rodei cada um dos 16 arquivos `*.spec.luau` individualmente via `lune run`. Todos passaram: Args 18/18, CloudStore 9/9, Diagnostics 7/7, JsonValue 8/8, Messages 16/16, ModuleLoader 12/12, OutputFormatter 13/13, ProjectFile 17/17, RunCommand 31/31, ScriptEnvironment 8/8, ScriptRunner 7/7, SyncRules 33/33, **TreeMaterializer 32/32**, TreePlanner 38/38, UnsimulatedGlobals 6/6, init 7/7.
10. **`--!strict` / zero `any`.** Confirmado nos 3 arquivos alterados (`--!strict` na linha 1 de todos); `luau-lsp analyze --platform=standard --settings=".luaurc"` nos 3 arquivos devolveu zero diagnósticos. Única ocorrência da palavra "any" é dentro de um comentário (`TreeMaterializer.luau:561`, "nunca um `any` disfarçado"), não é tipo.
11. **Território limpo.** `git diff --stat` mostra só os arquivos alegados pelo coder em `src/cli/` + as 3 fixtures novas + a fixture `properties` atualizada. `src/services/generated/**` e `tools/generate-services.luau` aparecem modificados no `git status`, mas são de `task-services-036` (paralela) — confirmado, nenhum desses arquivos aparece tocado pelo diff do território de `cli`.

## Achado real (item 12 do pedido) — REGRESSÃO CONCRETA, reproduzida

O pedido pedia para tentar achar um contra-exemplo em que `SetPropertyRaw` rejeitasse um valor decodificado que passasse pelos filtros A1-A3. `SetPropertyRaw` em si (`src/runtime/Instance.luau:954-958`) não valida NADA por tipo — escreve qualquer valor. Nesse sentido estrito, o coder está certo.

Mas existe um caminho de erro real e MAIS SÉRIO que a análise do coder (e do arquiteto, no desenho) não considerou: `SetPropertyRaw` dispara `data.changed:Fire(name)` **de forma síncrona**, e esse `Fire` pode invocar um listener instalado por `services` (`behavior/<Classe>.luau`, dentro de `Initialize`, já ligado no bootstrap). Hoje existe exatamente um desses: `src/services/behavior/Lighting.luau:281` conecta `instance.Changed`, e para a propriedade `TimeOfDay` chama `parseTimeOfDay` (`Lighting.luau:164-174`), que **lança `error()`** para qualquer string que não bata o formato `H:MM`/`HH:MM`/`HH:MM:SS`.

`TimeOfDay` é `ValueCategory = "Primitive"` (`ValueType = "string"`) — em `resolvePropertyValue`, uma string comum passa DIRETO sem nenhuma validação de formato (só `Decode` valida array/objeto/enum). Ou seja: `$properties.TimeOfDay` com qualquer string malformada passa por A1/A2/A3 sem erro, chega em A4, `SetPropertyRaw` grava e dispara `Changed`, o listener de `Lighting` lança `error()`, e — via `src/runtime/Signal.luau:206-219` (sem thread "dona" via `ThreadBroker`, o PRIMEIRO erro é re-lançado depois do laço, `error(pendingError, 0)`) — esse erro escapa de `SetPropertyRaw` **sem nenhum `pcall` para capturá-lo** (A4 foi desenhada deliberadamente sem `pcall`).

**Reproduzido de ponta a ponta**, com um `.project.json` mínimo escrito por mim (`Lighting.$properties.TimeOfDay = "not-a-real-time-boom"`), rodando o binário real:

```
lune run src/cli/main.luau run "verify-cli038-e2e"
```

Resultado: **`luaubench run` crasha por inteiro** com um stack trace Lua cru, vazando caminho absoluto de instalação em disco (`D:\UserData\Documents\GitHub\luaubench\src\runtime\Signal`, `...\Instance`, `...\TreeMaterializer`, `...\RunCommand`) — exit code 1. NENHUM `Diagnostic` é produzido; o comando não termina de forma controlada.

**Isto é uma regressão real desta tarefa**, não um risco só teórico: confirmei que o código ANTIGO (`git show HEAD`) tratava exatamente este caso com sucesso — `writable[key] = value` rodava dentro de `pcall`, então o mesmo erro do listener de `Lighting` era capturado e virava `materialize/invalid-property` (`MaterializePropertyAssignmentFailed`), sem derrubar o comando. Ao trocar para `SetPropertyRaw` sem `pcall` no Caminho A, essa proteção foi perdida especificamente para este cenário — que é inteiramente alcançável por um `.project.json` de usuário legítimo (typo em `TimeOfDay`), viola a regra 00 ("nunca stack trace cru", "nunca crash não tratado") e reintroduz a MESMA classe de vazamento de caminho absoluto que task-cli-010/011 already fecharam para outros pontos deste mesmo arquivo.

Escopo atual: só `Lighting` tem um `Changed:Connect` em `behavior/**` hoje (confirmado por grep em `src/services/behavior/*.luau`), e dentro dele só `TimeOfDay` tem um caminho de `error()` alcançável por uma string arbitrária (`ClockTime` é número, sem validação de formato que possa lançar). Mas a causa raiz é estrutural: `applyProperties`/A4 assume que "depois de A1-A3 não sobra caminho de erro real" olhando só para `SetPropertyRaw` isoladamente, ignorando que `Changed:Fire` executa código arbitrário de `services` de forma síncrona e sem proteção. Qualquer `behavior/**` futuro com um `Changed:Connect` que valide/normalize e possa lançar reabre a mesma classe de bug.

**Correção sugerida (não bloqueante para o restante da tarefa, mas deveria ser uma correção rápida antes de fechar `task-cli-038`):** envolver a chamada de `SetPropertyRaw` em A4 num `pcall` + `stripEngineErrorLocation` (mesmo padrão já usado 2x neste arquivo para `Services.new`), convertendo esse tipo de erro em `materialize/invalid-property` em vez de deixá-lo escapar cru.

## Outros achados menores

Nenhum. `Messages.luau` segue a disciplina de "só formatação" do arquivo. As 4 mensagens novas (`MaterializeStructuralPropertyIgnored`, `MaterializePropertyNotAMember`, `MaterializePropertyNotAProperty`, mais a reutilização de `MaterializePropertyAssignmentFailed` no Caminho B) citam nó/campo corretamente e não vazam localização interna (testado pelo próprio coder e por mim).

## Veredito

**APROVADO COM RESSALVAS**

O núcleo da tarefa (fechar o bug que travava o template do `rojo init` — `Lighting.Technology`/`Workspace.FilteringEnabled`) está correto, bem testado (32/32 próprios + 16/16 arquivos da suíte de `cli`), fiel ao Rojo real pela pesquisa citada, e reproduzido por mim de ponta a ponta contra o projeto Tiktok real. Território limpo, `--!strict`/zero `any` confirmados.

A ressalva é o achado do item 12: uma regressão real e reproduzível em que `$properties` numa propriedade com `Changed:Connect` reentrante em `services` (hoje só `Lighting.TimeOfDay`) faz `luaubench run` crashar por inteiro com stack trace cru vazando caminho de instalação, em vez de produzir um `Diagnostic` como o resto do arquivo garante. Recomendo consertar (`pcall` em A4) antes de considerar `task-cli-038` fechada — é uma correção pequena e localizada, não exige redesenho.
