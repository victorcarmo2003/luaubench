--!strict

--[[
	Teste da task-cli-003 (SyncRules.luau). Cobre o acceptance do board: as 5 formas suportadas de
	arquivo e as 7 de diretório, na ORDEM certa -- com teste EXPLÍCITO de que `.server.lua` não
	cai em `.lua` (e o mesmo pra `.plugin.lua`, que teria o mesmo problema) e de que
	`default.project.json` vence `init.luau`. Módulo é dados puros (sem I/O) -- roda sem fixture
	nenhum em disco.

	Roda com `lune run src/cli/SyncRules.spec.luau`.
]]

local process = require("@lune/process")
local SyncRules = require("./SyncRules")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

--------------------------------------------------------------------------------------------------
-- ClassifyFile: as 5 formas suportadas
--------------------------------------------------------------------------------------------------

test("ClassifyFile: *.server.lua/.luau -> Script, nome sem extensão", function()
	local kind, name = SyncRules.ClassifyFile("Combat.server.lua")
	assert(kind == "Script", `esperava Script, recebeu {kind}`)
	assert(name == "Combat", `esperava 'Combat', recebeu '{name}'`)

	local kind2, name2 = SyncRules.ClassifyFile("Combat.server.luau")
	assert(kind2 == "Script", `esperava Script, recebeu {kind2}`)
	assert(name2 == "Combat", `esperava 'Combat', recebeu '{name2}'`)
end)

test("ClassifyFile: *.client.lua/.luau -> LocalScript, nome sem extensão", function()
	local kind, name = SyncRules.ClassifyFile("Combat.client.lua")
	assert(kind == "LocalScript", `esperava LocalScript, recebeu {kind}`)
	assert(name == "Combat", `esperava 'Combat', recebeu '{name}'`)

	local kind2, name2 = SyncRules.ClassifyFile("Combat.client.luau")
	assert(kind2 == "LocalScript", `esperava LocalScript, recebeu {kind2}`)
	assert(name2 == "Combat", `esperava 'Combat', recebeu '{name2}'`)
end)

test("ClassifyFile: *.lua/.luau (sobra) -> ModuleScript, nome sem extensão", function()
	local kind, name = SyncRules.ClassifyFile("Utils.lua")
	assert(kind == "ModuleScript", `esperava ModuleScript, recebeu {kind}`)
	assert(name == "Utils", `esperava 'Utils', recebeu '{name}'`)

	local kind2, name2 = SyncRules.ClassifyFile("Utils.luau")
	assert(kind2 == "ModuleScript", `esperava ModuleScript, recebeu {kind2}`)
	assert(name2 == "Utils", `esperava 'Utils', recebeu '{name2}'`)
end)

test("ClassifyFile: *.project.json/.jsonc -> NestedProject, nome sem extensão", function()
	local kind, name = SyncRules.ClassifyFile("Vendor.project.json")
	assert(kind == "NestedProject", `esperava NestedProject, recebeu {kind}`)
	assert(name == "Vendor", `esperava 'Vendor', recebeu '{name}'`)

	local kind2, name2 = SyncRules.ClassifyFile("Vendor.project.jsonc")
	assert(kind2 == "NestedProject", `esperava NestedProject, recebeu {kind2}`)
	assert(name2 == "Vendor", `esperava 'Vendor', recebeu '{name2}'`)
end)

test("ClassifyFile: *.meta.json/.jsonc -> MetaFile (não é Instance), nome do irmão", function()
	local kind, name = SyncRules.ClassifyFile("Utils.meta.json")
	assert(kind == "MetaFile", `esperava MetaFile, recebeu {kind}`)
	assert(name == "Utils", `esperava 'Utils', recebeu '{name}'`)

	local kind2, name2 = SyncRules.ClassifyFile("Utils.meta.jsonc")
	assert(kind2 == "MetaFile", `esperava MetaFile, recebeu {kind2}`)
	assert(name2 == "Utils", `esperava 'Utils', recebeu '{name2}'`)
end)

--------------------------------------------------------------------------------------------------
-- ClassifyFile: ORDEM -- primeira regra que casa vence (teste explícito do board)
--------------------------------------------------------------------------------------------------

test("ClassifyFile: '.server.lua' NÃO cai no match genérico '.lua' (ordem é significativa)", function()
	local kind = SyncRules.ClassifyFile("Combat.server.lua")
	-- Ordem dos dois asserts É significativa pro TYPECHECKER (não só pro teste): `assert(kind ==
	-- "Script", ...)` faria o luau-lsp ESTREITAR `kind` pro literal "Script" dali em diante, e um
	-- `kind ~= "ModuleScript"` DEPOIS disso vira comparação entre dois literais disjuntos (erro de
	-- tipo "Script" cannot be compared with "ModuleScript") -- por isso o `~=` (que só EXCLUI um
	-- membro da união, sem colapsar pro literal) vem primeiro.
	assert(kind ~= "ModuleScript", "'.server.lua' NUNCA deveria virar ModuleScript")
	assert(kind == "Script", `'.server.lua' deveria casar ANTES de '.lua' genérico -- recebeu {kind}`)
end)

test("ClassifyFile: '.client.luau' NÃO cai no match genérico '.luau'", function()
	local kind = SyncRules.ClassifyFile("Combat.client.luau")
	assert(kind ~= "ModuleScript", "'.client.luau' NUNCA deveria virar ModuleScript")
	assert(kind == "LocalScript", `'.client.luau' deveria casar ANTES de '.luau' genérico -- recebeu {kind}`)
end)

test("ClassifyFile: '.plugin.lua' NÃO cai no match genérico '.lua' (mesmo risco de ordem)", function()
	local kind = SyncRules.ClassifyFile("Tool.plugin.lua")
	assert(kind ~= "ModuleScript", "'.plugin.lua' NUNCA deveria virar ModuleScript")
	assert(kind == "Unsupported", `'.plugin.lua' deveria casar ANTES de '.lua' genérico -- recebeu {kind}`)
end)

test("ClassifyFile: '.meta.json' NÃO cai no match genérico '.json' (viraria Unsupported por engano)", function()
	local kind = SyncRules.ClassifyFile("Utils.meta.json")
	assert(kind == "MetaFile", `'.meta.json' deveria casar ANTES de '.json' genérico -- recebeu {kind}`)
end)

test("ClassifyFile: '.project.json' NÃO cai no match genérico '.json'", function()
	local kind = SyncRules.ClassifyFile("Vendor.project.json")
	assert(kind == "NestedProject", `'.project.json' deveria casar ANTES de '.json' genérico -- recebeu {kind}`)
end)

test("ClassifyFile: '.model.json' NÃO cai no match genérico '.json' (os dois são Unsupported, mas por regras distintas)", function()
	local kind = SyncRules.ClassifyFile("Item.model.json")
	assert(kind == "Unsupported", `esperava Unsupported, recebeu {kind}`)
end)

--------------------------------------------------------------------------------------------------
-- ClassifyFile: fora da leva 1 -> Unsupported (reconhecido e reportável)
--------------------------------------------------------------------------------------------------

test("ClassifyFile: extensões fora da leva 1 (reconhecidas pelo Rojo) -> Unsupported", function()
	local unsupportedNames = {
		"Tool.plugin.lua",
		"Tool.plugin.luau",
		"Item.model.json",
		"Item.model.jsonc",
		"raw.json",
		"raw.jsonc",
		"config.toml",
		"locale.csv",
		"notes.txt",
		"thing.yml",
		"thing.yaml",
		"Model.rbxm",
		"Model.rbxmx",
	}
	for _, fileName in unsupportedNames do
		local kind = SyncRules.ClassifyFile(fileName)
		assert(kind == "Unsupported", `'{fileName}' deveria ser Unsupported, recebeu {kind}`)
	end
end)

--------------------------------------------------------------------------------------------------
-- ClassifyFile: extensão totalmente desconhecida -> Ignored (fora do radar, NUNCA "Unsupported")
--------------------------------------------------------------------------------------------------

test("ClassifyFile: extensão não reconhecida pela tabela do Rojo -> Ignored (não é 'Unsupported')", function()
	local kind, name = SyncRules.ClassifyFile("readme.md")
	assert(kind == "Ignored", `extensão desconhecida deveria ser 'Ignored', recebeu {kind}`)
	assert(name == "readme.md", "'Ignored' deveria devolver o fileName completo (nenhuma extensão reconhecida pra cortar)")
end)

test("ClassifyFile: nome sem NENHUMA extensão -> Ignored", function()
	local kind = SyncRules.ClassifyFile("Makefile")
	assert(kind == "Ignored", `arquivo sem extensão deveria ser 'Ignored', recebeu {kind}`)
end)

--------------------------------------------------------------------------------------------------
-- ClassifyDir: as 7 formas, na ordem certa
--------------------------------------------------------------------------------------------------

test("ClassifyDir: default.project.json dentro -> NestedProject, vence TUDO (teste explícito do board)", function()
	local kind, initFile = SyncRules.ClassifyDir("Vendor", { "default.project.json", "init.luau", "Extra.lua" })
	assert(kind == "NestedProject", `default.project.json deveria vencer init.luau -- recebeu {kind}`)
	assert(initFile == "default.project.json", `initFile deveria ser 'default.project.json', recebeu '{initFile}'`)
end)

test("ClassifyDir: default.project.jsonc dentro -> NestedProject, vence init.server.luau também", function()
	local kind, initFile = SyncRules.ClassifyDir("Vendor", { "default.project.jsonc", "init.server.luau" })
	assert(kind == "NestedProject", `default.project.jsonc deveria vencer init.server.luau -- recebeu {kind}`)
	assert(initFile == "default.project.jsonc", `initFile deveria ser 'default.project.jsonc', recebeu '{initFile}'`)
end)

test("ClassifyDir: init.luau (sem default.project.json) -> ModuleScript", function()
	local kind, initFile = SyncRules.ClassifyDir("Modules", { "init.luau", "Sub.lua" })
	assert(kind == "ModuleScript", `esperava ModuleScript, recebeu {kind}`)
	assert(initFile == "init.luau", `initFile deveria ser 'init.luau', recebeu '{initFile}'`)
end)

test("ClassifyDir: init.lua -> ModuleScript", function()
	local kind, initFile = SyncRules.ClassifyDir("Modules", { "init.lua" })
	assert(kind == "ModuleScript", `esperava ModuleScript, recebeu {kind}`)
	assert(initFile == "init.lua", `initFile deveria ser 'init.lua', recebeu '{initFile}'`)
end)

test("ClassifyDir: init.server.luau -> Script", function()
	local kind, initFile = SyncRules.ClassifyDir("Main", { "init.server.luau" })
	assert(kind == "Script", `esperava Script, recebeu {kind}`)
	assert(initFile == "init.server.luau", `initFile deveria ser 'init.server.luau', recebeu '{initFile}'`)
end)

test("ClassifyDir: init.server.lua -> Script", function()
	local kind, initFile = SyncRules.ClassifyDir("Main", { "init.server.lua" })
	assert(kind == "Script", `esperava Script, recebeu {kind}`)
	assert(initFile == "init.server.lua", `initFile deveria ser 'init.server.lua', recebeu '{initFile}'`)
end)

test("ClassifyDir: init.client.luau -> LocalScript", function()
	local kind, initFile = SyncRules.ClassifyDir("Ui", { "init.client.luau" })
	assert(kind == "LocalScript", `esperava LocalScript, recebeu {kind}`)
	assert(initFile == "init.client.luau", `initFile deveria ser 'init.client.luau', recebeu '{initFile}'`)
end)

test("ClassifyDir: init.client.lua -> LocalScript", function()
	local kind, initFile = SyncRules.ClassifyDir("Ui", { "init.client.lua" })
	assert(kind == "LocalScript", `esperava LocalScript, recebeu {kind}`)
	assert(initFile == "init.client.lua", `initFile deveria ser 'init.client.lua', recebeu '{initFile}'`)
end)

test("ClassifyDir: init.plugin.lua/.luau -> Unsupported", function()
	local kind, initFile = SyncRules.ClassifyDir("Plugin", { "init.plugin.lua" })
	assert(kind == "Unsupported", `esperava Unsupported, recebeu {kind}`)
	assert(initFile == "init.plugin.lua", `initFile deveria ser 'init.plugin.lua', recebeu '{initFile}'`)

	local kind2, initFile2 = SyncRules.ClassifyDir("Plugin", { "init.plugin.luau" })
	assert(kind2 == "Unsupported", `esperava Unsupported, recebeu {kind2}`)
	assert(initFile2 == "init.plugin.luau", `initFile deveria ser 'init.plugin.luau', recebeu '{initFile2}'`)
end)

test("ClassifyDir: init.csv -> Unsupported", function()
	local kind, initFile = SyncRules.ClassifyDir("Locale", { "init.csv" })
	assert(kind == "Unsupported", `esperava Unsupported, recebeu {kind}`)
	assert(initFile == "init.csv", `initFile deveria ser 'init.csv', recebeu '{initFile}'`)
end)

test("ClassifyDir: nenhuma das regras de init/projeto -> Folder", function()
	local kind, initFile = SyncRules.ClassifyDir("Assets", { "Sword.lua", "Shield.lua" })
	assert(kind == "Folder", `esperava Folder, recebeu {kind}`)
	assert(initFile == nil, "Folder não deveria ter um 'arquivo init'")
end)

test("ClassifyDir: pasta vazia -> Folder", function()
	local kind, initFile = SyncRules.ClassifyDir("Empty", {})
	assert(kind == "Folder", `pasta vazia deveria ser Folder, recebeu {kind}`)
	assert(initFile == nil, "Folder não deveria ter um 'arquivo init'")
end)

--------------------------------------------------------------------------------------------------
-- ClassifyDir: prioridade entre init.* concorrentes (a pasta nunca deveria ter os dois na
-- prática, mas a ordem fixa do Rojo real ainda precisa estar correta caso aconteça)
--------------------------------------------------------------------------------------------------

test("ClassifyDir: init.luau vence init.server.luau quando os dois coexistem (ordem fixa do Rojo)", function()
	local kind = SyncRules.ClassifyDir("Weird", { "init.luau", "init.server.luau" })
	assert(kind == "ModuleScript", `init.luau deveria vencer init.server.luau -- recebeu {kind}`)
end)

test("ClassifyDir: init.server.luau vence init.client.luau quando os dois coexistem", function()
	local kind = SyncRules.ClassifyDir("Weird", { "init.server.luau", "init.client.luau" })
	assert(kind == "Script", `init.server.luau deveria vencer init.client.luau -- recebeu {kind}`)
end)

--------------------------------------------------------------------------------------------------
-- InferFixedChildClassName -- CORREÇÃO task-cli-014 (pesquisa-formato-projeto-rojo-2026-09-05.md,
-- seção "Correção 2026-09-05"): ramos 2 e 3 (hardcoded) de `infer_class_name` do Rojo real --
-- StarterPlayer->{StarterPlayerScripts, StarterCharacterScripts} e Workspace->Terrain. Ramo 1
-- (DataModel->Service, dinâmico) NÃO é coberto aqui -- fica em TreePlanner.spec.luau, porque
-- depende de `options.IsServiceClass` injetada.
--------------------------------------------------------------------------------------------------

test("InferFixedChildClassName: StarterPlayer -> StarterPlayerScripts (par fixo confirmado)", function()
	local className = SyncRules.InferFixedChildClassName("StarterPlayer", "StarterPlayerScripts")
	assert(className == "StarterPlayerScripts", `esperava 'StarterPlayerScripts', recebeu '{className}'`)
end)

test("InferFixedChildClassName: StarterPlayer -> StarterCharacterScripts (par fixo confirmado)", function()
	local className = SyncRules.InferFixedChildClassName("StarterPlayer", "StarterCharacterScripts")
	assert(className == "StarterCharacterScripts", `esperava 'StarterCharacterScripts', recebeu '{className}'`)
end)

test("InferFixedChildClassName: Workspace -> Terrain (par fixo confirmado)", function()
	local className = SyncRules.InferFixedChildClassName("Workspace", "Terrain")
	assert(className == "Terrain", `esperava 'Terrain', recebeu '{className}'`)
end)

test("InferFixedChildClassName: nome que NÃO é filho fixo do pai reconhecido -> nil", function()
	assert(SyncRules.InferFixedChildClassName("StarterPlayer", "Terrain") == nil, "'Terrain' não é filho fixo de StarterPlayer")
	assert(SyncRules.InferFixedChildClassName("Workspace", "StarterPlayerScripts") == nil, "'StarterPlayerScripts' não é filho fixo de Workspace")
	assert(SyncRules.InferFixedChildClassName("StarterPlayer", "Foo") == nil, "'Foo' não é filho fixo de nada")
end)

test("InferFixedChildClassName: parentClassName não reconhecido (nem StarterPlayer nem Workspace) -> nil, mesmo com nome coincidente", function()
	assert(SyncRules.InferFixedChildClassName("DataModel", "Terrain") == nil, "ramo DataModel->Service NÃO é resolvido por esta função (fica em TreePlanner, dinâmico)")
	assert(SyncRules.InferFixedChildClassName("Folder", "Terrain") == nil, "'Folder' não é um dos dois pais hardcoded reconhecidos")
	assert(SyncRules.InferFixedChildClassName("Teams", "AnyTeam") == nil, "'Teams' não tem filho fixo no Rojo real (confirmado exaustivo na pesquisa)")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
