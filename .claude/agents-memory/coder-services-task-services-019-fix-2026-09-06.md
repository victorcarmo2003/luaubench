# task-services-019-fix — DataStoreKey em ListKeysAsync

Achado MÉDIO da revisão de task-services-019 (`.claude/agents-memory/revisor-services-task-services-019-2026-09-05.md`):
`DataStore:ListKeysAsync`/`DataStoreKeyPages:GetCurrentPage()` devolviam strings cruas em vez de
instâncias `DataStoreKey` reais, porque `DataStoreKey` existe no dump mas nunca era descoberta pelo
fecho transitivo automático do gerador (o dump não parametriza item de `Array`).

## O que foi feito

1. **`tools/coverage.luau`** — `DataStoreKey` acrescentada manualmente à lista (Superclass "Instance"
   direto no dump, não puxa nada novo). Comentário extenso explicando por que essa entrada é
   diferente de todas as outras (nunca seria descoberta pelo fecho automático — nada no fecho a
   referencia via `Superclass`, só via `ReturnType` de método, que o gerador não segue).
2. **Regeneração** via `lune run tools/generate-services` — `src/services/generated/classes/DataStoreKey.luau`
   criado (schema com só `KeyName`, `ReadOnly=true`, `ValueType="string"/Primitive`; tipo público
   `unknown` para `KeyName` porque o `Default` no dump é o sentinela `__api_dump_class_not_creatable__`,
   mesma disciplina de `DataStoreKeyInfo.CreatedTime`/`.Version`). `Index.luau`/`Manifest.luau`
   atualizados automaticamente (só a entrada de `DataStoreKey`, nada mais mudou — confirmado por diff).
3. **`src/services/behavior/DataStore.luau`** — `buildKeyItems` agora constrói
   `Runtime.ClassRegistry.NewEngineInstance("DataStoreKey")` + `Runtime.Instance.SetPropertyRaw(_, "KeyName", entry.Key)`
   para cada chave, em vez de devolver a string crua — mesma fábrica que `DataStoreKeyInfo.luau`/
   `DataStore.luau` (`DataStoreObjectVersionInfo`) já usam. Cabeçalho e doc do método atualizados
   (a seção "DIVERGÊNCIA DECLARADA" virou "RESOLVIDO em task-services-019-fix").
4. **Specs atualizados**:
   - `src/services/behavior/DataStore.spec.luau`: os 3 testes de `ListKeysAsync` que tratavam item
     como string agora verificam `item.ClassName == "DataStoreKey"` e leem `.KeyName`.
   - `tools/generate-services.spec.luau`: fecho passou de 44 para 45 classes (lista `expected`
     atualizada, comentários de cabeçalho atualizados); teste novo dedicado a `DataStoreKey`
     (schema mínimo, `ReadOnly`, `Primitive string`, `IsAbstract`, zero `MethodNames`).
   - `src/services/init.spec.luau`: `CLOSED_NEVER_LEGITIMATE` (teste de coerência
     `IsEngineOnlyClass`) ganhou a entrada `DataStoreKey = true` — sem isso o teste de coerência
     "toda classe IsEngineOnlyClass é Service/filho fixo/lista fechada" falha de propósito (é
     exatamente o alarme que esse teste existe para pegar). Confirmado rodando ANTES do fix: falha
     com `[ALARME] "DataStoreKey" é IsEngineOnlyClass mas não é Service...`; depois do fix: passa.

## Superfície coberta / não coberta

- `DataStoreKey.KeyName` — coberto (leitura via `.KeyName`, `ReadOnly`).
- `DataStoreKey` não tem métodos no dump (`MethodNames = {}`) — nada ficou de fora.

## Fidelidade

- Tipo de `KeyName` no arquivo gerado é `unknown` em vez de `string` porque o `Default` do dump é
  sentinela `NotCreatable` (não representável) — mesma regra que já se aplica a `DataStoreKeyInfo`,
  não uma nova aproximação.
- `DataStoreKey` continua **entrada manual** em `coverage.luau`, não uma mudança no algoritmo do
  fecho transitivo do gerador (fora do escopo desta tarefa — o comentário em `coverage.luau`
  documenta isso para a próxima pessoa que mexer ali).

## Testes

Rodei a suíte inteira de `src/services/**` (30 arquivos `.spec.luau`) + `tools/generate-services.spec.luau`:

- **462/462 testes passaram** (soma de todos os arquivos, incluindo os specs novos/ajustados).
- `src/services/behavior/HttpService.spec.luau` **falhou** com timeout de watchdog de rede
  ("rede travada?") — **confirmado como falha PRÉ-EXISTENTE, não relacionada a esta task**: rodei o
  mesmo spec com `git stash` (árvore limpa, antes de qualquer mudança minha) e o mesmo teste falha
  da mesma forma (ambiente sem rede/sandbox). `DataStoreKey`/`DataStore.luau` não tocam
  `HttpService` em nada.
- `luau-lsp analyze --platform=standard --settings=".luaurc"` limpo (exit 0, zero diagnósticos) em:
  `tools/coverage.luau`, `tools/generate-services.luau`, `tools/generate-services.spec.luau`,
  `src/services/generated/classes/DataStoreKey.luau`, `src/services/behavior/DataStore.luau`,
  `src/services/behavior/DataStore.spec.luau`.
- `src/services/init.spec.luau` analisado isoladamente reporta os mesmos "Unknown require"/"Unknown
  type" de sempre — confirmado que é o falso-positivo de tooling já documentado (arquivo `init.*`
  analisado fora do grafo) rodando a MESMA análise em `git stash` (antes das minhas mudanças): conjunto
  idêntico de erros pré-existentes, nenhum novo introduzido pela minha edição (só 6 linhas de dado
  puro em `CLOSED_NEVER_LEGITIMATE`).
- `--!strict` presente, zero `any` em todos os arquivos tocados/gerados.

## Observação (fora do meu território)

Durante a sessão, `src/runtime/DataModel.luau` apareceu modificado no `git status` (29 linhas
adicionadas) — **não fui eu**: é `task-runtime-038`, rodando em paralelo por outro agente na mesma
árvore de trabalho (confirmado pelo board `.claude/tasks.json`, que já mostrava essa task
`in-progress` antes de eu começar). Não toquei nesse arquivo.
