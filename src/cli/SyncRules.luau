--!strict

--[[
	Convenção arquivo/pasta -> ClassName do Rojo (arquiteto-cli-2026-09-05.md, Decisão 6;
	pesquisa-formato-projeto-rojo-2026-09-05.md, seção 3). Dados puros, SEM I/O -- não toca
	`@lune/fs`, não conhece caminho absoluto nenhum. `TreePlanner.luau` é o único consumidor.

	Fonte de verdade: código-fonte real do Rojo, branch `master`, correspondente à release
	publicada **v7.7.0** (2026-07-01) -- `default_sync_rules()` e `get_dir_middleware()` em
	`src/snapshot_middleware/mod.rs`, linha 110-150 e 419-444 (pesquisa, seção 3). Pesquisa feita
	em 2026-09-05, NÃO reconferida aqui.

	ORDEM É SEMÂNTICA em `ClassifyFile`: primeira regra que casa vence (comentário do próprio
	código do Rojo: a ordem de `ClassifyDir` "não pode mudar por compatibilidade"). Um sufixo mais
	específico (`.server.lua`, `.plugin.lua`, `.meta.json`, `.project.json`, `.model.json`)
	SEMPRE aparece antes do sufixo genérico que o conteria (`.lua`, `.json`) -- senão
	`Combat.server.lua` cairia no match genérico `.lua` e viraria `ModuleScript` por engano
	(exatamente o tipo de divergência silenciosa que a regra 00 proíbe).

	TERCEIRA CATEGORIA além de "suportado" e "Unsupported reconhecido e reportado" (arquiteto NÃO
	tinha essa distinção explícita no `FileKind` de 6 valores do desenho original -- esta é uma
	extensão ADITIVA, decidida aqui, dentro do próprio território desta tarefa, sem consumidor
	fora de `TreePlanner.luau`): `"Ignored"`. É a extensão que o Rojo real simplesmente não
	reconhece em NENHUMA regra de sync (nem suportada, nem a lista de "fora da leva 1") -- o Rojo
	de verdade não gera warning nenhum pra ela, só ignora o arquivo por completo ("fora do radar").
	Tratar isso como `"Unsupported"` mentiria (geraria um warning que o Rojo real nunca geraria
	pra esse arquivo); tratar como qualquer um dos kinds "reais" mentiria pior ainda. `"Ignored"`
	é o único jeito honesto de representar essa terceira categoria sem inventar um warning que não
	existe no motor real.
]]

export type FileKind = "Script" | "LocalScript" | "ModuleScript" | "NestedProject" | "MetaFile" | "Unsupported" | "Ignored"

export type DirKind = "NestedProject" | "ModuleScript" | "Script" | "LocalScript" | "Folder" | "Unsupported"

local SyncRules = {}

--[[
	CORREÇÃO task-cli-014 (achado do testador, pesquisa-formato-projeto-rojo-2026-09-05.md, seção
	"Correção 2026-09-05"): `infer_class_name` do Rojo real (`src/snapshot_middleware/project.rs`)
	tem 3 ramos `if`/`else if` MUTUAMENTE EXCLUSIVOS por `parentClassName` -- não é "tenta os 3",
	é "só um se aplica, escolhido pelo pai":
		1. `parentClassName == "DataModel"` -> qualquer classe com a tag `Service` no dump
		   (DINÂMICO -- `TreePlanner` resolve isso à parte, via `options.IsServiceClass` injetado
		   de `services`, porque `SyncRules` não tem acesso a nenhuma classe real).
		2. `parentClassName == "StarterPlayer"` -> `"StarterPlayerScripts"`/`"StarterCharacterScripts"`
		   (HARDCODED -- comparação de string literal, nunca consulta reflection database).
		3. `parentClassName == "Workspace"` -> `"Terrain"` (HARDCODED, mesma forma).
	Esta tabela cobre SÓ os ramos 2 e 3 (hardcoded, dados puros) -- o ramo 1 (Service, dinâmico)
	fica em `TreePlanner.luau`, que já o resolvia corretamente antes desta correção. Os dois
	mecanismos nunca competem pelo mesmo nó (um nó só tem UM `parentClassName` concreto).
]]
local FIXED_CHILD_CLASS_NAMES: { [string]: { [string]: boolean } } = {
	StarterPlayer = { StarterPlayerScripts = true, StarterCharacterScripts = true },
	Workspace = { Terrain = true },
}

-- `endsWith` + índice de corte -- puramente textual (nenhum acesso a filesystem neste módulo).
local function endsWith(text: string, suffix: string): boolean
	local suffixLength = #suffix
	if suffixLength >= #text then
		-- `>=`, não `>`: um arquivo cujo NOME INTEIRO é igual ao sufixo (ex.: um arquivo
		-- literalmente chamado ".lua", sem nada antes) não produziria um nome de Instance útil
		-- (ficaria vazio) -- tratado como não-casado, cai pra próxima regra (ou "Ignored" no fim).
		return false
	end
	return string.sub(text, -suffixLength) == suffix
end

-- Tabela ORDENADA (Decisão 6) -- primeiro casamento vence. Sufixos específicos ANTES dos
-- genéricos que os conteriam. Ordem exata verificada contra a pesquisa (seção 3):
--   .server.lua|luau -> Script
--   .client.lua|luau -> LocalScript
--   .plugin.lua|luau -> Unsupported (leva 1 não simula plugin de Studio -- não faz sentido fora
--       do Studio; teria que vir ANTES de .lua|luau genérico, senão cairia lá por engano)
--   .lua|luau (sobra) -> ModuleScript
--   .project.json|jsonc -> NestedProject
--   .meta.json|jsonc -> MetaFile (não é Instance -- metadado do irmão, Decisão 7)
--   .model.json|jsonc -> Unsupported (formato não confirmado pela pesquisa, "Incerto")
--   .json|jsonc (sobra, fora de meta/model/project) -> Unsupported
--   .toml / .yml / .yaml / .csv / .txt / .rbxm / .rbxmx -> Unsupported
local FILE_SUFFIX_RULES: { { Suffix: string, Kind: FileKind } } = {
	{ Suffix = ".server.lua", Kind = "Script" },
	{ Suffix = ".server.luau", Kind = "Script" },
	{ Suffix = ".client.lua", Kind = "LocalScript" },
	{ Suffix = ".client.luau", Kind = "LocalScript" },
	{ Suffix = ".plugin.lua", Kind = "Unsupported" },
	{ Suffix = ".plugin.luau", Kind = "Unsupported" },
	{ Suffix = ".lua", Kind = "ModuleScript" },
	{ Suffix = ".luau", Kind = "ModuleScript" },
	{ Suffix = ".project.json", Kind = "NestedProject" },
	{ Suffix = ".project.jsonc", Kind = "NestedProject" },
	{ Suffix = ".meta.json", Kind = "MetaFile" },
	{ Suffix = ".meta.jsonc", Kind = "MetaFile" },
	{ Suffix = ".model.json", Kind = "Unsupported" },
	{ Suffix = ".model.jsonc", Kind = "Unsupported" },
	{ Suffix = ".json", Kind = "Unsupported" },
	{ Suffix = ".jsonc", Kind = "Unsupported" },
	{ Suffix = ".toml", Kind = "Unsupported" },
	{ Suffix = ".yml", Kind = "Unsupported" },
	{ Suffix = ".yaml", Kind = "Unsupported" },
	{ Suffix = ".csv", Kind = "Unsupported" },
	{ Suffix = ".txt", Kind = "Unsupported" },
	{ Suffix = ".rbxm", Kind = "Unsupported" },
	{ Suffix = ".rbxmx", Kind = "Unsupported" },
}

-- `fileName` é só o NOME do arquivo (sem diretório) -- `TreePlanner` é quem resolve caminho
-- absoluto; este módulo não sabe onde o arquivo mora. Devolve o `FileKind` e o nome da Instance
-- SEM a extensão casada (ex.: `"Combat.server.lua"` -> `("Script", "Combat")`). Pra `"Ignored"`
-- (nenhuma regra casou), o segundo valor é o `fileName` completo -- não há extensão conhecida
-- pra cortar, e ninguém deveria usar esse nome pra criar uma Instance de qualquer forma.
function SyncRules.ClassifyFile(fileName: string): (FileKind, string)
	for _, rule in FILE_SUFFIX_RULES do
		if endsWith(fileName, rule.Suffix) then
			return rule.Kind, string.sub(fileName, 1, #fileName - #rule.Suffix)
		end
	end
	return "Ignored", fileName
end

-- Ordem de prioridade FIXA (pesquisa, seção 3: comentada no código do Rojo como "não pode mudar
-- por compatibilidade") -- `default.project.json`/`.jsonc` vence TUDO, inclusive `init.*`.
-- `entries` são só os NOMES dos itens dentro do diretório (o que `@lune/fs.readDir` devolve) --
-- este módulo não faz I/O, `TreePlanner` já leu o diretório antes de chamar isto.
--
-- `dirName` (nome da própria pasta) é aceito pra manter paridade com a assinatura documentada no
-- desenho do arquiteto, mas NÃO participa de nenhuma regra de classificação nesta leva -- o nome
-- da Instance de um `Folder`/pasta-`ModuleScript` vem da CHAVE do `.project.json` ou do nome do
-- diretório em si, decisão de `TreePlanner`, nunca deste módulo.
function SyncRules.ClassifyDir(_dirName: string, entries: { string }): (DirKind, string?)
	local present: { [string]: boolean } = {}
	for _, entry in entries do
		present[entry] = true
	end

	if present["default.project.json"] then
		return "NestedProject", "default.project.json"
	end
	if present["default.project.jsonc"] then
		return "NestedProject", "default.project.jsonc"
	end

	if present["init.luau"] then
		return "ModuleScript", "init.luau"
	end
	if present["init.lua"] then
		return "ModuleScript", "init.lua"
	end

	if present["init.server.luau"] then
		return "Script", "init.server.luau"
	end
	if present["init.server.lua"] then
		return "Script", "init.server.lua"
	end

	if present["init.client.luau"] then
		return "LocalScript", "init.client.luau"
	end
	if present["init.client.lua"] then
		return "LocalScript", "init.client.lua"
	end

	if present["init.plugin.luau"] then
		return "Unsupported", "init.plugin.luau"
	end
	if present["init.plugin.lua"] then
		return "Unsupported", "init.plugin.lua"
	end

	if present["init.csv"] then
		return "Unsupported", "init.csv"
	end

	return "Folder", nil
end

-- Ramos hardcoded (2 e 3) de `infer_class_name` do Rojo real -- ver comentário da tabela
-- `FIXED_CHILD_CLASS_NAMES` acima. NÃO cobre o ramo 1 (`parentClassName == "DataModel"` ->
-- Service): esse é dinâmico (consulta o dump via `IsServiceClass`, injetada de fora) e continua
-- resolvido por `TreePlanner.luau`, nunca por este módulo (Decisão 6: `SyncRules` é dados puros,
-- sem I/O nem acoplamento a `runtime`/`services`). Devolve `nil` quando `parentClassName` não é
-- um dos pais reconhecidos (`"StarterPlayer"`/`"Workspace"`) OU `name` não é um filho fixo
-- daquele pai -- caller (`TreePlanner`) trata `nil` como "nenhuma inferência disponível", igual
-- ao `infer_class_name` real que cai no `None` final.
function SyncRules.InferFixedChildClassName(parentClassName: string, name: string): string?
	local knownChildren = FIXED_CHILD_CLASS_NAMES[parentClassName]
	if knownChildren == nil then
		return nil
	end
	if knownChildren[name] then
		return name
	end
	return nil
end

return SyncRules
