--!strict

--[[
	Color3 -- cor RGB imutável (task-valuetypes-005). Fonte: `.claude/agents-memory/
	pesquisa-datatypes-color-udim-enum-2026-09-05.md`, seção A) Color3 -- leitura obrigatória
	já feita antes de escrever este módulo, mesma disciplina do resto do território (regra 00:
	nenhuma assinatura inventada, nenhuma pesquisa repetida).

	## Superfície confirmada pela pesquisa

	- Construtores: `Color3.new(r?, g?, b?)` (defaults 0, range documentado 0-1),
	  `Color3.fromRGB(r?, g?, b?)` (defaults 0, range documentado 0-255), `Color3.fromHSV(h, s, v)`
	  (a doc NÃO declara default pra nenhum dos três -- por isso são parâmetros OBRIGATÓRIOS aqui,
	  diferente de `.new`/`fromRGB`), `Color3.fromHex(hex: string)` (aceita "RRGGBB" ou "RGB"
	  abreviado tipo CSS, com ou sem "#" líder, case-insensitive -- os quatro exemplos do próprio
	  YAML: "FF0000", "ec008c", "000", "#FFF").
	- Propriedades: `R`, `G`, `B` -- todas read-only (garantido pela fábrica via `__newindex`).
	- Métodos: `Lerp(color, alpha): Color3`, `ToHSV(): (number, number, number)` (devolve TRÊS
	  valores), `ToHex(): string` (6 caracteres, formato "RRGGBB", SEM "#" prefixado).
	- `Color3.toHSV(color)` (função solta, não-método) é DEPRECATED na doc oficial -- NÃO
	  implementada aqui (regra 03: membro deprecated só entra se algum projeto real depender dele;
	  nenhuma evidência disso até agora).

	## `Color3 + Color3` ERRA -- de propósito, não é lacuna esquecida

	`math_operations: []` na doc oficial (seção A da pesquisa, citação direta) -- Color3 NÃO tem
	NENHUM operador aritmético no Roblox real. Por isso o Descriptor abaixo simplesmente OMITE
	`Add`/`Sub`/`Mul`/`Div`/`Unm` -- a fábrica (`Userdata.luau`) não instala o metamétodo
	correspondente, e o erro nativo que o Luau levanta sozinho ("attempt to perform
	arithmetic...") já É o comportamento certo. Testado explicitamente no spec
	("Color3 + Color3 ERRA").

	## Divergências declaradas (regra 00 -- nunca silenciosas)

	- **Sem clamping em `new`/`fromRGB` fora do range documentado (0-1 / 0-255)**: a pesquisa
	  (seção "Incerto", item 1) não confirma se o Roblox clampa, lança erro ou aceita HDR sem
	  modificar -- implementar clamping seria inventar comportamento não confirmado (invariante 1
	  do projeto). Valores fora do range passam direto (podem produzir um Color3 "HDR", R/G/B fora
	  de [0,1]).
	- **`fromRGB` não arredonda o input** (ex.: `fromRGB(127.5, 0, 0)`): pesquisa item 2 não achou
	  fonte. Escolha mais simples e conservadora: divide por 255 sem arredondar antes.
	- **`ToHex` usa dígitos hexadecimais MINÚSCULOS** (`"ff0000"`, não `"FF0000"`): não confirmado
	  por nenhuma fonte da pesquisa -- aproximação de boa-fé (convenção mais comum de
	  `string.format("%02x", ...)`, e a doc mostra exemplos de INPUT de fromHex em ambos os casos,
	  não confirma o case do OUTPUT de ToHex).
	- **`ToHSV`/`fromHSV` usam o algoritmo padrão matemático de conversão HSV<->RGB**: não é
	  comportamento Roblox-específico inventado -- é a matemática universal do espaço de cor HSV
	  (a mesma fórmula usada por qualquer engine/ferramenta gráfica), não uma suposição sobre a
	  implementação interna do Roblox.

	Depende de: Float32, Userdata. Usado por: init.luau (task-valuetypes-007, futura).
]]

local Float32 = require("../Float32")
local Userdata = require("../Userdata")

export type Color3 = typeof(setmetatable(
	{} :: {
		R: number,
		G: number,
		B: number,
		Lerp: (self: Color3, color: Color3, alpha: number) -> Color3,
		ToHSV: (self: Color3) -> (number, number, number),
		ToHex: (self: Color3) -> string,
	},
	{} :: {
		__tostring: (Color3) -> string,
	}
))

local Color3Module = {}

-- Forward declaration -- mesmo padrão de `SpecPointFactory` em Userdata.spec.luau: os
-- construtores abaixo fecham sobre `Factory` como upvalue, mas só a CHAMAM em runtime, depois
-- que `Userdata.Define` já rodou (fim deste arquivo).
local Factory: Userdata.Factory

local function fields(r: number, g: number, b: number): Userdata.Fields
	return {
		Float32.Quantize(r),
		Float32.Quantize(g),
		Float32.Quantize(b),
	}
end

local function fromFields(r: number, g: number, b: number): Color3
	return Factory(fields(r, g, b)) :: Color3
end

-- ================================================================================================
-- HSV <-> RGB -- algoritmo padrão do espaço de cor (ver "Divergências declaradas" acima).
-- ================================================================================================

local function hsvToRgb(h: number, s: number, v: number): (number, number, number)
	if s <= 0 then
		return v, v, v
	end

	-- h em [0, 1) representa uma volta completa (0..360°) -- convenção do próprio Color3.fromHSV.
	local sector = (h % 1) * 6
	local sectorIndex = math.min(math.floor(sector), 5)
	local fractional = sector - sectorIndex

	local p = v * (1 - s)
	local q = v * (1 - s * fractional)
	local t = v * (1 - s * (1 - fractional))

	if sectorIndex == 0 then
		return v, t, p
	elseif sectorIndex == 1 then
		return q, v, p
	elseif sectorIndex == 2 then
		return p, v, t
	elseif sectorIndex == 3 then
		return p, q, v
	elseif sectorIndex == 4 then
		return t, p, v
	else
		return v, p, q
	end
end

local function rgbToHsv(r: number, g: number, b: number): (number, number, number)
	local maxComponent = math.max(r, g, b)
	local minComponent = math.min(r, g, b)
	local delta = maxComponent - minComponent

	local h = 0
	if delta > 0 then
		if maxComponent == r then
			h = ((g - b) / delta) % 6
		elseif maxComponent == g then
			h = (b - r) / delta + 2
		else
			h = (r - g) / delta + 4
		end
		h = h / 6
	end

	local s = if maxComponent <= 0 then 0 else delta / maxComponent
	local v = maxComponent

	return h, s, v
end

-- ================================================================================================
-- Hex parsing -- "RRGGBB" ou "RGB" (shorthand tipo CSS), com/sem "#", case-insensitive.
-- ================================================================================================

local function parseHexChannel(hexPair: string): number
	local value = tonumber(hexPair, 16)
	if value == nil then
		error(`Color3.fromHex: "{hexPair}" não é um dígito hexadecimal válido`, 4)
	end
	return (value :: number) / 255
end

Color3Module.new = function(r: number?, g: number?, b: number?): Color3
	return fromFields(r or 0, g or 0, b or 0)
end

Color3Module.fromRGB = function(r: number?, g: number?, b: number?): Color3
	return fromFields((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end

-- Sem defaults (ver cabeçalho): a doc oficial não declara nenhum pros três parâmetros.
Color3Module.fromHSV = function(h: number, s: number, v: number): Color3
	local r, g, b = hsvToRgb(h, s, v)
	return fromFields(r, g, b)
end

Color3Module.fromHex = function(hex: string): Color3
	local body = hex
	if string.sub(body, 1, 1) == "#" then
		body = string.sub(body, 2)
	end

	if #body == 3 then
		local r = parseHexChannel(string.rep(string.sub(body, 1, 1), 2))
		local g = parseHexChannel(string.rep(string.sub(body, 2, 2), 2))
		local b = parseHexChannel(string.rep(string.sub(body, 3, 3), 2))
		return fromFields(r, g, b)
	elseif #body == 6 then
		local r = parseHexChannel(string.sub(body, 1, 2))
		local g = parseHexChannel(string.sub(body, 3, 4))
		local b = parseHexChannel(string.sub(body, 5, 6))
		return fromFields(r, g, b)
	end

	error(
		`Color3.fromHex: "{hex}" não é um formato hexadecimal válido (esperado "RRGGBB" ou "RGB", com "#" opcional)`,
		2
	)
end

local methods: { [string]: unknown } = {
	Lerp = function(self: unknown, other: unknown, alpha: number): unknown
		local a = Userdata.Unwrap(self, "Color3")
		local b = Userdata.Unwrap(other, "Color3")
		local ar, ag, ab = a[1] :: number, a[2] :: number, a[3] :: number
		local br, bg, bb = b[1] :: number, b[2] :: number, b[3] :: number
		return fromFields(ar + (br - ar) * alpha, ag + (bg - ag) * alpha, ab + (bb - ab) * alpha)
	end,
	ToHSV = function(self: unknown): (number, number, number)
		local f = Userdata.Unwrap(self, "Color3")
		return rgbToHsv(f[1] :: number, f[2] :: number, f[3] :: number)
	end,
	ToHex = function(self: unknown): string
		local f = Userdata.Unwrap(self, "Color3")
		local r = math.clamp(math.floor((f[1] :: number) * 255 + 0.5), 0, 255)
		local g = math.clamp(math.floor((f[2] :: number) * 255 + 0.5), 0, 255)
		local b = math.clamp(math.floor((f[3] :: number) * 255 + 0.5), 0, 255)
		return string.format("%02x%02x%02x", r, g, b)
	end,
}
table.freeze(methods)

Factory = Userdata.Define({
	TypeName = "Color3",
	Methods = methods,
	GetProperty = function(f: Userdata.Fields, key: string): (unknown, boolean)
		if key == "R" then
			return f[1], true
		elseif key == "G" then
			return f[2], true
		elseif key == "B" then
			return f[3], true
		end
		return nil, false
	end,
	-- Confirmado por citação literal da pesquisa: "R, G, B" (vírgula-espaço, sem colchetes),
	-- ex. `print(gray10) --> 0.9, 0.9, 0.9`.
	Format = function(f: Userdata.Fields): string
		return `{Float32.Format(f[1] :: number)}, {Float32.Format(f[2] :: number)}, {Float32.Format(f[3] :: number)}`
	end,
	-- Add/Sub/Mul/Div/Unm deliberadamente AUSENTES -- ver cabeçalho ("Color3 + Color3 ERRA").
	Equals = function(a: Userdata.Fields, b: Userdata.Fields): boolean
		return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
	end,
})

return Color3Module
