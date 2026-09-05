# Revisão — `task-valuetypes-001` (`Float32.luau`)

Primeiro código real do território `src/valuetypes/`. Revisão rigorosa, nada aceito por
self-report — todo item abaixo foi reproduzido por mim (`lune run`, `luau-lsp analyze`, scripts
descartáveis próprios apagados ao final, `git status` limpo confirmado).

## O que foi verificado e bateu

1. `lune run src/valuetypes/Float32.spec.luau` → **9/9 passaram**, rodado por mim.
2. Paridade bit a bit com `vector.create(x,0,0).x`, 12 valores próprios (diferentes dos do
   coder): `0`, `-0.0`, `1e30`, `1e-30`, `-1e-30`, `math.huge`, `-math.huge`, `0/0`, `math.pi`,
   `2^-149` (menor subnormal float32), `16777217` (2^24+1, não representável exatamente),
   `9999999.5`. Todos bateram, incluindo NaN (`~= ~=` nos dois lados) e o sinal do zero negativo
   (`1 / Float32.Quantize(-0.0) == -inf`, confirmando que o buffer preserva o sinal do zero via
   IEEE-754, não só o valor absoluto).
3. `Format`: os 4 casos do acceptance batem exatos — `0.1`→`"0.1"`, `-0.7`→`"-0.7"`,
   `1/3`→`"0.33333334"`, `123456.789`→`"123456.79"`.
4. `QuantizeInt32`/`QuantizeInt16`: fronteiras exatas de saturação confirmadas —
   `2^31-1`→inalterado, `2^31`→satura em `2^31-1`, `-2^31`→inalterado, `2^31+1`→satura;
   idem em int16. Half-away-from-zero confirmado (`2.5`→`3`, `-2.5`→`-3`).
5. Buffer module-local: uma única `buffer.create(4)` no escopo do módulo (linha 32), reusada
   dentro de `Quantize` — nenhuma alocação por chamada. Confirmado por leitura (grep não achou
   segunda chamada de `buffer.create`).
6. `--!strict` nos dois arquivos; `grep` por `any` não achou nenhuma ocorrência (nem em
   comentário).
7. P2 (dígitos exatos do `tostring` do Roblox) e P3 (grafia de `nan`/`inf`) estão claramente
   comentadas como aproximação de boa-fé não confirmada, nunca implementadas como se fossem
   fato — mesmo protocolo já usado em `Services.new`.
8. Território: só `src/valuetypes/Float32.luau` + `Float32.spec.luau` foram criados por esta
   tarefa. As modificações concorrentes vistas em `git status` (`src/runtime/Instance.luau`,
   `Sandbox.luau`, `Signal.luau`, `init.luau`, `TypeNameResolver.luau` novo) são de outro agente
   rodando `task-runtime-032` em paralelo (confirmado pelos commits recentes do repo:
   `feat(runtime): reexport SandboxGlobals type`, `feat(services): inject unknown-class resolver
   into runtime` — nada relacionado a `Float32`). Não é violação de território desta tarefa.
9. `luau-lsp analyze --platform=standard --settings=".luaurc"` nos dois arquivos: **exit 0, zero
   diagnósticos**, rodado por mim.

## Achado — MÉDIO

**`src/valuetypes/Float32.luau:158-180` (heurística de widening pra evitar notação
científica espúria)**

Problema: a heurística de widening (introduzida pelo coder para consertar `Format(100)` que
dava `"1e+02"`) parte de uma premissa matematicamente falsa, e o próprio comentário do código
afirma essa premissa como fato ("matematicamente, ... os dígitos extras revelados só podem ser
zeros"). Reproduzi o contra-exemplo:

```
Format(100000000000)        (1e11)  = "99999997952"          -- esperado "100000000000"
Format(100000000000000)     (1e14)  = "100000000376832"      -- esperado "100000000000000"
Format(999999999999999)             = "999999986991104"      -- não é o número redondo original
Format(100000000000000000)  (1e17)  = "99999998430674944"    -- garbled, não "1" seguido de zeros
```

Cenário de falha: qualquer `number` cuja quantização float32 mais próxima **não** seja
exatamente representável em 24 bits de mantissa (a partir de ~2^24 ≈ 16,7 milhões, quando o
número não é um múltiplo "limpo" de potências de 2×5) e cujo primeiro candidato de round-trip
encontrado seja de baixa precisão (1-3 dígitos significativos, típico de números grandes em
notação científica). O widening então usa `%.{magnitude}g` sobre o valor já quantizado — que
para esses casos não são zeros à direita, são os dígitos reais (e "feios") da aproximação
float32/double, porque o candidato curto bateu no round-trip por causa do espaçamento ULP gigante
nessa magnitude, não porque os dígitos extras fossem de fato zero.

Note que valores "redondos" no sentido de serem exatamente representáveis em float32 (ex.:
`1e9`, `2e10`, `1e8`) continuam corretos — o problema só aparece quando a exatidão float32 já se
perdeu antes da formatação.

Por que é MÉDIO e não ALTO/GRAVE: não quebra a fábrica de userdata nem o território; a
propriedade de round-trip (o texto formatado ainda faz `Quantize(tonumber(texto)) == quantized`)
continua válida — é só a legibilidade (o objetivo declarado da correção) que fica pior que a
notação científica original nesse intervalo de magnitude. Para os tipos da leva 1
(`Vector3`/`Color3`/`UDim`/`CFrame`), coordenadas de jogo raramente chegam a `1e11`, então o
impacto prático imediato é baixo — mas `Float32.Format` é módulo-base compartilhado por todo o
território, e o comentário incorreto pode induzir um próximo dev a confiar na heurística além do
que ela suporta.

Correção sugerida: (a) reescrever o comentário para não afirmar como fato matemático algo que só
vale quando o candidato de round-trip cobre dígitos que realmente são zero (ex.: quando o próprio
valor é exatamente representável em float32 dentro da faixa de 24 bits), ou (b) restringir o
widening a magnitudes onde isso é garantido (ex.: só quando `quantized` é um inteiro exatamente
representável em float32, o que pode ser checado comparando `quantized == quantized - quantized %
(10^k)` ou de forma mais direta comparando contra o valor antes de aplicar `%g`), ou (c) no
mínimo documentar a faixa onde a heurística é conhecida por falhar (~acima de `2^24`) em vez de
declarar "cap de magnitude 18" como se fosse uma faixa uniformemente segura.

Não bloqueia a tarefa (P2 já cobre a formatação decimal como aproximação não confirmada), mas
deveria ser corrigido ou pelo menos re-documentado antes que outro tipo do território dependa da
legibilidade de `Format` para valores grandes.

## Veredito

**APROVADO COM RESSALVAS**

As quatro funções pedidas existem, a fábrica de quantização é sólida (paridade bit a bit
confirmada por mim em 12+9=21 valores próprios e do coder, incluindo nan/inf/-inf/zero
negativo/subnormal), a saturação e o arredondamento half-away-from-zero estão corretos e testados
nas fronteiras exatas, o buffer é module-local e reusado, P2/P3 estão honestamente marcadas como
pendência, e o território não vazou. A ressalva é o achado MÉDIO acima: a heurística
anti-notação-científica não generaliza para magnitudes grandes e o comentário que a justifica
está factualmente errado — corrigir a documentação (mínimo) ou a lógica (ideal) antes que
`CFrame`/`Vector3`/etc. comecem a depender de `Format` para exibir valores fora da faixa de
coordenadas típicas de jogo.
