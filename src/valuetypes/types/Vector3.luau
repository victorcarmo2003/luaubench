--!strict

--[[
	Vector3 simulado (task-valuetypes-004). Desenho completo em
	.claude/agents-memory/arquiteto-valuetypes-2026-09-05.md (seção 3.2). Toda assinatura
	confirmada contra o YAML oficial (`Roblox/creator-docs`) em
	.claude/agents-memory/pesquisa-datatypes-vector-cframe-2026-09-05.md, seções 1-9 -- nenhuma
	assinatura aqui vem de memória.

	## DIVERGÊNCIA D8 (OBRIGATÓRIA -- ver desenho §8, linha D8)

	`type(Vector3.new())` AQUI devolve **"userdata"**. No Roblox moderno devolve **"vector"** --
	tipo primitivo nativo da VM Luau, pra qual a Roblox migrou Vector3 (`Vector2`/`CFrame`
	continuam "userdata" nos dois mundos -- confirmado por dois anúncios oficiais da equipe
	Roblox no DevForum, ver pesquisa §7). `typeof(Vector3.new())` CONTINUA correto ("Vector3")
	nos dois casos -- só `type()` diverge.

	Por quê: o Lune NÃO expõe `debug.setmetatable` (confirmado pelo arquiteto, §0.1: `pairs(debug)`
	só tem as chaves `info`/`traceback`). Sem essa função não há como instalar `.Magnitude`/
	`.Unit`/`:Cross()`/etc no tipo `vector` nativo do Luau -- ele não tem metatable e não pode
	ganhar uma depois de criado. Por isso este módulo usa `Userdata.Define` (newproxy(true)) como
	TODO outro value type do território, e não o `vector` nativo.

	Impacto prático quase nulo: "userdata" e "vector" são ambos `~= "table"`, então todo
	`if type(v) == "table" then ... end` de serializer (o caso de uso nº1 do LuauBench, ver
	desenho §4 "Decisão 2") se comporta igual nos dois mundos. Reavaliar SÓ se o Lune passar a
	expor `debug.setmetatable`.

	## PENDÊNCIA P8 (NÃO CONFIRMADA -- ver desenho §9)

	`==` aqui é EXATO, componente a componente (`Equals`, abaixo). A pesquisa não achou nenhuma
	citação direta confirmando se o Roblox real usa `==` exato ou com epsilon para Vector3 --
	é inferência (a existência de `FuzzyEq` como método SEPARADO só faz sentido se `==` já não
	fosse fuzzy; ver pesquisa §9). Implementado como APROXIMAÇÃO DE BOA-FÉ: exato. Reavaliar se
	P8 for pesquisada.

	## Outras aproximações declaradas nesta tarefa (regra 00 -- nunca silenciosas)

	- `FuzzyEq`: a doc oficial diz que Vector3 usa um "hybrid epsilon that scales relative to the
	  magnitude of each component" (pesquisa §9), SEM dar a fórmula exata. Implementado aqui como
	  `|a_i - b_i| <= epsilon * max(|a_i|, |b_i|, 1)` por componente -- um epsilon relativo com piso
	  absoluto de 1, que reproduz o COMPORTAMENTO descrito (escala com a magnitude) sem ser a
	  fórmula literal do motor (fechada/não documentada). Diferente de propósito do algoritmo de
	  `Vector2.FuzzyEq` (abs puro, sem escala) -- ver types/Vector2.luau, é a assimetria real
	  confirmada pela pesquisa (§9), não um descuido de cópia-e-cola.
	- `Angle(other, axis?)`: a doc só confirma o INTERVALO de saída ([0,π] sem eixo, [-π,π] com
	  eixo), não a fórmula. Implementado via `atan2(|cross|, dot)` (sem eixo) e sinalizado pela
	  projeção do cross no eixo dado (com eixo) -- forma numericamente estável e padrão pra esse
	  tipo de cálculo, mas não é uma citação literal do motor Roblox (fechado).
	- Unário `-v`: suportado por EVIDÊNCIA INDIRETA (exemplo de prosa `-cf.ZVector` no YAML de
	  CFrame, que só faz sentido se Vector3 suportar `-`, ver pesquisa §5) -- não há uma entrada
	  formal em `math_operations` pra operadores unários em nenhum YAML.
	- `FromNormalId`/`FromAxis`: `Enum` (task-valuetypes-003) roda em PARALELO a esta tarefa no
	  board (wave 40, ver desenho §11 -- "paralelos entre si") e `types/Enum.luau` ainda não existe
	  neste território. Pra não bloquear nem inventar um require pra um módulo inexistente, o
	  parâmetro é tipado como `EnumItemLike` (tipo estrutural mínimo, só `.Name: string`) em vez de
	  `Enum.NormalId`/`Enum.Axis` -- funciona tanto com o `EnumItem` real (userdata, futuro,
	  `.Name` respondido pelo `__index` dele) quanto com uma tabela comum `{ Name = "Top" }` (usado
	  nos specs desta tarefa). NÃO valida `EnumType` (exigiria o módulo Enum) -- documentado como
	  gap, não confirmado como comportamento idêntico ao Roblox real (que provavelmente rejeitaria
	  `Enum.Axis.X` passado pra `FromNormalId`). O mapeamento Top/Front é CITADO LITERALMENTE pela
	  pesquisa (Vector3.yaml); Bottom/Back/Left/Right são INFERIDOS (opostos óbvios, convenção
	  universalmente conhecida dos NormalId do Roblox), não citados individualmente pela pesquisa.
	- `Magnitude`/`Dot`/`Angle` (retornos `number`, não um Vector3 novo): quantizados pra float32
	  via `Float32.Quantize` igual aos componentes -- extensão de boa-fé da Decisão 3 do desenho
	  (que lista só os campos X/Y/Z na tabela, mas todo `float` do Roblox real é 32 bits, e esses
	  três retornos são documentados como `float` na doc oficial).

	Depende de: `../Float32`, `../Userdata`. Nenhuma dependência de `runtime`/`services`/`cli`
	(módulo-folha do território, ver desenho §2).
]]

local Float32 = require("../Float32")
local Userdata = require("../Userdata")

local TYPE_NAME = "Vector3"

-- Epsilon default de `FuzzyEq`, confirmado LITERAL e IGUAL nos três tipos (Vector3/Vector2/
-- CFrame) pela pesquisa (§9): `0.00001` (`1e-5`).
local DEFAULT_FUZZY_EPSILON = 0.00001

export type Vector3 = typeof(setmetatable(
	{} :: {
		X: number,
		Y: number,
		Z: number,
		Magnitude: number,
		Unit: Vector3,
		-- Métodos de instância (sintaxe `v:Metodo(...)`) -- precisam estar aqui, na parte de
		-- TABELA do tipo opaco, não na metatable: o Luau resolve `v:Metodo()` como um campo
		-- comum do tipo de `v`, não via `__index` (mesmo padrão de `SpecPoint`/`SpecColor` em
		-- Userdata.spec.luau). Isto é só a "vitrine" tipada pro type-checker -- quem valida de
		-- verdade em runtime é `Userdata.luau:sharedIndex`, ver D4 no desenho arquitetural.
		Abs: (self: Vector3) -> Vector3,
		Ceil: (self: Vector3) -> Vector3,
		Floor: (self: Vector3) -> Vector3,
		Sign: (self: Vector3) -> Vector3,
		Cross: (self: Vector3, other: Vector3) -> Vector3,
		Angle: (self: Vector3, other: Vector3, axis: Vector3?) -> number,
		Dot: (self: Vector3, other: Vector3) -> number,
		FuzzyEq: (self: Vector3, other: Vector3, epsilon: number?) -> boolean,
		Lerp: (self: Vector3, goal: Vector3, alpha: number) -> Vector3,
		-- UM ÚNICO argumento -- diferente de Vector2:Max/Min (tupla variádica), ver
		-- types/Vector2.luau.
		Max: (self: Vector3, other: Vector3) -> Vector3,
		Min: (self: Vector3, other: Vector3) -> Vector3,
	},
	{} :: {
		__add: (Vector3, Vector3) -> Vector3,
		__sub: (Vector3, Vector3) -> Vector3,
		__mul: ((Vector3, Vector3) -> Vector3) & ((Vector3, number) -> Vector3) & ((number, Vector3) -> Vector3),
		__div: (Vector3, Vector3 | number) -> Vector3,
		__idiv: (Vector3, Vector3 | number) -> Vector3,
		__unm: (Vector3) -> Vector3,
		__eq: (Vector3, Vector3) -> boolean,
		__tostring: (Vector3) -> string,
	}
))

-- Tipo estrutural mínimo pra `FromNormalId`/`FromAxis` -- ver cabeçalho, "Outras aproximações".
export type EnumItemLike = { Name: string }

local function numAt(fields: Userdata.Fields, index: number): number
	return fields[index] :: number
end

-- Descreve `value` pra mensagem de erro de operador -- nosso TypeName se for value type
-- registrado, senão o `typeof()` nativo (mesmo vocabulário do erro nativo do Luau).
local function describeType(value: unknown): string
	local name = Userdata.TypeNameOf(value)
	if name ~= nil then
		return name
	end
	return typeof(value)
end

-- `nil` se `value` não for um Vector3 nosso (inclusive: outro value type nosso, ou não-userdata).
local function tryUnwrap(value: unknown): Userdata.Fields?
	if Userdata.TypeNameOf(value) == TYPE_NAME then
		return Userdata.Unwrap(value, TYPE_NAME)
	end
	return nil
end

local function signOf(value: number): number
	if value > 0 then
		return 1
	elseif value < 0 then
		return -1
	end
	return 0
end

local Vector3Factory: Userdata.Factory

-- Construtor privado ÚNICO (Decisão 3 do desenho): quantiza os três componentes pra float32
-- aqui, e só aqui. Como TODO operador/método que produz um Vector3 novo passa por esta função,
-- a aritmética inteira fica encadeada em float32 automaticamente.
local function construct(x: number, y: number, z: number): Vector3
	local fields: Userdata.Fields = {
		Float32.Quantize(x),
		Float32.Quantize(y),
		Float32.Quantize(z),
	}
	return Vector3Factory(fields) :: Vector3
end

local function magnitudeOf(fields: Userdata.Fields): number
	local x, y, z = numAt(fields, 1), numAt(fields, 2), numAt(fields, 3)
	return Float32.Quantize(math.sqrt(x * x + y * y + z * z))
end

-- Se a magnitude é 0, todos os componentes de entrada são 0 -> 0/0 = NaN nos três, sem precisar
-- de um caso especial -- exatamente o comportamento documentado (pesquisa §3: "se magnitude 0,
-- resulta em componentes NaN", não `(0,0,0)`).
local function unitOf(fields: Userdata.Fields): Vector3
	local x, y, z = numAt(fields, 1), numAt(fields, 2), numAt(fields, 3)
	local magnitude = math.sqrt(x * x + y * y + z * z)
	return construct(x / magnitude, y / magnitude, z / magnitude)
end

local function getProperty(fields: Userdata.Fields, key: string): (unknown, boolean)
	if key == "X" then
		return numAt(fields, 1), true
	elseif key == "Y" then
		return numAt(fields, 2), true
	elseif key == "Z" then
		return numAt(fields, 3), true
	elseif key == "Magnitude" then
		return magnitudeOf(fields), true
	elseif key == "Unit" then
		return unitOf(fields), true
	end
	return nil, false
end

-- Ângulo entre `a` e `b`: SEM eixo, unsigned em [0,π] via atan2(|cross|, dot) -- range e sinal
-- confirmados pela pesquisa, a fórmula em si é implementação própria (ver cabeçalho). COM eixo,
-- sinalizado em [-π,π]: o sinal vem da projeção do vetor cross sobre o eixo dado.
local function angleBetween(aFields: Userdata.Fields, bFields: Userdata.Fields, axisFields: Userdata.Fields?): number
	local ax, ay, az = numAt(aFields, 1), numAt(aFields, 2), numAt(aFields, 3)
	local bx, by, bz = numAt(bFields, 1), numAt(bFields, 2), numAt(bFields, 3)

	local cx = ay * bz - az * by
	local cy = az * bx - ax * bz
	local cz = ax * by - ay * bx
	local crossMagnitude = math.sqrt(cx * cx + cy * cy + cz * cz)
	local dot = ax * bx + ay * by + az * bz

	local unsigned = math.atan2(crossMagnitude, dot)
	if axisFields == nil then
		return Float32.Quantize(unsigned)
	end

	local axisDot = cx * numAt(axisFields, 1) + cy * numAt(axisFields, 2) + cz * numAt(axisFields, 3)
	if axisDot < 0 then
		return Float32.Quantize(-unsigned)
	end
	return Float32.Quantize(unsigned)
end

local function fuzzyEq(aFields: Userdata.Fields, bFields: Userdata.Fields, epsilon: number): boolean
	for index = 1, 3 do
		local a, b = numAt(aFields, index), numAt(bFields, index)
		local scale = math.max(math.abs(a), math.abs(b), 1)
		if math.abs(a - b) > epsilon * scale then
			return false
		end
	end
	return true
end

local methods: { [string]: unknown } = {
	Abs = function(self: unknown): unknown
		local fields = Userdata.Unwrap(self, TYPE_NAME)
		return construct(math.abs(numAt(fields, 1)), math.abs(numAt(fields, 2)), math.abs(numAt(fields, 3)))
	end,

	Ceil = function(self: unknown): unknown
		local fields = Userdata.Unwrap(self, TYPE_NAME)
		return construct(math.ceil(numAt(fields, 1)), math.ceil(numAt(fields, 2)), math.ceil(numAt(fields, 3)))
	end,

	Floor = function(self: unknown): unknown
		local fields = Userdata.Unwrap(self, TYPE_NAME)
		return construct(math.floor(numAt(fields, 1)), math.floor(numAt(fields, 2)), math.floor(numAt(fields, 3)))
	end,

	Sign = function(self: unknown): unknown
		local fields = Userdata.Unwrap(self, TYPE_NAME)
		return construct(signOf(numAt(fields, 1)), signOf(numAt(fields, 2)), signOf(numAt(fields, 3)))
	end,

	-- Retorna Vector3 (regra da mão direita) -- DIFERENTE de Vector2:Cross, que retorna um
	-- `number` escalar. Assimetria real confirmada pela pesquisa (§4), não copiar-e-colar.
	Cross = function(self: unknown, other: unknown): unknown
		local a = Userdata.Unwrap(self, TYPE_NAME)
		local b = Userdata.Unwrap(other, TYPE_NAME)
		local ax, ay, az = numAt(a, 1), numAt(a, 2), numAt(a, 3)
		local bx, by, bz = numAt(b, 1), numAt(b, 2), numAt(b, 3)
		return construct(ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx)
	end,

	Angle = function(self: unknown, other: unknown, axis: unknown): unknown
		local a = Userdata.Unwrap(self, TYPE_NAME)
		local b = Userdata.Unwrap(other, TYPE_NAME)
		local axisFields: Userdata.Fields? = if axis == nil then nil else Userdata.Unwrap(axis, TYPE_NAME)
		return angleBetween(a, b, axisFields)
	end,

	Dot = function(self: unknown, other: unknown): unknown
		local a = Userdata.Unwrap(self, TYPE_NAME)
		local b = Userdata.Unwrap(other, TYPE_NAME)
		local dot = numAt(a, 1) * numAt(b, 1) + numAt(a, 2) * numAt(b, 2) + numAt(a, 3) * numAt(b, 3)
		return Float32.Quantize(dot)
	end,

	-- `vector: Vector3` -- UM ÚNICO argumento. DIFERENTE de Vector2:Max, que aceita tupla
	-- variádica. Assimetria real confirmada pela pesquisa (§4), não copiar-e-colar.
	Max = function(self: unknown, other: unknown): unknown
		local a = Userdata.Unwrap(self, TYPE_NAME)
		local b = Userdata.Unwrap(other, TYPE_NAME)
		return construct(
			math.max(numAt(a, 1), numAt(b, 1)),
			math.max(numAt(a, 2), numAt(b, 2)),
			math.max(numAt(a, 3), numAt(b, 3))
		)
	end,

	Min = function(self: unknown, other: unknown): unknown
		local a = Userdata.Unwrap(self, TYPE_NAME)
		local b = Userdata.Unwrap(other, TYPE_NAME)
		return construct(
			math.min(numAt(a, 1), numAt(b, 1)),
			math.min(numAt(a, 2), numAt(b, 2)),
			math.min(numAt(a, 3), numAt(b, 3))
		)
	end,

	FuzzyEq = function(self: unknown, other: unknown, epsilon: unknown): unknown
		local a = Userdata.Unwrap(self, TYPE_NAME)
		local b = Userdata.Unwrap(other, TYPE_NAME)
		local eps: number = if epsilon == nil then DEFAULT_FUZZY_EPSILON else (epsilon :: number)
		return fuzzyEq(a, b, eps)
	end,

	-- `alpha` NÃO é clampado (confirmado pela pesquisa §4) -- `Lerp(goal, 2)` extrapola.
	Lerp = function(self: unknown, goal: unknown, alpha: unknown): unknown
		local a = Userdata.Unwrap(self, TYPE_NAME)
		local b = Userdata.Unwrap(goal, TYPE_NAME)
		local t = alpha :: number
		return construct(
			numAt(a, 1) + (numAt(b, 1) - numAt(a, 1)) * t,
			numAt(a, 2) + (numAt(b, 2) - numAt(a, 2)) * t,
			numAt(a, 3) + (numAt(b, 3) - numAt(a, 3)) * t
		)
	end,
}
table.freeze(methods)

-- Componente a componente (soma/subtração só existem entre dois Vector3, confirmado §5).
local function add(a: Userdata.Fields, b: Userdata.Fields, bTypeName: string): unknown
	if bTypeName ~= TYPE_NAME then
		error(`attempt to perform arithmetic (add) on {TYPE_NAME} and {bTypeName}`, 3)
	end
	return construct(numAt(a, 1) + numAt(b, 1), numAt(a, 2) + numAt(b, 2), numAt(a, 3) + numAt(b, 3))
end

local function sub(a: Userdata.Fields, b: Userdata.Fields, bTypeName: string): unknown
	if bTypeName ~= TYPE_NAME then
		error(`attempt to perform arithmetic (sub) on {TYPE_NAME} and {bTypeName}`, 3)
	end
	return construct(numAt(a, 1) - numAt(b, 1), numAt(a, 2) - numAt(b, 2), numAt(a, 3) - numAt(b, 3))
end

-- Vector3*Vector3 (componente a componente -- NÃO é dot nem cross, confirmado §5),
-- Vector3*number e number*Vector3 (escalar, comutativo -- o Luau despacha pro nosso __mul
-- em qualquer ordem já que number não tem metamétodo próprio).
local function mul(a: unknown, b: unknown): unknown
	local aFields = tryUnwrap(a)
	local bFields = tryUnwrap(b)
	if aFields ~= nil and bFields ~= nil then
		return construct(
			numAt(aFields, 1) * numAt(bFields, 1),
			numAt(aFields, 2) * numAt(bFields, 2),
			numAt(aFields, 3) * numAt(bFields, 3)
		)
	elseif aFields ~= nil and typeof(b) == "number" then
		local scalar = b :: number
		return construct(numAt(aFields, 1) * scalar, numAt(aFields, 2) * scalar, numAt(aFields, 3) * scalar)
	elseif bFields ~= nil and typeof(a) == "number" then
		local scalar = a :: number
		return construct(numAt(bFields, 1) * scalar, numAt(bFields, 2) * scalar, numAt(bFields, 3) * scalar)
	end
	error(`attempt to perform arithmetic (mul) on {describeType(a)} and {describeType(b)}`, 2)
end

-- Vector3/Vector3 e Vector3/number -- SEM reverso (number/Vector3 não existe, confirmado §5:
-- só "Vector3 / Vector3" e "Vector3 / number" aparecem em math_operations, nessa ordem).
local function div(a: unknown, b: unknown): unknown
	local aFields = tryUnwrap(a)
	if aFields == nil then
		error(`attempt to perform arithmetic (div) on {describeType(a)} and {describeType(b)}`, 2)
	end
	local bFields = tryUnwrap(b)
	if bFields ~= nil then
		return construct(
			numAt(aFields, 1) / numAt(bFields, 1),
			numAt(aFields, 2) / numAt(bFields, 2),
			numAt(aFields, 3) / numAt(bFields, 3)
		)
	elseif typeof(b) == "number" then
		local scalar = b :: number
		return construct(numAt(aFields, 1) / scalar, numAt(aFields, 2) / scalar, numAt(aFields, 3) / scalar)
	end
	error(`attempt to perform arithmetic (div) on {TYPE_NAME} and {describeType(b)}`, 2)
end

-- Vector3//Vector3 e Vector3//number -- confirmado §5. Vector2 NÃO tem este operador (ver
-- types/Vector2.luau) -- assimetria real, IDiv fica de fora do Descriptor dele.
local function idiv(a: unknown, b: unknown): unknown
	local aFields = tryUnwrap(a)
	if aFields == nil then
		error(`attempt to perform arithmetic (idiv) on {describeType(a)} and {describeType(b)}`, 2)
	end
	local bFields = tryUnwrap(b)
	if bFields ~= nil then
		return construct(
			numAt(aFields, 1) // numAt(bFields, 1),
			numAt(aFields, 2) // numAt(bFields, 2),
			numAt(aFields, 3) // numAt(bFields, 3)
		)
	elseif typeof(b) == "number" then
		local scalar = b :: number
		return construct(numAt(aFields, 1) // scalar, numAt(aFields, 2) // scalar, numAt(aFields, 3) // scalar)
	end
	error(`attempt to perform arithmetic (idiv) on {TYPE_NAME} and {describeType(b)}`, 2)
end

-- Unário `-v` -- evidência indireta, ver cabeçalho.
local function unm(a: Userdata.Fields): unknown
	return construct(-numAt(a, 1), -numAt(a, 2), -numAt(a, 3))
end

-- P8 (ver cabeçalho): exato, componente a componente. Aproximação de boa-fé não confirmada.
local function equals(a: Userdata.Fields, b: Userdata.Fields): boolean
	return numAt(a, 1) == numAt(b, 1) and numAt(a, 2) == numAt(b, 2) and numAt(a, 3) == numAt(b, 3)
end

local function format(fields: Userdata.Fields): string
	return `{Float32.Format(numAt(fields, 1))}, {Float32.Format(numAt(fields, 2))}, {Float32.Format(numAt(fields, 3))}`
end

Vector3Factory = Userdata.Define({
	TypeName = TYPE_NAME,
	Methods = methods,
	GetProperty = getProperty,
	Format = format,
	Add = add,
	Sub = sub,
	Mul = mul,
	Div = div,
	IDiv = idiv,
	Unm = unm,
	Equals = equals,
})

local Vector3 = {}

function Vector3.new(x: number?, y: number?, z: number?): Vector3
	return construct(x or 0, y or 0, z or 0)
end

-- Mapeamento Top/Front CITADO LITERALMENTE pela pesquisa (Vector3.yaml). Bottom/Back/Left/Right
-- INFERIDOS (opostos óbvios) -- ver cabeçalho, "Outras aproximações".
local NORMAL_ID_TO_VECTOR: { [string]: { number } } = {
	Top = { 0, 1, 0 },
	Bottom = { 0, -1, 0 },
	Front = { 0, 0, -1 },
	Back = { 0, 0, 1 },
	Right = { 1, 0, 0 },
	Left = { -1, 0, 0 },
}

-- Os TRÊS confirmados literalmente pela pesquisa (Vector3.yaml).
local AXIS_TO_VECTOR: { [string]: { number } } = {
	X = { 1, 0, 0 },
	Y = { 0, 1, 0 },
	Z = { 0, 0, 1 },
}

-- Ver cabeçalho, "Outras aproximações" -- `normal` é `EnumItemLike`, não `Enum.NormalId` de
-- verdade (o módulo Enum ainda não existe nesta leva).
function Vector3.FromNormalId(normal: EnumItemLike): Vector3
	local vector = NORMAL_ID_TO_VECTOR[normal.Name]
	if vector == nil then
		error(`Vector3.FromNormalId: '{normal.Name}' não é um Enum.NormalId válido`, 2)
	end
	return construct(vector[1], vector[2], vector[3])
end

function Vector3.FromAxis(axis: EnumItemLike): Vector3
	local vector = AXIS_TO_VECTOR[axis.Name]
	if vector == nil then
		error(`Vector3.FromAxis: '{axis.Name}' não é um Enum.Axis válido`, 2)
	end
	return construct(vector[1], vector[2], vector[3])
end

Vector3.zero = construct(0, 0, 0)
Vector3.one = construct(1, 1, 1)
Vector3.xAxis = construct(1, 0, 0)
Vector3.yAxis = construct(0, 1, 0)
Vector3.zAxis = construct(0, 0, 1)

return Vector3
