--!strict

--[[
	Quantização e formatação numérica dos value types do Roblox (task-valuetypes-001).

	Responsabilidade: fazer um `number` do Luau (double de 64 bits) se comportar como o
	`float`/`int32`/`int16` que o Roblox guarda de verdade em `Vector3`, `CFrame`, `Color3`,
	`UDim`/`UDim2`, etc. Todo tipo em `src/valuetypes/types/*` quantiza os componentes no seu
	construtor privado único -- como todo resultado de operador passa por esse mesmo
	construtor, a aritmética inteira fica encadeada em float32 automaticamente, igual ao
	Roblox (ver `.claude/agents-memory/arquiteto-valuetypes-2026-09-05.md`, seção 5).

	Depende de: nada. Módulo-folha do território `valuetypes` (fábrica de userdata em
	`Userdata.luau` depende deste módulo, não o contrário).

	## Fatos empíricos usados aqui (seção 0 do desenho, reproduzidos e reconferidos nesta
	## tarefa com `lune run` sobre um script descartável de scratchpad)

	- `buffer.writef32`/`readf32` dá float32 exato: uma ida-e-volta de 4 bytes bate BIT A BIT
	  (comparado por `==` de double, que é exato para valores float32-representáveis) com
	  `vector.create(x, 0, 0).x` da biblioteca nativa `vector` do Luau -- confirmado de novo
	  nesta tarefa para 0.1, -0.7, 1/3, 123456.789, 0, -0, 1, 2^30, 1e30, -1e30, math.pi, nan,
	  inf, -inf.
	- O algoritmo "shortest round-trip" (tentar `%.1g`..`%.9g`, devolver o primeiro cujo
	  `tonumber()` re-quantizado bate) reproduz os quatro casos do oráculo desta tarefa:
	  `Format(0.1) == "0.1"`, `Format(-0.7) == "-0.7"`, `Format(1/3) == "0.33333334"`,
	  `Format(123456.789) == "123456.79"`.
]]

-- Buffer de 4 bytes MODULE-LOCAL e reusado por toda quantização -- nunca alocado por
-- chamada (regra 01, seção Performance: evitar alocação por operação em caminho quente).
local quantizeBuffer = buffer.create(4)

local INT32_MIN = -2147483648
local INT32_MAX = 2147483647
local INT16_MIN = -32768
local INT16_MAX = 32767

-- Acima de quantos dígitos de magnitude a formatação de números "redondos" grandes
-- (ex.: 1e18) deixa de tentar evitar notação científica -- ver comentário em `Format`
-- logo abaixo do loop de dígitos significativos. Heurística própria desta tarefa (não
-- confirmada contra o Roblox real), documentada porque `Float32.Format` é aproximação de
-- boa-fé (pendência P2, seção 9 do desenho arquitetural).
local MAX_FIXED_NOTATION_MAGNITUDE = 18

export type Formatter = (value: number) -> string

local Float32 = {}

-- Quantiza `value` para a precisão de um float32 IEEE-754, via
-- `buffer.writef32`/`buffer.readf32` (ida-e-volta de 4 bytes). Verificado bit a bit contra
-- `vector.create(x, 0, 0).x` -- ver cabeçalho.
function Float32.Quantize(value: number): number
	buffer.writef32(quantizeBuffer, 0, value)
	return buffer.readf32(quantizeBuffer, 0)
end

-- Arredondamento "half away from zero" (2.5 -> 3, -2.5 -> -3), como o Roblox usa para
-- propriedades int32/int16 (ex.: `UDim.Offset`). `math.floor`/`math.ceil` puros -- sem
-- depender de `math.round` (que no Luau arredonda half-away-from-zero também, mas a forma
-- explícita deixa a semântica auditável sem depender de outra função embutida).
local function roundHalfAwayFromZero(value: number): number
	if value >= 0 then
		return math.floor(value + 0.5)
	end
	return math.ceil(value - 0.5)
end

-- Arredonda para o inteiro mais próximo (half away from zero) e satura em
-- [-2^31, 2^31 - 1]. Usado por `UDim.Offset` e pelos offsets de `UDim2`.
--
-- NaN não tem representação int32 sensata e o Roblox real não foi pesquisado para este
-- caso (fora do escopo desta tarefa) -- devolver 0 em vez de propagar NaN para um campo
-- que o resto do território assume ser sempre um inteiro finito é uma escolha defensiva
-- desta implementação, não um fato confirmado sobre o Roblox. Documentado aqui para não
-- ser um silêncio (regra 00).
function Float32.QuantizeInt32(value: number): number
	if value ~= value then
		return 0
	end
	local rounded = roundHalfAwayFromZero(value)
	if rounded > INT32_MAX then
		return INT32_MAX
	elseif rounded < INT32_MIN then
		return INT32_MIN
	end
	return rounded
end

-- Idem, em [-32768, 32767]. Usado por `Vector3int16`/`Vector2int16`/`Region3int16` (leva 2,
-- fora do escopo desta tarefa -- implementado aqui porque `Float32.luau` é a base
-- compartilhada e a task explicitamente pede as três funções de quantização).
function Float32.QuantizeInt16(value: number): number
	if value ~= value then
		return 0
	end
	local rounded = roundHalfAwayFromZero(value)
	if rounded > INT16_MAX then
		return INT16_MAX
	elseif rounded < INT16_MIN then
		return INT16_MIN
	end
	return rounded
end

-- PENDÊNCIA DE PESQUISA P3 (seção 9 do desenho arquitetural): a grafia exata que o Roblox
-- usa no `tostring` de `nan`/`inf`/`-inf` dentro de um value type (`Vector3`, `CFrame`, ...)
-- não foi confirmada contra doc oficial nem contra o Roblox real. As strings abaixo são a
-- aproximação de boa-fé mais conservadora disponível: reproduzem exatamente o que o
-- `tostring()` NATIVO do Luau/Lune devolve para esses valores (verificado nesta tarefa:
-- `tostring(0/0) == "nan"`, `tostring(math.huge) == "inf"`, `tostring(-math.huge) ==
-- "-inf"`) -- não o que `print()` mostra internamente no Lune, que usa um formatador
-- diferente e imprime "NaN" capitalizado (observado, mas descartado por não ser o
-- `tostring` da linguagem). Reavaliar quando P3 for pesquisada.
function Float32.FormatSpecial(value: number): string?
	if value ~= value then
		return "nan"
	end
	if value == math.huge then
		return "inf"
	end
	if value == -math.huge then
		return "-inf"
	end
	return nil
end

-- Formata `value` como o Roblox formataria um componente float32 dentro do `tostring` de um
-- value type: menor quantidade de dígitos significativos (`%.1g` .. `%.9g`) cujo
-- `tonumber()` re-quantizado bate de novo com o valor quantizado original (algoritmo
-- "shortest round-trip", seção 0.5 do desenho).
--
-- PENDÊNCIA DE PESQUISA P2 (seção 9, parcial): o formato "X, Y, Z" (vírgula-espaço, sem
-- parênteses) está confirmado; a contagem exata de dígitos significativos que o Roblox usa
-- tem só um exemplo de fórum como fonte, não uma spec. Os quatro casos do oráculo desta
-- tarefa (0.1, -0.7, 1/3, 123456.789) batem com este algoritmo -- é uma aproximação de
-- boa-fé, não uma implementação confirmada byte a byte.
function Float32.Format(value: number): string
	local special = Float32.FormatSpecial(value)
	if special ~= nil then
		return special
	end

	local quantized = Float32.Quantize(value)

	local significantDigits = 9
	local formatted = string.format("%.9g", quantized)
	for precision = 1, 9 do
		local candidate = string.format(`%.{precision}g`, quantized)
		local roundTripped = tonumber(candidate)
		if roundTripped ~= nil and Float32.Quantize(roundTripped) == quantized then
			significantDigits = precision
			formatted = candidate
			break
		end
	end

	-- Achado empírico desta tarefa, fora do que a seção 0.5 original testou: `%g` troca
	-- para notação científica sempre que o expoente decimal >= precisão pedida. Isso faz um
	-- valor "redondo" como 100 (cujo round-trip já bate com 1 dígito significativo) imprimir
	-- "1e+02" em vez de "100" -- e "100, 0, 0" é o formato bem conhecido que o Roblox usa
	-- para `Vector3.new(100, 0, 0)`. Corrigido pedindo dígitos suficientes para cobrir a
	-- parte inteira sem notação científica, SEM mudar a quantidade de dígitos
	-- SIGNIFICATIVOS já encontrada -- matematicamente, se o valor já bate com menos dígitos
	-- do que os necessários para representar a parte inteira, os dígitos extras revelados só
	-- podem ser zeros (senão o round-trip de menor precisão não teria batido). Cap em
	-- MAX_FIXED_NOTATION_MAGNITUDE: acima disso, mantém notação científica -- não pesquisado
	-- onde exatamente o Roblox faria essa troca (P2), então não se estica a heurística além
	-- do que dá pra defender.
	local exponentText = string.match(formatted, "e([%+%-]?%d+)$")
	if exponentText ~= nil then
		local exponent = tonumber(exponentText) :: number
		local magnitude = exponent + 1
		if magnitude > significantDigits and magnitude <= MAX_FIXED_NOTATION_MAGNITUDE then
			local widened = string.format(`%.{magnitude}g`, quantized)
			if not string.find(widened, "[eE]") then
				formatted = widened
			end
		end
	end

	return formatted
end

return Float32
