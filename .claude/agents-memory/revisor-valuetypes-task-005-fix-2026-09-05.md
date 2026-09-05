# Revisão — task-valuetypes-005-fix (Color3.fromHex + consolidação Catalog.luau)

Revisão independente, tudo reproduzido pelo revisor (não aceito self-report do coder). Ambiente:
Lune em `~/.rokit/bin/lune`, `luau-lsp` em `~/.rokit/bin/luau-lsp`.

## 1. Suíte completa (9 specs do território) — rodada por mim

```
Float32.spec.luau        10/10
Userdata.spec.luau       33/33
Catalog.spec.luau        15/15
types/Enum.spec.luau     30/30
types/Vector3.spec.luau  42/42
types/Vector2.spec.luau  38/38
types/Color3.spec.luau   24/24
types/UDim.spec.luau     17/17
types/UDim2.spec.luau    24/24
```

Todos os números batem exatamente com o alegado. Todos `exit code: 0`.

## 2. Reproduzido bug original + fix (script descartável, apagado depois)

Confirmado `tonumber("-1", 16) == 18446744073709552000` (causa raiz alegada, correta).

Casos que devem ERRAR — todos erraram, mensagem cita a entrada original (não a "body" sem `#`):
- `"-10000"` → erra, cita `"-10000"`
- `"+00ff00"` → erra, cita `"+00ff00"`
- `"12 456"` (espaço embutido) → erra, cita `"12 456"`
- `"12345!"` (símbolo) → erra, cita `"12345!"`
- `"#-fff"` (sinal na forma abreviada, com `#`) → erra, cita `"#-fff"` (o `hex` original, não o `body` já sem `#` — confirmado que a mensagem usa a variável certa)

## 3. Regressão de entradas válidas — confirmado

- `Ec008C` (case misto, 6 dígitos) → R=0.9254902 G=0 B=0.5490196 = `0xEC/255, 0x00/255, 0x8C/255` ✓
- `AbC` (case misto, 3 dígitos) → equivale a `AABBCC` expandido, valores batem ✓
- `#FFF`, `000`, `FF0000` → corretos

## 4. Teste de coerência do Catalog — é varredura real de filesystem

`Catalog.spec.luau` linha ~268 usa `fs.readDir(process.cwd .. "src/valuetypes/types")` de verdade
(não lista hardcoded). Raciocínio verificado: se um `types/CFrame.luau` futuro existisse sem
`Catalog.luau` marcar `CFrame` como `Simulated = true`, o loop encontraria `CFrame.luau`,
`byName["CFrame"]` existiria (`Simulated = false` hoje) e o `assert(entry.Simulated, ...)` falharia
— o teste pegaria o drift de verdade.

**Achado BAIXO (documentação, não funcional)**: o comentário do teste (linhas ~278-280) diz que
arquivo que "não seja um `.luau` 1:1 com o nome de uma entrada do catálogo (ex.: futuro helper
interno)" é **ignorado** — mas o código não implementa esse ignore: qualquer `.luau` não-spec cujo
nome não bata com uma entrada de `Catalog` faz o teste falhar com
`assert(entry ~= nil, ...)`, não ser pulado silenciosamente. Não é bug hoje (todo arquivo em
`types/` corresponde 1:1 a uma entrada), mas o comentário promete um comportamento que o código não
tem — se um futuro coder adicionar um helper interno em `types/` (ex. `types/hsvMath.luau`), o
teste vai quebrar a build em vez de ignorar como o comentário sugere. Correção sugerida: ajustar o
comentário para refletir a real (e mais segura) postura de "falha alto e cedo", ou implementar de
fato o skip se for essa a intenção.

## 5. Grep `Simulated = true` em Catalog.luau

Exatamente: `Vector3`, `Vector2`, `Color3`, `UDim`, `UDim2`, `Enum` = `true`. `CFrame` e todo o
resto = `false`. Confirmado por grep direto, não só leitura visual.

## 6. `--!strict` / `any`

Presente nos 4 arquivos. Zero ocorrências de `any` (grep `\bany\b` vazio).

## 7. Território limpo

`git status --porcelain`: só `.claude/tasks.json`, `src/valuetypes/Catalog.luau`,
`src/valuetypes/Catalog.spec.luau`, `src/valuetypes/types/Color3.luau`,
`src/valuetypes/types/Color3.spec.luau`. Nada em `runtime/`, `services/`, `cli/`, `tools/`.

## 8. Edge cases extras (não necessariamente cobertos pelo coder)

- `""` (string vazia) → erra citando `""` ✓
- `"#"` (só cerquilha, body vira `""`) → erra citando `"#"` ✓
- `"1234"` / `"12345"` / `"abcd"` / `"abcde"` (4 e 5 dígitos hex válidos, nem 3 nem 6) → erram
  citando a entrada ✓
- `nil` → erra, mas com erro NATIVO do Luau (`invalid argument #1 to 'sub' (string expected, got
  nil)`), não a mensagem custom do `Color3.fromHex`. Nunca produz lixo — apenas a mensagem não cita
  "Color3.fromHex" nem é tão amigável quanto o caso de formato inválido.
- `true` (boolean) → mesmo comportamento: erro nativo de `string.sub`, nunca lixo.
- Número puro (`12345`, tipo `number`, não `string`) → **não é rejeitado por tipo**: a biblioteca
  `string.*` do Lua/Luau faz coerção automática número→string, então `12345` (number) é tratado
  como se fosse `"12345"` e cai no mesmo caminho de validação de formato (erra por ter 5 dígitos).
  Não é uma regressão introduzida por este fix — comportamento herdado da coerção nativa da
  linguagem, não checado explicitamente antes nem depois. Nenhum destes casos (`nil`/`boolean`/
  `number`) está no escopo do acceptance da task (que é sobre formato de string hex), e nenhum
  produz valor-lixo — só achados informativos (BAIXO), não bloqueantes.

## Veredito

APROVADO.

Nenhum achado GRAVE/ALTO/MÉDIO. Dois achados BAIXO, nenhum bloqueante:
1. Comentário do teste de coerência do Catalog promete um "ignore" de arquivos não-catalogados que
   o código não implementa (falha em vez de ignorar) — ajustar comentário ou implementar o skip.
2. `fromHex` com input não-string (`nil`/`boolean`) erra com mensagem nativa do Luau em vez da
   mensagem custom — nunca produz lixo, mas foge do padrão de mensagem "cita a entrada" que os
   outros casos têm. Fora do escopo do acceptance desta task.
