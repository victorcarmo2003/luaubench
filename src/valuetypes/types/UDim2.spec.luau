--!strict

--[[
	Teste da task-valuetypes-005 (types/UDim2.luau). Fonte de toda assinatura testada:
	`.claude/agents-memory/pesquisa-datatypes-color-udim-enum-2026-09-05.md`, seção B) UDim e
	UDim2.

	Cobre (acceptance da task + regra 06):
	1. Construtores: `new()` (zero), `new(4 números)`, o overload REAL `new(x: UDim, y: UDim)`
	   (citação literal do YAML: equivalente a `UDim2.new(0.5, 10, 1, 0)` quando `x =
	   UDim.new(0.5,10)`, `y = UDim.new(1,0)`), `fromScale`, `fromOffset`.
	2. Validação de forma inválida do overload (UDim + não-UDim, contagem errada de args).
	3. Propriedades X/Y e os sinônimos EXATOS Width==X/Height==Y (confirmado pela pesquisa).
	4. Método `Lerp`.
	5. Operadores CONFIRMADOS `+`/`-`.
	6. P9 (não confirmado, mesma pendência de UDim): unário `-` e `==`.
	7. `tostring` no formato CONFIRMADO "{xScale, xOffset}, {yScale, yOffset}" (citação literal:
	   `print(guiObject.Size) --> {0, 300}, {1, 0}`, reproduzido byte a byte).
	8. Tentativa de mutação erra; `setmetatable`/`pairs` erram nativamente.

	Roda com `lune run src/valuetypes/types/UDim2.spec.luau`.
]]

local process = require("@lune/process")
local Float32 = require("../Float32")
local UDim = require("./UDim")
local UDim2 = require("./UDim2")
local Color3 = require("./Color3")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

type EqProbe = typeof(setmetatable({} :: {}, {} :: { __eq: (EqProbe, EqProbe) -> boolean }))
local function asEq(value: unknown): EqProbe
	return value :: EqProbe
end

type StringIndexableProbe = typeof(setmetatable({} :: { [string]: unknown }, {}))
local function asStringIndexable(value: unknown): StringIndexableProbe
	return value :: StringIndexableProbe
end

type BinaryOperableProbe = typeof(setmetatable(
	{} :: {},
	{} :: { __add: (BinaryOperableProbe, BinaryOperableProbe) -> BinaryOperableProbe }
))
local function asBinaryOperable(value: unknown): BinaryOperableProbe
	return value :: BinaryOperableProbe
end

type BinaryRawFn = (unknown, unknown) -> unknown
local setmetatableUnknown: BinaryRawFn = (setmetatable :: unknown) :: BinaryRawFn

-- ================================================================================================
-- Construtores
-- ================================================================================================

test("UDim2.new(): sem argumentos == UDim2.new(0,0,0,0)", function()
	local u = UDim2.new()
	assert(u.X.Scale == 0 and u.X.Offset == 0, "X deveria ser {0,0}")
	assert(u.Y.Scale == 0 and u.Y.Offset == 0, "Y deveria ser {0,0}")
end)

test("UDim2.new(xScale, xOffset, yScale, yOffset): forma de 4 números, defaults 0", function()
	local u = UDim2.new(0, 300, 1, 0)
	assert(u.X.Scale == 0 and u.X.Offset == 300, `X incorreto: {u.X.Scale},{u.X.Offset}`)
	assert(u.Y.Scale == 1 and u.Y.Offset == 0, `Y incorreto: {u.Y.Scale},{u.Y.Offset}`)

	local partial = UDim2.new(0.5)
	assert(partial.X.Scale == 0.5 and partial.X.Offset == 0, "xOffset/yScale/yOffset deveriam defaultar pra 0")
	assert(partial.Y.Scale == 0 and partial.Y.Offset == 0, "Y deveria ser {0,0} quando omitido")
end)

test("UDim2.new(x: UDim, y: UDim): overload REAL confirmado -- reproduz o exemplo literal do YAML", function()
	local x = UDim.new(0.5, 10)
	local y = UDim.new(1, 0)
	local u = UDim2.new(x, y)

	local expected = UDim2.new(0.5, 10, 1, 0)
	assert(u.X.Scale == expected.X.Scale and u.X.Offset == expected.X.Offset, "X deveria bater com a forma de 4 números")
	assert(u.Y.Scale == expected.Y.Scale and u.Y.Offset == expected.Y.Offset, "Y deveria bater com a forma de 4 números")
end)

test("UDim2.new(UDim, <não-UDim>) erra citando o argumento", function()
	local x = UDim.new(0.5, 10)
	local ok, err = pcall(function()
		-- `Userdata.Fields`/tipagem interna trata isso como "número no lugar de UDim" --
		-- despachado pelo caminho da forma numérica (2 args: x não é UDim... mas aqui x É UDim,
		-- então cai no ramo do overload de dois UDim, e o segundo argumento não bate).
		return ((UDim2.new :: unknown) :: (UDim.UDim, unknown) -> unknown)(x, 5)
	end)
	assert(not ok, "UDim2.new(UDim, número) deveria errar -- o overload de 2 args com UDim exige os DOIS UDim")
	assert(string.find(tostring(err), "UDim", 1, true) ~= nil, `mensagem deveria mencionar UDim, recebeu: {err}`)
end)

test("UDim2.new(UDim) sozinho (1 argumento) erra -- overload de UDim exige exatamente 2", function()
	local x = UDim.new(0.5, 10)
	local ok = pcall(function()
		return ((UDim2.new :: unknown) :: (UDim.UDim) -> unknown)(x)
	end)
	assert(not ok, "UDim2.new(UDim) com um único argumento deveria errar")
end)

test("UDim2.fromScale(xScale?, yScale?): offsets ficam 0", function()
	local u = UDim2.fromScale(0.5, 0.25)
	assert(u.X.Scale == 0.5 and u.X.Offset == 0, "X incorreto")
	assert(u.Y.Scale == 0.25 and u.Y.Offset == 0, "Y incorreto")

	local defaults = UDim2.fromScale()
	assert(defaults.X.Scale == 0 and defaults.Y.Scale == 0, "fromScale() sem args deveria ser 0,0")
end)

test("UDim2.fromOffset(xOffset?, yOffset?): scales ficam 0", function()
	local u = UDim2.fromOffset(100, 50)
	assert(u.X.Scale == 0 and u.X.Offset == 100, "X incorreto")
	assert(u.Y.Scale == 0 and u.Y.Offset == 50, "Y incorreto")
end)

test("UDim2.new: componentes quantizados corretamente (Scale float32, Offset int32 arredondado)", function()
	local u = UDim2.new(0.1, 5.6, 0.2, -5.6)
	assert(u.X.Scale == Float32.Quantize(0.1), "xScale deveria estar quantizado pra float32")
	assert(u.X.Offset == 6, `xOffset deveria arredondar pra 6, recebeu {u.X.Offset}`)
	assert(u.Y.Offset == -6, `yOffset deveria arredondar pra -6, recebeu {u.Y.Offset}`)
end)

-- ================================================================================================
-- Propriedades: X/Y e os sinônimos EXATOS Width/Height
-- ================================================================================================

test("Width é sinônimo EXATO de X, Height é sinônimo EXATO de Y (confirmado pela pesquisa)", function()
	local u = UDim2.new(0.5, 10, 1, 20)
	assert(u.Width.Scale == u.X.Scale and u.Width.Offset == u.X.Offset, "Width deveria ser igual a X")
	assert(u.Height.Scale == u.Y.Scale and u.Height.Offset == u.Y.Offset, "Height deveria ser igual a Y")
	assert(asEq(u.Width) == asEq(u.X), "Width == X deveria ser true (mesmo valor)")
	assert(asEq(u.Height) == asEq(u.Y), "Height == Y deveria ser true (mesmo valor)")
end)

test("acessar um membro inválido erra citando a chave e 'UDim2'", function()
	local u = UDim2.new()
	local ok, err = pcall(function()
		return asStringIndexable(u).NaoExiste
	end)
	assert(not ok, "ler um membro inválido deveria errar")
	local message = tostring(err)
	assert(string.find(message, "NaoExiste", 1, true) ~= nil, `mensagem deveria citar a chave, recebeu: {message}`)
	assert(string.find(message, "UDim2", 1, true) ~= nil, `mensagem deveria citar UDim2, recebeu: {message}`)
end)

-- ================================================================================================
-- Lerp
-- ================================================================================================

test("Lerp: interpola X e Y (Scale e Offset) linearmente", function()
	local a = UDim2.new(0, 0, 0, 0)
	local b = UDim2.new(1, 100, 1, 100)
	local mid = a:Lerp(b, 0.5)
	assert(mid.X.Scale == 0.5 and mid.X.Offset == 50, `X incorreto: {mid.X.Scale},{mid.X.Offset}`)
	assert(mid.Y.Scale == 0.5 and mid.Y.Offset == 50, `Y incorreto: {mid.Y.Scale},{mid.Y.Offset}`)
end)

-- ================================================================================================
-- Operadores CONFIRMADOS: + e -
-- ================================================================================================

test("UDim2 + UDim2: soma X e Y componente a componente", function()
	local a = UDim2.new(0, 10, 0, 10)
	local b = UDim2.new(0, 5, 0, 5)
	local sum = a + b
	assert(sum.X.Offset == 15 and sum.Y.Offset == 15, `esperava Offset 15/15, recebeu {sum.X.Offset}/{sum.Y.Offset}`)
end)

test("UDim2 - UDim2: subtrai componente a componente", function()
	local a = UDim2.new(0.5, 10, 0.5, 10)
	local b = UDim2.new(0.1, 4, 0.1, 4)
	local diff = a - b
	assert(math.abs(diff.X.Scale - 0.4) < 1e-6, `X.Scale incorreto: {diff.X.Scale}`)
	assert(diff.X.Offset == 6, `X.Offset incorreto: {diff.X.Offset}`)
end)

test("UDim2 + tipo diferente (Color3) erra coerentemente", function()
	local a = UDim2.new(0, 10, 0, 10)
	local color = Color3.new(1, 0, 0)
	local ok = pcall(function()
		return asBinaryOperable(a) + asBinaryOperable(color)
	end)
	assert(not ok, "UDim2 + Color3 deveria errar")
end)

-- ================================================================================================
-- P9 -- Unário `-` e `==`: NÃO confirmados (mesma pendência de UDim, ver cabeçalho de UDim2.luau)
-- ================================================================================================

test("[P9, NÃO CONFIRMADO] unário -UDim2 nega os 4 componentes", function()
	local u = UDim2.new(0.5, 10, 0.25, 5)
	local negated = -u
	assert(negated.X.Scale == -0.5 and negated.X.Offset == -10, "X negado incorretamente")
	assert(negated.Y.Scale == -0.25 and negated.Y.Offset == -5, "Y negado incorretamente")
end)

test("[P9, NÃO CONFIRMADO] == compara por valor, componente a componente", function()
	local a = UDim2.new(0.5, 10, 0.25, 5)
	local b = UDim2.new(0.5, 10, 0.25, 5)
	local c = UDim2.new(0.5, 10, 0.25, 6)
	assert(asEq(a) == asEq(b), "dois UDim2 com o mesmo valor deveriam ser ==")
	assert(not (asEq(a) == asEq(c)), "dois UDim2 com Y.Offset diferente não deveriam ser ==")
end)

test("__eq: tipo NOSSO diferente (UDim) -> false SEM erro (invariante 4 da fábrica)", function()
	local u2 = UDim2.new(0.5, 10, 0.25, 5)
	local u1 = UDim.new(0.5, 10)
	local ok, result = pcall(function()
		return asEq(u2) == asEq(u1)
	end)
	assert(ok, `comparar UDim2 com UDim não deveria errar, erro: {tostring(result)}`)
	assert(result == false, "UDim2 == UDim deveria ser false")
end)

test("__eq: comparação com valor solto (number/string/nil) -> false, sem erro", function()
	local u2 = UDim2.new()
	assert(not (asEq(u2) == asEq(5)), "UDim2 == 5 deveria ser false")
	assert(not (asEq(u2) == asEq("5")), "UDim2 == \"5\" deveria ser false")
	assert(not (asEq(u2) == asEq(nil)), "UDim2 == nil deveria ser false")
end)

-- ================================================================================================
-- tostring -- CONFIRMADO por citação literal: "{xScale, xOffset}, {yScale, yOffset}"
-- ================================================================================================

test("tostring: reproduz o exemplo literal do YAML byte a byte", function()
	local s = tostring(UDim2.new(0, 300, 1, 0))
	assert(s == "{0, 300}, {1, 0}", `esperava "\{0, 300\}, \{1, 0\}", recebeu "{s}"`)
end)

test("tostring: UDim2.new() formata '{0, 0}, {0, 0}'", function()
	local s = tostring(UDim2.new())
	assert(s == "{0, 0}, {0, 0}", `esperava "\{0, 0\}, \{0, 0\}", recebeu "{s}"`)
end)

-- ================================================================================================
-- Imutabilidade / userdata nativo
-- ================================================================================================

test("mutação erra: escrever em X/Y não é permitido (UDim2 é imutável)", function()
	local u = UDim2.new(0, 10, 0, 10)
	local ok, err = pcall(function()
		asStringIndexable(u).X = UDim.new(1, 1)
	end)
	assert(not ok, "escrever em X deveria errar")
	assert(string.find(tostring(err), "UDim2", 1, true) ~= nil, `mensagem deveria citar UDim2, recebeu: {err}`)
end)

test("type(UDim2.new()) == 'userdata'", function()
	assert(type(UDim2.new()) == "userdata", `esperava userdata, recebeu {type(UDim2.new())}`)
end)

test("setmetatable sobre um UDim2 erra nativamente (não é código nosso)", function()
	local u = UDim2.new()
	local ok, err = pcall(function()
		setmetatableUnknown(u, {})
	end)
	assert(not ok, "setmetatable sobre um UDim2 deveria errar")
	assert(
		string.find(tostring(err), "table expected", 1, true) ~= nil,
		`mensagem deveria indicar que UDim2 não é uma tabela (userdata), recebeu: {err}`
	)
end)

test("pairs sobre um UDim2 erra nativamente (userdata não é iterável)", function()
	local u = UDim2.new()
	local ok = pcall(function()
		pairs(u)
	end)
	assert(not ok, "pairs sobre um UDim2 deveria errar")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
