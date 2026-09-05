# Pesquisa — Datatypes (Color3, UDim, UDim2, Rect, NumberRange, TweenInfo, BrickColor) e sistema Enum

Data da pesquisa: 2026-09-05.

## Fontes usadas

1. **Roblox/creator-docs** (repositório oficial que alimenta `create.roblox.com/docs`), branch `main`, arquivos YAML brutos baixados diretamente via `curl` de
   `https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/datatypes/<Nome>.yaml`.
   Esses YAMLs são a fonte estruturada que gera as páginas de doc oficiais — texto lido **verbatim** por mim (não resumido por ferramenta), salvo indicação contrária.
2. **Full-API-Dump.json local já pinado no projeto** (`.cache/api-dump/28360dea.json` / `28360dea4b90b35dc3fe9f829baae64fb6c50e75.json`), conforme `tools/api-dump.lock.json`:
   - `source`: MaximumADHD/Roblox-Client-Tracker
   - `commit`: `28360dea4b90b35dc3fe9f829baae64fb6c50e75`
   - `robloxVersion`: `0.737.0.7371584`
   - `fetchedAt`: 2026-09-05
   - Usei este arquivo diretamente com Python (`json.load`) para a seção `Enums` — não peguei de nenhuma cópia externa.
3. **devforum.roblox.com** — só para comportamento de runtime que a doc de referência (YAML) não cobre (mensagens de erro reais, equality de datatypes). Marcado explicitamente como comunidade/inferência, nunca como fonte primária.
4. `content/en-us/luau/enums.md` do mesmo repositório (página conceitual "Enums", não a referência de datatype) — lida verbatim.

---

## A) Color3

Fonte: `Color3.yaml` (creator-docs), lido integralmente.

**Construtores**
- `Color3.new(red: number = 0, green: number = 0, blue: number = 0)` — range declarado 0 a 1. Todos os três parâmetros têm default `0` (confirmado: `default: 0` no YAML para os três).
- `Color3.fromRGB(red: number = 0, green: number = 0, blue: number = 0)` — range declarado 0 a 255, defaults `0` para os três.
- `Color3.fromHSV(hue: number, saturation: number, value: number)` — sem default declarado (campo `default:` vazio no YAML) — ou seja, a doc não afirma que são opcionais.
- `Color3.fromHex(hex: string)` — "a six- or three-character hexadecimal format, case insensitive. A preceding hashtag (#) is ignored, if present." Formatos aceitos confirmados: `RRGGBB`, `RGB` (shorthand tipo CSS), com ou sem `#` na frente, case-insensitive. Exemplos do próprio YAML: `Color3.fromHex("FF0000")`, `Color3.fromHex("ec008c")`, `Color3.fromHex("000")`, `Color3.fromHex("#FFF")`.

**Propriedades** — `R`, `G`, `B`: todas `type: number`, sem indicação de mutabilidade no YAML (não há flag explícita de "read-only" no schema desses três campos, diferente de UDim que documenta isso em prosa). Convenção real do Roblox (não 100% no YAML, mas consistente com todos datatypes de valor): são read-only — datatypes são imutáveis, não há setter.

**Métodos**
- `Color3:Lerp(color: Color3, alpha: number): Color3`
- `Color3:ToHSV(): (number, number, number)` — retorna 3 valores (h, s, v), sem parâmetros.
- `Color3:ToHex(): string` — retorna string de 6 caracteres, formato `RRGGBB`, **sem** `#` prefixado.
- Função solta (não-método) `Color3.toHSV(color)` existe mas está **deprecated**, com nota explícita: "This function is functionally equivalent to `Datatype.Color3:ToHSV()`." — não implementar como membro simulado a menos que algum projeto real dependa (regra 03).

**Operadores**: seção `math_operations: []` — **vazia**. Ou seja, a doc oficial **não lista nenhum operador aritmético** (`+`, `-`, `*`, `/`) para Color3. Isso é evidência direta contra a suposição comum de que Color3 suporta `+`/`-`/`*`. **Não simular operadores aritméticos em Color3** a menos que o usuário peça uma extensão deliberada (documentada como extensão do LuauBench, fora do namespace real — regra 00).

**`tostring`**: confirmado pelo exemplo literal do próprio YAML (dentro do método `Lerp`):
```lua
local gray10 = white:Lerp(black, 0.1)
print(gray10)  --> 0.9, 0.9, 0.9
```
Formato: `"R, G, B"` — três números separados por `, `, sem colchetes/chaves, sem prefixo de tipo.

---

## B) UDim e UDim2

Fonte: `UDim.yaml` e `UDim2.yaml` (creator-docs), lidos integralmente.

### UDim

**Construtor**: `UDim.new(Scale: number = 0, Offset: number = 0)`. A doc afirma explicitamente: "Both parameters are optional and default to `0` when omitted; calling `UDim.new()` with no arguments produces a UDim equivalent to `UDim.new(0, 0)`." — confirma que `UDim.new()` sem argumentos é válido.

**Propriedades**: `Scale: number`, `Offset: number` — ambas descritas em prosa como "This property is read-only." Offset é dito "Stored as an integer" (mesmo sendo tipado como `number`).

**Operadores** (`math_operations`), únicos dois listados:
- `+` : `UDim + UDim -> UDim`, soma Scale com Scale e Offset com Offset independentemente.
- `-` : `UDim - UDim -> UDim`, subtração componente a componente.

**Unário `-` e `==`: NÃO documentados nesta seção.** Importante: comparei com `Vector3.yaml` (mesmo repositório) — o `math_operations` de Vector3 lista `+`, `-` (binário), `*`, `/`, `//` mas **também não lista** unário `-` nem `==`, apesar de Vector3 comprovadamente suportar ambos no Roblox real. Ou seja, **esta seção do YAML documenta só operadores binários aritméticos, nunca unário nem igualdade — a ausência não é evidência de que UDim não suporte unário `-` ou `==`.** Não consegui confirmar com uma fonte primária dedicada se `-UDim.new(...)` é válido. Ver seção "Incerto".

**`tostring`**: não há exemplo isolado de `print(UDim.new(...))` no YAML. Inferência de alta confiança pelo padrão do UDim2 (ver abaixo): `"{Scale, Offset}"`, ex. `"{0.5, 10}"`. **Não é uma citação direta — marcar como inferido.**

### UDim2

**Construtores** (4 entradas na doc, todas chamadas `UDim2.new` — overloads reais confirmados):
1. `UDim2.new()` — sem parâmetros, retorna `UDim2.new(0,0,0,0)`.
2. `UDim2.new(xScale: number = 0, xOffset: number = 0, yScale: number = 0, yOffset: number = 0)`.
3. `UDim2.new(x: UDim, y: UDim)` — **confirmado, existe de fato** o overload que recebe dois `UDim`. Exemplo do próprio YAML: `UDim2.new(x, y)` equivalente a `UDim2.new(0.5, 10, 1, 0)` quando `x = UDim.new(0.5,10)`, `y = UDim.new(1,0)`.
4. `UDim2.fromScale(xScale: number = 0, yScale: number = 0)`.
5. `UDim2.fromOffset(xOffset: number = 0, yOffset: number = 0)`.

**Propriedades**:
- `X: UDim`, `Y: UDim` — dimensões nativas.
- `Width: UDim`, `Height: UDim` — **confirmado que existem e são sinônimos exatos**: "A synonym for `Datatype.UDim2.X`" / "...`Datatype.UDim2.Y`". Ou seja `Width == X` e `Height == Y` (mesmo UDim, não cópia com semântica diferente).

**Métodos**: `UDim2:Lerp(goal: UDim2, alpha: number): UDim2`.

**Operadores**: `math_operations` lista apenas `+` e `-` (binários, `UDim2 op UDim2 -> UDim2`, soma/subtrai X e Y componente a componente). Mesma ressalva de UDim: unário `-` e `==` não estão nesta seção do schema, e essa seção comprovadamente omite unário/igualdade mesmo para datatypes que os suportam (Vector3). Não confirmado diretamente para UDim2.

**`tostring`**: **confirmado por exemplo literal do YAML**:
```lua
guiObject.Size = UDim2.new(0, 300, 1, 0)
print(guiObject.Size) --> {0, 300}, {1, 0}
```
Formato exato: `"{xScale, xOffset}, {yScale, yOffset}"`.

---

## C) Rect, NumberRange, TweenInfo, BrickColor

Fontes: `Rect.yaml`, `NumberRange.yaml`, `TweenInfo.yaml`, `BrickColor.yaml` (creator-docs), lidos integralmente.

### Rect
- `Rect.new()` — sem args, `Min`/`Max` = `Vector2.new(0,0)`.
- `Rect.new(min: Vector2, max: Vector2)` — o construtor normaliza: `Min` é o mínimo componente-a-componente dos dois vetores passados, `Max` o máximo, **independente da ordem** em que foram passados.
- `Rect.new(minX: number, minY: number, maxX: number, maxY: number)` — quarto overload por 4 números.
- Propriedades: `Min: Vector2`, `Max: Vector2`, `Width: number` (= `Max.X - Min.X`, sempre não-negativo), `Height: number` (= `Max.Y - Min.Y`, sempre não-negativo). `math_operations: []` (nenhum operador).

### NumberRange
- `NumberRange.new(value: number)` — Min e Max ambos setados a `value`.
- `NumberRange.new(minimum: number, maximum: number)` — doc afirma "`minimum` must be less than or equal to `maximum`" (não diz explicitamente o que acontece se violado — não confirmado se lança erro ou apenas é contrato/UB).
- Propriedades: `Min: number`, `Max: number`. Nota da doc: armazenados como float 32-bit — números muito grandes ou de alta precisão decimal podem perder precisão. `math_operations: []`.

### TweenInfo
**Assinatura exata confirmada, ordem e defaults do YAML** (`TweenInfo.new`):
```
TweenInfo.new(
    time: number = 1,
    easingStyle: EasingStyle = Enum.EasingStyle.Quad,
    easingDirection: EasingDirection = Enum.EasingDirection.Out,
    repeatCount: number = 0,
    reverses: boolean = false,
    delayTime: number = 0
)
```
Propriedades read-only correspondentes (nomes exatos, todas presentes no YAML): `Time`, `EasingStyle`, `EasingDirection`, `RepeatCount`, `Reverses`, `DelayTime`. A doc afirma explicitamente: "The properties of a `Datatype.TweenInfo` cannot be written to after its creation." `math_operations: []`.

### BrickColor
Fonte: `BrickColor.yaml` (1976 linhas — a maior parte é uma tabela HTML embutida no campo `description`, ver abaixo).

**Construtores/factory (todos confirmados no YAML)**:
- `BrickColor.new(val: number)` — por índice numérico (**Number** na tabela de referência). Se inválido, retorna default `"Medium stone grey"` (não lança erro).
- `BrickColor.new(r: number, g: number, b: number)` — componentes 0–1; casa com a `BrickColor` de menor distância total (soma das diferenças absolutas por canal) entre todas as cores conhecidas.
- `BrickColor.new(name: string)` — nome exato (ex: `"Pastel Blue"`); se não casar, retorna default `"Medium stone grey"`.
- `BrickColor.new(color: Color3)` — mesmo algoritmo de menor distância do overload `(r,g,b)`.
- `BrickColor.palette(paletteValue: number)` — índice zero-based de 0 a 127 (paleta de 128 cores do color picker do Studio). **Lança erro se fora dos limites** (diferente do `.new(val)` numérico, que faz fallback silencioso).
- `BrickColor.random()` — cor aleatória dentre as 128 da paleta.
- Constantes nomeadas confirmadas: `BrickColor.White()`, `.Gray()` (= "Medium stone grey", mesma default de fallback), `.DarkGray()` (= "Dark stone grey"), `.Black()`, `.Red()` (= "Bright red"), `.Yellow()` (= "Bright yellow"), `.Green()` (= "Dark green"), `.Blue()` (= "Bright blue").

**Propriedades** (todas read-only, confirmadas): `Number: number`, `Name: string`, `Color: Color3`, `r: number` (equivalente a `Color.R`), `g: number` (equivalente a `Color.G`), `b: number` (equivalente a `Color.B`).

**Tabela canônica de cores (Name ↔ Number ↔ Palette Index ↔ Color3)**: **existe e está embutida diretamente na documentação oficial**, no campo `description` do YAML, como uma tabela HTML com colunas: `Color` (swatch), `Name`, `Number`, `Palette Index`, `RGB Value (0-255)`, `RGB Value (0-1)`.
- Contagem confirmada por script: **208 linhas de cor** (`<tr>` menos o cabeçalho) — ou seja, **208 BrickColors documentados** oficialmente.
- Localização exata para o `coder-services`/gerador: `content/en-us/reference/engine/datatypes/BrickColor.yaml`, dentro do bloco `description:` do datatype (linhas ~38–1718 no arquivo baixado em 2026-09-05). **Não copiei as 208 linhas para este relatório** (bloataria o arquivo) — recomendo ao `arquiteto`/`coder-services` escrever um pequeno script de extração desse HTML embutido (ou, alternativa mais simples, usar uma lib/dataset já extraído — mas **a fonte primária confirmada é este YAML**, não uma cópia de terceiros).
- Exemplo de linha (primeira da tabela, White): `Number=1`, `Palette Index=87`, RGB 0-255 = `242, 243, 243`, RGB 0-1 = `0.950, 0.953, 0.953`.

---

## D) Enum — estrutura e semântica

### D.1 — Estrutura exata da seção `Enums` no `Full-API-Dump.json` (fonte primária: dump local pinado, `.cache/api-dump/28360dea.json`)

Li o JSON diretamente com Python. Estrutura confirmada:

```json
{
  "Classes": [ ... ],
  "Enums": [
    {
      "Name": "KeyCode",
      "Items": [
        { "LegacyNames": ["Unknown"], "Name": "None", "Value": 0 },
        { "Name": "Backspace", "Value": 8 },
        { "Name": "Tab", "Value": 9 }
        // ...
      ]
    }
    // ... 628 outros enums
  ],
  "Version": 1
}
```

Campos confirmados por inspeção real (não documentação — inspecionei o JSON bruto):
- Cada entrada de `Enums` tem exatamente as chaves `Name` (string) e `Items` (array). **Não há `Tags` no nível do enum na maioria dos casos** — mas **existe em 6 dos 629 enums** (todos com `Tags: ["Deprecated"]`), exemplo real extraído do dump:
```json
{
  "Name": "GearGenreSetting",
  "Tags": ["Deprecated"],
  "Items": [
    { "Name": "AllGenres", "Tags": ["Deprecated"], "Value": 0 },
    { "Name": "MatchingGenreOnly", "Tags": ["Deprecated"], "Value": 1 }
  ]
}
```
- Cada item de `Items` tem `Name` (string) e `Value` (number/inteiro), sempre presentes.
- Campo opcional `LegacyNames` (array de string) — presente em **55 itens** no dump inteiro (ex.: `KeyCode.None` tem `LegacyNames: ["Unknown"]`, ou seja, o item já se chamou `Unknown` numa versão anterior do Roblox).
- Campo opcional `Tags` no nível do item — presente em **152 itens**, valor observado sempre `["Deprecated"]` neste dump (não vi outras tags em itens de enum, ex. não vi `Hidden`/`NotScriptable` em itens — essas tags aparecem em `Classes`, não necessariamente aqui; **não fiz varredura exaustiva de todos os valores possíveis de Tag em itens**, só confirmei quais valores aparecem neste dump específico).
- **Não há campo de descrição/summary dentro do dump** — isso só existe na doc separada (`content/en-us/reference/engine/enums/<Nome>.yaml`, que é outro arquivo, não pesquisado aqui pois não foi pedido).

### D.2 — Semântica em runtime

Fontes: `content/en-us/luau/enums.md` (página conceitual, lida verbatim) + `Datatype.Enum.yaml`, `Datatype.Enums.yaml`, `Datatype.EnumItem.yaml` (referência de datatype, lidos verbatim) + devforum (para o que a doc não cobre — marcado abaixo).

Existem **três datatypes distintos e documentados separadamente** — confirmado pelos nomes exatos dos arquivos/campo `name:` de cada YAML:

| Datatype | O que é | Membros confirmados na doc |
|---|---|---|
| `Enums` | O objeto raiz, exposto na global Luau `Enum` | Método `Enums:GetEnums(): {Enum}` — "Returns an array containing all available Enums on Roblox." |
| `Enum` | Um enum individual, ex. `Enum.KeyCode` | `Enum:GetEnumItems(): {EnumItem}`, `Enum:FromName(name: string): EnumItem?`, `Enum:FromValue(value: number): EnumItem?` |
| `EnumItem` | Um item, ex. `Enum.KeyCode.Space` | Propriedades `Name: string`, `Value: number`, `EnumType: Enum` (referência ao Enum pai) |

- **`Enum` global** = uma instância do datatype `Enums` (confusão de nomenclatura proposital do próprio Roblox: a global se chama `Enum` mas o *datatype* dela se chama `Enums`, plural). Citação direta da doc: "The `Datatype.Enums` data type, more commonly known as `Datatype.Enum` by its global variable in Luau, acts as the root access point for all available enums."
- `typeof(Enum)` → `"Enums"` — **inferido com alta confiança, não citado com exemplo direto no texto**: a doc de `typeof` (`RobloxGlobals.yaml`) diz que `typeof` "returns the type of the object specified, as a string" e que para tipos Roblox-específicos retorna o nome do datatype (ex. `"Vector3"`, `"CFrame"`, citados como exemplo na própria doc). Como o nome do datatype é literalmente `Enums`, a inferência é direta, mas não vi um `print(typeof(Enum)) --> "Enums"` escrito em lugar nenhum.
- `typeof(Enum.KeyCode)` → `"Enum"` — mesma lógica de inferência (datatype se chama `Enum`).
- `typeof(Enum.KeyCode.Space)` → `"EnumItem"` — mesma lógica (datatype se chama `EnumItem`). Essa cadeia de inferência é corroborada por uma busca na web (devforum, resumida por ferramenta, não citação literal) que descreve exatamente essa mesma cadeia Enums→Enum→EnumItem para `typeof`.
- **`tostring(Enum.KeyCode.Space)`**: **confirmado por exemplo literal** em `content/en-us/luau/enums.md`:
  ```lua
  local partTypes = Enum.PartType:GetEnumItems()
  for index, enumItem in partTypes do
      print(enumItem)
  end
  --[[
      Enum.PartType.Ball
      Enum.PartType.Block
      ...
  ]]
  ```
  Formato exato: `"Enum.<NomeDoEnum>.<NomeDoItem>"`.
  Também confirmado no mesmo arquivo: `print(Enum.PartType.Cylinder.EnumType) --> PartType` — ou seja, `tostring` do **objeto `Enum` sozinho** (não do item) é só o nome, sem prefixo `Enum.`.

- **Igualdade (`==`)**: **não encontrei uma fonte primária (doc oficial) que declare explicitamente** se `Enum.KeyCode.Space == Enum.KeyCode.Space` compara por identidade ou por valor. Evidência indireta forte (não prova formal):
  - Datatypes de valor "clássicos" do Roblox (`Vector3`, e por extensão a família UDim/Color3) usam **igualdade por valor** via metamétodo `__eq` — confirmado via múltiplas discussões de devforum (comunidade, não doc oficial) descrevendo que `Vector3.new(1,2,3) == Vector3.new(1,2,3)` é `true` mesmo sendo dois userdata distintos.
  - Para `EnumItem` especificamente, a arquitetura é diferente: `Enum.KeyCode.Space` não é um "construtor" (não é `.new(...)`), é um **lookup** num conjunto fixo — não há como criar duas instâncias distintas de `Enum.KeyCode.Space`. Isso é fortemente sugerido (mas não citado literalmente por nenhuma fonte que encontrei) pelo padrão extremamente comum e confiável no ecossistema Roblox de usar EnumItem como **chave de tabela** (`local map = {[Enum.KeyCode.Space] = "jump"}`) — em Luau/Lua, indexação de tabela com chave userdata usa igualdade **bruta** (referência), não `__eq`; para esse padrão funcionar de forma consistente entre módulos diferentes que importam `Enum.KeyCode.Space` separadamente, **o objeto precisa ser o mesmo (singleton internado)**.
  - **Recomendação prática para o LuauBench** (decisão de design, não fato): internar `EnumItem` — cada `Enum.<X>.<Y>` deve resolver sempre para a mesma tabela/userdata Luau. Isso satisfaz tanto igualdade por identidade quanto por valor simultaneamente e replica o uso real como chave de tabela sem risco. Marcar como decisão do `arquiteto`, não fato confirmado.

- **Erro ao acessar enum/item inexistente** — **não é doc oficial** (a referência de datatype não documenta mensagens de erro). Levantei via múltiplos relatos reais de erro no devforum (mensagens reportadas por usuários, altamente consistentes entre si):
  - `Enum.NaoExiste` (nome de enum que não existe no `Enum` global) → mensagem no padrão: `"<Nome> is not a valid member of Enum"` (sem aspas ao redor de "Enum"). Exemplo real citado: `"RigType is not a valid member of Enum"` (quando o dev tentou `Enum.RigType.R15` em vez de `Enum.HumanoidRigType.R15`).
  - `Enum.KeyCode.NaoExiste` (nome de item que não existe dentro de um enum válido) → mensagem no padrão: `"<Nome> is not a valid member of "Enum.<NomeDoEnum>""` (com aspas ao redor de `Enum.<NomeDoEnum>`). Exemplo real citado: `"MouseButton2 is not a valid member of "Enum.KeyCode""`.
  - **Confiança**: média-alta (múltiplos relatos independentes e consistentes de erro real em produção), mas **não é texto de documentação oficial** — é reconstrução a partir de mensagens de erro reportadas por desenvolvedores. Recomendo ao `coder-runtime`/`coder-services` reproduzir esse padrão de string ao implementar o erro simulado, mas sem tratar como 100% garantido caractere-por-caractere (ex: não confirmei se a pontuação final tem ou não um ponto final).

### D.3 — Dimensionamento para o arquiteto

Contagem exata feita diretamente no dump local pinado (`28360dea...json`, 8 006 149 bytes / ~7.6 MB):
- **629 enums** na seção `Enums`.
- **3611 EnumItems no total** (soma de todos os `Items` de todos os enums).
- Isso já faz parte do mesmo arquivo de 8 MB que cobre `Classes` — **não é uma segunda fonte de dados a carregar**, é uma seção a mais dentro do mesmo JSON já cacheado. A regra de performance do projeto (`.claude/rules/01-luau.md`, seção "Performance": não reparsear o dump inteiro a cada `luaubench run`) **já cobre isso** — não há decisão nova de cache necessária além da que já existe para `Classes`.
- Custo de manter os 3611 EnumItems como objetos internados em memória (ver D.2) é desprezível (cada um é `{Name, Value, EnumType}`, não há overhead de propriedades/eventos como as classes de `Services`).

---

## Incerto (não confirmado por fonte primária)

1. **Comportamento de `Color3.new`/`Color3.fromRGB` fora do range declarado** (ex. `Color3.new(1.5, 0, 0)` ou `Color3.fromRGB(300, 0, 0)`): a doc oficial só diz "should be within the range of 0 to 1/255", **não** diz se clampa, lança erro ou aceita sem modificar (permitindo HDR). Encontrei uma thread de devforum ("Remove clamping on Color3 values") pedindo a remoção de clamping, o que sugere que **existe** algum clamping em algum lugar do pipeline de render, mas nenhuma resposta oficial de staff confirma o comportamento exato do datatype em si (fora do contexto de render). **Não implemente clamping automático sem essa confirmação** — se implementar, documente como suposição explícita.
2. **`Color3.fromRGB` arredonda o input?** (ex. `fromRGB(127.5, 0, 0)`) — não encontrado em nenhuma fonte.
3. **Unário `-` e `==` explícitos para `UDim`/`UDim2`** (o usuário pediu para confirmar especificamente) — a seção `math_operations` do YAML não documenta nenhum dos dois, mas essa seção comprovadamente **não documenta unário nem igualdade para nenhum datatype** (nem para `Vector3`, que definitivamente suporta ambos) — então a ausência não prova ausência real no motor. Recomendo tratar como "provavelmente suporta `==` por valor, como todo datatype de valor do Roblox" mas **não fiz teste direto no Studio/cliente real** (fora do escopo read-only desta pesquisa) e não achei uma citação textual isolada.
4. **`tostring(UDim.new(...))` isolado** — inferido como `"{Scale, Offset}"` pelo padrão de `UDim2`, mas não há exemplo literal isolado de `print(UDim.new(...))` nas fontes que encontrei.
5. **Identidade (`rawequal`) de `EnumItem`** — ver D.2, é inferência de arquitetura + uso corrente na comunidade, não citação direta de nenhuma fonte oficial.
6. **Texto exato/pontuação das mensagens de erro de Enum inválido** — reconstruído de múltiplos relatos de devforum, não de documentação oficial; padrão confirmado mas caracteres exatos (aspas, ponto final) podem variar entre versões do engine.
7. **`NumberRange.new(minimum, maximum)` com `minimum > maximum`** — doc diz que deve ser `<=`, não diz o que acontece se violado (erro? swap automático? undefined?).
8. Não pesquisei os enums `Deprecated` individualmente além dos 6 que têm `Tags` no nível do enum e os 152 itens com `Tags` no nível do item — não fiz um levantamento de *quais* enums/itens especificamente são candidatos a "implementar só se algum projeto real depender" (regra 03) — isso é trabalho para quando o `coder-services` for gerar o registro de enums, não desta pesquisa.

---

## Resumo para quem vai implementar

- `Color3`: **sem operadores aritméticos** — só `Lerp`/`ToHSV`/`ToHex`. `tostring` = `"R, G, B"`.
- `UDim`/`UDim2`: só `+`/`-` documentados; `UDim2.new(x: UDim, y: UDim)` é overload real; `Width`/`Height` são sinônimos exatos de `X`/`Y`. `tostring(UDim2)` = `"{xS, xO}, {yS, yO}"`.
- `TweenInfo.new` ordem/defaults: `time=1, easingStyle=Quad, easingDirection=Out, repeatCount=0, reverses=false, delayTime=0` — todas as propriedades read-only.
- `BrickColor`: 4 overloads de `.new` + `.palette`/`.random`/8 constantes nomeadas; tabela canônica de 208 cores está embutida no YAML oficial de `BrickColor` (não em JSON separado) — precisa de extração.
- `Enum`: dump local já tem a seção `Enums` (629 enums, 3611 items, mesmo arquivo de 8 MB já cacheado — sem custo extra de I/O). Três datatypes (`Enums`→`Enum`→`EnumItem`) com métodos `GetEnums`/`GetEnumItems`/`FromName`/`FromValue`. Recomendo internar EnumItems como singletons na simulação.
