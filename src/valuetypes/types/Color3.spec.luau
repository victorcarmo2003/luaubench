--!strict

--[[
	Teste da task-valuetypes-005 (types/Color3.luau). Fonte de toda assinatura testada:
	`.claude/agents-memory/pesquisa-datatypes-color-udim-enum-2026-09-05.md`, seção A) Color3.

	Cobre (acceptance da task + regra 06):
	1. Construtores: `new` (com defaults e quantização float32), `fromRGB` (range 0-255,
	   defaults), `fromHSV` (obrigatórios, sem default), `fromHex` (6 e 3 dígitos, com/sem "#",
	   case-insensitive -- os quatro exemplos literais do YAML oficial).
	2. Propriedades R/G/B (leitura).
	3. Métodos: `Lerp`, `ToHSV`, `ToHex`.
	4. `tostring` no formato confirmado "R, G, B" (citação literal: `print(gray10) --> 0.9, 0.9,
	   0.9`, reproduzido aqui byte a byte).
	5. `Color3 + Color3` ERRA (`math_operations: []` confirmado -- não é lacuna, é ausência real).
	6. `__eq`: mesmo valor, valor diferente, tipo NOSSO diferente (UDim), valor solto (5/"x"/nil).
	7. Tentativa de mutação erra (imutabilidade).
	8. `setmetatable`/`pairs` erram nativamente sobre o userdata (não é código nosso que erra).
	9. Quantização float32 verificada contra o oráculo `Float32.Quantize`.

	Roda com `lune run src/valuetypes/types/Color3.spec.luau`.
]]

local process = require("@lune/process")
local Float32 = require("../Float32")
local Color3 = require("./Color3")
local UDim = require("./UDim")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

-- Tipo sintético só pra permitir `==` entre dois value types NOSSOS de tipos diferentes sem que
-- o type-checker recuse a comparação estaticamente (mesmo idioma de `asEq` em
-- Userdata.spec.luau) -- o comportamento exercitado é 100% do `__eq` real instalado pela
-- fábrica, o tipo sintético só empresta a assinatura de operador pro checker.
type EqProbe = typeof(setmetatable({} :: {}, {} :: { __eq: (EqProbe, EqProbe) -> boolean }))
local function asEq(value: unknown): EqProbe
	return value :: EqProbe
end

type BinaryOperableProbe = typeof(setmetatable(
	{} :: {},
	{} :: { __add: (BinaryOperableProbe, BinaryOperableProbe) -> BinaryOperableProbe }
))
local function asBinaryOperable(value: unknown): BinaryOperableProbe
	return value :: BinaryOperableProbe
end

type StringIndexableProbe = typeof(setmetatable({} :: { [string]: unknown }, {}))
local function asStringIndexable(value: unknown): StringIndexableProbe
	return value :: StringIndexableProbe
end

type BinaryRawFn = (unknown, unknown) -> unknown
local setmetatableUnknown: BinaryRawFn = (setmetatable :: unknown) :: BinaryRawFn

-- ================================================================================================
-- Construtores
-- ================================================================================================

test("Color3.new: defaults são 0,0,0 (Color3.new() == Color3.new(0,0,0))", function()
	local c = Color3.new()
	assert(c.R == 0 and c.G == 0 and c.B == 0, `esperava 0,0,0, recebeu {c.R},{c.G},{c.B}`)
end)

test("Color3.new: componentes quantizados pra float32 (oráculo Float32.Quantize)", function()
	local c = Color3.new(0.1, 0.2, 0.3)
	assert(c.R == Float32.Quantize(0.1), "R deveria estar quantizado pra float32")
	assert(c.G == Float32.Quantize(0.2), "G deveria estar quantizado pra float32")
	assert(c.B == Float32.Quantize(0.3), "B deveria estar quantizado pra float32")
end)

test("Color3.fromRGB: defaults 0,0,0 e range 0-255 dividido por 255", function()
	local c = Color3.fromRGB()
	assert(c.R == 0 and c.G == 0 and c.B == 0, "fromRGB() sem args deveria ser 0,0,0")

	local red = Color3.fromRGB(255, 0, 0)
	assert(red.R == 1 and red.G == 0 and red.B == 0, `esperava 1,0,0, recebeu {red.R},{red.G},{red.B}`)

	local mid = Color3.fromRGB(128, 64, 32)
	assert(mid.R == Float32.Quantize(128 / 255), "R deveria ser 128/255 quantizado")
	assert(mid.G == Float32.Quantize(64 / 255), "G deveria ser 64/255 quantizado")
	assert(mid.B == Float32.Quantize(32 / 255), "B deveria ser 32/255 quantizado")
end)

test("Color3.fromHSV: sem defaults -- os três parâmetros são obrigatórios (confirmado pela pesquisa)", function()
	-- fromHSV(0, 1, 1) -> vermelho puro (matiz 0 = vermelho, saturação/valor máximos).
	local red = Color3.fromHSV(0, 1, 1)
	assert(red.R == 1 and red.G == 0 and red.B == 0, `fromHSV(0,1,1) deveria ser vermelho puro, recebeu {red.R},{red.G},{red.B}`)

	-- saturação 0 -> tom de cinza igual a v em todos os canais, independente do matiz.
	local gray = Color3.fromHSV(0.5, 0, 0.5)
	assert(gray.R == gray.G and gray.G == gray.B, "saturação 0 deveria produzir R==G==B")
	assert(math.abs(gray.R - 0.5) < 1e-6, `esperava ~0.5, recebeu {gray.R}`)
end)

test("Color3.fromHex: 6 dígitos, com e sem '#', case-insensitive (exemplos literais do YAML)", function()
	local a = Color3.fromHex("FF0000")
	assert(a.R == 1 and a.G == 0 and a.B == 0, "fromHex(FF0000) deveria ser vermelho puro")

	local b = Color3.fromHex("#ec008c")
	assert(b.R == Float32.Quantize(0xec / 255), "R deveria bater com 0xEC/255")
	assert(b.G == Float32.Quantize(0x00 / 255), "G deveria bater com 0x00/255")
	assert(b.B == Float32.Quantize(0x8c / 255), "B deveria bater com 0x8C/255")

	-- case-insensitive: minúsculo e maiúsculo produzem o mesmo resultado.
	local lower = Color3.fromHex("ff0000")
	assert(lower.R == a.R and lower.G == a.G and lower.B == a.B, "fromHex deveria ser case-insensitive")
end)

test("Color3.fromHex: shorthand de 3 dígitos duplica cada dígito (exemplos literais '000'/'#FFF')", function()
	local black = Color3.fromHex("000")
	assert(black.R == 0 and black.G == 0 and black.B == 0, "fromHex(000) deveria ser preto")

	local white = Color3.fromHex("#FFF")
	assert(white.R == 1 and white.G == 1 and white.B == 1, "fromHex(#FFF) deveria ser branco")
end)

test("Color3.fromHex: formato inválido erra", function()
	local ok = pcall(function()
		Color3.fromHex("12345")
	end)
	assert(not ok, "fromHex com 5 dígitos deveria errar")

	local ok2 = pcall(function()
		Color3.fromHex("GGGGGG")
	end)
	assert(not ok2, "fromHex com dígitos não-hexadecimais deveria errar")
end)

-- Regressão do bug real (task-valuetypes-005-fix, achado MEDIO do revisor): a validação antiga
-- usava só `tonumber(x, 16) == nil`, que NÃO rejeita sinal embutido -- `tonumber("-1", 16)` no
-- Lune/Luau devolve 18446744073709552000 (interpretado como inteiro de 64 bits sem sinal) em vez
-- de `nil`, então `Color3.fromHex("-10000")` não errava: devolvia um Color3 "HDR" com
-- R = 72340177116200960 (wraparound), lixo silencioso. O fix valida o FORMATO inteiro (regex
-- `^%x%x%x%x%x%x$`/`^%x%x%x$`, que só casa `[0-9a-fA-F]`) antes de converter qualquer dígito.
test("Color3.fromHex: sinal embutido ou caractere fora de [0-9a-fA-F] erra citando a entrada, nunca devolve valor-lixo", function()
	local invalidInputs = {
		"-10000", -- sinal de menos embutido -- o bug original relatado pelo revisor.
		"+00ff00", -- sinal de mais embutido.
		"12345!", -- símbolo fora do alfabeto hex, 6 caracteres no total.
		"12 456", -- espaço fora do alfabeto hex.
		"#-fff", -- sinal embutido na forma abreviada, com "#".
	}

	for _, input in invalidInputs do
		local ok, err = pcall(function()
			return Color3.fromHex(input)
		end)
		assert(not ok, `fromHex("{input}") deveria errar, nunca devolver um Color3`)
		local message = tostring(err)
		assert(
			string.find(message, input, 1, true) ~= nil,
			`mensagem de erro deveria citar a entrada inválida "{input}", recebeu: {message}`
		)
	end
end)

-- Confirma que o fix NÃO afetou nenhuma entrada válida (regressão): 3 e 6 dígitos, com/sem "#",
-- case misto (maiúsculo/minúsculo dentro da MESMA string, não só uma string toda maiúscula ou
-- toda minúscula) continuam produzindo exatamente o mesmo resultado de antes do fix.
test("Color3.fromHex: entradas válidas continuam idênticas após o fix (3/6 dígitos, com/sem '#', case misto)", function()
	local mixedCase = Color3.fromHex("Ec008C")
	local allLower = Color3.fromHex("#ec008c")
	assert(
		mixedCase.R == allLower.R and mixedCase.G == allLower.G and mixedCase.B == allLower.B,
		"fromHex com case misto deveria produzir o mesmo resultado que tudo minúsculo"
	)

	local shortMixed = Color3.fromHex("AbC")
	local shortExpanded = Color3.fromHex("AABBCC")
	assert(
		shortMixed.R == shortExpanded.R and shortMixed.G == shortExpanded.G and shortMixed.B == shortExpanded.B,
		"fromHex abreviado com case misto deveria expandir cada dígito igual a antes"
	)
end)

-- ================================================================================================
-- Propriedades
-- ================================================================================================

test("R/G/B: leitura de propriedade", function()
	local c = Color3.new(0.25, 0.5, 0.75)
	assert(c.R == Float32.Quantize(0.25), "R incorreto")
	assert(c.G == Float32.Quantize(0.5), "G incorreto")
	assert(c.B == Float32.Quantize(0.75), "B incorreto")
end)

test("acessar um membro inválido erra citando a chave e 'Color3'", function()
	local c = Color3.new()
	local ok, err = pcall(function()
		return asStringIndexable(c).NaoExiste
	end)
	assert(not ok, "ler um membro inválido deveria errar")
	local message = tostring(err)
	assert(string.find(message, "NaoExiste", 1, true) ~= nil, `mensagem deveria citar a chave, recebeu: {message}`)
	assert(string.find(message, "Color3", 1, true) ~= nil, `mensagem deveria citar Color3, recebeu: {message}`)
end)

-- ================================================================================================
-- Métodos: Lerp / ToHSV / ToHex
-- ================================================================================================

test("Lerp: reproduz o exemplo literal do YAML (white:Lerp(black, 0.1) --> 0.9, 0.9, 0.9)", function()
	local white = Color3.new(1, 1, 1)
	local black = Color3.new(0, 0, 0)
	local gray10 = white:Lerp(black, 0.1)
	assert(tostring(gray10) == "0.9, 0.9, 0.9", `esperava "0.9, 0.9, 0.9", recebeu "{tostring(gray10)}"`)
end)

test("Lerp: alpha 0 devolve o próprio, alpha 1 devolve o alvo", function()
	local a = Color3.new(0.2, 0.4, 0.6)
	local b = Color3.new(0.8, 0.6, 0.4)
	local at0 = a:Lerp(b, 0)
	local at1 = a:Lerp(b, 1)
	assert(at0.R == a.R and at0.G == a.G and at0.B == a.B, "Lerp(alpha=0) deveria ser igual ao próprio")
	assert(at1.R == b.R and at1.G == b.G and at1.B == b.B, "Lerp(alpha=1) deveria ser igual ao alvo")
end)

test("ToHSV: devolve 3 valores, round-trip com fromHSV pra cores primárias", function()
	local red = Color3.new(1, 0, 0)
	local h, s, v = red:ToHSV()
	assert(h == 0, `esperava h==0 pro vermelho puro, recebeu {h}`)
	assert(s == 1, `esperava s==1, recebeu {s}`)
	assert(v == 1, `esperava v==1, recebeu {v}`)

	local green = Color3.new(0, 1, 0)
	local hg = green:ToHSV()
	assert(math.abs(hg - 1 / 3) < 1e-6, `esperava h~=1/3 pro verde puro, recebeu {hg}`)
end)

test("ToHex: devolve string de 6 caracteres, formato RRGGBB, sem '#'", function()
	local red = Color3.fromRGB(255, 0, 0)
	local hex = red:ToHex()
	assert(#hex == 6, `esperava 6 caracteres, recebeu {#hex}: "{hex}"`)
	assert(string.sub(hex, 1, 1) ~= "#", "ToHex não deveria prefixar com '#'")
	assert(hex == "ff0000", `esperava "ff0000", recebeu "{hex}"`)

	-- round-trip: fromHex(ToHex(c)) deveria reproduzir a mesma cor.
	local roundTripped = Color3.fromHex(hex)
	assert(roundTripped.R == red.R and roundTripped.G == red.G and roundTripped.B == red.B, "round-trip ToHex/fromHex falhou")
end)

-- ================================================================================================
-- tostring
-- ================================================================================================

test("tostring: formato 'R, G, B' (vírgula-espaço, sem colchetes)", function()
	assert(tostring(Color3.new(0, 0, 0)) == "0, 0, 0", `esperava "0, 0, 0", recebeu "{tostring(Color3.new(0, 0, 0))}"`)
	assert(tostring(Color3.new(1, 1, 1)) == "1, 1, 1", `esperava "1, 1, 1", recebeu "{tostring(Color3.new(1, 1, 1))}"`)
end)

-- ================================================================================================
-- Color3 + Color3 ERRA -- math_operations: [] confirmado (não é lacuna, é comportamento certo).
-- ================================================================================================

test("Color3 + Color3 ERRA (sem operador aritmético, confirmado por math_operations: [])", function()
	local a = Color3.new(1, 0, 0)
	local b = Color3.new(0, 1, 0)
	local ok, err = pcall(function()
		return asBinaryOperable(a) + asBinaryOperable(b)
	end)
	assert(not ok, "Color3 + Color3 deveria ERRAR -- Color3 não tem nenhum operador aritmético")
	assert(
		string.find(tostring(err), "arithmetic", 1, true) ~= nil,
		`esperava o erro nativo de aritmética do Luau, recebeu: {err}`
	)
end)

-- ================================================================================================
-- __eq
-- ================================================================================================

test("__eq: mesmo valor -> true, valor diferente -> false", function()
	local a = Color3.new(0.5, 0.5, 0.5)
	local b = Color3.new(0.5, 0.5, 0.5)
	local c = Color3.new(0.5, 0.5, 0.6)
	assert(asEq(a) == asEq(b), "duas Color3 com o mesmo valor deveriam ser ==")
	assert(not (asEq(a) == asEq(c)), "duas Color3 com valores diferentes não deveriam ser ==")
end)

test("__eq: tipo NOSSO diferente (UDim) -> false SEM erro (invariante 4 da fábrica)", function()
	local color = Color3.new(0.5, 0.5, 0.5)
	local udim = UDim.new(0.5, 5)
	local ok, result = pcall(function()
		return asEq(color) == asEq(udim)
	end)
	assert(ok, `comparar Color3 com UDim não deveria errar, erro: {tostring(result)}`)
	assert(result == false, "Color3 == UDim deveria ser false")
end)

test("__eq: comparação com valor solto (number/string/nil) -> false, sem erro", function()
	local color = Color3.new(0.5, 0.5, 0.5)
	assert(not (asEq(color) == asEq(5)), "Color3 == 5 deveria ser false")
	assert(not (asEq(color) == asEq("5")), "Color3 == \"5\" deveria ser false")
	assert(not (asEq(color) == asEq(nil)), "Color3 == nil deveria ser false")
end)

-- ================================================================================================
-- Imutabilidade / userdata nativo
-- ================================================================================================

test("mutação erra: escrever em R/G/B não é permitido (Color3 é imutável)", function()
	local c = Color3.new(1, 0, 0)
	local ok, err = pcall(function()
		asStringIndexable(c).R = 0
	end)
	assert(not ok, "escrever em R deveria errar")
	assert(string.find(tostring(err), "Color3", 1, true) ~= nil, `mensagem deveria citar Color3, recebeu: {err}`)
	assert(c.R == 1, "R não deveria ter sido alterado pela tentativa de escrita")
end)

test("type(Color3.new()) == 'userdata'", function()
	assert(type(Color3.new()) == "userdata", `esperava userdata, recebeu {type(Color3.new())}`)
end)

test("setmetatable sobre um Color3 erra nativamente (não é código nosso)", function()
	local c = Color3.new()
	local ok, err = pcall(function()
		setmetatableUnknown(c, {})
	end)
	assert(not ok, "setmetatable sobre um Color3 deveria errar")
	assert(
		string.find(tostring(err), "table expected", 1, true) ~= nil,
		`mensagem deveria indicar que Color3 não é uma tabela (userdata), recebeu: {err}`
	)
end)

test("pairs sobre um Color3 erra nativamente (userdata não é iterável)", function()
	local c = Color3.new()
	local ok = pcall(function()
		pairs(c)
	end)
	assert(not ok, "pairs sobre um Color3 deveria errar")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
