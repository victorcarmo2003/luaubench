# Arquiteto — Value Types simulados (`Vector3`/`CFrame`/`Color3`/`Enum`/...)

Desenho de `task-runtime-031`. Escopo NOVO GRANDE: o conjunto de tipos de VALOR do Roblox que hoje
não existem no LuauBench e que `src/cli/UnsimulatedGlobals.luau` apenas nomeia como lacuna.

Data: 2026-09-05. API Dump fixado: `0.737.0.7371584`, commit
`28360dea4b90b35dc3fe9f829baae64fb6c50e75` (`tools/api-dump.lock.json`), cópia local em
`.cache/api-dump/28360dea.json`.

---

## Propósito

Dar ao script do usuário os tipos de valor reais do Roblox (`Vector3`, `CFrame`, `Color3`, `Enum`,
`UDim`/`UDim2`, ...) como **userdata imutável com semântica de operador e precisão float32 fiéis**,
e dar a `services`/`cli` o vocabulário para tipar propriedades e decodificar `$properties` do Rojo.

---

## 0. Fatos apurados nesta sessão (empíricos, não de memória)

Tudo abaixo foi rodado de verdade contra o Lune instalado neste repositório, com scripts
descartáveis no scratchpad. Nenhuma linha desta seção é lembrança — quem for implementar pode
reproduzir cada uma em dois minutos.

### 0.1 O Luau do Lune TEM a biblioteca nativa `vector` — e ela NÃO serve como `Vector3`

```
typeof(vector.create(1,2,3))            -> "vector"   (tipo nativo da VM, não userdata)
tostring(vector.create(1,2,3))          -> "1, 2, 3"
vector.create(0.1,0,0).x                -> 0.10000000149011611938   (float32 nativo)
vector.create(1,2,3) + vector.create(1,2,3) -> operador nativo, funciona
vector.create(3,4,0).X                  -> 3          (aceita x/y/z E X/Y/Z)
vector.create(3,4,0).Magnitude          -> ERRO: "attempt to index vector with 'Magnitude'"
```

Chaves de `vector`: `abs, angle, ceil, clamp, create, cross, dot, floor, lerp, magnitude, max,
min, normalize, one, sign, zero`.

**O bloqueador**: o tipo nativo `vector` não tem metatable e **o Lune não expõe
`debug.setmetatable`** — a biblioteca `debug` do Lune tem exatamente duas chaves: `info` e
`traceback` (verificado por `pairs(debug)`). Sem `debug.setmetatable` não há como instalar
`.Magnitude`/`.Unit`/`:Cross()`/`:Dot()`/`:Lerp()` no tipo nativo. Como `(a - b).Magnitude` é
provavelmente a expressão mais comum de todo código Roblox real, **`vector` nativo está
descartado como representação de `Vector3`**.

O que ele continua servindo: como *oráculo de referência* para testes de precisão float32 (a
quantização de `buffer.writef32` bate BIT A BIT com a de `vector.create`, verificado).

**Achado do `pesquisador` que aperta esta decisão** (`pesquisa-datatypes-vector-cframe-2026-09-05.md`):
no Roblox moderno, `type(Vector3.new())` devolve **`"vector"`, não `"userdata"`** — a Roblox
migrou `Vector3` para esse mesmo tipo primitivo nativo da Luau. `Vector2` e `CFrame` continuam
`"userdata"`. Ou seja: o tipo que seria perfeito é literalmente o que a Roblox usa, e nós não
podemos usá-lo *porque o Lune não deixa dar metatable a ele*. A consequência é a divergência D8
(§8) — assumida conscientemente, não descoberta depois.

### 0.2 `buffer.writef32`/`readf32` dá float32 exato, de graça

```
buffer.writef32(b,0,0.1); buffer.readf32(b,0)  -> 0.10000000149011611938
                                               == vector.create(0.1,0,0).x   -> true
```

Uma ida-e-volta de 4 bytes por componente. O custo é irrelevante perto do custo de alocar o
userdata (medido abaixo). **Isto derruba a premissa da task de que "float32 é mais trabalho" —
não é: é uma função de três linhas.**

### 0.3 `newproxy(true)` entrega userdata com a fidelidade que precisamos

```
type(p)                        -> "userdata"     (como no Roblox real)
setmetatable(p, {})            -> ERRO "invalid argument #1 to 'setmetatable' (table expected, got userdata)"
pairs(p)                       -> ERRO "invalid argument #1 to 'pairs' (table expected, got userdata)"
getmetatable(p) com __metatable-> devolve a string travada, nunca a metatable real
__index/__newindex/__add/__sub/__unm/__eq/__tostring -> todos disparam
p == <userdata alheio>         -> chama nosso __eq, que devolve false sem erro
p == 5                         -> false, sem chamar __eq (tipos diferentes)
```

`newproxy(true)` já está na whitelist do sandbox desde `task-runtime-026` — nenhuma mudança de
superfície de segurança é necessária para isto.

### 0.4 Custo medido (200.000 construções + 200.000 somas)

| Representação | Tempo | Por operação |
|---|---|---|
| `vector` nativo | 0.002 s | ~10 ns |
| tabela + metatable compartilhada | 0.056 s | ~0.28 µs |
| `newproxy(true)` + metatable por instância | 0.637 s | ~3.2 µs |

`newproxy` é ~11x mais caro que tabela. **Aceito**: LuauBench é bancada de teste de lógica, não
motor de jogo. Um script que faz 10.000 operações vetoriais gasta 32 ms. Ver §6 para por que a
fidelidade de `type()` vale esse preço exato neste projeto.

### 0.5 Formatação float32 "shortest round-trip" reproduz o `tostring` do Roblox

Algoritmo: tentar `%.1g` .. `%.9g`, devolver o primeiro cujo `f32(tonumber(s)) == n`.

```
f32(0.1)      -> 0.10000000149011612   formatado -> "0.1"
f32(-0.7)     -> -0.699999988079071    formatado -> "-0.7"
f32(1/3)      -> 0.3333333432674408    formatado -> "0.33333334"
f32(123456.789) -> 123456.7890625      formatado -> "123456.79"
```

Note que `tostring` do `vector` nativo do Lune imprime `"0.10000000149011612, 0, 0"` — **não** é o
formato do Roblox. Nosso formatador precisa existir de qualquer jeito.

### 0.6 O dump TEM os dados que faltam

**Enums**: `Full-API-Dump.json` tem a seção `Enums` — **629 enums, 3611 itens**, no formato
`{"Name": "AccessModifierType", "Items": [{"Name":"Allow","Value":0}, ...]}`. Gerado como módulo
Luau plano dá **64 KB** e carrega em **8.5 ms** (medido). Menor que o `generated/Manifest.luau`
que já existe (101 KB).

**Defaults de DataType**: ao contrário do que o gerador atual assume (`Default = nil` para tudo
que não é `Primitive`), o dump traz o default serializado em forma legível:

| ValueType | Exemplo de `Default` no dump |
|---|---|
| `Vector3` | `"0, 0, 0"` |
| `Color3` | `"0, 0, 0"` |
| `CFrame` | `"0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1"` (posição + matriz 3x3) |
| `UDim` | `"0, 8"` |
| `NumberRange` | `"4 10000 "` (separado por espaço) |
| `NumberSequence` | `"0 0.5 0 1 0.5 0 "` (trincas tempo/valor/envelope) |
| `ColorSequence` | `"0 1 1 1 0 1 1 1 1 0 "` |
| `TweenInfo` | `"Time:1 DelayTime:0 RepeatCount:0 Reverses:False EasingDirection:Out EasingStyle:Quad"` |
| `Faces` | `"Right, Top, Back, Left, Bottom, Front"` |
| `Axes` | `"X, Y, Z"` |
| `Enum` | nome do item (`"Deny"`, `"Unknown"`) |

Sentinelas para o resto (`__api_dump_no_string_value__`, `__api_dump_class_not_creatable__`,
`__api_dump_failed_to_create_class__`, `__api_dump_skipped_class__`) — o gerador já tem
`isSentinelDefault`.

### 0.7 Frequência real no dump (define prioridade, ver §7)

`ValueType`/`ReturnType`/`Parameters` de todos os membros de todas as classes — **71 DataTypes
distintos**, dos quais os relevantes:

```
Vector3 354 | CFrame 180 | Color3 157 | Vector2 145 | UDim2 34 | NumberRange 26
BrickColor 26 | Region3 22 | Ray 15 | UDim 15 | Font 13 | Rect 13 | NumberSequence 7
Region3int16 7 | RaycastParams 5 | ColorSequence 4 | DateTime 3 | PhysicalProperties 3
OverlapParams 3 | Vector3int16 3 | Faces 2 | TweenInfo 2 | Axes 1
```

### 0.8 A lista de 22 nomes de `UnsimulatedGlobals.luau` está INCOMPLETA

Faltam nomes que o Roblox real expõe como global de valor e que aparecem no dump ou são
pré-requisito de um dos 22: **`NumberSequenceKeypoint`** e **`ColorSequenceKeypoint`** (sem eles é
impossível construir `NumberSequence`/`ColorSequence`), `Vector3int16`, `Vector2int16`,
`Region3int16`, `PathWaypoint`, `CatalogSearchParams`, `FloatCurveKey`, `RotationCurveKey`,
`Path2DControlPoint`, `SharedTable`, `Secret`, `Content`, `RaycastResult` (não construtível — só
retornado). Ver §3, `Catalog.luau`, que fecha esta lista de uma vez.

---

## 1. Decisão 1 — Território: **`src/valuetypes/` NOVO**

**Decisão: territóro novo `src/valuetypes/`, quarto ao lado de `runtime`/`services`/`cli`, com um
agente `coder-valuetypes` e um `revisor-valuetypes` próprios.**

### Por que NÃO `runtime`

Não é a regra 02 ("runtime não conhece Service específico") que decide — value type não é Service.
O que decide é a outra metade da mesma regra, literal: **"`runtime` nunca lê o API Dump
diretamente"**. `Enum` é 629 enums × 3611 itens **derivados do dump**, e os defaults de
`Vector3`/`Color3`/`CFrame` das propriedades também. Pôr `Enum` em `runtime` obriga `runtime` a
consumir dado do dump — violação direta e literal, não interpretativa. E `Enum` não é separável do
resto: `TweenInfo`, `Font`, `Faces`, `Axes`, `PhysicalProperties` todos dependem dele.

### Por que NÃO `services`

Três razões, em ordem de peso:

1. **Serializa 20 módulos independentes atrás de um agente só.** `Vector3`, `CFrame`, `Color3`,
   `UDim`, `Enum`... não compartilham arquivo e não têm dependência entre si além de uma base
   comum minúscula. É o conjunto de trabalho mais paralelizável que este projeto já teve. Enfiar
   tudo em `src/services/` desperdiça exatamente a propriedade que a regra 05 existe para
   preservar. Um território novo abre uma **quarta pista de escrita que nunca colide** com as
   outras três.
2. **A regra 03 inteira é sobre CLASSES.** "Toda classe de Service e toda propriedade/evento/método
   de qualquer Instance simulada"; "Service não coberto não é stub silencioso"; "prioridade de
   cobertura" listando `Workspace`/`Players`/`DataStoreService`. Value type não é Instance, não tem
   `Parent`, não tem evento, não é `GetService`-ável, não passa por `ClassRegistry`. Misturar as
   duas coisas faz `src/services/` significar duas coisas e apodrece a regra 03.
3. **Direção de dependência.** `services` depende de `runtime`. Se value types morassem em
   `services`, `runtime` (que precisa deles para `typeof` e para validar escrita de propriedade)
   dependeria de `services` — ciclo. Com território próprio, o grafo fica trivialmente acíclico
   (§2).

### Por que o overhead do território novo se paga

`src/valuetypes/` é, na leva 1, uma **folha pura do grafo de dependências**: `Vector3`, `Vector2`,
`CFrame`, `Color3`, `UDim`, `UDim2`, `Enum` não precisam de NADA de `runtime`, `services` ou `cli`.
Nenhum outro território deste projeto tem essa propriedade. Um território que não depende de
ninguém é o caso mais forte possível de "isto é uma preocupação separada" — e o mais barato de
testar (spec sem `DataModel`, sem `Bootstrap`, sem fixture de projeto).

O custo é uma pasta, um agente e um revisor. O ganho é uma pista paralela permanente + um grafo
acíclico sem hook nenhum entre value types e o resto. Se em algum momento o território encolher a
três módulos, funde-se em `services` sem prejuízo. Não é uma porta de mão única.

### O que fica FORA do território novo

`tools/generate-enums.luau` (gerador offline) vive em `tools/`, que já é área compartilhada fora
dos três territórios `src/` (`tools/generate-services.luau` já mora lá). **Arquivo novo e
separado** — `coder-valuetypes` escreve `tools/generate-enums.luau`, `coder-services` continua dono
de `tools/generate-services.luau`. Arquivos distintos, zero colisão (regra 05: nunca o mesmo
arquivo para dois agentes).

---

## 2. Grafo de dependências (acíclico, verificável)

```
                    ┌──────────────┐
                    │  valuetypes  │  leva 1: FOLHA PURA (não requer ninguém)
                    │              │  leva 2: requer ../runtime SÓ pelo TIPO `Instance`
                    └──────┬───────┘     (RaycastParams.FilterDescendantsInstances)
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
   ┌────▼─────┐      ┌─────▼─────┐      ┌─────▼────┐
   │ runtime  │◄─────┤ services  │◄─────┤   cli    │
   └────┬─────┘      └───────────┘      └──────────┘
        │
        └── NUNCA requer valuetypes. Recebe um resolvedor injetado
            (Runtime.TypeNameResolver.Set), mesmo padrão já usado em
            UnknownClassResolver (task-runtime-030).
```

Regra de ouro deste desenho, e o único ponto onde um revisor precisa ser implacável:
**`src/runtime/**` nunca contém a string `valuetypes`.** A ponte é sempre um resolvedor injetado
pelo composition root (`cli`).

---

## 3. Módulos

Todo caminho abaixo é `--!strict`, sem `any`. Toda estrutura pública tem `export type`.

### 3.1 Base (território `valuetypes`)

#### `src/valuetypes/Float32.luau` — quantização e formatação numérica

Responsabilidade: fazer um `number` do Luau (double) se comportar como o `float`/`int32`/`int16`
que o Roblox guarda de verdade.

```luau
export type Formatter = (value: number) -> string

-- Quantiza para float32 via buffer.writef32/readf32 (§0.2). O buffer de 4 bytes é
-- module-local e reusado -- nunca alocado por chamada.
function Float32.Quantize(value: number): number

-- Arredonda para o inteiro mais próximo (half away from zero, como o Roblox) e satura em
-- [-2^31, 2^31-1]. Usado por UDim.Offset e UDim2 offsets.
function Float32.QuantizeInt32(value: number): number

-- Idem em [-32768, 32767]. Usado por Vector3int16/Vector2int16/Region3int16 (leva 2).
function Float32.QuantizeInt16(value: number): number

-- Shortest round-trip: menor precisão %g cujo tonumber() re-quantizado devolve o mesmo
-- float32 (§0.5). É o que faz tostring(Vector3.new(0.1,0,0)) imprimir "0.1, 0, 0" em vez
-- de "0.10000000149011612, 0, 0".
function Float32.Format(value: number): string

-- nan/inf/-inf com a grafia que o Roblox usa. PENDÊNCIA DE PESQUISA (§9, item P3).
function Float32.FormatSpecial(value: number): string?
```

Depende de: nada. Usado por: todo módulo de `types/`.

#### `src/valuetypes/Userdata.luau` — fábrica única de userdata imutável

Responsabilidade: **um único lugar** onde `newproxy(true)` é chamado neste projeto. Todo value
type nasce daqui. É a superfície de segurança inteira dos value types — ter duas cópias é
exatamente o tipo de divergência silenciosa que a regra 00 proíbe (mesmo argumento que
`Sandbox.buildEnvironment` já registra para a whitelist).

```luau
-- Estado interno de UMA instância: um array denso de números/valores, sem chave string
-- (evita alocar hash part). Nunca escapa deste território.
export type Fields = { unknown }

export type Descriptor = {
    -- Nome que `typeof()` deve devolver: "Vector3", "CFrame", "EnumItem", ...
    TypeName: string,
    -- Métodos de instância (`v:Dot(o)`). Tabela COMPARTILHADA e CONGELADA por tipo.
    Methods: { [string]: unknown },
    -- Propriedades calculadas/lidas (`v.X`, `v.Magnitude`). Recebe os Fields crus.
    GetProperty: (fields: Fields, key: string) -> (unknown, boolean),
    Format: (fields: Fields) -> string,
    -- Metamétodos aritméticos opcionais. `nil` = operador não suportado pelo tipo, e o
    -- erro que o Luau levanta sozinho já é o certo ("attempt to perform arithmetic").
    Add: ((a: Fields, b: Fields, bTypeName: string) -> unknown)?,
    Sub: ((a: Fields, b: Fields, bTypeName: string) -> unknown)?,
    Mul: ((a: unknown, b: unknown) -> unknown)?,   -- recebe os operandos crus: Vector3*number
    Div: ((a: unknown, b: unknown) -> unknown)?,
    IDiv: ((a: unknown, b: unknown) -> unknown)?,
    Unm: ((a: Fields) -> unknown)?,
    -- Igualdade componente a componente. Só é chamado quando AMBOS os lados são userdata
    -- NOSSO e do MESMO TypeName -- a fábrica já filtra antes (§0.3).
    Equals: (a: Fields, b: Fields) -> boolean,
}

export type Factory = (fields: Fields) -> unknown

-- Registra um tipo e devolve a fábrica dele. Chamada UMA vez por tipo, no load do módulo
-- daquele tipo.
function Userdata.Define(descriptor: Descriptor): Factory

-- Nome de tipo Roblox de um valor, ou nil se não for value type nosso. Alimenta
-- ValueTypes.TypeNameOf -> Runtime.TypeNameResolver (Decisão 4).
function Userdata.TypeNameOf(value: unknown): string?

-- Campos crus de um valor NOSSO. Só para uso interno do território (um tipo lendo outro:
-- CFrame lendo os componentes de um Vector3). Erra se o valor não for do TypeName pedido --
-- é o que dá a mensagem certa em `CFrame.new(1, "x", 3)`.
function Userdata.Unwrap(value: unknown, expectedTypeName: string): Fields
```

Invariantes que a fábrica garante, e que nenhum tipo individual pode afrouxar:

1. `__metatable` **sempre** travado com a string do Roblox (`"The metatable is locked"` —
   confirmar grafia exata, §9 item P4). O script nunca alcança nossos closures.
2. `__newindex` **sempre** erra — value type do Roblox é imutável.
   Exceção: `RaycastParams`/`OverlapParams` são MUTÁVEIS no Roblox real (§7, leva 2) — usam um
   `Descriptor` com `SetProperty`, e isso é declarado explicitamente lá, nunca por omissão.
3. Estado em side-table `__mode = "k"` module-local (não alcançável do sandbox). Chave fraca:
   quando o script solta a referência, o estado é coletado junto.
4. `__eq` só chama `Equals` se os dois lados forem userdata registrado e do mesmo `TypeName`;
   caso contrário devolve `false` sem erro (§0.3, verificado contra userdata alheio).

Depende de: `Float32.luau`. Usado por: todo `types/*`.

#### `src/valuetypes/Catalog.luau` — a lista fechada, fonte única

Responsabilidade: encerrar de vez a divergência entre "o que existe no Roblox como global de
valor", "o que já simulamos" e "o que `cli` deve transformar em sentinela de erro".

```luau
export type CatalogEntry = {
    Name: string,
    -- true = há um módulo em types/ e o global é real. false = ainda vira sentinela em
    -- cli/UnsimulatedGlobals.luau, com a mensagem nomeada de sempre.
    Simulated: boolean,
    -- false para RaycastResult, Content, Secret, SharedTable...: existem como VALOR no
    -- Roblox mas não têm construtor global. Nunca viram global nenhum -- nem real, nem
    -- sentinela (uma sentinela para um nome que o Roblox também não expõe seria uma
    -- mensagem MENTIROSA: diria "LuauBench não simula" quando o certo é `nil`, como no
    -- Roblox real).
    HasGlobalConstructor: boolean,
}

function Catalog.All(): { CatalogEntry }
function Catalog.SimulatedNames(): { string }
function Catalog.UnsimulatedGlobalNames(): { string }  -- Simulated=false E HasGlobalConstructor=true
```

**Esta é uma extensão deliberada do LuauBench, não conteúdo do dump** — datatypes não vivem em
`Full-API-Dump.json` (só são referenciados por nome nos `ValueType` das classes). Fica em módulo
próprio do LuauBench, claramente distinto, exatamente como a regra 00 permite. O cabeçalho do
arquivo declara isso e cita a fonte de cada nome (doc oficial + `ValueType` do dump).

`cli/UnsimulatedGlobals.luau` passa a **derivar** sua lista de `Catalog.UnsimulatedGlobalNames()`
em vez de manter as 22 strings à mão. Consequência que vale mais que a economia: quando a leva 2
marcar `Simulated = true` em `Font`, a sentinela some sozinha — sem ninguém lembrar de editar dois
arquivos em territórios diferentes.

#### `src/valuetypes/Decode.luau` — gramática de valor do `.project.json`

Responsabilidade: resolver a forma **ambígua** do `$properties` do Rojo. É a única coisa nova de
verdade em `cli` e não pode ser feita lá: a pesquisa do Rojo
(`.claude/agents-memory/pesquisa-formato-projeto-rojo-2026-09-05.md`, seção "Formato de
`$properties`") confirma que Rojo resolve `[1, 2, 3]` **contra o banco de reflection, por classe +
propriedade** — o mesmo array é `Vector3` em `Part.Position` e `Color3` em `Lighting.Ambient`.
Sem o `ValueType` alvo, decidir é adivinhar.

```luau
export type DecodeSuccess = { Ok: true, Value: unknown }
export type DecodeFailure = { Ok: false, Reason: string }  -- frase pronta, sem prefixo
export type DecodeResult = DecodeSuccess | DecodeFailure

-- `raw` é o JSON já parseado (cli/JsonValue.luau). `valueTypeName` vem do
-- MemberDescriptor.ValueType do schema (Decisão 3). `valueCategory` distingue
-- "DataType" de "Enum" (uma string "Plastic" em Enum.Material vs. em uma propriedade string).
function Decode.FromRojoJson(
    valueTypeName: string,
    valueCategory: string,
    raw: unknown
): DecodeResult
```

Nunca lança — devolve `DecodeFailure` com a frase, e `cli` decide se vira warning ou erro (hoje é
warning `plan/non-primitive-property`; ver Decisão 5).

Depende de: `types/*`, `Catalog.luau`. Usado por: `cli`.

#### `src/valuetypes/init.luau` — superfície pública única

`services`/`cli` fazem `require("../valuetypes")`. Nunca `require("../valuetypes/types/Vector3")`
— mesmo contrato que `runtime`/`services` já têm.

```luau
export type Vector3 = Vector3Module.Vector3   -- opaco; ver nota abaixo
export type CFrame = CFrameModule.CFrame
-- ... um export type por tipo

local ValueTypes = {
    Vector3 = { new = ..., zero = ..., one = ..., xAxis = ..., ... },
    Vector2 = { ... },
    CFrame  = { ... },
    Color3  = { ... },
    UDim    = { ... },
    UDim2   = { ... },
    Enum    = EnumRoot,      -- o objeto `Enum` global inteiro (Decisão 6)

    -- Para cli/ScriptEnvironment: tabela NOVA a cada chamada, com as chaves dos tipos
    -- simulados prontas para virar global. Mesmo contrato de UnsimulatedGlobals.Build().
    BuildGlobals = function(): { [string]: unknown } ... end,

    -- Para cli/RunCommand: alimenta Runtime.TypeNameResolver.Set (Decisão 4).
    TypeNameOf = function(value: unknown): string? ... end,

    Decode = { FromRojoJson = ... },
    Catalog = { SimulatedNames = ..., UnsimulatedGlobalNames = ... },
}
```

**Nota de tipagem (importante para quem escrever)**: o valor em runtime é `userdata`, e o Luau não
deixa declarar campos em `userdata`. O `export type Vector3` é portanto um tipo **nominal opaco**
(`export type Vector3 = typeof(setmetatable({} :: { X: number, Y: number, Z: number, ... }, {}))`
ou equivalente) usado só para assinatura entre módulos — nunca para prometer ao Luau que a
indexação é checada em tempo de compilação, porque não é: quem checa é `__index` em runtime. Isso
é **divergência declarada** (§8): no Roblox real, o `luau-lsp` tem os tipos nativos e checa em
tempo de análise; aqui a checagem é só em runtime. A alternativa (gerar um `.d.luau` de tipos) fica
explicitamente fora do escopo (§10).

### 3.2 Tipos da leva 1 (território `valuetypes`)

Um módulo por tipo em `src/valuetypes/types/`. Cada um: `--!strict`, `export type`, construtores
estáticos, constantes, propriedades, métodos, operadores — **toda assinatura confirmada contra os
relatórios de pesquisa**, nunca de memória:

- `.claude/agents-memory/pesquisa-datatypes-vector-cframe-2026-09-05.md` — `Vector3`, `Vector2`,
  `CFrame`
- `.claude/agents-memory/pesquisa-datatypes-color-udim-enum-2026-09-05.md` — `Color3`, `UDim`,
  `UDim2`, `Rect`, `NumberRange`, `TweenInfo`, `BrickColor`, `Enum`

| Módulo | Depende de |
|---|---|
| `types/Vector3.luau` | `Float32`, `Userdata` |
| `types/Vector2.luau` | `Float32`, `Userdata` |
| `types/CFrame.luau` | `Float32`, `Userdata`, `types/Vector3` |
| `types/Color3.luau` | `Float32`, `Userdata` |
| `types/UDim.luau` | `Float32`, `Userdata` |
| `types/UDim2.luau` | `Float32`, `Userdata`, `types/UDim` |
| `types/Enum.luau` | `Userdata`, `generated/EnumData` |
| `generated/EnumData.luau` | nada (dados puros, gerado) |

**`Enum` são TRÊS tipos, não um** — confirmado pelo `pesquisador` contra a doc oficial, e o
desenho tem que refletir isso ou o `typeof` sai errado:

| Valor | `typeof()` | Superfície |
|---|---|---|
| o global `Enum` | `"Enums"` | `:GetEnums()` |
| `Enum.KeyCode` | `"Enum"` | `:GetEnumItems()`, `:FromName(n)`, `:FromValue(v)` |
| `Enum.KeyCode.Space` | `"EnumItem"` | `.Name`, `.Value`, `.EnumType`; `tostring` = `"Enum.KeyCode.Space"` |

`types/Enum.luau` define os três via `Userdata.Define` (três `TypeName` distintos) e constrói
**preguiçosamente e com memoização por enum**: tocar `Enum.KeyCode` materializa os `EnumItem`
daquele enum e só dele. Os itens são **internados** (a mesma referência para o mesmo item, sempre)
— o `pesquisador` não conseguiu confirmar por doc oficial se o Roblox garante identidade
(`rawequal`) ou só igualdade por valor, então internar é a escolha segura: satisfaz `==` de
qualquer jeito e ainda satisfaz `rawequal` se for o caso. Registrado como P7 (§9).

**`Color3` não tem operador aritmético** — `math_operations: []` na doc oficial, confirmado. O
`Descriptor` dele passa `Add`/`Sub`/`Mul`/`Div`/`Unm` como `nil`, e o erro que o Luau levanta
sozinho ("attempt to perform arithmetic") já é o comportamento certo. Não inventar `+` porque
"parece razoável".

**Assimetrias reais entre `Vector3` e `Vector2`** que o coder tem que respeitar em vez de
copiar-e-colar: `Vector2` **não tem** `//`; `Vector2:Cross()` devolve `number` (o de `Vector3`
devolve `Vector3`); `Vector2:Max/Min` aceitam tupla variádica e os de `Vector3` só um argumento;
os três `FuzzyEq` usam algoritmos de epsilon diferentes entre si (default `1e-5` nos três).

`coder-valuetypes` **não escreve assinatura que não esteja no relatório de pesquisa.** Item não
confirmado pela pesquisa não é implementado por adivinhação: fica de fora e o relatório da tarefa
diz que ficou (regra 00 — "dado dúvida sobre comportamento real, `pesquisador` confirma antes de
implementar").

### 3.3 Ferramenta offline

`tools/generate-enums.luau` — lê `.cache/api-dump/<commit>.json`, emite
`src/valuetypes/generated/EnumData.luau` (64 KB, §0.6). Espelha `tools/generate-services.luau`:
mesmo `api-dump.lock.json`, mesmo padrão de cabeçalho "GERADO — não editar à mão", mesmo relatório
de contagem no fim. Roda por decisão explícita, nunca a cada build (regra 03: versão do dump é
fixada, atualizar é decisão).

### 3.4 Mudanças nos territórios existentes

#### `runtime` (`coder-runtime`)

**(a) `src/runtime/TypeNameResolver.luau` — módulo novo.** Cópia estrutural de
`UnknownClassResolver.luau` (task-runtime-030), o precedente exato: `runtime` precisa de um fato
que só outro território sabe, e o recebe injetado.

```luau
export type TypeNameResolver = (value: unknown) -> string?
function TypeNameResolver.Set(resolver: TypeNameResolver): ()
function TypeNameResolver.Resolve(value: unknown): string?   -- interno, NÃO reexportado em init
```

`init.luau` reexporta **só `Set`** e o tipo — mesmo precedente literal de
`UnknownClassResolver` (o cabeçalho de `runtime/init.luau` já explica por quê).

**(b) `typeof` do sandbox deixa de ser o `typeof` do Luau cru.** Hoje
`Sandbox.buildEnvironment` faz `env.typeof = typeof`. Passa a ser um wrapper:

```
1. É Instance nossa?              -> "Instance"                (runtime sabe sozinho)
2. É Signal nosso?                -> "RBXScriptSignal"         (runtime sabe sozinho)
3. É Connection nossa?            -> "RBXScriptConnection"     (runtime sabe sozinho)
4. TypeNameResolver.Resolve(v)    -> "Vector3"/"CFrame"/"EnumItem"/...
5. senão                          -> typeof(v) nativo do Luau
```

Isto corrige de quebra três bugs de fidelidade **que já existem hoje** e que ninguém tinha
registrado: `typeof(workspace)` devolve `"table"` (Roblox: `"Instance"`),
`typeof(part.Touched)` devolve `"table"` (Roblox: `"RBXScriptSignal"`), idem `Connection`. Não é
escopo inventado — é o mesmo `env.typeof` sendo tocado uma vez só, e deixar os três quebrados
enquanto se conserta o quarto seria arbitrário.

**(c) `MemberDescriptor` ganha o tipo da propriedade.** Hoje é
`{ Kind, Default, ReadOnly }` — o tipo declarado da propriedade **não existe em lugar nenhum do
runtime**, e sem ele nem `cli` decodifica `$properties` nem `Instance.__newindex` sabe o que
rejeitar.

```luau
export type MemberValueCategory = "Primitive" | "DataType" | "Enum" | "Class" | "Group"

export type MemberDescriptor = {
    Kind: MemberKind,
    Default: unknown,
    ReadOnly: boolean,
    -- NOVOS. `nil` só para Kind ~= "Property" (Event/Callback/Function não têm ValueType).
    ValueType: string?,          -- "Vector3", "Color3", "Material", "string", ...
    ValueCategory: MemberValueCategory?,
}
```

Campos **opcionais** de propósito: todo `ClassSchema` já escrito (24 classes geradas + specs
com classes fictícias) continua válido sem edição, e o modo estrito/leniente de `Instance.luau`
não muda de comportamento. É aditivo puro.

**Escopo explícito desta leva: `runtime` NÃO passa a validar escrita por `ValueType`.** O campo
entra como dado disponível; usar isso para rejeitar `part.Position = "abc"` é decisão separada
(§10), porque exige responder o que o Roblox faz com coerção implícita (`part.Size = 5`?) e isso
não foi pesquisado. Meia-validação seria pior que nenhuma.

#### `services` (`coder-services`)

**(a) O gerador emite `ValueType`/`ValueCategory`** por propriedade — é uma leitura direta do
`member.ValueType` que `generate-services.luau` **já parseia hoje** (`luauTypeForValueType` usa
`vt.Category`/`vt.Name` e joga fora); passa a também emitir.

**(b) O gerador emite defaults reais de DataType e Enum.** `computeDefault` hoje devolve `nil`
para tudo que não é `Primitive` (§0.6 mostra que o dado está lá). Passa a parsear as gramáticas da
tabela do §0.6 e emitir uma chamada de construtor no módulo gerado
(`Default = ValueTypes.Vector3.new(0, 0, 0)`). Consequência: `generated/classes/*.luau` passa a
`require("../../valuetypes")`, e `services` passa a depender de `valuetypes` — direção correta do
grafo (§2).

Consequência boa e mensurável: `Lighting.Ambient` deixa de nascer `nil` (hoje) e nasce
`Color3.new(0, 0, 0)`, como no Roblox real. Idem ~600 propriedades nas 24 classes cobertas.

**(c) O tipo Luau do campo gerado** deixa de ser `unknown` para DataType/Enum e passa a ser
`ValueTypes.Vector3`/`ValueTypes.EnumItem`/etc. (`luauTypeForValueType`).

#### `cli` (`coder-cli`)

**(a) `TreePlanner`**: `PlanPropertyValue` deixa de ser `boolean | number | string`. `$properties`
não-primitivo para de virar warning `plan/non-primitive-property` **quando o alvo é decodificável**
— ver Decisão 5 para a mecânica exata (o `ValueType` só é conhecido na materialização, não no
planejamento).

**(b) `ScriptEnvironment.Build`**: sobrepõe `ValueTypes.BuildGlobals()` por cima de
`UnsimulatedGlobals.Build()`, antes de `game`/`workspace`/`script`. Uma linha.

**(c) `UnsimulatedGlobals`**: lista derivada de `Catalog.UnsimulatedGlobalNames()`.

**(d) `RunCommand`**: `Runtime.TypeNameResolver.Set(ValueTypes.TypeNameOf)` uma vez, ao lado da
chamada de `Services.Bootstrap` que já existe. **`cli` é o composition root** — é onde a ponte
`runtime ← valuetypes` é atada, explicitamente, num lugar só e visível. (`services` poderia
fazê-lo em `Bootstrap`, mas aí `typeof` correto passaria a depender de os Services terem sido
inicializados, o que não tem relação nenhuma com value type.)

---

## 4. Decisão 2 — Representação: **userdata via `newproxy(true)`**

Alternativas medidas em §0.3/§0.4. Tabela congelada com metatable é 11x mais rápida. Foi
rejeitada, e a razão é específica **deste** projeto, não estética:

O caso de uso central declarado no `CLAUDE.md` é *"ProfileStore, data managers"*. Todo serializer
desse tipo de código tem esta forma:

```luau
local function serialize(value)
    if type(value) == "table" then
        for k, v in value do ... end     -- desce recursivamente
    end
end
```

Com value type representado como **tabela**, `serialize(Vector3.new(1,2,3))` desceria dentro do
Vector3 e o serializaria como um dicionário — **silenciosamente**, sem erro, produzindo um dado
corrompido salvo no DataStore simulado. O usuário rodaria o LuauBench, veria "funcionou", e
descobriria o bug em produção. Isso é exatamente o modo de falha que a invariante 2 do projeto
existe para impedir ("divergência não declarada é um bug silencioso que engana quem confia na
ferramenta").

Com userdata (§0.3): `type()` devolve `"userdata"`, `pairs()` erra igual ao Roblox, `setmetatable`
erra igual ao Roblox, `__metatable` travado. **A fidelidade que compramos com os 3 µs é
precisamente a que protege o caso de uso número um do projeto.** Se algum cenário real medir
lentidão inaceitável, a saída é otimizar o caminho quente com o oráculo `vector` nativo (§0.1) —
decisão futura, com dado na mão, não agora.

**O que o achado do `pesquisador` muda e o que não muda.** Como `type(Vector3.new())` é `"vector"`
no Roblox real (§0.1) e será `"userdata"` aqui, a igualdade de `type()` não é atingida para
`Vector3` (é para `Vector2` e `CFrame`, que são `"userdata"` no Roblox também). Mas **o argumento
do serializer sobrevive inteiro e é o que importa**: `"vector"` e `"userdata"` são ambos
não-`"table"`, então o `if type(v) == "table"` de um data manager real toma o mesmo ramo nos dois
mundos. O que estava em jogo era "value type não pode ser confundido com tabela" — e isso está
garantido. A diferença residual entre `"vector"` e `"userdata"` só aparece em código que testa
`type(v) == "vector"` explicitamente, o que é raríssimo e fica declarado em D8.

---

## 5. Decisão 3 — Precisão: **simular float32, sem exceção**

A task pedia para ponderar fidelidade vs. pragmatismo. **A ponderação não se aplica**: §0.2 mostra
que float32 exato custa uma função de três linhas e uma ida-e-volta de 4 bytes, verificada
bit a bit contra o `vector` nativo do Luau. Não há trade-off para negociar.

Regra: **quantizar no construtor privado único de cada tipo.** Como todo resultado de operador
passa pelo mesmo construtor, toda a aritmética fica automaticamente encadeada em float32 — igual
ao Roblox, e sem nenhum código extra por operador.

| Campo | Quantização |
|---|---|
| `Vector3.X/Y/Z`, `Vector2.X/Y` | float32 |
| `CFrame` — os 12 componentes | float32 |
| `Color3.R/G/B` | float32 |
| `UDim.Scale`, escalas de `UDim2` | float32 |
| `UDim.Offset`, offsets de `UDim2` | **int32** (arredonda + satura) |
| `NumberRange`, `Rect`, `Ray`, sequences (leva 2) | float32 |
| `Vector3int16`/`Vector2int16`/`Region3int16` (leva 2) | **int16** |

Divergências que **permanecem** e vão declaradas em comentário no código (§8, D1–D3): ordem de
operações internas do Roblox em `.Magnitude`/`:Lerp()`/multiplicação de `CFrame`, que podem
diferir no último ulp; e o formato de `nan`/`inf`.

---

## 6. Decisão 4 — Exposição no sandbox (segurança)

Mesma disciplina do `Sandbox.luau` atual, sem nenhuma frouxidão nova:

1. **Whitelist explícita, sem metatable no `env`.** `ScriptEnvironment.Build` continua montando
   uma tabela de chaves nomeadas. Nenhum `__index` de fallback é adicionado — indexar um global
   ausente continua devolvendo `nil` puro (garantia já documentada no cabeçalho de `Sandbox.luau`).
2. **Zero capacidade nova concedida.** Todo construtor de value type é função pura sobre
   `number`/`string`/outro value type. Nenhum toca `fs`/`net`/`process`/`serde`/`io`. A auditoria
   caso a caso da leva 1: `Vector3`/`Vector2`/`CFrame`/`Color3`/`UDim`/`UDim2` = aritmética pura;
   `Enum` = leitura de tabela congelada gerada offline. **Nada** na leva 1 lê relógio, ambiente,
   disco ou rede.
3. **`__metatable` travado em todo value type** (§0.3): o script não lê nossos closures nem troca
   a metatable de um valor compartilhado. É *mais* fechado que a `Instance` de hoje era antes de
   `task-runtime-027`.
4. **Estado em side-table module-local com chave fraca.** Não é alcançável do sandbox: a tabela é
   upvalue de `Userdata.luau`, e `Userdata` nunca entra em `env`.
5. **Constantes compartilhadas são seguras.** `Vector3.zero`, `CFrame.identity`, cada `EnumItem` —
   construídos uma vez no load e reusados entre scripts e entre runs. São imutáveis por construção
   (`__newindex` erra) — mesmo argumento que os `SENTINELS` de `UnsimulatedGlobals.luau` já usam.
6. **Riscos da leva 2, decididos agora para não virarem decisão de coder** (regra 02: simplificação
   é decisão do arquiteto):
   - **`Random`**: PRNG **próprio**, estado por instância. **Proibido** chamar `math.randomseed` —
     o sandbox compartilha a tabela `math` do host por referência (`env.math = math`), então mexer
     na semente global deixaria um script perturbar o RNG do processo inteiro do LuauBench.
     (Nota de acompanhamento, fora deste escopo: isso já é verdade hoje, um script já pode chamar
     `math.randomseed` direto. Registrado aqui porque foi descoberto ao auditar isto; não é
     causado por este desenho.)
   - **`DateTime`**: lê o relógio via as MESMAS `os.time`/`os.date` já na whitelist. Nenhuma
     leitura nova.
   - **`RaycastParams`/`OverlapParams`**: guardam `{Instance}` em `FilterDescendantsInstances`.
     Guardam **a referência que o script já tem** — nenhum caminho novo até o `DataModel`.

---

## 7. Decisão 5 — `$properties` do Rojo: onde o `ValueType` entra

O problema, concreto (do `default.project.json` real do projeto **Tiktok**, o template do
`rojo init`, testado pelo `testador`):

```json
"Lighting":  { "$properties": { "Ambient":  [0.5, 0.5, 0.5] } },   ->  Color3
"Baseplate": { "$properties": { "Position": [0, -10, 0],
                                "Size":     [512, 20, 512] } }      ->  Vector3
```

Mesma forma JSON, tipos alvo diferentes. Rojo resolve pelo banco de reflection; nós resolvemos
pelo `MemberDescriptor.ValueType` (§3.4-runtime-c).

**A dificuldade de sequenciamento**, e por que ela decide o desenho: `TreePlanner` roda **antes** de
qualquer Instance existir — não há schema, logo não há `ValueType` disponível ali. Quem tem o
schema é `TreeMaterializer`, que já chama `applyProperties` sobre a Instance real.

**Decisão**: o valor bruto (`unknown`, o JSON parseado) **atravessa o plano intacto**, e a
decodificação acontece em `TreeMaterializer.applyProperties`, que é o primeiro ponto onde o
`ValueType` é conhecível.

- `TreePlanner.PlanPropertyValue` passa de `boolean | number | string` para
  `boolean | number | string | JsonValue.JsonValue` (i.e., a forma bruta), e **para de emitir**
  `plan/non-primitive-property` — deixa de ser uma decisão do planejador.
- `TreeMaterializer.applyProperties`, por propriedade: lê o `MemberDescriptor` do schema →
  `ValueTypes.Decode.FromRojoJson(descriptor.ValueType, descriptor.ValueCategory, raw)` → em
  `Ok`, escreve; em falha, emite **`materialize/undecodable-property`** citando nó, propriedade,
  tipo alvo e o motivo devolvido pelo `Decode`.
- Propriedade cujo `ValueType` aponta para um tipo ainda **não simulado** (leva 2): warning
  `materialize/property-type-not-simulated` com o prefixo `[LuauBench]` — **sem contraparte real**
  (no Roblox isso funcionaria), então a regra de idioma dos erros exige o prefixo, exatamente como
  `Messages.UnsimulatedGlobal` já faz.

Nunca escrever valor inventado, nunca falhar silenciosamente — é a mesma postura que o `testador`
já elogiou no comportamento atual, só que agora o caminho feliz existe de verdade.

---

## 8. Fidelidade vs. pragmatismo — divergências declaradas

Toda linha desta tabela vira comentário `--` no código do módulo correspondente (regra 00: nunca
silenciosa) e é repetida no relatório da tarefa que a introduzir.

| # | Divergência | Onde | Por quê |
|---|---|---|---|
| D1 | Ordem de operações internas pode diferir no último ulp em `.Magnitude`, `:Lerp()`, `CFrame * CFrame`. Componentes de entrada/saída são float32 exatos; o caminho *interno* usa double. | `types/*` | Reproduzir a ordem exata do motor exigiria o código-fonte fechado do Roblox. Erro relativo ~1e-7, invisível a lógica de jogo. |
| D2 | `tostring` usa shortest-round-trip float32 (§0.5). Reproduz `"0.1"`, `"−0.7"`, `"0.33333334"` — mas o formato exato do Roblox não foi confirmado byte a byte. | `Float32.Format` | Pendência P2 (§9). Aproximação de boa-fé, marcada como tal — mesmo protocolo que `Services.new` já usa para mensagem de família Roblox não confirmada. |
| D3 | `nan`/`inf` podem imprimir diferente do Roblox. | `Float32.FormatSpecial` | Pendência P3 (§9). |
| D4 | Sem checagem de tipo em tempo de ANÁLISE. No Studio o `luau-lsp` conhece `Vector3` nativamente e acusa `Vector3.new(1,2,3).Nope` antes de rodar; aqui o erro só aparece em runtime, via `__index`. | `init.luau` (tipos opacos) | Exigiria emitir definições de tipo Luau para o LSP do usuário — sistema próprio, fora deste escopo (§10). |
| D5 | `typeof()` só é fiel **dentro do sandbox**. Código de `services`/`cli` que chamar o `typeof` do Luau sobre um value type recebe `"userdata"`, não `"Vector3"`. | `Sandbox.buildEnvironment` | O `typeof` global do Luau não é substituível fora do ambiente que nós montamos. Território interno usa `ValueTypes.TypeNameOf`. |
| D6 | Value type do LuauBench não é o mesmo objeto que o do Roblox: um `Vector3` nosso não sobrevive a serialização binária `rbxm`/`rbxl`. | território todo | Ninguém no LuauBench escreve `rbxm` hoje. Vira problema quando/se isso existir. |
| D8 | **`type(Vector3.new())` devolve `"userdata"`; no Roblox moderno devolve `"vector"`** (tipo primitivo nativo da Luau). `Vector2`/`CFrame`/o resto conferem (`"userdata"` nos dois). `typeof()` devolve `"Vector3"` corretamente nos dois. | `types/Vector3.luau` | O Lune não expõe `debug.setmetatable`, logo o tipo `vector` nativo não pode ganhar `.Magnitude`/`.Unit`/`:Cross()` (§0.1). Impacto prático quase nulo: os dois são não-`"table"`, então todo `if type(v) == "table"` de serializer se comporta igual (§4). Reavaliar **só** se o Lune passar a expor `debug.setmetatable`. |
| D7 | Precisão de `CFrame` na composição de rotações: o Roblox re-ortonormaliza em alguns caminhos; quais, exatamente, não está documentado. | `types/CFrame.luau` | `:Orthonormalize()` é exposto como método explícito (existe no Roblox real); a re-ortonormalização *implícita* não é reproduzida. Pendência P1 (§9). |

---

## 9. Pendências de PESQUISA (bloqueiam parte da leva 1)

### CONCLUÍDAS — as duas pesquisas voltaram nesta sessão

- `.claude/agents-memory/pesquisa-datatypes-vector-cframe-2026-09-05.md` — `Vector3`/`Vector2`/
  `CFrame`. **Construtores, constantes, propriedades e métodos 100% confirmados** contra os YAML
  oficiais de `Roblox/creator-docs`, incluindo os 6 overloads de `CFrame.new` (0/1/2/3/7/12 args)
  com a ordem exata dos 12 componentes, e `lookAt`/`lookAlong`/`fromMatrix`/`fromAxisAngle`.
- `.claude/agents-memory/pesquisa-datatypes-color-udim-enum-2026-09-05.md` — `Color3`/`UDim`/
  `UDim2`/`Rect`/`NumberRange`/`TweenInfo`/`BrickColor` + `Enum`. Ordem e defaults de
  `TweenInfo.new` confirmados (`time=1, easingStyle=Quad, easingDirection=Out, repeatCount=0,
  reverses=false, delayTime=0`); overload `UDim2.new(x: UDim, y: UDim)` confirmado real;
  `Width`/`Height` são sinônimos exatos de `X`/`Y`; estrutura da seção `Enums` do dump confirmada
  lendo o dump local pinado.

**`coder-valuetypes` lê os dois arquivos antes de escrever qualquer assinatura.** Não repetir a
pesquisa; não escrever nada que não esteja neles.

### ABERTAS — o que ainda não tem fonte

| # | Pergunta | Bloqueia | Estado |
|---|---|---|---|
| P1 | O Roblox re-ortonormaliza `CFrame` implicitamente? Em quais operações? | só D7, não o módulo | aberta |
| P2 | Formatação decimal exata do `tostring` (dígitos significativos). O formato `"X, Y, Z"` (vírgula-espaço, sem parênteses) **está confirmado**; o número de dígitos tem só um exemplo de fórum, não spec. | `Float32.Format` (aproximação de §0.5 já definida) | parcial |
| P3 | Grafia de `nan`/`inf` no `tostring` do Roblox. | `Float32.FormatSpecial` | aberta |
| P4 | String exata de `__metatable` travado (`"The metatable is locked"`?). | `Userdata.luau` | aberta |
| P5 | ~~De onde vem a tabela canônica de `BrickColor`?~~ **RESPONDIDA**: as 208 cores estão embutidas como HTML **dentro do próprio YAML oficial** de `BrickColor` em `Roblox/creator-docs` — precisa de extração, mas a fonte existe e é oficial. | `types/BrickColor.luau` (leva 2) | resolvida — vira tarefa de extração, não de pesquisa |
| P6 | Tabela `Enum.Material` → densidade/fricção/elasticidade — **não está no API Dump**. | `types/PhysicalProperties.luau` (leva 2) | **aberta, bloqueia** |
| P7 | `EnumItem` tem identidade garantida (`rawequal(Enum.KeyCode.Space, Enum.KeyCode.Space)`) ou só igualdade por valor? | `types/Enum.luau` — **não bloqueia**: internar satisfaz as duas hipóteses (§3.2) | aberta, mitigada por design |
| P8 | `==` de `Vector3`/`CFrame` é exato componente a componente ou tem epsilon? Só inferência hoje. | `types/Vector3.luau`, `types/CFrame.luau` | aberta |
| P9 | Unário `-` e `==` em `UDim`/`UDim2` — a doc omite, mas omissão não é prova (o mesmo YAML omite para `Vector3`, que comprovadamente os tem). | `types/UDim.luau`, `types/UDim2.luau` | aberta |
| P10 | Texto literal do erro de `Enum` inválido e de `CFrame + CFrame`. | mensagens de erro | aberta |

**P6 é a única que bloqueia de verdade**: sem fonte de dado, `PhysicalProperties` seria inventar
valores — proibido pela invariante 1. Fica na leva 2 e **não pode subir**.

P8/P9/P10 são de baixo risco e não bloqueiam a leva 1: onde a pesquisa não confirmou, o coder
implementa a hipótese mais conservadora, **marca no código como aproximação de boa-fé não
confirmada** (mesmo protocolo que `Services.new` já usa para mensagem de família Roblox) e
registra no relatório da tarefa. O que ele **não** pode fazer é implementar em silêncio como se
fosse fato.

---

## 10. Prioridade — leva 1 e leva 2

### Honestidade sobre a evidência

A task pedia para basear a prioridade no uso observado em
`.claude/agents-memory/testador-roblox-games-2026-09-05.md`. **Reli o relatório: ele não sustenta
uma priorização em nível de script.** Nas duas rodadas, nenhum script de usuário chegou a chamar
`Vector3.new` — a primeira rodada parou em `plan/missing-class-name`, e a segunda parou em
`GetService("HttpService")` (Panic - CHESSS) ou em dependências Wally ausentes (TheGame). O único
contato real com value types foi via `$properties`: **Tiktok**, 4 warnings
`plan/non-primitive-property` em `Ambient`/`Position`/`Color`/`Size` — todos `Vector3`/`Color3`.

Isso é evidência **fraca mas direcional**, e eu declaro que é fraca em vez de inflá-la. A
priorização abaixo se apoia principalmente na evidência forte disponível: a **frequência no dump**
(§0.7) e as **dependências entre tipos** (o que é pré-requisito de quê).

### Leva 1 — o que desbloqueia o pipeline e o vocabulário comum

| Ordem | Item | Justificativa |
|---|---|---|
| 1 | Base: `Float32`, `Userdata`, `Catalog`, `init` | Pré-requisito de todo o resto. Único ponto de serialização da leva. |
| 2 | `Enum` + `tools/generate-enums.luau` + `generated/EnumData` | Maior alavanca isolada: **milhares** de propriedades no dump são `Category: "Enum"`; `$properties` resolve enum por nome de item (`"Material": "Plastic"`); `TweenInfo`/`Font`/`Faces`/`Axes`/`PhysicalProperties` todos dependem dele. Sem `Enum`, metade da leva 2 fica bloqueada. |
| 3 | `Vector3` + `Vector2` | 354 e 145 referências no dump — os dois primeiros lugares. É o par que os `$properties` reais do Tiktok pedem. |
| 4 | `Color3` | 157 referências; o outro tipo dos warnings reais observados. |
| 5 | `CFrame` | 180 referências (2º lugar). Depende de `Vector3`. |
| 6 | `UDim` + `UDim2` | 15 + 34. Todo código de UI. Baratos e sem dependência externa. |
| 7 | Ponte `runtime`: `TypeNameResolver` + `typeof` do sandbox + `MemberDescriptor.ValueType` | Sem isto, os tipos existem mas `typeof(v) == "Vector3"` é falso e `$properties` continua sem decodificar. |
| 8 | Ponte `services`: gerador emite `ValueType`/`ValueCategory` + defaults reais | Faz ~600 propriedades das 24 classes cobertas nascerem com o valor certo em vez de `nil`. |
| 9 | Ponte `cli`: `Decode` no `TreeMaterializer`, globals, `UnsimulatedGlobals` derivado, wiring do resolver | Fecha o ciclo: `$properties` do Tiktok deixa de ser warning. |

### Leva 2 — cauda longa

Agrupada por dependência, cada grupo paralelizável:

- **Sem dependência nova**: `Rect` (usa `Vector2`), `NumberRange`, `Ray` (usa `Vector3`),
  `Region3` (usa `Vector3`+`CFrame`), `Random`, `DateTime`, `Vector3int16`/`Vector2int16`/
  `Region3int16`.
- **Dependem de `Enum` (leva 1)**: `TweenInfo`, `Faces`, `Axes`, `Font`.
- **Precisam de keypoints, hoje ausentes da lista de 22 (§0.8)**: `NumberSequence` +
  `NumberSequenceKeypoint`, `ColorSequence` + `ColorSequenceKeypoint`.
- **Objetos MUTÁVEIS — forma diferente, decidir junto**: `RaycastParams`, `OverlapParams`,
  `CatalogSearchParams`. Não são value types imutáveis; têm propriedades escrevíveis. Usam
  `Userdata.Descriptor` com `SetProperty`, declarado explicitamente.
- **`BrickColor`**: desbloqueado (P5 resolvida) — vira uma tarefa de **extração** das 208 cores do
  HTML embutido no YAML oficial para um `generated/BrickColorData.luau`, não de pesquisa.
- **BLOQUEADO por pesquisa de dado (§9 P6)**: `PhysicalProperties`. Não entra em nenhuma leva até
  a tabela de materiais ter fonte confirmada.

---

## 11. Divisão por território

| Território | O que constrói | Contrato com o vizinho |
|---|---|---|
| **`valuetypes`** (NOVO, `coder-valuetypes`) | `Float32`, `Userdata`, `Catalog`, `Decode`, `init`, `types/{Vector3,Vector2,CFrame,Color3,UDim,UDim2,Enum}`, `generated/EnumData`, `tools/generate-enums.luau` | Expõe **só** `require("../valuetypes")`: construtores por tipo, `BuildGlobals()`, `TypeNameOf(value)`, `Decode.FromRojoJson(...)`, `Catalog.*`. Não requer `runtime`/`services`/`cli` na leva 1. |
| **`runtime`** (`coder-runtime`) | `TypeNameResolver.luau` (novo); `typeof` do sandbox; `MemberDescriptor.ValueType`/`ValueCategory`; reexports em `init.luau` | Recebe o resolvedor **injetado** por `cli`. **`src/runtime/**` nunca contém a string `valuetypes`.** |
| **`services`** (`coder-services`) | `tools/generate-services.luau`: emitir `ValueType`/`ValueCategory` + parsear defaults de DataType/Enum (§0.6); regerar as 24 classes | Passa a `require("../valuetypes")` nos módulos gerados. Consome `MemberDescriptor` estendido de `runtime`. |
| **`cli`** (`coder-cli`) | `TreePlanner` (valor bruto atravessa), `TreeMaterializer` (decode + 2 diagnósticos novos), `ScriptEnvironment` (overlay), `UnsimulatedGlobals` (derivado do `Catalog`), `RunCommand` (wiring do resolver), `Messages` | Requer `../valuetypes` só pelo agregador público. Único lugar que ata `runtime ← valuetypes`. |
| **`testador`** | Cenário `value-types-real-project.scenario.luau`: `luaubench run` no **Tiktok** real; asserta que os 4 warnings `plan/non-primitive-property` sumiram e que `Baseplate.Size`/`Lighting.Ambient` têm o valor certo | Read-only em `src/**`. |

**Ordem obrigatoriamente em série** (regra 05, dependência explícita `depends` no board):

```
base de valuetypes (1)
      ├──▶ Enum, Vector3/Vector2, Color3, UDim/UDim2   (paralelos entre si)
      │          └──▶ CFrame  (depende de Vector3)
      │
      ├──▶ runtime: TypeNameResolver + typeof + MemberDescriptor   (paralelo aos tipos —
      │                                                             só precisa do CONTRATO,
      │                                                             não da implementação)
      │          └──▶ services: gerador emite ValueType + defaults
      │                     └──▶ cli: Decode + globals + wiring
      │                                └──▶ testador: cenário Tiktok
```

`coder-runtime` pode começar **em paralelo** com `coder-valuetypes`: `TypeNameResolver` e o wrapper
de `typeof` dependem só da assinatura `(value: unknown) -> string?`, congelada aqui, não do código
dos tipos.

---

## 12. Riscos e o que dá errado

| Risco | Mitigação |
|---|---|
| **Ciclo de dependência** `valuetypes ↔ runtime` se alguém "der um jeito" e requerer `valuetypes` de dentro de `runtime`. | Invariante verificável mecanicamente: `grep -r valuetypes src/runtime/` tem que ser vazio. Item obrigatório de checklist do `revisor-runtime`. |
| **Divergência entre `Catalog` e o que existe em `types/`** — o global `Font` existir e a sentinela também. | `Catalog` é a fonte única; `UnsimulatedGlobals` deriva. Spec do território assevera: todo `Simulated = true` tem entrada em `BuildGlobals()`, e nenhum nome aparece nos dois lados. |
| **`__eq` entre value types diferentes** (`Vector3` vs `Color3`) chamando o comparador errado — Luau chama `__eq` quando os dois lados são userdata. | Verificado em §0.3: a fábrica filtra por `TypeName` antes de delegar; comparação com userdata alheio devolve `false` sem erro. Spec cobre os três casos. |
| **Vazamento de memória** pela side-table de estado. | `__mode = "k"`. Spec com `collectgarbage("count")` antes/depois de criar e soltar 100k valores. |
| **Regressão silenciosa das 24 classes já geradas** quando o gerador passar a emitir defaults reais. | O gerador já tem spec (`tools/generate-services.spec.luau`) e as classes são regeradas, não editadas. `revisor-services` compara o diff de `generated/` contra o dump. |
| **Script do usuário com `while true do end`** — inalterado por este desenho: value type é síncrono e puro, nunca cede coroutine. O `--timeout` do `RunCommand` continua sendo o único mecanismo. | — |
| **`.project.json` inválido** — inalterado: `ProjectFile` erra antes. O caso novo é `$properties` com forma indecodificável, que vira `materialize/undecodable-property` citando nó+propriedade+tipo alvo, nunca stack trace cru (§7). | — |
| **Perf** (§0.4: 3.2 µs por operação). | Aceito e declarado. Se um cenário real medir dor, o `vector` nativo (§0.1) é a rota de otimização — **com dado**, não por antecipação. |
| **`Enum` inflar o startup.** | Medido: 8.5 ms para os 3611 itens (§0.6). Construção dos `EnumItem` como userdata é **preguiçosa e memoizada** por enum — quem toca só `Enum.KeyCode` paga por `Enum.KeyCode`. |

---

## 13. O que deliberadamente NÃO fazer agora

1. **Não** validar escrita de propriedade por `ValueType` em `Instance.__newindex`. O campo entra
   como dado; usá-lo para rejeitar exige responder o que o Roblox faz com coerção implícita
   (`part.Size = 5`? `part.BrickColor = "Bright red"`?) e isso não foi pesquisado. Meia-validação é
   pior que nenhuma. Tarefa própria, depois de pesquisa.
2. **Não** emitir definições de tipo Luau (`.d.luau`) para o `luau-lsp` do usuário. É um sistema
   próprio (D4).
3. **Não** usar o `vector` nativo do Luau como `Vector3`. §0.1 fecha: sem `debug.setmetatable` no
   Lune, não há `.Magnitude`. Reavaliar **só** se o Lune passar a expor `debug.setmetatable`.
4. **Não** implementar `BrickColor` nem `PhysicalProperties` antes de P5/P6 (§9). Sem fonte de
   dado, seria inventar valor — invariante 1.
5. **Não** implementar `RaycastResult`, `Content`, `Secret`, `SharedTable`, `UniqueId`,
   `SecurityCapabilities` como globais: o Roblox não expõe construtor global para eles.
   `Catalog.HasGlobalConstructor = false` — nem valor real, nem sentinela.
6. **Não** simular geometria de verdade (`Region3` intersectando partes, `RaycastParams` filtrando
   de fato). A leva 2 entrega a **superfície de API** com comportamento simplificado e documentado,
   como a regra 02 manda — nunca omite a API, nunca finge exatidão física.
7. **Não** tocar `math.randomseed` a partir de `Random` (§6.6).
8. **Não** fundir os relatórios de pesquisa neste arquivo. Cada tipo tem sua assinatura confirmada
   no arquivo do `pesquisador`; a tarefa aponta para lá. Duplicar aqui criaria uma segunda fonte de
   verdade que envelhece.

---

## 14. Tarefas escritas no board

`.claude/tasks.json`, 13 tarefas com `depends` já encadeados. `task-runtime-031` (esta arquitetura)
foi movida para `done`.

| Wave | ID | Agente | Depende de |
|---|---|---|---|
| 38 | `task-valuetypes-000` — **pré-requisito: decisão do usuário** sobre o território/agentes | `arquiteto` | — |
| 39 | `task-valuetypes-001` — `Float32.luau` | `coder-valuetypes` | `-000` |
| 39 | `task-valuetypes-002` — `Userdata.luau` + `Catalog.luau` | `coder-valuetypes` | `-001` |
| 40 | `task-valuetypes-003` — `Enum` + gerador + `EnumData` | `coder-valuetypes` | `-002` |
| 40 | `task-valuetypes-004` — `Vector3` + `Vector2` | `coder-valuetypes` | `-002` |
| 40 | `task-valuetypes-005` — `Color3` + `UDim` + `UDim2` | `coder-valuetypes` | `-002` |
| 40 | `task-runtime-032` — ponte `runtime` | `coder-runtime` | `-000` (só o contrato) |
| 41 | `task-valuetypes-006` — `CFrame` | `coder-valuetypes` | `-004` |
| 41 | `task-valuetypes-007` — `Decode.luau` + `init.luau` | `coder-valuetypes` | `-003`, `-005`, `-006` |
| 41 | `task-services-015` — ponte `services` | `coder-services` | `-007`, `task-runtime-032` |
| 42 | `task-cli-025` — ponte `cli` | `coder-cli` | `task-services-015` |
| 43 | `task-test-valuetypes-001` — cenário real (Tiktok) | `testador` | `task-cli-025` |

Wave 40 é a de maior paralelismo: **quatro agentes simultâneos** (`-003`, `-004`, `-005` em
`coder-valuetypes` — que o planejador pode fatiar ou serializar conforme a política de despacho —
mais `coder-runtime` em `task-runtime-032`, que só precisa do contrato congelado neste documento,
não do código dos tipos).

---

## Apêndice — reprodução dos experimentos

Todos os números do §0 saíram de scripts descartáveis rodados com o Lune deste repositório
(`lune run <arquivo>`), no scratchpad da sessão, **não commitados**. Para reproduzir:
`vector.create`/`typeof`/`tostring`; `pairs(debug)`; `buffer.writef32`+`readf32` vs.
`vector.create(x,0,0).x`; `newproxy(true)` + `__metatable`/`__eq`/`__add` + `pcall(setmetatable, p, {})`;
laço de 200.000 nas três representações com `os.clock()`; `%.1g`..`%.9g` com re-quantização;
`json.load` do dump contando `Enums`/`Items` e a frequência de `ValueType.Category == "DataType"`.
