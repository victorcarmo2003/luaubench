--!strict

--[[
	Gramática de valor do `$properties` do Rojo (task-valuetypes-007). Desenho completo em
	.claude/agents-memory/arquiteto-valuetypes-2026-09-05.md, seção 3.1 ("Decode.luau -- gramática
	de valor do .project.json").

	## O problema que este módulo resolve (por que não dá pra "adivinhar" a partir do JSON sozinho)

	`.claude/agents-memory/pesquisa-formato-projeto-rojo-2026-09-05.md`, seção "Formato de
	`$properties`" (linha 47-49), confirma contra o CÓDIGO-FONTE real do Rojo (`UnresolvedValue`,
	`src/resolution.rs`) que a forma "ambígua" do `$properties` é resolvida **pelo Rojo real** contra
	o banco de reflection oficial da Roblox, **por classe+propriedade** -- não existe informação no
	JSON em si que diga "este array de 3 números é um Vector3" vs. "é um Color3". Exemplo real citado
	pelo arquiteto (§7 do desenho, do `default.project.json` do template `rojo init`, projeto
	Tiktok testado pelo `testador`):

		"Lighting":  { "$properties": { "Ambient":  [0.5, 0.5, 0.5] } }   ->  Color3
		"Baseplate": { "$properties": { "Position": [0, -10, 0] } }       ->  Vector3

	Mesma forma JSON (array de 3 números), tipos alvo diferentes. O LuauBench não embarca o banco de
	reflection do Rojo (`rbx_reflection_database`, um crate Rust) -- em vez disso, resolve pelo
	`MemberDescriptor.ValueType`/`ValueCategory` que o PRÓPRIO SCHEMA do LuauBench já carrega
	(gerado do `Full-API-Dump.json`, ver `src/runtime/Instance.luau` -- território `runtime`/
	`services`, task-runtime-032/task-services-015, ainda não conectado a este módulo: essa é a
	responsabilidade de `cli`, que vai chamar `Decode.FromRojoJson(descriptor.ValueType,
	descriptor.ValueCategory, raw)` de dentro de `TreeMaterializer.applyProperties`, task futura
	`task-cli-025`). Este módulo SÓ recebe o par (nome do tipo alvo, categoria) já resolvido -- ele
	não conhece Rojo, `.project.json` nem `MemberDescriptor` (nenhum `require` de `cli`/`runtime`
	aqui, mantendo o território uma folha do grafo, ver desenho §2).

	## NUNCA lança erro (contrato do acceptance da task)

	Toda forma inválida -- tipo errado, array de tamanho errado, elemento não-numérico, categoria
	não suportada, nome de Enum/item inexistente -- devolve `DecodeFailure` com uma frase legível.
	Nenhuma chamada de construtor de value type deste módulo pode lançar: cada decodificador só
	invoca `X.new(...)` DEPOIS de validar a forma bruta a mão (nunca via `pcall` "torcendo" pra
	capturar um erro nativo) -- é o que garante, por construção, que este módulo não precisa de
	`pcall` em lugar nenhum. Quem decide se um `DecodeFailure` vira warning ou erro é `cli`
	(hoje `plan/non-primitive-property`; task futura substitui por
	`materialize/undecodable-property`, ver desenho §7) -- este módulo nunca decide isso sozinho.

	## Formas cobertas nesta tarefa (leva 1 -- tipos que já existem em `types/`)

	| `valueCategory` | `valueTypeName` | Forma bruta aceita                          | Fonte da forma |
	|---|---|---|---|
	| `"Enum"`   | nome do enum (ex. `"Material"`) | string = nome do item (ex. `"Plastic"`) | pesquisa Rojo §"Formato de $properties": "string que casa com um nome de item de Enum" |
	| `"DataType"` | `"Vector3"` | array de 3 números `[x, y, z]` | pesquisa Rojo (confirmado: "array de 3 números (Vector3 ou Color3)") |
	| `"DataType"` | `"Vector2"` | array de 2 números `[x, y]` | pesquisa Rojo (confirmado: "array de 2 números (Vector2)") |
	| `"DataType"` | `"Color3"` | array de 3 números `[r, g, b]`, faixa 0-1 | ver "Color3: 0-1 ou 0-255?" abaixo |
	| `"DataType"` | `"CFrame"` | array de 12 números (posição + matriz 3x3) | pesquisa Rojo (confirmado: "array de 12 números (CFrame: posição xyz + matriz de rotação 3x3)") |
	| `"DataType"` | `"UDim"` | array de 2 números `[scale, offset]` | ver "UDim/UDim2" abaixo -- APROXIMAÇÃO |
	| `"DataType"` | `"UDim2"` | array de 4 números `[xScale, xOffset, yScale, yOffset]` | ver "UDim/UDim2" abaixo -- APROXIMAÇÃO |

	Qualquer outro `valueTypeName` de `"DataType"` (`Rect`, `NumberRange`, `TweenInfo`, ...) ainda não
	tem módulo em `types/` (leva 2, ver desenho §10) -- devolve `DecodeFailure` citando o nome, nunca
	finge decodificar. Qualquer `valueCategory` fora de `"DataType"`/`"Enum"` (`"Primitive"`,
	`"Class"`, `"Group"`) também devolve `DecodeFailure` explícita: este módulo só existe pra
	resolver a forma AMBÍGUA (regra 00 -- Decode não é um decodificador de JSON genérico, é
	especificamente sobre a ambiguidade descrita acima).

	## Color3: 0-1 ou 0-255? (decisão tomada, documentada -- pergunta explícita do acceptance)

	`.claude/agents-memory/pesquisa-datatypes-color-udim-enum-2026-09-05.md` (seção A, Color3) só
	pesquisou o DATATYPE em si -- confirma que `Color3.new(r,g,b)` é 0-1 e `Color3.fromRGB(r,g,b)` é
	0-255, mas essa pesquisa NÃO cobre qual das duas faixas o Rojo usa dentro do `$properties`. A
	pesquisa do FORMATO DO ROJO também não distingue -- só diz "array de 3 números". A evidência
	decisiva vem do exemplo REAL citado pelo arquiteto (§7 do desenho, acima): `Lighting.Ambient =
	[0.5, 0.5, 0.5]` no `default.project.json` gerado por `rojo init` -- um cinza médio plausível em
	0-1 (equivalente a RGB 128,128,128), mas seria um cinza quase invisível (~0.2%) se fosse 0-255.
	Decisão: array de Color3 é decodificado em 0-1 (equivalente a `Color3.new`, NÃO `Color3.fromRGB`)
	-- aproximação de boa-fé apoiada num exemplo real observado, não uma citação literal da spec do
	Rojo. Reavaliar se uma pesquisa dedicada ao `resolution.rs` do Rojo confirmar diferente.

	## UDim/UDim2: forma NÃO confirmada literalmente pela pesquisa do Rojo -- aproximação declarada

	A pesquisa do formato do Rojo confirma "array de 2 números (Vector2)" e "array de 4 números"
	(SEM nomear o tipo alvo do array de 4) -- não cita `UDim` nem `UDim2` deste jeito. A forma
	implementada aqui segue o MESMO PRINCÍPIO já confirmado para `Vector3`/`CFrame` (a ordem
	posicional do array bate com a ordem dos argumentos do construtor real do datatype, confirmada
	por `pesquisa-datatypes-color-udim-enum-2026-09-05.md`, seção B: `UDim.new(scale, offset)`,
	segundo overload de `UDim2.new(xScale, xOffset, yScale, yOffset)`) -- é uma EXTRAPOLAÇÃO
	consistente com o mecanismo confirmado (Rojo resolve o MESMO formato de array conforme o tipo
	alvo, por classe+propriedade), não uma citação direta pro par UDim/UDim2 especificamente.
	Documentado aqui como aproximação de boa-fé (regra 00, mesmo protocolo que P8/P9 já usam em
	`types/UDim.luau`/`types/UDim2.luau`) -- reavaliar se uma pesquisa dedicada a `resolution.rs`
	(`UnresolvedValue`) confirmar ou contradizer.

	Depende de: `types/Vector3`, `types/Vector2`, `types/Color3`, `types/UDim`, `types/UDim2`,
	`types/CFrame`, `types/Enum`, `generated/EnumData`. Usado por: `init.luau` (reexporta),
	`cli` (via `init.luau`, task futura `task-cli-025`) -- nunca requerido diretamente por um módulo
	interno de fora deste território (regra 06: `services`/`cli` só fazem `require("../valuetypes")`).
]]

local Vector3 = require("./types/Vector3")
local Vector2 = require("./types/Vector2")
local Color3 = require("./types/Color3")
local UDim = require("./types/UDim")
local UDim2 = require("./types/UDim2")
local CFrame = require("./types/CFrame")
local EnumModule = require("./types/Enum")
local EnumData = require("./generated/EnumData")

export type DecodeSuccess = { Ok: true, Value: unknown }
export type DecodeFailure = { Ok: false, Reason: string }
export type DecodeResult = DecodeSuccess | DecodeFailure

local Decode = {}

local function ok(value: unknown): DecodeResult
	return { Ok = true, Value = value }
end

local function fail(reason: string): DecodeResult
	return { Ok = false, Reason = reason }
end

-- Descreve `value` em vocabulário JSON (não Luau) pra mensagem de erro -- "array"/"objeto" em vez
-- de só "table", "nil" em vez de vazio. Implementação PRÓPRIA deste módulo (não reusa
-- `cli/JsonValue.luau:describeKind`, que é praticamente idêntica): `valuetypes` não pode requerer
-- `cli` (grafo acíclico, desenho §2) -- duplicar esta função pequena e sem estado é o preço
-- correto dessa direção de dependência, não uma divergência de comportamento (mesma lógica: chave
-- não-numérica -> objeto, chave numérica -> array, tabela vazia -> "objeto" por convenção, mesma
-- ambiguidade JSON de sempre).
local function describeRaw(value: unknown): string
	if value == nil then
		return "nil"
	end
	local kind = typeof(value)
	if kind ~= "table" then
		return kind
	end
	local asGeneric = (value :: unknown) :: { [unknown]: unknown }
	local firstKey = next(asGeneric)
	if firstKey == nil then
		return "objeto vazio"
	elseif typeof(firstKey) == "number" then
		return "array"
	end
	return "objeto"
end

-- Valida que `raw` é um array de EXATAMENTE `expectedLength` números (chaves 1..N, sem chave
-- não-numérica, sem elemento faltando/de outro tipo) -- a validação central de que toda forma
-- "array de N números" do cabeçalho depende. Nunca lança: devolve `(valores, nil)` em sucesso ou
-- `(nil, motivo)` em qualquer forma inválida.
local function asNumberArray(raw: unknown, expectedLength: number, targetTypeName: string): ({ number }?, string?)
	if typeof(raw) ~= "table" then
		return nil, `{targetTypeName} espera um array de {expectedLength} números, recebeu {describeRaw(raw)}`
	end

	local asGeneric = (raw :: unknown) :: { [unknown]: unknown }
	local length = 0
	for key in asGeneric do
		if typeof(key) ~= "number" then
			return nil, `{targetTypeName} espera um array de {expectedLength} números, recebeu um objeto (chave não numérica '{tostring(key)}')`
		end
		length += 1
	end

	if length ~= expectedLength then
		return nil, `{targetTypeName} espera um array de {expectedLength} números, recebeu array de tamanho {length}`
	end

	local values: { number } = table.create(expectedLength)
	for index = 1, expectedLength do
		local element = asGeneric[index]
		if typeof(element) ~= "number" then
			return nil,
				`{targetTypeName} espera um array de {expectedLength} números, elemento {index} é {describeRaw(element)} (esperava number)`
		end
		values[index] = element :: number
	end

	return values, nil
end

-- Um decodificador por `valueTypeName` de `"DataType"` -- registro data-driven pra crescer na leva
-- 2 sem precisar reescrever o `if`/`elseif` de despacho (só adicionar uma entrada aqui).
type DataTypeDecoder = (raw: unknown) -> DecodeResult

local dataTypeDecoders: { [string]: DataTypeDecoder }
dataTypeDecoders = {
	Vector3 = function(raw: unknown): DecodeResult
		local values, reason = asNumberArray(raw, 3, "Vector3")
		if values == nil then
			return fail(reason :: string)
		end
		return ok(Vector3.new(values[1], values[2], values[3]))
	end,

	Vector2 = function(raw: unknown): DecodeResult
		local values, reason = asNumberArray(raw, 2, "Vector2")
		if values == nil then
			return fail(reason :: string)
		end
		return ok(Vector2.new(values[1], values[2]))
	end,

	-- Faixa 0-1 (equivalente a `Color3.new`, NÃO `Color3.fromRGB`) -- ver cabeçalho, "Color3: 0-1
	-- ou 0-255?".
	Color3 = function(raw: unknown): DecodeResult
		local values, reason = asNumberArray(raw, 3, "Color3")
		if values == nil then
			return fail(reason :: string)
		end
		return ok(Color3.new(values[1], values[2], values[3]))
	end,

	-- 12 números: posição (x,y,z) + matriz de rotação 3x3 em ordem row-major -- mesma ordem que
	-- `CFrame.new` (7º overload, confirmado pela pesquisa) e o `Default` serializado do dump
	-- ("0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1", ver desenho §0.6).
	CFrame = function(raw: unknown): DecodeResult
		local values, reason = asNumberArray(raw, 12, "CFrame")
		if values == nil then
			return fail(reason :: string)
		end
		return ok(CFrame.new(
			values[1],
			values[2],
			values[3],
			values[4],
			values[5],
			values[6],
			values[7],
			values[8],
			values[9],
			values[10],
			values[11],
			values[12]
		))
	end,

	-- APROXIMAÇÃO -- ver cabeçalho, "UDim/UDim2": ordem = `UDim.new(scale, offset)`.
	UDim = function(raw: unknown): DecodeResult
		local values, reason = asNumberArray(raw, 2, "UDim")
		if values == nil then
			return fail(reason :: string)
		end
		return ok(UDim.new(values[1], values[2]))
	end,

	-- APROXIMAÇÃO -- ver cabeçalho, "UDim/UDim2": ordem = `UDim2.new(xScale, xOffset, yScale,
	-- yOffset)` (2º overload numérico, confirmado pela pesquisa).
	UDim2 = function(raw: unknown): DecodeResult
		local values, reason = asNumberArray(raw, 4, "UDim2")
		if values == nil then
			return fail(reason :: string)
		end
		return ok(UDim2.new(values[1], values[2], values[3], values[4]))
	end,
}
table.freeze(dataTypeDecoders)

-- Índice de EXISTÊNCIA de nome de enum, O(1), construído uma vez a partir do MESMO
-- `generated/EnumData.luau` que `types/Enum.luau` já usa (fonte única -- não é uma segunda lista
-- de nomes mantida à mão, é um índice derivado dos mesmos dados gerados). Evita indexar
-- `EnumModule[enumName]` (que ERRA de propósito pra enum inexistente, ver `types/Enum.luau`,
-- "Divergência declarada -- mensagens de erro") só pra descobrir se o nome existe -- este módulo
-- não pode deixar esse erro nativo escapar (contrato "nunca lança"), e capturar via `pcall` só pra
-- descartar o texto interno seria mais frágil (e vazaria formatação de erro interna do território
-- numa mensagem que deveria ser só nossa) do que checar antes com um índice puro.
local enumExists: { [string]: boolean } = {}
for _, definition in EnumData do
	enumExists[definition.Name] = true
end

-- Vitrine tipada SEM `any` pra indexar `EnumModule[enumName]` por chave dinâmica -- mesmo padrão
-- de `asStringIndexable` em `types/Enum.spec.luau` (a única forma de expressar "indexação por
-- string arbitrária" sobre um userdata opaco sem cair em `any`).
type StringIndexableProbe = typeof(setmetatable({} :: { [string]: unknown }, {}))
local function asStringIndexable(value: unknown): StringIndexableProbe
	return value :: StringIndexableProbe
end

-- `enumName` já confirmado existente por `enumExists` antes de chamar (ver `decodeEnum`) -- a
-- indexação abaixo nunca dispara o `error()` de "Enum inexistente" de `types/Enum.luau`.
local function decodeEnum(enumName: string, raw: unknown): DecodeResult
	if typeof(raw) ~= "string" then
		return fail(`Enum.{enumName} espera o nome de um item (string), recebeu {describeRaw(raw)}`)
	end
	local itemName = raw :: string

	if not enumExists[enumName] then
		return fail(`'{enumName}' não é um Enum válido`)
	end

	local enumObject = asStringIndexable(EnumModule)[enumName] :: EnumModule.Enum
	local item = enumObject:FromName(itemName)
	if item == nil then
		return fail(`'{itemName}' não é um item válido de Enum.{enumName}`)
	end
	return ok(item)
end

-- Resolve a forma AMBÍGUA do `$properties` do Rojo: `raw` é o JSON já parseado (chega como
-- `nil | boolean | number | string | table` -- o mesmo universo de `cli/JsonValue.JsonValue`, mas
-- este módulo não importa aquele tipo, ver cabeçalho sobre a direção do grafo).
-- `valueTypeName`/`valueCategory` vêm do `MemberDescriptor` do schema (`runtime`, campo
-- `ValueType`/`ValueCategory` -- task-runtime-032) -- SEM eles, decidir a forma seria adivinhar
-- (ver cabeçalho). NUNCA lança: toda forma inválida vira `DecodeFailure` com frase legível.
function Decode.FromRojoJson(valueTypeName: string, valueCategory: string, raw: unknown): DecodeResult
	if valueCategory == "Enum" then
		return decodeEnum(valueTypeName, raw)
	end

	if valueCategory == "DataType" then
		local decoder = dataTypeDecoders[valueTypeName]
		if decoder == nil then
			return fail(
				`Decode.FromRojoJson: '{valueTypeName}' ainda não é um DataType decodificável neste LuauBench (fora da leva atual de src/valuetypes/types/)`
			)
		end
		return decoder(raw)
	end

	return fail(
		`Decode.FromRojoJson: valueCategory '{valueCategory}' não é decodificável (só 'DataType'/'Enum' têm forma ambígua no $properties do Rojo -- 'Primitive'/'Class'/'Group' não deveriam chegar aqui)`
	)
end

return Decode
