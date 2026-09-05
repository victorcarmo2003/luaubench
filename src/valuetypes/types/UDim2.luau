--!strict

--[[
	UDim2 -- par (X: UDim, Y: UDim) imutável usado por UI (task-valuetypes-005). Fonte:
	`.claude/agents-memory/pesquisa-datatypes-color-udim-enum-2026-09-05.md`, seção B) UDim e
	UDim2 -- leitura obrigatória já feita antes de escrever este módulo.

	## Superfície confirmada

	- `UDim2.new()` -- sem parâmetros, equivalente a `UDim2.new(0, 0, 0, 0)`.
	- `UDim2.new(xScale?, xOffset?, yScale?, yOffset?)` -- quatro números, todos default 0.
	- `UDim2.new(x: UDim, y: UDim)` -- overload REAL confirmado pela pesquisa (citação literal do
	  YAML oficial: `UDim2.new(x, y)` equivale a `UDim2.new(0.5, 10, 1, 0)` quando
	  `x = UDim.new(0.5, 10)`, `y = UDim.new(1, 0)`). Luau não tem overload nativo por assinatura
	  -- `UDim2Module.new` abaixo é uma função ÚNICA que despacha em runtime pela CONTAGEM e pelo
	  TIPO REAL dos argumentos (via `Userdata.TypeNameOf`), exposta publicamente com o tipo
	  INTERSECÇÃO `UDim2NewOverload` (mesmo idioma de "overload por intersecção de tipos de
	  função" que o Luau suporta nativamente) -- sem `any` em lugar nenhum: a implementação interna
	  usa `...: unknown`, e o único cast pro tipo público acontece na fronteira de exportação
	  (mesmo padrão de "único ponto de cast" já usado em `Userdata.luau`/`types/Color3.luau`).
	- `UDim2.fromScale(xScale?, yScale?)` -- offsets ficam 0.
	- `UDim2.fromOffset(xOffset?, yOffset?)` -- scales ficam 0.
	- Propriedades: `X: UDim`, `Y: UDim`. `Width: UDim`, `Height: UDim` são SINÔNIMOS EXATOS de
	  `X`/`Y` (confirmado: "A synonym for Datatype.UDim2.X" / "...Y" -- é o MESMO UDim, não uma
	  cópia com semântica diferente. Como UDim é imutável e cada leitura de `.X`/`.Width`
	  constrói um `UDim` NOVO a partir dos mesmos componentes já quantizados, a igualdade de VALOR
	  entre `.X` e `.Width` está garantida -- identidade de referência não é observável nem
	  relevante pra um value type imutável).
	- Método: `Lerp(goal: UDim2, alpha: number): UDim2`.
	- Operadores CONFIRMADOS: `+` e `-` (binários) -- somam/subtraem X com X e Y com Y
	  (componente a componente, como dois UDim sendo somados/subtraídos).

	## P9 -- Unário `-` e `==` NÃO confirmados (mesma pendência de types/UDim.luau, ver lá o
	## raciocínio completo). `Equals`/`Unm` implementados aqui com a MESMA hipótese conservadora:
	## igualdade componente a componente nos 4 campos, `Unm` negando os 4. Documentado, não
	## silencioso.

	Depende de: Float32, Userdata, types/UDim. Usado por: init.luau (task-valuetypes-007, futura).
]]

local Float32 = require("../Float32")
local Userdata = require("../Userdata")
local UDim = require("./UDim")

export type UDim2 = typeof(setmetatable(
	{} :: {
		X: UDim.UDim,
		Y: UDim.UDim,
		Width: UDim.UDim,
		Height: UDim.UDim,
		Lerp: (self: UDim2, goal: UDim2, alpha: number) -> UDim2,
	},
	{} :: {
		__add: (UDim2, UDim2) -> UDim2,
		__sub: (UDim2, UDim2) -> UDim2,
		__unm: (UDim2) -> UDim2,
		__tostring: (UDim2) -> string,
	}
))

-- Tipo INTERSECÇÃO representando os dois overloads reais de `UDim2.new` (ver cabeçalho). Padrão
-- nativo do Luau pra expor overload de função sem duplicar o nome.
export type UDim2NewOverload = ((number?, number?, number?, number?) -> UDim2) & ((UDim.UDim, UDim.UDim) -> UDim2)

local UDim2Module = {}

-- Forward declaration -- mesmo padrão de types/Color3.luau / types/UDim.luau.
local Factory: Userdata.Factory

local function fields(xScale: number, xOffset: number, yScale: number, yOffset: number): Userdata.Fields
	return {
		Float32.Quantize(xScale),
		Float32.QuantizeInt32(xOffset),
		Float32.Quantize(yScale),
		Float32.QuantizeInt32(yOffset),
	}
end

local function fromFields(xScale: number, xOffset: number, yScale: number, yOffset: number): UDim2
	return Factory(fields(xScale, xOffset, yScale, yOffset)) :: UDim2
end

-- Valida um argumento posicional opcional da forma numérica: `nil` é aceito (vira o default 0 no
-- chamador), qualquer coisa que não seja `number` erra citando o nome do argumento e o tipo real
-- recebido -- mesmo vocabulário de erro que `Userdata.Unwrap` já usa pro resto do território.
local function toOptionalNumber(value: unknown, argName: string): number?
	if value == nil then
		return nil
	end
	if typeof(value) == "number" then
		return value :: number
	end
	error(`invalid argument '{argName}' to 'UDim2.new' (number expected, got {typeof(value)})`, 4)
end

-- Implementação ÚNICA que despacha pelos dois overloads reais (ver cabeçalho). `...: unknown` --
-- sem `any` -- é o único jeito de aceitar assinaturas de aridade/tipo diferentes numa função Luau
-- concreta; o tipo público exposto (`UDim2NewOverload`, intersecção) é aplicado num ÚNICO cast na
-- atribuição final de `UDim2Module.new`, abaixo.
local function newRaw(...: unknown): UDim2
	local argCount = select("#", ...)

	if argCount >= 1 then
		local first: unknown = select(1, ...)
		if Userdata.TypeNameOf(first) == "UDim" then
			if argCount ~= 2 then
				error(`UDim2.new: overload (UDim, UDim) espera exatamente 2 argumentos, recebeu {argCount}`, 3)
			end
			local second: unknown = select(2, ...)
			local secondTypeName = Userdata.TypeNameOf(second)
			if secondTypeName ~= "UDim" then
				error(`invalid argument #2 to 'new' (UDim expected, got {secondTypeName or typeof(second)})`, 3)
			end
			local xFields = Userdata.Unwrap(first, "UDim")
			local yFields = Userdata.Unwrap(second, "UDim")
			return fromFields(xFields[1] :: number, xFields[2] :: number, yFields[1] :: number, yFields[2] :: number)
		end
	end

	local xScale = toOptionalNumber(select(1, ...), "xScale")
	local xOffset = toOptionalNumber(select(2, ...), "xOffset")
	local yScale = toOptionalNumber(select(3, ...), "yScale")
	local yOffset = toOptionalNumber(select(4, ...), "yOffset")

	return fromFields(xScale or 0, xOffset or 0, yScale or 0, yOffset or 0)
end

UDim2Module.new = newRaw :: UDim2NewOverload

UDim2Module.fromScale = function(xScale: number?, yScale: number?): UDim2
	return fromFields(xScale or 0, 0, yScale or 0, 0)
end

UDim2Module.fromOffset = function(xOffset: number?, yOffset: number?): UDim2
	return fromFields(0, xOffset or 0, 0, yOffset or 0)
end

local methods: { [string]: unknown } = {
	Lerp = function(self: unknown, other: unknown, alpha: number): unknown
		local a = Userdata.Unwrap(self, "UDim2")
		local b = Userdata.Unwrap(other, "UDim2")
		local axs, axo, ays, ayo = a[1] :: number, a[2] :: number, a[3] :: number, a[4] :: number
		local bxs, bxo, bys, byo = b[1] :: number, b[2] :: number, b[3] :: number, b[4] :: number
		return fromFields(
			axs + (bxs - axs) * alpha,
			axo + (bxo - axo) * alpha,
			ays + (bys - ays) * alpha,
			ayo + (byo - ayo) * alpha
		)
	end,
}
table.freeze(methods)

Factory = Userdata.Define({
	TypeName = "UDim2",
	Methods = methods,
	GetProperty = function(f: Userdata.Fields, key: string): (unknown, boolean)
		-- Width/Height são sinônimos EXATOS de X/Y (ver cabeçalho) -- mesmos componentes, UDim
		-- NOVO construído a cada leitura (imutabilidade não distingue "a mesma referência" de
		-- "uma cópia com o mesmo valor").
		if key == "X" or key == "Width" then
			return UDim.new(f[1] :: number, f[2] :: number), true
		elseif key == "Y" or key == "Height" then
			return UDim.new(f[3] :: number, f[4] :: number), true
		end
		return nil, false
	end,
	-- Confirmado por citação literal da pesquisa: "{xScale, xOffset}, {yScale, yOffset}", ex.
	-- `print(guiObject.Size) --> {0, 300}, {1, 0}`.
	Format = function(f: Userdata.Fields): string
		return string.format(
			"{%s, %d}, {%s, %d}",
			Float32.Format(f[1] :: number),
			f[2] :: number,
			Float32.Format(f[3] :: number),
			f[4] :: number
		)
	end,
	Add = function(a: Userdata.Fields, b: Userdata.Fields, bTypeName: string): unknown
		if bTypeName ~= "UDim2" then
			error(`cannot add UDim2 and {bTypeName}`, 3)
		end
		return fromFields(
			(a[1] :: number) + (b[1] :: number),
			(a[2] :: number) + (b[2] :: number),
			(a[3] :: number) + (b[3] :: number),
			(a[4] :: number) + (b[4] :: number)
		)
	end,
	Sub = function(a: Userdata.Fields, b: Userdata.Fields, bTypeName: string): unknown
		if bTypeName ~= "UDim2" then
			error(`cannot subtract UDim2 and {bTypeName}`, 3)
		end
		return fromFields(
			(a[1] :: number) - (b[1] :: number),
			(a[2] :: number) - (b[2] :: number),
			(a[3] :: number) - (b[3] :: number),
			(a[4] :: number) - (b[4] :: number)
		)
	end,
	-- P9 (ver cabeçalho): NÃO confirmado por fonte primária -- hipótese conservadora, negando os
	-- 4 componentes.
	Unm = function(a: Userdata.Fields): unknown
		return fromFields(-(a[1] :: number), -(a[2] :: number), -(a[3] :: number), -(a[4] :: number))
	end,
	-- P9 (ver cabeçalho): igualdade por valor componente a componente -- convenção do resto da
	-- família, NÃO citação direta confirmando `==` pra UDim2 especificamente.
	Equals = function(a: Userdata.Fields, b: Userdata.Fields): boolean
		return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
	end,
})

return UDim2Module
