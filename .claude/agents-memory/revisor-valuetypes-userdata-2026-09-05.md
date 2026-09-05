# Revisão — task-valuetypes-002 (Userdata.luau + Catalog.luau)

Data: 2026-09-05. Revisor: `revisor-valuetypes`. Read-only, nada editado.

Escopo revisado: `src/valuetypes/Userdata.luau`, `src/valuetypes/Catalog.luau`,
`src/valuetypes/Userdata.spec.luau`, `src/valuetypes/Catalog.spec.luau`. Nenhum self-report do
coder foi aceito sem reprodução — todo item abaixo foi rodado por mim, com evidência.

## O que rodei

1. `lune --version` → `0.10.5`; `luau-lsp --version` → `1.69.0`. Ambos disponíveis.
2. `lune run src/valuetypes/Userdata.spec.luau` → **33/33 passaram** (bate com o alegado).
3. `lune run src/valuetypes/Catalog.spec.luau` → **12/12 passaram** (bate com o alegado).
4. `lune run src/valuetypes/Float32.spec.luau` → **10/10 passaram**, sem regressão.
5. `luau-lsp analyze --platform=standard --settings=.luaurc` nos 4 arquivos → só 2 diagnósticos,
   ambos `Unknown global 'collectgarbage'` em `Userdata.spec.luau:340,344` (gap real de banco de
   tipos — `--platform=standard` espelha o Roblox, que não expõe `collectgarbage`; o global é real
   no Lune). Bate exatamente com o alegado, nada mais.
6. `grep -n "\bany\b"` nos 4 arquivos: zero ocorrências em `Userdata.luau`/`Catalog.luau`; nas
   specs, só dentro de comentários que explicam a ausência de `any` (nunca uso real). `--!strict`
   confirmado no topo dos 4 arquivos.
7. `grep -rn "newproxy" src/valuetypes/`: só `Userdata.luau:304` chama `newproxy(true)` dentro de
   uma fábrica (`Userdata.Define`'s factory). As outras ocorrências (`Userdata.spec.luau:389,390,572`)
   são `newproxy` cru usado só para simular "userdata alheio" num teste — não é uma segunda
   fábrica, é o cenário de teste exigido pelo próprio acceptance (comparar contra userdata de fora
   do módulo). **Fábrica única confirmada.**
8. `grep -rn "valuetypes" src/runtime/`: **vazio**. Grafo acíclico intacto.
9. `grep -n "The metatable is locked" -r src/runtime/`: confirmado em
   `runtime/Instance.luau:877`, string idêntica à usada em `Userdata.luau:131`.
10. `git status --short`: só `src/valuetypes/{Userdata,Catalog}.luau` e
    `{Userdata,Catalog}.spec.luau` novos (mais `.claude/tasks.json`, alterado pelo usuário ao mover
    a task pra `review`, não pelo coder). Nenhum arquivo fora do território tocado, incluindo
    `tools/generate-services.luau` (intocado).

## Teste próprio das 4 invariantes (Descriptor independente do coder)

Escrevi um `Descriptor` próprio (`RevPair`/`RevOther`, nada reaproveitado do `Userdata.spec.luau`)
e rodei via `lune run` (script temporário, removido depois — repo confirmado limpo com `git status`
ao final). Resultado: **todos os checks passaram**.

- `type(v) == "userdata"` — OK.
- `getmetatable(v)` devolve a string travada (`"The metatable is locked"`), nunca a metatable real — OK.
- `setmetatable(v, {})` erra — OK.
- `pairs(v)` erra — OK.
- **`rawset(v, "A", 999)` e `rawget(v, "A")`** (o vetor pedido explicitamente, que já quebrou
  `Instance` antes de `newproxy(true)`): **ambos erram nativamente** (`invalid argument #1 to
  'rawset'/'rawget' (table expected, got userdata)`) — o vetor está fechado, `newproxy(true)`
  não expõe slots de tabela pra `rawset`/`rawget` contornarem `__index`/`__newindex`.
- `__newindex` sempre erra, valor não muda após a tentativa — OK.
- `__eq`: mesmo tipo/mesmo valor → true; mesmo tipo/valor diferente → false; tipo NOSSO diferente
  (`RevOther`) → `false` sem erro; `newproxy(true)` alheio → `false` sem erro; `newproxy(false)`
  alheio → `false` sem erro; comparação com `5`/`{}`/`"x"` solto → `false` sem erro em nenhum caso.
- Leak: **4 execuções independentes** do meu próprio teste (100k valores soltos, side-table real
  do módulo, sem reusar o teste do coder) deram diff de **2151 / 2447 / 2586 / 2462 KB** — bem
  dentro da faixa que o coder mediu (~2258 KB) e folgado sob o limiar de 5000 KB usado no spec.
  Nenhuma tendência de crescimento entre rodadas (GC incremental do Lune realmente coleta a
  side-table fraca).
- Tentativas de quebrar a fábrica: `Define` com `TypeName` duplicado (`"RevPair"` de novo) erra;
  `TypeName` vazio erra; `Methods` não congelada erra; `Equals` que sempre lança propaga o erro
  (não é engolido/mascarado por `__eq`); `RevPair + RevOther` e `RevOther + RevPair` (despacho
  cruzado entre DOIS `Define`s diferentes, um só com `Add`) erram coerentemente nos dois sentidos,
  nunca somam campos incompatíveis; `Unwrap(RevOther, "RevPair")` erra citando o tipo real;
  `TypeNameOf` em número/tabela/`newproxy` alheio devolve `nil` em todos os casos.

**Conclusão da fábrica: nenhuma fissura encontrada.** As quatro invariantes seguram sob ataque
direto, inclusive o vetor `rawset`/`rawget` que é historicamente o mais perigoso.

## Verificação dos nomes do Catalog (contra doc oficial Roblox, não memória)

Busquei `create.roblox.com/docs/reference/engine/datatypes/*` para confirmar/reprovar
`HasGlobalConstructor`:

| Nome | Grupo | Catalog diz | Doc oficial confirma |
|---|---|---|---|
| `RaycastResult` | 14 novos, sem construtor | `false` | **Correto** — só propriedades documentadas, nenhum construtor; só é devolvido por `WorldRoot:Raycast(...)`. |
| `Secret` | 14 novos, sem construtor | `false` | **Correto** — só `AddPrefix`/`AddSuffix`; só chega via `HttpService:GetSecret(...)`. |
| `SharedTable` | 14 novos, sem construtor | `false` | **ERRADO** — a doc oficial documenta `SharedTable.new()` e `SharedTable.new(t: table)`, ambos chamáveis por um script comum. |
| `Content` | 14 novos, sem construtor | `false` | **ERRADO** — a doc oficial documenta `Content.fromUri(uri)`, `Content.fromAssetId(id)`, `Content.fromObject(obj)` e a constante `Content.none`, todos chamáveis por um script comum. |
| `FloatCurveKey` | 14 novos, com construtor | `true` | Correto — `FloatCurveKey.new(time, value, Interpolation)` confirmado. |
| `Path2DControlPoint` | 14 novos, com construtor | `true` | Correto — 3 overloads de `.new(...)` confirmados. |

### Achado ALTO — `SharedTable` e `Content` classificados incorretamente como `HasGlobalConstructor = false`

`src/valuetypes/Catalog.luau:130-133` (entradas) e o cabeçalho (linhas 44-54) afirmam que nenhum
dos quatro nomes do grupo "sem construtor" tem "um global `X.new(...)` que um script comum possa
chamar". Isso é **falso para dois dos quatro**:

- `SharedTable.new()`/`SharedTable.new(t)` — documentado oficialmente, chamável por script comum.
  O próprio cabeçalho do arquivo JÁ ADMITE isso ("`SharedTable` só nasce de `SharedTable.new(uma
  tabela Lua)` (**tem construtor**, mas é um caso à parte de mutabilidade -- fora do escopo desta
  leva de qualquer forma)") — ou seja, a linha seguinte da MESMA frase se contradiz: primeiro diz
  que "nenhum deles tem um `X.new(...)`", depois admite que `SharedTable` tem. A razão dada
  ("caso à parte de mutabilidade") é uma consideração de PRIORIZAÇÃO (vale a pena simular agora?),
  não do que o campo `HasGlobalConstructor` foi desenhado para responder (o Roblox real expõe
  um construtor chamável?). São perguntas diferentes sendo respondidas com o mesmo booleano.
- `Content.fromUri`/`fromAssetId`/`fromObject`/`Content.none` — a doc oficial documenta múltiplos
  construtores estáticos. O cabeçalho afirma, sem ressalva, que `Content` "só chega via API do
  Engine (... uma propriedade de textura devolvendo `Content`)" — isso ignora os construtores
  estáticos documentados. Vale notar: o próprio Catalog já trata `DateTime` (que também só tem
  métodos estáticos tipo `DateTime.now()`, nunca um `.new()` literal) como `HasGlobalConstructor =
  true` — ou seja, o padrão "namespace com função estática em vez de `.new()`" já é aceito como
  construtor válido em outro lugar do mesmo arquivo. `Content` deveria receber o mesmo tratamento
  que `DateTime` já recebe, por consistência.

**Cenário de falha concreto**: um projeto Rojo real usa `Content.fromUri(...)` numa propriedade
de imagem (padrão moderno pós-2024, cada vez mais comum em UI). Como `HasGlobalConstructor = false`
faz este nome NUNCA virar global (nem real, nem sentinela — por desenho, ver `Catalog.luau:76-80`),
o script do usuário roda no LuauBench com `Content` indexando pra `nil` (comportamento do sandbox
pra global ausente) e o erro que ele vê é o genérico `attempt to call a nil value` — exatamente o
"stub silencioso" que a regra 03 proíbe ("Service não coberto ainda não é stub silencioso... nunca
`nil` silencioso"). O mesmo raciocínio vale pra `SharedTable.new()`. Quando `task-cli` futura
derivar `UnsimulatedGlobals.luau` de `Catalog.UnsimulatedGlobalNames()` (regra 06), essa mensagem
"[LuauBench] Content ainda não simulado" nunca vai aparecer pra esses dois nomes — o erro vai ficar
pior, não melhor, precisamente pros dois nomes que a "leva 2" descreveria como "existem e algum dia
serão simulados".

**Correção**: marcar `SharedTable` e `Content` com `HasGlobalConstructor = true` em
`Catalog.luau` (ficam em 25 nomes com construtor real de "14 novos", não 10) e reescrever o
parágrafo do cabeçalho que hoje afirma o oposto — mantendo `Secret`/`RaycastResult` como os únicos
dois genuinamente sem construtor confirmado pela pesquisa. Ajustar `Catalog.spec.luau` de acordo
(hoje afirma "os 4 nomes novos SEM construtor" incluindo os dois errados — o teste está validando
o comportamento ERRADO, não vai pegar a regressão sozinho).

Não é GRAVE (não quebra a fábrica de userdata, não vaza território, não é mutabilidade não
declarada) — é um erro de dado factual na "fonte única" que o próprio desenho (seção 3.1,
`Catalog.luau`) promete manter correta, com efeito concreto e previsível downstream. **ALTO.**

## Demais itens verificados (sem achado)

- **Guardas de `Define`**: testei eu mesmo — `TypeName` vazio erra; registro duplicado do mesmo
  `TypeName` erra (usei `"RevPair"`, já registrado pela minha própria fixture, numa segunda
  chamada); `Methods` não congelada erra. Os três confirmados.
- **`Catalog.UnsimulatedGlobalNames()` vs `SimulatedNames()`**: teste do coder + minha leitura do
  código confirmam disjunção. Nota não-bloqueante: nesta leva `SimulatedNames()` está vazia (nenhum
  `types/*.luau` existe ainda), então a checagem de disjunção é **vacuamente verdadeira** agora —
  só vai testar algo de fato quando `task-valuetypes-003+` virar entradas `Simulated = true`. Não é
  defeito desta tarefa, só um lembrete pro revisor da próxima leva confirmar de novo com dado real.
- **37 entradas**: contagem bate (23 + 14). Nomes checados adicionalmente contra conhecimento
  confirmável: `Random.new()`, `BrickColor.new()`, `PhysicalProperties.new()`,
  `Vector3int16.new(x,y,z)`, `PathWaypoint.new(...)`, `CatalogSearchParams.new()` — todos
  consistentes com `HasGlobalConstructor = true`.
- **`--!strict` sem `any` real**: confirmado nos 4 arquivos. Os tipos `SpecPoint`/`SpecColor` e os
  "probes" sintéticos (`EqProbe`, `BinaryOperableProbe`, etc.) são de fato tipos nominais opacos
  via `typeof(setmetatable(...))`, não `any` disfarçado — testei que a técnica é exigida pelo
  próprio Luau (não há como declarar campo em userdata) e que o comportamento em runtime não muda
  nada, só o que o type-checker aceita ver.
- **Território**: `git status` confirma zero arquivos fora de `src/valuetypes/` tocados.
  `grep -r valuetypes src/runtime/` vazio. `tools/generate-services.luau` intocado.
- **Add/Sub cruzados**: testei com dois `Define`s independentes meus (`RevPair` com `Add`,
  `RevOther` sem nenhum operador) nos dois sentidos — sempre erro coerente, nunca resultado
  numericamente errado. Confirma a "limitação conhecida" documentada no cabeçalho de `Userdata.luau`.

## Veredito

**APROVADO COM RESSALVAS**

A fábrica (`Userdata.luau`) — o ponto de maior risco desta tarefa — passou em todo ataque que
tentei, incluindo o vetor `rawset`/`rawget` pedido explicitamente. As quatro invariantes,
`--!strict` sem `any`, a fronteira de território (`grep valuetypes src/runtime/` vazio) e a
contagem de testes alegada pelo coder (33/33, 12/12, 10/10) foram todas reproduzidas por mim, sem
divergência. O achado ALTO é isolado em `Catalog.luau` (2 de 37 entradas com `HasGlobalConstructor`
errado, confirmado contra a doc oficial da Roblox) — não compromete a segurança do território, mas
precisa ser corrigido antes que `cli` (task futura) derive `UnsimulatedGlobals.luau` daqui, ou a
lista errada vira permanente por herança.
