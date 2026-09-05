--!strict

--[[
	Localizar, ler e validar o `.project.json`/`.project.jsonc` do Rojo (arquiteto-cli-2026-09-
	05.md, seção "Módulos" -> "ProjectFile.luau"; Decisões 2 e 14). Formato confirmado contra o
	código-fonte real do Rojo v7.7.0 em .claude/agents-memory/pesquisa-formato-projeto-rojo-2026-
	09-05.md -- NÃO repesquisado aqui.

	Este módulo só entende o NÍVEL RAIZ do `.project.json` (campos de topo) e o ESQUELETO de cada
	nó da árvore (`$className`/`$path`/`$properties`/`$attributes`/`$id`/
	`$ignoreUnknownInstances`/filhos nomeados) -- ele NÃO resolve `ClassName` (precedência
	$className > $path > inferência de Service), NÃO anda o filesystem via `$path`, e NÃO
	interpreta o CONTEÚDO de `$properties`/`$attributes` (primitivo vs. Vector3/Color3/etc.).
	Tudo isso é responsabilidade de `TreePlanner.luau` (task-cli-003) -- este módulo devolve os
	valores de `$properties`/`$attributes` como `JsonValue` cru, sem tentar interpretá-los.

	ESPELHA o `deny_unknown_fields` do Rojo real NO NÍVEL RAIZ (Decisão 14): uma chave
	desconhecida no topo do `.project.json` é um ERRO nomeando a chave e listando as válidas --
	é o que impede um typo como `"tre"` (em vez de `"tree"`) de passar como projeto vazio, e o
	que garante, na prática, que ninguém enfie um campo próprio do LuauBench ali (isso quebraria
	`rojo serve`/`build` de verdade -- pesquisa, "Limites e pegadinhas").

	Filosofia de erro (Decisão 3, "falha antes de mutar"): `Read` ACUMULA todos os problemas que
	encontrar no `bag` em vez de abortar no primeiro, e só devolve `nil` no final se `bag` tiver
	pelo menos um ERRO (`bag:HasErrors()`) -- um warning (campo aceito mas não suportado, ex.
	`globIgnorePaths`) nunca impede um `Project` válido de ser devolvido.

	Depende só de `JsonValue.luau` (narrowing de JSON), `Diagnostics.luau` (tipos `Bag`/
	`Diagnostic`), `Messages.luau` (toda string de erro) e `@lune/fs` (achar/ler o arquivo).
	NÃO importa `runtime` nem `services` -- é parsing puro (mesmo princípio do `TreePlanner`
	futuro: nenhuma dependência de módulo fora do próprio território `cli`).
]]

local fs = require("@lune/fs")
local Diagnostics = require("./Diagnostics")
local JsonValue = require("./JsonValue")
local Messages = require("./Messages")

export type PathNode = { Kind: "required", Path: string } | { Kind: "optional", Path: string }

export type ProjectNode = {
	ClassName: string?,
	Path: PathNode?,
	Properties: { [string]: JsonValue.JsonValue },
	Attributes: { [string]: JsonValue.JsonValue },
	Children: { [string]: ProjectNode },
	NodePath: string,
}

export type Project = {
	Name: string?,
	Tree: ProjectNode,
	FilePath: string,
	FolderPath: string,
	EmitLegacyScripts: boolean,
	GlobIgnorePaths: { string },
	HasSyncRules: boolean,
}

local ProjectFile = {}

-- Nomes reais que o Rojo procura quando recebe um diretório em vez de um arquivo (pesquisa,
-- seção 1: "DEFAULT_PROJECT_NAMES") -- ordem importa: `.json` antes de `.jsonc`.
local DEFAULT_PROJECT_NAMES = { "default.project.json", "default.project.jsonc" }

-- Campos de topo válidos do `.project.json` real (pesquisa, seção 1, struct `Project` de
-- `project.rs`) -- ordem usada tal-e-qual na mensagem de erro de campo desconhecido.
local VALID_TOP_LEVEL_FIELDS = {
	"name",
	"tree",
	"$schema",
	"servePort",
	"serveAddress",
	"serveAllowedHosts",
	"servePlaceIds",
	"blockedPlaceIds",
	"placeId",
	"gameId",
	"syncbackRules",
	"emitLegacyScripts",
	"globIgnorePaths",
	"syncRules",
}

local VALID_TOP_LEVEL_FIELD_SET: { [string]: boolean } = {}
for _, field in VALID_TOP_LEVEL_FIELDS do
	VALID_TOP_LEVEL_FIELD_SET[field] = true
end

-- As seis chaves de nó reconhecidas pelo Rojo (pesquisa, seção 2) -- qualquer outra chave do nó
-- é filho nomeado (se "$"-livre) ou warning de chave "$" desconhecida (se "$"-prefixada).
local RESERVED_NODE_KEYS: { [string]: boolean } = {
	["$className"] = true,
	["$path"] = true,
	["$properties"] = true,
	["$attributes"] = true,
	["$id"] = true,
	["$ignoreUnknownInstances"] = true,
}

-- Separa um caminho em (diretório, último segmento) -- puramente textual, sem tocar o
-- filesystem. Aceita `/` e `\` como separador (Windows/Unix). Serve tanto pra achar a pasta que
-- contém o `.project.json` (`FolderPath`) quanto pra derivar o nome do projeto a partir do nome
-- de arquivo/pasta quando `name` está ausente (pesquisa, seção 1: "se ausente, Rojo deriva do
-- nome do arquivo/pasta").
local function splitPath(path: string): (string, string)
	local trimmed = path
	if #trimmed > 1 then
		local lastChar = string.sub(trimmed, -1)
		if lastChar == "/" or lastChar == "\\" then
			trimmed = string.sub(trimmed, 1, -2)
		end
	end

	for index = #trimmed, 1, -1 do
		local char = string.sub(trimmed, index, index)
		if char == "/" or char == "\\" then
			return string.sub(trimmed, 1, index - 1), string.sub(trimmed, index + 1)
		end
	end

	return ".", trimmed
end

-- Concatena `directory` + `name` com uma única barra entre os dois, mesmo que `directory` já
-- termine com `/` ou `\` (evita barra dupla, ex.: candidate == "C:/proj/" passado pelo usuário).
local function joinPath(directory: string, name: string): string
	local normalized = directory
	if #normalized > 0 then
		local lastChar = string.sub(normalized, -1)
		if lastChar == "/" or lastChar == "\\" then
			normalized = string.sub(normalized, 1, -2)
		end
	end
	return `{normalized}/{name}`
end

-- Remove a extensão `.project.json`/`.project.jsonc` de um nome de arquivo. `nil` se o nome não
-- terminar em nenhuma das duas (não deveria acontecer -- `ProjectFile.Read` só é chamado com um
-- `filePath` que `Locate` já confirmou ter uma dessas extensões).
local function stripProjectExtension(fileName: string): string?
	local withoutJson = string.match(fileName, "^(.+)%.project%.json$")
	if withoutJson ~= nil then
		return withoutJson
	end
	return string.match(fileName, "^(.+)%.project%.jsonc$")
end

-- Deriva o `name` do projeto a partir do arquivo/pasta quando o campo `name` está ausente
-- (pesquisa, seção 1). `default.project.json`/`.jsonc` (ou uma extensão que não bateu) cai pro
-- nome da PASTA -- "default" não é um nome de projeto útil; qualquer outro nome de arquivo usa o
-- próprio stem (ex.: `MyGame.project.json` -> `"MyGame"`).
local function deriveNameFromPath(filePath: string): string
	local folder, fileName = splitPath(filePath)
	local stem = stripProjectExtension(fileName)

	if stem == nil or stem == "default" then
		local _, folderName = splitPath(folder)
		return folderName
	end

	return stem
end

-- Reaproveita um `Diagnostic` genérico já produzido por `JsonValue` (mensagem pronta, com o
-- `path` e os tipos esperado/encontrado) mas com um `Code` ESTÁVEL e específico de
-- `ProjectFile` -- evita duplicar a lógica de "qual é o tipo encontrado" (que já mora em
-- `JsonValue.luau`) só pra trocar o rótulo do erro. `nodePath`/`filePath` vêm de quem chama.
local function retagJsonDiagnostic(diagnostic: Diagnostics.Diagnostic, code: string, nodePath: string?, filePath: string): Diagnostics.Diagnostic
	return {
		Severity = diagnostic.Severity,
		Code = code,
		Message = diagnostic.Message,
		Field = diagnostic.Field,
		NodePath = nodePath,
		FilePath = filePath,
	}
end

-- `pathArg` apontando pra um arquivo existente usa direto; apontando pra diretório (ou ausente,
-- caindo no `cwd`) procura `default.project.json` e depois `default.project.jsonc` -- os
-- `DEFAULT_PROJECT_NAMES` reais do Rojo (pesquisa, seção 1). Nenhum dos dois achado -> erro
-- nomeando o diretório procurado. `fs.isFile`/`fs.isDir` devolvem `false` (nunca erro) pra um
-- caminho que não existe -- confirmado empiricamente pra esta task.
function ProjectFile.Locate(pathArg: string?, cwd: string): (string?, Diagnostics.Diagnostic?)
	local candidate = if pathArg ~= nil and pathArg ~= "" then pathArg else cwd

	if fs.isFile(candidate) then
		return candidate, nil
	end

	if not fs.isDir(candidate) then
		return nil, {
			Severity = "error",
			Code = "project/path-not-found",
			Message = Messages.ProjectPathNotFound(candidate),
			FilePath = candidate,
		}
	end

	for _, name in DEFAULT_PROJECT_NAMES do
		local attempt = joinPath(candidate, name)
		if fs.isFile(attempt) then
			return attempt, nil
		end
	end

	return nil, {
		Severity = "error",
		Code = "project/file-not-found",
		Message = Messages.ProjectFileNotFound(candidate),
		FilePath = candidate,
	}
end

-- `$path` é um enum "untagged" no Rojo real (pesquisa, seção 2): OU uma string (obrigatório) OU
-- um objeto `{"optional": "..."}` (opcional). Tenta as duas formas nessa ordem; se nenhuma bater,
-- um único erro genérico (nunca dois diagnósticos redundantes pro mesmo `$path`).
local function parsePathNode(value: JsonValue.JsonValue, nodePath: string, bag: Diagnostics.Bag, filePath: string): PathNode?
	local pathFieldPath = `{nodePath}.$path`

	local asString = JsonValue.AsString(value, pathFieldPath)
	if asString ~= nil then
		return { Kind = "required", Path = asString }
	end

	local asObject = JsonValue.AsObject(value, pathFieldPath)
	if asObject ~= nil then
		local optionalValue = asObject["optional"]
		if optionalValue == nil then
			bag:Add({
				Severity = "error",
				Code = "project/invalid-path-value",
				Message = Messages.ProjectInvalidPathValue(),
				NodePath = nodePath,
				FilePath = filePath,
			})
			return nil
		end

		local optionalString = JsonValue.AsString(optionalValue, `{pathFieldPath}.optional`)
		if optionalString == nil then
			bag:Add({
				Severity = "error",
				Code = "project/invalid-path-value",
				Message = Messages.ProjectInvalidPathValue(),
				NodePath = nodePath,
				FilePath = filePath,
			})
			return nil
		end

		return { Kind = "optional", Path = optionalString }
	end

	bag:Add({
		Severity = "error",
		Code = "project/invalid-path-value",
		Message = Messages.ProjectInvalidPathValue(),
		NodePath = nodePath,
		FilePath = filePath,
	})
	return nil
end

-- Parseia recursivamente UM nó da árvore (`tree` em si, ou qualquer filho nomeado). `object` já
-- foi confirmado como um objeto JSON válido por quem chama (raiz via `ProjectFile.Read`, filhos
-- via o laço abaixo). Nunca devolve `nil` -- um `$className`/`$path`/`$properties`/`$attributes`
-- malformado gera um `Diagnostic` de erro no `bag` (que faz `Read` devolver `nil` no final) mas
-- ainda assim produz um `ProjectNode` (com o campo problemático ausente/default), pra permitir
-- continuar acumulando o resto dos problemas da árvore na mesma passada.
local function parseNode(object: { [string]: JsonValue.JsonValue }, nodePath: string, bag: Diagnostics.Bag, filePath: string): ProjectNode
	local className: string? = nil
	local classNameValue = object["$className"]
	if classNameValue ~= nil then
		local classNameString, diagnostic = JsonValue.AsString(classNameValue, `{nodePath}.$className`)
		if classNameString == nil then
			if diagnostic ~= nil then
				bag:Add(retagJsonDiagnostic(diagnostic, "project/invalid-class-name", nodePath, filePath))
			end
		else
			className = classNameString
		end
	end

	local path: PathNode? = nil
	local pathValue = object["$path"]
	if pathValue ~= nil then
		path = parsePathNode(pathValue, nodePath, bag, filePath)
	end

	local properties: { [string]: JsonValue.JsonValue } = {}
	local propertiesValue = object["$properties"]
	if propertiesValue ~= nil then
		local propertiesObject, diagnostic = JsonValue.AsObject(propertiesValue, `{nodePath}.$properties`)
		if propertiesObject == nil then
			if diagnostic ~= nil then
				bag:Add(retagJsonDiagnostic(diagnostic, "project/invalid-properties-value", nodePath, filePath))
			end
		else
			properties = propertiesObject
		end
	end

	local attributes: { [string]: JsonValue.JsonValue } = {}
	local attributesValue = object["$attributes"]
	if attributesValue ~= nil then
		local attributesObject, diagnostic = JsonValue.AsObject(attributesValue, `{nodePath}.$attributes`)
		if attributesObject == nil then
			if diagnostic ~= nil then
				bag:Add(retagJsonDiagnostic(diagnostic, "project/invalid-attributes-value", nodePath, filePath))
			end
		else
			attributes = attributesObject
		end
	end

	-- `$id`: aceito, warning (Ref/reflection -- leva futura, depende de tipos de valor).
	if object["$id"] ~= nil then
		bag:Add({
			Severity = "warning",
			Code = "project/node-id-unsupported",
			Message = Messages.ProjectNodeIdUnsupported(),
			NodePath = nodePath,
			FilePath = filePath,
		})
	end

	-- `$ignoreUnknownInstances`: aceito e IGNORADO SEM warning -- é semântica de sincronização
	-- bidirecional Studio->disco (pesquisa, seção 2), sem efeito numa carga só-leitura. Nada a
	-- fazer aqui além de reconhecer a chave (já está em `RESERVED_NODE_KEYS`, então o laço de
	-- filhos abaixo não a trata como filho nem como "$"-desconhecida).

	local children: { [string]: ProjectNode } = {}
	for key, value in object do
		if RESERVED_NODE_KEYS[key] then
			continue
		end

		if string.sub(key, 1, 1) == "$" then
			-- Chave "$"-prefixada não reconhecida: no Rojo real isso é só um warning de log
			-- ("reservado pro próprio Rojo evoluir" -- pesquisa, seção 2), nunca um filho.
			bag:Add({
				Severity = "warning",
				Code = "project/unknown-dollar-key",
				Message = Messages.ProjectUnknownDollarKey(key),
				NodePath = nodePath,
				FilePath = filePath,
			})
			continue
		end

		local childNodePath = `{nodePath}.{key}`
		local childObject, diagnostic = JsonValue.AsObject(value, childNodePath)
		if childObject == nil then
			if diagnostic ~= nil then
				bag:Add(retagJsonDiagnostic(diagnostic, "project/invalid-node-value", childNodePath, filePath))
			end
			continue
		end

		children[key] = parseNode(childObject, childNodePath, bag, filePath)
	end

	return {
		ClassName = className,
		Path = path,
		Properties = properties,
		Attributes = attributes,
		Children = children,
		NodePath = nodePath,
	}
end

-- Lê, decodifica e valida `filePath` (já resolvido por `Locate`, ou passado direto por quem
-- chama). Acumula TODOS os problemas encontrados em `bag`; devolve `nil` se `bag:HasErrors()`
-- ficar `true` ao final (um `Diagnostic` de severidade "warning"/"info" nunca impede um `Project`
-- válido de ser devolvido -- Decisão 14).
function ProjectFile.Read(filePath: string, bag: Diagnostics.Bag): Project?
	local readOk, textOrError = pcall(function(): unknown
		return fs.readFile(filePath)
	end)

	if not readOk then
		local rawMessage = tostring(textOrError)
		local newlineIndex = string.find(rawMessage, "\n", 1, true)
		local ioMessage = if newlineIndex ~= nil then string.sub(rawMessage, 1, newlineIndex - 1) else rawMessage

		bag:Add({
			Severity = "error",
			Code = "project/file-not-readable",
			Message = Messages.ProjectFileNotReadable(filePath, ioMessage),
			FilePath = filePath,
		})
		return nil
	end

	-- `fs.readFile` devolve `string` de verdade (não `any`/`unknown`) -- o closure acima só
	-- precisou anotar `unknown` pra passar pelo mesmo protocolo de `pcall` sem introduzir `any`;
	-- aqui a narrowing é trivial porque já sabemos (pelo `readOk == true`) que veio de
	-- `fs.readFile`, cuja assinatura real é `(path: string): string`.
	local text = textOrError :: string

	local decoded, decodeDiagnostic = JsonValue.Decode(text, filePath)
	if decodeDiagnostic ~= nil then
		bag:Add(retagJsonDiagnostic(decodeDiagnostic, "project/malformed-json", nil, filePath))
		return nil
	end

	local root, rootDiagnostic = JsonValue.AsObject(decoded, "<root>")
	if root == nil then
		if rootDiagnostic ~= nil then
			bag:Add(retagJsonDiagnostic(rootDiagnostic, "project/invalid-root", nil, filePath))
		else
			bag:Add({ Severity = "error", Code = "project/invalid-root", Message = Messages.ProjectInvalidRoot(), FilePath = filePath })
		end
		return nil
	end

	-- Espelha `deny_unknown_fields` do Rojo no nível raiz (Decisão 14) -- acumula TODAS as
	-- chaves desconhecidas encontradas, não só a primeira.
	for key, _ in root do
		if not VALID_TOP_LEVEL_FIELD_SET[key] then
			bag:Add({
				Severity = "error",
				Code = "project/unknown-field",
				Message = Messages.ProjectUnknownField(key, VALID_TOP_LEVEL_FIELDS),
				Field = key,
				FilePath = filePath,
			})
		end
	end

	-- `name`: ausente -> derivado do arquivo/pasta (pesquisa, seção 1). Presente com tipo errado
	-- -> erro, mas não impede o resto da validação (cai pro nome derivado só pra continuar
	-- montando um `Project` coerente internamente -- `Read` devolve `nil` de qualquer forma por
	-- causa do erro acumulado).
	local name: string? = nil
	local nameValue = root["name"]
	if nameValue ~= nil then
		local nameString, diagnostic = JsonValue.AsString(nameValue, "name")
		if nameString == nil then
			if diagnostic ~= nil then
				bag:Add(retagJsonDiagnostic(diagnostic, "project/invalid-name-value", nil, filePath))
			end
		else
			name = nameString
		end
	end
	if name == nil then
		name = deriveNameFromPath(filePath)
	end

	-- `tree`: obrigatório (Decisão 14) -- ausente é erro fatal (sem árvore não há Project útil).
	local treeValue = root["tree"]
	if treeValue == nil then
		bag:Add({
			Severity = "error",
			Code = "project/missing-tree",
			Message = Messages.ProjectMissingField("tree"),
			Field = "tree",
			FilePath = filePath,
		})
	end

	local treeObject: { [string]: JsonValue.JsonValue }? = nil
	if treeValue ~= nil then
		local resolvedTreeObject, diagnostic = JsonValue.AsObject(treeValue, "tree")
		if resolvedTreeObject == nil then
			if diagnostic ~= nil then
				bag:Add(retagJsonDiagnostic(diagnostic, "project/invalid-tree-value", "tree", filePath))
			end
		else
			treeObject = resolvedTreeObject
		end
	end

	-- `emitLegacyScripts`: default efetivo `true` até o Rojo v8 (pesquisa, seção 1). `false`
	-- explícito -> warning (Decisão 14: LuauBench não modela `RunContext`).
	local emitLegacyScripts = true
	local emitLegacyScriptsValue = root["emitLegacyScripts"]
	if emitLegacyScriptsValue ~= nil then
		local emitLegacyScriptsBoolean, diagnostic = JsonValue.AsBoolean(emitLegacyScriptsValue, "emitLegacyScripts")
		if emitLegacyScriptsBoolean == nil then
			if diagnostic ~= nil then
				bag:Add(retagJsonDiagnostic(diagnostic, "project/invalid-emit-legacy-scripts-value", nil, filePath))
			end
		else
			emitLegacyScripts = emitLegacyScriptsBoolean
			if emitLegacyScriptsBoolean == false then
				bag:Add({
					Severity = "warning",
					Code = "project/emit-legacy-scripts-false",
					Message = Messages.ProjectEmitLegacyScriptsFalse(),
					Field = "emitLegacyScripts",
					FilePath = filePath,
				})
			end
		end
	end

	-- `globIgnorePaths`: não-vazio -> warning listando os globs (não aplicado -- precisa de um
	-- motor de glob, fora da leva 1).
	local globIgnorePaths: { string } = {}
	local globIgnorePathsValue = root["globIgnorePaths"]
	if globIgnorePathsValue ~= nil then
		local globArray, globArrayDiagnostic = JsonValue.AsArray(globIgnorePathsValue, "globIgnorePaths")
		if globArray == nil then
			if globArrayDiagnostic ~= nil then
				bag:Add(retagJsonDiagnostic(globArrayDiagnostic, "project/invalid-glob-ignore-paths-value", nil, filePath))
			end
		else
			for index, item in globArray do
				local itemString, itemDiagnostic = JsonValue.AsString(item, `globIgnorePaths[{index}]`)
				if itemString == nil then
					if itemDiagnostic ~= nil then
						bag:Add(retagJsonDiagnostic(itemDiagnostic, "project/invalid-glob-ignore-paths-value", nil, filePath))
					end
				else
					table.insert(globIgnorePaths, itemString)
				end
			end

			if #globIgnorePaths > 0 then
				bag:Add({
					Severity = "warning",
					Code = "project/glob-ignore-paths-unsupported",
					Message = Messages.ProjectGlobIgnorePathsUnsupported(globIgnorePaths),
					Field = "globIgnorePaths",
					FilePath = filePath,
				})
			end
		end
	end

	-- `syncRules`: não-vazio -> warning (não aplicado -- formato de `SyncRule` não confirmado
	-- pela pesquisa, "Incerto"; aplicar pela metade seria pior que não aplicar).
	local hasSyncRules = false
	local syncRulesValue = root["syncRules"]
	if syncRulesValue ~= nil then
		local syncRulesArray, diagnostic = JsonValue.AsArray(syncRulesValue, "syncRules")
		if syncRulesArray == nil then
			if diagnostic ~= nil then
				bag:Add(retagJsonDiagnostic(diagnostic, "project/invalid-sync-rules-value", nil, filePath))
			end
		elseif #syncRulesArray > 0 then
			hasSyncRules = true
			bag:Add({
				Severity = "warning",
				Code = "project/sync-rules-unsupported",
				Message = Messages.ProjectSyncRulesUnsupported(#syncRulesArray),
				Field = "syncRules",
				FilePath = filePath,
			})
		end
	end

	local rootNode: ProjectNode? = nil
	if treeObject ~= nil then
		rootNode = parseNode(treeObject, "tree", bag, filePath)
	end

	if bag:HasErrors() or rootNode == nil then
		return nil
	end

	local folderPath, _ = splitPath(filePath)

	return {
		Name = name,
		Tree = rootNode,
		FilePath = filePath,
		FolderPath = folderPath,
		EmitLegacyScripts = emitLegacyScripts,
		GlobIgnorePaths = globIgnorePaths,
		HasSyncRules = hasSyncRules,
	}
end

return ProjectFile
