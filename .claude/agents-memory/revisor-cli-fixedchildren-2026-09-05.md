# Revisão task-cli-014 — TreePlanner infere ClassName de filhos fixos (StarterPlayerScripts/StarterCharacterScripts/Terrain)

Revisor: `revisor-cli` (read-only). Nenhum arquivo de `src/cli/` foi editado nesta revisão — só criei dois scripts TEMPORÁRIOS na raiz do repo (`_revisor_adversarial_check.luau`, `_revisor_services_check.luau`) para reprodução independente, executei e DELETEI os dois antes de terminar (`git status --short` confirmado limpo de qualquer resíduo meu, ver evidência abaixo).

Ceticismo aplicado: nada do "result" do coder foi aceito sem reprodução própria. Todo item abaixo tem evidência de comando real rodado por mim nesta sessão.

## 1. Regressão total — reproduzida, não aceita de relato

Rodei os 32 `*.spec.luau` individualmente (`lune run`), somei os contadores impressos:

```
13+7+7+8+10+12+13+17+11+6+7+33+10+21+5+29+12+6+63+9+20+16+7+4+8+11+3+9+3+16+14+5+10 = 425
```

**425/425, 32/32 arquivos com `exit=0`.** Bate exatamente com o alegado. Destaque:
`src/cli/SyncRules.spec.luau` = 33/33 (28 antigos + 5 novos), `src/cli/TreePlanner.spec.luau` = 21/21 (16 antigos + 5 novos) — nenhum teste de precedência pré-existente (`ClassifyFile`/`ClassifyDir`/conflito `$className`+`$path`/`service-name-mismatch`/projeto aninhado/ciclo) quebrou.

## 2. Estrutura mutuamente exclusiva por `parentClassName` — confirmada por leitura + teste adversarial próprio

Leitura de `TreePlanner.luau:611-618`:
```lua
local inferredClassName: string? = nil
if parentClassName == "DataModel" then
    if options.IsServiceClass(name) then inferredClassName = name end
elseif parentClassName ~= nil then
    inferredClassName = SyncRules.InferFixedChildClassName(parentClassName, name)
end
```
É `if`/`elseif` de verdade — não duas checagens independentes. Isso IMPLICA que sob `parentClassName == "DataModel"`, o ramo `SyncRules.InferFixedChildClassName` NUNCA é chamado (correto — o Rojo real também não checa `StarterPlayer`/`Workspace` fixos quando o pai é `DataModel`).

Não confiei só na fixture do coder (`fixed-child-wrong-parent`, que já cobre "Terrain sob StarterPlayer"). Escrevi um script adversarial próprio (`_revisor_adversarial_check.luau`, deletado depois) com um fixture cruzando TODOS os pares errados de uma vez: `StarterPlayer.Terrain`, `Workspace.StarterPlayerScripts`, `ReplicatedStorage.Terrain` (pai nem sequer um dos dois hardcoded), mais os pares corretos `Workspace.Terrain` e `StarterPlayer.StarterCharacterScripts` no mesmo plano. Resultado real (`lune run`):

```
[error] plan/missing-class-name :: tree.ReplicatedStorage.Terrain
[error] plan/missing-class-name :: tree.StarterPlayer.Terrain
[error] plan/missing-class-name :: tree.Workspace.StarterPlayerScripts
```
— e SEM erro nos dois pares corretos. Rodei também `SyncRules.InferFixedChildClassName` direto numa matriz de 10 combinações (incluindo `DataModel→Terrain`, `DataModel→StarterPlayerScripts`, pai=`"Terrain"`) — todas bateram o esperado, zero vazamento entre ramos.

## 3. Precedência — confirmada por leitura + specs existentes rodados por mim

- `$className` explícito vence inferência mesmo quando ambos bateriam: fixture `fixed-child-explicit-override` (`StarterPlayer.StarterPlayerScripts` com `$className:"Folder"`) → `ClassName == "Folder"`, teste passou dentro do 21/21.
- `$path` que resolve a `Folder` perde para a inferência: fixture `fixed-child-path-folder` (`Workspace.Terrain` com `$path` apontando pra uma pasta real só com um `readme.md` — que classifica como `Folder` puro) → `ClassName == "Terrain"`, mesma regra já usada pro Service (`TreePlanner.luau:896-902`, `if pathClassName=="Folder" and inferredClassName~=nil then pathOrInferredClassName=inferredClassName`). Também dentro do 21/21 que rodei.

## 4. Binário real contra os 3 projetos — rodado por mim, não só relatado

```
lune run src/cli/main.luau run "C:/Users/hakor/Documents/Roblox-Games/Tiktok" --no-color --timeout 5
```
→ stdout contém `ServerScriptService.Server: Hello world, from server!` e `1 Script(s) executed`; stderr SEM `plan/missing-class-name`; erros legítimos remanescentes (`materialize/service-not-simulated` SoundService, `materialize/invalid-class` StarterPlayerScripts, `Part` não simulado); `EXIT=2`.

```
lune run src/cli/main.luau run "C:/Users/hakor/Documents/Roblox-Games/Panic - CHESSS" --no-color --timeout 5
```
→ script real do jogo roda e erra em runtime citando `MatchmakingService:4` e `HttpService`; SEM `plan/missing-class-name`; `EXIT=2`.

```
lune run src/cli/main.luau run "C:/Users/hakor/Documents/Roblox-Games/TheGame" --no-color --timeout 5
```
→ `0.673s` real; `plan/required-path-not-found` (Packages/ServerPackages, Wally não instalado); SEM `plan/missing-class-name`; `EXIT=2`.

Também rodei o cenário oficial diretamente: `lune run tests/scenarios/real-roblox-games-pipeline-smoke.scenario.luau` → **3/3 PASS**, `EXIT=0`.

Tudo bate exatamente com o "result" do coder — inclusive as mensagens de erro remanescentes citadas linha a linha.

## 5. `Services.new` falhando para os 3 filhos fixos — confirmado por execução direta, com precisão adicional

Script temporário (`_revisor_services_check.luau`, deletado depois) que faz `Runtime.Scheduler.new()` + `Runtime.DataModel.new()` + `Services.Bootstrap` reais e chama `Services.new` direto:

```
Services.new("StarterPlayerScripts", ...) -> ok=false :: Unable to create an Instance of type "StarterPlayerScripts"
Services.new("StarterCharacterScripts", ...) -> ok=false :: Unable to create an Instance of type "StarterCharacterScripts"
Services.new("Terrain", ...) -> ok=false :: [LuauBench] Terrain exists in the Roblox API Dump (0.737.0.7371584) but is not simulated by LuauBench yet
Services.new("Folder", ...) -> ok=true :: userdata: ...   (controle positivo confirmando que o harness funciona)
```

Confirmado também via `src/services/generated/Manifest.luau:744/749/807`: `StarterPlayerScripts`/`StarterCharacterScripts` têm `IsAbstract=true, Covered=true` (por isso erram por `ClassRegistry.Get(...).IsAbstract`, família "Unable to create..." — fiel ao Roblox real, que também não permite `Instance.new("StarterPlayerScripts")`); `Terrain` tem `IsAbstract=true, Covered=false` (erra por um motivo DIFERENTE — nem chega a estar registrado, cai no ramo "`[LuauBench] ... not simulated yet`"). O relatório do coder generaliza os três sob "não instanciáveis via Services.new" — verdadeiro, mas por DUAS causas distintas; vale a pena essa distinção ficar registrada porque a correção futura (ver item 6) não é a mesma para os dois casos (Terrain nem tem comportamento simulado ainda; StarterPlayerScripts/StarterCharacterScripts têm).

Confirmei também que o motor JÁ cria os dois filhos de `StarterPlayer` sozinho, via `game:GetService("StarterPlayer")`:
```
StarterPlayer ja tem StarterPlayerScripts pre-criado pelo motor? true
  ClassName do pre-criado: StarterPlayerScripts
```
(rastreado até `src/services/behavior/StarterPlayer.luau:47-51`, que chama `Runtime.ClassRegistry.NewEngineInstance` dentro do `Initialize` do Service).

**Conclusão do item 5: achado do coder CONFIRMADO, não é engano — e a causa raiz é mais precisa do que "não instanciável", ver item 6.**

## 6. Decisão de não tocar `IsServiceRoot` — coerente para ESTA task, mas expõe um buraco arquitetural real e urgente

A decisão em si (não marcar `StarterPlayerScripts`/`StarterCharacterScripts`/`Terrain` como `IsServiceRoot`) está CORRETA do ponto de vista de fidelidade: nenhuma delas tem a tag `Service` no dump, `game:GetService("StarterPlayerScripts")` não existe no Roblox real, e o comentário em `TreePlanner.luau:944-956` documenta isso explicitamente. Não é um erro de revisão desta task.

**Mas** a combinação com `TreeMaterializer.luau` (mesmo território, arquivo vizinho, não tocado por esta task) tem só DOIS caminhos: `IsServiceRoot=true` → `game:GetService` (usa o singleton, que já vem com os filhos fixos do motor prontos) e `IsServiceRoot=false` → `Services.new` + `.Parent` (sempre cria uma Instance NOVA). Não existe um terceiro caminho para "filho fixo que o motor já pré-criou dentro do pai" — resultado prático, confirmado pelos runs reais acima: **todo nó do `.project.json` do usuário chamado `StarterPlayerScripts`/`StarterCharacterScripts` vira `materialize/invalid-class` e a subárvore inteira é descartada**, incluindo qualquer Script real que o usuário tenha colocado lá dentro (ex.: script de câmera/controles em `StarterPlayerScripts` — um dos locais MAIS comuns de projeto Roblox real).

Isso é mais urgente do que "próxima parede legítima e diferente" sugere: o motivo prático de desbloquear `TreePlanner` (rodar scripts reais de projetos reais) fica só PARCIALMENTE resolvido por esta task para qualquer projeto que tenha script dentro de `StarterPlayerScripts`/`StarterCharacterScripts` — o que é o padrão universal do `rojo init`. Os 3 projetos testados não têm script all´i dentro (por isso os cenários "passam" hoje), mas isso é sorte da amostra, não uma prova de que o caminho está livre.

**Recomendação, registrada para o `arquiteto` decidir (fora do escopo de aprovação desta task):** `TreeMaterializer` precisa de um terceiro caminho — "filho fixo do motor": ao encontrar (via alguma superfície pública equivalente a `FIXED_CHILD_CLASS_NAMES`, do lado de `services`/`runtime`, não hardcoded em `cli`) que o nó corresponde a um filho que o `Initialize` do pai já criou, ele deveria localizar a Instance JÁ EXISTENTE (`parent:FindFirstChild(name)`) e aplicar `Source`/`$properties`/recursão nela, em vez de tentar `Services.new`. Isso não é decisão de `cli` sozinho (depende de uma superfície nova de `services`, análoga a `IsServiceClass`, ex. `Services.IsEngineFixedChild`), por isso fica sinalizado para o board, não implementado aqui.

## 7. `--!strict` / zero `any`

`head -1` dos 5 arquivos tocados (`SyncRules.luau`, `TreePlanner.luau`, `SyncRules.spec.luau`, `TreePlanner.spec.luau`, `real-roblox-games-pipeline-smoke.scenario.luau`) — todos começam com `--!strict`. `grep '\bany\b'` só encontrou 1 ocorrência, dentro de um COMENTÁRIO em `TreePlanner.luau:322` explicando que um cast NÃO é um `any` disfarçado — zero `any` em código real.

`luau-lsp analyze --platform=standard` nos 5 arquivos: `EXIT=0`, zero diagnostics.

## 8. Regressão de precedência antiga

Confirmada dentro do item 1 — os 21/21 de `TreePlanner.spec.luau` incluem todos os testes de precedência pré-existentes (`class-name-conflict`, `service-name-mismatch`, `nested-project`, ciclo duplo/triplo, `meta-class-conflict`, `properties-and-attributes`, `unsupported-file`) e todos passaram.

## Achado incidental fora do escopo (não bloqueia, não é território `cli`)

Durante o run real de "Panic - CHESSS" (item 4), o erro final do script do usuário aparece assim:
```
error ServerScriptService.Server.Services.MatchmakingService:4: GetService: classe 'HttpService' não registrada em ClassRegistry (required by ServerScriptService.Server)
```
Mensagem interna em PORTUGUÊS de `Runtime.DataModel.GetService` vazando direto pro stderr do usuário final quando um SCRIPT (não o `TreeMaterializer`) chama `game:GetService` para uma classe não registrada em runtime — caminho diferente do que `TreeMaterializer`/`Services.new` já tratam (que produzem mensagens em inglês, família `[LuauBench] ... not simulated yet`). Não é parte do diff desta task nem do território `cli` (a mensagem crua vem de `runtime`) — sinalizando para `revisor-runtime`/`revisor-services` avaliarem, não bloqueia este veredito.

## Veredito

**APROVADO COM RESSALVAS.**

A correção do `TreePlanner`/`SyncRules` em si (o algoritmo de inferência de filhos fixos, a estrutura mutuamente exclusiva, a precedência, os testes, a regressão) está correta, completa e fielmente reproduzida por mim, com evidência própria em todos os pontos pedidos — nenhum achado GRAVE ou ALTO dentro do escopo desta task. A ressalva é a do item 6: o board precisa registrar com urgência uma tarefa de arquitetura para o terceiro caminho de materialização de "filho fixo do motor" em `TreeMaterializer`, porque sem isso o valor prático desta correção fica incompleto para o padrão mais comum de projeto Roblox real (scripts dentro de `StarterPlayerScripts`/`StarterCharacterScripts`). Isso não é motivo para reprovar task-cli-014 (fora do seu escopo declarado), mas deveria virar a PRÓXIMA task de prioridade máxima, não uma nota de rodapé.
