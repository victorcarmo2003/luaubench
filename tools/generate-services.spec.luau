--!strict

--[[
	Teste da task-services-002 (leva 1), ESTENDIDO por task-services-017 (leva 2 -- as 16 classes
	de DataStoreService entraram em tools/coverage.luau, ver L2.1.7), por task-services-022
	(`HttpService`/`MessagingService`, L2.2/L2.3), por task-services-023 (`PhysicsService`, L2.5.1),
	por task-services-025 (`SoundService`, L2.5.3) e por task-services-019-fix (`DataStoreKey`,
	entrada MANUAL de coverage.luau -- ver o comentário lá): verifica os FATOS que
	`lune run tools/generate-services` deve produzir em `src/services/generated/` -- não roda o
	gerador (que baixa/lê o dump e pode demorar e depende de rede na ausência de cache), só
	INSPECIONA a saída já commitada. Rode `lune run tools/generate-services` antes desta suíte
	sempre que `tools/coverage.luau`, `tools/api-dump.lock.json` ou `tools/capabilities.lock.json`
	mudarem -- e, ao fazê-lo, os números fixos abaixo (tamanho do fecho, total de métodos) mudam
	JUNTO: são uma FOTOGRAFIA da saída atual do gerador, não uma constante do projeto -- cada leva
	que adiciona classe a `coverage.luau` precisa atualizar os números aqui, mesma disciplina de
	`CLOSED_NEVER_LEGITIMATE`/`COVERED_CLASSES` em `src/services/init.spec.luau`/
	`Integration.spec.luau`.

	Cobre os números exatos do acceptance de task-services-002 + task-services-017 +
	task-services-022 + task-services-023 + task-services-025 + task-services-019-fix:
	- Manifest.luau com exatamente 916 entradas (as 916 classes do dump -- não muda entre levas)
	- fecho de 45 classes: as 24 da leva 1 (task-services-002 -- as 20 de tools/coverage.luau +
	  WorldRoot/Model/PVInstance/BasePlayerGui, puxadas por herança sem estarem listadas em
	  coverage.luau) + as 16 de DataStoreService da leva 2 (task-services-017 -- todas listadas
	  EXPLICITAMENTE em coverage.luau, nenhuma puxada por herança desta vez: L2.1.7 confirma que
	  nenhuma tem superclasse fora da lista, exceto `Pages`, que já está listada) + as 2 de
	  task-services-022 (`HttpService`/`MessagingService` -- as duas terminam em `Instance` direto
	  no dump, nenhuma puxa classe nova pelo fecho de superclasses) + 1 de task-services-023
	  (`PhysicsService` -- idem, `Instance` direto) + 1 de task-services-025 (`SoundService` --
	  idem, `Instance` direto, ver L2.5.3) + 1 de task-services-019-fix (`DataStoreKey` -- entrada
	  MANUAL de coverage.luau, `Instance` direto no dump, mas NUNCA seria descoberta pelo fecho
	  automático -- ver o comentário de coverage.luau, "task-services-019-fix", para o porquê)
	- exatamente 4 membros de schema excluídos pelo eixo Capabilities na leva 1 (Script.Source,
	  ModuleScript.Source, RunService.Misprediction, RunService.FrameNumber) -- nem a leva 2 nem
	  task-services-022/023/025 acrescentam exclusão nova por este eixo (pesquisa-datastore-
	  2026-09-05.md, seção A, e pesquisa-http-messaging-2026-09-05.md, seção A: `HttpService`/
	  `MessagingService` não têm membro excluído por Capability -- `Network`/`ServerCommunication`
	  são grantable; `PhysicsService`/`SoundService` idem, ver pesquisa-lighting-sound-physics-
	  2026-09-05.md) fora de `DataStoreService.AutomaticRetry`/`LegacyNamingScheme`, que são
	  `Property`, não afetam esta contagem de MÉTODOS -- ver teste dedicado abaixo)
	- 201 métodos emitidos no total no fecho (171 até task-services-017 + 9 de `HttpService` +
	  2 de `MessagingService`, task-services-022 (182) + 15 de `PhysicsService` (8 de grupo de
	  colisão + 7 `Deprecated`), task-services-023 (197) + 4 de `SoundService` (`GetListener`/
	  `SetListener`/`GetMixerTime`/`PlayLocalSound`), task-services-025 -- conferido por inspeção
	  direta do `Index` gerado)
	- Lighting/Players/StarterPlayer com schema COMPLETO (nenhuma exclusão por Capability -- prova
	  de que a regra ingênua "capability != Basic é restritiva" não foi implementada)
	- RunService.Heartbeat/Stepped/RenderStepped/PreRender continuam no schema
	- Generated.Schema vem sempre congelado (table.freeze)
	- DataStoreService.AutomaticRetry/LegacyNamingScheme (LocalUserSecurity) ficam FORA do schema
	  -- único filtro de Security/Capabilities que a leva 2 introduz (task-services-017)
	- HttpService.HttpEnabled semeada Default=false/ReadOnly=true (task-services-022, L2.2.1)

	Roda com `lune run tools/generate-services.spec.luau`.
]]

local process = require("@lune/process")

local Manifest = require("../src/services/generated/Manifest")
local Index = require("../src/services/generated/Index")
local ValueTypes = require("../src/valuetypes")

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

test("O fecho tem exatamente 45 classes (24 da leva 1 + 16 de DataStoreService da leva 2 + 2 de HttpService/MessagingService (task-services-022) + 1 de PhysicsService (task-services-023) + 1 de SoundService (task-services-025) + 1 de DataStoreKey (task-services-019-fix))", function()
	local expected = {
		-- Leva 1 (task-services-002) -- 24 classes, 4 delas (WorldRoot/Model/PVInstance/
		-- BasePlayerGui) puxadas por herança sem estarem em coverage.luau (ver prova abaixo).
		"BasePlayerGui", "BaseScript", "Folder", "Instance", "Lighting", "LocalScript",
		"LuaSourceContainer", "Model", "ModuleScript", "PVInstance", "Players", "ReplicatedFirst",
		"ReplicatedStorage", "RunService", "Script", "ServerScriptService", "ServerStorage",
		"StarterCharacterScripts", "StarterGui", "StarterPack", "StarterPlayer",
		"StarterPlayerScripts", "Workspace", "WorldRoot",
		-- Leva 2 (task-services-017, L2.1.7) -- 16 classes de DataStoreService, TODAS listadas
		-- explicitamente em coverage.luau (nenhuma puxada por herança desta vez).
		"DataStoreService", "GlobalDataStore", "DataStore", "OrderedDataStore", "DataStoreKeyInfo",
		"DataStoreSetOptions", "DataStoreOptions", "DataStoreGetOptions", "DataStoreIncrementOptions",
		"Pages", "DataStorePages", "DataStoreKeyPages", "DataStoreListingPages",
		"DataStoreVersionPages", "DataStoreObjectVersionInfo", "DataStoreInfo",
		-- task-services-022 (L2.2/L2.3) -- 2 classes, ambas terminam em "Instance" direto no dump.
		"HttpService", "MessagingService",
		-- task-services-023 (L2.5.1) -- 1 classe, listada explicitamente em coverage.luau.
		"PhysicsService",
		-- task-services-025 (L2.5.3) -- 1 classe, "Instance" direto no dump, listada
		-- explicitamente em coverage.luau, nenhuma classe nova puxada pelo fecho.
		"SoundService",
		-- task-services-019-fix -- 1 classe, "Instance" direto no dump, entrada MANUAL de
		-- coverage.luau (o fecho automático NUNCA a descobriria sozinho -- ver o comentário de
		-- coverage.luau, "task-services-019-fix").
		"DataStoreKey",
	}
	local indexCount = 0
	for _ in Index do
		indexCount += 1
	end
	assert(#expected == 45, `sanity check da própria lista 'expected' deste teste -- deveria ter 45 nomes, tem {#expected}`)
	assert(indexCount == 45, `Index deveria ter 45 classes, tem {indexCount}`)
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

test(
	"task-services-017: DataStoreService.AutomaticRetry/LegacyNamingScheme ficam FORA do schema (LocalUserSecurity -- pesquisa-datastore-2026-09-05.md, seção A)",
	function()
		local dataStoreServiceSchema = Index["DataStoreService"].Schema
		assert(
			dataStoreServiceSchema["AutomaticRetry"] == nil,
			"DataStoreService.AutomaticRetry deveria estar FORA do schema (Security Read/Write = LocalUserSecurity, fora do alcance de um Script comum)"
		)
		assert(
			dataStoreServiceSchema["LegacyNamingScheme"] == nil,
			"DataStoreService.LegacyNamingScheme deveria estar FORA do schema (idem, e também Deprecated no dump)"
		)
	end
)

test("RunService.Heartbeat/Stepped/RenderStepped/PreRender continuam no schema (Capabilities=[Basic])", function()
	local schema = Index["RunService"].Schema
	for _, eventName in { "Heartbeat", "Stepped", "RenderStepped", "PreRender" } do
		local entry = schema[eventName]
		assert(entry ~= nil, `RunService.{eventName} deveria estar no schema`)
		assert(entry.Kind == "Event", `RunService.{eventName} deveria ser Kind="Event"`)
		assert(entry.ReadOnly == true, `RunService.{eventName} deveria ser ReadOnly (evento)`)
	end
end)

test("201 métodos emitidos no total no fecho (197 até task-services-023 + 4 de SoundService, task-services-025)", function()
	local total = 0
	for _, generated in Index do
		total += #generated.MethodNames
	end
	assert(total == 201, `esperava 201 métodos no total do fecho, contei {total}`)
end)

test("HttpService.HttpEnabled semeada Default=false/ReadOnly=true pelo schema gerado (task-services-022, L2.2.1)", function()
	local httpEnabled = Index["HttpService"].Schema["HttpEnabled"]
	assert(httpEnabled ~= nil, "HttpService.HttpEnabled deveria estar no schema")
	assert(httpEnabled.Kind == "Property", "HttpService.HttpEnabled deveria ser Kind=\"Property\"")
	assert(httpEnabled.Default == false, `HttpService.HttpEnabled.Default deveria ser false, recebeu {tostring(httpEnabled.Default)}`)
	assert(httpEnabled.ReadOnly == true, "HttpService.HttpEnabled deveria ser ReadOnly (Security.Write=LocalUserSecurity)")
end)

test("MessagingService não tem NENHUMA propriedade/evento no schema -- só PublishAsync/SubscribeAsync em MethodNames (task-services-022, L2.3)", function()
	local schemaCount = 0
	for _ in Index["MessagingService"].Schema do
		schemaCount += 1
	end
	assert(schemaCount == 0, `MessagingService.Schema deveria estar vazio, tem {schemaCount} entradas`)
	assert(#Index["MessagingService"].MethodNames == 2, "MessagingService.MethodNames deveria ter exatamente 2 métodos")
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

-- ================================================================================================
-- task-services-015 -- ponte com `valuetypes`: (a) ValueType/ValueCategory emitidos por Property,
-- (b) Default REAL de DataType/Enum já simulado (leva 1) em vez de nil, (c) DataType da leva 2
-- (sem módulo em src/valuetypes/types/) NUNCA ganha um Default inventado. Testes de INTEGRAÇÃO
-- contra a saída REALMENTE commitada (mesmo estilo do resto deste arquivo) -- as funções de
-- gramática do gerador (`computeDefault`/`computeDataTypeDefaultExpr`) são locais ao script
-- `tools/generate-services.luau` (não um módulo que devolve tabela), então não há como
-- importá-las isoladamente pra um teste unitário puro sem rodar o gerador de novo (que baixa/lê o
-- dump -- o mesmo motivo já documentado no cabeçalho deste arquivo pra não rodar o gerador aqui).
-- ================================================================================================

-- Os 6 DataType que já têm módulo em src/valuetypes/types/ hoje (Enum é o 7º, mas é
-- ValueCategory "Enum", testado à parte) -- espelha LEVA1_DATATYPE_ARITY/LEVA1_DATATYPE_LUAU_TYPE
-- de tools/generate-services.luau (cópia deliberada, não um require: este teste verifica o
-- CONTRATO externo -- "que nomes o gerador considera já simulados" -- não a constante interna do
-- gerador).
local LEVA1_SIMULATED_DATATYPES: { [string]: boolean } =
	{ Vector3 = true, Vector2 = true, Color3 = true, UDim = true, UDim2 = true, CFrame = true }

test("ValueType/ValueCategory aparecem em toda Property; nil nos dois pra Event/Callback", function()
	local lightingSchema = Index["Lighting"].Schema

	local brightness = lightingSchema["Brightness"]
	assert(brightness.ValueType == "float", `Brightness.ValueType esperado "float", recebeu {tostring(brightness.ValueType)}`)
	assert(
		brightness.ValueCategory == "Primitive",
		`Brightness.ValueCategory esperado "Primitive", recebeu {tostring(brightness.ValueCategory)}`
	)

	local ambient = lightingSchema["Ambient"]
	assert(ambient.ValueType == "Color3", `Ambient.ValueType esperado "Color3", recebeu {tostring(ambient.ValueType)}`)
	assert(
		ambient.ValueCategory == "DataType",
		`Ambient.ValueCategory esperado "DataType", recebeu {tostring(ambient.ValueCategory)}`
	)

	local lightingStyle = lightingSchema["LightingStyle"]
	assert(
		lightingStyle.ValueType == "LightingStyle",
		`LightingStyle.ValueType esperado "LightingStyle", recebeu {tostring(lightingStyle.ValueType)}`
	)
	assert(
		lightingStyle.ValueCategory == "Enum",
		`LightingStyle.ValueCategory esperado "Enum", recebeu {tostring(lightingStyle.ValueCategory)}`
	)

	local camera = Index["Workspace"].Schema["CurrentCamera"]
	assert(camera.ValueType == "Camera", `CurrentCamera.ValueType esperado "Camera", recebeu {tostring(camera.ValueType)}`)
	assert(
		camera.ValueCategory == "Class",
		`CurrentCamera.ValueCategory esperado "Class", recebeu {tostring(camera.ValueCategory)}`
	)

	local lightingChanged = lightingSchema["LightingChanged"]
	assert(lightingChanged.Kind == "Event", "LightingChanged deveria ser Kind=\"Event\" (sanity do próprio teste)")
	assert(lightingChanged.ValueType == nil, "Event não tem ValueType -- deveria ser nil")
	assert(lightingChanged.ValueCategory == nil, "Event não tem ValueCategory -- deveria ser nil")
end)

test("Color3: Lighting.Ambient/FogColor ganham Default REAL (deixaram de ser nil)", function()
	local schema = Index["Lighting"].Schema

	local ambient = schema["Ambient"].Default
	assert(ambient ~= nil, "Lighting.Ambient.Default não deveria mais ser nil")
	assert(
		ValueTypes.TypeNameOf(ambient) == "Color3",
		`Lighting.Ambient.Default deveria ser um Color3, TypeNameOf devolveu {tostring(ValueTypes.TypeNameOf(ambient))}`
	)
	-- `ambient`/`fogColor` chegam tipados `unknown` (Runtime.MemberDescriptor.Default) -- cast
	-- explícito pro tipo opaco real ANTES de comparar (`unknown == Color3` não tipa: Luau exige
	-- metatable compatível dos dois lados do `==`, mesma disciplina de `Userdata.Unwrap`/
	-- `Decode.asStringIndexable`, nunca `any`).
	assert(
		(ambient :: ValueTypes.Color3) == ValueTypes.Color3.new(0.5, 0.5, 0.5),
		"Lighting.Ambient.Default deveria ser Color3.new(0.5, 0.5, 0.5) (grafia real do dump: \"0.5, 0.5, 0.5\")"
	)

	local fogColor = schema["FogColor"].Default
	assert(
		(fogColor :: ValueTypes.Color3) == ValueTypes.Color3.new(0.75, 0.75, 0.75),
		"Lighting.FogColor.Default deveria ser Color3.new(0.75, 0.75, 0.75)"
	)
end)

test("CFrame: Model.WorldPivot ganha Default REAL (identidade, 12 componentes do dump)", function()
	local worldPivot = Index["Model"].Schema["WorldPivot"].Default
	assert(worldPivot ~= nil, "Model.WorldPivot.Default não deveria mais ser nil")
	assert(
		ValueTypes.TypeNameOf(worldPivot) == "CFrame",
		`Model.WorldPivot.Default deveria ser um CFrame, TypeNameOf devolveu {tostring(ValueTypes.TypeNameOf(worldPivot))}`
	)
	assert(
		(worldPivot :: ValueTypes.CFrame) == ValueTypes.CFrame.identity,
		"Model.WorldPivot.Default deveria ser a CFrame identidade (dump: \"0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1\")"
	)
end)

test("Enum: Lighting.LightingStyle ganha Default REAL (EnumItem pelo NOME do item)", function()
	local lightingStyle = Index["Lighting"].Schema["LightingStyle"].Default
	assert(lightingStyle ~= nil, "Lighting.LightingStyle.Default não deveria mais ser nil")
	assert(
		ValueTypes.TypeNameOf(lightingStyle) == "EnumItem",
		`Lighting.LightingStyle.Default deveria ser um EnumItem, TypeNameOf devolveu {tostring(ValueTypes.TypeNameOf(lightingStyle))}`
	)
	-- `ValueTypes.Enum` (o global "Enum" do Roblox real) é um datatype OPACO por desenho -- não tem
	-- indexador estático por nome de enum (mesmo motivo de `Decode.luau:asStringIndexable`: existem
	-- itens de enum literalmente chamados "Name"/"Value"). Resolve pelo mesmo
	-- `ValueTypes.Decode.FromRojoJson` que o PRÓPRIO gerador usa em tempo de execução pra este
	-- exato par (nome do enum, nome do item) -- não reimplementa aqui uma segunda forma de indexar.
	local expected = ValueTypes.Decode.FromRojoJson("LightingStyle", "Enum", "Realistic")
	assert(expected.Ok, "sanity check do teste -- Decode.FromRojoJson deveria resolver Enum.LightingStyle.Realistic")
	assert(lightingStyle == expected.Value, "Lighting.LightingStyle.Default deveria ser Enum.LightingStyle.Realistic")

	-- Outra classe/enum, pra provar que não é um caso isolado hard-coded: StarterPlayer tem 6
	-- Enum com Default real (ver relatório do gerador, "Defaults REAIS ... ponte com valuetypes").
	local cameraMode = Index["StarterPlayer"].Schema["CameraMode"].Default
	local expectedCameraMode = ValueTypes.Decode.FromRojoJson("CameraMode", "Enum", "Classic")
	assert(expectedCameraMode.Ok, "sanity check do teste -- Decode.FromRojoJson deveria resolver Enum.CameraMode.Classic")
	assert(
		cameraMode == expectedCameraMode.Value,
		"StarterPlayer.CameraMode.Default deveria ser Enum.CameraMode.Classic"
	)
end)

test("Sentinela em DataType/Enum já simulado continua nil -- ValueType/ValueCategory continuam preenchidos", function()
	-- Workspace.GlobalWind: ValueType Vector3 (já simulado), mas o dump não serializa um Default
	-- utilizável pra este membro (sentinela) -- prova de que "categoria simulada" não força um
	-- Default fabricado quando a FORMA do dump não é a esperada.
	local globalWind = Index["Workspace"].Schema["GlobalWind"]
	assert(globalWind.ValueType == "Vector3", `GlobalWind.ValueType esperado "Vector3", recebeu {tostring(globalWind.ValueType)}`)
	assert(globalWind.ValueCategory == "DataType", "GlobalWind.ValueCategory esperado \"DataType\"")
	assert(globalWind.Default == nil, "GlobalWind.Default deveria continuar nil (sentinela no dump, não \"x, y, z\")")

	-- Workspace.ClientAnimatorThrottling: Enum sentinela -- mesma prova do lado Enum.
	local throttling = Index["Workspace"].Schema["ClientAnimatorThrottling"]
	assert(throttling.ValueCategory == "Enum", "ClientAnimatorThrottling.ValueCategory esperado \"Enum\"")
	assert(throttling.Default == nil, "ClientAnimatorThrottling.Default deveria continuar nil (sentinela no dump)")
end)

test(
	"DataType da leva 2 (sem módulo em src/valuetypes/types/) NUNCA ganha Default inventado, em NENHUMA classe do fecho",
	function()
		local checked = 0
		for className, generated in Index do
			for memberName, descriptor in generated.Schema do
				if descriptor.ValueCategory == "DataType" and descriptor.ValueType ~= nil then
					checked += 1
					if not LEVA1_SIMULATED_DATATYPES[descriptor.ValueType] then
						assert(
							descriptor.Default == nil,
							`{className}.{memberName} (DataType leva 2, "{descriptor.ValueType}") deveria ter Default nil, tem {typeof(
								descriptor.Default
							)}`
						)
					end
				end
			end
		end
		assert(checked > 0, "sanity check do próprio teste -- deveria ter encontrado ao menos uma Property DataType no fecho")
	end
)

-- ================================================================================================
-- task-services-019-fix -- `DataStoreKey` foi acrescentado À MÃO a tools/coverage.luau (nunca seria
-- descoberto pelo fecho automático, ver o comentário lá). Teste dedicado: schema mínimo (só
-- `KeyName`, ReadOnly, ValueType "string"/Primitive), classe abstrata (`NotCreatable` no dump), sem
-- MethodNames -- consumido por `src/services/behavior/DataStore.luau` (`ListKeysAsync`).
-- ================================================================================================

test("DataStoreKey: schema mínimo com KeyName (ReadOnly, Primitive string), IsAbstract, sem MethodNames", function()
	local generated = Index["DataStoreKey"]
	assert(generated ~= nil, "DataStoreKey deveria estar no Index (entrada manual de coverage.luau)")
	assert(generated.Superclass == "Instance", `DataStoreKey.Superclass esperado "Instance", recebeu {generated.Superclass}`)
	assert(generated.IsAbstract == true, "DataStoreKey deveria ser IsAbstract (NotCreatable no dump)")
	assert(generated.IsService == false, "DataStoreKey não é um Service")

	local schemaCount = 0
	for _ in generated.Schema do
		schemaCount += 1
	end
	assert(schemaCount == 1, `DataStoreKey.Schema deveria ter exatamente 1 entrada (KeyName), tem {schemaCount}`)

	local keyName = generated.Schema["KeyName"]
	assert(keyName ~= nil, "DataStoreKey.Schema deveria conter KeyName")
	assert(keyName.Kind == "Property", `KeyName.Kind esperado "Property", recebeu {keyName.Kind}`)
	assert(keyName.ReadOnly == true, "KeyName deveria ser ReadOnly (tag ReadOnly no dump)")
	assert(keyName.ValueType == "string", `KeyName.ValueType esperado "string", recebeu {tostring(keyName.ValueType)}`)
	assert(keyName.ValueCategory == "Primitive", `KeyName.ValueCategory esperado "Primitive", recebeu {tostring(keyName.ValueCategory)}`)

	assert(#generated.MethodNames == 0, `DataStoreKey.MethodNames deveria estar vazio, tem {#generated.MethodNames}`)
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
