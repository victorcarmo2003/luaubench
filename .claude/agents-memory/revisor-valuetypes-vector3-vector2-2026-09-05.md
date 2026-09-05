# Revisão — task-valuetypes-004 (`types/Vector3.luau` + `types/Vector2.luau`)

Data: 2026-09-05. Escopo: `src/valuetypes/types/Vector3.luau`, `types/Vector2.luau` e os 2 specs
correspondentes. Nada fora desses 4 arquivos foi lido/analisado com ferramenta de análise
(`luau-lsp analyze` rodado só nesses 4). Self-report do coder NÃO foi aceito como prova — tudo
abaixo foi reproduzido por mim.

## 1. Testes rodados por mim (`lune run`)

```
Vector3.spec.luau: 42/42 PASS
Vector2.spec.luau: 38/38 PASS
Float32.spec.luau: 10/10 PASS
Userdata.spec.luau: 33/33 PASS
Catalog.spec.luau: 14/14 PASS  <-- coder alegou 13/13
```

Investiguei a diferença 13 vs 14: `git diff -- src/valuetypes/Catalog.luau src/valuetypes/Catalog.spec.luau`
mostra que a mudança (marcar `Enum` como `Simulated = true` + um teste novo) foi feita pela tarefa
IRMÃ em paralelo (`task-valuetypes-003`, `coder-valuetypes` no `Enum`), não pelo coder desta task.
Comentário no próprio `Catalog.spec.luau` confirma isso explicitamente ("ATUALIZAÇÃO
(task-valuetypes-003, `Enum`)..."). Não é falha desta task — é só o número de regressão citado no
relatório do coder ter ficado desatualizado pela tarefa paralela. Sem impacto: os 14/14 passam.

## 2. Paridade float32 (valores PRÓPRIOS, não os do coder)

Script descartável (`_review_vector_tmp.luau`, removido) testou contra `vector.create` nativo:
`3.14159265358979, -123.456, 0.000001, 999999.125, -0.0, 42, 7/9, 2^40, -2^40+3` para
Vector3(v,2v,3v) e Vector2(v,5v) — todos batem bit a bit (`==` de double, exato para valor
float32-representável). Também confirmei `Vector3.new(0.1,0,0).X == vector.create(0.1,0,0).x` e
que esse valor é DIFERENTE do double cru `0.1` (perda de precisão real, como documentado).

## 3. Assimetrias reais confirmadas

- `Vector2 // Vector2` e `Vector2 // number` erram (sem `IDiv` no Descriptor) — confirmado, erro
  nativo "attempt to perform arithmetic".
- `Vector2:Cross()` devolve `number` (`typeof == "number"`, valor `3*2-4*1=2` verificado com
  vetores próprios) — `Vector3:Cross()` devolve `Vector3` (`type() == "userdata"`).
- `Vector3 * Vector2`, `Vector3 / Vector2`, `Vector2 * Vector3` (ordem trocada) — todos erram com
  mensagem citando os DOIS TypeNames corretos (`"attempt to perform arithmetic (mul) on Vector3
  and Vector2"`), nunca produzem valor errado silenciosamente.
- `Vector2:Max()/:Min()` variádico (0, 1 e 2+ argumentos extras, coberto no spec do coder,
  reproduzido) vs. `Vector3:Max/Min` com exatamente 1 argumento.
- `FuzzyEq`: Vector3 usa epsilon escalado por magnitude, Vector2 usa abs puro — confirmado nos dois
  módulos, valores de teste passam.

## 4. `Unit` de vetor zero

`Vector3.zero.Unit` e `Vector2.zero.Unit`: todos os componentes são NaN (`x ~= x` verdadeiro),
NÃO `(0,0,0)`/`(0,0)` — confirmado por mim, bate com a pesquisa (§3 do relatório de pesquisa).

## 5. Comutatividade de `Vector3 * number`

`a * 10`, `10 * a`, `a * b` (Vector3*Vector3 componente a componente) — todos com valores próprios,
resultado correto e comutativo.

## 6. `FromNormalId`/`FromAxis` contra `Enum` REAL

No momento desta revisão `src/valuetypes/types/Enum.luau` e `generated/EnumData.luau` JÁ EXISTEM no
disco (tarefa irmã em paralelo). Testei ao vivo (script descartável, removido):

```
Enum.NormalId.Top.Name = Top, typeof = userdata
Vector3.FromNormalId(Enum.NormalId.Top) -> ok, "0, 1, 0"
Vector3.FromAxis(Enum.Axis.X) -> ok, "1, 0, 0"
```

Confirma que a tipagem estrutural `EnumItemLike = { Name: string }` funciona em runtime com o
`EnumItem` real (userdata cujo `__index` responde `.Name`). Nota pra tarefa futura de integração
(`Decode.luau`/bridging): `EnumItem` é `typeof(setmetatable(...))`, não uma tabela pura — vale
confirmar com `luau-lsp` se um call-site real (fora de `:: any`) aceita passar `Enum.NormalId.Top`
direto pra um parâmetro `EnumItemLike` sem cast explícito. Não é bug desta task (Vector3.luau não
importa Enum, não há erro de análise nos 4 arquivos escopados), só um ponto de atenção para quem
escrever a ponte de verdade.

Também confirmei case-sensitivity: `FromNormalId({Name="top"})` (minúsculo) erra.

## 7. D8 e P8

Ambas documentadas nos cabeçalhos de `Vector3.luau` (D8 + P8) e `Vector2.luau` (só P8, com nota
explícita de que D8 não se aplica a Vector2). Redigidas como aproximação de boa-fé/inferência, não
como fato confirmado — linguagem correta ("APROXIMAÇÃO DE BOA-FÉ", "não confirmada", "reavaliar
se pesquisada").

## 8. `--!strict` e ausência de `any`

`grep -n "any"` nos 4 arquivos: zero ocorrências do tipo `any` (a única menção é o nome do tipo
sintético `AnyOperable` nos specs, que é um tipo próprio, não o `any` embutido). `--!strict` na
primeira linha dos 4 arquivos.

`luau-lsp analyze` (v1.69.0) rodado SÓ nos 4 arquivos (não no diretório inteiro, conforme
restrição de escopo): zero erros, zero warnings de tipo — só o aviso de plataforma esperado
(`--platform roblox` sem definitions).

## 9. Território

`git diff -- src/valuetypes/Catalog.luau src/valuetypes/Catalog.spec.luau` mostra que a única
mudança nesses dois arquivos é `Enum: Simulated = false -> true` + 1 teste — atribuída
explicitamente no comentário à `task-valuetypes-003` (Enum), não a esta task. `git status --short
src/runtime src/services src/cli` vazio. `grep -rl valuetypes src/runtime` vazio. `git diff --
.claude/tasks.json` só move a task de `in-progress` pra `review`. Confirmado: o coder desta task
tocou EXATAMENTE `types/Vector3.luau`, `types/Vector2.luau`, `types/Vector3.spec.luau`,
`types/Vector2.spec.luau` — nada mais.

## 10. Testes de quebra

- `Vector3.new()` sem argumentos -> `(0,0,0)` (default correto, confirmado).
- `Vector3 + Vector2` erra; `Vector3 == Vector2` -> `false` SEM erro (invariante 4 de
  `Userdata.luau`, reconfirmada).
- `Vector3:Cross("nope")` e `Vector3:Dot(42)` erram (via `Userdata.Unwrap` validando TypeName).
- `setmetatable(v, {})` erra nativamente; `pairs(v)` erra nativamente; `getmetatable(v)` devolve a
  string travada (não a metatable real).

## Achados

Nenhum GRAVE/ALTO/MÉDIO. Duas notas BAIXO, nenhuma bloqueante:

1. **BAIXO** — `Float32.Quantize` aplicado aos retornos escalares `Magnitude`/`Dot`/`Cross`/`Angle`
   é uma extensão além da tabela explícita da Decisão 3 do desenho arquitetural (que lista só
   X/Y/Z). O cabeçalho de `Vector3.luau`/`Vector2.luau` documenta isso honestamente como
   "extensão de boa-fé", com justificativa (esses retornos são documentados como `float` na doc
   oficial). Não é silencioso, não é inventado sem base — só maior que o escopo literal do
   desenho. Sem ação necessária, só registro.
2. **BAIXO** — `numAt`/`describeType`/`tryUnwrap` são duplicados quase idênticos entre
   `Vector3.luau` e `Vector2.luau`. A arquitetura não exige um módulo-base compartilhado entre
   tipos irmãos nesta leva, então não é violação de contrato — só uma oportunidade cosmética de
   redução de duplicação, se algum dia houver um terceiro tipo com a mesma forma.

## Veredito

APROVADO
