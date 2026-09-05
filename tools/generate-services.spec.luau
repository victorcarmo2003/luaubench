--!strict

--[[
	Teste da task-services-002: verifica os FATOS que `lune run tools/generate-services` deve
	produzir em `src/services/generated/` -- não roda o gerador (que baixa/lê o dump e pode demorar
	e depende de rede na ausência de cache), só INSPECIONA a saída já commitada. Rode
	`lune run tools/generate-services` antes desta suíte sempre que `tools/coverage.luau`,
	`tools/api-dump.lock.json` ou `tools/capabilities.lock.json` mudarem.

	Cobre os números exatos do acceptance de task-services-002 (.claude/tasks.json):
	- Manifest.luau com exatamente 916 entradas
	- fecho de 24 classes (as 20 de tools/coverage.luau + WorldRoot/Model/PVInstance/BasePlayerGui,
	  puxadas por herança sem estarem listadas em coverage.luau)
	- exatamente 4 membros de schema excluídos pelo eixo Capabilities na leva 1 (Script.Source,
	  ModuleScript.Source, RunService.Misprediction, RunService.FrameNumber)
	- 143 métodos emitidos no total no fecho
	- Lighting/Players/StarterPlayer com schema COMPLETO (nenhuma exclusão por Capability -- prova
	  de que a regra ingênua "capability != Basic é restritiva" não foi implementada)
	- RunService.Heartbeat/Stepped/RenderStepped/PreRender continuam no schema
	- Generated.Schema vem sempre congelado (table.freeze)

	Roda com `lune run tools/generate-services.spec.luau`.
]]

local process = require("@lune/process")

local Manifest = require("../src/services/generated/Manifest")
local Index = require("../src/services/generated/Index")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

test("Manifest.luau tem exatamente 916 entradas e a versão fixada do dump", function()
	local count = 0
	for _ in Manifest.Classes do
		count += 1
	end
	assert(count == 916, `Manifest deveria ter 916 entradas, tem {count}`)
	assert(
		Manifest.DumpCommit == "28360dea4b90b35dc3fe9f829baae64fb6c50e75",
		`DumpCommit inesperado: {Manifest.DumpCommit}`
	)
	assert(Manifest.DumpVersion == "0.737.0.7371584", `DumpVersion inesperado: {Manifest.DumpVersion}`)
end)

test("Manifest distingue classe não coberta (mas conhecida) de classe coberta", function()
	local workspaceEntry = Manifest.Classes["Workspace"]
	assert(workspaceEntry ~= nil, "Workspace deveria estar no Manifest")
	assert(workspaceEntry.Covered == true, "Workspace deveria estar Covered = true (está no fecho)")
	assert(workspaceEntry.IsService == true, "Workspace deveria ter IsService = true")
	assert(workspaceEntry.IsAbstract == true, "Workspace deveria ter IsAbstract = true (NotCreatable)")

	local frameEntry = Manifest.Classes["Frame"]
	assert(frameEntry ~= nil, "Frame deveria estar no Manifest (existe no dump)")
	assert(frameEntry.Covered == false, "Frame NÃO deveria estar coberto nesta leva")
end)

test("O fecho tem exatamente 24 classes, incluindo as puxadas por herança sem estar em coverage.luau", function()
	local expected = {
		"BasePlayerGui", "BaseScript", "Folder", "Instance", "Lighting", "LocalScript",
		"LuaSourceContainer", "Model", "ModuleScript", "PVInstance", "Players", "ReplicatedFirst",
		"ReplicatedStorage", "RunService", "Script", "ServerScriptService", "ServerStorage",
		"StarterCharacterScripts", "StarterGui", "StarterPack", "StarterPlayer",
		"StarterPlayerScripts", "Workspace", "WorldRoot",
	}
	local indexCount = 0
	for _ in Index do
		indexCount += 1
	end
	assert(indexCount == 24, `Index deveria ter 24 classes, tem {indexCount}`)
	for _, name in expected do
		assert(Index[name] ~= nil, `Index deveria conter "{name}"`)
		assert(Manifest.Classes[name].Covered == true, `Manifest deveria marcar "{name}" como Covered`)
	end

	-- Prova de que o fecho é CALCULADO, não escrito à mão: nenhuma destas 4 aparece em
	-- tools/coverage.luau, mas todas precisam existir no fecho (Workspace -> WorldRoot -> Model ->
	-- PVInstance -> Instance; StarterGui -> BasePlayerGui -> Instance).
	for _, name in { "WorldRoot", "Model", "PVInstance", "BasePlayerGui" } do
		assert(Index[name] ~= nil, `"{name}" deveria ter entrado no fecho por herança, mesmo fora de coverage.luau`)
	end
end)

test("Eixo Capabilities exclui EXATAMENTE os 4 membros de schema esperados na leva 1", function()
	local scriptSchema = Index["Script"].Schema
	local moduleScriptSchema = Index["ModuleScript"].Schema
	local runServiceSchema = Index["RunService"].Schema

	assert(scriptSchema["Source"] == nil, "Script.Source deveria estar FORA do schema (Capabilities.Read=[PluginOrOpenCloud])")
	assert(
		moduleScriptSchema["Source"] == nil,
		"ModuleScript.Source deveria estar FORA do schema (Capabilities.Read=[PluginOrOpenCloud])"
	)
	assert(
		runServiceSchema["Misprediction"] == nil,
		"RunService.Misprediction deveria estar FORA do schema (Capabilities=[Basic,PluginOrOpenCloud])"
	)
	assert(
		runServiceSchema["FrameNumber"] == nil,
		"RunService.FrameNumber deveria estar FORA do schema (Capabilities.Read=[Basic,InternalTest])"
	)
end)

test("RunService.Heartbeat/Stepped/RenderStepped/PreRender continuam no schema (Capabilities=[Basic])", function()
	local schema = Index["RunService"].Schema
	for _, eventName in { "Heartbeat", "Stepped", "RenderStepped", "PreRender" } do
		local entry = schema[eventName]
		assert(entry ~= nil, `RunService.{eventName} deveria estar no schema`)
		assert(entry.Kind == "Event", `RunService.{eventName} deveria ser Kind="Event"`)
		assert(entry.ReadOnly == true, `RunService.{eventName} deveria ser ReadOnly (evento)`)
	end
end)

test("143 métodos emitidos no total no fecho (acceptance de task-services-002)", function()
	local total = 0
	for _, generated in Index do
		total += #generated.MethodNames
	end
	assert(total == 143, `esperava 143 métodos no total do fecho, contei {total}`)
end)

test("Lighting/Players/StarterPlayer têm schema COMPLETO (zero exclusão pelo eixo Capabilities)", function()
	-- Prova negativa direta: propriedades com Capabilities != Basic que a regra INGÊNUA
	-- ("capability != Basic é restritiva") apagaria por completo.
	local lightingSchema = Index["Lighting"].Schema
	assert(lightingSchema["Ambient"] ~= nil, "Lighting.Ambient (Capabilities.Read=[Environment]) deveria estar no schema")

	local playersSchema = Index["Players"].Schema
	assert(playersSchema["PlayerAdded"] ~= nil, "Players.PlayerAdded (Capabilities=[Players]) deveria estar no schema")

	local starterPlayerSchema = Index["StarterPlayer"].Schema
	assert(
		starterPlayerSchema["AutoJumpEnabled"] ~= nil,
		"StarterPlayer.AutoJumpEnabled (Capabilities.Read=[Players]) deveria estar no schema"
	)

	-- E o Default REAL (não sentinela) de fato chegou parseado -- prova de que a Decisão 3
	-- (Default parseado por ValueType.Category) funciona de ponta a ponta.
	assert(starterPlayerSchema["AutoJumpEnabled"].Default == true, "StarterPlayer.AutoJumpEnabled deveria ter Default = true")
end)

test("Todo Generated.Schema vem congelado (table.freeze)", function()
	for className, generated in Index do
		local ok = pcall(function()
			-- Escreve um MemberDescriptor genuíno (nunca `any`) -- só interessa que a ESCRITA em
			-- si falhe, por table.freeze, não o valor escrito.
			generated.Schema["__probe_de_teste_nunca_deve_gravar__"] = { Kind = "Property", Default = nil, ReadOnly = false }
		end)
		assert(not ok, `Generated.Schema de "{className}" deveria estar table.freeze()ado`)
	end
end)

test("Object.GetPropertyChangedSignal/isA NÃO são dobradas em Instance.MethodNames (gap declarado)", function()
	local instanceMethodSet: { [string]: boolean } = {}
	for _, name in Index["Instance"].MethodNames do
		instanceMethodSet[name] = true
	end
	assert(
		instanceMethodSet["GetPropertyChangedSignal"] == nil,
		"GetPropertyChangedSignal (de Object) não deveria estar em Instance.MethodNames nesta leva"
	)
	assert(instanceMethodSet["isA"] == nil, "isA (de Object, deprecated) não deveria estar em Instance.MethodNames nesta leva")
	-- Mas IsA (de Instance, via runtime nativo) segue funcionando -- só não é redeclarado aqui
	-- porque step 3 do __index (métodos base) já resolve, ver ClassBuilder/Instance.luau.
end)

test("Instance.Schema dobra Property/Event de Object (ClassName/className/Changed)", function()
	local schema = Index["Instance"].Schema
	assert(schema["ClassName"] ~= nil, "ClassName (de Object) deveria estar dobrado no schema de Instance")
	assert(schema["Changed"] ~= nil, "Changed (de Object) deveria estar dobrado no schema de Instance")
	assert(schema["className"] ~= nil, "className (alias deprecated de Object) deveria estar dobrado no schema de Instance")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
