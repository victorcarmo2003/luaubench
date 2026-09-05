--!strict

--[[
	Teste da task-valuetypes-005 (types/UDim.luau). Fonte de toda assinatura testada:
	`.claude/agents-memory/pesquisa-datatypes-color-udim-enum-2026-09-05.md`, seção B) UDim e
	UDim2.

	Cobre (acceptance da task + regra 06):
	1. Construtor: defaults (`UDim.new() == UDim.new(0,0)`, citação literal da doc), quantização
	   float32 pra Scale e int32 (arredondado) pra Offset.
	2. Propriedades Scale/Offset.
	3. Operadores CONFIRMADOS: `+`/`-` (binários).
	4. Operadores NÃO CONFIRMADOS (P9, documentada explicitamente aqui e no cabeçalho de
	   UDim.luau): unário `-` e `==`. Testados como hipótese conservadora, nunca apresentados
	   como fato confirmado.
	5. `tostring` -- formato inferido "{Scale, Offset}" (P2, sem exemplo isolado no YAML).
	6. Tentativa de mutação erra.
	7. `setmetatable`/`pairs` erram nativamente.

	Roda com `lune run src/valuetypes/types/UDim.spec.luau`.
]]

local process = require("@lune/process")
local Float32 = require("../Float32")
local UDim = require("./UDim")
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

-- Mesmo idioma de `asBinaryOperable` em Userdata.spec.luau -- SEM `any` (regra 01): empresta a
-- assinatura de `__add` pro checker aceitar somar dois value types NOSSOS de tipos DIFERENTES,
-- cenário que o Luau real também rejeitaria estaticamente sem essa "lente" sintética. O
-- comportamento exercitado é 100% do despacho real instalado por Userdata.Define.
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
-- Construtor
-- ================================================================================================

test("UDim.new(): sem argumentos == UDim.new(0, 0) (citação literal da doc oficial)", function()
	local a = UDim.new()
	local b = UDim.new(0, 0)
	assert(a.Scale == 0 and a.Offset == 0, `esperava Scale=0, Offset=0, recebeu {a.Scale},{a.Offset}`)
	assert(a.Scale == b.Scale and a.Offset == b.Offset, "UDim.new() deveria ser equivalente a UDim.new(0,0)")
end)

test("UDim.new(scale, offset): Scale quantizado pra float32 (oráculo Float32.Quantize)", function()
	local u = UDim.new(0.1, 10)
	assert(u.Scale == Float32.Quantize(0.1), `Scale deveria estar quantizado pra float32, recebeu {u.Scale}`)
end)

test("UDim.new(scale, offset): Offset é armazenado como INTEIRO (arredondado, half-away-from-zero)", function()
	local u = UDim.new(0, 10.6)
	assert(u.Offset == 11, `esperava Offset arredondado pra 11, recebeu {u.Offset}`)

	local uNeg = UDim.new(0, -10.6)
	assert(uNeg.Offset == -11, `esperava Offset arredondado pra -11, recebeu {uNeg.Offset}`)
end)

-- ================================================================================================
-- Propriedades
-- ================================================================================================

test("Scale/Offset: leitura de propriedade", function()
	local u = UDim.new(0.5, 20)
	assert(u.Scale == 0.5 and u.Offset == 20, `esperava 0.5/20, recebeu {u.Scale}/{u.Offset}`)
end)

test("acessar um membro inválido erra citando a chave e 'UDim'", function()
	local u = UDim.new()
	local ok, err = pcall(function()
		return asStringIndexable(u).NaoExiste
	end)
	assert(not ok, "ler um membro inválido deveria errar")
	local message = tostring(err)
	assert(string.find(message, "NaoExiste", 1, true) ~= nil, `mensagem deveria citar a chave, recebeu: {message}`)
	assert(string.find(message, "UDim", 1, true) ~= nil, `mensagem deveria citar UDim, recebeu: {message}`)
end)

-- ================================================================================================
-- Operadores CONFIRMADOS: + e - (binários)
-- ================================================================================================

test("UDim + UDim: soma Scale com Scale e Offset com Offset independentemente", function()
	local a = UDim.new(0.1, 5)
	local b = UDim.new(0.2, 10)
	local sum = a + b
	assert(sum.Scale == Float32.Quantize(0.1 + 0.2), `Scale incorreto, recebeu {sum.Scale}`)
	assert(sum.Offset == 15, `Offset incorreto, recebeu {sum.Offset}`)
end)

test("UDim - UDim: subtrai componente a componente", function()
	local a = UDim.new(0.5, 10)
	local b = UDim.new(0.1, 4)
	local diff = a - b
	assert(math.abs(diff.Scale - 0.4) < 1e-6, `Scale incorreto, recebeu {diff.Scale}`)
	assert(diff.Offset == 6, `Offset incorreto, recebeu {diff.Offset}`)
end)

test("UDim + UDim com tipo diferente (Color3) erra coerentemente", function()
	local a = UDim.new(0.1, 5)
	local color = Color3.new(1, 0, 0)
	local ok = pcall(function()
		return asBinaryOperable(a) + asBinaryOperable(color)
	end)
	assert(not ok, "UDim + Color3 deveria errar")
end)

-- ================================================================================================
-- P9 -- Unário `-` e `==`: NÃO confirmados por fonte primária (ver cabeçalho de UDim.luau).
-- Testados aqui como a hipótese conservadora IMPLEMENTADA, nunca como fato confirmado.
-- ================================================================================================

test("[P9, NÃO CONFIRMADO] unário -UDim nega os dois componentes", function()
	local u = UDim.new(0.5, 10)
	local negated = -u
	assert(negated.Scale == -0.5, `esperava Scale=-0.5, recebeu {negated.Scale}`)
	assert(negated.Offset == -10, `esperava Offset=-10, recebeu {negated.Offset}`)
end)

test("[P9, NÃO CONFIRMADO] == compara por valor, componente a componente", function()
	local a = UDim.new(0.5, 10)
	local b = UDim.new(0.5, 10)
	local c = UDim.new(0.5, 11)
	assert(asEq(a) == asEq(b), "dois UDim com o mesmo valor deveriam ser ==")
	assert(not (asEq(a) == asEq(c)), "dois UDim com Offset diferente não deveriam ser ==")
end)

test("__eq: tipo NOSSO diferente (Color3) -> false SEM erro (invariante 4 da fábrica)", function()
	local u = UDim.new(0.5, 10)
	local color = Color3.new(0.5, 0.5, 0.5)
	local ok, result = pcall(function()
		return asEq(u) == asEq(color)
	end)
	assert(ok, `comparar UDim com Color3 não deveria errar, erro: {tostring(result)}`)
	assert(result == false, "UDim == Color3 deveria ser false")
end)

test("__eq: comparação com valor solto (number/string/nil) -> false, sem erro", function()
	local u = UDim.new(0.5, 10)
	assert(not (asEq(u) == asEq(5)), "UDim == 5 deveria ser false")
	assert(not (asEq(u) == asEq("5")), "UDim == \"5\" deveria ser false")
	assert(not (asEq(u) == asEq(nil)), "UDim == nil deveria ser false")
end)

-- ================================================================================================
-- tostring -- P2: inferido, sem exemplo isolado no YAML (ver cabeçalho de UDim.luau)
-- ================================================================================================

test("[P2, inferido] tostring: formato '{Scale, Offset}'", function()
	local a = tostring(UDim.new(0.5, 10))
	assert(a == "{0.5, 10}", `esperava "\{0.5, 10\}", recebeu "{a}"`)
	local b = tostring(UDim.new(0, 0))
	assert(b == "{0, 0}", `esperava "\{0, 0\}", recebeu "{b}"`)
end)

-- ================================================================================================
-- Imutabilidade / userdata nativo
-- ================================================================================================

test("mutação erra: escrever em Scale/Offset não é permitido (UDim é imutável)", function()
	local u = UDim.new(0.5, 10)
	local ok, err = pcall(function()
		asStringIndexable(u).Offset = 99
	end)
	assert(not ok, "escrever em Offset deveria errar")
	assert(string.find(tostring(err), "UDim", 1, true) ~= nil, `mensagem deveria citar UDim, recebeu: {err}`)
	assert(u.Offset == 10, "Offset não deveria ter sido alterado pela tentativa de escrita")
end)

test("type(UDim.new()) == 'userdata'", function()
	assert(type(UDim.new()) == "userdata", `esperava userdata, recebeu {type(UDim.new())}`)
end)

test("setmetatable sobre um UDim erra nativamente (não é código nosso)", function()
	local u = UDim.new()
	local ok, err = pcall(function()
		setmetatableUnknown(u, {})
	end)
	assert(not ok, "setmetatable sobre um UDim deveria errar")
	assert(
		string.find(tostring(err), "table expected", 1, true) ~= nil,
		`mensagem deveria indicar que UDim não é uma tabela (userdata), recebeu: {err}`
	)
end)

test("pairs sobre um UDim erra nativamente (userdata não é iterável)", function()
	local u = UDim.new()
	local ok = pcall(function()
		pairs(u)
	end)
	assert(not ok, "pairs sobre um UDim deveria errar")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
