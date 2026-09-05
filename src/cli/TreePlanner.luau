--!strict

--[[
	`Project` (`ProjectFile.luau`) + filesystem -> `InstancePlan` (arquiteto-cli-2026-09-05.md,
	Decisões 3, 4, 6, 7 e 8; pesquisa-formato-projeto-rojo-2026-09-05.md, seção 4). NENHUMA
	Instance é criada aqui -- só dado. Materializar contra o `DataModel` real é responsabilidade
	de `TreeMaterializer.luau` (task-cli-004, ainda não escrita).

	NÃO REQUER `runtime` nem `services` (Decisão 3 e "Contrato entre territórios" do desenho) --
	`options.IsServiceClass` é INJETADA por quem chama (`RunCommand`, task-cli-006, passando
	`Services.IsServiceClass`), o que torna este módulo testável com um fixture em disco e uma
	função falsa, sem `DataModel`/`Bootstrap` nenhum. Confirmável por leitura: nenhum `require`
	deste arquivo aponta pra `../runtime` ou `../services`.

	Resolve `ClassName` na MESMA precedência do Rojo real (pesquisa, seção 4):
		1. `$className` explícito;
		2. classe inferida do `$path` (via `SyncRules`);
		3. inferência de filho fixo/Service, dependendo de QUEM é o pai (raiz é chamada com
		   `parentClassName = nil`, então a raiz em si NUNCA tem essa inferência; seus FILHOS
		   diretos têm, dependendo do `ClassName` da raiz/pai já resolvido) -- CORREÇÃO
		   task-cli-014 (pesquisa-formato-projeto-rojo-2026-09-05.md, seção "Correção
		   2026-09-05"): `infer_class_name` do Rojo real tem 3 ramos `if`/`else if` MUTUAMENTE
		   EXCLUSIVOS por `parentClassName` -- nunca "tenta os 3", sempre "só um se aplica":
		     a. pai == "DataModel" -> qualquer classe com tag `Service` no dump (dinâmico, via
		        `options.IsServiceClass` injetada -- só este ramo resolvido aqui em
		        `TreePlanner`, porque depende de uma classe real);
		     b. pai == "StarterPlayer" -> "StarterPlayerScripts"/"StarterCharacterScripts"
		        (hardcoded, `SyncRules.InferFixedChildClassName`);
		     c. pai == "Workspace" -> "Terrain" (hardcoded, mesma função de `SyncRules`).
		4. nada resolve -> erro nomeando o nó (família de mensagem real do Rojo).
	Conflito `$className` + `$path`: só é legal se `$path` resolver para `Folder`. `$path` que
	resolve a `Folder` sob um pai com um nome de filho fixo/Service reconhecido -> a inferência
	(ramo a, b ou c acima) VENCE sobre o `Folder` genérico.

	`$path` é sempre relativo à pasta do `.project.json` QUE DEFINE aquele nó (Decisão 8) --
	`containerFolderPath` é recarregado a cada projeto aninhado, nunca uma variável global de
	raiz. Projeto aninhado = recursão do mesmo parser (`ProjectFile.Read` de novo), com PROTEÇÃO
	DE CICLO por um conjunto de caminhos absolutos de projeto no RAMO corrente (não global à
	árvore inteira -- dois ramos irmãos podem apontar pro mesmo projeto aninhado sem ser ciclo).

	CORREÇÃO (revisor-cli-treeplanner-2026-09-05.md, achado GRAVE): todo caminho absoluto
	derivado de um `$path` é NORMALIZADO (`normalizePath`, abaixo -- colapsa segmentos "."/".."
	por álgebra de string, sem tocar filesystem) ANTES de virar `ownAbsolutePath`/alimentar
	`classifyTarget`. Sem isso, um `$path` relativo tipo "../b" (padrão normal de pacote
	vendorizado/monorepo referenciando "pra cima") faz duas strings que apontam pro MESMO arquivo
	em disco parecerem diferentes pro `cycleGuard` -- um ciclo real (A -> B -> A) nunca era
	detectado, e o path crescia sem limite a cada volta (`a/../b/../a/...`) até o SO recusar abrir
	o caminho. Normalizar de uma vez, no ponto em que `$path` vira caminho absoluto, mantém TODO
	caminho derivado (source, filhos de pasta, `nestedProjectFilePath`) canônico -- não é só o
	`cycleGuard` que se beneficia, é o que também impede o crescimento ilimitado da string. LIMITE
	DECLARADO (regra 00): não cobre symlink nem diferença de maiúscula/minúscula em path
	case-insensitive do Windows -- a API `fs` do Lune 0.10.5 (pesquisa-cli) não expõe
	canonicalização/realpath, e um limite duro de profundidade como rede de segurança independente
	(sugerido pelo revisor) fica para uma tarefa futura dedicada (exigiria uma mensagem nova em
	`Messages.luau`, fora do escopo desta correção).

	APROXIMAÇÕES DECLARADAS desta tarefa (regra 00 -- nunca silenciosas):
	- Um nó cujo `$path` resolve a um projeto aninhado E que TAMBÉM declara filhos nomeados no
	  próprio `.project.json` usa SÓ a árvore do projeto aninhado -- os filhos nomeados são
	  ignorados com um warning (`plan/nested-project-children-ignored`). O Rojo real faz um merge
	  mais profundo entre os dois; não é coberto por esta leva.
	- Um projeto aninhado nunca vira `IsServiceRoot = true`, mesmo se, em teoria, terminasse
	  resolvendo pra uma classe de Service sob a raiz de um projeto pai -- caso de borda raro, não
	  coberto por teste, documentado aqui em vez de fingir suporte completo.
	- `$path` apontando DIRETAMENTE pra um arquivo classificado como `MetaFile` ou `Ignored` (uso
	  incomum -- meta files são pensados pra ficar ao lado de outro arquivo, não serem o alvo de
	  um `$path`) não produz `ClassName` nenhum e não gera diagnostic dedicado -- cai no erro
	  genérico de "faltou informação" (tier 4) se nada mais resolver a classe do nó.
]]

local fs = require("@lune/fs")
local Diagnostics = require("./Diagnostics")
local JsonValue = require("./JsonValue")
local Messages = require("./Messages")
local ProjectFile = require("./ProjectFile")
local SyncRules = require("./SyncRules")

export type PlanPropertyValue = boolean | number | string

export type PlanNode = {
	Name: string,
	ClassName: string,
	IsServiceRoot: boolean,
	Source: string?,
	SourcePath: string?,
	Properties: { [string]: PlanPropertyValue },
	Children: { PlanNode },
	NodePath: string,
}

export type InstancePlan = {
	ProjectName: string,
	ProjectPath: string,
	RootClassName: string,
	-- Campo ADITIVO (task-cli-018, Decisão 15 "Parte 2"): `$properties` da raiz de TOPO do
	-- projeto -- antes desta correção era descartado em silêncio (`planProjectTree` só devolvia
	-- `ClassName`). `TreeMaterializer.Materialize` aplica isto no `game` pela via pública de
	-- escrita já existente (`applyProperties`), logo após confirmar que a raiz é mesmo um
	-- `DataModel`.
	RootProperties: { [string]: PlanPropertyValue },
	Roots: { PlanNode },
	Diagnostics: { Diagnostics.Diagnostic },
}

export type PlanOptions = {
	IsServiceClass: (className: string) -> boolean,
}

local TreePlanner = {}

-- LIMITE DURO DE PROFUNDIDADE DE RECURSÃO (task-cli-008) -- rede de segurança COMPLEMENTAR ao
-- `cycleGuard`/`normalizePath` (comentário grande no cabeçalho do arquivo, "CORREÇÃO"). Aquele
-- mecanismo só cobre CICLO DE PROJETO ANINHADO (chave = caminho absoluto normalizado de um
-- "$path" que resolve a outro `.project.json`) -- ele NÃO cobre um loop de PASTA COMUM (filhos
-- descobertos via `fs.readDir` em `planChildrenOf`, sem nenhum "$path" novo em cada nível), que
-- nunca passa pelo `cycleGuard`. Um symlink/junction de pasta apontando de volta pra um
-- ancestral causaria recursão real sem limite nenhum antes desta tarefa (a API `fs` do Lune
-- 0.10.5 não expõe sequer como CRIAR um pra testar aqui, mas nada impede o projeto do usuário de
-- ter um). Este contador é a defesa: incrementado a CADA NÍVEL DE RECURSÃO REAL (um filho de
-- pasta via `planChildrenOf`/`planChildNode`, OU entrar num projeto aninhado via
-- `planProjectTree`) -- nunca amarrado a um path específico, então pega QUALQUER vetor de
-- recursão sem limite, não só os dois mencionados acima (case-insensitivity de path no Windows
-- incluída -- ver teste dedicado em `TreePlanner.spec.luau`, que também documenta por que ESSE
-- vetor específico, com só duas pastas envolvidas, já termina sozinho via `cycleGuard` em poucos
-- saltos, sem precisar deste limite).
--
-- NÚMERO ESCOLHIDO: 200. Justificativa:
--   - Projeto Rojo real legítimo raramente passa de umas poucas dezenas de níveis de PASTA (a
--     árvore de instâncias de um jogo real, mesmo grande, não costuma passar de ~20-30 níveis de
--     profundidade); projeto aninhado (pacote Wally vendorizado) raramente passa de 2-3 níveis
--     encadeados. 200 dá margem de sobra (~5-10x) pra qualquer combinação razoável dos dois sem
--     nunca ser confundido com um projeto real.
--   - Sondado empiricamente (`lune run` de um script fora deste módulo, removido depois) que a
--     MESMA FORMA de recursão mútua usada aqui (`resolveCore` -> `planChildrenOf` ->
--     `planChildNode` -> `resolveCore`, ~4 chamadas de função por nível) só estoura a pilha
--     nativa do Luau do Lune perto de ~5000 níveis -- 200 para MUITO antes disso (margem de
--     ~25x), então o Diagnostic claro abaixo sempre dispara antes de qualquer risco de "stack
--     overflow" cru vazando pro usuário (regra 04: nunca stack trace cru).
local MAX_PLAN_DEPTH = 200

--------------------------------------------------------------------------------------------------
-- Tipos internos (não exportados -- só usados pela recursão deste módulo)
--------------------------------------------------------------------------------------------------

-- Agrupa o que NÃO muda entre chamadas recursivas (ao contrário de `cycleGuard`/`cycleChain`, que
-- mudam ao entrar num projeto aninhado) -- reduz a lista de parâmetros das funções abaixo.
type PlanContext = {
	Options: PlanOptions,
	Bag: Diagnostics.Bag,
	-- Caminho NORMALIZADO do arquivo de projeto MAIS EXTERNO (o que `TreePlanner.Plan` recebeu).
	-- Invariante do plano inteiro -- não muda ao entrar num projeto aninhado, por isso mora aqui e
	-- não num parâmetro. É o que distingue "raiz do plano" de "raiz de um projeto qualquer"
	-- (`isRoot`), dois conceitos que a task-cli-018 tinha colapsado no mesmo nome (Decisão 16).
	OutermostProjectFilePath: string,
}

-- Resultado de resolver UM nó (raiz de projeto OU filho nomeado) até o ponto de saber sua classe
-- final e de onde vêm seus filhos -- mas SEM ainda ter recursado nos filhos (isso é
-- `planChildrenOf`, separado, porque a raiz de um `Project` nunca vira um `PlanNode` -- só os
-- FILHOS dela viram `InstancePlan.Roots`, ver Decisão 3).
type CoreResolution = {
	ClassName: string,
	IsServiceRoot: boolean,
	Source: string?,
	SourcePath: string?,
	Properties: { [string]: PlanPropertyValue },
	IsNestedProject: boolean,
	NestedChildren: { PlanNode }?,
	FsChildBaseDir: string?,
	FsChildEntries: { string }?,
	FsInitFileName: string?,
}

-- O que a raiz de UM `Project` (de topo ou aninhado) resolve, além dos filhos -- task-cli-018,
-- arquiteto-cli-2026-09-05.md, Decisão 15. Existe porque a raiz NÃO vira um `PlanNode` (Decisão
-- 3) e portanto precisava de um carona para `Source`/`SourcePath`/`Properties`, que antes eram
-- descartados em `planProjectTree` (devolvia só `ClassName`) -- bug ALTO: a raiz de TODO projeto
-- aninhado (ou seja, todo pacote Wally com `default.project.json` próprio) perdia o próprio
-- `Source` em silêncio (`require(ServerPackages.ProfileStore)` devolvia módulo vazio).
type RootResolution = {
	ClassName: string,
	Source: string?,
	SourcePath: string?,
	Properties: { [string]: PlanPropertyValue },
}

-- Um candidato a filho, antes de ser resolvido: pode ter vindo do JSON (`JsonNode`), do
-- filesystem (`DiscoveredAbsolutePath`, achado ao andar o `$path` de diretório do pai), ou dos
-- dois ao mesmo tempo (JSON aplicando `$properties`/`$path` próprio a um arquivo/pasta que
-- também existe fisicamente sob o `$path` do pai).
type ChildSpec = {
	Name: string,
	JsonNode: ProjectFile.ProjectNode?,
	DiscoveredAbsolutePath: string?,
}

-- O que `classifyTarget` devolve sobre UM caminho absoluto já confirmado existente (arquivo OU
-- pasta) -- une `SyncRules.FileKind`/`DirKind` num só vocabulário de 8 valores possíveis.
type TargetClassification = {
	Kind: "Script" | "LocalScript" | "ModuleScript" | "Folder" | "NestedProject" | "Unsupported" | "Ignored" | "MetaFile",
	IsDirectory: boolean,
	SourcePath: string?,
	NestedProjectPath: string?,
	DirPath: string?,
	DirEntries: { string }?,
	InitFileName: string?,
}

type MetaFileData = {
	Properties: { [string]: JsonValue.JsonValue },
	Attributes: { [string]: JsonValue.JsonValue },
	ClassName: string?,
}

--------------------------------------------------------------------------------------------------
-- Helpers puramente textuais (duplicados minúsculos de `ProjectFile.luau` -- privados lá, e este
-- módulo não deveria acoplar no formato interno de outro arquivo do território por causa de duas
-- funções de ~10 linhas cada)
--------------------------------------------------------------------------------------------------

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

-- Colapsa segmentos "."/".." de um caminho ABSOLUTO já concatenado por `joinPath` (que é
-- concatenação de string pura -- nunca resolve ".."/"." sozinho). Pura álgebra sobre os
-- componentes do caminho, SEM tocar o filesystem (a API `fs` do Lune 0.10.5 confirmada no desenho
-- não expõe canonicalização/realpath) -- existe pra que dois caminhos que apontam pro MESMO
-- arquivo em disco (um com ".." resolvido mentalmente, outro não) produzam a MESMA string, o que
-- `cycleGuard`/`cycleChain` exigem pra reconhecer um ciclo de projeto aninhado que passa por um
-- "$path" relativo tipo "../b" (achado GRAVE, revisor-cli-treeplanner-2026-09-05.md).
--
-- Aceita "/" e "\" como separador (mesma convenção de `joinPath`/`baseNameOf`) e preserva um
-- prefixo de raiz -- letra de drive do Windows ("C:/"), barra dupla inicial (UNC, "//") ou barra
-- única inicial (POSIX) -- antes de colapsar o resto. ".." além da raiz é descartado (não existe
-- "acima" da raiz/drive), mesmo comportamento de um realpath de SO de verdade. NÃO faz lowercase
-- -- case-insensitivity do filesystem do Windows é uma limitação declarada, não coberta aqui (ver
-- comentário no cabeçalho do arquivo).
local function normalizePath(path: string): string
	local unified = string.gsub(path, "\\", "/")

	local prefix = ""
	local rest = unified

	local driveLetter = string.match(unified, "^(%a:)/")
	if string.sub(unified, 1, 2) == "//" then
		prefix = "//"
		rest = string.sub(unified, 3)
	elseif driveLetter ~= nil then
		prefix = `{driveLetter}/`
		rest = string.sub(unified, #driveLetter + 2)
	elseif string.sub(unified, 1, 1) == "/" then
		prefix = "/"
		rest = string.sub(unified, 2)
	end

	local stack: { string } = {}
	for segment in string.gmatch(rest, "[^/]+") do
		if segment == "." then
			-- nada a fazer -- "." não muda o diretório corrente.
		elseif segment == ".." then
			if #stack > 0 then
				table.remove(stack)
			end
			-- ".." além da raiz (`stack` vazio) é descartado, nunca sobe "acima" do drive/raiz.
		else
			table.insert(stack, segment)
		end
	end

	return prefix .. table.concat(stack, "/")
end

local function baseNameOf(path: string): string
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
			return string.sub(trimmed, index + 1)
		end
	end
	return trimmed
end

local function copyStringSet(set: { [string]: boolean }): { [string]: boolean }
	local copy: { [string]: boolean } = {}
	for key, value in set do
		copy[key] = value
	end
	return copy
end

local function copyStringList(list: { string }): { string }
	local copy: { string } = table.create(#list)
	for _, value in list do
		table.insert(copy, value)
	end
	return copy
end

-- task-cli-018 (Decisão 15): usado pra semear `nestedProperties` com uma CÓPIA do `$properties`
-- já resolvido pela raiz de um projeto aninhado, antes de aplicar o `$properties` do nó EXTERNO
-- por cima -- cópia, nunca a mesma tabela, porque `RootResolution.Properties` pode ser
-- referenciada por mais de uma chamada (ex.: dois nós irmãos apontando pro mesmo pacote
-- vendorizado) e `applyProperties` muta o destino que recebe.
local function copyPlanProperties(properties: { [string]: PlanPropertyValue }): { [string]: PlanPropertyValue }
	local copy: { [string]: PlanPropertyValue } = {}
	for key, value in properties do
		copy[key] = value
	end
	return copy
end

-- Mesmo protocolo de `JsonValue.luau` (corta na primeira quebra de linha) -- usado só pros erros
-- de I/O deste módulo (`fs.readFile`/`fs.readDir` lançando via `pcall`), pra nunca vazar stack
-- trace cru (regra 04).
local function firstLineOf(value: unknown): string
	local text = tostring(value)
	local newlineIndex = string.find(text, "\n", 1, true)
	if newlineIndex == nil then
		return text
	end
	return string.sub(text, 1, newlineIndex - 1)
end

-- Duplicata minúscula do `describeKind` privado de `JsonValue.luau` -- só pra rotular um
-- `$properties`/meta-`properties` não-primitivo na mensagem de warning ("array"/"object" em vez
-- de só "table"). `value` aqui NUNCA é `nil` (chamador só invoca depois de já ter descartado
-- boolean/number/string -- e uma entrada de mapa JSON com valor `null` não aparece como chave,
-- ver `JsonValue.luau`, "Ambiguidade de JSON->Lua HONESTAMENTE DECLARADA").
local function describeNonPrimitiveKind(value: JsonValue.JsonValue): string
	if typeof(value) == "table" then
		local asGeneric = (value :: unknown) :: { [unknown]: unknown }
		local firstKey = next(asGeneric)
		if firstKey ~= nil and typeof(firstKey) == "number" then
			return "array"
		end
		return "object"
	end
	return typeof(value)
end

--------------------------------------------------------------------------------------------------
-- Classificação de UM caminho absoluto (arquivo ou pasta) já confirmado existente
--------------------------------------------------------------------------------------------------

local function classifyTarget(absolutePath: string): TargetClassification?
	if fs.isFile(absolutePath) then
		local fileName = baseNameOf(absolutePath)
		local kind = SyncRules.ClassifyFile(fileName)

		if kind == "NestedProject" then
			return {
				Kind = "NestedProject",
				IsDirectory = false,
				SourcePath = nil,
				NestedProjectPath = absolutePath,
				DirPath = nil,
				DirEntries = nil,
				InitFileName = nil,
			}
		end

		local sourcePathValue: string? = nil
		if kind == "Script" or kind == "LocalScript" or kind == "ModuleScript" then
			sourcePathValue = absolutePath
		end

		-- ACHADO DE TOOLING (mesma classe já documentada em `Diagnostics.luau`, "ACHADO DE
		-- TOOLING #1"/"#2": `luau-lsp` 1.69.0 larga a narrowing de literal de união de um valor
		-- vindo de OUTRO módulo -- `kind: SyncRules.FileKind` -- pra `string` genérico assim que
		-- ele vira o VALOR de um campo dentro de um construtor de tabela devolvido por uma função
		-- com tipo de retorno declarado explicitamente (`TargetClassification?`). Confirmado que
		-- `lune run` sempre executou certo (o campo carrega o valor real em runtime); é só a
		-- análise estática que erra. Contornado com o MESMO cast em duas etapas por `unknown` já
		-- usado em `JsonValue.luau`/`Instance.luau` pra widening estrutural (não é um `any`
		-- disfarçado -- o valor de fato pertence ao subconjunto certo em runtime).
		return ({
			Kind = kind,
			IsDirectory = false,
			SourcePath = sourcePathValue,
			NestedProjectPath = nil,
			DirPath = nil,
			DirEntries = nil,
			InitFileName = nil,
		} :: unknown) :: TargetClassification
	end

	if fs.isDir(absolutePath) then
		local entries = fs.readDir(absolutePath)
		local dirName = baseNameOf(absolutePath)
		local dirKind, initFile = SyncRules.ClassifyDir(dirName, entries)

		if dirKind == "NestedProject" then
			return {
				Kind = "NestedProject",
				IsDirectory = true,
				SourcePath = nil,
				NestedProjectPath = joinPath(absolutePath, initFile :: string),
				DirPath = absolutePath,
				DirEntries = entries,
				InitFileName = initFile,
			}
		elseif dirKind == "ModuleScript" or dirKind == "Script" or dirKind == "LocalScript" then
			return {
				Kind = dirKind,
				IsDirectory = true,
				SourcePath = joinPath(absolutePath, initFile :: string),
				NestedProjectPath = nil,
				DirPath = absolutePath,
				DirEntries = entries,
				InitFileName = initFile,
			}
		elseif dirKind == "Folder" then
			return {
				Kind = "Folder",
				IsDirectory = true,
				SourcePath = nil,
				NestedProjectPath = nil,
				DirPath = absolutePath,
				DirEntries = entries,
				InitFileName = nil,
			}
		else
			return {
				Kind = "Unsupported",
				IsDirectory = true,
				SourcePath = nil,
				NestedProjectPath = nil,
				DirPath = absolutePath,
				DirEntries = entries,
				InitFileName = initFile,
			}
		end
	end

	return nil
end

--------------------------------------------------------------------------------------------------
-- Meta files (Decisão 7): `<nome>.meta.json` (irmão de um arquivo) e `init.meta.json` (dentro de
-- uma pasta) -- mesma leitura, `className` só é honrado por quem chama quando fizer sentido.
--------------------------------------------------------------------------------------------------

local function readMetaFile(absoluteMetaPath: string, nodePath: string, bag: Diagnostics.Bag): MetaFileData?
	local readOk, textOrError = pcall(function(): unknown
		return fs.readFile(absoluteMetaPath)
	end)

	if not readOk then
		bag:Add({
			Severity = "error",
			Code = "plan/io-error",
			Message = Messages.PlanIoError(nodePath, absoluteMetaPath, firstLineOf(textOrError)),
			NodePath = nodePath,
			FilePath = absoluteMetaPath,
		})
		return nil
	end

	local text = textOrError :: string

	local decoded, decodeDiagnostic = JsonValue.Decode(text, absoluteMetaPath)
	if decodeDiagnostic ~= nil then
		bag:Add({
			Severity = decodeDiagnostic.Severity,
			Code = "plan/malformed-meta-json",
			Message = decodeDiagnostic.Message,
			NodePath = nodePath,
			FilePath = absoluteMetaPath,
		})
		return nil
	end

	local root, rootDiagnostic = JsonValue.AsObject(decoded, absoluteMetaPath)
	if root == nil then
		if rootDiagnostic ~= nil then
			bag:Add({
				Severity = rootDiagnostic.Severity,
				Code = "plan/invalid-meta-json",
				Message = rootDiagnostic.Message,
				NodePath = nodePath,
				FilePath = absoluteMetaPath,
			})
		end
		return nil
	end

	local properties: { [string]: JsonValue.JsonValue } = {}
	local propertiesValue = root["properties"]
	if propertiesValue ~= nil then
		local propertiesObject = JsonValue.AsObject(propertiesValue, `{absoluteMetaPath}#properties`)
		if propertiesObject ~= nil then
			properties = propertiesObject
		end
	end

	local attributes: { [string]: JsonValue.JsonValue } = {}
	local attributesValue = root["attributes"]
	if attributesValue ~= nil then
		local attributesObject = JsonValue.AsObject(attributesValue, `{absoluteMetaPath}#attributes`)
		if attributesObject ~= nil then
			attributes = attributesObject
		end
	end

	local className: string? = nil
	local classNameValue = root["className"]
	if classNameValue ~= nil then
		local classNameString = JsonValue.AsString(classNameValue, `{absoluteMetaPath}#className`)
		if classNameString ~= nil then
			className = classNameString
		end
	end

	if root["id"] ~= nil then
		bag:Add({
			Severity = "warning",
			Code = "plan/meta-field-unsupported",
			Message = Messages.PlanMetaFieldUnsupported(nodePath, "id"),
			NodePath = nodePath,
			FilePath = absoluteMetaPath,
		})
	end
	if root["ignoreUnknownInstances"] ~= nil then
		bag:Add({
			Severity = "warning",
			Code = "plan/meta-field-unsupported",
			Message = Messages.PlanMetaFieldUnsupported(nodePath, "ignoreUnknownInstances"),
			NodePath = nodePath,
			FilePath = absoluteMetaPath,
		})
	end

	return { Properties = properties, Attributes = attributes, ClassName = className }
end

--------------------------------------------------------------------------------------------------
-- $properties / $attributes (Decisão 7): primitivo entra no plano; não-primitivo é warning e
-- pula (nunca grava a tabela crua -- mentiria, o LuauBench não tem tipos de valor ainda);
-- $attributes NUNCA é aplicado, sempre warning listando o que ficou de fora.
--------------------------------------------------------------------------------------------------

local function applyProperties(
	destination: { [string]: PlanPropertyValue },
	merged: { [string]: JsonValue.JsonValue },
	nodePath: string,
	filePath: string,
	bag: Diagnostics.Bag
): ()
	for key, value in merged do
		local kind = typeof(value)
		if kind == "boolean" or kind == "number" or kind == "string" then
			destination[key] = value :: PlanPropertyValue
		else
			bag:Add({
				Severity = "warning",
				Code = "plan/non-primitive-property",
				Message = Messages.PlanNonPrimitiveProperty(nodePath, key, describeNonPrimitiveKind(value)),
				NodePath = nodePath,
				Field = key,
				FilePath = filePath,
			})
		end
	end
end

local function warnAttributesIfAny(attributes: { [string]: JsonValue.JsonValue }, nodePath: string, filePath: string, bag: Diagnostics.Bag): ()
	local names: { string } = {}
	for key, _ in attributes do
		table.insert(names, key)
	end
	if #names == 0 then
		return
	end
	table.sort(names)
	bag:Add({
		Severity = "warning",
		Code = "plan/attributes-unsupported",
		Message = Messages.PlanAttributesUnsupported(nodePath, names),
		NodePath = nodePath,
		FilePath = filePath,
	})
end

--------------------------------------------------------------------------------------------------
-- Recursão principal -- quatro funções mutuamente recursivas, pré-declaradas com assinatura
-- tipada (regra 01) pra permitir a referência cruzada antes da definição completa.
--------------------------------------------------------------------------------------------------

local resolveCore: (
	jsonNode: ProjectFile.ProjectNode?,
	name: string,
	nodePath: string,
	parentClassName: string?,
	containerFolderPath: string,
	discoveredAbsolutePath: string?,
	adjacentMetaPath: string?,
	isRoot: boolean,
	cycleGuard: { [string]: boolean },
	cycleChain: { string },
	currentProjectFilePath: string,
	-- task-cli-008: profundidade de recursão REAL acumulada até este nó (ver `MAX_PLAN_DEPTH`,
	-- acima) -- não confundir com `#cycleChain` (que só cresce ao entrar num projeto aninhado);
	-- esta conta TAMBÉM cada nível de pasta comum.
	depth: number,
	ctx: PlanContext
) -> CoreResolution?

local planChildrenOf: (
	core: CoreResolution,
	jsonNode: ProjectFile.ProjectNode?,
	containerFolderPath: string,
	nodePath: string,
	ownClassName: string,
	cycleGuard: { [string]: boolean },
	cycleChain: { string },
	currentProjectFilePath: string,
	depth: number,
	ctx: PlanContext
) -> { PlanNode }

local planChildNode: (
	spec: ChildSpec,
	containerFolderPath: string,
	parentClassName: string,
	nodePath: string,
	adjacentMetaPath: string?,
	cycleGuard: { [string]: boolean },
	cycleChain: { string },
	currentProjectFilePath: string,
	depth: number,
	ctx: PlanContext
) -> PlanNode?

local planProjectTree: (
	project: ProjectFile.Project,
	cycleGuard: { [string]: boolean },
	cycleChain: { string },
	depth: number,
	ctx: PlanContext
) -> (RootResolution?, { PlanNode })

resolveCore = function(
	jsonNode: ProjectFile.ProjectNode?,
	name: string,
	nodePath: string,
	parentClassName: string?,
	containerFolderPath: string,
	discoveredAbsolutePath: string?,
	adjacentMetaPath: string?,
	isRoot: boolean,
	cycleGuard: { [string]: boolean },
	cycleChain: { string },
	currentProjectFilePath: string,
	depth: number,
	ctx: PlanContext
): CoreResolution?
	local bag = ctx.Bag
	local options = ctx.Options

	-- task-cli-008: checado ANTES de qualquer trabalho (inclusive I/O) -- ver `MAX_PLAN_DEPTH`,
	-- acima do arquivo, pro número escolhido e a justificativa completa. Contador simples,
	-- independente de `cycleGuard`/`normalizePath` -- cobre vetor de recursão de PASTA COMUM
	-- (sem "$path" nenhum envolvido), que a detecção de ciclo por path nunca cobre.
	if depth > MAX_PLAN_DEPTH then
		bag:Add({
			Severity = "error",
			Code = "plan/max-depth-exceeded",
			Message = Messages.PlanMaxDepthExceeded(nodePath, MAX_PLAN_DEPTH),
			NodePath = nodePath,
			FilePath = currentProjectFilePath,
		})
		return nil
	end

	local explicitClassName: string? = nil
	if jsonNode ~= nil then
		explicitClassName = jsonNode.ClassName
	end

	-- CORREÇÃO task-cli-014: `infer_class_name` real tem 3 ramos MUTUAMENTE EXCLUSIVOS por
	-- `parentClassName` (comentário do cabeçalho do arquivo) -- por isso é um `if`/`elseif`, não
	-- três checagens independentes que poderiam competir pelo mesmo nó. Ramo "DataModel -> Service"
	-- fica AQUI (depende de `options.IsServiceClass`, que só `TreePlanner` recebe injetado); ramos
	-- "StarterPlayer"/"Workspace" -> filho fixo ficam em `SyncRules` (dados puros, sem depender de
	-- nenhuma classe real).
	local inferredClassName: string? = nil
	if parentClassName == "DataModel" then
		if options.IsServiceClass(name) then
			inferredClassName = name
		end
	elseif parentClassName ~= nil then
		inferredClassName = SyncRules.InferFixedChildClassName(parentClassName, name)
	end

	-- 1) `$path` (explícito) OU descoberta do pai -> caminho absoluto alvo (ou omissão/erro).
	local ownAbsolutePath: string? = nil
	local pathNode: ProjectFile.PathNode? = nil
	if jsonNode ~= nil then
		pathNode = jsonNode.Path
	end

	if pathNode ~= nil then
		-- Normalizado AQUI, no ponto em que "$path" vira caminho absoluto -- todo caminho
		-- derivado a partir daqui (source, filhos de pasta, `nestedProjectFilePath`) herda a
		-- forma canônica automaticamente, porque é sempre `joinPath(<algo já canônico>, <nome
		-- puro, sem "..">)` daqui em diante (ver comentário grande no cabeçalho do arquivo).
		local candidate = normalizePath(joinPath(containerFolderPath, pathNode.Path))
		if fs.isFile(candidate) or fs.isDir(candidate) then
			ownAbsolutePath = candidate
		else
			if pathNode.Kind == "required" then
				bag:Add({
					Severity = "error",
					Code = "plan/required-path-not-found",
					Message = Messages.PlanRequiredPathNotFound(nodePath, candidate),
					NodePath = nodePath,
					Field = "$path",
					FilePath = candidate,
				})
				return nil
			end

			-- $path opcional ausente.
			if isRoot then
				if explicitClassName == nil then
					-- A raiz não pode ser "omitida" (não existiria projeto nenhum) -- vira o
					-- erro genérico de "faltou informação" em vez do info silencioso.
					bag:Add({
						Severity = "error",
						Code = "plan/missing-class-name",
						Message = Messages.PlanMissingClassName(nodePath),
						NodePath = nodePath,
						FilePath = currentProjectFilePath,
					})
					return nil
				end
			elseif explicitClassName == nil and inferredClassName == nil then
				bag:Add({
					Severity = "info",
					Code = "plan/optional-path-omitted",
					Message = Messages.PlanOptionalPathOmitted(nodePath, candidate),
					NodePath = nodePath,
					Field = "$path",
					FilePath = candidate,
				})
				return nil
			end
			-- senão: segue sem contribuição de `$path` (`ownAbsolutePath` permanece nil).
		end
	elseif discoveredAbsolutePath ~= nil then
		ownAbsolutePath = discoveredAbsolutePath
	end

	-- 2) Classificar o alvo (Script/LocalScript/ModuleScript/Folder/NestedProject/Unsupported/
	--    Ignored/MetaFile), consumir `init.meta.json` quando o alvo é uma pasta.
	local pathClassName: string? = nil
	local source: string? = nil
	local sourcePath: string? = nil
	local fsChildBaseDir: string? = nil
	local fsChildEntries: { string }? = nil
	local fsInitFileName: string? = nil
	local nestedProjectFilePath: string? = nil
	local isDirectoryTarget = false
	local metaProperties: { [string]: JsonValue.JsonValue } = {}
	local metaAttributes: { [string]: JsonValue.JsonValue } = {}
	local metaClassNameOverride: string? = nil

	if ownAbsolutePath ~= nil then
		local classification = classifyTarget(ownAbsolutePath)
		if classification == nil then
			bag:Add({
				Severity = "error",
				Code = "plan/io-error",
				Message = Messages.PlanIoError(nodePath, ownAbsolutePath, "path existed a moment ago but vanished while planning"),
				NodePath = nodePath,
				FilePath = ownAbsolutePath,
			})
			return nil
		end

		isDirectoryTarget = classification.IsDirectory

		if classification.Kind == "Unsupported" then
			local citedPath = ownAbsolutePath
			if classification.IsDirectory and classification.InitFileName ~= nil then
				citedPath = joinPath(classification.DirPath :: string, classification.InitFileName :: string)
			end
			bag:Add({
				Severity = "warning",
				Code = "sync/unsupported-extension",
				Message = Messages.SyncUnsupportedExtension(citedPath),
				NodePath = nodePath,
				FilePath = citedPath,
			})
		elseif classification.Kind == "Ignored" or classification.Kind == "MetaFile" then
			-- Sem contribuição, sem diagnostic -- "fora do radar" (Decisão 6) ou uso incomum de
			-- `$path` apontando direto pra um meta file (não coberto por teste).
		elseif classification.Kind == "NestedProject" then
			nestedProjectFilePath = classification.NestedProjectPath
		else
			-- Script / LocalScript / ModuleScript / Folder.
			pathClassName = classification.Kind
			sourcePath = classification.SourcePath

			-- `classification.SourcePath` é só o CAMINHO do arquivo a ler (o próprio arquivo,
			-- pra Script/LocalScript/ModuleScript de arquivo simples; `pasta/init.*`, pra
			-- pasta-Script/LocalScript/ModuleScript) -- `Source` é o CONTEÚDO, lido aqui.
			if sourcePath ~= nil then
				local readOk, textOrError = pcall(function(): unknown
					return fs.readFile(sourcePath :: string)
				end)
				if readOk then
					source = textOrError :: string
				else
					bag:Add({
						Severity = "error",
						Code = "plan/io-error",
						Message = Messages.PlanIoError(nodePath, sourcePath :: string, firstLineOf(textOrError)),
						NodePath = nodePath,
						FilePath = sourcePath,
					})
					return nil
				end
			end

			if classification.IsDirectory then
				local dirPath = classification.DirPath :: string
				local entries = classification.DirEntries :: { string }
				fsChildBaseDir = dirPath
				fsChildEntries = entries
				fsInitFileName = classification.InitFileName

				local initMetaName: string? = nil
				for _, entry in entries do
					if entry == "init.meta.json" or entry == "init.meta.jsonc" then
						initMetaName = entry
						break
					end
				end

				if initMetaName ~= nil then
					local metaData = readMetaFile(joinPath(dirPath, initMetaName), nodePath, bag)
					if metaData ~= nil then
						metaProperties = metaData.Properties
						metaAttributes = metaData.Attributes
						if metaData.ClassName ~= nil then
							if classification.Kind == "Folder" then
								metaClassNameOverride = metaData.ClassName
							else
								bag:Add({
									Severity = "error",
									Code = "plan/meta-class-name-conflict",
									Message = Messages.PlanMetaClassNameConflict(nodePath, classification.Kind),
									NodePath = nodePath,
									FilePath = joinPath(dirPath, initMetaName),
								})
								return nil
							end
						end
					end
				end
			end
		end
	end

	-- `<nome>.meta.json` adjacente (Decisão 7): só faz sentido ao lado de um ARQUIVO (pesquisa,
	-- seção 3) -- nunca sobrescreve `className` (só `init.meta.json`, de pasta, faz isso).
	if adjacentMetaPath ~= nil and not isDirectoryTarget then
		local metaData = readMetaFile(adjacentMetaPath, nodePath, bag)
		if metaData ~= nil then
			for key, value in metaData.Properties do
				metaProperties[key] = value
			end
			for key, value in metaData.Attributes do
				metaAttributes[key] = value
			end
			if metaData.ClassName ~= nil then
				bag:Add({
					Severity = "warning",
					Code = "plan/meta-field-unsupported",
					Message = Messages.PlanMetaFieldUnsupported(nodePath, "className (an adjacent .meta.json cannot set className -- only init.meta.json, on a folder, can)"),
					NodePath = nodePath,
					FilePath = adjacentMetaPath,
				})
			end
		end
	end

	-- 3) Projeto aninhado -- ramo totalmente separado: ClassName e filhos vêm da raiz do
	--    projeto aninhado (Decisão 8), nunca do resto desta função.
	if nestedProjectFilePath ~= nil then
		if cycleGuard[nestedProjectFilePath] then
			local chain = copyStringList(cycleChain)
			table.insert(chain, nestedProjectFilePath)
			bag:Add({
				Severity = "error",
				Code = "plan/nested-project-cycle",
				Message = Messages.PlanNestedProjectCycle(chain),
				NodePath = nodePath,
				FilePath = nestedProjectFilePath,
			})
			return nil
		end

		local nestedProject = ProjectFile.Read(nestedProjectFilePath, bag)
		if nestedProject == nil then
			-- `ProjectFile.Read` já colocou o(s) erro(s) de parsing no `bag`.
			return nil
		end

		local newCycleGuard = copyStringSet(cycleGuard)
		newCycleGuard[nestedProjectFilePath] = true
		local newCycleChain = copyStringList(cycleChain)
		table.insert(newCycleChain, nestedProjectFilePath)

		-- task-cli-008: entrar num projeto aninhado É um nível de recursão real (mesma família do
		-- "filho de pasta" contado em `planChildrenOf`, abaixo) -- soma ao contador, nunca reseta.
		local nestedRoot, nestedChildren = planProjectTree(nestedProject, newCycleGuard, newCycleChain, depth + 1, ctx)
		if nestedRoot == nil then
			-- Erro já reportado dentro da resolução da raiz do projeto aninhado.
			return nil
		end

		if jsonNode ~= nil and next(jsonNode.Children) ~= nil then
			bag:Add({
				Severity = "warning",
				Code = "plan/nested-project-children-ignored",
				Message = Messages.PlanNestedProjectChildrenIgnored(nodePath),
				NodePath = nodePath,
				FilePath = nestedProjectFilePath,
			})
		end

		-- Achado MÉDIO (revisor-cli-treeplanner-2026-09-05.md): um "$className" explícito era
		-- descartado em silêncio quando o "$path" do MESMO nó resolve pra um projeto aninhado --
		-- mesma classe de bug do warning acima (informação do usuário descartada), mesmo padrão
		-- de correção.
		if explicitClassName ~= nil then
			bag:Add({
				Severity = "warning",
				Code = "plan/nested-project-class-name-ignored",
				Message = Messages.PlanNestedProjectClassNameIgnored(nodePath, explicitClassName),
				NodePath = nodePath,
				Field = "$className",
				FilePath = nestedProjectFilePath,
			})
		end

		-- task-cli-018 (Decisão 15, Parte 1): a cópia começa a partir do `$properties` que a
		-- PRÓPRIA raiz do projeto aninhado já resolveu (`nestedRoot.Properties`) -- não de uma
		-- tabela vazia -- e só ENTÃO aplica o `$properties` do nó EXTERNO por cima. O nó externo
		-- continua vencendo em chave repetida (`applyProperties` sobrescreve `destination[key]`) --
		-- comportamento já shipado, é o único jeito do consumidor de um pacote Wally sobrescrever
		-- um default que o próprio pacote declarou na raiz.
		local nestedProperties: { [string]: PlanPropertyValue } = copyPlanProperties(nestedRoot.Properties)
		if jsonNode ~= nil then
			applyProperties(nestedProperties, jsonNode.Properties, nodePath, currentProjectFilePath, bag)
			warnAttributesIfAny(jsonNode.Attributes, nodePath, currentProjectFilePath, bag)
		end

		return {
			ClassName = nestedRoot.ClassName,
			IsServiceRoot = false,
			-- CORREÇÃO (bug ALTO, task-cli-018): antes, os dois eram `nil` literais aqui -- a raiz
			-- de TODO projeto aninhado (ou seja, todo pacote Wally com `default.project.json`
			-- próprio: ProfileStore, Jecs, Promise, Sera, Fusion) perdia o próprio `Source` em
			-- silêncio. `planProjectTree`, acima, já resolveu os dois de verdade -- só repassar.
			Source = nestedRoot.Source,
			SourcePath = nestedRoot.SourcePath,
			Properties = nestedProperties,
			IsNestedProject = true,
			NestedChildren = nestedChildren,
			FsChildBaseDir = nil,
			FsChildEntries = nil,
			FsInitFileName = nil,
		}
	end

	-- 4) ClassName final -- precedência real do Rojo (Decisão 4). `inferredClassName` cobre os 3
	-- ramos mutuamente exclusivos (Service, StarterPlayer->filho fixo, Workspace->Terrain) --
	-- CORREÇÃO task-cli-014, ver comentário no ponto onde é calculado, acima.
	local pathOrInferredClassName: string? = nil
	if pathClassName == "Folder" and inferredClassName ~= nil then
		pathOrInferredClassName = inferredClassName
	elseif pathClassName ~= nil then
		pathOrInferredClassName = pathClassName
	else
		pathOrInferredClassName = inferredClassName
	end

	if metaClassNameOverride ~= nil then
		-- Só chega aqui quando `pathClassName == "Folder"` (checado na leitura do
		-- `init.meta.json` acima) -- sobrescreve o que a Decisão 4 teria resolvido pra esse
		-- Folder, incluindo uma eventual inferência de Service/filho fixo (que só valeria pra um
		-- Folder).
		pathOrInferredClassName = metaClassNameOverride
	end

	local finalClassName: string? = nil
	if explicitClassName ~= nil then
		-- ACHADO/EXCEÇÃO (task-cli-018, Decisão 15 "Parte 2" -- `plan/root-source-ignored`):
		-- descoberto ao implementar o warning de `TreePlanner.Plan`, mais abaixo, que ele seria
		-- CÓDIGO MORTO sem esta exceção. A regra geral ("só é legal se $path resolver pra Folder")
		-- fica INTACTA pra qualquer outro nó -- `class-name-conflict.spec` continua cobrindo isso.
		-- Só na raiz do projeto MAIS EXTERNO (`isOutermostRoot`) com `"$className": "DataModel"`
		-- explícito -- a ÚNICA classe que só é legal bem na raiz -- "a classe explícita vence"
		-- (texto literal da Decisão 15): em vez de `plan/class-name-conflict`, o `Source`/
		-- `SourcePath` que o `$path` produziu (que `DataModel` não tem onde receber -- não existe
		-- no dump) fica sem destino, e `TreePlanner.Plan` avisa com `plan/root-source-ignored` em
		-- vez de descartar em silêncio ou barrar com um erro de conflito que a Decisão 15 não
		-- previa pra este canto. Ver Decisão 16 (task-cli-020): a exceção NÃO vale pra raiz de um
		-- projeto aninhado qualquer (`isRoot` também é `true` ali) -- só pra raiz do plano inteiro.
		local isOutermostRoot = isRoot and normalizePath(currentProjectFilePath) == ctx.OutermostProjectFilePath
		local rootDataModelSourceException = isOutermostRoot and explicitClassName == "DataModel"
		if pathClassName ~= nil and pathClassName ~= "Folder" and not rootDataModelSourceException then
			bag:Add({
				Severity = "error",
				Code = "plan/class-name-conflict",
				Message = Messages.PlanClassNameConflict(nodePath),
				NodePath = nodePath,
				Field = "$className",
				FilePath = currentProjectFilePath,
			})
			return nil
		end
		finalClassName = explicitClassName
	else
		finalClassName = pathOrInferredClassName
	end

	if finalClassName == nil then
		bag:Add({
			Severity = "error",
			Code = "plan/missing-class-name",
			Message = Messages.PlanMissingClassName(nodePath),
			NodePath = nodePath,
			FilePath = currentProjectFilePath,
		})
		return nil
	end

	-- 5) `IsServiceRoot` -- só quando o pai é o DataModel E a classe final É mesmo uma Service,
	--    independente de como ela foi resolvida (explícita, de `$path`, ou inferida).
	--
	-- DECISÃO task-cli-014: este bloco NÃO ganha um ramo equivalente para
	-- StarterPlayer->{StarterPlayerScripts, StarterCharacterScripts}/Workspace->Terrain.
	-- `IsServiceRoot` não significa "teve o ClassName inferido sem $className" -- significa
	-- "materializar via `game:GetService(ClassName)` em vez de `Services.new` + `.Parent`"
	-- (`TreeMaterializer.luau`, comentário de cabeçalho: "Nó com IsServiceRoot ->
	-- game:GetService(ClassName) ... Todo o resto -> Services.new"). StarterPlayerScripts/
	-- StarterCharacterScripts/Terrain NÃO são Services do Roblox real (não têm a tag `Service`
	-- no dump -- `Manifest.luau` confirma `IsService = false` pras três) -- não existe
	-- `game:GetService("StarterPlayerScripts")` no Roblox de verdade, então continuam
	-- materializadas como Instance comum (`Services.new` + `.Parent`), IGUAL a qualquer outro
	-- filho. A checagem abaixo continua restrita a `options.IsServiceClass(finalClassName)` de
	-- propósito -- generalizá-la pra "teve inferência" marcaria esses três como Service por
	-- engano.
	local isServiceRoot = false
	if parentClassName == "DataModel" and options.IsServiceClass(finalClassName) then
		if name == finalClassName then
			isServiceRoot = true
		else
			bag:Add({
				Severity = "error",
				Code = "plan/service-name-mismatch",
				Message = Messages.PlanServiceNameMismatch(nodePath, name, finalClassName),
				NodePath = nodePath,
				FilePath = currentProjectFilePath,
			})
			return nil
		end
	end

	-- 6) `$properties` (meta + próprio nó -- o nó vence em conflito) e `$attributes` (warning,
	--    nunca aplicado).
	local mergedProperties: { [string]: JsonValue.JsonValue } = {}
	for key, value in metaProperties do
		mergedProperties[key] = value
	end
	if jsonNode ~= nil then
		for key, value in jsonNode.Properties do
			mergedProperties[key] = value
		end
	end

	local properties: { [string]: PlanPropertyValue } = {}
	applyProperties(properties, mergedProperties, nodePath, currentProjectFilePath, bag)

	local mergedAttributes: { [string]: JsonValue.JsonValue } = {}
	for key, value in metaAttributes do
		mergedAttributes[key] = value
	end
	if jsonNode ~= nil then
		for key, value in jsonNode.Attributes do
			mergedAttributes[key] = value
		end
	end
	warnAttributesIfAny(mergedAttributes, nodePath, currentProjectFilePath, bag)

	return {
		ClassName = finalClassName,
		IsServiceRoot = isServiceRoot,
		Source = source,
		SourcePath = sourcePath,
		Properties = properties,
		IsNestedProject = false,
		NestedChildren = nil,
		FsChildBaseDir = fsChildBaseDir,
		FsChildEntries = fsChildEntries,
		FsInitFileName = fsInitFileName,
	}
end

planChildrenOf = function(
	core: CoreResolution,
	jsonNode: ProjectFile.ProjectNode?,
	containerFolderPath: string,
	nodePath: string,
	ownClassName: string,
	cycleGuard: { [string]: boolean },
	cycleChain: { string },
	currentProjectFilePath: string,
	depth: number,
	ctx: PlanContext
): { PlanNode }
	if core.IsNestedProject then
		return core.NestedChildren :: { PlanNode }
	end

	local specs: { [string]: ChildSpec } = {}
	local order: { string } = {}
	local metaTargets: { [string]: string } = {}

	local function ensureSpec(childName: string): ChildSpec
		local existing = specs[childName]
		if existing ~= nil then
			return existing
		end
		local created: ChildSpec = { Name = childName, JsonNode = nil, DiscoveredAbsolutePath = nil }
		specs[childName] = created
		table.insert(order, childName)
		return created
	end

	if core.FsChildBaseDir ~= nil and core.FsChildEntries ~= nil then
		local baseDir = core.FsChildBaseDir :: string
		local entries = core.FsChildEntries :: { string }

		for _, entry in entries do
			if entry == core.FsInitFileName then
				continue
			end

			local entryAbsolutePath = joinPath(baseDir, entry)
			if fs.isFile(entryAbsolutePath) then
				local kind, strippedName = SyncRules.ClassifyFile(entry)
				if kind == "MetaFile" then
					metaTargets[strippedName] = entryAbsolutePath
				elseif kind == "Ignored" then
					-- Fora do radar (Decisão 6) -- nenhum diagnostic.
				elseif kind == "Unsupported" then
					ctx.Bag:Add({
						Severity = "warning",
						Code = "sync/unsupported-extension",
						Message = Messages.SyncUnsupportedExtension(entryAbsolutePath),
						NodePath = `{nodePath}.{strippedName}`,
						FilePath = entryAbsolutePath,
					})
				else
					local spec = ensureSpec(strippedName)
					spec.DiscoveredAbsolutePath = entryAbsolutePath
				end
			else
				local spec = ensureSpec(entry)
				spec.DiscoveredAbsolutePath = entryAbsolutePath
			end
		end
	end

	if jsonNode ~= nil then
		for childName, childJsonNode in jsonNode.Children do
			local spec = ensureSpec(childName)
			spec.JsonNode = childJsonNode
		end
	end

	table.sort(order)

	local children: { PlanNode } = {}
	for _, childName in order do
		local spec = specs[childName]
		local childNodePath = `{nodePath}.{childName}`

		local hasOwnPath = false
		if spec.JsonNode ~= nil and spec.JsonNode.Path ~= nil then
			hasOwnPath = true
		end

		local adjacentMetaPath: string? = nil
		if spec.DiscoveredAbsolutePath ~= nil and not hasOwnPath then
			adjacentMetaPath = metaTargets[childName]
		end

		-- task-cli-008: cada filho de pasta é UM NÍVEL a mais que o pai (`core`) -- é este "+1",
		-- repetido a cada chamada recursiva, que faz o contador crescer com a árvore real, nunca
		-- amarrado a nenhum path específico (vetor de pasta comum, sem "$path" nenhum).
		local planned = planChildNode(spec, containerFolderPath, ownClassName, childNodePath, adjacentMetaPath, cycleGuard, cycleChain, currentProjectFilePath, depth + 1, ctx)
		if planned ~= nil then
			table.insert(children, planned)
		end
	end

	return children
end

planChildNode = function(
	spec: ChildSpec,
	containerFolderPath: string,
	parentClassName: string,
	nodePath: string,
	adjacentMetaPath: string?,
	cycleGuard: { [string]: boolean },
	cycleChain: { string },
	currentProjectFilePath: string,
	depth: number,
	ctx: PlanContext
): PlanNode?
	local core = resolveCore(
		spec.JsonNode,
		spec.Name,
		nodePath,
		parentClassName,
		containerFolderPath,
		spec.DiscoveredAbsolutePath,
		adjacentMetaPath,
		false,
		cycleGuard,
		cycleChain,
		currentProjectFilePath,
		depth,
		ctx
	)
	if core == nil then
		return nil
	end

	local children = planChildrenOf(core, spec.JsonNode, containerFolderPath, nodePath, core.ClassName, cycleGuard, cycleChain, currentProjectFilePath, depth, ctx)

	return {
		Name = spec.Name,
		ClassName = core.ClassName,
		IsServiceRoot = core.IsServiceRoot,
		Source = core.Source,
		SourcePath = core.SourcePath,
		Properties = core.Properties,
		Children = children,
		NodePath = nodePath,
	}
end

planProjectTree = function(
	project: ProjectFile.Project,
	cycleGuard: { [string]: boolean },
	cycleChain: { string },
	depth: number,
	ctx: PlanContext
): (RootResolution?, { PlanNode })
	local core = resolveCore(
		project.Tree,
		"<root>",
		project.Tree.NodePath,
		nil,
		project.FolderPath,
		nil,
		nil,
		true,
		cycleGuard,
		cycleChain,
		project.FilePath,
		depth,
		ctx
	)
	if core == nil then
		return nil, {}
	end

	local children = planChildrenOf(core, project.Tree, project.FolderPath, project.Tree.NodePath, core.ClassName, cycleGuard, cycleChain, project.FilePath, depth, ctx)

	-- task-cli-018 (Decisão 15): devolve o registro inteiro (`Source`/`SourcePath`/`Properties`
	-- inclusos), não só o `ClassName` -- é isto que permite ao ramo de projeto aninhado de
	-- `resolveCore` (acima) repassar o `Source`/`Properties` da raiz aninhada em vez de descartá-
	-- los, e ao `TreePlanner.Plan` (abaixo) preencher `InstancePlan.RootProperties`/avisar sobre
	-- `Source` perdido na raiz de topo.
	local rootResolution: RootResolution = {
		ClassName = core.ClassName,
		Source = core.Source,
		SourcePath = core.SourcePath,
		Properties = core.Properties,
	}
	return rootResolution, children
end

--------------------------------------------------------------------------------------------------
-- API pública
--------------------------------------------------------------------------------------------------

-- Devolve `nil` SE E SOMENTE SE `bag:HasErrors()` for `true` ao final (mesmo contrato de
-- `ProjectFile.Read` -- consistência entre os dois módulos do território que já fazem
-- "acumula tudo, falha no final" em vez de abortar no primeiro problema, Decisão 3).
function TreePlanner.Plan(project: ProjectFile.Project, options: PlanOptions, bag: Diagnostics.Bag): InstancePlan?
	-- Semeado com a forma NORMALIZADA de `project.FilePath` -- um projeto aninhado, em algum
	-- lugar da árvore, pode acabar resolvendo de volta pro PRÓPRIO arquivo raiz (não só entre
	-- dois projetos aninhados); a semente precisa estar na mesma forma canônica que
	-- `nestedProjectFilePath` (normalizado no ponto em que "$path" vira caminho absoluto,
	-- acima) pra essa comparação de string funcionar em qualquer caso. Calculado ANTES do `ctx`
	-- (função pura, sem efeito colateral) porque também preenche `ctx.OutermostProjectFilePath`
	-- (Decisão 16).
	local normalizedProjectFilePath = normalizePath(project.FilePath)
	local ctx: PlanContext = { Options = options, Bag = bag, OutermostProjectFilePath = normalizedProjectFilePath }
	local cycleGuard: { [string]: boolean } = { [normalizedProjectFilePath] = true }
	local cycleChain: { string } = { normalizedProjectFilePath }

	local rootResolution, roots = planProjectTree(project, cycleGuard, cycleChain, 0, ctx)

	if bag:HasErrors() then
		return nil
	end

	-- Declarado com o tipo FINAL (`string`, nunca `string?`) explícito -- reatribuir um valor não-
	-- nil a uma variável inferida como `T?` não muda o tipo ESTÁTICO da variável pro resto do
	-- escopo (só a narrowing de controle de fluxo dentro do próprio `if` faz isso); anotar o tipo
	-- na declaração é o jeito de garantir `string` puro daqui em diante.
	local projectName: string
	if project.Name ~= nil then
		projectName = project.Name
	else
		projectName = ""
	end

	-- task-cli-018 (Decisão 15, Parte 2): `resolvedRootClassName`/`rootProperties` vêm do MESMO
	-- registro agora -- antes só o `ClassName` sobrevivia até aqui.
	local resolvedRootClassName: string
	local rootProperties: { [string]: PlanPropertyValue }
	if rootResolution ~= nil then
		resolvedRootClassName = rootResolution.ClassName
		rootProperties = rootResolution.Properties
	else
		resolvedRootClassName = ""
		rootProperties = {}
	end

	-- task-cli-018 (Decisão 15, Parte 2): único canto em que um `Source` resolvido pela raiz de
	-- TOPO não tem onde ser aplicado -- a raiz é um `DataModel` explícito (não tem a propriedade
	-- `Source` no dump) mas o próprio "$path" da raiz também produziu código (só possível com a
	-- exceção estreita de `resolveCore`, ver comentário lá, "plan/class-name-conflict"). Fora
	-- deste canto, um `Source` de raiz sempre tem destino: uma raiz que resolve pra
	-- Script/LocalScript/ModuleScript sem "$className" explícito já erra em
	-- `materialize/root-not-datamodel` (TreeMaterializer) -- nada silencioso. Avisar em vez de
	-- descartar em silêncio (regra 00).
	if rootResolution ~= nil and rootResolution.Source ~= nil and resolvedRootClassName == "DataModel" then
		local rootSourcePath = rootResolution.SourcePath
		if rootSourcePath ~= nil then
			bag:Add({
				Severity = "warning",
				Code = "plan/root-source-ignored",
				Message = Messages.PlanRootSourceIgnored(project.Tree.NodePath, rootSourcePath),
				NodePath = project.Tree.NodePath,
				Field = "$path",
				FilePath = rootSourcePath,
			})
		end
	end

	return {
		ProjectName = projectName,
		ProjectPath = project.FilePath,
		RootClassName = resolvedRootClassName,
		RootProperties = rootProperties,
		Roots = roots,
		Diagnostics = bag:All(),
	}
end

-- Exportado só pra `TreePlanner.spec.luau` poder gerar uma cadeia de pastas mais funda que o
-- limite sem duplicar o número mágico (task-cli-008) -- não é uma opção configurável, é o MESMO
-- valor que `resolveCore` usa internamente (a constante `MAX_PLAN_DEPTH`, acima).
TreePlanner.MAX_PLAN_DEPTH = MAX_PLAN_DEPTH

return TreePlanner
