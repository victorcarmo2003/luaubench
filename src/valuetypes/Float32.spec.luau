--!strict

--[[
	Teste da task-valuetypes-001 (Float32.luau). Cobre, na mesma tarefa da lógica que testa
	(regra 01):

	1. Paridade bit a bit de `Float32.Quantize` com o oráculo `vector.create(x, 0, 0).x` da
	   biblioteca nativa `vector` do Luau, em mais de 8 valores (incluindo nan/inf/-inf à
	   parte, já que `==` nunca bate para NaN).
	2. `Float32.Format` reproduzindo os quatro casos do oráculo da task: 0.1, -0.7, 1/3,
	   123456.789.
	3. `Float32.FormatSpecial`/`Format` para nan/inf/-inf (pendência P3, aproximação de
	   boa-fé documentada no cabeçalho de Float32.luau).
	4. `Float32.QuantizeInt32`/`QuantizeInt16` arredondando half-away-from-zero e saturando
	   nos limites de int32/int16.
	5. Reuso do buffer module-local de 4 bytes não vaza estado entre chamadas intercaladas.

	Roda com `lune run src/valuetypes/Float32.spec.luau`.
]]

local process = require("@lune/process")
local Float32 = require("./Float32")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

test("Quantize bate bit a bit com vector.create nativo em pelo menos 8 valores", function()
	local values: { number } = {
		0.1,
		-0.7,
		1 / 3,
		123456.789,
		0,
		1,
		-0.1,
		100,
		2 ^ 30,
		1e30,
		-1e30,
		math.pi,
	}

	assert(#values >= 8, "a lista de valores do oráculo precisa ter pelo menos 8 entradas")

	for _, value in values do
		local ours = Float32.Quantize(value)
		local native = (vector.create(value, 0, 0) :: vector).x
		assert(
			ours == native,
			`Quantize({value}) = {ours}, mas vector.create({value},0,0).x = {native} -- deveriam bater bit a bit`
		)
	end
end)

test("Quantize preserva nan/inf/-inf igual ao oráculo vector nativo", function()
	local nan = 0 / 0
	local inf = math.huge
	local ninf = -math.huge

	local quantizedNan = Float32.Quantize(nan)
	assert(quantizedNan ~= quantizedNan, "Quantize(nan) deveria continuar sendo NaN (NaN nunca é igual a si mesmo)")

	local nativeNan = (vector.create(nan, 0, 0) :: vector).x
	assert(nativeNan ~= nativeNan, "sanity check: o oráculo vector nativo também deveria devolver NaN")

	assert(Float32.Quantize(inf) == (vector.create(inf, 0, 0) :: vector).x, "Quantize(inf) deveria bater com o oráculo")
	assert(
		Float32.Quantize(ninf) == (vector.create(ninf, 0, 0) :: vector).x,
		"Quantize(-inf) deveria bater com o oráculo"
	)
end)

test("Quantize é idempotente e o buffer module-local não vaza estado entre chamadas intercaladas", function()
	local a = Float32.Quantize(0.1)
	local b = Float32.Quantize(100)
	local c = Float32.Quantize(0.1)
	local d = Float32.Quantize(-1e30)
	local e = Float32.Quantize(100)

	assert(a == c, "duas quantizações do mesmo valor, intercaladas por outra chamada, deveriam bater")
	assert(b == e, "duas quantizações do mesmo valor, intercaladas por outra chamada, deveriam bater")
	assert(Float32.Quantize(a) == a, "quantizar um valor já quantizado deveria ser um no-op")
	assert(Float32.Quantize(d) == d, "quantizar um valor já quantizado deveria ser um no-op")
end)

test("Format reproduz os quatro casos do oráculo da task (0.1 / -0.7 / 0.33333334 / 123456.79)", function()
	assert(Float32.Format(0.1) == "0.1", `esperava "0.1", recebeu "{Float32.Format(0.1)}"`)
	assert(Float32.Format(-0.7) == "-0.7", `esperava "-0.7", recebeu "{Float32.Format(-0.7)}"`)
	assert(Float32.Format(1 / 3) == "0.33333334", `esperava "0.33333334", recebeu "{Float32.Format(1 / 3)}"`)
	assert(
		Float32.Format(123456.789) == "123456.79",
		`esperava "123456.79", recebeu "{Float32.Format(123456.789)}"`
	)
end)

test("Format evita notação científica espúria em números redondos (achado desta tarefa, ver comentário em Float32.luau)", function()
	assert(Float32.Format(100) == "100", `esperava "100", recebeu "{Float32.Format(100)}"`)
	assert(Float32.Format(-100) == "-100", `esperava "-100", recebeu "{Float32.Format(-100)}"`)
	assert(Float32.Format(1000000) == "1000000", `esperava "1000000", recebeu "{Float32.Format(1000000)}"`)
	assert(Float32.Format(0) == "0", `esperava "0", recebeu "{Float32.Format(0)}"`)
end)

test("Format acima de 2^24 nunca inventa dígitos (task-valuetypes-001-fix, achado MÉDIO do revisor)", function()
	-- Estes quatro valores produziam saída NUMERICAMENTE ERRADA antes da correção (o
	-- widening tratava dígitos reais da aproximação double do float32 como se fossem
	-- zeros à direita). A guarda `INTEGER_EXACT_LIMIT` corta o widening para
	-- |quantized| >= 2^24 -- o critério de aceite é round-trip correto e ausência de
	-- dígitos fabricados, não uma string fixa (a representação pode ser notação
	-- científica, que é honesta, ao contrário do bug original).
	local problematicValues: { number } = { 1e11, 1e14, 999999999999999, 1e17 }

	for _, value in problematicValues do
		local quantized = Float32.Quantize(value)
		local formatted = Float32.Format(value)

		-- Round-trip: reconverter o texto formatado e requantizar tem que bater com o
		-- valor quantizado original -- essa propriedade nunca quebrou (nem no bug
		-- original), mas continua sendo o critério mínimo de correção numérica.
		local roundTripped = tonumber(formatted)
		assert(roundTripped ~= nil, `Format({value}) = "{formatted}" não é convertível de volta por tonumber()`)
		assert(
			Float32.Quantize(roundTripped :: number) == quantized,
			`Format({value}) = "{formatted}" não sobrevive ao round-trip (esperava requantizar para {quantized})`
		)

		-- Nunca fabricar dígitos: se a saída não usa notação científica, ela tem que ser
		-- exatamente `quantized` formatado por %.17g (a representação double completa,
		-- sem nenhum dígito "editado" pelo widening) -- ou seja, ou é notação científica
		-- honesta, ou é o valor exato, nunca um meio-termo com dígitos trocados.
		if not string.find(formatted, "[eE]") then
			local exact = string.format("%.17g", quantized)
			local exactAsNumber = tonumber(exact)
			assert(exactAsNumber ~= nil and (exactAsNumber :: number) == quantized, "sanity check do formatador %.17g falhou")
			assert(
				tonumber(formatted) == quantized,
				`Format({value}) = "{formatted}" em notação fixa não bate com o valor quantizado exato {quantized} -- dígito fabricado`
			)
		end
	end
end)

test("Format delega nan/inf/-inf para FormatSpecial (pendência P3)", function()
	assert(Float32.Format(0 / 0) == "nan", `esperava "nan", recebeu "{Float32.Format(0 / 0)}"`)
	assert(Float32.Format(math.huge) == "inf", `esperava "inf", recebeu "{Float32.Format(math.huge)}"`)
	assert(Float32.Format(-math.huge) == "-inf", `esperava "-inf", recebeu "{Float32.Format(-math.huge)}"`)

	assert(Float32.FormatSpecial(0 / 0) == "nan", "FormatSpecial(nan) deveria devolver \"nan\"")
	assert(Float32.FormatSpecial(math.huge) == "inf", "FormatSpecial(inf) deveria devolver \"inf\"")
	assert(Float32.FormatSpecial(-math.huge) == "-inf", "FormatSpecial(-inf) deveria devolver \"-inf\"")
	assert(Float32.FormatSpecial(0.1) == nil, "FormatSpecial de um número finito comum deveria devolver nil")
end)

test("QuantizeInt32 arredonda half-away-from-zero", function()
	assert(Float32.QuantizeInt32(2.5) == 3, `esperava 3, recebeu {Float32.QuantizeInt32(2.5)}`)
	assert(Float32.QuantizeInt32(-2.5) == -3, `esperava -3, recebeu {Float32.QuantizeInt32(-2.5)}`)
	assert(Float32.QuantizeInt32(0.5) == 1, `esperava 1, recebeu {Float32.QuantizeInt32(0.5)}`)
	assert(Float32.QuantizeInt32(-0.5) == -1, `esperava -1, recebeu {Float32.QuantizeInt32(-0.5)}`)
	assert(Float32.QuantizeInt32(2.4) == 2, `esperava 2, recebeu {Float32.QuantizeInt32(2.4)}`)
	assert(Float32.QuantizeInt32(-2.4) == -2, `esperava -2, recebeu {Float32.QuantizeInt32(-2.4)}`)
	assert(Float32.QuantizeInt32(0) == 0, `esperava 0, recebeu {Float32.QuantizeInt32(0)}`)
end)

test("QuantizeInt32 satura em [-2^31, 2^31 - 1]", function()
	assert(Float32.QuantizeInt32(2147483647) == 2147483647, "valor exatamente no limite superior não deveria mudar")
	assert(Float32.QuantizeInt32(-2147483648) == -2147483648, "valor exatamente no limite inferior não deveria mudar")
	assert(
		Float32.QuantizeInt32(2147483648) == 2147483647,
		"um a mais que o limite superior deveria saturar em INT32_MAX"
	)
	assert(
		Float32.QuantizeInt32(-2147483649) == -2147483648,
		"um a menos que o limite inferior deveria saturar em INT32_MIN"
	)
	assert(Float32.QuantizeInt32(1e15) == 2147483647, "valor muito acima do limite deveria saturar em INT32_MAX")
	assert(Float32.QuantizeInt32(-1e15) == -2147483648, "valor muito abaixo do limite deveria saturar em INT32_MIN")
end)

test("QuantizeInt16 arredonda half-away-from-zero e satura em [-32768, 32767]", function()
	assert(Float32.QuantizeInt16(2.5) == 3, `esperava 3, recebeu {Float32.QuantizeInt16(2.5)}`)
	assert(Float32.QuantizeInt16(-2.5) == -3, `esperava -3, recebeu {Float32.QuantizeInt16(-2.5)}`)
	assert(Float32.QuantizeInt16(32767) == 32767, "valor exatamente no limite superior não deveria mudar")
	assert(Float32.QuantizeInt16(-32768) == -32768, "valor exatamente no limite inferior não deveria mudar")
	assert(Float32.QuantizeInt16(32768) == 32767, "um a mais que o limite superior deveria saturar")
	assert(Float32.QuantizeInt16(-32769) == -32768, "um a menos que o limite inferior deveria saturar")
	assert(Float32.QuantizeInt16(1e9) == 32767, "valor muito acima do limite deveria saturar em INT16_MAX")
	assert(Float32.QuantizeInt16(-1e9) == -32768, "valor muito abaixo do limite deveria saturar em INT16_MIN")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
