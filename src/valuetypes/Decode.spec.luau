--!strict

--[[
	Teste da task-valuetypes-007 (Decode.luau -- gramática de valor do `$properties` do Rojo).
	Cobre o acceptance verbatim do board (.claude/tasks.json, task-valuetypes-007):

	1. `[1,2,3]` com alvo `Vector3` vs. alvo `Color3` produzindo tipos DIFERENTES a partir do MESMO
	   array bruto.
	2. Array de 12 números -> `CFrame`.
	3. String com alvo `Enum` -> `EnumItem` (via `Enum.<Nome>:FromName(...)` internamente).
	4. Forma inválida -> `DecodeFailure` com motivo legível, NUNCA erro lançado -- cada teste de
	   forma inválida chama `Decode.FromRojoJson` DIRETO, sem `pcall`: se o contrato "nunca lança"
	   fosse violado, o teste crasharia o processo inteiro (falha óbvia, não passa escondido).

	Cobre também: `Vector2`/`UDim`/`UDim2` (arrays de 2/2/4 números), e as várias formas de "forma
	inválida" (tipo errado, tamanho errado, elemento não-numérico, categoria não decodificável,
	`valueTypeName` de DataType ainda não simulado, enum inexistente, item de enum inexistente).

	Roda com `lune run src/valuetypes/Decode.spec.luau`.
]]

local process = require("@lune/process")
local Userdata = require("./Userdata")
local Decode = require("./Decode")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

-- Vitrine tipada SEM `any` pra ler propriedade dinâmica (`.X`, `.R`, ...) do `Value: unknown` de
-- um `DecodeSuccess` -- mesmo padrão de `asStringIndexable` já usado em todo `types/*.spec.luau`
-- deste território.
type StringIndexableProbe = typeof(setmetatable({} :: { [string]: unknown }, {}))
local function asStringIndexable(value: unknown): StringIndexableProbe
	return value :: StringIndexableProbe
end

local function expectOk(result: Decode.DecodeResult): unknown
	assert(result.Ok, `esperava DecodeSuccess, recebeu DecodeFailure: {if result.Ok then "" else result.Reason}`)
	return (result :: Decode.DecodeSuccess).Value
end

local function expectFail(result: Decode.DecodeResult): string
	assert(not result.Ok, "esperava DecodeFailure, recebeu DecodeSuccess")
	local reason = (result :: Decode.DecodeFailure).Reason
	assert(typeof(reason) == "string" and #reason > 0, "DecodeFailure.Reason deveria ser uma string não vazia e legível")
	return reason
end

-- ================================================================================================
-- ACCEPTANCE 1: [1,2,3] com alvo Vector3 vs. alvo Color3 -- MESMO array bruto, tipos DIFERENTES.
-- Prova a ambiguidade confirmada pela pesquisa do Rojo (o mesmo array serve Part.Position
-- (Vector3) e Lighting.Ambient (Color3) -- resolvida só pelo ValueType alvo, nunca pelo JSON).
-- ================================================================================================

test("[1,2,3] com valueTypeName=Vector3 produz um Vector3 de verdade", function()
	local value = expectOk(Decode.FromRojoJson("Vector3", "DataType", { 1, 2, 3 }))
	assert(Userdata.TypeNameOf(value) == "Vector3", `esperava TypeNameOf == "Vector3", recebeu {tostring(Userdata.TypeNameOf(value))}`)
	local probe = asStringIndexable(value)
	assert(probe.X == 1 and probe.Y == 2 and probe.Z == 3, `esperava (1,2,3), recebeu ({probe.X},{probe.Y},{probe.Z})`)
end)

test("O MESMO array [1,2,3] com valueTypeName=Color3 produz um Color3 de verdade (tipo DIFERENTE)", function()
	local value = expectOk(Decode.FromRojoJson("Color3", "DataType", { 1, 2, 3 }))
	assert(Userdata.TypeNameOf(value) == "Color3", `esperava TypeNameOf == "Color3", recebeu {tostring(Userdata.TypeNameOf(value))}`)
	local probe = asStringIndexable(value)
	assert(probe.R == 1 and probe.G == 2 and probe.B == 3, `esperava (1,2,3), recebeu ({probe.R},{probe.G},{probe.B})`)
end)

test("[0.5, 0.5, 0.5] com valueTypeName=Color3 decodifica em faixa 0-1 (equivalente a Color3.new, não fromRGB)", function()
	-- Exemplo real citado pelo arquiteto (desenho §7): Lighting.Ambient = [0.5, 0.5, 0.5] no
	-- default.project.json gerado por `rojo init` -- ver cabeçalho de Decode.luau, "Color3: 0-1 ou
	-- 0-255?".
	local value = expectOk(Decode.FromRojoJson("Color3", "DataType", { 0.5, 0.5, 0.5 }))
	local probe = asStringIndexable(value)
	assert(probe.R == 0.5 and probe.G == 0.5 and probe.B == 0.5, `esperava (0.5,0.5,0.5), recebeu ({probe.R},{probe.G},{probe.B})`)
end)

-- ================================================================================================
-- ACCEPTANCE 2: array de 12 números -> CFrame.
-- ================================================================================================

test("array de 12 números com valueTypeName=CFrame produz um CFrame de verdade", function()
	local raw = { 1, 2, 3, 1, 0, 0, 0, 1, 0, 0, 0, 1 }
	local value = expectOk(Decode.FromRojoJson("CFrame", "DataType", raw))
	assert(Userdata.TypeNameOf(value) == "CFrame", `esperava TypeNameOf == "CFrame", recebeu {tostring(Userdata.TypeNameOf(value))}`)
	local probe = asStringIndexable(value)
	assert(probe.X == 1 and probe.Y == 2 and probe.Z == 3, `posição esperada (1,2,3), recebeu ({probe.X},{probe.Y},{probe.Z})`)
end)

-- ================================================================================================
-- ACCEPTANCE 3: string com alvo Enum -> EnumItem.
-- ================================================================================================

test("string 'Plastic' com valueTypeName=Material, valueCategory=Enum produz o EnumItem Enum.Material.Plastic", function()
	local value = expectOk(Decode.FromRojoJson("Material", "Enum", "Plastic"))
	assert(Userdata.TypeNameOf(value) == "EnumItem", `esperava TypeNameOf == "EnumItem", recebeu {tostring(Userdata.TypeNameOf(value))}`)
	assert(tostring(value) == "Enum.Material.Plastic", `esperava "Enum.Material.Plastic", recebeu {tostring(value)}`)
	local probe = asStringIndexable(value)
	assert(probe.Name == "Plastic", `EnumItem.Name esperado "Plastic", recebeu {tostring(probe.Name)}`)
end)

-- ================================================================================================
-- Vector2 / UDim / UDim2 -- mesma família de "array de N números", cobertos pelo mesmo mecanismo.
-- ================================================================================================

test("[1,2] com valueTypeName=Vector2 produz um Vector2 de verdade", function()
	local value = expectOk(Decode.FromRojoJson("Vector2", "DataType", { 1, 2 }))
	assert(Userdata.TypeNameOf(value) == "Vector2", `esperava TypeNameOf == "Vector2", recebeu {tostring(Userdata.TypeNameOf(value))}`)
	local probe = asStringIndexable(value)
	assert(probe.X == 1 and probe.Y == 2, `esperava (1,2), recebeu ({probe.X},{probe.Y})`)
end)

test("[0.5, 10] com valueTypeName=UDim produz um UDim de verdade (Scale, Offset)", function()
	local value = expectOk(Decode.FromRojoJson("UDim", "DataType", { 0.5, 10 }))
	assert(Userdata.TypeNameOf(value) == "UDim", `esperava TypeNameOf == "UDim", recebeu {tostring(Userdata.TypeNameOf(value))}`)
	local probe = asStringIndexable(value)
	assert(probe.Scale == 0.5 and probe.Offset == 10, `esperava (0.5,10), recebeu ({probe.Scale},{probe.Offset})`)
end)

test("[0, 300, 1, 0] com valueTypeName=UDim2 produz um UDim2 de verdade (xScale,xOffset,yScale,yOffset)", function()
	local value = expectOk(Decode.FromRojoJson("UDim2", "DataType", { 0, 300, 1, 0 }))
	assert(Userdata.TypeNameOf(value) == "UDim2", `esperava TypeNameOf == "UDim2", recebeu {tostring(Userdata.TypeNameOf(value))}`)
	assert(tostring(value) == "{0, 300}, {1, 0}", `esperava "\{0, 300\}, \{1, 0\}", recebeu {tostring(value)}`)
end)

-- ================================================================================================
-- ACCEPTANCE 4: formas inválidas -> DecodeFailure com motivo legível, NUNCA erro lançado.
-- Cada chamada abaixo é feita DIRETO (sem pcall): se Decode violasse o contrato "nunca lança",
-- o próprio `lune run` deste arquivo crasharia aqui -- a ausência de crash já é parte da prova.
-- ================================================================================================

test("Vector3 recebendo uma STRING (tipo errado) -> DecodeFailure, não erro", function()
	local reason = expectFail(Decode.FromRojoJson("Vector3", "DataType", "não é um array"))
	assert(string.find(reason, "Vector3", 1, true) ~= nil, `motivo deveria citar o tipo alvo, recebeu: {reason}`)
end)

test("Vector3 recebendo array de tamanho ERRADO ([1,2]) -> DecodeFailure citando o tamanho", function()
	local reason = expectFail(Decode.FromRojoJson("Vector3", "DataType", { 1, 2 }))
	assert(string.find(reason, "tamanho 2", 1, true) ~= nil, `motivo deveria citar o tamanho recebido, recebeu: {reason}`)
end)

test("Vector3 recebendo array com ELEMENTO NÃO-NUMÉRICO ([1, 'x', 3]) -> DecodeFailure", function()
	-- Anotado como `{ unknown }` (não `{1, "x", 3}` cru): um array literal heterogêneo sem
	-- anotação faria o Luau inferir o tipo pelo PRIMEIRO elemento (`{number}`) e recusar o
	-- segundo ("x") estaticamente -- o que aconteceria é exatamente um erro de type-checker, não
	-- o comportamento de runtime que este teste quer exercitar (JSON de verdade não passa por
	-- checagem estática nenhuma antes de chegar em `Decode`).
	local raw: { unknown } = { 1, "x", 3 }
	local reason = expectFail(Decode.FromRojoJson("Vector3", "DataType", raw))
	assert(string.find(reason, "elemento 2", 1, true) ~= nil, `motivo deveria citar o elemento problemático, recebeu: {reason}`)
end)

test("CFrame recebendo array de 11 números (faltando 1) -> DecodeFailure", function()
	local reason = expectFail(Decode.FromRojoJson("CFrame", "DataType", { 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0 }))
	assert(string.find(reason, "12", 1, true) ~= nil, `motivo deveria citar o tamanho esperado (12), recebeu: {reason}`)
end)

test("Vector3 recebendo um OBJETO ({x=1,y=2,z=3}, chave não numérica) -> DecodeFailure", function()
	local reason = expectFail(Decode.FromRojoJson("Vector3", "DataType", { x = 1, y = 2, z = 3 }))
	assert(string.find(reason, "objeto", 1, true) ~= nil, `motivo deveria mencionar "objeto", recebeu: {reason}`)
end)

test("Vector3 recebendo nil -> DecodeFailure", function()
	local reason = expectFail(Decode.FromRojoJson("Vector3", "DataType", nil))
	assert(string.find(reason, "nil", 1, true) ~= nil, `motivo deveria mencionar "nil", recebeu: {reason}`)
end)

test("valueTypeName de DataType ainda não simulado (ex.: 'Rect') -> DecodeFailure citando o nome", function()
	local reason = expectFail(Decode.FromRojoJson("Rect", "DataType", { 0, 0, 10, 10 }))
	assert(string.find(reason, "Rect", 1, true) ~= nil, `motivo deveria citar o nome do tipo, recebeu: {reason}`)
end)

test("valueCategory não decodificável (ex.: 'Primitive') -> DecodeFailure, nunca crasha", function()
	local reason = expectFail(Decode.FromRojoJson("string", "Primitive", "qualquer coisa"))
	assert(string.find(reason, "Primitive", 1, true) ~= nil, `motivo deveria citar a categoria recebida, recebeu: {reason}`)
end)

test("Enum com raw não-string -> DecodeFailure", function()
	local reason = expectFail(Decode.FromRojoJson("Material", "Enum", 5))
	assert(string.find(reason, "Material", 1, true) ~= nil, `motivo deveria citar o enum, recebeu: {reason}`)
end)

test("Enum inexistente (nome de enum que não existe) -> DecodeFailure citando o nome, nunca erro", function()
	local reason = expectFail(Decode.FromRojoJson("NaoExisteEnumComEsseNome", "Enum", "Qualquer"))
	assert(string.find(reason, "NaoExisteEnumComEsseNome", 1, true) ~= nil, `motivo deveria citar o nome do enum, recebeu: {reason}`)
end)

test("item de enum inexistente (enum válido, item que não existe) -> DecodeFailure citando os dois nomes", function()
	local reason = expectFail(Decode.FromRojoJson("Material", "Enum", "NaoExisteEsseMaterial"))
	assert(string.find(reason, "NaoExisteEsseMaterial", 1, true) ~= nil, `motivo deveria citar o item, recebeu: {reason}`)
	assert(string.find(reason, "Material", 1, true) ~= nil, `motivo deveria citar o enum, recebeu: {reason}`)
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
