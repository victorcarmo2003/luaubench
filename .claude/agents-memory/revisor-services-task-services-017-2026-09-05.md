# Revisão — task-services-017 (Value/Store/coverage/geração DataStore)

Read-only. Nenhum self-report aceito sem reprodução — todo número abaixo foi obtido rodando os
comandos eu mesmo, não copiado do relatório do coder.

## Veredito

**APROVADO COM RESSALVAS**

Nenhum achado GRAVE. Dois achados MÉDIO (nenhum bloqueante, ambos de baixo custo de correção) e um
BAIXO. Todo o núcleo funcional (serializabilidade, deep copy, versionamento, tombstone, limites de
tamanho/nome, regeneração determinística, cobertura declarada) foi reproduzido e bate com o que o
coder alega.

## O que foi verificado e reproduzido

1. **4 suítes-alvo rodadas por mim, números exatos confirmados**: `Value.spec.luau` 28/28,
   `Store.spec.luau` 24/24, `init.spec.luau` 24/24, `generate-services.spec.luau` 11/11.
2. **NaN/inf/-inf aceitos** — confirmado tanto pela suíte do coder quanto por um script
   independente meu (`Value.CheckSerializable`/`AssertSerializable`/`Validate` para `0/0`,
   `math.huge`, `-math.huge`, isolados e aninhados). Nenhum resquício de `Kind = "NaN"`/`"Infinite"`
   no código (grep confirmou).
3. **Recusas confirmadas independentemente**: chave mista (`{[1]=1,x=2}`), função, thread,
   userdata (testei com `buffer.create(4)` — ver achado BAIXO abaixo sobre a categorização),
   referência cíclica (`t.self=t`) — todas corretamente rejeitadas com o `Kind` esperado.
4. **Limites exatos testados por mim**: nome/chave/scope 50 chars passa, 51 falha (bate com o
   spec). Tamanho do valor: escrevi um script que acha por busca binária o `n` cujo
   `EstimateByteSize` é EXATAMENTE 4194304 bytes e confirmei que `AssertByteSize` aceita esse valor
   e rejeita `4194304+1`. **O spec do coder não tem um teste de fronteira exata (só testa
   "4194304+100"), mas o comportamento real na fronteira está correto** — reportado como nota, não
   como bug.
5. **Deep copy verificado independentemente**: `Set` então mutar o original não afeta o valor
   guardado (nível raso e aninhado); `Get` então mutar o retorno não afeta uma leitura seguinte.
6. **Tombstone verificado independentemente**: `Set→Remove→Get` devolve `(nil,nil)`;
   `GetVersion` da versão anterior ao `Remove` continua legível e não vem marcada `Tombstone`.
7. **Versionamento verificado independentemente**: `Set`s sucessivos geram `Version` distintas e
   ordenáveis lexicograficamente (`v1 < v2 < v3`).
8. **Regeração determinística**: rodei `lune run tools/generate-services` eu mesmo depois do
   `git status` inicial e o diff ficou idêntico (nenhuma mudança adicional) — confirma que
   `generated/classes/*.luau` das 16 classes não foi editado à mão.
9. **coverage.luau**: as 16 classes acrescentadas batem exatamente com L2.1.7 do desenho do
   arquiteto.
10. **11 nomes novos em `CLOSED_NEVER_LEGITIMATE`**: conferi TODOS os 11
    (`GlobalDataStore`/`DataStore`/`OrderedDataStore`/`DataStoreKeyInfo`/`Pages`/`DataStorePages`/
    `DataStoreKeyPages`/`DataStoreListingPages`/`DataStoreVersionPages`/
    `DataStoreObjectVersionInfo`/`DataStoreInfo`) direto contra `.cache/api-dump/...json`: todos
    têm `NotCreatable`, nenhum tem `Service`. As 4 classes de opções
    (`DataStoreSetOptions`/`DataStoreOptions`/`DataStoreGetOptions`/`DataStoreIncrementOptions`)
    corretamente ficaram DE FORA da lista — não têm `NotCreatable` no dump.
11. **`@lune/fs`**: grep por `require("@lune/fs")` em `src/services/` não encontrou nada. A única
    ocorrência da string `@lune/fs` é um comentário em `Store.luau` citando a própria regra.
12. **Território limpo**: `git status`/`git diff --stat` só toca `src/services/datastore/**`,
    `src/services/generated/**`, `src/services/init.spec.luau`, `tools/coverage.luau`,
    `tools/generate-services.spec.luau`. Nada em `runtime/`, `cli/`, `valuetypes/`, `behavior/`
    (confirmado — task-services-017 explicitamente não cria `behavior/*.luau`, e não criou).
13. **Suíte completa**: rodei as 12 demais suítes de `services` (`AsyncCall`, `ClassBuilder`,
    `Context`, `EngineFixedChildren`, `InstanceState`, `Integration`, `RejectingSignal`,
    `behavior/Index`, `behavior/Lighting`, `behavior/Players`, `behavior/RunService`,
    `behavior/StarterPlayer`) — somam 93 testes, todos passando. `93 + 28 + 24 + 24 + 11 = 180`,
    bate com o "180 testes, zero falha" alegado. **Nota trivial**: o relatório do coder diz "demais
    15 suítes inalteradas" mas são 12 arquivos, não 15 — imprecisão de contagem no self-report, sem
    efeito real (o total de 180 testes está certo).

## Achados

### [MÉDIO] src/services/datastore/Value.spec.luau (6 ocorrências) e Store.spec.luau (12 ocorrências)
**Problema**: uso de `:: any` para acessar campos de um valor `unknown` retornado por
`Get`/`Update`/`Remove`/`DeepCopy`, violando a regra 01 ("Sem `any`. Tipo genuinamente desconhecido
é `unknown`, estreitado antes de usar") — `--!strict`, "sem exceção, inclusive script de teste".
**Cenário de falha**: não é um bug funcional (specs passam), mas é uma inconsistência de padrão —
o resto do projeto já resolve exatamente este problema (narrowing de `unknown` vindo de um
`require`/retorno genérico em teste) com um cast para um tipo estrutural concreto, não `any`. Ver
`src/cli/ModuleLoader.spec.luau:139`: `local resultTable = (first :: unknown) :: { marker: string }`.
Um grep em todo `src/` e `tools/` mostra que estes são os ÚNICOS DOIS arquivos do projeto inteiro
que usam `:: any` — o resto do código sempre estreita para um tipo nomeado.
**Correção**: trocar `(value :: any).Coins` por `(value :: unknown) :: { Coins: number, ... }` (ou
declarar um tipo de fixture local, ex. `type TestPayload = { Coins: number, Inventory: {string}? }`),
seguindo o padrão já estabelecido em `ModuleLoader.spec.luau`. Mudança mecânica, não muda cobertura
de teste nenhuma.

### [MÉDIO] src/services/datastore/Store.luau:48-53 (comentário de cabeçalho) e :155-157 (`nowMillis`)
**Problema**: a divergência declarada ("CreatedTime/UpdatedTime perdem granularidade de
milissegundo porque `os.time()` do Lune só dá segundos") trata isso como uma limitação inerente do
Lune, mas **não é** — confirmei ao vivo que `require("@lune/datetime")` expõe
`DateTime.now().unixTimestampMillis`, um inteiro com precisão de milissegundo real desde a época
(testei: `1788651164318`). O módulo `@lune/datetime` já é fornecido pelo Lune (não introduz
dependência nova, não fere a regra 00/03 "nenhum binário externo além do que o Lune já provê") e
não é `@lune/fs`/`net`/`process` (não conflita com a regra "services nunca chama @lune/fs" nem com
o sandbox de script arbitrário, já que isto é estado interno do host, nunca exposto ao script do
usuário).
**Cenário de falha**: dois `Set`/`Update` na MESMA chave dentro do mesmo segundo relógio produzem
`VersionInfo.UpdatedTime` idêntico (só `Version` os distingue). Uma tarefa futura de
`behavior/DataStoreKeyInfo.luau`/`ProfileStore` que compare `UpdatedTime` entre duas leituras
rápidas (padrão comum: medir latência, ou invalidar cache local por "mudou desde X ms") veria
timestamps empatados onde o Roblox real teria valores distintos.
**Correção**: trocar `os.time() * 1000` por `require("@lune/datetime").now().unixTimestampMillis`
em `nowMillis()`. Se por algum motivo o time (`@lune/datetime`) não estiver disponível no
ambiente de build alvo, ao menos reformular o comentário para não descrever isto como limite do
Lune — é uma escolha de implementação, não uma restrição da plataforma. Não bloqueia a tarefa (é
documentado, não silencioso — regra 00 tecnicamente satisfeita), mas a premissa que justifica a
divergência está incompleta.

### [BAIXO] src/services/datastore/Value.luau:233-238
**Problema**: o comentário afirma "`type()` do Luau só devolve 8 nomes... este ramo é inalcançável
na prática" antes do `return { Kind = "UnsupportedType", ... }` de fallback. Isso é factualmente
incorreto para o Luau do Lune: confirmei ao vivo que `type(buffer.create(4)) == "buffer"` e
`type(vector.create(1,2,3)) == "vector"` — dois nomes adicionais além dos 8 listados. O ramo
"inalcançável" É alcançado por qualquer script que passe um `buffer`/`vector` de topo ou aninhado
para `SetAsync`/`UpdateAsync` (confirmei: `CheckSerializable(buffer.create(4))` devolve
`Kind = "UnsupportedType", DetailType = "buffer"`, não erro nem aceitação silenciosa).
**Cenário de falha**: nenhum funcionalmente — o fallback já rejeita corretamente (fail-safe, não
fail-open). É só a documentação que engana um mantenedor futuro que confie na frase "inalcançável"
e pule testar esse caminho. Não sei (e não afirmo) se o Roblox real aceita `buffer` num DataStore
hoje — está fora do escopo desta tarefa e do dump (não é uma classe/propriedade simulada); só
registro que a alegação "inalcançável" é falsa e que a fidelidade de `buffer`/`vector` em
DataStore é uma pergunta em aberto para o `pesquisador`, não para eu decidir.
**Correção**: corrigir o comentário (Luau moderno tem pelo menos 10 nomes de `type()`, incluindo
`buffer` e `vector`) e, opcionalmente, abrir um item de pesquisa sobre se `buffer`/`vector` são de
fato rejeitados pelo Roblox real hoje.

## Não verificado / fora do escopo desta revisão

- Não avaliei `behavior/DataStoreService.luau` etc. — corretamente NÃO fazem parte desta tarefa
  (ficam para task-services-018, que ainda está em `todo` e depende desta).
- Não critiquei a exatidão da string de erro de serializabilidade (o próprio módulo já documenta
  como aproximação de boa-fé NÃO CONFIRMADA, com a pesquisa já anexada) — não é um achado novo.
