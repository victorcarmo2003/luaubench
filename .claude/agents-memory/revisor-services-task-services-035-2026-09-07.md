# Revisão — task-services-035 (Gerador: toda Property entra no schema; Security/Tags decidem ScriptVisible)

**Data:** 2026-09-07
**Revisor:** revisor-services (read-only)
**Método:** nada do self-report do coder foi aceito por afirmação — cada alegação foi reproduzida de novo: leitura direta do código-fonte, `git diff` isolado, recontagem independente por script (`grep`), execução real de todas as suítes citadas, regeneração dupla com hash, e `luau-lsp analyze` (validado com um arquivo quebrado de propósito, pra confirmar que a ferramenta realmente pega erro).

## Achados

Nenhum achado GRAVE/ALTO. Uma ressalva MÉDIA/BAIXA (ver Veredito).

Verificações, todas reproduzidas por mim:

1. **`classifySchemaMember`** (`tools/generate-services.luau:440-541`) — lido por completo e comparado via `git diff` isolado na função. Bate exatamente com a alegação: ramo `Property` retorna `included=true` sempre; os 4 gatilhos (`NotScriptable`, `Security.Read` elevado, tag `WriteOnly`, `required_read ∩ reserved`) só afetam `scriptVisible`/`scriptInvisibleReason`; passos 4-8 (`readOnly`) rodam idênticos para `scriptVisible=true`. Ramo `Event`/`Callback`: os mesmos passos continuam retornando `included=false` — nenhuma linha de comportamento mudou aí. `classifyMethodMember` (linhas 551+) não aparece em nenhum hunk do diff — confirmado intocada.

2. **`Lighting.luau`** lido por inteiro: `Technology` = `{ Kind = "Property", Default = nil, ReadOnly = false, ValueType = "Technology", ValueCategory = "Enum", ScriptVisible = false }` (linha 93). `ExtendLightRangeTo120` igual (linha 81). Nenhuma das duas aparece no bloco `export type Lighting` (linhas 36-65) — confirmado por leitura direta, não grep solto.

3. **`Workspace.luau`**: `FilteringEnabled = { ..., ReadOnly = true, ..., ScriptVisible = true }` (linha 65) — inalterado, como alegado (só `Security.Write` é elevado no dump).

4. **Recontagem independente** (`grep -o 'ScriptVisible = false' src/services/generated/classes/*.luau`, script meu, não do coder): Workspace 48, StarterPlayer 24, Instance 15, Model 11, LuaSourceContainer 7, WorldRoot 7, Players 6, StarterGui 6, SoundService 4, ModuleScript 3, RunService 3, DataStoreService 2, Lighting 2, PVInstance 2, Folder 1, Script 1, ServerScriptService 1 — **total 143**, bate byte a byte com o alegado. Cross-check contra a saída real do gerador (`lune run tools/generate-services`, seção "Property no schema porém INVISÍVEIS ao script") — idêntico.

5. **Nenhuma classe fora das 17** tem entrada `ScriptVisible = false` — a mesma recontagem rodou sobre os 45 arquivos de `src/services/generated/classes/*.luau` (não só os 28 que aparecem no `git diff`), zero ocorrência fora da lista. As 17 classes "modificadas mas sem `ScriptVisible=false` nova" (ex.: `DataStore`, `GlobalDataStore`, `ReplicatedStorage`, `ServerStorage`, `LocalScript`, `BasePlayerGui`, `MessagingService`, `PhysicsService`) têm `Schema = {}` vazio — confirmado por leitura direta de `ReplicatedStorage.luau`, nada para o campo `ScriptVisible` afetar.

6. **Event/Callback**: 24 `Kind = "Event"` no fecho, 0 `Callback`. `git diff` isolado mostra 24 linhas `-` e 24 linhas `+`, nome a nome idênticas (só ganharam `, ScriptVisible = true` no fim) — nenhum Event novo, nenhum removido. `MethodNames`: `git diff` sem nenhuma linha de conteúdo `+`/`-` dentro desses blocos, em nenhum dos 30 arquivos.

7. **Suítes rodadas por mim, do zero:**
   - `lune run tools/generate-services.spec.luau` → **26/26 passaram**.
   - Todos os 31 `*.spec.luau` sob `src/services/**` rodados individualmente → 30 passaram; `src/services/behavior/HttpService.spec.luau` falhou (timeout de 10s no watchdog, teste que depende de DNS real contra um domínio `.invalid`, linha 625-639, não relacionado a `Script.Source`/`ModuleScript.Source` nem a `classifySchemaMember` — o arquivo `src/services/behavior/HttpService.luau` que esse spec testa não está no diff da tarefa). Reproduzido 2x consecutivas, falha as duas vezes neste ambiente (rede/DNS bloqueados na sandbox, não flakiness aleatória) — mas de qualquer forma comprovadamente fora do território tocado.
   - Nota: contei 31 arquivos `*.spec.luau` sob `src/services/`, não 29 como o relatório do coder diz — divergência pequena de contagem, sem efeito no resultado (todos rodaram, resultado bate).
   - `src/cli/TreeMaterializer.spec.luau` → 28/28, `ModuleLoader.spec.luau` → 12/12, `ScriptRunner.spec.luau` → 7/7, `init.spec.luau` → 7/7, `RunCommand.spec.luau` → 31/31 — todos batem com o alegado.

8. **Determinismo**: rodei o gerador 2x adicionais (3 estados no total: árvore de trabalho + 2 regenerações) e comparei sha256 de todo `src/services/generated/**` — idêntico byte a byte nas 3 execuções.

9. **`--!strict`/`any`**: confirmado nos dois arquivos de `tools/`. `luau-lsp analyze --platform=standard` limpo nos dois (zero diagnóstico) — validei que a ferramenta de fato pega erro real (rodei contra um arquivo quebrado de propósito e ela reportou `TypeError` corretamente), então o resultado limpo é significativo, não um no-op silencioso.

10. **Território**: `git status --porcelain` (árvore inteira) só mostra os 30 arquivos gerados + `tools/generate-services.luau` + `tools/generate-services.spec.luau` — 32 entradas, nada fora disso (fora o `.md` de memória do próprio coder, não código).

11. **`Default = nil` sempre para entrada invisível — avaliação**: a decisão NÃO foi inventada pelo coder — está registrada explicitamente em `arquiteto-rojo-properties-2026-09-07.md`, seção D2 ("`Default = nil` sempre — não chamar `computeDefault`") e D3 (`Instance.SetClassSchema` "não semeia `Default` nem `Signal` para entrada com `ScriptVisible == false`"). Confirmei em `src/runtime/Instance.luau:1127-1142` que isso é literal: para `descriptor.ScriptVisible == false` o loop de semeadura faz `continue` — `descriptor.Default` nunca é lido em runtime para essas entradas. Ou seja, o `nil` no schema gerado é dado morto por desenho, não um bug latente — coerente e seguro hoje.
    - **Ressalva (BAIXA)**: o memo do arquiteto diz "registrado no cabeçalho do arquivo gerado como decisão deliberada". Isso não está no arquivo gerado — só no comentário de `tools/generate-services.luau` (fonte única). O comentário do `export type` em cada classe gerada (que o coder cita como substituto) fala só de `unknown` para ValueType não representável, nunca menciona `Default = nil`. Um leitor que abra só `Lighting.luau` (sem ir ler o gerador) pode achar que `Technology`/`ExtendLightRangeTo120` não têm default real no Roblox — não é o caso (`Technology` tem default real de Enum). Risco baixo hoje (nada em `runtime`/`services` lê esse `Default` para entrada invisível, confirmado no item acima), mas é um desvio pequeno do que o arquiteto pediu literalmente, sem ter sido sinalizado como desvio no relatório do coder.
    - Segunda consequência da mesma decisão, também coerente com DV-1 (declarada no memo do arquiteto): uma instância de `Lighting` criada via `Instance.new` (sem hidratação por `$properties`) nunca terá um valor real para `Technology` via `GetPropertyRaw` — fica `nil` até alguém escrever com `SetPropertyRaw`. Documentado e aceito no desenho (nenhum comportamento simulado reage a isso hoje), só registro para quem for construir comportamento de `Lighting` mais pra frente não presumir default populado.

## Veredito

## Veredito
APROVADO COM RESSALVAS

Território limpo, `classifySchemaMember`/`classifyMethodMember` batem exatamente com o desenho e com o `git diff` isolado, os 143 casos load-only recontados de forma independente batem número a número (inclusive por classe), Event/Callback comprovadamente inalterado (24=24, nome a nome), `export type` nunca ganhou campo invisível, todas as suítes citadas rodam limpo (exceto um teste de rede pré-existente e fora do território, reproduzido e confirmado não relacionado), gerador determinístico, `--!strict`/zero `any` confirmados. A única ressalva é de rastreabilidade/documentação (item 11): a nota "decisão deliberada" do `Default = nil` para propriedades load-only não chegou ao cabeçalho dos arquivos gerados individuais como o arquiteto pediu — vive só no gerador. Não bloqueia a tarefa (nenhum código lê esse `Default` para entrada invisível), mas vale um ajuste de uma linha de comentário em `generateClassFile` numa próxima passada, ou uma decisão explícita do usuário de que "fonte única no gerador" é aceitável no lugar do cabeçalho por arquivo.
