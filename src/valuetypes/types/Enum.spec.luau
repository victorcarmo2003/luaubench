--!strict

--[[
	Teste da task-valuetypes-003 (`Enum`/`Enums`/`EnumItem`). Cobre o acceptance verbatim do board
	(.claude/tasks.json, task-valuetypes-003): os três `typeof`, `tostring` de `EnumItem`,
	`GetEnumItems`/`FromName`/`FromValue`, identidade preservada (`rawequal` do mesmo item), enum e
	item inexistentes errando e citando o nome, e o tempo de load de `EnumData` medido e registrado.

	`typeof()` NATIVO do Luau/Lune devolve sempre `"userdata"` pra qualquer proxy desta fábrica
	(fato confirmado em `Userdata.luau`/o desenho arquitetural, seção 4 "Decisão 2") -- o `typeof`
	FIEL ("Enums"/"Enum"/"EnumItem") só existe DENTRO do sandbox de script, via o wrapper que
	`task-runtime-032` instala em `Sandbox.buildEnvironment` (fora do território desta tarefa). Os
	três `typeof` do acceptance desta tarefa são verificados aqui via `Userdata.TypeNameOf`, que é
	exatamente a função que alimenta aquele wrapper (`Runtime.TypeNameResolver.Set(ValueTypes.
	TypeNameOf)`, task futura -- init.luau) -- é o fato de fidelidade que esta tarefa É responsável
	por garantir; o encanamento até o `typeof` real do script é responsabilidade de outro
	território, já entregue.

	Roda com `lune run src/valuetypes/types/Enum.spec.luau`.
]]

local process = require("@lune/process")
local Userdata = require("../Userdata")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

-- ================================================================================================
-- Tempo de load de EnumData -- acceptance: "tempo de load de EnumData medido e registrado".
-- `require` em Lune roda o módulo (e o CACHEIA) na primeira chamada -- medir o tempo de PRIMEIRA
-- carga exige `require` acontecer DEPOIS do relógio começar a contar, então este bloco roda ANTES
-- de qualquer outro `require` deste arquivo tocar `EnumData` (direta ou indiretamente via
-- `types/Enum`, abaixo) -- se `Enum.luau` já tivesse sido carregado antes por outro módulo do
-- mesmo processo `lune run`, esta medição capturaria só o custo (barato) de um cache-hit, não o
-- parse+execução reais. Neste arquivo, `EnumData` é o PRIMEIRO módulo do território a ser
-- `require`ado (nem `Userdata`, acima, toca nele).
-- ================================================================================================

local loadStart = os.clock()
local EnumData = require("../generated/EnumData")
local loadElapsedSeconds = os.clock() - loadStart

print(`[MEDIÇÃO] src/valuetypes/generated/EnumData.luau: require() levou {loadElapsedSeconds * 1000} ms `
	.. `({#EnumData} enums, medido nesta execução via os.clock() -- ver relatório da tarefa pro `
	.. `valor observado e a comparação com a estimativa do desenho, seção 0.6, ~8.5 ms)`)

test("EnumData carrega em tempo desprezível para um script real (< 500ms, generoso)", function()
	-- Limite FROUXO de propósito: o objetivo deste teste é pegar uma REGRESSÃO GROSSEIRA (ex.:
	-- alguém acidentalmente reintroduzindo parsing do dump JSON de 8MB no caminho de `require`),
	-- não fixar um número apertado que quebraria por variação de máquina/CI. O número REAL
	-- observado nesta máquina é impresso acima e registrado no relatório da tarefa, não neste
	-- assert.
	assert(loadElapsedSeconds < 0.5, `EnumData.luau levou {loadElapsedSeconds * 1000}ms pra carregar -- suspeito`)
end)

test("EnumData tem exatamente 629 enums (seção D.3 da pesquisa)", function()
	assert(#EnumData == 629, `esperava 629 enums, recebeu {#EnumData}`)
end)

test("EnumData tem exatamente 3611 EnumItems no total (soma de todos os enums)", function()
	local total = 0
	for _, definition in EnumData do
		total += #definition.ItemNames
		assert(#definition.ItemNames == #definition.ItemValues, `{definition.Name}: ItemNames/ItemValues com tamanhos diferentes`)
	end
	assert(total == 3611, `esperava 3611 itens no total, recebeu {total}`)
end)

-- ================================================================================================
-- Requer o módulo real (`types/Enum.luau`) DEPOIS da medição acima -- ele também faz `require` de
-- `EnumData`, mas o Lune cacheia módulos por caminho: esta segunda chamada é um cache-hit, não
-- reparseia nem re-executa o arquivo.
-- ================================================================================================

local EnumRoot = require("./Enum")

-- ================================================================================================
-- Vitrines tipadas SEM `any` (regra 01) -- mesmo padrão de `Color3.spec.luau`/`Userdata.spec.luau`
-- pra testar um value type opaco (userdata real, __index/__newindex reais, sem checagem estática):
--
--   1. `asStringIndexable`: indexa uma chave de STRING dinâmica (`.KeyCode`, `.Space`,
--      `.NaoExiste`) que os tipos exportados de `types/Enum.luau` (`Enums`/`Enum`/`EnumItem`) não
--      modelam estaticamente -- eles só declaram os MÉTODOS/PROPRIEDADES fixos; qual enum/qual
--      item é resolvido 100% em runtime, via `GetProperty`. Devolve `unknown`, nunca `any`.
--   2. `enumMember`/`enumItemMember`: aplicam o MESMO cast de fronteira `unknown -> tipo nominal
--      real` já usado em `Userdata.spec.luau` (`newSpecPoint`) e em todo `types/*.luau`
--      (`fromFields` de `Color3.luau`) -- uma vez, na fronteira, pro tipo REAL que `types/Enum.
--      luau` já exporta (`EnumRoot.Enum`/`EnumRoot.EnumItem`). Daí em diante (`.Name`, `.Value`,
--      `:GetEnumItems()`, `:FromName(...)`, etc.) o resto do arquivo usa o tipo real do módulo,
--      SEM cast nenhum -- é exatamente a superfície que `types/Enum.luau` já declara.
--   3. `asEq`/`EqProbe`: mesmo probe de `Color3.spec.luau`/`Userdata.spec.luau` -- necessário
--      porque os tipos exportados `Enum`/`EnumItem` não declaram `__eq` na metatable estática (só
--      `__tostring`), então o checker recusa `==`/`~=` entre dois valores desse tipo sem essa
--      "lente". O comportamento exercitado é 100% do `__eq` real instalado por `Userdata.Define`
--      -- o tipo sintético só empresta a assinatura de operador pro checker.
--   4. `UnaryRawFn`: mesmo precedente de `BinaryRawFn`/`setmetatableUnknown` dos dois arquivos
--      irmãos -- casta a FUNÇÃO de método (`GetEnumItems`) pra aceitar um `self` `unknown`, usado
--      só no teste que deliberadamente invoca o método com um `self` ERRADO (não um `Enum`) pra
--      confirmar que `Userdata.Unwrap` rejeita.
-- ================================================================================================

type StringIndexableProbe = typeof(setmetatable({} :: { [string]: unknown }, {}))
local function asStringIndexable(value: unknown): StringIndexableProbe
	return value :: StringIndexableProbe
end

type EqProbe = typeof(setmetatable({} :: {}, {} :: { __eq: (EqProbe, EqProbe) -> boolean }))
local function asEq(value: unknown): EqProbe
	return value :: EqProbe
end

type UnaryRawFn = (unknown) -> unknown

-- Indexa `Enum.<name>` (ex.: `enumMember(EnumRoot, "KeyCode")`) já convertido pro tipo nominal
-- real `Enum` que `types/Enum.luau` exporta -- cast único de fronteira, ver bloco acima.
local function enumMember(container: unknown, name: string): EnumRoot.Enum
	return asStringIndexable(container)[name] :: EnumRoot.Enum
end

-- Indexa `Enum.<Enum>.<name>` (ex.: `enumItemMember(keyCode, "Space")`) já convertido pro tipo
-- nominal real `EnumItem`, mesmo raciocínio.
local function enumItemMember(container: unknown, name: string): EnumRoot.EnumItem
	return asStringIndexable(container)[name] :: EnumRoot.EnumItem
end

-- ================================================================================================
-- Os três typeof (acceptance) -- via Userdata.TypeNameOf, ver cabeçalho pro porquê.
-- ================================================================================================

test("typeof do global Enum (Enums) é \"Enums\"", function()
	assert(Userdata.TypeNameOf(EnumRoot) == "Enums", `esperava "Enums", recebeu {tostring(Userdata.TypeNameOf(EnumRoot))}`)
end)

test("typeof de Enum.KeyCode (Enum) é \"Enum\"", function()
	local keyCode = enumMember(EnumRoot, "KeyCode")
	assert(Userdata.TypeNameOf(keyCode) == "Enum", `esperava "Enum", recebeu {tostring(Userdata.TypeNameOf(keyCode))}`)
end)

test("typeof de Enum.KeyCode.Space (EnumItem) é \"EnumItem\"", function()
	local space = enumItemMember(enumMember(EnumRoot, "KeyCode"), "Space")
	assert(Userdata.TypeNameOf(space) == "EnumItem", `esperava "EnumItem", recebeu {tostring(Userdata.TypeNameOf(space))}`)
end)

test("type() nativo é \"userdata\" para os três (fábrica única, ver Userdata.luau)", function()
	local keyCode = enumMember(EnumRoot, "KeyCode")
	local space = enumItemMember(keyCode, "Space")
	assert(type(EnumRoot) == "userdata", `Enum (root): esperava userdata, recebeu {type(EnumRoot)}`)
	assert(type(keyCode) == "userdata", `Enum.KeyCode: esperava userdata, recebeu {type(keyCode)}`)
	assert(type(space) == "userdata", `Enum.KeyCode.Space: esperava userdata, recebeu {type(space)}`)
end)

-- ================================================================================================
-- tostring de EnumItem/Enum -- confirmado pela pesquisa (content/en-us/luau/enums.md).
-- ================================================================================================

test("tostring(Enum.KeyCode.Space) == \"Enum.KeyCode.Space\"", function()
	local space = enumItemMember(enumMember(EnumRoot, "KeyCode"), "Space")
	assert(tostring(space) == "Enum.KeyCode.Space", `esperava "Enum.KeyCode.Space", recebeu {tostring(space)}`)
end)

test("tostring(Enum.KeyCode) == \"KeyCode\" (bare name, sem prefixo Enum.)", function()
	local keyCode = enumMember(EnumRoot, "KeyCode")
	assert(tostring(keyCode) == "KeyCode", `esperava "KeyCode", recebeu {tostring(keyCode)}`)
end)

test("tostring de outro EnumItem qualquer (Enum.Material.Plastic)", function()
	local plastic = enumItemMember(enumMember(EnumRoot, "Material"), "Plastic")
	assert(tostring(plastic) == "Enum.Material.Plastic", `esperava "Enum.Material.Plastic", recebeu {tostring(plastic)}`)
end)

-- ================================================================================================
-- .Name / .Value / .EnumType de EnumItem.
-- ================================================================================================

test("EnumItem.Name/.Value/.EnumType", function()
	local space = enumItemMember(enumMember(EnumRoot, "KeyCode"), "Space")
	assert(space.Name == "Space", `Name esperado "Space", recebeu {tostring(space.Name)}`)
	assert(type(space.Value) == "number", `Value deveria ser number, recebeu {type(space.Value)}`)
	assert(space.Value == 32, `Value esperado 32 (confirmado no dump), recebeu {tostring(space.Value)}`)
	assert(Userdata.TypeNameOf(space.EnumType) == "Enum", "EnumType deveria ser o objeto \"Enum\" pai")
	assert(tostring(space.EnumType) == "KeyCode", `EnumType deveria imprimir "KeyCode", recebeu {tostring(space.EnumType)}`)
end)

-- ================================================================================================
-- ACHADO desta tarefa (ver tools/generate-enums.luau, cabeçalho): existem itens de enum
-- literalmente chamados "Name"/"Value" (Enum.SortOrder.Name, Enum.CompletionItemKind.Value). O
-- objeto "Enum" NÃO reserva essas chaves como propriedade especial seguindo a pesquisa (só
-- EnumItem tem .Name/.Value documentado) -- confirma que a resolução vai pro item, não pra uma
-- propriedade fantasma do objeto "Enum".
-- ================================================================================================

test("Enum.SortOrder.Name resolve para o EnumItem \"Name\", não para uma propriedade do objeto Enum", function()
	local sortOrder = enumMember(EnumRoot, "SortOrder")
	local nameItem = enumItemMember(sortOrder, "Name")
	assert(Userdata.TypeNameOf(nameItem) == "EnumItem", `Enum.SortOrder.Name deveria ser um EnumItem, TypeNameOf = {tostring(Userdata.TypeNameOf(nameItem))}`)
	assert(nameItem.Name == "Name", `EnumItem.Name esperado "Name", recebeu {tostring(nameItem.Name)}`)
	assert(tostring(nameItem) == "Enum.SortOrder.Name", `esperava "Enum.SortOrder.Name", recebeu {tostring(nameItem)}`)
end)

test("Enum.CompletionItemKind.Value resolve para o EnumItem \"Value\"", function()
	local completionItemKind = enumMember(EnumRoot, "CompletionItemKind")
	local valueItem = enumItemMember(completionItemKind, "Value")
	assert(Userdata.TypeNameOf(valueItem) == "EnumItem", "Enum.CompletionItemKind.Value deveria ser um EnumItem")
	assert(valueItem.Name == "Value", `EnumItem.Name esperado "Value", recebeu {tostring(valueItem.Name)}`)
end)

-- ================================================================================================
-- GetEnumItems / FromName / FromValue.
-- ================================================================================================

test("Enum:GetEnumItems() devolve todos os itens, na ordem do dump, todos EnumItem", function()
	local accessModifierType = enumMember(EnumRoot, "AccessModifierType")
	local items = accessModifierType:GetEnumItems()
	assert(#items == 2, `AccessModifierType deveria ter 2 itens, recebeu {#items}`)
	assert(items[1].Name == "Allow", `primeiro item esperado "Allow", recebeu {tostring(items[1].Name)}`)
	assert(items[2].Name == "Deny", `segundo item esperado "Deny", recebeu {tostring(items[2].Name)}`)
	for _, item in items do
		assert(Userdata.TypeNameOf(item) == "EnumItem", "todo item de GetEnumItems() deveria ser EnumItem")
	end
end)

test("Enum:GetEnumItems() devolve uma CÓPIA nova a cada chamada (não expõe a lista interna)", function()
	local keyCode = enumMember(EnumRoot, "KeyCode")
	local first = keyCode:GetEnumItems()
	-- Mutação de propósito na CÓPIA devolvida (duplica o primeiro item) -- sem precisar de nenhum
	-- valor de tipo estranho/`any`: um `EnumItem` de verdade já serve pra provar a independência
	-- das cópias (o que importa é o TAMANHO divergir e o cache interno continuar íntegro).
	table.insert(first, first[1])
	local second = keyCode:GetEnumItems()
	assert(#second ~= #first, "a segunda chamada não deveria refletir a mutação feita na primeira")
	for _, item in second do
		assert(Userdata.TypeNameOf(item) == "EnumItem", "cache interno não deveria ter sido corrompido")
	end
end)

test("Enum:FromName(nome) devolve o EnumItem certo", function()
	local keyCode = enumMember(EnumRoot, "KeyCode")
	local found = keyCode:FromName("Space")
	assert(found ~= nil, "FromName('Space') não deveria ser nil")
	assert(found.Name == "Space", `esperava item "Space", recebeu {tostring(found.Name)}`)
	assert(rawequal(found, enumItemMember(keyCode, "Space")), "FromName deveria devolver o MESMO objeto internado que a indexação direta")
end)

test("Enum:FromName(nome inexistente) devolve nil, SEM erro (lookup, não indexação direta)", function()
	local keyCode = enumMember(EnumRoot, "KeyCode")
	local found = keyCode:FromName("NomeQueNaoExiste")
	assert(found == nil, `esperava nil, recebeu {tostring(found)}`)
end)

test("Enum:FromValue(valor) devolve o EnumItem certo", function()
	local keyCode = enumMember(EnumRoot, "KeyCode")
	local space = enumItemMember(keyCode, "Space")
	local found = keyCode:FromValue(space.Value)
	assert(found ~= nil, "FromValue(32) não deveria ser nil")
	assert(rawequal(found, space), "FromValue deveria devolver o MESMO objeto internado que a indexação direta")
end)

test("Enum:FromValue(valor inexistente) devolve nil, SEM erro", function()
	local keyCode = enumMember(EnumRoot, "KeyCode")
	local found = keyCode:FromValue(-999999)
	assert(found == nil, `esperava nil, recebeu {tostring(found)}`)
end)

test("Enum:GetEnums() devolve os 629 enums, todos Enum, incluindo KeyCode", function()
	local root: EnumRoot.Enums = EnumRoot :: EnumRoot.Enums
	local all = root:GetEnums()
	assert(#all == 629, `esperava 629, recebeu {#all}`)
	local sawKeyCode = false
	for _, enumObject in all do
		assert(Userdata.TypeNameOf(enumObject) == "Enum", "todo elemento de GetEnums() deveria ser Enum")
		if tostring(enumObject) == "KeyCode" then
			sawKeyCode = true
		end
	end
	assert(sawKeyCode, "GetEnums() deveria incluir KeyCode")
end)

-- ================================================================================================
-- Identidade preservada (internamento) -- acceptance: "identidade preservada (rawequal do mesmo
-- item)".
-- ================================================================================================

test("rawequal: dois acessos a Enum.KeyCode.Space são o MESMO userdata", function()
	local a = enumItemMember(enumMember(EnumRoot, "KeyCode"), "Space")
	local b = enumItemMember(enumMember(EnumRoot, "KeyCode"), "Space")
	assert(rawequal(a, b), "Enum.KeyCode.Space deveria ser internado -- mesma referência sempre")
	assert(asEq(a) == asEq(b), "== também deveria ser true (curto-circuita na mesma referência)")
end)

test("rawequal: dois acessos a Enum.KeyCode (o objeto Enum) são o MESMO userdata", function()
	local a = enumMember(EnumRoot, "KeyCode")
	local b = enumMember(EnumRoot, "KeyCode")
	assert(rawequal(a, b), "Enum.KeyCode deveria ser memoizado -- mesma referência sempre")
end)

test("rawequal: itens de enums DIFERENTES nunca são o mesmo objeto", function()
	local space = enumItemMember(enumMember(EnumRoot, "KeyCode"), "Space")
	local plastic = enumItemMember(enumMember(EnumRoot, "Material"), "Plastic")
	assert(not rawequal(space, plastic), "itens de enums diferentes não podem ser o mesmo objeto")
	assert(not (asEq(space) == asEq(plastic)), "== também deveria ser false")
end)

test("== entre EnumItem de enums diferentes com o mesmo Value não são iguais (Equals compara EnumType também)", function()
	-- Procura dois itens de enums DIFERENTES com o MESMO Value (0 é universal -- quase todo enum
	-- tem um item com Value == 0) -- prova que Equals não confunde dois itens só porque Value bate.
	local accessModifierAllow = enumItemMember(enumMember(EnumRoot, "AccessModifierType"), "Allow") -- Value = 0
	local accessoryTypeUnknown = enumItemMember(enumMember(EnumRoot, "AccessoryType"), "Unknown") -- Value = 0
	assert(accessModifierAllow.Value == 0 and accessoryTypeUnknown.Value == 0, "sanity check: os dois deveriam ter Value == 0")
	assert(not (asEq(accessModifierAllow) == asEq(accessoryTypeUnknown)), "itens de enums diferentes com o mesmo Value não deveriam ser ==")
end)

-- ================================================================================================
-- Erros: enum e item inexistentes erram citando o nome (acceptance).
-- ================================================================================================

test("Enum.NaoExiste erra citando o nome, formato \"X is not a valid member of Enum\"", function()
	local ok, err = pcall(function()
		return asStringIndexable(EnumRoot).NaoExiste
	end)
	assert(not ok, "Enum.NaoExiste deveria errar")
	local message = tostring(err)
	assert(string.find(message, "NaoExiste", 1, true) ~= nil, `mensagem deveria citar o nome, recebeu: {message}`)
	assert(string.find(message, "is not a valid member of Enum", 1, true) ~= nil, `mensagem deveria seguir o formato confirmado pela pesquisa, recebeu: {message}`)
end)

test("Enum.KeyCode.NaoExiste erra citando o nome do item E do enum, formato com aspas", function()
	local ok, err = pcall(function()
		return asStringIndexable(enumMember(EnumRoot, "KeyCode")).NaoExiste
	end)
	assert(not ok, "Enum.KeyCode.NaoExiste deveria errar")
	local message = tostring(err)
	assert(string.find(message, "NaoExiste", 1, true) ~= nil, `mensagem deveria citar o nome do item, recebeu: {message}`)
	assert(string.find(message, "is not a valid member of \"Enum.KeyCode\"", 1, true) ~= nil, `mensagem deveria citar o enum entre aspas, recebeu: {message}`)
end)

test("Enum.KeyCode.Space.NaoExiste (propriedade inválida de um EnumItem) erra citando o nome", function()
	local ok, err = pcall(function()
		return asStringIndexable(enumItemMember(enumMember(EnumRoot, "KeyCode"), "Space")).NaoExiste
	end)
	assert(not ok, "propriedade inválida de um EnumItem deveria errar")
	assert(string.find(tostring(err), "NaoExiste", 1, true) ~= nil, `mensagem deveria citar o nome, recebeu: {err}`)
end)

test("Enum:GetEnumItems() chamado sobre um valor que não é Enum erra (Unwrap)", function()
	local keyCode = enumMember(EnumRoot, "KeyCode")
	local method: UnaryRawFn = asStringIndexable(keyCode).GetEnumItems :: UnaryRawFn
	local ok = pcall(function()
		return method(5)
	end)
	assert(not ok, "GetEnumItems chamado com self errado deveria errar")
end)

-- ================================================================================================
-- Imutabilidade -- mesma disciplina de todo value type deste território (invariantes 1/2 de
-- Userdata.luau já testadas em Userdata.spec.luau; aqui só confirmamos que Enum/EnumItem também
-- passam pela MESMA fábrica, não reabrem as quatro invariantes inteiras).
-- ================================================================================================

test("Enum.KeyCode.Space é imutável (__newindex erra)", function()
	local space = enumItemMember(enumMember(EnumRoot, "KeyCode"), "Space")
	local ok = pcall(function()
		asStringIndexable(space).Name = "Hacked"
	end)
	assert(not ok, "atribuir a uma propriedade de EnumItem deveria errar")
end)

test("getmetatable de qualquer um dos três devolve a string travada, nunca a real", function()
	local space = enumItemMember(enumMember(EnumRoot, "KeyCode"), "Space")
	local mt: unknown = getmetatable(space)
	assert(type(mt) == "string", `esperava string travada, recebeu {type(mt)}`)
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
