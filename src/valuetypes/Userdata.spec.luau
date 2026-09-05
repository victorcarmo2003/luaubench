--!strict

--[[
	Teste da task-valuetypes-002 (Userdata.luau -- fábrica única de userdata imutável). Cobre as
	QUATRO invariantes obrigatórias da fábrica (ver cabeçalho de Userdata.luau) mais o resto da
	superfície pública (Define/TypeNameOf/Unwrap) e das guardas defensivas.

	Fixtures deste arquivo (nunca reaproveitadas fora dele): dois tipos de teste registrados via
	`Userdata.Define` só pra exercitar a fábrica de forma genérica --
	 - `SpecPoint`: tem TODOS os operadores opcionais (Add/Sub/Mul/Div/IDiv/Unm), imita o formato
	   real de um Vector-like (`Fields = { x: number }`).
	 - `SpecColor`: NÃO tem NENHUM operador aritmético (todos `nil`), imita `Color3`
	   (`math_operations: []` confirmado por pesquisa) -- usado pra provar que o Luau nativo erra
	   sozinho quando o Descriptor não instala o metamétodo.

	SEM `any` em lugar nenhum (regra 01) -- `SpecPoint`/`SpecColor` são tipos NOMINAIS OPACOS
	(`typeof(setmetatable(...))`), a mesma técnica que `.claude/agents-memory/arquiteto-
	valuetypes-2026-09-05.md` (seção 3.1, "Nota de tipagem") prescreve pra `init.luau` expor
	`Vector3`/`CFrame`/etc. de verdade -- aplicada aqui aos fixtures de teste. Onde um cenário
	precisa contornar de propósito uma restrição ESTÁTICA que o Luau real também imporia (ex.:
	somar dois tipos sem operador em comum, ou invocar um operador que o tipo não declara), o
	valor é estreitado (nunca `any`) pra um tipo sintético local que só existe pra emprestar a
	assinatura de operador necessária -- mesmo espírito do cast de função cru já usado em
	`runtime/Instance.spec.luau` (`UnaryRawFn`/`BinaryRawFn`: casta a FUNÇÃO builtin pra aceitar
	`unknown`), generalizado aqui de "função" pra "operando de operador". O comportamento
	exercitado nesses casos é 100% do despacho real instalado por `Userdata.Define` -- os tipos
	sintéticos não mudam nada em runtime, só o que o type-checker aceita ver.

	Roda com `lune run src/valuetypes/Userdata.spec.luau`.

	NOTA DE TOOLING: `luau-lsp analyze --platform=standard` reporta "Unknown global
	'collectgarbage'" nas duas chamadas do teste de vazamento (invariante 3) -- ver o comentário
	local naquele teste pro porquê (gap real de banco de tipos, não bug de --!strict: o Roblox
	real não expõe `collectgarbage`, e `--platform=standard` espelha o namespace do Roblox; o
	global É real neste Lune, só ausente do banco de tipos de análise). Resto do arquivo tipa
	limpo (confirmado nesta tarefa com `luau-lsp analyze --platform=standard --settings=.luaurc`).
]]

local process = require("@lune/process")
local Userdata = require("./Userdata")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

-- ================================================================================================
-- Tipos nominais opacos dos fixtures (ver cabeçalho) -- SEM relação estrutural com Userdata.Fields
-- por design: são só a "vitrine" tipada que um script/teste usa pra chamar `.X`/`:Double()`/`+`
-- com sintaxe normal, exatamente como `types/Vector3.luau` (task futura) vai expor `Vector3`.
-- ================================================================================================

type SpecPoint = typeof(setmetatable(
	{} :: {
		X: number,
		Double: (self: SpecPoint) -> SpecPoint,
	},
	{} :: {
		__add: (SpecPoint, SpecPoint) -> SpecPoint,
		__sub: (SpecPoint, SpecPoint) -> SpecPoint,
		__mul: (SpecPoint, number) -> SpecPoint,
		__div: (SpecPoint, number) -> SpecPoint,
		__idiv: (SpecPoint, number) -> SpecPoint,
		__unm: (SpecPoint) -> SpecPoint,
		__tostring: (SpecPoint) -> string,
	}
))

-- SpecColor NÃO declara NENHUM metamétodo aritmético -- imita Color3 (math_operations: []).
type SpecColor = typeof(setmetatable(
	{} :: { R: number },
	{} :: { __tostring: (SpecColor) -> string }
))

-- Tipos SINTÉTICOS usados só pra contornar restrições estáticas em cenários de teste que o
-- Luau real também rejeitaria ao compilar (ver cabeçalho do arquivo). Nunca alteram o valor em
-- runtime -- só a "lente" com que o type-checker o vê.
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

type UnaryOperableProbe = typeof(setmetatable({} :: {}, {} :: { __unm: (UnaryOperableProbe) -> UnaryOperableProbe }))
local function asUnaryOperable(value: unknown): UnaryOperableProbe
	return value :: UnaryOperableProbe
end

type MulOperableProbe = typeof(setmetatable({} :: {}, {} :: { __mul: (MulOperableProbe, number) -> MulOperableProbe }))
local function asMulOperable(value: unknown): MulOperableProbe
	return value :: MulOperableProbe
end

-- Mesmo precedente de runtime/Instance.spec.luau: casta a FUNÇÃO builtin `setmetatable` pra
-- aceitar `unknown` nos dois argumentos, evitando "setmetatable should take a table" (o
-- checker sabe que SpecPoint não é uma tabela comum -- é exatamente isso que Userdata.luau
-- garante em runtime, e o que este teste confirma).
type BinaryRawFn = (unknown, unknown) -> unknown
local setmetatableUnknown: BinaryRawFn = (setmetatable :: unknown) :: BinaryRawFn

-- ================================================================================================
-- Fixture 1: SpecPoint -- tem todos os operadores opcionais.
-- ================================================================================================

-- Declarado sem valor inicial (só o tipo) -- upvalue capturada pelos closures de
-- `specPointDescriptor` abaixo (Add/Mul/Div/IDiv/Methods.Double), que só RODAM depois de
-- `SpecPointFactory` já ter sido atribuída (linha de `Userdata.Define`, mais abaixo). Mesmo
-- padrão de "forward declaration" que os tipos reais de `types/*.luau` vão precisar (um
-- construtor de Vector3 que soma dois Vector3 precisa criar um Vector3 NOVO, o que exige a
-- própria fábrica que ainda está sendo definida) -- verificado nesta tarefa que não precisa de
-- `any`: `local x: T` sem inicializador tipa limpo em --!strict (luau-lsp analyze confirmado).
local SpecPointFactory: Userdata.Factory

local function specPointFields(x: number): Userdata.Fields
	return { x }
end

-- Único ponto de cast `unknown -> SpecPoint` deste arquivo pro tipo Point -- mesmo precedente
-- de `runtime/Instance.luau:NewBase` (`local self = (proxy :: unknown) :: Instance`): o
-- Factory devolve `unknown` de verdade (é o que `Userdata.Factory` promete), e aqui a "vitrine"
-- tipada é aplicada UMA vez, na fronteira de construção -- todo o resto do arquivo usa `SpecPoint`
-- com sintaxe normal, sem cast nenhum.
local function newSpecPoint(x: number): SpecPoint
	return SpecPointFactory(specPointFields(x)) :: SpecPoint
end

local specPointMethods: { [string]: unknown } = {
	Double = function(self: unknown): unknown
		local fields = Userdata.Unwrap(self, "SpecPoint")
		return newSpecPoint((fields[1] :: number) * 2)
	end,
}
table.freeze(specPointMethods)

local specPointDescriptor: Userdata.Descriptor = {
	TypeName = "SpecPoint",
	Methods = specPointMethods,
	GetProperty = function(fields: Userdata.Fields, key: string): (unknown, boolean)
		if key == "X" then
			return fields[1], true
		end
		return nil, false
	end,
	Format = function(fields: Userdata.Fields): string
		return `SpecPoint({fields[1]})`
	end,
	Add = function(a: Userdata.Fields, b: Userdata.Fields, bTypeName: string): unknown
		if bTypeName ~= "SpecPoint" then
			error(`cannot add SpecPoint and {bTypeName}`, 3)
		end
		return newSpecPoint((a[1] :: number) + (b[1] :: number))
	end,
	Sub = function(a: Userdata.Fields, b: Userdata.Fields, bTypeName: string): unknown
		if bTypeName ~= "SpecPoint" then
			error(`cannot subtract SpecPoint and {bTypeName}`, 3)
		end
		return newSpecPoint((a[1] :: number) - (b[1] :: number))
	end,
	Mul = function(a: unknown, b: unknown): unknown
		local aName = Userdata.TypeNameOf(a)
		local bName = Userdata.TypeNameOf(b)
		if aName == "SpecPoint" and typeof(b) == "number" then
			local fields = Userdata.Unwrap(a, "SpecPoint")
			return newSpecPoint((fields[1] :: number) * (b :: number))
		elseif bName == "SpecPoint" and typeof(a) == "number" then
			local fields = Userdata.Unwrap(b, "SpecPoint")
			return newSpecPoint((fields[1] :: number) * (a :: number))
		end
		error("SpecPoint Mul: operandos não suportados", 3)
	end,
	Div = function(a: unknown, b: unknown): unknown
		if Userdata.TypeNameOf(a) == "SpecPoint" and typeof(b) == "number" then
			local fields = Userdata.Unwrap(a, "SpecPoint")
			return newSpecPoint((fields[1] :: number) / (b :: number))
		end
		error("SpecPoint Div: operandos não suportados", 3)
	end,
	IDiv = function(a: unknown, b: unknown): unknown
		if Userdata.TypeNameOf(a) == "SpecPoint" and typeof(b) == "number" then
			local fields = Userdata.Unwrap(a, "SpecPoint")
			return newSpecPoint(math.floor((fields[1] :: number) // (b :: number)))
		end
		error("SpecPoint IDiv: operandos não suportados", 3)
	end,
	Unm = function(a: Userdata.Fields): unknown
		return newSpecPoint(-(a[1] :: number))
	end,
	Equals = function(a: Userdata.Fields, b: Userdata.Fields): boolean
		return a[1] == b[1]
	end,
}

SpecPointFactory = Userdata.Define(specPointDescriptor)

-- ================================================================================================
-- Fixture 2: SpecColor -- nenhum operador aritmético (imita Color3, math_operations: []).
-- ================================================================================================

local SpecColorFactory: Userdata.Factory

local function newSpecColor(r: number): SpecColor
	return SpecColorFactory({ r }) :: SpecColor
end

local specColorDescriptor: Userdata.Descriptor = {
	TypeName = "SpecColor",
	Methods = table.freeze({}) :: { [string]: unknown },
	GetProperty = function(fields: Userdata.Fields, key: string): (unknown, boolean)
		if key == "R" then
			return fields[1], true
		end
		return nil, false
	end,
	Format = function(fields: Userdata.Fields): string
		return `SpecColor({fields[1]})`
	end,
	-- Add/Sub/Mul/Div/IDiv/Unm deliberadamente ausentes (nil) -- ver teste "operador não
	-- suportado" abaixo.
	Equals = function(a: Userdata.Fields, b: Userdata.Fields): boolean
		return a[1] == b[1]
	end,
}

SpecColorFactory = Userdata.Define(specColorDescriptor)

-- ================================================================================================
-- Invariante 1: __metatable sempre travado.
-- ================================================================================================

test("type(v) == \"userdata\" para todo value type criado pela fábrica", function()
	local p = newSpecPoint(1)
	assert(type(p) == "userdata", `esperava userdata, recebeu {type(p)}`)
end)

test("getmetatable(v) devolve a string travada, nunca a metatable real (invariante 1)", function()
	local p = newSpecPoint(1)
	-- `mt` é anotado `unknown` explicitamente: o valor de RETORNO estático de `getmetatable(p)`
	-- é o TIPO da metatable declarada de SpecPoint (não uma string), então comparar contra um
	-- literal de string exigiria o mesmo tipo dos dois lados (mesma restrição de `==` entre
	-- tipos com metatable declarada, ver `asEq` acima) -- aqui queremos testar o valor REAL em
	-- runtime (a string travada), não o que o checker acha que o tipo promete estaticamente.
	local mt: unknown = getmetatable(p)
	assert(mt == "The metatable is locked", `esperava a string travada, recebeu {typeof(mt)}: {tostring(mt)}`)
end)

test("setmetatable(v, {}) erra em vez de trocar a metatable silenciosamente (invariante 1)", function()
	local p = newSpecPoint(1)
	local ok, err = pcall(function()
		setmetatableUnknown(p, {})
	end)
	assert(not ok, "setmetatable sobre um value type deveria errar")
	assert(
		string.find(tostring(err), "table expected", 1, true) ~= nil,
		`mensagem deveria indicar que o value type não é uma tabela (userdata), recebeu: {err}`
	)
	-- o valor continua funcional depois da tentativa (não ficou num estado corrompido).
	assert(p.X == 1, "o value type deveria continuar funcional após a tentativa de setmetatable")
end)

test("pairs(v) erra nativamente (userdata não é iterável) -- invariante 1 por extensão", function()
	local p = newSpecPoint(1)
	local ok = pcall(function()
		pairs(p)
	end)
	assert(not ok, "pairs sobre um value type deveria errar")
end)

-- ================================================================================================
-- Invariante 2: __newindex sempre erra.
-- ================================================================================================

test("escrever numa propriedade existente erra (invariante 2, value type é imutável)", function()
	local p = newSpecPoint(1)
	local ok, err = pcall(function()
		p.X = 99
	end)
	assert(not ok, "escrever em X deveria errar")
	assert(
		string.find(tostring(err), "SpecPoint", 1, true) ~= nil,
		`mensagem de erro deveria citar o TypeName, recebeu: {err}`
	)
	assert(p.X == 1, "X não deveria ter sido alterado pela tentativa de escrita")
end)

test("escrever numa chave desconhecida também erra (não é um caso à parte de ReadOnly)", function()
	local p = newSpecPoint(1)
	local ok = pcall(function()
		asStringIndexable(p).NaoExiste = 1
	end)
	assert(not ok, "escrever numa chave desconhecida deveria errar igual a uma propriedade conhecida")
end)

-- ================================================================================================
-- Invariante 3: estado em side-table module-local com __mode = "k" -- sem vazamento.
-- ================================================================================================

test("estado não vaza: 100k value types soltos não deixam a memória crescer sem limite (invariante 3)", function()
	-- Threshold calibrado empiricamente nesta tarefa (reproduzível com `lune run` sobre um
	-- script descartável de scratchpad, não commitado):
	--   - COM `__mode = "k"` (implementação real): baseline ~179 KB -> depois de 100k criados e
	--     soltos, ~2437 KB (diff ~2258 KB) -- estabiliza, não cresce mais em rodadas seguintes.
	--   - SEM `__mode = "k"` (side-table forte, controle negativo simulado com uma tabela comum
	--     `{[unknown]: {number}}` fora deste módulo): baseline ~163 KB -> depois de 100k, ~12054
	--     KB (diff ~11891 KB) -- e continua crescendo linearmente em rodadas seguintes.
	-- 5000 KB fica confortavelmente entre os dois casos observados (2258 vs 11891), com margem
	-- de sobra pra ruído do GC incremental do Lune, que não é forçável aqui: `collectgarbage`
	-- neste Lune só aceita o modo "count" (confirmado nesta tarefa -- "collect"/"isrunning"/sem
	-- argumento erram "invalid option"), então este teste depende do GC incremental rodar
	-- sozinho durante as 100k alocações, não de uma coleta forçada.
	local LEAK_THRESHOLD_KB = 5000

	-- GAP DE TOOLING CONHECIDO (não é uma violação real de --!strict/regra 01): `luau-lsp
	-- analyze --platform=standard` reporta "Unknown global 'collectgarbage'" nas duas linhas
	-- abaixo. `collectgarbage` é uma extensão do Lune ao ambiente Luau -- o Roblox real não
	-- expõe esse global a scripts nenhuma (não há controle de GC na API pública do Roblox), e
	-- `--platform=standard` espelha exatamente o namespace global do Roblox, então o global
	-- nem existe no banco de tipos consultado. Confirmado nesta tarefa que roda perfeitamente
	-- via `lune run` (é um global real do runtime, só ausente do banco de tipos de análise) --
	-- mesma categoria de gap já documentada no projeto pra `init.spec.luau` (falso-positivo de
	-- luau-lsp 1.69.0), só que aqui é ausência de declaração, não bug do analisador. Não existe
	-- workaround sem introduzir `any` (a única saída, `_G.collectgarbage`, foi testada e
	-- comprovada que NÃO funciona neste Lune -- `_G` não é o ambiente global real aqui).
	local before = collectgarbage("count")
	for i = 1, 100000 do
		local _throwaway = newSpecPoint(i)
	end
	local after = collectgarbage("count")

	local diff = after - before
	print(`    (memória: antes={before}KB depois={after}KB diff={diff}KB, limite={LEAK_THRESHOLD_KB}KB)`)
	assert(
		diff < LEAK_THRESHOLD_KB,
		`memória cresceu {diff}KB depois de 100k value types soltos -- acima do limite de {LEAK_THRESHOLD_KB}KB, suspeita de vazamento na side-table (__mode="k" ausente ou quebrado)`
	)
end)

-- ================================================================================================
-- Invariante 4: __eq só delega quando os dois lados são userdata NOSSO do MESMO TypeName.
-- ================================================================================================

test("__eq: mesmo tipo e mesmo valor -> true", function()
	local a = newSpecPoint(5)
	local b = newSpecPoint(5)
	assert(asEq(a) == asEq(b), "dois SpecPoint com o mesmo valor deveriam ser ==")
end)

test("__eq: mesmo tipo e valor diferente -> false", function()
	local a = newSpecPoint(5)
	local b = newSpecPoint(6)
	assert(not (asEq(a) == asEq(b)), "dois SpecPoint com valores diferentes não deveriam ser ==")
end)

test("__eq: tipos NOSSOS diferentes -> false SEM erro (invariante 4)", function()
	local point = newSpecPoint(5)
	local color = newSpecColor(5)
	local ok, result = pcall(function()
		return asEq(point) == asEq(color)
	end)
	assert(ok, `comparar tipos diferentes não deveria errar, erro: {tostring(result)}`)
	assert(result == false, "SpecPoint == SpecColor deveria ser false mesmo com Fields[1] igual")

	-- ordem invertida também não deveria errar nem ser true.
	local ok2, result2 = pcall(function()
		return asEq(color) == asEq(point)
	end)
	assert(ok2, `comparar na ordem invertida não deveria errar, erro: {tostring(result2)}`)
	assert(result2 == false, "SpecColor == SpecPoint (ordem invertida) deveria ser false")
end)

test("__eq: userdata alheio (newproxy cru de fora deste módulo) -> false SEM erro (invariante 4)", function()
	local point = newSpecPoint(5)
	local alienProtected = newproxy(true)
	local alienUnprotected = newproxy(false)

	local ok1, result1 = pcall(function()
		return asEq(point) == asEq(alienProtected)
	end)
	assert(ok1, `point == alien (protected) não deveria errar, erro: {tostring(result1)}`)
	assert(result1 == false, "point == alien (protected) deveria ser false")

	local ok2, result2 = pcall(function()
		return asEq(point) == asEq(alienUnprotected)
	end)
	assert(ok2, `point == alien (unprotected) não deveria errar, erro: {tostring(result2)}`)
	assert(result2 == false, "point == alien (unprotected) deveria ser false")

	-- ordem invertida: o operando alheio é checado primeiro por Lua/Luau (não tem __eq),
	-- então cai no __eq do NOSSO lado (segundo operando) -- mesmo resultado, sem erro.
	local ok3, result3 = pcall(function()
		return asEq(alienUnprotected) == asEq(point)
	end)
	assert(ok3, `alien == point (ordem invertida) não deveria errar, erro: {tostring(result3)}`)
	assert(result3 == false, "alien == point (ordem invertida) deveria ser false")
end)

test("__eq: comparação com valor solto (number/string/nil/boolean) -> false, __eq nem é chamado (comportamento nativo do Luau)", function()
	local point = newSpecPoint(5)
	assert(not (asEq(point) == asEq(5)), "SpecPoint == 5 deveria ser false")
	assert(not (asEq(point) == asEq("5")), "SpecPoint == \"5\" deveria ser false")
	assert(not (asEq(point) == asEq(nil)), "SpecPoint == nil deveria ser false")
	assert(not (asEq(point) == asEq(true)), "SpecPoint == true deveria ser false")
end)

test("__eq: mesma referência é sempre true (otimização primitiva do Luau, nem chama __eq)", function()
	local point = newSpecPoint(5)
	assert(asEq(point) == asEq(point), "um value type deveria ser == a si mesmo")
end)

-- ================================================================================================
-- GetProperty / Methods / Format (__tostring)
-- ================================================================================================

test("GetProperty: leitura de propriedade declarada", function()
	local p = newSpecPoint(7)
	assert(p.X == 7, `esperava X == 7, recebeu {p.X}`)
end)

test("Methods: chamada de método (sintaxe de dois-pontos) devolve um SpecPoint novo", function()
	local p = newSpecPoint(4)
	local doubled = p:Double()
	assert(doubled.X == 8, `esperava Double() devolver X == 8, recebeu {doubled.X}`)
	assert(p.X == 4, "o SpecPoint original não deveria ter sido alterado (imutabilidade)")
end)

test("acessar um membro inválido erra citando a chave e o TypeName", function()
	local p = newSpecPoint(1)
	local ok, err = pcall(function()
		return asStringIndexable(p).NaoExiste
	end)
	assert(not ok, "ler um membro inválido deveria errar")
	local message = tostring(err)
	assert(string.find(message, "NaoExiste", 1, true) ~= nil, `mensagem deveria citar a chave, recebeu: {message}`)
	assert(string.find(message, "SpecPoint", 1, true) ~= nil, `mensagem deveria citar o TypeName, recebeu: {message}`)
end)

test("acessar com uma chave não-string (ex.: v[5]) erra em vez de silenciosamente devolver nil", function()
	local p = newSpecPoint(1)
	local ok = pcall(function()
		return p[5]
	end)
	assert(not ok, "indexar um value type com uma chave não-string deveria errar")
end)

test("tostring usa Format do descritor (não o tostring cru do Luau)", function()
	local p = newSpecPoint(3)
	assert(tostring(p) == "SpecPoint(3)", `esperava "SpecPoint(3)", recebeu "{tostring(p)}"`)
end)

-- ================================================================================================
-- Operadores: Add/Sub (Fields desembrulhados), Mul/Div/IDiv (operandos crus), Unm.
-- ================================================================================================

test("__add: soma dois SpecPoint", function()
	local a = newSpecPoint(2)
	local b = newSpecPoint(3)
	local sum = a + b
	assert(sum.X == 5, `esperava X == 5, recebeu {sum.X}`)
end)

test("__sub: subtrai dois SpecPoint", function()
	local a = newSpecPoint(5)
	local b = newSpecPoint(2)
	local diff = a - b
	assert(diff.X == 3, `esperava X == 3, recebeu {diff.X}`)
end)

test("__mul: SpecPoint * number e number * SpecPoint (operandos crus)", function()
	local a = newSpecPoint(4)
	local scaledRight = a * 2
	assert(scaledRight.X == 8, `esperava X == 8, recebeu {scaledRight.X}`)

	local scaledLeft = 2 * a
	assert(scaledLeft.X == 8, `esperava X == 8 (número * SpecPoint), recebeu {scaledLeft.X}`)
end)

test("__div/__idiv: SpecPoint / number", function()
	local a = newSpecPoint(9)
	local divided = a / 2
	assert(divided.X == 4.5, `esperava X == 4.5, recebeu {divided.X}`)

	local floorDivided = a // 2
	assert(floorDivided.X == 4, `esperava X == 4, recebeu {floorDivided.X}`)
end)

test("__unm: nega um SpecPoint", function()
	local a = newSpecPoint(7)
	local negated = -a
	assert(negated.X == -7, `esperava X == -7, recebeu {negated.X}`)
end)

test("Add erra coerentemente quando bTypeName não é aceito pelo tipo (SpecPoint + SpecColor)", function()
	local point = newSpecPoint(1)
	local color = newSpecColor(1)
	local ok = pcall(function()
		return asBinaryOperable(point) + asBinaryOperable(color)
	end)
	assert(not ok, "SpecPoint + SpecColor deveria errar (SpecPoint só aceita somar com SpecPoint)")
end)

test("despacho cruzado: SpecColor + SpecPoint (SpecColor não tem __add) erra coerentemente, nunca devolve valor errado", function()
	-- SpecColor não define Add (nil) -- o Luau despacha pelo operando da DIREITA (SpecPoint,
	-- que TEM __add). O wrapper da fábrica detecta que o "self" verdadeiro é o operando da
	-- direita e chama SpecPoint.Add(pointFields, colorFields, "SpecColor") -- ordem física
	-- invertida em relação à escrita "SpecColor + SpecPoint", mas como SpecPoint.Add rejeita
	-- qualquer bTypeName que não seja "SpecPoint", o resultado é SEMPRE um erro coerente, nunca
	-- um valor numericamente errado (ver "Limitação conhecida: despacho cruzado" no cabeçalho
	-- de Userdata.luau).
	local color = newSpecColor(1)
	local point = newSpecPoint(1)
	local ok, err = pcall(function()
		return asBinaryOperable(color) + asBinaryOperable(point)
	end)
	assert(not ok, "SpecColor + SpecPoint deveria errar (SpecColor não suporta Add e SpecPoint só soma com SpecPoint)")
	assert(
		string.find(tostring(err), "SpecColor", 1, true) ~= nil,
		`mensagem deveria mencionar o tipo rejeitado, recebeu: {err}`
	)
end)

test("operador NÃO suportado (SpecColor, todos os operadores nil): o Luau levanta o erro nativo sozinho", function()
	local a = newSpecColor(1)
	local b = newSpecColor(2)

	local okAdd, errAdd = pcall(function()
		return asBinaryOperable(a) + asBinaryOperable(b)
	end)
	assert(not okAdd, "SpecColor + SpecColor deveria errar (Add não instalado)")
	assert(
		string.find(tostring(errAdd), "arithmetic", 1, true) ~= nil,
		`esperava o erro NATIVO de aritmética do Luau, recebeu: {errAdd}`
	)

	local okUnm = pcall(function()
		return -asUnaryOperable(a)
	end)
	assert(not okUnm, "-SpecColor deveria errar (Unm não instalado)")

	local okMul = pcall(function()
		return asMulOperable(a) * 2
	end)
	assert(not okMul, "SpecColor * 2 deveria errar (Mul não instalado)")
end)

-- ================================================================================================
-- Userdata.TypeNameOf / Userdata.Unwrap
-- ================================================================================================

test("TypeNameOf: devolve o TypeName certo pra valores nossos, nil pro resto", function()
	local point = newSpecPoint(1)
	assert(Userdata.TypeNameOf(point) == "SpecPoint", "TypeNameOf deveria devolver \"SpecPoint\"")
	assert(Userdata.TypeNameOf(5) == nil, "TypeNameOf de um número deveria ser nil")
	assert(Userdata.TypeNameOf("x") == nil, "TypeNameOf de uma string deveria ser nil")
	assert(Userdata.TypeNameOf(nil) == nil, "TypeNameOf de nil deveria ser nil")
	assert(Userdata.TypeNameOf({}) == nil, "TypeNameOf de uma tabela comum deveria ser nil")
	assert(Userdata.TypeNameOf(newproxy(true)) == nil, "TypeNameOf de um newproxy cru alheio deveria ser nil")
end)

test("Unwrap: devolve os Fields corretos quando o TypeName bate", function()
	local point = newSpecPoint(9)
	local fields = Userdata.Unwrap(point, "SpecPoint")
	assert(fields[1] == 9, `esperava Fields[1] == 9, recebeu {tostring(fields[1])}`)
end)

test("Unwrap: erra citando o tipo real quando o TypeName não bate", function()
	local color = newSpecColor(1)
	local ok, err = pcall(function()
		Userdata.Unwrap(color, "SpecPoint")
	end)
	assert(not ok, "Unwrap com TypeName errado deveria errar")
	assert(
		string.find(tostring(err), "SpecColor", 1, true) ~= nil,
		`mensagem deveria citar o tipo real recebido (SpecColor), recebeu: {err}`
	)
end)

test("Unwrap: erra pra um valor que não é userdata nosso nenhum", function()
	local ok, err = pcall(function()
		Userdata.Unwrap(5, "SpecPoint")
	end)
	assert(not ok, "Unwrap de um número deveria errar")
	assert(string.find(tostring(err), "number", 1, true) ~= nil, `mensagem deveria citar "number", recebeu: {err}`)
end)

-- ================================================================================================
-- Guardas defensivas de Userdata.Define.
-- ================================================================================================

test("Define recusa TypeName vazio", function()
	local ok = pcall(function()
		Userdata.Define({
			TypeName = "",
			Methods = table.freeze({}) :: { [string]: unknown },
			GetProperty = function()
				return nil, false
			end,
			Format = function()
				return ""
			end,
			Equals = function()
				return true
			end,
		})
	end)
	assert(not ok, "Define com TypeName vazio deveria errar")
end)

test("Define recusa registrar o mesmo TypeName duas vezes", function()
	local ok = pcall(function()
		Userdata.Define(specPointDescriptor)
	end)
	assert(not ok, "Define('SpecPoint') pela segunda vez deveria errar (já registrado por esta suíte)")
end)

test("Define recusa Methods não congelada", function()
	local ok, err = pcall(function()
		Userdata.Define({
			TypeName = "SpecUnfrozenMethods",
			Methods = {} :: { [string]: unknown }, -- NÃO congelada de propósito
			GetProperty = function()
				return nil, false
			end,
			Format = function()
				return ""
			end,
			Equals = function()
				return true
			end,
		})
	end)
	assert(not ok, "Define com Methods não congelada deveria errar")
	assert(string.find(tostring(err), "Methods", 1, true) ~= nil, `mensagem deveria mencionar Methods, recebeu: {err}`)
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
