--!strict

--[[
	Teste da task-valuetypes-004 (types/Vector3.luau). Cobre construtores, constantes,
	propriedades, cada método, cada operador suportado, tostring e precisão f32 (paridade com o
	`vector` nativo do Luau, usado aqui só como ORÁCULO de precisão -- não como representação,
	ver D8 no cabeçalho de Vector3.luau).

	Roda com `lune run src/valuetypes/types/Vector3.spec.luau`.

	SEM `any` em lugar nenhum (regra 01) -- pra exercitar operador em cenários que o Luau real
	também rejeitaria estaticamente (ex.: `Vector3 + number`, que não tem overload declarado no
	tipo opaco exportado), usa o mesmo precedente de `Userdata.spec.luau`: um tipo SINTÉTICO local
	(`AnyOperable`) que só empresta a assinatura de operador necessária pro type-checker, nunca
	muda o valor em runtime.
]]

local process = require("@lune/process")
local Vector3 = require("./Vector3")
local Vector2 = require("./Vector2")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

-- Tipo sintético só pra emprestar assinatura de operador em cenários que o tipo opaco real
-- (Vector3) não declara (porque o Roblox real também não suporta essa combinação) -- mesmo
-- precedente de `asBinaryOperable`/`asUnaryOperable`/`asEq` em Userdata.spec.luau.
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

test("Vector3.new() usa default (0,0,0)", function()
	local v = Vector3.new()
	assert(v.X == 0 and v.Y == 0 and v.Z == 0, `esperava (0,0,0), recebeu ({v.X},{v.Y},{v.Z})`)
end)

test("Vector3.new(x,y,z) constrói com os valores dados", function()
	local v = Vector3.new(1, 2, 3)
	assert(v.X == 1 and v.Y == 2 and v.Z == 3, `esperava (1,2,3), recebeu ({v.X},{v.Y},{v.Z})`)
end)

test("Vector3.new com argumentos parciais usa 0 pros ausentes", function()
	local v = Vector3.new(5)
	assert(v.X == 5 and v.Y == 0 and v.Z == 0, `esperava (5,0,0), recebeu ({v.X},{v.Y},{v.Z})`)
end)

test("Vector3.FromNormalId mapeia os 6 valores de Enum.NormalId", function()
	local top = Vector3.FromNormalId({ Name = "Top" })
	assert(top.X == 0 and top.Y == 1 and top.Z == 0, `Top: esperava (0,1,0), recebeu ({top.X},{top.Y},{top.Z})`)
	local bottom = Vector3.FromNormalId({ Name = "Bottom" })
	assert(
		bottom.X == 0 and bottom.Y == -1 and bottom.Z == 0,
		`Bottom: esperava (0,-1,0), recebeu ({bottom.X},{bottom.Y},{bottom.Z})`
	)
	local front = Vector3.FromNormalId({ Name = "Front" })
	assert(
		front.X == 0 and front.Y == 0 and front.Z == -1,
		`Front: esperava (0,0,-1), recebeu ({front.X},{front.Y},{front.Z})`
	)
	local back = Vector3.FromNormalId({ Name = "Back" })
	assert(back.X == 0 and back.Y == 0 and back.Z == 1, `Back: esperava (0,0,1), recebeu ({back.X},{back.Y},{back.Z})`)
	local right = Vector3.FromNormalId({ Name = "Right" })
	assert(
		right.X == 1 and right.Y == 0 and right.Z == 0,
		`Right: esperava (1,0,0), recebeu ({right.X},{right.Y},{right.Z})`
	)
	local left = Vector3.FromNormalId({ Name = "Left" })
	assert(left.X == -1 and left.Y == 0 and left.Z == 0, `Left: esperava (-1,0,0), recebeu ({left.X},{left.Y},{left.Z})`)
end)

test("Vector3.FromNormalId erra pra um nome desconhecido", function()
	local ok = pcall(function()
		return Vector3.FromNormalId({ Name = "Diagonal" })
	end)
	assert(not ok, "FromNormalId com nome inválido deveria errar")
end)

test("Vector3.FromAxis mapeia X/Y/Z", function()
	local x = Vector3.FromAxis({ Name = "X" })
	assert(x.X == 1 and x.Y == 0 and x.Z == 0, `X: esperava (1,0,0), recebeu ({x.X},{x.Y},{x.Z})`)
	local y = Vector3.FromAxis({ Name = "Y" })
	assert(y.X == 0 and y.Y == 1 and y.Z == 0, `Y: esperava (0,1,0), recebeu ({y.X},{y.Y},{y.Z})`)
	local z = Vector3.FromAxis({ Name = "Z" })
	assert(z.X == 0 and z.Y == 0 and z.Z == 1, `Z: esperava (0,0,1), recebeu ({z.X},{z.Y},{z.Z})`)
end)

test("Vector3.FromAxis erra pra um nome desconhecido", function()
	local ok = pcall(function()
		return Vector3.FromAxis({ Name = "W" })
	end)
	assert(not ok, "FromAxis com nome inválido deveria errar")
end)

-- ================================================================================================
-- Constantes
-- ================================================================================================

test("constantes estáticas têm os valores certos (case-sensitive, ver pesquisa §2)", function()
	local zero, one = Vector3.zero, Vector3.one
	assert(zero.X == 0 and zero.Y == 0 and zero.Z == 0, "Vector3.zero deveria ser (0,0,0)")
	assert(one.X == 1 and one.Y == 1 and one.Z == 1, "Vector3.one deveria ser (1,1,1)")
	local xAxis, yAxis, zAxis = Vector3.xAxis, Vector3.yAxis, Vector3.zAxis
	assert(xAxis.X == 1 and xAxis.Y == 0 and xAxis.Z == 0, "Vector3.xAxis deveria ser (1,0,0)")
	assert(yAxis.X == 0 and yAxis.Y == 1 and yAxis.Z == 0, "Vector3.yAxis deveria ser (0,1,0)")
	assert(zAxis.X == 0 and zAxis.Y == 0 and zAxis.Z == 1, "Vector3.zAxis deveria ser (0,0,1)")
end)

-- ================================================================================================
-- Propriedades
-- ================================================================================================

test("X/Y/Z lidos corretamente", function()
	local v = Vector3.new(7, 8, 9)
	assert(v.X == 7 and v.Y == 8 and v.Z == 9, "leitura de X/Y/Z incorreta")
end)

test("Magnitude == sqrt(X^2+Y^2+Z^2)", function()
	local v = Vector3.new(3, 4, 0)
	assert(v.Magnitude == 5, `esperava Magnitude 5, recebeu {v.Magnitude}`)
	local w = Vector3.new(1, 2, 2)
	assert(w.Magnitude == 3, `esperava Magnitude 3, recebeu {w.Magnitude}`)
end)

test("Unit normaliza corretamente", function()
	local v = Vector3.new(3, 4, 0)
	local unit = v.Unit
	assert(math.abs(unit.X - 0.6) < 1e-6, `esperava Unit.X ~= 0.6, recebeu {unit.X}`)
	assert(math.abs(unit.Y - 0.8) < 1e-6, `esperava Unit.Y ~= 0.8, recebeu {unit.Y}`)
	assert(unit.Z == 0, `esperava Unit.Z == 0, recebeu {unit.Z}`)
end)

test("Unit de Vector3.zero produz NaN nos 3 componentes (não (0,0,0)) -- confirmado pela pesquisa §3", function()
	local unit = Vector3.zero.Unit
	assert(unit.X ~= unit.X, "Unit.X de zero deveria ser NaN")
	assert(unit.Y ~= unit.Y, "Unit.Y de zero deveria ser NaN")
	assert(unit.Z ~= unit.Z, "Unit.Z de zero deveria ser NaN")
end)

test("ler uma propriedade inválida erra citando a chave e o TypeName", function()
	local v = Vector3.new(1, 2, 3)
	local ok, err = pcall(function()
		return asStringIndexable(v).NaoExiste
	end)
	assert(not ok, "ler uma propriedade inválida deveria errar")
	local message = tostring(err)
	assert(string.find(message, "NaoExiste", 1, true) ~= nil, `mensagem deveria citar a chave, recebeu: {message}`)
	assert(string.find(message, "Vector3", 1, true) ~= nil, `mensagem deveria citar o TypeName, recebeu: {message}`)
end)

test("escrever numa propriedade erra -- Vector3 é imutável", function()
	local v = Vector3.new(1, 2, 3)
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
	local v = Vector3.new(-1, 2, -3):Abs()
	assert(v.X == 1 and v.Y == 2 and v.Z == 3, `esperava (1,2,3), recebeu ({v.X},{v.Y},{v.Z})`)
end)

test(":Ceil()", function()
	local v = Vector3.new(1.1, -1.1, 2.9):Ceil()
	assert(v.X == 2 and v.Y == -1 and v.Z == 3, `esperava (2,-1,3), recebeu ({v.X},{v.Y},{v.Z})`)
end)

test(":Floor()", function()
	local v = Vector3.new(1.9, -1.1, 2.1):Floor()
	assert(v.X == 1 and v.Y == -2 and v.Z == 2, `esperava (1,-2,2), recebeu ({v.X},{v.Y},{v.Z})`)
end)

test(":Sign()", function()
	local v = Vector3.new(-5, 0, 5):Sign()
	assert(v.X == -1 and v.Y == 0 and v.Z == 1, `esperava (-1,0,1), recebeu ({v.X},{v.Y},{v.Z})`)
end)

test(":Cross() devolve um Vector3 (regra da mão direita) -- DIFERENTE de Vector2:Cross", function()
	local x = Vector3.new(1, 0, 0)
	local y = Vector3.new(0, 1, 0)
	local cross = x:Cross(y)
	-- checagem de type() (não typeof()) de propósito: comparar `typeof(cross) == "Vector3"`
	-- literal aciona o refinamento de tipo do PRÓPRIO Luau (mesmo mecanismo de
	-- `type(x) == "number"`), e "Vector3" não existe como tipo GLOBAL neste arquivo (só como
	-- valor importado) -- luau-lsp acusa "Unknown type 'Vector3'" nesse padrão específico.
	assert(type(cross) == "userdata", "Cross deveria devolver um Vector3 (userdata)")
	assert(cross.X == 0 and cross.Y == 0 and cross.Z == 1, `x cross y esperava (0,0,1), recebeu ({cross.X},{cross.Y},{cross.Z})`)
end)

test(":Dot()", function()
	local a = Vector3.new(1, 2, 3)
	local b = Vector3.new(4, 5, 6)
	assert(a:Dot(b) == 32, `esperava 32, recebeu {a:Dot(b)}`)
end)

test(":Angle() sem eixo -- unsigned em [0,pi]", function()
	local x = Vector3.new(1, 0, 0)
	assert(math.abs(x:Angle(x) - 0) < 1e-6, "ângulo entre vetores iguais deveria ser 0")
	local y = Vector3.new(0, 1, 0)
	assert(math.abs(x:Angle(y) - math.pi / 2) < 1e-6, "ângulo entre vetores perpendiculares deveria ser pi/2")
	local negX = Vector3.new(-1, 0, 0)
	assert(math.abs(x:Angle(negX) - math.pi) < 1e-6, "ângulo entre vetores opostos deveria ser pi")
end)

test(":Angle() com eixo -- sinalizado em [-pi,pi]", function()
	local x = Vector3.new(1, 0, 0)
	local y = Vector3.new(0, 1, 0)
	local negY = Vector3.new(0, -1, 0)
	local zAxis = Vector3.new(0, 0, 1)
	local positiveAngle = x:Angle(y, zAxis)
	local negativeAngle = x:Angle(negY, zAxis)
	assert(positiveAngle > 0, `esperava ângulo positivo, recebeu {positiveAngle}`)
	assert(negativeAngle < 0, `esperava ângulo negativo, recebeu {negativeAngle}`)
end)

test(":FuzzyEq() -- dentro do epsilon default é true, fora é false", function()
	local a = Vector3.new(1, 1, 1)
	local closeEnough = Vector3.new(1.0000001, 1, 1)
	local tooFar = Vector3.new(1.01, 1, 1)
	assert(a:FuzzyEq(closeEnough), "diferença de 1e-7 deveria passar no FuzzyEq default (1e-5)")
	assert(not a:FuzzyEq(tooFar), "diferença de 0.01 não deveria passar no FuzzyEq default (1e-5)")
end)

test(":FuzzyEq() aceita epsilon customizado", function()
	local a = Vector3.new(1, 1, 1)
	local b = Vector3.new(1.05, 1, 1)
	assert(not a:FuzzyEq(b), "diferença de 0.05 não deveria passar no epsilon default")
	assert(a:FuzzyEq(b, 0.1), "diferença de 0.05 deveria passar com epsilon 0.1")
end)

test(":Lerp() -- alpha 0/1/0.5 e NÃO clampado (extrapola fora de [0,1])", function()
	local a = Vector3.new(0, 0, 0)
	local b = Vector3.new(10, 20, 30)
	local at0 = a:Lerp(b, 0)
	local at1 = a:Lerp(b, 1)
	local atHalf = a:Lerp(b, 0.5)
	local extrapolated = a:Lerp(b, 2)
	assert(at0.X == 0 and at0.Y == 0 and at0.Z == 0, "Lerp(alpha=0) deveria devolver o início")
	assert(at1.X == 10 and at1.Y == 20 and at1.Z == 30, "Lerp(alpha=1) deveria devolver o fim")
	assert(atHalf.X == 5 and atHalf.Y == 10 and atHalf.Z == 15, "Lerp(alpha=0.5) deveria devolver o meio")
	assert(extrapolated.X == 20 and extrapolated.Y == 40 and extrapolated.Z == 60, "Lerp(alpha=2) deveria extrapolar (não clampado)")
end)

test(":Max()/:Min() aceitam UM ÚNICO argumento -- diferente de Vector2 (tupla variádica)", function()
	local a = Vector3.new(1, 5, 2)
	local b = Vector3.new(4, 3, 6)
	local maxV = a:Max(b)
	local minV = a:Min(b)
	assert(maxV.X == 4 and maxV.Y == 5 and maxV.Z == 6, `Max: esperava (4,5,6), recebeu ({maxV.X},{maxV.Y},{maxV.Z})`)
	assert(minV.X == 1 and minV.Y == 3 and minV.Z == 2, `Min: esperava (1,3,2), recebeu ({minV.X},{minV.Y},{minV.Z})`)
end)

-- ================================================================================================
-- Operadores
-- ================================================================================================

test("+ soma componente a componente", function()
	local sum = Vector3.new(1, 2, 3) + Vector3.new(4, 5, 6)
	assert(sum.X == 5 and sum.Y == 7 and sum.Z == 9, `esperava (5,7,9), recebeu ({sum.X},{sum.Y},{sum.Z})`)
end)

test("- subtrai componente a componente", function()
	local diff = Vector3.new(5, 7, 9) - Vector3.new(1, 2, 3)
	assert(diff.X == 4 and diff.Y == 5 and diff.Z == 6, `esperava (4,5,6), recebeu ({diff.X},{diff.Y},{diff.Z})`)
end)

test("* Vector3*Vector3 é componente a componente (NÃO é dot nem cross)", function()
	local product = Vector3.new(2, 3, 4) * Vector3.new(5, 6, 7)
	assert(
		product.X == 10 and product.Y == 18 and product.Z == 28,
		`esperava (10,18,28), recebeu ({product.X},{product.Y},{product.Z})`
	)
end)

test("* Vector3*number e number*Vector3 (comutativo)", function()
	local a = Vector3.new(1, 2, 3)
	local right = a * 2
	local left = 2 * a
	assert(right.X == 2 and right.Y == 4 and right.Z == 6, "Vector3 * number incorreto")
	assert(left.X == 2 and left.Y == 4 and left.Z == 6, "number * Vector3 incorreto")
end)

test("/ Vector3/Vector3 e Vector3/number (SEM reverso number/Vector3)", function()
	local quotient = Vector3.new(10, 20, 30) / Vector3.new(2, 4, 5)
	assert(
		quotient.X == 5 and quotient.Y == 5 and quotient.Z == 6,
		`esperava (5,5,6), recebeu ({quotient.X},{quotient.Y},{quotient.Z})`
	)
	local scaled = Vector3.new(10, 20, 30) / 2
	assert(scaled.X == 5 and scaled.Y == 10 and scaled.Z == 15, "Vector3 / number incorreto")
end)

test("// Vector3//Vector3 e Vector3//number (Vector3 TEM // -- diferente de Vector2)", function()
	local floorQuotient = Vector3.new(7, 8, 9) // Vector3.new(2, 3, 4)
	assert(
		floorQuotient.X == 3 and floorQuotient.Y == 2 and floorQuotient.Z == 2,
		`esperava (3,2,2), recebeu ({floorQuotient.X},{floorQuotient.Y},{floorQuotient.Z})`
	)
	local floorScaled = Vector3.new(7, 8, 9) // 2
	assert(floorScaled.X == 3 and floorScaled.Y == 4 and floorScaled.Z == 4, "Vector3 // number incorreto")
end)

test("unário -v nega os 3 componentes (evidência indireta, ver cabeçalho)", function()
	local negated = -Vector3.new(1, -2, 3)
	assert(negated.X == -1 and negated.Y == 2 and negated.Z == -3, "unário - incorreto")
end)

test("== é EXATO componente a componente (P8, aproximação não confirmada)", function()
	local a = Vector3.new(1, 2, 3)
	local b = Vector3.new(1, 2, 3)
	local c = Vector3.new(1, 2, 3.0000005)
	assert(a == b, "dois Vector3 com os mesmos componentes deveriam ser ==")
	assert(not (a == c), "== deveria ser EXATO -- uma diferença mínima já quebra a igualdade")
end)

test("== entre Vector3 e Vector2 -> false SEM erro (tipos diferentes, mesma invariante 4 de Userdata.luau)", function()
	local v3 = Vector3.new(1, 2, 3)
	local v2 = Vector2.new(1, 2)
	local ok, result = pcall(function()
		return op(v3) == op(v2)
	end)
	assert(ok, `comparar Vector3 com Vector2 não deveria errar, erro: {tostring(result)}`)
	assert(result == false, "Vector3 == Vector2 deveria ser false")
end)

test("Vector3 + number erra (o Luau levanta o erro nativo de aritmética sozinho)", function()
	local v = Vector3.new(1, 2, 3)
	local ok, err = pcall(function()
		return op(v) + op(5)
	end)
	assert(not ok, "Vector3 + number deveria errar (só Vector3+Vector3 é suportado)")
	assert(
		string.find(tostring(err), "arithmetic", 1, true) ~= nil,
		`esperava o erro nativo de aritmética, recebeu: {err}`
	)
end)

test("Vector3 + Vector2 erra coerentemente (tipos DataType diferentes)", function()
	local v3 = Vector3.new(1, 2, 3)
	local v2 = Vector2.new(1, 2)
	local ok = pcall(function()
		return op(v3) + op(v2)
	end)
	assert(not ok, "Vector3 + Vector2 deveria errar")
end)

test("Vector3 * string erra", function()
	local v = Vector3.new(1, 2, 3)
	local ok = pcall(function()
		return op(v) * op("oi")
	end)
	assert(not ok, "Vector3 * string deveria errar")
end)

-- ================================================================================================
-- tostring
-- ================================================================================================

test("tostring: formato \"X, Y, Z\" (vírgula-espaço, sem parênteses)", function()
	assert(tostring(Vector3.zero) == "0, 0, 0", `esperava "0, 0, 0", recebeu "{tostring(Vector3.zero)}"`)
	assert(tostring(Vector3.one) == "1, 1, 1", `esperava "1, 1, 1", recebeu "{tostring(Vector3.one)}"`)
end)

test("tostring: usa Float32.Format (shortest round-trip), não o tostring cru do Luau", function()
	local v = Vector3.new(0.1, 0, 0)
	assert(tostring(v) == "0.1, 0, 0", `esperava "0.1, 0, 0", recebeu "{tostring(v)}"`)
end)

-- ================================================================================================
-- Precisão f32 -- paridade com o `vector` nativo do Luau usado como ORÁCULO (não representação)
-- ================================================================================================

test("componentes batem bit a bit com o oráculo vector.create nativo (float32)", function()
	local values: { number } = { 0.1, -0.7, 1 / 3, 123456.789, 100, 2 ^ 30, 1e20 }
	for _, value in values do
		local ours = Vector3.new(value, 0, 0).X
		local native = (vector.create(value, 0, 0) :: vector).x
		assert(ours == native, `Vector3.new({value},0,0).X = {ours}, mas vector.create nativo = {native}`)
	end
end)

test("type(Vector3.new()) é \"userdata\" (D8: diferente do Roblox moderno, que usa \"vector\" nativo)", function()
	assert(type(Vector3.new()) == "userdata", `esperava "userdata" (D8), recebeu "{type(Vector3.new())}"`)
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
