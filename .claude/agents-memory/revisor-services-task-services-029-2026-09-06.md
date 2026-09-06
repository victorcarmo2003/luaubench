# Revisão — task-services-029 (`datastore/Snapshot.luau`)

**Data:** 2026-09-06 · `revisor-services` · Read-only. Self-report do coder **não aceito sem reprodução** — todo item abaixo foi verificado por mim, com evidência.

## Escopo confirmado

Território da tarefa: `src/services/datastore/Snapshot.luau` + `Snapshot.spec.luau`. `git status --porcelain -- src/services/datastore/` mostra:

```
 M src/services/datastore/Store.luau        <- task-services-030, já aprovada separadamente, fora deste escopo
 M src/services/datastore/Store.spec.luau   <- idem
?? src/services/datastore/Snapshot.luau
?? src/services/datastore/Snapshot.spec.luau
```

**Território limpo**: só os 2 arquivos novos pertencem a esta tarefa. `Store.luau`/`Store.spec.luau` são de `task-services-030` (já `done`/`APROVADO` no board).

## 1. `lune run` no spec do coder

```
lune run src/services/datastore/Snapshot.spec.luau
```
**37/37 testes passaram** — reproduzido, não é self-report.

## 2. Property test PRÓPRIO (gerador independente, não reusa o do coder)

Escrevi `verify_snapshot.luau` do zero, com `deepEqual` própria e lista de casos própria (cópia local de `Snapshot.luau` no scratchpad só para permitir `require` cross-drive — nenhuma edição no repo). Casos incluídos, além dos 5 hostis do acceptance: `2^53`, `2^53+1`, `-0.0`, aninhamento de 10 níveis com `NaN` na folha, array de registros com `inf`/`-inf`/string hostil misturados, dict com chaves que **parecem** tags mas não são (`n`, `s`, `m`, `"$x"`), string vazia, UTF-8 multibyte.

Rodei duas formas do round-trip para cada caso: via `EncodeToJson`/`DecodeFromJson` (conveniência) **e** via `Encode` + `serde.encode`/`serde.decode` cru + `Decode` (a fórmula literal do acceptance). **66/66 passaram.**

Depois, um segundo script (`extra_check.luau`) cobriu casos extras de fronteira: dicionário de chave única `{["$"]="x"}` (o caso mais adversarial da ambiguidade tag-vs-dicionário) e string com byte `NUL` embutido (`"line1\0line2"`, UTF-8 válido mas incomum) — **ambos sobreviveram ao round-trip.**

## 3. Os 5 casos que motivaram a task, isolados

- `NaN` → JSON → volta como `NaN` (não `null`, não erro): confirmado (`decoded ~= decoded`).
- `inf`/`-inf` → volta exato: confirmado (`decoded == math.huge` / `== -math.huge`).
- Array esparso `{[1]=1,[3]=3]}` → depois do round-trip completo via JSON real, **preserva a esparsidade**: `decoded[1]==1`, `decoded[3]==3`, `decoded[2]==nil`, contagem de chaves = 2 (não veio denso `{1}`).
- `{[2]='a'}` → chave `2` preservada como chave real (`decoded[2]=="a"`, `decoded[1]==nil`).

## 4. `SchemaVersion` maior que o suportado

Documento com `SchemaVersion = CurrentSchemaVersion + 7` → `DecodeDocument` erra citando **os dois números** (encontrada e suportada) na mesma mensagem. Confirmado por busca de substring de ambos os números na mensagem de erro.

## 5. JSON malformado

Três variantes testadas independentemente: JSON truncado/quebrado como valor solto (`DecodeFromJson`) e como documento (`DecodeDocument`) → erro claro contendo `"invalid JSON"`, nunca crash genérico nem retorno silencioso. JSON **válido** mas de forma errada no topo (`"42"`, um número solto em vez de objeto) → também erra (`"malformed document"`), não devolve `nil` fingindo sucesso.

## 6. `Stores` tratado como opaco

Construí uma estrutura **deliberadamente diferente** do formato real de `KeyRecord`/`Version` (`{ SomeRandomShapeThatIsNotAKeyRecordAtAll = { Whatever = {...}, AnotherField = "x" } }`, com um `NaN` aninhado) e rodei `EncodeDocument`/`DecodeDocument`. Sobreviveu **idêntica**. Confirma por leitura de código e por teste que `Snapshot.luau` nunca inspeciona campos específicos (`Name`/`Scope`/`Keys`/`Version`/etc.) — só recursa genericamente sobre o domínio de `Value.CheckSerializable`, exatamente como o desenho (seção 3) exige ("Stores é OPACO para este módulo").

## 7. Avaliação da decisão `{}` → `[]`

**Aceitável, e não encontrei caso onde seria observável dentro deste sistema.** Racional:
- `next({}) == nil` é verdade tanto para array vazio quanto dicionário vazio em Lua — não existe estado interno de tabela que distinga os dois (não há "tipo de tabela" real em Lua, só o padrão de uso das chaves).
- Consumidores dentro do LuauBench (`Store.Export`/`Import`, `GlobalDataStore`) recebem de volta uma tabela Lua comum — `pairs`/`ipairs`/`#` se comportam identicamente sobre `{}` nos dois casos hipotéticos.
- A única forma de isso "vazar" seria se algo fora deste módulo inspecionasse o **JSON bruto no disco** esperando `{}` vs `[]` como sinal de tipo (ex.: uma ferramenta externa de terceiros lendo `datastore.json` diretamente). Isso não é um requisito declarado em nenhum lugar do desenho — o arquivo em disco é formato interno do LuauBench, não uma API pública documentada para terceiros. Se um dia isso mudar (ex.: o arquivo virar contrato público), a decisão precisaria ser revisitada — mas hoje não há tal contrato.
- Testado meu próprio round-trip de `{}` isolado (incluído na leva de 66 casos) e confirmado idempotente.

Concluo: decisão correta e devidamente documentada no cabeçalho do módulo (não é uma omissão silenciosa).

## 8. `--!strict`, zero `any`

Ambos os arquivos começam com `--!strict` (linha 1, confirmado por grep). Único hit de `"any"` no arquivo é dentro de uma **string de mensagem de erro** citada do `serde` (`"expected any valid JSON value"`), não um tipo — não conta como violação.

`luau-lsp analyze --platform=standard --settings=".luaurc"` nos 2 arquivos: **exit 0, zero diagnósticos** (reproduzido).

## 9. Zero `require("@lune/fs")` real — confirmado independentemente

`grep -rn "@lune/fs" src/services/` retorna 4 ocorrências:
- `Snapshot.luau:98` — **comentário** afirmando a invariante ("ZERO require(@lune/fs) neste módulo").
- `Store.luau:7,82` — comentários (tarefa irmã, fora do escopo, mesma invariante documentada).
- `HttpService.spec.luau:57` — **arquivo de teste de outra classe** (`HttpService`), usa `@lune/fs` para fixture de teste, não é código de produção de `Snapshot`/`Store`, fora do território desta tarefa.

Nenhuma chamada `require("@lune/fs")` real em `Snapshot.luau`. Nota da orquestração já havia verificado isso via grep; confirmo de forma independente com o mesmo resultado.

## 10. Território

Confirmado na seção "Escopo" acima — só os 2 arquivos novos.

## Achados

Nenhum GRAVE, ALTO, MÉDIO ou BAIXO. Não encontrei divergência entre o que o coder alegou e o que reproduzi.

**Observação não-bloqueante** (fora do escopo desta tarefa, registrar para quem despachar `task-services-031`): a alegação do coder de "30/30 specs de `src/services/` (556 testes agregados)" não foi reproduzida por mim aqui — está fora do território desta tarefa (que é só os 2 arquivos), e `Snapshot.luau` é um módulo novo, autocontido, com zero `require` além de `@lune/serde`, então o risco de regressão cruzada é estruturalmente baixo (nada mais no repo ainda importa `Snapshot.luau` nesta leva — a fiação fica em `task-services-031`). Recomendo que o revisor de `task-services-031` reproduza a suíte agregada quando a fiação existir, já que é ali que `Snapshot` passa a ser exercitado por outros módulos.

## Veredito

**APROVADO.**
