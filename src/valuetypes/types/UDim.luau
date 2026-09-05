--!strict

--[[
	UDim -- par (Scale, Offset) imutável usado por UI (task-valuetypes-005). Fonte:
	`.claude/agents-memory/pesquisa-datatypes-color-udim-enum-2026-09-05.md`, seção B) UDim e
	UDim2 -- leitura obrigatória já feita antes de escrever este módulo.

	## Superfície confirmada

	- Construtor: `UDim.new(scale?: number, offset?: number)` -- ambos default 0. A doc oficial
	  afirma explicitamente que `UDim.new()` sem argumentos == `UDim.new(0, 0)` (citação literal
	  no relatório de pesquisa).
	- Propriedades: `Scale: number` (float32), `Offset: number` (a doc diz "Stored as an
	  integer" -- por isso quantizado como int32, não float32). Ambas read-only (garantido pela
	  fábrica via `__newindex`).
	- Operadores CONFIRMADOS: `+` e `-` (binários) -- somam/subtraem Scale com Scale e Offset com
	  Offset, independentemente um do outro.

	## P9 -- Unário `-` e `==` NÃO confirmados (seção 9 do desenho arquitetural, pendência aberta)

	A seção `math_operations` da doc oficial só lista `+`/`-` binários para UDim -- MAS essa mesma
	seção do YAML comprovadamente OMITE unário `-` e `==` até para `Vector3`, que sabidamente
	suporta os dois no Roblox real (pesquisa, seção "Incerto", item 3: "a ausência não prova
	ausência real no motor"). Portanto:

	- `Equals` é campo OBRIGATÓRIO de todo `Userdata.Descriptor` (toda instância desta fábrica
	  SEMPRE tem `==` -- ver `Userdata.luau`) -- implementado aqui como igualdade por valor
	  componente a componente, a mesma convenção usada por TODO o resto da família de datatypes de
	  valor do Roblox. Isso é a hipótese mais conservadora disponível, **NÃO uma citação direta
	  confirmando `==` para UDim especificamente** -- marcado aqui como aproximação de boa-fé.
	- `Unm` (unário `-`) é OPCIONAL no Descriptor e é implementado aqui negando os dois
	  componentes (Scale e Offset) -- também NÃO CONFIRMADO por nenhuma fonte primária, mesma
	  pendência P9. Documentado explicitamente para não ser um silêncio (regra 00).

	Depende de: Float32, Userdata. Usado por: types/UDim2.luau, init.luau (task-valuetypes-007,
	futura).
]]

local Float32 = require("../Float32")
local Userdata = require("../Userdata")

export type UDim = typeof(setmetatable(
	{} :: {
		Scale: number,
		Offset: number,
	},
	{} :: {
		__add: (UDim, UDim) -> UDim,
		__sub: (UDim, UDim) -> UDim,
		__unm: (UDim) -> UDim,
		__tostring: (UDim) -> string,
	}
))

local UDimModule = {}

-- Forward declaration -- ver o mesmo padrão em types/Color3.luau / Userdata.spec.luau.
local Factory: Userdata.Factory

local function fields(scale: number, offset: number): Userdata.Fields
	return {
		Float32.Quantize(scale),
		Float32.QuantizeInt32(offset),
	}
end

local function fromFields(scale: number, offset: number): UDim
	return Factory(fields(scale, offset)) :: UDim
end

UDimModule.new = function(scale: number?, offset: number?): UDim
	return fromFields(scale or 0, offset or 0)
end

local methods: { [string]: unknown } = table.freeze({}) :: { [string]: unknown }

Factory = Userdata.Define({
	TypeName = "UDim",
	Methods = methods,
	GetProperty = function(f: Userdata.Fields, key: string): (unknown, boolean)
		if key == "Scale" then
			return f[1], true
		elseif key == "Offset" then
			return f[2], true
		end
		return nil, false
	end,
	-- PENDÊNCIA P2 (seção 9 do desenho): não há exemplo literal isolado de `print(UDim.new(...))`
	-- nas fontes da pesquisa -- inferido pelo padrão confirmado de UDim2 ("{Scale, Offset}", ex.
	-- "{0.5, 10}"). Offset é formatado como INTEIRO (nunca via Float32.Format, que é pra float32).
	Format = function(f: Userdata.Fields): string
		return string.format("{%s, %d}", Float32.Format(f[1] :: number), f[2] :: number)
	end,
	Add = function(a: Userdata.Fields, b: Userdata.Fields, bTypeName: string): unknown
		if bTypeName ~= "UDim" then
			error(`cannot add UDim and {bTypeName}`, 3)
		end
		return fromFields((a[1] :: number) + (b[1] :: number), (a[2] :: number) + (b[2] :: number))
	end,
	Sub = function(a: Userdata.Fields, b: Userdata.Fields, bTypeName: string): unknown
		if bTypeName ~= "UDim" then
			error(`cannot subtract UDim and {bTypeName}`, 3)
		end
		return fromFields((a[1] :: number) - (b[1] :: number), (a[2] :: number) - (b[2] :: number))
	end,
	-- P9 (ver cabeçalho): NÃO confirmado por fonte primária -- implementado como hipótese
	-- conservadora (negar os dois componentes).
	Unm = function(a: Userdata.Fields): unknown
		return fromFields(-(a[1] :: number), -(a[2] :: number))
	end,
	-- P9 (ver cabeçalho): igualdade por valor componente a componente -- convenção do resto da
	-- família de datatypes, NÃO citação direta confirmando `==` pra UDim especificamente.
	Equals = function(a: Userdata.Fields, b: Userdata.Fields): boolean
		return a[1] == b[1] and a[2] == b[2]
	end,
})

return UDimModule
