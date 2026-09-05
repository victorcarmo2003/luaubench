--!strict

--[[
	Teste da task-valuetypes-004 (types/Vector2.luau). Cobre construtores, constantes,
	propriedades, cada método, cada operador suportado, tostring e precisão f32 (paridade com o
	`vector` nativo do Luau, usado aqui só como ORÁCULO de precisão -- Vector2 nunca foi
	representado por ele, só Vector3 no Roblox real -- ver cabeçalho de types/Vector2.luau).

	Roda com `lune run src/valuetypes/types/Vector2.spec.luau`.

	Cobertura ESPECÍFICA das assimetrias reais com Vector3 (ver cabeçalho de Vector2.luau, e a
	descrição da task-valuetypes-004): SEM `//`, `:Cross()` devolve `number`, `:Max`/`:Min`
	aceitam tupla variádica, `:FuzzyEq` usa algoritmo diferente (abs puro, sem escala).

	SEM `any` -- mesmo precedente de tipo sintético `AnyOperable` usado em Vector3.spec.luau.
]]

local process = require("@lune/process")
local Vector2 = require("./Vector2")
local Vector3 = require("./Vector3")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

type AnyOperable = typeof(setmetatable(
	{} :: {},
	{} :: {
		__add: (AnyOperable, AnyOperable) -> AnyOperable,
		__sub: (AnyOperable, AnyOperable) -> AnyOperable,
		__mul: (AnyOperable, AnyOperable) -> AnyOperable,
		__div: (AnyOperable, AnyOperable) -> AnyOperable,
		__idiv: (AnyOperable, AnyOperable) -> AnyOperable,
		__eq: (AnyOperable, AnyOperable) -> boolean,
	}
))
local function op(value: unknown): AnyOperable
	return value :: AnyOperable
end

type StringIndexableProbe = typeof(setmetatable({} :: { [string]: unknown }, {}))
local function asStringIndexable(value: unknown): StringIndexableProbe
	return value :: StringIndexableProbe
end

-- ================================================================================================
-- Construtores
-- ================================================================================================

test("Vector2.new() usa default (0,0)", function()
	local v = Vector2.new()
	assert(v.X == 0 and v.Y == 0, `esperava (0,0), recebeu ({v.X},{v.Y})`)
end)

test("Vector2.new(x,y) constrói com os valores dados", function()
	local v = Vector2.new(3, 4)
	assert(v.X == 3 and v.Y == 4, `esperava (3,4), recebeu ({v.X},{v.Y})`)
end)

test("Vector2.new com argumento parcial usa 0 pro ausente", function()
	local v = Vector2.new(5)
	assert(v.X == 5 and v.Y == 0, `esperava (5,0), recebeu ({v.X},{v.Y})`)
end)

test("Vector2 NÃO tem FromNormalId/FromAxis (assimetria 6, ver cabeçalho de Vector2.luau)", function()
	local vectorModule = asStringIndexable(Vector2)
	assert(vectorModule.FromNormalId == nil, "Vector2.FromNormalId não deveria existir")
	assert(vectorModule.FromAxis == nil, "Vector2.FromAxis não deveria existir")
end)

-- ================================================================================================
-- Constantes
-- ================================================================================================

test("constantes estáticas têm os valores certos, SEM zAxis (assimetria 5)", function()
	local zero, one = Vector2.zero, Vector2.one
	assert(zero.X == 0 and zero.Y == 0, "Vector2.zero deveria ser (0,0)")
	assert(one.X == 1 and one.Y == 1, "Vector2.one deveria ser (1,1)")
	local xAxis, yAxis = Vector2.xAxis, Vector2.yAxis
	assert(xAxis.X == 1 and xAxis.Y == 0, "Vector2.xAxis deveria ser (1,0)")
	assert(yAxis.X == 0 and yAxis.Y == 1, "Vector2.yAxis deveria ser (0,1)")
	assert(asStringIndexable(Vector2).zAxis == nil, "Vector2 NÃO deveria ter zAxis -- é 2D")
end)

-- ================================================================================================
-- Propriedades
-- ================================================================================================

test("X/Y lidos corretamente", function()
	local v = Vector2.new(7, 8)
	assert(v.X == 7 and v.Y == 8, "leitura de X/Y incorreta")
end)

test("Magnitude == sqrt(X^2+Y^2)", function()
	local v = Vector2.new(3, 4)
	assert(v.Magnitude == 5, `esperava Magnitude 5, recebeu {v.Magnitude}`)
end)

test("Unit normaliza corretamente", function()
	local v = Vector2.new(3, 4)
	local unit = v.Unit
	assert(math.abs(unit.X - 0.6) < 1e-6, `esperava Unit.X ~= 0.6, recebeu {unit.X}`)
	assert(math.abs(unit.Y - 0.8) < 1e-6, `esperava Unit.Y ~= 0.8, recebeu {unit.Y}`)
end)

test("Unit de Vector2.zero produz NaN nos 2 componentes (não (0,0)) -- confirmado pela pesquisa §3", function()
	local unit = Vector2.zero.Unit
	assert(unit.X ~= unit.X, "Unit.X de zero deveria ser NaN")
	assert(unit.Y ~= unit.Y, "Unit.Y de zero deveria ser NaN")
end)

test("ler uma propriedade inválida erra citando a chave e o TypeName", function()
	local v = Vector2.new(1, 2)
	local ok, err = pcall(function()
		return asStringIndexable(v).NaoExiste
	end)
	assert(not ok, "ler uma propriedade inválida deveria errar")
	local message = tostring(err)
	assert(string.find(message, "NaoExiste", 1, true) ~= nil, `mensagem deveria citar a chave, recebeu: {message}`)
	assert(string.find(message, "Vector2", 1, true) ~= nil, `mensagem deveria citar o TypeName, recebeu: {message}`)
end)

test("escrever numa propriedade erra -- Vector2 é imutável", function()
	local v = Vector2.new(1, 2)
	local ok = pcall(function()
		asStringIndexable(v).X = 99
	end)
	assert(not ok, "escrever em X deveria errar")
	assert(v.X == 1, "X não deveria ter mudado")
end)

-- ================================================================================================
-- Métodos
-- ================================================================================================

test(":Abs()", function()
	local v = Vector2.new(-1, 2):Abs()
	assert(v.X == 1 and v.Y == 2, `esperava (1,2), recebeu ({v.X},{v.Y})`)
end)

test(":Ceil()", function()
	local v = Vector2.new(1.1, -1.1):Ceil()
	assert(v.X == 2 and v.Y == -1, `esperava (2,-1), recebeu ({v.X},{v.Y})`)
end)

test(":Floor()", function()
	local v = Vector2.new(1.9, -1.1):Floor()
	assert(v.X == 1 and v.Y == -2, `esperava (1,-2), recebeu ({v.X},{v.Y})`)
end)

test(":Sign()", function()
	local v = Vector2.new(-5, 5):Sign()
	assert(v.X == -1 and v.Y == 1, `esperava (-1,1), recebeu ({v.X},{v.Y})`)
	local zeroSign = Vector2.new(0, 0):Sign()
	assert(zeroSign.X == 0 and zeroSign.Y == 0, "Sign de (0,0) deveria ser (0,0)")
end)

test(":Cross() devolve um NUMBER escalar -- DIFERENTE de Vector3:Cross (assimetria 2)", function()
	local x = Vector2.new(1, 0)
	local y = Vector2.new(0, 1)
	local cross = x:Cross(y)
	assert(typeof(cross) == "number", `Cross de Vector2 deveria devolver number, recebeu {typeof(cross)}`)
	assert(cross == 1, `x cross y esperava 1, recebeu {cross}`)
end)

test(":Dot()", function()
	local a = Vector2.new(1, 2)
	local b = Vector2.new(3, 4)
	assert(a:Dot(b) == 11, `esperava 11, recebeu {a:Dot(b)}`)
end)

test(":Angle() sem sinal -- unsigned em [0,pi] (default isSigned=false)", function()
	local x = Vector2.new(1, 0)
	assert(math.abs(x:Angle(x) - 0) < 1e-6, "ângulo entre vetores iguais deveria ser 0")
	local y = Vector2.new(0, 1)
	assert(math.abs(x:Angle(y) - math.pi / 2) < 1e-6, "ângulo entre vetores perpendiculares deveria ser pi/2")
	local negY = Vector2.new(0, -1)
	-- sem sinal, o ângulo com -Y também deveria ser pi/2 (magnitude do cross, não o cross cru)
	assert(math.abs(x:Angle(negY) - math.pi / 2) < 1e-6, "ângulo sem sinal com -Y deveria ser pi/2 (unsigned)")
end)

test(":Angle() com isSigned=true -- sinalizado em [-pi,pi]", function()
	local x = Vector2.new(1, 0)
	local y = Vector2.new(0, 1)
	local negY = Vector2.new(0, -1)
	local positiveAngle = x:Angle(y, true)
	local negativeAngle = x:Angle(negY, true)
	assert(positiveAngle > 0, `esperava ângulo positivo, recebeu {positiveAngle}`)
	assert(negativeAngle < 0, `esperava ângulo negativo, recebeu {negativeAngle}`)
end)

test(":FuzzyEq() usa ABS PURO por componente (SEM escala, diferente do algoritmo de Vector3)", function()
	local a = Vector2.new(1, 1)
	local closeEnough = Vector2.new(1.000001, 1)
	local tooFar = Vector2.new(1.01, 1)
	assert(a:FuzzyEq(closeEnough), "diferença de 1e-6 deveria passar no FuzzyEq default (1e-5)")
	assert(not a:FuzzyEq(tooFar), "diferença de 0.01 não deveria passar no FuzzyEq default (1e-5)")
end)

test(":FuzzyEq() aceita epsilon customizado", function()
	local a = Vector2.new(1, 1)
	local b = Vector2.new(1.05, 1)
	assert(not a:FuzzyEq(b), "diferença de 0.05 não deveria passar no epsilon default")
	assert(a:FuzzyEq(b, 0.1), "diferença de 0.05 deveria passar com epsilon 0.1")
end)

test(":Lerp() -- alpha 0/1/0.5 e NÃO clampado", function()
	local a = Vector2.new(0, 0)
	local b = Vector2.new(10, 20)
	local at0 = a:Lerp(b, 0)
	local at1 = a:Lerp(b, 1)
	local atHalf = a:Lerp(b, 0.5)
	local extrapolated = a:Lerp(b, 2)
	assert(at0.X == 0 and at0.Y == 0, "Lerp(alpha=0) deveria devolver o início")
	assert(at1.X == 10 and at1.Y == 20, "Lerp(alpha=1) deveria devolver o fim")
	assert(atHalf.X == 5 and atHalf.Y == 10, "Lerp(alpha=0.5) deveria devolver o meio")
	assert(extrapolated.X == 20 and extrapolated.Y == 40, "Lerp(alpha=2) deveria extrapolar (não clampado)")
end)

test(":Max()/:Min() aceitam TUPLA VARIÁDICA -- diferente de Vector3 (um único argumento)", function()
	local a = Vector2.new(1, 5)

	-- zero argumentos extras: devolve o próprio self.
	local maxNone = a:Max()
	assert(maxNone.X == 1 and maxNone.Y == 5, "Max() sem argumentos deveria devolver o próprio vetor")

	-- um argumento extra: comportamento normal de dois vetores.
	local b = Vector2.new(4, 3)
	local maxOne = a:Max(b)
	assert(maxOne.X == 4 and maxOne.Y == 5, `Max(b): esperava (4,5), recebeu ({maxOne.X},{maxOne.Y})`)

	-- múltiplos argumentos (2+) -- é isso que a tupla variádica confirmada pela pesquisa permite.
	local c = Vector2.new(-1, 10)
	local maxMany = a:Max(b, c)
	assert(maxMany.X == 4 and maxMany.Y == 10, `Max(b,c): esperava (4,10), recebeu ({maxMany.X},{maxMany.Y})`)

	local minMany = a:Min(b, c)
	assert(minMany.X == -1 and minMany.Y == 3, `Min(b,c): esperava (-1,3), recebeu ({minMany.X},{minMany.Y})`)
end)

-- ================================================================================================
-- Operadores
-- ================================================================================================

test("+ soma componente a componente", function()
	local sum = Vector2.new(1, 2) + Vector2.new(3, 4)
	assert(sum.X == 4 and sum.Y == 6, `esperava (4,6), recebeu ({sum.X},{sum.Y})`)
end)

test("- subtrai componente a componente", function()
	local diff = Vector2.new(5, 7) - Vector2.new(1, 2)
	assert(diff.X == 4 and diff.Y == 5, `esperava (4,5), recebeu ({diff.X},{diff.Y})`)
end)

test("* Vector2*Vector2 é componente a componente", function()
	local product = Vector2.new(2, 3) * Vector2.new(5, 6)
	assert(product.X == 10 and product.Y == 18, `esperava (10,18), recebeu ({product.X},{product.Y})`)
end)

test("* Vector2*number e number*Vector2 (comutativo)", function()
	local a = Vector2.new(1, 2)
	local right = a * 2
	local left = 2 * a
	assert(right.X == 2 and right.Y == 4, "Vector2 * number incorreto")
	assert(left.X == 2 and left.Y == 4, "number * Vector2 incorreto")
end)

test("/ Vector2/Vector2 e Vector2/number (SEM reverso number/Vector2)", function()
	local quotient = Vector2.new(10, 20) / Vector2.new(2, 4)
	assert(quotient.X == 5 and quotient.Y == 5, `esperava (5,5), recebeu ({quotient.X},{quotient.Y})`)
	local scaled = Vector2.new(10, 20) / 2
	assert(scaled.X == 5 and scaled.Y == 10, "Vector2 / number incorreto")
end)

test("Vector2 NÃO tem // (assimetria 1 -- diferente de Vector3, que TEM) -- erro nativo do Luau", function()
	local a = Vector2.new(7, 8)
	local ok, err = pcall(function()
		return op(a) // op(2)
	end)
	assert(not ok, "Vector2 // number deveria errar -- Vector2 não suporta floor division")
	assert(
		string.find(tostring(err), "arithmetic", 1, true) ~= nil,
		`esperava o erro nativo de aritmética, recebeu: {err}`
	)

	local b = Vector2.new(1, 2)
	local okVecVec = pcall(function()
		return op(a) // op(b)
	end)
	assert(not okVecVec, "Vector2 // Vector2 também deveria errar")
end)

test("unário -v nega os 2 componentes (por analogia com Vector3, confiança menor -- ver cabeçalho)", function()
	local negated = -Vector2.new(1, -2)
	assert(negated.X == -1 and negated.Y == 2, "unário - incorreto")
end)

test("== é EXATO componente a componente (P8, aproximação não confirmada)", function()
	local a = Vector2.new(1, 2)
	local b = Vector2.new(1, 2)
	local c = Vector2.new(1, 2.0000005)
	assert(a == b, "dois Vector2 com os mesmos componentes deveriam ser ==")
	assert(not (a == c), "== deveria ser EXATO -- uma diferença mínima já quebra a igualdade")
end)

test("== entre Vector2 e Vector3 -> false SEM erro (tipos diferentes)", function()
	local v2 = Vector2.new(1, 2)
	local v3 = Vector3.new(1, 2, 0)
	local ok, result = pcall(function()
		return op(v2) == op(v3)
	end)
	assert(ok, `comparar Vector2 com Vector3 não deveria errar, erro: {tostring(result)}`)
	assert(result == false, "Vector2 == Vector3 deveria ser false")
end)

test("Vector2 + number erra (o Luau levanta o erro nativo de aritmética sozinho)", function()
	local v = Vector2.new(1, 2)
	local ok, err = pcall(function()
		return op(v) + op(5)
	end)
	assert(not ok, "Vector2 + number deveria errar (só Vector2+Vector2 é suportado)")
	assert(
		string.find(tostring(err), "arithmetic", 1, true) ~= nil,
		`esperava o erro nativo de aritmética, recebeu: {err}`
	)
end)

test("Vector2 * string erra", function()
	local v = Vector2.new(1, 2)
	local ok = pcall(function()
		return op(v) * op("oi")
	end)
	assert(not ok, "Vector2 * string deveria errar")
end)

-- ================================================================================================
-- tostring
-- ================================================================================================

test("tostring: formato \"X, Y\" (vírgula-espaço, sem parênteses)", function()
	assert(tostring(Vector2.zero) == "0, 0", `esperava "0, 0", recebeu "{tostring(Vector2.zero)}"`)
	assert(tostring(Vector2.one) == "1, 1", `esperava "1, 1", recebeu "{tostring(Vector2.one)}"`)
end)

test("tostring: usa Float32.Format (shortest round-trip), não o tostring cru do Luau", function()
	local v = Vector2.new(0.1, 0)
	assert(tostring(v) == "0.1, 0", `esperava "0.1, 0", recebeu "{tostring(v)}"`)
end)

-- ================================================================================================
-- Precisão f32 -- paridade com o `vector` nativo do Luau usado como ORÁCULO (não representação)
-- ================================================================================================

test("componentes batem bit a bit com o oráculo vector.create nativo (float32)", function()
	local values: { number } = { 0.1, -0.7, 1 / 3, 123456.789, 100, 2 ^ 30, 1e20 }
	for _, value in values do
		local ours = Vector2.new(value, 0).X
		local native = (vector.create(value, 0, 0) :: vector).x
		assert(ours == native, `Vector2.new({value},0).X = {ours}, mas vector.create nativo = {native}`)
	end
end)

test("type(Vector2.new()) é \"userdata\" -- Vector2 NÃO foi migrado pro tipo `vector` nativo (só Vector3 foi)", function()
	assert(type(Vector2.new()) == "userdata", `esperava "userdata", recebeu "{type(Vector2.new())}"`)
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
