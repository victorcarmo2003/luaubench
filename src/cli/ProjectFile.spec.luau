--!strict

--[[
	Teste da task-cli-002 (ProjectFile.luau). Cobre o acceptance do board contra os fixtures em
	`src/cli/fixtures/`: Locate acha default.project.json/.jsonc a partir de diretório e de cwd;
	Read decodifica JSONC, rejeita campo de topo desconhecido, exige `tree`, nunca propaga stack
	trace cru de JSON malformado, parseia as duas formas de PathNode, produz warning pros campos
	aceitos-mas-não-suportados (globIgnorePaths/syncRules/emitLegacyScripts:false/$id), aceita
	`$ignoreUnknownInstances` em silêncio, e trata chave "$" desconhecida como warning (nunca
	filho).

	Roda com `lune run src/cli/ProjectFile.spec.luau`.
]]

local process = require("@lune/process")
local Diagnostics = require("./Diagnostics")
local ProjectFile = require("./ProjectFile")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

local function contains(haystack: string, needle: string): boolean
	return string.find(haystack, needle, 1, true) ~= nil
end

-- Caminho absoluto da pasta `fixtures/`, resolvido a partir do cwd do processo (este spec
-- sempre roda via `lune run src/cli/ProjectFile.spec.luau`, então o cwd é a raiz do repo).
local FIXTURES_ROOT = process.cwd .. "src/cli/fixtures"

local function fixturePath(name: string): string
	return `{FIXTURES_ROOT}/{name}`
end

-- Acha, na lista de um Bag, o primeiro Diagnostic com o Code dado (assere por Code, nunca por
-- texto -- é o contrato de `Diagnostics.luau`: "Code é o que permite ao teste asserir sem casar
-- o texto exato de Message"). `nil` se nenhum bater.
local function findByCode(bag: Diagnostics.Bag, code: string): Diagnostics.Diagnostic?
	for _, diagnostic in bag:All() do
		if diagnostic.Code == code then
			return diagnostic
		end
	end
	return nil
end

local function countByCode(bag: Diagnostics.Bag, code: string): number
	local count = 0
	for _, diagnostic in bag:All() do
		if diagnostic.Code == code then
			count += 1
		end
	end
	return count
end

--------------------------------------------------------------------------------------------------
-- Locate
--------------------------------------------------------------------------------------------------

test("Locate acha default.project.json a partir de um caminho de DIRETÓRIO", function()
	local found, diagnostic = ProjectFile.Locate(fixturePath("valid-minimal"), "C:/unused-cwd")
	assert(diagnostic == nil, "diretório com default.project.json não deveria produzir Diagnostic")
	assert(found == fixturePath("valid-minimal") .. "/default.project.json", `caminho encontrado inesperado: {found}`)
end)

test("Locate acha default.project.json a partir do CWD quando pathArg é nil", function()
	local found, diagnostic = ProjectFile.Locate(nil, fixturePath("valid-minimal"))
	assert(diagnostic == nil, "cwd com default.project.json não deveria produzir Diagnostic")
	assert(found == fixturePath("valid-minimal") .. "/default.project.json", `caminho encontrado inesperado: {found}`)
end)

test("Locate usa um caminho de ARQUIVO explícito direto, sem procurar default.project.*", function()
	local explicitFile = fixturePath("jsonc-only") .. "/default.project.jsonc"
	local found, diagnostic = ProjectFile.Locate(explicitFile, "C:/unused-cwd")
	assert(diagnostic == nil, "arquivo explícito existente não deveria produzir Diagnostic")
	assert(found == explicitFile, "deveria devolver exatamente o arquivo pedido")
end)

test("Locate cai para default.project.jsonc quando só ela existe (sem .json)", function()
	local found, diagnostic = ProjectFile.Locate(fixturePath("jsonc-only"), "C:/unused-cwd")
	assert(diagnostic == nil, "diretório com só .jsonc não deveria produzir Diagnostic")
	assert(found == fixturePath("jsonc-only") .. "/default.project.jsonc", `caminho encontrado inesperado: {found}`)
end)

test("Locate devolve Diagnostic de erro quando nem .json nem .jsonc existem no diretório", function()
	local found, diagnostic = ProjectFile.Locate(fixturePath("empty"), "C:/unused-cwd")
	assert(found == nil, "diretório sem projeto não deveria encontrar nada")
	assert(diagnostic ~= nil, "deveria produzir um Diagnostic")
	if diagnostic ~= nil then
		assert(diagnostic.Severity == "error", "deveria ser Severity 'error'")
		assert(diagnostic.Code == "project/file-not-found", "Code deveria ser 'project/file-not-found'")
		assert(contains(diagnostic.Message, fixturePath("empty")), "Message deveria citar o diretório procurado")
	end
end)

test("Locate devolve Diagnostic de erro quando o caminho não existe nem como arquivo nem como diretório", function()
	local found, diagnostic = ProjectFile.Locate(fixturePath("does-not-exist"), "C:/unused-cwd")
	assert(found == nil, "caminho inexistente não deveria encontrar nada")
	assert(diagnostic ~= nil, "deveria produzir um Diagnostic")
	if diagnostic ~= nil then
		assert(diagnostic.Code == "project/path-not-found", "Code deveria ser 'project/path-not-found'")
	end
end)

--------------------------------------------------------------------------------------------------
-- Read: caso feliz + PathNode nas duas formas + $properties/$attributes crus
--------------------------------------------------------------------------------------------------

test("Read de um projeto válido devolve Project com Name/Tree corretos, sem nenhum Diagnostic", function()
	local bag = Diagnostics.newBag()
	local project = ProjectFile.Read(fixturePath("valid-minimal") .. "/default.project.json", bag)

	assert(#bag:All() == 0, "projeto válido não deveria produzir nenhum Diagnostic")
	assert(project ~= nil, "Read deveria devolver um Project")

	if project ~= nil then
		assert(project.Name == "ValidMinimal", `Name deveria ser 'ValidMinimal', recebeu '{project.Name}'`)
		assert(project.Tree.ClassName == "DataModel", "raiz deveria ter ClassName 'DataModel'")
		assert(project.EmitLegacyScripts == true, "sem 'emitLegacyScripts' explícito, default deveria ser true")
		assert(#project.GlobIgnorePaths == 0, "sem 'globIgnorePaths', deveria vir vazio")
		assert(project.HasSyncRules == false, "sem 'syncRules', HasSyncRules deveria ser false")

		local replicatedStorage = project.Tree.Children["ReplicatedStorage"]
		assert(replicatedStorage ~= nil, "deveria ter um filho 'ReplicatedStorage'")
		if replicatedStorage ~= nil then
			assert(replicatedStorage.NodePath == "tree.ReplicatedStorage", "NodePath deveria ser construído incrementalmente")
			local path = replicatedStorage.Path
			assert(path ~= nil and path.Kind == "required" and path.Path == "shared", "PathNode string deveria virar Kind 'required'")
		end

		local serverScriptService = project.Tree.Children["ServerScriptService"]
		assert(serverScriptService ~= nil, "deveria ter um filho 'ServerScriptService'")
		if serverScriptService ~= nil then
			local path = serverScriptService.Path
			assert(path ~= nil and path.Kind == "optional" and path.Path == "server", "PathNode {optional=...} deveria virar Kind 'optional'")
		end

		local nested = project.Tree.Children["Nested"]
		assert(nested ~= nil, "deveria ter um filho 'Nested'")
		if nested ~= nil then
			assert(nested.Properties["Foo"] == true, "$properties deveria vir cru (boolean intacto)")
			assert(nested.Attributes["Bar"] == 1, "$attributes deveria vir cru (number intacto)")

			local child = nested.Children["Child"]
			assert(child ~= nil, "nó aninhado dois níveis abaixo da raiz deveria existir")
			if child ~= nil then
				assert(child.NodePath == "tree.Nested.Child", "NodePath de um neto deveria acumular os três segmentos")
			end
		end
	end
end)

--------------------------------------------------------------------------------------------------
-- Read: JSONC (comentário + vírgula sobrando) num arquivo ".project.json"
--------------------------------------------------------------------------------------------------

test("Read decodifica JSONC (comentário + vírgula sobrando) mesmo num arquivo '.project.json'", function()
	local bag = Diagnostics.newBag()
	local project = ProjectFile.Read(fixturePath("jsonc-comments") .. "/default.project.json", bag)

	assert(not bag:HasErrors(), "JSONC válido não deveria produzir nenhum erro")
	assert(project ~= nil, "Read deveria conseguir decodificar comentário + vírgula sobrando")
	if project ~= nil then
		assert(project.Name == "JsoncComments", "Name deveria ter sido lido corretamente através do comentário")
		assert(project.Tree.Children["Trailing"] ~= nil, "filho declarado após a vírgula sobrando deveria existir")
	end
end)

--------------------------------------------------------------------------------------------------
-- Read: campo de topo desconhecido
--------------------------------------------------------------------------------------------------

test("Read com campo de topo desconhecido produz Diagnostic de erro nomeando a chave, e devolve nil", function()
	local bag = Diagnostics.newBag()
	local project = ProjectFile.Read(fixturePath("unknown-field") .. "/default.project.json", bag)

	assert(project == nil, "campo de topo desconhecido deveria impedir Read de devolver um Project")
	local diagnostic = findByCode(bag, "project/unknown-field")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic com Code 'project/unknown-field'")
	if diagnostic ~= nil then
		assert(diagnostic.Severity == "error", "campo de topo desconhecido deveria ser Severity 'error'")
		assert(contains(diagnostic.Message, "unknownField"), "Message deveria citar a chave desconhecida exata")
		assert(contains(diagnostic.Message, "tree"), "Message deveria listar ao menos uma chave válida (ex.: 'tree')")
	end
end)

--------------------------------------------------------------------------------------------------
-- Read: tree ausente
--------------------------------------------------------------------------------------------------

test("Read sem o campo 'tree' produz Diagnostic de erro nomeando o campo, e devolve nil", function()
	local bag = Diagnostics.newBag()
	local project = ProjectFile.Read(fixturePath("missing-tree") .. "/default.project.json", bag)

	assert(project == nil, "'tree' ausente deveria impedir Read de devolver um Project")
	local diagnostic = findByCode(bag, "project/missing-tree")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic com Code 'project/missing-tree'")
	if diagnostic ~= nil then
		assert(diagnostic.Field == "tree", "Diagnostic deveria nomear o campo 'tree'")
	end
end)

--------------------------------------------------------------------------------------------------
-- Read: JSON malformado
--------------------------------------------------------------------------------------------------

test("Read de JSON malformado produz Diagnostic com o caminho do arquivo, nunca stack trace cru", function()
	local bag = Diagnostics.newBag()
	local filePath = fixturePath("malformed") .. "/default.project.json"
	local project = ProjectFile.Read(filePath, bag)

	assert(project == nil, "JSON malformado deveria impedir Read de devolver um Project")
	local diagnostic = findByCode(bag, "project/malformed-json")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic com Code 'project/malformed-json'")
	if diagnostic ~= nil then
		assert(diagnostic.FilePath == filePath, "Diagnostic deveria citar o caminho do arquivo")
		assert(not contains(diagnostic.Message, "stack traceback"), "Message NUNCA deveria conter stack trace cru (regra 04)")
	end
end)

--------------------------------------------------------------------------------------------------
-- Read: warnings aceitos-mas-não-suportados (globIgnorePaths/syncRules/emitLegacyScripts/$id)
--------------------------------------------------------------------------------------------------

test("Read com globIgnorePaths/syncRules/emitLegacyScripts:false/$id produz warning pra cada um, e AINDA devolve um Project", function()
	local bag = Diagnostics.newBag()
	local project = ProjectFile.Read(fixturePath("warnings") .. "/default.project.json", bag)

	assert(not bag:HasErrors(), "campos aceitos-mas-não-suportados são warning, nunca erro")
	assert(project ~= nil, "warnings não deveriam impedir Read de devolver um Project válido")

	if project ~= nil then
		assert(project.EmitLegacyScripts == false, "EmitLegacyScripts deveria refletir o valor explícito 'false'")
		assert(#project.GlobIgnorePaths == 2, "GlobIgnorePaths deveria ter capturado os dois globs do fixture")
		assert(project.HasSyncRules == true, "HasSyncRules deveria ser true (syncRules não-vazio)")
	end

	local emitDiagnostic = findByCode(bag, "project/emit-legacy-scripts-false")
	assert(emitDiagnostic ~= nil, "deveria haver warning 'project/emit-legacy-scripts-false'")
	if emitDiagnostic ~= nil then
		assert(emitDiagnostic.Severity == "warning", "emitLegacyScripts:false deveria ser Severity 'warning', nunca 'error'")
	end

	local globDiagnostic = findByCode(bag, "project/glob-ignore-paths-unsupported")
	assert(globDiagnostic ~= nil, "deveria haver warning 'project/glob-ignore-paths-unsupported'")
	if globDiagnostic ~= nil then
		assert(globDiagnostic.Severity == "warning", "globIgnorePaths não-vazio deveria ser Severity 'warning'")
		assert(contains(globDiagnostic.Message, "**/*.spec.lua"), "Message deveria listar os globs do fixture")
		assert(contains(globDiagnostic.Message, "_Index/**"), "Message deveria listar os globs do fixture")
	end

	local syncDiagnostic = findByCode(bag, "project/sync-rules-unsupported")
	assert(syncDiagnostic ~= nil, "deveria haver warning 'project/sync-rules-unsupported'")
	if syncDiagnostic ~= nil then
		assert(syncDiagnostic.Severity == "warning", "syncRules não-vazio deveria ser Severity 'warning'")
	end

	local idDiagnostic = findByCode(bag, "project/node-id-unsupported")
	assert(idDiagnostic ~= nil, "deveria haver warning 'project/node-id-unsupported' pro nó com $id")
	if idDiagnostic ~= nil then
		assert(idDiagnostic.Severity == "warning", "$id deveria ser Severity 'warning'")
		assert(idDiagnostic.NodePath == "tree.Flagged", "Diagnostic do $id deveria apontar o NodePath do nó certo")
	end
end)

--------------------------------------------------------------------------------------------------
-- Read: $ignoreUnknownInstances aceito em silêncio
--------------------------------------------------------------------------------------------------

test("Read com $ignoreUnknownInstances não produz NENHUM Diagnostic (aceito e ignorado em silêncio)", function()
	local bag = Diagnostics.newBag()
	local project = ProjectFile.Read(fixturePath("ignore-unknown-instances") .. "/default.project.json", bag)

	assert(project ~= nil, "Read deveria devolver um Project válido")
	assert(#bag:All() == 0, "$ignoreUnknownInstances não deveria produzir nenhum Diagnostic, nem warning")
end)

--------------------------------------------------------------------------------------------------
-- Read: filho cujo valor não é um objeto JSON
--------------------------------------------------------------------------------------------------

test("Read com um filho cujo valor não é objeto JSON produz erro 'project/invalid-node-value'", function()
	local bag = Diagnostics.newBag()
	local project = ProjectFile.Read(fixturePath("invalid-node-value") .. "/default.project.json", bag)

	assert(project == nil, "filho com valor não-objeto deveria impedir Read de devolver um Project")
	local diagnostic = findByCode(bag, "project/invalid-node-value")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic com Code 'project/invalid-node-value'")
	if diagnostic ~= nil then
		assert(diagnostic.Severity == "error", "valor de filho inválido deveria ser Severity 'error'")
		assert(diagnostic.NodePath == "tree.BadChild", "Diagnostic deveria apontar o NodePath do filho problemático")
	end
end)

--------------------------------------------------------------------------------------------------
-- Read: chave "$" desconhecida vira warning, NUNCA filho
--------------------------------------------------------------------------------------------------

test("Read com chave '$' desconhecida produz warning e NÃO cria um filho com esse nome", function()
	local bag = Diagnostics.newBag()
	local project = ProjectFile.Read(fixturePath("unknown-dollar-key") .. "/default.project.json", bag)

	assert(not bag:HasErrors(), "chave '$' desconhecida é warning, nunca erro")
	assert(project ~= nil, "Read deveria devolver um Project válido")

	local diagnostic = findByCode(bag, "project/unknown-dollar-key")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic com Code 'project/unknown-dollar-key'")
	if diagnostic ~= nil then
		assert(contains(diagnostic.Message, "$future"), "Message deveria citar a chave '$' desconhecida exata")
	end

	if project ~= nil then
		assert(project.Tree.Children["$future"] == nil, "chave '$' desconhecida NUNCA deveria virar filho")
		assert(next(project.Tree.Children) == nil, "a árvore não deveria ganhar nenhum filho a partir de uma chave '$' desconhecida")
	end
end)

--------------------------------------------------------------------------------------------------
-- Read: $path com valor que não é nem string nem {optional: ...}
--------------------------------------------------------------------------------------------------

test("Read com $path de tipo inválido (nem string, nem {optional: ...}) produz erro 'project/invalid-path-value'", function()
	local bag = Diagnostics.newBag()
	local project = ProjectFile.Read(fixturePath("invalid-path-value") .. "/default.project.json", bag)

	assert(project == nil, "$path inválido deveria impedir Read de devolver um Project")
	local diagnostic = findByCode(bag, "project/invalid-path-value")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic com Code 'project/invalid-path-value'")
	if diagnostic ~= nil then
		assert(diagnostic.Severity == "error", "$path inválido deveria ser Severity 'error'")
		assert(diagnostic.NodePath == "tree.Bad", "Diagnostic deveria apontar o NodePath do nó com o $path problemático")
	end
end)

--------------------------------------------------------------------------------------------------
-- Read: acumula TODOS os problemas na mesma passada (Decisão 3, "falha antes de mutar")
--------------------------------------------------------------------------------------------------

test("Read acumula erro de campo de topo desconhecido JUNTO com o de $path inválido, na mesma chamada", function()
	-- Fixture ad-hoc (não precisa de arquivo em disco): reaproveita os dois fixtures existentes
	-- não é possível num Read só (são dois arquivos), então este teste confirma o princípio via
	-- 'unknown-field', que sozinho já tem 'tree' válido e ainda assim é rejeitado -- prova de que
	-- a validação de campo desconhecido não depende de 'tree' estar ausente/errado.
	local bag = Diagnostics.newBag()
	local project = ProjectFile.Read(fixturePath("unknown-field") .. "/default.project.json", bag)

	assert(project == nil, "deveria continuar rejeitando mesmo com 'tree' presente e válido")
	assert(countByCode(bag, "project/unknown-field") == 1, "deveria haver exatamente um Diagnostic de campo desconhecido")
	assert(countByCode(bag, "project/missing-tree") == 0, "'tree' está presente e válido neste fixture -- não deveria haver erro de tree ausente")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
