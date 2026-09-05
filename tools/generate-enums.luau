--!strict

--[[
	Gerador dev-time do território `valuetypes` (task-valuetypes-003) -- ARQUIVO NOVO E EXCLUSIVO
	desta tarefa, distinto de `tools/generate-services.luau` (território de `coder-services`; não
	tocado por este arquivo, nem o contrário). Lê a seção `Enums` do Roblox API Dump oficial e emite
	`src/valuetypes/generated/EnumData.luau` -- dados PUROS (Name/Value por item, por enum), sem
	NENHUMA lógica de `Enums`/`Enum`/`EnumItem` (typeof, GetEnumItems/FromName/FromValue, memoização,
	internamento) -- essa lógica vive em `src/valuetypes/types/Enum.luau`, que consome este módulo
	gerado. Mesma separação "dado vs. comportamento" que `tools/generate-services.luau` já usa entre
	`generated/classes/*.luau` (dado) e `src/services/behavior/*` (comportamento).

	Espelha `tools/generate-services.luau` (mesmo espírito, cópia própria do código de lock/cache --
	os dois são SCRIPTS dev-time independentes, nenhum faz `require` do outro):
	 - mesmo `tools/api-dump.lock.json` (mesma versão do dump FIXADA -- regra 03: atualizar é decisão
	   explícita, nunca automática a cada geração);
	 - mesmo cache local em `.cache/api-dump/<commit>.json`, com validação de `sizeBytes`+`sha256` --
	   ABORTA se divergir, nunca gera contra um dump que não bate com o lock;
	 - mesmo cabeçalho "GERADO -- NÃO EDITAR À MÃO" no arquivo emitido;
	 - mesmo relatório de contagem impresso no fim.

	Invocação: `lune run tools/generate-enums` -- script DEV-TIME, manual, nunca requerido por `src/`
	nem rodado em `luaubench run`/CI de release (regra 01, seção Performance: o dado gerado já
	commitado é lido por `require`, nunca reparseado do dump a cada `luaubench run`).

	Território exclusivo desta tarefa: `tools/generate-enums.luau` +
	`src/valuetypes/generated/EnumData.luau`. NÃO toca `tools/generate-services.luau`,
	`tools/coverage.luau`, `tools/capabilities.lock.json` nem nada em `src/services/`, `src/runtime/`,
	`src/cli/` (territórios de outros agentes).

	## Fatos empíricos usados aqui (verificados nesta tarefa com `lune run` sobre um script
	## descartável de scratchpad, contra `.cache/api-dump/28360dea4b90b35dc3fe9f829baae64fb6c50e75.json`
	## -- não é suposição, é leitura direta do dump pinado; complementa
	## `.claude/agents-memory/pesquisa-datatypes-color-udim-enum-2026-09-05.md`, seção D.1)

	- 629 enums, 3611 itens no total -- confere com a seção D.3 da pesquisa.
	- Todo `Value` de item é um inteiro não-negativo (mínimo 0, máximo 1048576 neste dump) -- nenhum
	  valor fracionário, nenhum negativo. `tostring(value)` embute um literal numérico Luau válido
	  sem risco de notação científica nessa faixa.
	- Nenhum nome de enum colide entre si; nenhum nome de item colide com outro item DENTRO do mesmo
	  enum (sem ambiguidade de `itemsByName`/`itemsByValue` dentro de um enum).
	- ACHADO RELEVANTE PARA `types/Enum.luau`: existem itens cujo `Name` é literalmente `"Name"`
	  (`CompletionItemKind.Value`, `LexemeType.Name`, `SortOrder.Name`) -- ou seja, um item de enum
	  pode se chamar "Name" ou "Value". Isso só é seguro porque o datatype `Enum` (o objeto de UM
	  enum, ex. `Enum.SortOrder`) NÃO tem propriedades `.Name`/`.Value` documentadas (só `EnumItem`
	  tem -- confirmado na pesquisa, seção D.2, tabela de membros) -- `types/Enum.luau` NÃO reserva
	  essas chaves no objeto "Enum", só faz lookup de item por nome, então `Enum.SortOrder.Name`
	  resolve para o EnumItem "Name" de SortOrder sem ambiguidade nenhuma. Nenhum item colide com os
	  nomes dos MÉTODOS do objeto "Enum" (`GetEnumItems`/`FromName`/`FromValue`), nem nenhum nome de
	  ENUM colide com o método do objeto raiz (`GetEnums`) -- verificado nesta tarefa.
]]

local fs = require("@lune/fs")
local net = require("@lune/net")
local serde = require("@lune/serde")
local process = require("@lune/process")

-- ============================================================================================
-- Tipos locais do dump decodificado -- `serde.decode` devolve `unknown` no typedef do Lune
-- (regra 01: sem `any`); a variável que recebe o retorno é estreitada por UM cast explícito para
-- os tipos abaixo, reflexo empírico da seção `Enums` confirmado por inspeção direta (ver cabeçalho
-- e a pesquisa D.1) -- nunca suposição.
-- ============================================================================================

type RawEnumItem = {
	Name: string,
	Value: number,
	-- `Tags`/`LegacyNames` existem no dump (pesquisa D.1: 152 itens com Tags=["Deprecated"], 55 com
	-- LegacyNames) mas não são emitidos aqui de propósito: nenhum dos dois fica exposto a um script
	-- Roblox real via API de `EnumItem` (não existe `enumItem.Deprecated`/`.LegacyNames` no Roblox
	-- real) -- omitir não é perda de fidelidade, é a MESMA superfície que o Roblox real exporia.
}

type RawEnum = {
	Name: string,
	Items: { RawEnumItem },
	-- `Tags` no nível do enum (6 dos 629, sempre ["Deprecated"], pesquisa D.1) também omitido pelo
	-- mesmo motivo: não há API real para um script consultar "este Enum é deprecated".
}

type RawDump = {
	Classes: unknown,
	Enums: { RawEnum },
	Version: number,
}

type ApiDumpLock = {
	commit: string,
	robloxVersion: string,
	dumpSchemaVersion: number,
	url: string,
	sizeBytes: number,
	sha256: string,
}

-- ============================================================================================
-- abort/lock/cache -- mesma lógica de `tools/generate-services.luau` (mesmo lock, mesma
-- validação), reproduzida aqui porque os dois geradores são scripts dev-time INDEPENDENTES: nenhum
-- faz `require` do outro (evita acoplar dois territórios de agentes diferentes por um `require` de
-- conveniência).
-- ============================================================================================

-- ACHADO DE TOOLING já registrado por `tools/generate-services.luau` (reconfirmado aqui, mesmo
-- Lune/luau-lsp desta sessão): `process.exit` é `-> never` no typedef do Lune, mas o checker não
-- propaga isso pra considerar `abort` como "todo codepath retorna never" -- por isso todo chamador
-- que precisa de exaustividade depois de `abort` tem um `return` explícito logo depois, nunca
-- depende de inferência de fluxo através deste helper.
local function abort(message: string): ()
	print(`[generate-enums] ERRO: {message}`)
	process.exit(1)
end

local function readJsonFile(path: string): unknown
	if not fs.isFile(path) then
		abort(`arquivo de lock ausente: {path}`)
	end
	local contents = fs.readFile(path)
	local decoded: unknown = serde.decode("json", contents)
	return decoded
end

local dumpLockRaw = readJsonFile("tools/api-dump.lock.json")
local dumpLock = dumpLockRaw :: ApiDumpLock

local CACHE_DIR = ".cache/api-dump"
local cachePath = `{CACHE_DIR}/{dumpLock.commit}.json`

local function validateDumpBytes(bytes: string, context: string): ()
	if #bytes ~= dumpLock.sizeBytes then
		abort(
			`{context}: tamanho do dump ({#bytes} bytes) diverge de tools/api-dump.lock.json `
				.. `(esperado {dumpLock.sizeBytes} bytes) -- a versão do dump mudou? atualize o lock deliberadamente, nunca em silêncio`
		)
	end
	local hash = serde.hash("sha256", bytes)
	if hash ~= dumpLock.sha256 then
		abort(
			`{context}: sha256 do dump ({hash}) diverge de tools/api-dump.lock.json `
				.. `(esperado {dumpLock.sha256}) -- a versão do dump mudou? atualize o lock deliberadamente, nunca em silêncio`
		)
	end
end

local function loadDumpBytes(): string
	if fs.isFile(cachePath) then
		local cached = fs.readFile(cachePath)
		validateDumpBytes(cached, `cache local ({cachePath})`)
		return cached
	end

	print(`[generate-enums] baixando dump de {dumpLock.url} ...`)
	local response = net.request({ url = dumpLock.url, method = "GET" })
	if not response.ok then
		abort(`falha ao baixar o dump: HTTP {response.statusCode} {response.statusMessage}`)
	end
	local bytes = response.body
	validateDumpBytes(bytes, "dump baixado agora")

	if not fs.isDir(CACHE_DIR) then
		fs.writeDir(CACHE_DIR)
	end
	fs.writeFile(cachePath, bytes)
	return bytes
end

local dumpBytes = loadDumpBytes()

local decodedDump: unknown = serde.decode("json", dumpBytes)
local dump = decodedDump :: RawDump

if dump.Version ~= 1 then
	abort(
		`esquema do dump (campo "Version") é {tostring(dump.Version)}, esperado 1 -- o formato do `
			.. `Full-API-Dump.json mudou; este gerador precisa ser revisado antes de continuar (nunca gerar contra um esquema desconhecido)`
	)
end

-- ============================================================================================
-- Emissão de literais Luau -- `string.format("%q", ...)` escapa qualquer conteúdo com segurança
-- (mesma disciplina de `tools/generate-services.luau:luaStringLiteral`).
-- ============================================================================================

local function luaStringLiteral(value: string): string
	return string.format("%q", value)
end

local FILE_HEADER = `--!strict\n`
	.. `-- ARQUIVO GERADO por tools/generate-enums.luau — NÃO EDITAR À MÃO.\n`
	.. `-- Roblox API Dump: MaximumADHD/Roblox-Client-Tracker @ {dumpLock.commit}\n`
	.. `-- Versão Roblox: {dumpLock.robloxVersion} | esquema do dump: Version {dumpLock.dumpSchemaVersion}\n`
	.. `-- Regenerar: lune run tools/generate-enums\n`

-- ============================================================================================
-- src/valuetypes/generated/EnumData.luau -- dados puros, na ORDEM ORIGINAL do dump (determinístico
-- entre execuções: mesmos bytes verificados por sha256 sempre produzem o mesmo array na mesma
-- ordem -- nenhuma iteração de tabela hash própria deste script entra em texto emitido).
-- ============================================================================================

local function generateEnumData(): string
	local lines: { string } = {}
	table.insert(lines, FILE_HEADER)
	table.insert(
		lines,
		"\n-- Dados PUROS (por enum: nome + duas listas PARALELAS ItemNames/ItemValues, mesmo índice\n"
			.. "-- == mesmo item) -- nenhuma lógica de Enums/Enum/EnumItem (typeof, GetEnumItems/FromName/\n"
			.. "-- FromValue, memoização, internamento) vive aqui; isso é responsabilidade de\n"
			.. "-- src/valuetypes/types/Enum.luau, que faz require deste módulo e monta o EnumItem real\n"
			.. "-- (zipando ItemNames[i]/ItemValues[i]) só na primeira vez que aquele ENUM é tocado.\n"
			.. "-- Ordem preservada exatamente como no Full-API-Dump.json (enums na ordem original do\n"
			.. "-- array \"Enums\"; itens de cada enum na ordem original do array \"Items\" daquele enum).\n"
			.. "--\n"
			.. "-- Listas PARALELAS em vez de `Items: { { Name, Value } }` por tamanho de arquivo/custo de\n"
			.. "-- parse: cada item numa lista de records repetiria os literais \"Name = \"/\"Value = \" 3611\n"
			.. "-- vezes (medido nesta tarefa: ~165 KB, quase 3x o ~64 KB estimado pelo arquiteto na\n"
			.. "-- seção 0.6 do desenho) -- duas listas paralelas custam só DOIS rótulos por enum (629x,\n"
			.. "-- não 3611x) e ainda são um array denso (sem hash part) em vez de 3611 tabelas hash\n"
			.. "-- pequenas. Mesmo assim, o design ESCOLHIDO (este arquivo) ficou em ~103 KB reais, bem\n"
			.. "-- acima da estimativa de ~64 KB do arquiteto -- redução real foi de ~165 KB para ~103 KB\n"
			.. "-- (~38%), não até os ~64 KB estimados originalmente.\n\n"
	)

	table.insert(lines, "export type EnumDefinition = {\n\tName: string,\n\tItemNames: { string },\n\tItemValues: { number },\n}\n\n")

	table.insert(lines, "local EnumData: { EnumDefinition } = {\n")
	for _, enum in dump.Enums do
		local nameLiterals: { string } = {}
		local valueLiterals: { string } = {}
		for _, item in enum.Items do
			table.insert(nameLiterals, luaStringLiteral(item.Name))
			table.insert(valueLiterals, tostring(item.Value))
		end
		table.insert(
			lines,
			`\t\{ Name = {luaStringLiteral(enum.Name)}, ItemNames = \{ {table.concat(nameLiterals, ", ")} \}, ItemValues = \{ {table.concat(
				valueLiterals,
				", "
			)} \} \},\n`
		)
	end
	table.insert(lines, "}\n\n")
	table.insert(lines, "return EnumData\n")

	return table.concat(lines)
end

-- ============================================================================================
-- Executa a geração
-- ============================================================================================

local GENERATED_DIR = "src/valuetypes/generated"

if not fs.isDir(GENERATED_DIR) then
	fs.writeDir(GENERATED_DIR)
end

fs.writeFile(`{GENERATED_DIR}/EnumData.luau`, generateEnumData())

-- ============================================================================================
-- Relatório final
-- ============================================================================================

local enumCount = #dump.Enums
local itemCount = 0
for _, enum in dump.Enums do
	itemCount += #enum.Items
end

print("\n[generate-enums] geração concluída.")
print(`  Enums emitidos: {enumCount}`)
print(`  EnumItems emitidos (soma de todos os enums): {itemCount}`)
print(`  Arquivo: {GENERATED_DIR}/EnumData.luau`)
print("\n[generate-enums] OK.")
process.exit(0)
