# Regra 06 — Value Types simulados (`src/valuetypes/`)

Território novo, criado em 2026-09-05 (decisão do usuário, `task-valuetypes-000`) sobre o desenho completo em `.claude/agents-memory/arquiteto-valuetypes-2026-09-05.md`. Vale a leitura inteira desse arquivo antes de tocar código — aqui só as invariantes que sobrevivem entre tarefas.

## O que é este território

`Vector3`, `Vector2`, `CFrame`, `Color3`, `UDim`, `UDim2`, `Enum` e os demais tipos de valor do Roblox — não são `Instance`, não têm `Parent`, não passam por `ClassRegistry`, não são `GetService`-áveis. São valores imutáveis com semântica de operador (`+`/`-`/`==`/`tostring`) e precisão float32 fiéis ao Roblox real.

## Fonte única

- `src/valuetypes/Catalog.luau` é a fonte única de "o que existe como global de valor no Roblox", "o que já simulamos" e "o que vira sentinela de erro". `src/cli/UnsimulatedGlobals.luau` **deriva** de `Catalog.UnsimulatedGlobalNames()` — nunca mantém lista duplicada à mão.
- Datatype não vem do `Full-API-Dump.json` diretamente (só é referenciado por nome nos `ValueType` de membros de classe) — `Catalog.luau` é extensão deliberada do LuauBench (regra 00 permite), documentando a fonte de cada nome (doc oficial + `ValueType` do dump) no cabeçalho.

## Fábrica única de userdata

- `src/valuetypes/Userdata.luau` é o **único** lugar do projeto onde `newproxy(true)` é chamado para um value type. Toda tarefa que precisar de um tipo novo usa `Userdata.Define`, nunca uma segunda fábrica — duas fábricas seria exatamente a divergência silenciosa que a regra 00 proíbe.
- Invariantes que a fábrica garante e nenhum tipo individual pode afrouxar:
  1. `__metatable` sempre travado (script nunca alcança os closures internos).
  2. `__newindex` sempre erra — value type é imutável. Exceção declarada explicitamente: `RaycastParams`/`OverlapParams` (mutáveis no Roblox real, leva 2) via `Descriptor.SetProperty`, nunca por omissão silenciosa.
  3. Estado em side-table `__mode="k"` module-local — nunca alcançável do sandbox do script.
  4. `__eq` só chama a comparação real quando os dois lados são userdata nosso do mesmo `TypeName`; caso contrário `false` sem erro.

## Precisão numérica

- Todo componente numérico é quantizado pra float32 no construtor (`Float32.Quantize`/`QuantizeInt32`/`QuantizeInt16`, `buffer.writef32`/`readf32`) — o Roblox real guarda `Vector3`/`CFrame`/etc como float32, não double. Nunca guardar `double` cru "porque é mais simples" sem declarar a divergência.
- `tostring` usa `Float32.Format` (algoritmo shortest round-trip) — nunca o `tostring` cru do Luau, que imprime a representação double completa (`"0.10000000149011612"` em vez de `"0.1"`).

## Contrato com os outros territórios (grafo acíclico)

- **`src/runtime/**` nunca contém a string `"valuetypes"`.** É a regra de ouro deste desenho — `runtime` nunca lê o API Dump diretamente (regra 02) e `Enum` é derivado do dump; misturar quebra essa invariante literalmente.
- A ponte com `runtime` é sempre um resolvedor injetado pelo composition root (`cli`) — `Runtime.TypeNameResolver.Set`, mesmo padrão já usado por `UnknownClassResolver` (`task-runtime-030`). `valuetypes` nunca `require`s `runtime` na leva 1 (tipos-base); na leva 2, só o TIPO `Instance` é referenciado (ex: `RaycastParams.FilterDescendantsInstances`), nunca lógica de `runtime`.
- `services`/`cli` fazem `require("../valuetypes")` — nunca `require` de um módulo interno (`types/Vector3.luau` direto), mesmo contrato que `runtime`/`services` já têm entre si.
- `tools/generate-enums.luau` (gerador offline dos 629 enums do dump) vive em `tools/`, escrito por `coder-valuetypes` — arquivo distinto de `tools/generate-services.luau` (dono: `coder-services`), zero colisão.

## Testes

- Todo tipo novo tem teste cobrindo: construtor com quantização float32, ao menos um operador aritmético relevante, `tostring`, `__eq` (mesmo tipo e tipo diferente, incluindo comparação com valor solto tipo `5`/`"x"`), tentativa de mutação (erro), tentativa de `setmetatable`/`pairs` no valor (erro nativo do userdata, não do nosso código).
- Valor default bate com o que o dump traz por `ValueType` (`Vector3` → `"0, 0, 0"`, `UDim` → `"0, 8"`, etc.) — nunca um `nil`/zero arbitrário inventado.
