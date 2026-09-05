# Revisão — task-valuetypes-005 (Color3 + UDim + UDim2)

Data: 2026-09-05. Escopo revisado (read-only, nenhum arquivo editado): `src/valuetypes/types/Color3.luau`,
`UDim.luau`, `UDim2.luau` + os 3 `.spec.luau` correspondentes. Base usada só como oráculo/sanidade:
`Userdata.luau`, `Float32.luau`. Não rodei `luau-lsp analyze`/specs no diretório inteiro (outros dois
`coder-valuetypes` escrevendo em paralelo em `types/Vector2.luau`/`Vector3.luau`/`Enum.luau`/
`generated/EnumData.luau`/`tools/generate-enums.luau` — confirmado por `git status`/mtimes que esses
arquivos foram escritos DEPOIS dos 6 desta task, sem sobreposição).

## O que foi reproduzido eu mesmo (não aceitei nenhum número do self-report sem rodar)

- `lune run` nos 6 specs desta task + base: **22/22 Color3.spec, 17/17 UDim.spec, 24/24 UDim2.spec,
  33/33 Userdata.spec, 10/10 Float32.spec** — todos batem exatamente com o que o coder alegou.
  `Catalog.spec.luau` deu **13/13 na primeira rodada**, mas ao re-rodar mais tarde (mesma sessão)
  **falhou** (`Enum deveria ter Simulated = false ...`) — não é regressão desta task: outro
  `coder-valuetypes` (Enum) editou `Catalog.luau` ao vivo entre as duas rodadas (`git diff` confirma:
  só a linha do `Enum` mudou). Ruído de concorrência, documentado aqui só para registro, não é
  achado contra task-005.
- `luau-lsp analyze --platform=standard --settings=.luaurc` rodado SÓ nos 6 arquivos desta task (+
  Userdata/Float32) — exit 0, zero diagnósticos.
- `grep -rn newproxy` nos 6 arquivos — vazio (nenhuma segunda fábrica).
- `grep -ri valuetypes src/runtime/` — vazio (invariante de território intacta).
- `git status`/mtimes — os 6 arquivos desta task têm timestamp 18:46–18:52; os arquivos dos outros
  dois coders (Vector2/Vector3/Enum/EnumData/generate-enums) são 18:49–18:55 — sem colisão de
  arquivo, nenhum tocado por este coder além dos 6 declarados.
- Script próprio (copiei os 6 arquivos + Float32/Userdata pro scratchpad, fora do repo, pra rodar
  `require` relativo sem depender de path absoluto) exercitando: `fromHex` com `#`/sem `#`,
  maiúsculo/minúsculo, 3 e 6 dígitos, tamanhos inválidos (4/5/7/vazio/`"#"`); `Color3+Color3`
  (confirmei que ERRA de verdade, `pcall` captura, mensagem cita "arithmetic"); `UDim2.new(UDim,UDim)`
  byte-a-byte idêntico à forma de 4 números; `tostring(UDim2.new(0,300,1,0))` === `"{0, 300}, {1, 0}"`
  exato; `Width`/`Height` — mesmo valor, `rawequal` `false` (é um UDim novo a cada leitura, como o
  próprio cabeçalho documenta); quantização float32 (`0.1`, `1/3`) e int32 (saturação em
  `±2^31`, precisão perdida acima de `2^24`) batendo com `Float32.Quantize`/`QuantizeInt32`;
  `setmetatable`/`getmetatable` nativos; `--!strict` sem `any` real (só menções em comentário
  explicando a ausência).

## Achados

**[MÉDIO] `src/valuetypes/Catalog.luau` não foi atualizado — `Color3`/`UDim`/`UDim2` continuam
`Simulated = false` apesar de totalmente implementados nesta task.**
Problema: o próprio `Catalog.luau` (header e o `result` registrado da task-valuetypes-002 em
`.claude/tasks.json`) documenta que cada task que escreve um `types/*.luau` deve virar
`Simulated = true` nome a nome ("quando a leva 2 marcar `Simulated = true` em `Font`, a sentinela
some sozinha"). Confirmei que o coder do Enum (rodando em paralelo, outra task) cumpriu essa
convenção pro próprio tipo (`git diff` mostra só a entrada `Enum` virando `true`) — o coder desta
task não fez o mesmo pelas suas 3 entradas.
Cenário de falha: `task-valuetypes-007` (Decode.luau/init.luau) tem como critério de aceite "specs
de init assevera que `BuildGlobals()` ... bate com `Catalog.SimulatedNames()`" — com `Color3`/
`UDim`/`UDim2` ainda `false`, `SimulatedNames()` fica incompleta e `BuildGlobals()` corre risco de
não expor esses 3 globais (ou o teste de init vai falhar/mascarar o problema até alguém notar).
Sem impacto EM PRODUÇÃO agora: `cli/UnsimulatedGlobals.luau` ainda mantém lista própria hardcoded
(não deriva de `Catalog` ainda — isso é outra task de `cli`, ainda não despachada), então nenhum
script real quebra hoje por causa disso.
Correção: nesta mesma task (ou num fix rápido antes de `task-valuetypes-007` começar), marcar
`Color3`, `UDim`, `UDim2` como `Simulated = true` em `Catalog.luau`, com o mesmo comentário-padrão
que o coder do Enum já usou.

**[MÉDIO] `Color3.fromHex` aceita caracteres de sinal (`+`/`-`) dentro dos pares hex e produz cor
sem sentido em vez de erro — reproduzido, não estava coberto por nenhum spec.**
Problema: `parseHexChannel` valida só com `tonumber(hexPair, 16) == nil` — mas `tonumber` do Luau
aceita um `-`/`+` líder mesmo com base explícita 16, e para `-` faz wraparound de inteiro sem sinal
em vez de erro ou negativo matematicamente correto.
Cenário de falha (reproduzido por mim):
```
Color3.fromHex("-10000")  -- NÃO erra; R = 72340177116200960 (lixo, muito fora de qualquer range)
Color3.fromHex("+10000")  -- NÃO erra; equivale a "010000" (R = 1/255) -- também deveria ser inválido
```
`tonumber("-1", 16)` no Lune devolve `18446744073709552000` (wraparound de 64 bits sem sinal), não
`-1` nem erro — é essa magnitude que vaza pro `R` da cor.
Correção: validar `hexPair` com um padrão estrito de dígito hex (`string.match(hexPair, "^%x%x$")`,
ou equivalente pro caso de 1 char do shorthand) ANTES de chamar `tonumber`, em vez de confiar
só no retorno de `tonumber`. Acrescentar um teste cobrindo string com `+`/`-` embutido.

**[BAIXO] `ToHex` clampa valores HDR (fora de 0–1) pra `[0,255]` silenciosamente — não declarado na
seção "Divergências declaradas" do cabeçalho, que só fala da ausência de clamp em `new`/`fromRGB`.**
Reproduzido: `Color3.new(1.5, -0.2, 0.5):ToHex()` devolve `"ff0080"` sem erro nem aviso. Não é bug
funcional (o hexadecimal PRECISA caber em 0–255), mas é uma divergência/decisão que a regra 00 pede
pra declarar e o cabeçalho não menciona esse caso específico (só fala do lado `new`/`fromRGB`).
Correção: uma frase no cabeçalho ao lado da divergência de clamping já documentada.

**[BAIXO, informativo — não é achado contra esta task]** `Color3 + Color3` erra com a mensagem
nativa `"attempt to perform arithmetic (add) on userdata"` (genérica, sem citar "Color3") porque
`Add` é `nil` no descriptor e nenhum metamétodo é instalado — comportamento herdado de
`Userdata.luau` (já aprovado na task-valuetypes-002, mesmo padrão testado lá com `SpecColor`). O
spec desta task só assere a substring `"arithmetic"`, nunca alega citar "Color3" na mensagem —
sem alegação falsa, só registro de contexto pro caso de alguém esperar um texto mais específico no
futuro.

## Verificado sem achado

- Fábrica única: nenhum `newproxy` fora de `Userdata.luau` nos 6 arquivos.
- `__metatable` travado (testado empiricamente: `getmetatable` devolve a string, não a tabela real).
- `__newindex` erra sempre nos 3 tipos (nenhum é `RaycastParams`/`OverlapParams`).
- `__eq`: só compara valor quando os dois lados são userdata nosso do MESMO `TypeName`; `Color3 ==
  UDim`, `UDim2 == UDim`, e comparação com `5`/`"x"`/`nil` — todos `false` sem erro, testado por mim
  e pelos specs.
- Quantização float32 (`Scale`, `R`/`G`/`B`) e int32 (`Offset`, arredondado half-away-from-zero,
  saturado em `±2^31`) confirmadas com valores que estouram precisão double (`1/3`, `2^24+1`,
  `2^31-1+0.9`).
- `tostring` fiel aos dois exemplos literais do YAML: `Color3` → `"R, G, B"` (`Lerp` example bate
  byte a byte: `"0.9, 0.9, 0.9"`), `UDim2` → `"{0, 300}, {1, 0}"` byte a byte.
- Operadores batem com a pesquisa: `Color3` sem nenhum operador aritmético (confirmei que ERRA de
  verdade, não é lacuna esquecida); `UDim`/`UDim2` só `+`/`-`, componente a componente.
- `UDim2.new(UDim, UDim)` produz resultado byte-a-byte idêntico ao `UDim2.new(4 números)` para os
  mesmos valores; despacho por `Userdata.TypeNameOf`, sem `any`.
- `Width`/`Height` são sinônimos de VALOR exatos de `X`/`Y` (não de referência — `UDim` é imutável e
  cada leitura constrói um novo, documentado corretamente no cabeçalho, `rawequal` `false` mas
  `==` `true`, exatamente como esperado).
- Tentativa de quebra: `UDim2.new(UDim,UDim,3º arg)` erra citando contagem; `UDim2.new(UDim,
  <não-UDim>)` erra citando UDim; `UDim2.new(número, UDim)` erra citando tipo; `UDim.new()` sem
  args devolve `{0,0}` corretamente.
- `--!strict` presente nos 6 arquivos, zero `any` real (só menções em comentário justificando a
  ausência).
- P9 (unário `-`/`==` em `UDim`/`UDim2`) implementado como hipótese conservadora e claramente
  marcado `[P9, NÃO CONFIRMADO]` no nome dos testes e no cabeçalho dos módulos — não é apresentado
  como fato confirmado em nenhum lugar.
- Nenhum arquivo fora dos 6 desta task foi tocado por este coder (git status + mtimes).

## Veredito

APROVADO COM RESSALVAS — dois follow-ups recomendados antes de fechar a leva: (1) atualizar
`Catalog.luau` (`Color3`/`UDim`/`UDim2` → `Simulated = true`), (2) endurecer a validação de
`Color3.fromHex` contra `+`/`-` embutido (usar `%x%x` em vez de confiar em `tonumber(x,16)`), com
teste novo cobrindo o caso. Nenhum achado GRAVE — fábrica única, imutabilidade e fronteira de
território (`runtime`) intactas.
