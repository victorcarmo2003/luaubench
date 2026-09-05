--!strict

--[[
	Vector2 simulado (task-valuetypes-004). Desenho completo em
	.claude/agents-memory/arquiteto-valuetypes-2026-09-05.md (seção 3.2). Toda assinatura
	confirmada contra o YAML oficial (`Roblox/creator-docs`) em
	.claude/agents-memory/pesquisa-datatypes-vector-cframe-2026-09-05.md, seções 1-9 -- nenhuma
	assinatura aqui vem de memória.

	`type(Vector2.new())` aqui e no Roblox real são AMBOS "userdata" -- Vector2 NÃO foi migrado
	pro tipo primitivo `vector` da VM Luau (só Vector3 foi, ver o cabeçalho de types/Vector3.luau
	pra D8, que É sobre Vector3, não Vector2). Sem divergência de `type()` a declarar aqui.

	## PENDÊNCIA P8 (NÃO CONFIRMADA -- ver desenho §9, mesma pendência de types/Vector3.luau)

	`==` aqui é EXATO, componente a componente (`Equals`, abaixo) -- mesma inferência e mesma
	ressalva que Vector3: a doc não confirma isso por citação direta, é inferido da existência de
	`FuzzyEq` como método separado. APROXIMAÇÃO DE BOA-FÉ, não confirmada.

	## ASSIMETRIAS REAIS entre Vector2 e Vector3 (confirmadas pela pesquisa, §4/§5 -- NUNCA
	## copiadas-e-coladas de Vector3.luau; cada uma citada onde aparece abaixo)

	1. **Vector2 NÃO tem operador `//`** (floor division). `math_operations` do Vector2.yaml lista
	   só 6 entradas (+, -, * dois sabores, / dois sabores) -- SEM `//` nem vetor-vetor nem
	   vetor-número. `Descriptor.IDiv` fica de fora (nil) de propósito -- o erro nativo do Luau
	   ("attempt to perform arithmetic") é o comportamento certo pra `Vector2.new(1,2) // 2`.
	2. **`Vector2:Cross()` devolve `number`** (escalar `X*other.Y - Y*other.X`), NÃO um Vector2 --
	   diferente de `Vector3:Cross()`, que devolve Vector3.
	3. **`Vector2:Max`/`Vector2:Min` aceitam TUPLA VARIÁDICA** (`others...: Tuple`, literal no
	   YAML) -- diferente de `Vector3:Max`/`Vector3:Min`, que aceitam só UM argumento.
	4. **`FuzzyEq` usa um algoritmo DIFERENTE do de Vector3**: aqui é `|a_i - b_i| <= epsilon` puro
	   por componente (confirmado em prosa: "comparação por componente"), SEM escala pela
	   magnitude -- Vector3.FuzzyEq usa um epsilon "híbrido" que escala com a magnitude (ver
	   types/Vector3.luau). O epsilon DEFAULT é igual nos dois (`1e-5`, confirmado literal e igual
	   nos 3 tipos -- só o ALGORITMO difere).
	5. **Vector2 NÃO tem `zAxis`** (óbvio, é 2D) -- só `zero`/`one`/`xAxis`/`yAxis`.
	6. **Vector2 NÃO tem `FromNormalId`/`FromAxis`** -- confirmado que esses dois construtores só
	   existem em Vector3.yaml, sem equivalente em Vector2.yaml.

	## Outras aproximações declaradas nesta tarefa (regra 00 -- nunca silenciosas)

	- Unário `-v`: suportado POR ANALOGIA com Vector3 -- a pesquisa NÃO tem evidência direta (nem
	  indireta) específica de Vector2 suportando `-` (só viu o exemplo de prosa `-cf.ZVector` pra
	  Vector3/CFrame, ver pesquisa §5). Confiança MENOR que a de Vector3. Documentado aqui como
	  aproximação, não fato citado.
	- `Angle(other, isSigned?)`: a doc só confirma o INTERVALO de saída ([0,π] sem sinal, [-π,π]
	  com sinal), não a fórmula exata -- implementado via `atan2(cross, dot)`/`atan2(|cross|, dot)`,
	  forma numericamente padrão, não citação literal do motor Roblox (fechado).
	- `Magnitude`/`Dot`/`Cross`/`Angle` (retornos `number`): quantizados pra float32 via
	  `Float32.Quantize`, mesma extensão de boa-fé da Decisão 3 documentada em types/Vector3.luau.

	Depende de: `../Float32`, `../Userdata`. Nenhuma dependência de `runtime`/`services`/`cli`
	(módulo-folha do território, ver desenho §2).
]]

local Float32 = require("../Float32")
local Userdata = require("../Userdata")

local TYPE_NAME = "Vector2"

-- Epsilon default de `FuzzyEq`, confirmado LITERAL e IGUAL nos três tipos (Vector3/Vector2/
-- CFrame) pela pesquisa (§9): `0.00001` (`1e-5`). O ALGORITMO difere de Vector3 -- ver cabeçalho.
local DEFAULT_FUZZY_EPSILON = 0.00001

export type Vector2 = typeof(setmetatable(
	{} :: {
		X: number,
		Y: number,
		Magnitude: number,
		Unit: Vector2,
		-- Métodos de instância (sintaxe `v:Metodo(...)`) -- precisam estar aqui, na parte de
		-- TABELA do tipo opaco, não na metatable (mesmo padrão de types/Vector3.luau e de
		-- `SpecPoint`/`SpecColor` em Userdata.spec.luau). Vitrine pro type-checker; quem valida
		-- de verdade em runtime é `Userdata.luau:sharedIndex`.
		Abs: (self: Vector2) -> Vector2,
		Ceil: (self: Vector2) -> Vector2,
		Floor: (self: Vector2) -> Vector2,
		Sign: (self: Vector2) -> Vector2,
		-- Devolve `number` ESCALAR -- DIFERENTE de Vector3:Cross (devolve Vector3), assimetria 2.
		Cross: (self: Vector2, other: Vector2) -> number,
		Angle: (self: Vector2, other: Vector2, isSigned: boolean?) -> number,
		Dot: (self: Vector2, other: Vector2) -> number,
		FuzzyEq: (self: Vector2, other: Vector2, epsilon: number?) -> boolean,
		Lerp: (self: Vector2, goal: Vector2, alpha: number) -> Vector2,
		-- TUPLA VARIÁDICA -- DIFERENTE de Vector3:Max/Min (um único argumento), assimetria 3.
		Max: (self: Vector2, ...Vector2) -> Vector2,
		Min: (self: Vector2, ...Vector2) -> Vector2,
	},
	{} :: {
		__add: (Vector2, Vector2) -> Vector2,
		__sub: (Vector2, Vector2) -> Vector2,
		__mul: ((Vector2, Vector2) -> Vector2) & ((Vector2, number) -> Vector2) & ((number, Vector2) -> Vector2),
		__div: (Vector2, Vector2 | number) -> Vector2,
		-- SEM __idiv -- Vector2 não tem `//` (assimetria 1, ver cabeçalho).
		__unm: (Vector2) -> Vector2,
		__eq: (Vector2, Vector2) -> boolean,
		__tostring: (Vector2) -> string,
	}
))

local function numAt(fields: Userdata.Fields, index: number): number
	return fields[index] :: number
end

local function describeType(value: unknown): string
	local name = Userdata.TypeNameOf(value)
	if name ~= nil then
		return name
	end
	return typeof(value)
end

local function tryUnwrap(value: unknown): Userdata.Fields?
	if Userdata.TypeNameOf(value) == TYPE_NAME then
		return Userdata.Unwrap(value, TYPE_NAME)
	end
	return nil
end

local Vector2Factory: Userdata.Factory

-- Construtor privado ÚNICO (Decisão 3 do desenho): quantiza os dois componentes pra float32
-- aqui, e só aqui -- toda a aritmética fica encadeada em float32 automaticamente.
local function construct(x: number, y: number): Vector2
	local fields: Userdata.Fields = {
		Float32.Quantize(x),
		Float32.Quantize(y),
	}
	return Vector2Factory(fields) :: Vector2
end

local function magnitudeOf(fields: Userdata.Fields): number
	local x, y = numAt(fields, 1), numAt(fields, 2)
	return Float32.Quantize(math.sqrt(x * x + y * y))
end

-- Se a magnitude é 0, os dois componentes de entrada são 0 -> 0/0 = NaN nos dois, sem precisar
-- de caso especial -- comportamento documentado (pesquisa §3: "indefinido, contém valores nan").
local function unitOf(fields: Userdata.Fields): Vector2
	local x, y = numAt(fields, 1), numAt(fields, 2)
	local magnitude = math.sqrt(x * x + y * y)
	return construct(x / magnitude, y / magnitude)
end

local function getProperty(fields: Userdata.Fields, key: string): (unknown, boolean)
	if key == "X" then
		return numAt(fields, 1), true
	elseif key == "Y" then
		return numAt(fields, 2), true
	elseif key == "Magnitude" then
		return magnitudeOf(fields), true
	elseif key == "Unit" then
		return unitOf(fields), true
	end
	return nil, false
end

-- SEM sinal: [0,π] via atan2(|cross|, dot). COM sinal: [-π,π] via atan2(cross, dot) -- o sinal
-- do escalar cross já carrega a orientação em 2D (não precisa de eixo externo como em Vector3).
local function angleBetween(aFields: Userdata.Fields, bFields: Userdata.Fields, isSigned: boolean): number
	local ax, ay = numAt(aFields, 1), numAt(aFields, 2)
	local bx, by = numAt(bFields, 1), numAt(bFields, 2)
	local cross = ax * by - ay * bx
	local dot = ax * bx + ay * by
	if isSigned then
		return Float32.Quantize(math.atan2(cross, dot))
	end
	return Float32.Quantize(math.atan2(math.abs(cross), dot))
end

-- Algoritmo DIFERENTE do de Vector3 (ver cabeçalho, assimetria 4): abs puro por componente, sem
-- escala pela magnitude.
local function fuzzyEq(aFields: Userdata.Fields, bFields: Userdata.Fields, epsilon: number): boolean
	return math.abs(numAt(aFields, 1) - numAt(bFields, 1)) <= epsilon
		and math.abs(numAt(aFields, 2) - numAt(bFields, 2)) <= epsilon
end

local methods: { [string]: unknown } = {
	Abs = function(self: unknown): unknown
		local fields = Userdata.Unwrap(self, TYPE_NAME)
		return construct(math.abs(numAt(fields, 1)), math.abs(numAt(fields, 2)))
	end,

	Ceil = function(self: unknown): unknown
		local fields = Userdata.Unwrap(self, TYPE_NAME)
		return construct(math.ceil(numAt(fields, 1)), math.ceil(numAt(fields, 2)))
	end,

	Floor = function(self: unknown): unknown
		local fields = Userdata.Unwrap(self, TYPE_NAME)
		return construct(math.floor(numAt(fields, 1)), math.floor(numAt(fields, 2)))
	end,

	Sign = function(self: unknown): unknown
		local fields = Userdata.Unwrap(self, TYPE_NAME)
		local function signOf(value: number): number
			if value > 0 then
				return 1
			elseif value < 0 then
				return -1
			end
			return 0
		end
		return construct(signOf(numAt(fields, 1)), signOf(numAt(fields, 2)))
	end,

	-- Retorna `number` ESCALAR (`X*other.Y - Y*other.X`) -- DIFERENTE de Vector3:Cross, que
	-- retorna um Vector3 novo. Assimetria real confirmada pela pesquisa (§4), não
	-- copiar-e-colar de types/Vector3.luau.
	Cross = function(self: unknown, other: unknown): unknown
		local a = Userdata.Unwrap(self, TYPE_NAME)
		local b = Userdata.Unwrap(other, TYPE_NAME)
		local cross = numAt(a, 1) * numAt(b, 2) - numAt(a, 2) * numAt(b, 1)
		return Float32.Quantize(cross)
	end,

	Angle = function(self: unknown, other: unknown, isSigned: unknown): unknown
		local a = Userdata.Unwrap(self, TYPE_NAME)
		local b = Userdata.Unwrap(other, TYPE_NAME)
		local signedFlag: boolean = if isSigned == nil then false else (isSigned :: boolean)
		return angleBetween(a, b, signedFlag)
	end,

	Dot = function(self: unknown, other: unknown): unknown
		local a = Userdata.Unwrap(self, TYPE_NAME)
		local b = Userdata.Unwrap(other, TYPE_NAME)
		return Float32.Quantize(numAt(a, 1) * numAt(b, 1) + numAt(a, 2) * numAt(b, 2))
	end,

	-- `Lerp(v, alpha)` -- `alpha` NÃO é clampado (confirmado §4), igual a Vector3.
	Lerp = function(self: unknown, goal: unknown, alpha: unknown): unknown
		local a = Userdata.Unwrap(self, TYPE_NAME)
		local b = Userdata.Unwrap(goal, TYPE_NAME)
		local t = alpha :: number
		return construct(numAt(a, 1) + (numAt(b, 1) - numAt(a, 1)) * t, numAt(a, 2) + (numAt(b, 2) - numAt(a, 2)) * t)
	end,

	-- `others...: Tuple` -- TUPLA VARIÁDICA confirmada pelo YAML oficial (assimetria 3, ver
	-- cabeçalho). DIFERENTE de Vector3:Max, que aceita só um argumento.
	Max = function(self: unknown, ...: unknown): unknown
		local selfFields = Userdata.Unwrap(self, TYPE_NAME)
		local maxX, maxY = numAt(selfFields, 1), numAt(selfFields, 2)
		local count = select("#", ...)
		for index = 1, count do
			local other = select(index, ...)
			local fields = Userdata.Unwrap(other, TYPE_NAME)
			maxX = math.max(maxX, numAt(fields, 1))
			maxY = math.max(maxY, numAt(fields, 2))
		end
		return construct(maxX, maxY)
	end,

	Min = function(self: unknown, ...: unknown): unknown
		local selfFields = Userdata.Unwrap(self, TYPE_NAME)
		local minX, minY = numAt(selfFields, 1), numAt(selfFields, 2)
		local count = select("#", ...)
		for index = 1, count do
			local other = select(index, ...)
			local fields = Userdata.Unwrap(other, TYPE_NAME)
			minX = math.min(minX, numAt(fields, 1))
			minY = math.min(minY, numAt(fields, 2))
		end
		return construct(minX, minY)
	end,

	FuzzyEq = function(self: unknown, other: unknown, epsilon: unknown): unknown
		local a = Userdata.Unwrap(self, TYPE_NAME)
		local b = Userdata.Unwrap(other, TYPE_NAME)
		local eps: number = if epsilon == nil then DEFAULT_FUZZY_EPSILON else (epsilon :: number)
		return fuzzyEq(a, b, eps)
	end,
}
table.freeze(methods)

local function add(a: Userdata.Fields, b: Userdata.Fields, bTypeName: string): unknown
	if bTypeName ~= TYPE_NAME then
		error(`attempt to perform arithmetic (add) on {TYPE_NAME} and {bTypeName}`, 3)
	end
	return construct(numAt(a, 1) + numAt(b, 1), numAt(a, 2) + numAt(b, 2))
end

local function sub(a: Userdata.Fields, b: Userdata.Fields, bTypeName: string): unknown
	if bTypeName ~= TYPE_NAME then
		error(`attempt to perform arithmetic (sub) on {TYPE_NAME} and {bTypeName}`, 3)
	end
	return construct(numAt(a, 1) - numAt(b, 1), numAt(a, 2) - numAt(b, 2))
end

-- Vector2*Vector2 (componente a componente), Vector2*number e number*Vector2 (escalar,
-- comutativo). SEM `//` (assimetria 1, ver cabeçalho) -- não há função `idiv` neste arquivo.
local function mul(a: unknown, b: unknown): unknown
	local aFields = tryUnwrap(a)
	local bFields = tryUnwrap(b)
	if aFields ~= nil and bFields ~= nil then
		return construct(numAt(aFields, 1) * numAt(bFields, 1), numAt(aFields, 2) * numAt(bFields, 2))
	elseif aFields ~= nil and typeof(b) == "number" then
		local scalar = b :: number
		return construct(numAt(aFields, 1) * scalar, numAt(aFields, 2) * scalar)
	elseif bFields ~= nil and typeof(a) == "number" then
		local scalar = a :: number
		return construct(numAt(bFields, 1) * scalar, numAt(bFields, 2) * scalar)
	end
	error(`attempt to perform arithmetic (mul) on {describeType(a)} and {describeType(b)}`, 2)
end

-- Vector2/Vector2 e Vector2/number -- SEM reverso (number/Vector2 não existe, mesma lógica de
-- Vector3.luau).
local function div(a: unknown, b: unknown): unknown
	local aFields = tryUnwrap(a)
	if aFields == nil then
		error(`attempt to perform arithmetic (div) on {describeType(a)} and {describeType(b)}`, 2)
	end
	local bFields = tryUnwrap(b)
	if bFields ~= nil then
		return construct(numAt(aFields, 1) / numAt(bFields, 1), numAt(aFields, 2) / numAt(bFields, 2))
	elseif typeof(b) == "number" then
		local scalar = b :: number
		return construct(numAt(aFields, 1) / scalar, numAt(aFields, 2) / scalar)
	end
	error(`attempt to perform arithmetic (div) on {TYPE_NAME} and {describeType(b)}`, 2)
end

-- Unário `-v` -- por ANALOGIA com Vector3, confiança MENOR (ver cabeçalho).
local function unm(a: Userdata.Fields): unknown
	return construct(-numAt(a, 1), -numAt(a, 2))
end

-- P8 (ver cabeçalho): exato, componente a componente. Aproximação de boa-fé não confirmada.
local function equals(a: Userdata.Fields, b: Userdata.Fields): boolean
	return numAt(a, 1) == numAt(b, 1) and numAt(a, 2) == numAt(b, 2)
end

local function format(fields: Userdata.Fields): string
	return `{Float32.Format(numAt(fields, 1))}, {Float32.Format(numAt(fields, 2))}`
end

Vector2Factory = Userdata.Define({
	TypeName = TYPE_NAME,
	Methods = methods,
	GetProperty = getProperty,
	Format = format,
	Add = add,
	Sub = sub,
	Mul = mul,
	Div = div,
	-- IDiv deliberadamente AUSENTE -- Vector2 não tem `//` (assimetria 1, ver cabeçalho).
	Unm = unm,
	Equals = equals,
})

local Vector2 = {}

function Vector2.new(x: number?, y: number?): Vector2
	return construct(x or 0, y or 0)
end

Vector2.zero = construct(0, 0)
Vector2.one = construct(1, 1)
Vector2.xAxis = construct(1, 0)
Vector2.yAxis = construct(0, 1)
-- SEM zAxis (assimetria 5, ver cabeçalho) -- Vector2 é 2D.

return Vector2
