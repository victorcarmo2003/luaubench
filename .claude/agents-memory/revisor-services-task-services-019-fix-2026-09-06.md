# Revisão — task-services-019-fix (DataStoreKey em ListKeysAsync)

Revisor: `revisor-services` (read-only). Nenhum self-report do coder aceito sem reprodução própria
— todo item abaixo foi reproduzido de forma independente, com script próprio quando aplicável.

Nota de concorrência: `src/runtime/DataModel.luau`/`.spec.luau` apareciam modificados no `git status`
durante a revisão — confirmado (via `.claude/tasks.json`, task-runtime-038 `in-progress`) que é outro
agente rodando em paralelo, território diferente, sem overlap com esta tarefa. Não avaliado aqui.

## Metodologia

1. Lido `.claude/tasks.json` (task-services-019-fix) e o achado original
   (`.claude/agents-memory/revisor-services-task-services-019-2026-09-05.md`, achado MÉDIO).
2. Lido o diff completo dos 7 arquivos tocados + o 1 novo (`git diff` / leitura direta).
3. Rodados individualmente via `lune run`: `DataStore.spec.luau` (13/13),
   `generate-services.spec.luau` (20/20), `init.spec.luau` (30/30) — todos batem com o alegado.
4. Rodada a suíte COMPLETA de `src/services/**` — todos os 30 arquivos `.spec.luau`, um por um.
   Soma exata: 442 testes passando fora de `HttpService.spec.luau` + 20 de
   `tools/generate-services.spec.luau` = **462**, batendo exatamente com o "462/462" alegado.
5. `HttpService.spec.luau` falha com timeout de watchdog de rede (linha 141, "rede travada?").
   Confirmado como PRÉ-EXISTENTE: `git stash` só dos 7 arquivos tocados por esta tarefa (deixando
   `src/runtime/**` da task concorrente intocado), reproduzido o MESMO timeout na mesma linha antes
   da mudança. `git stash pop` restaurado, árvore de volta ao estado com a mudança.
6. Escrito um script de verificação PRÓPRIO (`__revisor_verify_datastorekey.luau`, copiado
   temporariamente para a raiz do repo, executado, apagado em seguida) que NÃO reusa
   `DataStore.spec.luau`: confirma que os itens de `ListKeysAsync`/`GetCurrentPage()` (a) não são
   strings cruas (`type(item) ~= "string"`), (b) têm `.ClassName == "DataStoreKey"`, (c) respondem
   `true` a `:IsA("DataStoreKey")` e `:IsA("Instance")` (prova que é Instance de verdade via API
   pública do runtime, não tabela solta fingindo ter `ClassName`), (d) `.KeyName` é string e bate
   com a chave escrita, (e) duas instâncias da mesma página são objetos DISTINTOS (não a mesma
   tabela reusada), (f) escrever em `.KeyName` por fora ERRA (ReadOnly, mesma disciplina de
   Instance) — 2/2 passou.
7. Segundo script próprio (`__revisor_verify_abstract.luau`, mesmo processo de copiar/rodar/apagar)
   confirmando que `DataStoreKey` é `NotCreatable` pela via pública
   (`Runtime.ClassRegistry.new("DataStoreKey")` erra citando a tag do dump) mas a via do motor
   (`NewEngineInstance`) funciona normalmente — 2/2 passou.
8. Lido `Full-API-Dump.json` pinado (`.cache/api-dump/28360dea.json`, mesmo commit do
   `tools/api-dump.lock.json`) diretamente via Python: `DataStoreKey` tem exatamente
   `Superclass=Instance`, tags `["NotCreatable", "NotReplicated"]`, único membro `KeyName`
   (`Primitive/string`, tags `["ReadOnly", "NotReplicated"]`, `Default =
   "__api_dump_class_not_creatable__"`) — bate exatamente com `generated/classes/DataStoreKey.luau`.
9. Lido `DataStoreKeyInfo.luau` (linha 88-92) e comparado com `buildKeyItems` em `DataStore.luau`:
   mesma fábrica, `Runtime.ClassRegistry.NewEngineInstance(...)` seguido de
   `Runtime.Instance.SetPropertyRaw(instance, "<Campo>", valor)` — nenhum segundo mecanismo.
10. `git diff --stat` do `Index.luau` (1 linha, só a entrada nova) e do `Manifest.luau` (1 linha,
    `Covered: false -> true` só para `DataStoreKey`) — confirma que a regeneração foi puramente
    aditiva, sem tocar mais nada.
11. Confirmado que `tools/generate-services.luau` (o algoritmo do gerador/fecho) NÃO foi tocado
    (`git diff --stat` vazio) — a correção é mesmo via seed manual em `coverage.luau`, como alegado,
    não uma mudança de heurística do fecho transitivo.
12. `luau-lsp analyze --platform=standard --settings=".luaurc"` nos 5 arquivos de código+spec novos
    (`coverage.luau`, `generate-services.spec.luau`, `DataStoreKey.luau`, `DataStore.luau`,
    `DataStore.spec.luau`): exit 0, zero diagnósticos. `init.spec.luau` isoladamente reporta 46
    linhas de erro de tooling (Unknown require/Unknown type/contagem de retorno) — confirmado via
    `git stash` que é EXATAMENTE o mesmo conjunto (mesma contagem, 46 linhas) antes da mudança:
    falso-positivo pré-existente de analisar `init.*` fora do grafo, não introduzido por esta task.
13. `grep -n '\bany\b'` nos 8 arquivos tocados: nenhuma ocorrência de tipo `any` real — só menções
    em comentário ("nunca `any`"). Todos com `--!strict` na primeira linha.
14. `git diff --stat` da árvore inteira: só `src/services/**` + `tools/**` (desta tarefa) e
    `src/runtime/DataModel.luau`/`.spec.luau` (task-runtime-038, concorrente, não desta tarefa).
    Nada em `src/cli/`, nada em `src/valuetypes/`.

## Resultados por item pedido

1. **Números batem** — `DataStore.spec` 13/13, `generate-services.spec` 20/20, `init.spec` 30/30.
2. **Suíte completa sem regressão** — 462/462 (442 dos 29 arquivos de `src/services/**` restantes +
   20 de `tools/generate-services.spec.luau`), `HttpService.spec.luau` falha por timeout de rede
   AMBIENTAL, confirmado pré-existente via `git stash` (mesma falha, mesma linha, antes da mudança).
3. **`ListKeysAsync` devolve `DataStoreKey` REAIS** — confirmado por script próprio: `ClassName`
   correto, `:IsA("DataStoreKey")`/`:IsA("Instance")` verdadeiros (via runtime real, não tabela
   solta), instâncias distintas por item, `.KeyName` correto por chave, mutação por fora ERRA
   (ReadOnly). Nenhuma string crua sobrevivendo em nenhum item.
4. **Schema do `DataStoreKey.luau` gerado bate com o dump** — confirmado por leitura direta do
   `Full-API-Dump.json` pinado: `Superclass=Instance`, único membro `KeyName` (ReadOnly, Primitive
   string), `NotCreatable` → `IsAbstract=true`. Tipo público `KeyName: unknown` (em vez de `string`)
   é consistente com o comportamento JÁ EXISTENTE do gerador para `Default` sentinela
   (`isSentinelDefault` → `representable=false` → tipo cai para `unknown` mesmo em Primitive já
   simulado) — confirmado que `DataStoreKeyInfo.CreatedTime` já sofre a MESMA disciplina; não é uma
   aproximação nova nem regressão desta tarefa.
5. **Fábrica é a MESMA de `DataStoreKeyInfo.luau`** — confirmado lendo os dois arquivos lado a lado:
   `Runtime.ClassRegistry.NewEngineInstance(className)` + `Runtime.Instance.SetPropertyRaw(instance,
   campo, valor)`, nenhum segundo mecanismo de criar Instance.
6. **`CLOSED_NEVER_LEGITIMATE` em `init.spec.luau` correta** — `DataStoreKey` é `NotCreatable`, não é
   Service nem filho fixo do motor, só nasce via `NewEngineInstance` dentro de `buildKeyItems`; sem
   a entrada, o teste de coerência "toda classe `IsEngineOnlyClass` é Service/filho fixo/lista
   fechada" falharia de propósito (é o alarme que o teste existe para pegar) — o teste de coerência
   está entre os 30/30 que passaram.
7. **`--!strict`/zero `any` real** — confirmado nos 8 arquivos tocados/gerados.
8. **Território limpo** — só `src/services/**` + `tools/**`; nada em `src/cli/`/`src/valuetypes/`;
   `src/runtime/DataModel.luau`/`.spec.luau` pertence à task-runtime-038 concorrente (confirmado
   pelo board), não a esta tarefa.

## Achados

Nenhum GRAVE/ALTO/MÉDIO/BAIXO. Toda alegação do coder foi reproduzida de forma independente e bateu
exatamente, incluindo o número exato de testes, o comportamento de `ReadOnly`, a identidade da
fábrica reusada, e a origem pré-existente (não desta tarefa) tanto da falha de `HttpService.spec`
quanto dos falso-positivos de lint em `init.spec.luau`.

## Veredito

**APROVADO**
