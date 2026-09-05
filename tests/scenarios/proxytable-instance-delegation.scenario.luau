--!strict

-- Cenário: proxytable clássica (__index/__newindex interceptando leitura e escrita) que
-- envolve uma Instance real do LuauBench -- delega pra Instance qualquer chave que não seja
-- um campo "customizado" do wrapper, e valida/clampa antes de escrever em campos específicos.
-- É o padrão usado por wrappers tipo "Component"/"Controller" no ecossistema Roblox, que
-- ficam por cima de uma Instance real adicionando lógica sem reabrir a classe dela.
-- Origem: sintético (idioma inspirado no padrão real de
-- D:\UserData\Documents\Roblox-Games\Towers\src\server\Components\Player\VitalComponent.luau
-- e equivalentes -- que fazem exatamente "wrapper com self.Health/self.Package por cima de
-- self.Instance" -- só que aqui delegando de verdade via __index/__newindex, em vez de guardar
-- a Instance num campo separado como o Modux faz).
-- Superfície exercitada: Instance.NewBase, .Name/.Parent, propriedade genérica
-- (Instance.SetPropertyRaw/GetPropertyRaw por baixo do __newindex/__index padrão), Changed.
-- Status: passa hoje.

local process = require("@lune/process")
local Instance = require("../../src/runtime/Instance")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

-- Constrói um "Component" que embrulha uma Instance: leitura de chave desconhecida delega pra
-- Instance (via __index como TABELA -- Lua repete a indexação em `instance`, o que aciona o
-- __index de função de Instance.luau normalmente); escrita passa por validação de campos
-- customizados (aqui, "Health" é clampado 0-100 e nunca é escrito na Instance de verdade,
-- porque "Health" não existe no vocabulário de Instance/Roblox real) e só then repassa pra
-- Instance.SetPropertyRaw quando não é um campo customizado.
local function wrapComponent(instance: Instance.Instance)
	local custom: { [string]: unknown } = { Health = 100 }
	local writes: { string } = {}

	local proxy = {}
	local meta = {}
	meta.__index = function(_self: unknown, key: string): unknown
		if custom[key] ~= nil then
			return custom[key]
		end
		return ((instance :: unknown) :: { [string]: unknown })[key]
	end
	meta.__newindex = function(_self: unknown, key: string, value: unknown): ()
		table.insert(writes, key)
		if key == "Health" then
			local numeric = value :: number
			custom.Health = math.clamp(numeric, 0, 100)
			return
		end
		-- Qualquer outra chave (ex: Name) é repassada pra Instance de verdade -- inclusive
		-- disparando o Changed real dela, não um Changed fake do wrapper.
		((instance :: unknown) :: { [string]: unknown })[key] = value
	end

	return setmetatable(proxy, meta), writes
end

test("leitura de chave desconhecida delega pro __index de Instance (Name/ClassName/métodos)", function()
	local instance = Instance.NewBase("Model", "Coin")
	local component = wrapComponent(instance)

	assert((component :: any).Name == "Coin", "leitura de Name deveria delegar pra Instance real")
	assert((component :: any).ClassName == "Model", "leitura de ClassName deveria delegar pra Instance real")
	-- Métodos de Instance também chegam pela mesma delegação -- IsA vem do __index de função.
	local isA = (component :: any).IsA
	assert(type(isA) == "function", "IsA deveria delegar como método de Instance através da proxytable")
end)

test("escrita em campo customizado (Health) é clampada e NUNCA chega na Instance real", function()
	local instance = Instance.NewBase("Model", "Player")
	local component, writes = wrapComponent(instance)

	local changedKeys: { string } = {}
	instance.Changed:Connect(function(key: string)
		table.insert(changedKeys, key)
	end)

	;(component :: any).Health = 999 -- deveria ser clampado pra 100

	assert((component :: any).Health == 100, `Health deveria ter sido clampado para 100, ficou {(component :: any).Health}`)
	assert(#writes == 1 and writes[1] == "Health", "o __newindex do wrapper deveria ter interceptado exatamente uma escrita, em 'Health'")
	assert(#changedKeys == 0, "Health é campo customizado do wrapper -- não deveria disparar o Changed real da Instance")

	;(component :: any).Health = -50 -- deveria ser clampado pra 0
	assert((component :: any).Health == 0, "Health negativo deveria ser clampado para 0")
end)

test("escrita em chave desconhecida (Name) é repassada pra Instance real e dispara o Changed dela", function()
	local instance = Instance.NewBase("Model", "Old")
	local component, writes = wrapComponent(instance)

	local changedKeys: { string } = {}
	instance.Changed:Connect(function(key: string)
		table.insert(changedKeys, key)
	end)

	;(component :: any).Name = "New"

	assert(instance.Name == "New", "escrever Name via o proxy deveria ter renomeado a Instance real por baixo")
	assert(#changedKeys == 1 and changedKeys[1] == "Name", "renomear via o proxy deveria disparar o Changed real da Instance")
	assert(#writes == 1 and writes[1] == "Name", "o __newindex do wrapper deveria ter visto a escrita em 'Name'")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
