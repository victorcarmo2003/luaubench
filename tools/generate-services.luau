--!strict

--[[
	Gerador dev-time de `services` (task-services-002). Transforma o Roblox API Dump oficial em
	`.luau` COMMITADO sob `src/services/generated/` -- `luaubench run` nunca vê o dump, nunca chama
	`serde`, nunca faz I/O de dados de API (regra 01: gerador não deve reparsear o dump a cada run).

	Invocação: `lune run tools/generate-services` -- script DEV-TIME, manual, NUNCA requerido por
	`src/` nem rodado em `luaubench run`/CI de release (regra 03).

	Território exclusivo desta tarefa: tools/generate-services.luau, tools/api-dump.lock.json,
	tools/coverage.luau, tools/capabilities.lock.json, src/services/generated/** -- nada além disso
	é tocado (nenhum arquivo em src/services/behavior/** ou src/services/init.luau é escrito aqui).

	Desenho completo: .claude/agents-memory/arquiteto-services-2026-09-05.md, seções "Decisão 1"
	(pipeline), "Decisão 2" (versão do dump), "Decisão 3" (formato do descritor de membro),
	"Módulos" e "Revisão pós-pesquisa 2026-09-05 -- Capabilities e RenderStepped", seção "A"
	(regra de emissão de 4 eixos: Security/Tags/ReadOnly/Capabilities).

	Pipeline, na ordem (espelha a seção "Módulos" do desenho):
	 1. lê tools/api-dump.lock.json
	 2. lê tools/capabilities.lock.json (grantable/reserved -- NUNCA baixa a doc de novo)
	 3. baixa (net.request) para .cache/api-dump/<commit>.json se ausente; valida sizeBytes+sha256,
	    ABORTA se divergir
	 4. serde.decode("json", ...) -> { Classes, Enums, Version }; valida Version == 1, ABORTA se
	    o esquema mudou
	 5. calcula o fecho de superclasses de tools/coverage.luau (para em "Instance"; ignora "Object")
	 6. varredura de PRÉ-VALIDAÇÃO: toda capability exigida por qualquer membro do fecho precisa
	    estar em grantable ∪ reserved -- ABORTA nomeando a capability e os membros afetados ANTES de
	    escrever qualquer arquivo (mesmo protocolo do abort de Version ~= 1)
	 7. emite src/services/generated/Manifest.luau (as 916 classes do dump)
	 8. emite src/services/generated/classes/<X>.luau para cada classe do fecho
	 9. emite src/services/generated/Index.luau (requires LITERAIS -- o `require` do Lune resolve
	    estaticamente, não há require dinâmico por string)
	10. imprime RELATÓRIO: deprecated emitidas, defaults não representáveis por classe, membros de
	    Object/Instance não cobertos por runtime/Instance.luau, classes sem schema/métodos

	IDEMPOTÊNCIA: `src/services/generated/` é APAGADO e RECRIADO do zero a cada execução (Decisão 1:
	"Saída ... 100% sobrescrito a cada execução") -- nunca uma mescla incremental. Toda iteração de
	tabela hash própria deste script (ex.: `closureSet`, capabilities desconhecidas) é ORDENADA
	antes de virar texto; iteração sobre `Members`/`Classes` do dump usa a ORDEM ORIGINAL do array
	(estável entre execuções, pois vem do mesmo arquivo de bytes verificado por sha256) -- nenhuma
	fonte de não-determinismo (timestamp, hash de endereço de memória, `pairs` sobre tabela própria
	sem ordenar) entra em texto emitido.
]]

local fs = require("@lune/fs")
local net = require("@lune/net")
local serde = require("@lune/serde")
local process = require("@lune/process")

local Coverage: { string } = require("./coverage")

-- ============================================================================================
-- 0. Tipos locais para o dump decodificado -- `serde.decode` devolve `any` no typedef do Lune;
--    a variável que recebe o retorno é tipada `unknown` (regra 01, "sem any") e estreitada por UM
--    cast explícito para os tipos abaixo, que são o reflexo empírico do dump (confirmado por
--    inspeção direta nesta sessão, nunca por suposição -- regra 00). `Security`/`Capabilities` são
--    polimórficos conforme `MemberType` (Decisão A.1 da revisão pós-pesquisa) -- ficam `unknown` e
--    são estreitados por função dedicada, não por um tipo de união só.
-- ============================================================================================

type RawParameter = {
	Name: string,
	Type: { Category: string, Name: string }?,
	Default: string?,
}

type RawMember = {
	Name: string,
	MemberType: string, -- "Property" | "Function" | "Event" | "Callback"
	Security: unknown, -- string (Function/Event/Callback) OU {Read:string, Write:string} (Property)
	Tags: { unknown }?, -- pode conter tags-OBJETO (não-string), ex.: {"PreferredDescriptorName":...}
	Capabilities: unknown?, -- {string} (Function/Event/Callback) OU {Read:{string}?,Write:{string}?} (Property)
	ValueType: { Category: string, Name: string }?, -- só Property
	Default: unknown?, -- só Property; sempre string no dump bruto (sentinela ou valor serializado)
	Parameters: { RawParameter }?, -- só Function/Event/Callback
	ReturnType: { Category: string, Name: string }?, -- só Function
}

type RawClass = {
	Name: string,
	Superclass: string,
	Tags: { unknown }?,
	Members: { RawMember },
}

type RawDump = {
	Classes: { RawClass },
	Enums: unknown,
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

type CapabilitiesLock = {
	grantable: { string },
	reserved: { string },
}

-- ============================================================================================
-- Helpers genéricos
-- ============================================================================================

-- ACHADO DE TOOLING (luau-lsp 1.69.0, confirmado empiricamente rodando `luau-lsp analyze` nesta
-- sessão -- regra 00, não adivinhado): apesar de `process.exit` estar tipado `-> never` no typedef
-- do Lune, o checker desta versão NÃO propaga isso para considerar esta função (cujo último
-- statement é exatamente essa chamada) como "todo codepath retorna never" -- reporta
-- "Not all codepaths in this function return 'never'" mesmo assim. Por isso `abort` NÃO é anotada
-- como `-> never`: toda função que precisa de exaustividade depois de chamar `abort` (ex.:
-- `computeDefault`/`luaValueLiteral`, abaixo) tem um `return` explícito logo depois, nunca depende
-- de inferência de fluxo através deste helper. Em tempo de EXECUÇÃO isso não muda nada:
-- `process.exit` encerra o processo Lune de verdade, então nenhum código depois dele roda.
local function abort(message: string): ()
	print(`[generate-services] ERRO: {message}`)
	process.exit(1)
end

-- `Tags` (de classe ou de membro) pode conter entradas OBJETO (não-string) -- confirmado por
-- inspeção direta (18 ocorrências de tag-objeto em Tags de classe; o mesmo padrão aparece em Tags
-- de membro, ex.: {"PreferredDescriptorName":"IsA","ThreadSafety":"Safe"}). Filtra antes de
-- comparar, nunca assume que todo elemento é string.
local function hasStringTag(tags: { unknown }?, tag: string): boolean
	if tags == nil then
		return false
	end
	for _, t in tags do
		if type(t) == "string" and (t :: string) == tag then
			return true
		end
	end
	return false
end

local function sortedKeys(set: { [string]: boolean }): { string }
	local out: { string } = {}
	for key in set do
		table.insert(out, key)
	end
	table.sort(out)
	return out
end

-- ============================================================================================
-- 1 + 2. Lock files
-- ============================================================================================

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

local capabilitiesLockRaw = readJsonFile("tools/capabilities.lock.json")
local capabilitiesLock = capabilitiesLockRaw :: CapabilitiesLock

local grantableSet: { [string]: boolean } = {}
for _, name in capabilitiesLock.grantable do
	grantableSet[name] = true
end

local reservedSet: { [string]: boolean } = {}
for _, name in capabilitiesLock.reserved do
	reservedSet[name] = true
end

-- ============================================================================================
-- 3. Baixa/valida o dump (.cache/api-dump/<commit>.json -- .cache/ já está no .gitignore)
-- ============================================================================================

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

	print(`[generate-services] baixando dump de {dumpLock.url} ...`)
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

-- ============================================================================================
-- 4. Decodifica + valida Version
-- ============================================================================================

local decodedDump: unknown = serde.decode("json", dumpBytes)
local dump = decodedDump :: RawDump

if dump.Version ~= 1 then
	abort(
		`esquema do dump (campo "Version") é {tostring(dump.Version)}, esperado 1 -- o formato do `
			.. `Full-API-Dump.json mudou; este gerador precisa ser revisado antes de continuar (nunca gerar contra um esquema desconhecido)`
	)
end

local classByName: { [string]: RawClass } = {}
for _, class in dump.Classes do
	classByName[class.Name] = class
end

-- ============================================================================================
-- 5. Fecho transitivo de superclasses a partir de tools/coverage.luau
-- ============================================================================================

local closureSet: { [string]: boolean } = {}
do
	local queue: { string } = table.clone(Coverage)
	local queueIndex = 1
	while queueIndex <= #queue do
		local className = queue[queueIndex]
		queueIndex += 1
		if not closureSet[className] then
			local class = classByName[className]
			if class == nil then
				abort(
					`classe '{className}' (de tools/coverage.luau ou puxada por herança) não existe no `
						.. `Roblox API Dump {dumpLock.robloxVersion} -- typo em coverage.luau?`
				)
			end
			closureSet[className] = true
			local rawSuper = class.Superclass
			-- "Object" é a raiz real do dump (Superclass == "<<<ROOT>>>"); só "Instance" tem
			-- Superclass == "Object" no dump inteiro. O gerador PARA aqui: "Instance" é a raiz
			-- simulada do LuauBench, "Object" nunca vira uma classe própria (Decisão 1).
			if rawSuper ~= "<<<ROOT>>>" and rawSuper ~= "Object" then
				if not closureSet[rawSuper] then
					table.insert(queue, rawSuper)
				end
			end
		end
	end
end

local closureNames: { string } = sortedKeys(closureSet)

-- ============================================================================================
-- Classificação de membro -- a tabela de emissão de 4 eixos (Security/Tags/ReadOnly/Capabilities),
-- seção A.4 da revisão pós-pesquisa 2026-09-05, avaliada EM ORDEM, primeiro casamento vence.
-- ============================================================================================

-- Devolve os conjuntos de nomes de capability EXIGIDOS para leitura e para escrita. Para
-- Property, vêm de `Capabilities.Read`/`Capabilities.Write` (podem faltar independentemente). Para
-- Function/Event/Callback, `Capabilities` é um array plano e o MESMO conjunto vale para os dois
-- lados (não há Read/Write separado para eles) -- fato A.1 da revisão pós-pesquisa.
local function requiredCapabilitySets(member: RawMember): ({ [string]: boolean }, { [string]: boolean })
	local requiredRead: { [string]: boolean } = {}
	local requiredWrite: { [string]: boolean } = {}
	local caps = member.Capabilities
	if caps == nil then
		return requiredRead, requiredWrite
	end
	if member.MemberType == "Property" then
		local capsTable = caps :: { Read: { string }?, Write: { string }? }
		if capsTable.Read ~= nil then
			for _, name in capsTable.Read do
				requiredRead[name] = true
			end
		end
		if capsTable.Write ~= nil then
			for _, name in capsTable.Write do
				requiredWrite[name] = true
			end
		end
	else
		local capsList = caps :: { string }
		for _, name in capsList do
			requiredRead[name] = true
			requiredWrite[name] = true
		end
	end
	return requiredRead, requiredWrite
end

local function allRequiredCapabilityNames(member: RawMember): { string }
	local read, write = requiredCapabilitySets(member)
	local set: { [string]: boolean } = {}
	for name in read do
		set[name] = true
	end
	for name in write do
		set[name] = true
	end
	return sortedKeys(set)
end

-- ============================================================================================
-- 6. Pré-validação: nenhuma capability exigida pode estar fora de grantable ∪ reserved. ABORTA
--    nomeando a capability e TODOS os membros afetados, ANTES de escrever qualquer arquivo --
--    mesmo protocolo do abort de Version ~= 1 (nunca excluir/incluir um nome desconhecido
--    silenciosamente).
-- ============================================================================================

do
	local unknownCapabilityToMembers: { [string]: { string } } = {}

	local function scanMember(className: string, member: RawMember): ()
		for _, capName in allRequiredCapabilityNames(member) do
			if not grantableSet[capName] and not reservedSet[capName] then
				local list = unknownCapabilityToMembers[capName]
				if list == nil then
					list = {}
					unknownCapabilityToMembers[capName] = list
				end
				table.insert(list, `{className}.{member.Name}`)
			end
		end
	end

	for _, className in closureNames do
		local class = classByName[className]
		for _, member in class.Members do
			scanMember(className, member)
		end
		if className == "Instance" then
			local objectClass = classByName["Object"]
			if objectClass ~= nil then
				for _, member in objectClass.Members do
					scanMember("Object", member)
				end
			end
		end
	end

	local unknownNames = sortedKeys((function(): { [string]: boolean }
		local set: { [string]: boolean } = {}
		for name in unknownCapabilityToMembers do
			set[name] = true
		end
		return set
	end)())

	if #unknownNames > 0 then
		print("[generate-services] ERRO: capability(ies) fora de grantable+reserved (tools/capabilities.lock.json):")
		for _, name in unknownNames do
			local members = unknownCapabilityToMembers[name]
			table.sort(members)
			print(`  '{name}' usada por: {table.concat(members, ", ")}`)
		end
		abort(
			"classifique a(s) capability(ies) acima em tools/capabilities.lock.json (grantable ou reserved) "
				.. "antes de gerar -- o gerador nunca assume um lado por omissão"
		)
	end
end

-- ============================================================================================
-- Classificação de membro Schema (Property/Event/Callback) -- tabela A.4, passos 1-8 (o passo 1,
-- abort por capability desconhecida, já foi tratado acima para o fecho inteiro).
-- ============================================================================================

type SchemaClassification = {
	included: boolean,
	readOnly: boolean,
	excludedByCapability: boolean,
}

local function classifySchemaMember(member: RawMember): SchemaClassification
	local hasNotScriptable = hasStringTag(member.Tags, "NotScriptable")
	local hasWriteOnly = hasStringTag(member.Tags, "WriteOnly")

	local securityReadElevated: boolean
	if member.MemberType == "Property" then
		local sec = member.Security :: { Read: string, Write: string }
		securityReadElevated = sec.Read ~= "None"
	else
		local sec = member.Security :: string
		securityReadElevated = sec ~= "None"
	end

	-- passo 2
	if hasNotScriptable or securityReadElevated or hasWriteOnly then
		return { included = false, readOnly = false, excludedByCapability = false }
	end

	local requiredRead, requiredWrite = requiredCapabilitySets(member)

	-- passo 3: required_read ∩ reserved ~= {} -> excluído
	for name in requiredRead do
		if reservedSet[name] then
			return { included = false, readOnly = false, excludedByCapability = true }
		end
	end

	-- passo 4: required_write ∩ reserved ~= {} (com read livre) -> incluído, ReadOnly = true
	-- (zero casos neste dump -- especificado por robustez, ver seção A.4 da revisão)
	for name in requiredWrite do
		if reservedSet[name] then
			return { included = true, readOnly = true, excludedByCapability = false }
		end
	end

	-- passo 5
	local hasReadOnlyTag = hasStringTag(member.Tags, "ReadOnly")
	local securityWriteElevated = false
	if member.MemberType == "Property" then
		local sec = member.Security :: { Read: string, Write: string }
		securityWriteElevated = sec.Write ~= "None"
	end
	if hasReadOnlyTag or securityWriteElevated then
		return { included = true, readOnly = true, excludedByCapability = false }
	end

	-- passo 6
	if member.MemberType == "Event" then
		return { included = true, readOnly = true, excludedByCapability = false }
	end

	-- passo 7
	if member.MemberType == "Callback" then
		return { included = true, readOnly = false, excludedByCapability = false }
	end

	-- passo 8
	return { included = true, readOnly = false, excludedByCapability = false }
end

-- Classificação de MethodNames (Function) -- MESMOS passos 1-3 da tabela A.4 (a correção "C" da
-- revisão pós-pesquisa: o filtro de Security/Capabilities também vale para métodos, buraco da
-- regra antiga). Passos 4-8 não se aplicam (método não tem escrituralidade).
type MethodClassification = {
	included: boolean,
	excludedByCapability: boolean,
}

local function classifyMethodMember(member: RawMember): MethodClassification
	local hasNotScriptable = hasStringTag(member.Tags, "NotScriptable")
	local hasWriteOnly = hasStringTag(member.Tags, "WriteOnly")
	local sec = member.Security :: string

	if hasNotScriptable or sec ~= "None" or hasWriteOnly then
		return { included = false, excludedByCapability = false }
	end

	local requiredRead = requiredCapabilitySets(member)
	for name in requiredRead do
		if reservedSet[name] then
			return { included = false, excludedByCapability = true }
		end
	end

	return { included = true, excludedByCapability = false }
end

-- ============================================================================================
-- Default: parseado por ValueType.Category (nunca a string bruta do dump). Sentinela
-- "__api_dump_*" (qualquer variante -- 5 formas distintas confirmadas por inspeção: nao aparece
-- sempre a mesma) vira nil independente da categoria; Enum/DataType/Class viram nil NESTA FASE
-- mesmo quando o dump traz um valor real (ex.: "Unknown" para um Enum) -- emitir a string mentiria
-- (part.Shape == Enum.PartType.Block falharia sem Enum simulado).
-- ============================================================================================

local function isSentinelDefault(raw: unknown): boolean
	return type(raw) == "string" and string.match(raw :: string, "^__api_dump") ~= nil
end

-- devolve (valor, representável)
local function computeDefault(member: RawMember): (unknown, boolean)
	if member.MemberType ~= "Property" then
		return nil, true -- Event/Callback não têm Default; "representável" não se aplica aqui
	end

	local raw = member.Default
	if raw == nil or isSentinelDefault(raw) then
		return nil, false
	end

	local vt = member.ValueType
	if vt == nil or vt.Category ~= "Primitive" then
		return nil, false -- Enum/DataType/Class -- nesta fase
	end

	local rawStr = raw :: string
	if vt.Name == "bool" then
		if rawStr == "true" then
			return true, true
		elseif rawStr == "false" then
			return false, true
		end
		abort(`Default booleano inesperado em {member.Name}: "{rawStr}"`)
		return nil, false
	elseif vt.Name == "string" then
		return rawStr, true
	elseif vt.Name == "int" or vt.Name == "int64" or vt.Name == "float" or vt.Name == "double" then
		local n = tonumber(rawStr)
		if n == nil then
			abort(`Default numérico ilegível em {member.Name}: "{rawStr}"`)
		end
		return n, true
	end

	return nil, false
end

-- ============================================================================================
-- Emissão de literais Luau -- string.format("%q", ...) escapa QUALQUER conteúdo com segurança
-- (aspas embutidas, espaço -- confirmado no dump real: PVInstance."Pivot Offset" -- etc.), por
-- isso todo nome de membro vira chave em colchetes (`["Nome"] = ...`) em vez de `.Nome`, nunca
-- assumindo que é um identificador Luau válido.
-- ============================================================================================

local function luaStringLiteral(value: string): string
	return string.format("%q", value)
end

local function luaValueLiteral(value: unknown): string
	if value == nil then
		return "nil"
	elseif type(value) == "boolean" then
		return tostring(value)
	elseif type(value) == "number" then
		return tostring(value)
	elseif type(value) == "string" then
		return luaStringLiteral(value :: string)
	end
	abort(`valor de Default com tipo Luau inesperado: {type(value)}`)
	return "nil"
end

-- Mapeia um ValueType do dump pro tipo Luau mais fiel possível: Primitive vira o tipo real
-- (boolean/string/number); qualquer outra categoria (Enum/DataType/Class/Group/desconhecida) vira
-- `unknown` -- NUNCA `any` (regra 01), e nunca uma aproximação solta tipo string genérica para um
-- Enum/DataType real (regra 03: sem Enum/DataType simulados nesta fase, mentir o tipo seria pior
-- que admitir `unknown`).
local function luauTypeForValueType(vt: { Category: string, Name: string }?): string
	if vt == nil then
		return "unknown"
	end
	if vt.Category == "Primitive" then
		if vt.Name == "bool" then
			return "boolean"
		elseif vt.Name == "string" then
			return "string"
		elseif vt.Name == "int" or vt.Name == "int64" or vt.Name == "float" or vt.Name == "double" then
			return "number"
		end
	end
	return "unknown"
end

-- Tipo de RETORNO de método: Primitive/"null" (convenção do dump pra "sem retorno") vira `()`;
-- Group/Tuple|Array|Dictionary não tem representação de tupla exata no dump (sem enumeração de
-- elementos) -- aproximação declarada, documentada no cabeçalho de cada arquivo gerado.
local function luauReturnType(vt: { Category: string, Name: string }?): string
	if vt == nil then
		return "()"
	end
	if vt.Category == "Primitive" and vt.Name == "null" then
		return "()"
	end
	if vt.Category == "Group" then
		if vt.Name == "Tuple" then
			return "...unknown"
		elseif vt.Name == "Array" then
			return "{ unknown }"
		else
			return "{ [string]: unknown }"
		end
	end
	return luauTypeForValueType(vt)
end

-- Palavras reservadas do Luau -- um nome de parâmetro do dump que colidir (ex.: `function` em
-- RunService:BindToRenderStep/BindToSimulation, confirmado por inspeção real) quebraria a
-- assinatura gerada (`function: unknown` não compila). Achado ao rodar o gerador pela primeira vez
-- nesta sessão, não hipotético.
local LUAU_KEYWORDS: { [string]: boolean } = {
	["and"] = true,
	["break"] = true,
	["do"] = true,
	["else"] = true,
	["elseif"] = true,
	["end"] = true,
	["false"] = true,
	["for"] = true,
	["function"] = true,
	["if"] = true,
	["in"] = true,
	["local"] = true,
	["nil"] = true,
	["not"] = true,
	["or"] = true,
	["repeat"] = true,
	["return"] = true,
	["then"] = true,
	["true"] = true,
	["until"] = true,
	["while"] = true,
	["continue"] = true,
	["self"] = true, -- já usado pelo parâmetro `self:` sintético; evita colisão de nome
}

local function sanitizeParamIdentifier(name: string): string
	local sanitized = string.gsub(name, "[^%w_]", "_")
	if string.match(sanitized, "^%d") ~= nil or sanitized == "" then
		sanitized = "_" .. sanitized
	end
	if LUAU_KEYWORDS[sanitized] then
		sanitized = sanitized .. "_"
	end
	return sanitized
end

local function buildMethodSignature(className: string, member: RawMember): string
	local params: { string } = { `self: {className}` }
	if member.Parameters ~= nil then
		for _, p in member.Parameters do
			local paramType = luauTypeForValueType(p.Type)
			local optional = if p.Default ~= nil then "?" else ""
			table.insert(params, `{sanitizeParamIdentifier(p.Name)}: {paramType}{optional}`)
		end
	end
	local returnType = luauReturnType(member.ReturnType)
	return `({table.concat(params, ", ")}) -> {returnType}`
end

local function buildEventSignalType(member: RawMember): string
	local paramTypes: { string } = {}
	if member.Parameters ~= nil then
		for _, p in member.Parameters do
			table.insert(paramTypes, luauTypeForValueType(p.Type))
		end
	end
	return `Runtime.Signal<{table.concat(paramTypes, ", ")}>`
end

-- ============================================================================================
-- Membros que `src/runtime/Instance.luau` JÁ implementa nativamente (campos fixos, sinais fixos e
-- métodos base -- ver o tipo público `Instance` nesse arquivo). Usado para (a) não redeclarar um
-- campo/método no TIPO Luau exportado de cada classe (evita conflito/redundância com
-- `Runtime.Instance &`, que já traz esses campos com o tipo real) e (b) computar o relatório
-- "membros de Object/Instance não cobertos por runtime/Instance.luau" (Decisão 1). PRECISA ficar em
-- sincronia manual com a superfície pública de src/runtime/Instance.luau -- se esse arquivo ganhar
-- um membro novo, esta lista precisa ser atualizada (risco aceito, documentado no relatório final).
-- ============================================================================================

local NATIVE_COVERED_BY_RUNTIME_INSTANCE: { [string]: boolean } = {
	-- campos fixos
	ClassName = true,
	Name = true,
	Parent = true,
	-- sinais fixos
	Changed = true,
	ChildAdded = true,
	ChildRemoved = true,
	AncestryChanged = true,
	Destroying = true,
	-- métodos base
	GetChildren = true,
	GetDescendants = true,
	FindFirstChild = true,
	FindFirstChildOfClass = true,
	FindFirstChildWhichIsA = true,
	FindFirstAncestor = true,
	WaitForChild = true,
	IsA = true,
	IsDescendantOf = true,
	IsAncestorOf = true,
	ClearAllChildren = true,
	Destroy = true,
	GetFullName = true,
}

-- ============================================================================================
-- Relatório (acumulado durante a geração, impresso no fim -- Decisão 1, passo 9 do pipeline)
-- ============================================================================================

local report = {
	deprecatedEmitted = {} :: { string },
	nonRepresentableDefaultsByClass = {} :: { [string]: number },
	notCoveredByRuntimeInstance = {} :: { string },
	danglingObjectFunctions = {} :: { string },
	emptyClasses = {} :: { string },
	totalMethodsKept = 0,
	totalMethodsExcludedSecurity = 0,
	totalMethodsExcludedCapability = 0,
	schemaExcludedByCapability = {} :: { string },
}

local function classTagFlag(class: RawClass, tag: string): boolean
	return hasStringTag(class.Tags, tag)
end

-- ============================================================================================
-- 7 + 8. Emissão dos arquivos gerados
-- ============================================================================================

local GENERATED_DIR = "src/services/generated"
local CLASSES_DIR = `{GENERATED_DIR}/classes`

local function resetGeneratedDir(): ()
	if fs.isDir(GENERATED_DIR) then
		fs.removeDir(GENERATED_DIR)
	end
	fs.writeDir(GENERATED_DIR)
	fs.writeDir(CLASSES_DIR)
end

local FILE_HEADER = `--!strict\n`
	.. `-- ARQUIVO GERADO por tools/generate-services.luau — NÃO EDITAR À MÃO.\n`
	.. `-- Roblox API Dump: {"MaximumADHD/Roblox-Client-Tracker"} @ {dumpLock.commit}\n`
	.. `-- Versão Roblox: {dumpLock.robloxVersion} | esquema do dump: Version {dumpLock.dumpSchemaVersion}\n`
	.. `-- Regenerar: lune run tools/generate-services\n`

-- ---- 7. Manifest.luau (as 916 classes) ----

local function generateManifest(): string
	local allNames: { string } = {}
	for _, class in dump.Classes do
		table.insert(allNames, class.Name)
	end
	table.sort(allNames)

	local lines: { string } = {}
	table.insert(lines, FILE_HEADER)
	table.insert(
		lines,
		"\n-- Reflexo LEVE das 916 classes do dump inteiro -- não confundir com src/services/generated/Index.luau\n"
			.. "-- (só as classes REALMENTE simuladas, com Schema/MethodNames completos). Serve a um propósito único\n"
			.. "-- (regra 03: 'Service não coberto ainda não é stub silencioso'): distinguir, em Services.new,\n"
			.. "-- 'não existe no Roblox' de 'existe no dump e ainda não simulado pelo LuauBench'.\n\n"
	)
	table.insert(lines, "export type ManifestEntry = {\n")
	table.insert(lines, "\tSuperclass: string,\n")
	table.insert(lines, "\tIsService: boolean,\n")
	table.insert(lines, "\tIsAbstract: boolean,\n")
	table.insert(lines, "\tCovered: boolean,\n")
	table.insert(lines, "}\n\n")

	table.insert(lines, "export type Manifest = {\n")
	table.insert(lines, "\tDumpCommit: string,\n")
	table.insert(lines, "\tDumpVersion: string,\n")
	table.insert(lines, "\tClasses: { [string]: ManifestEntry },\n")
	table.insert(lines, "}\n\n")

	table.insert(lines, `local Manifest: Manifest = \{\n`)
	table.insert(lines, `\tDumpCommit = {luaStringLiteral(dumpLock.commit)},\n`)
	table.insert(lines, `\tDumpVersion = {luaStringLiteral(dumpLock.robloxVersion)},\n`)
	table.insert(lines, "\tClasses = {\n")

	for _, name in allNames do
		local class = classByName[name]
		local isService = classTagFlag(class, "Service")
		local isAbstract = classTagFlag(class, "NotCreatable")
		local covered = closureSet[name] == true
		table.insert(
			lines,
			`\t\t[{luaStringLiteral(name)}] = \{ Superclass = {luaStringLiteral(class.Superclass)}, IsService = {tostring(
				isService
			)}, IsAbstract = {tostring(isAbstract)}, Covered = {tostring(covered)} \},\n`
		)
	end

	table.insert(lines, "\t},\n")
	table.insert(lines, "}\n\n")
	table.insert(lines, "table.freeze(Manifest.Classes)\n\n")
	table.insert(lines, "return Manifest\n")

	return table.concat(lines)
end

-- ---- 8. classes/<ClassName>.luau ----

-- Membros (Property/Event/Callback) que entram no SCHEMA de `className`, na ordem original do
-- dump (estável -- mesma entrada de array a cada decodificação dos mesmos bytes). Para "Instance"
-- especificamente, DOBRA os membros de Object (Property/Event/Callback, NUNCA Function -- ver
-- Decisão 1 e a nota "danglingObjectFunctions" abaixo) -- são responsabilidade de
-- `runtime/Instance.luau`, mas o schema achatado do ClassRegistry precisa deles para o modo
-- estrito não errar em `Archivable`/`Capabilities`/etc.
local function schemaMembersOf(className: string, class: RawClass): { RawMember }
	local members: { RawMember } = {}
	for _, m in class.Members do
		if m.MemberType == "Property" or m.MemberType == "Event" or m.MemberType == "Callback" then
			table.insert(members, m)
		end
	end
	if className == "Instance" then
		local objectClass = classByName["Object"]
		if objectClass ~= nil then
			for _, m in objectClass.Members do
				if m.MemberType == "Property" or m.MemberType == "Event" or m.MemberType == "Callback" then
					table.insert(members, m)
				end
			end
		end
	end
	return members
end

-- Membros Function que entram em MethodNames de `className` -- APENAS os que a própria classe
-- declara. Object.GetPropertyChangedSignal/IsA/isA NÃO são dobrados aqui (diferente do schema,
-- acima): IsA já é nativo (Runtime.Instance base, precedência sobre classMethods -- dobrar seria
-- morto); GetPropertyChangedSignal/isA ficam de fora e aparecem no relatório como gap conhecido,
-- nunca implementados silenciosamente nem inventados.
local function methodMembersOf(class: RawClass): { RawMember }
	local members: { RawMember } = {}
	for _, m in class.Members do
		if m.MemberType == "Function" then
			table.insert(members, m)
		end
	end
	return members
end

local function generateClassFile(className: string): string
	local class = classByName[className]
	local isService = classTagFlag(class, "Service")
	local isAbstract = classTagFlag(class, "NotCreatable")
	-- Decisão 1: "Superclass == 'Object' -> o gerador PARA em Instance" -- normalizado aqui. Só a
	-- própria classe "Instance" tem Superclass bruto == "Object" no dump inteiro; a auto-referência
	-- resultante ("Instance" normalizado para "Instance") é tratada de propósito por
	-- src/services/ClassBuilder.luau (SuperClassName = nil quando Superclass == "Instance").
	local normalizedSuperclass = if class.Superclass == "Object" then "Instance" else class.Superclass

	local schemaMembers = schemaMembersOf(className, class)
	local methodMembers = methodMembersOf(class)

	-- Linhas do valor Schema (tabela Lua real) e do TIPO público exportado, em paralelo.
	local schemaValueLines: { string } = {}
	local typeFieldLines: { string } = {}
	local emittedSchemaCount = 0

	for _, member in schemaMembers do
		local classification = classifySchemaMember(member)
		if classification.excludedByCapability then
			table.insert(report.schemaExcludedByCapability, `{className}.{member.Name} ({member.MemberType})`)
		end
		if classification.included then
			emittedSchemaCount += 1
			local kind = member.MemberType -- "Property" | "Event" | "Callback"

			local defaultValue, representable = computeDefault(member)
			if member.MemberType == "Property" and not representable then
				report.nonRepresentableDefaultsByClass[className] = (report.nonRepresentableDefaultsByClass[className] or 0)
					+ 1
			end

			if hasStringTag(member.Tags, "Deprecated") then
				table.insert(report.deprecatedEmitted, `{className}.{member.Name} ({member.MemberType})`)
			end

			table.insert(
				schemaValueLines,
				`\t\t[{luaStringLiteral(member.Name)}] = \{ Kind = {luaStringLiteral(kind)}, Default = {luaValueLiteral(
					defaultValue
				)}, ReadOnly = {tostring(classification.readOnly)} \},\n`
			)

			-- Só entra no TIPO público se `runtime/Instance.luau` ainda não cobre nativamente
			-- (evita redeclarar um campo que `Runtime.Instance &` já traz com o tipo real).
			if not NATIVE_COVERED_BY_RUNTIME_INSTANCE[member.Name] then
				if member.MemberType == "Property" then
					local fieldType = if representable then luauTypeForValueType(member.ValueType) else "unknown"
					table.insert(typeFieldLines, `\t[{luaStringLiteral(member.Name)}]: {fieldType},\n`)
				elseif member.MemberType == "Event" then
					table.insert(typeFieldLines, `\t[{luaStringLiteral(member.Name)}]: {buildEventSignalType(member)},\n`)
				else -- Callback
					table.insert(typeFieldLines, `\t[{luaStringLiteral(member.Name)}]: unknown,\n`)
				end
			end

			-- membros de Object/Instance não cobertos nativamente -- só interessa reportar para a
			-- classe "Instance" (Decisão 1: é o único lugar onde o fold de Object acontece).
			if className == "Instance" and not NATIVE_COVERED_BY_RUNTIME_INSTANCE[member.Name] then
				table.insert(report.notCoveredByRuntimeInstance, `{member.Name} ({member.MemberType})`)
			end
		end
	end

	local methodNameLines: { string } = {}
	for _, member in methodMembers do
		local classification = classifyMethodMember(member)
		if classification.included then
			report.totalMethodsKept += 1
			table.insert(methodNameLines, `\t\t{luaStringLiteral(member.Name)},\n`)

			if hasStringTag(member.Tags, "Deprecated") then
				table.insert(report.deprecatedEmitted, `{className}.{member.Name} (Function)`)
			end

			if not NATIVE_COVERED_BY_RUNTIME_INSTANCE[member.Name] then
				table.insert(
					typeFieldLines,
					`\t[{luaStringLiteral(member.Name)}]: {buildMethodSignature(className, member)},\n`
				)
			end
		elseif classification.excludedByCapability then
			report.totalMethodsExcludedCapability += 1
		else
			report.totalMethodsExcludedSecurity += 1
		end
	end

	-- Object.GetPropertyChangedSignal/isA: gap conhecido e declarado (ver methodMembersOf acima).
	if className == "Instance" then
		local objectClass = classByName["Object"]
		if objectClass ~= nil then
			for _, m in objectClass.Members do
				if m.MemberType == "Function" then
					table.insert(report.danglingObjectFunctions, `Object.{m.Name}`)
				end
			end
		end
	end

	if emittedSchemaCount == 0 and #methodNameLines == 0 then
		table.insert(report.emptyClasses, className)
	end

	local lines: { string } = {}
	table.insert(lines, FILE_HEADER)
	table.insert(lines, `\nlocal Types = require("../../Types")\n`)
	table.insert(lines, `local Runtime = require("../../../runtime")\n\n`)

	table.insert(
		lines,
		`-- Tipo público de "{className}". Campos/métodos que \`src/runtime/Instance.luau\` já cobre nativamente\n`
			.. `-- (ClassName/Name/Parent, os 5 sinais fixos, os 13 métodos base) NÃO são redeclarados aqui -- já vêm\n`
			.. `-- de \`Runtime.Instance &\` com o tipo real; redeclarar criaria redundância/risco de conflito de tipo.\n`
			.. `-- \`unknown\` (nunca \`any\`) para ValueType não representável nesta fase (Enum/DataType/Class) e para\n`
			.. `-- retorno/parametro de método cuja categoria não é Primitive -- ver tools/generate-services.luau,\n`
			.. `-- luauTypeForValueType/luauReturnType.\n`
	)
	table.insert(lines, `export type {className} = Runtime.Instance & \{\n`)
	for _, line in typeFieldLines do
		table.insert(lines, line)
	end
	table.insert(lines, "}\n\n")

	table.insert(lines, "local Generated: Types.GeneratedClass = {\n")
	table.insert(lines, `\tClassName = {luaStringLiteral(className)},\n`)
	table.insert(lines, `\tSuperclass = {luaStringLiteral(normalizedSuperclass)},\n`)
	table.insert(lines, `\tIsService = {tostring(isService)},\n`)
	table.insert(lines, `\tIsAbstract = {tostring(isAbstract)},\n`)
	table.insert(lines, "\tSchema = {\n")
	for _, line in schemaValueLines do
		table.insert(lines, line)
	end
	table.insert(lines, "\t} :: Runtime.ClassSchema,\n")
	table.insert(lines, "\tMethodNames = {\n")
	for _, line in methodNameLines do
		table.insert(lines, line)
	end
	table.insert(lines, "\t},\n")
	table.insert(lines, "}\n\n")
	table.insert(lines, "table.freeze(Generated.Schema)\n\n")
	table.insert(lines, "return Generated\n")

	return table.concat(lines)
end

-- ---- 9. Index.luau ----

local function generateIndex(): string
	local lines: { string } = {}
	table.insert(lines, FILE_HEADER)
	table.insert(
		lines,
		"\n-- Requires LITERAIS -- o `require` do Lune resolve estaticamente, não há require dinâmico\n"
			.. "-- por string (Decisão 1 do desenho). `src/services/init.luau` é quem itera este mapa.\n\n"
	)
	table.insert(lines, "local Types = require(\"../Types\")\n\n")
	table.insert(lines, "local Index: { [string]: Types.GeneratedClass } = {\n")
	for _, className in closureNames do
		table.insert(lines, `\t[{luaStringLiteral(className)}] = require("./classes/{className}") :: Types.GeneratedClass,\n`)
	end
	table.insert(lines, "}\n\n")
	table.insert(lines, "return Index\n")
	return table.concat(lines)
end

-- ============================================================================================
-- Executa a geração
-- ============================================================================================

resetGeneratedDir()

fs.writeFile(`{GENERATED_DIR}/Manifest.luau`, generateManifest())

for _, className in closureNames do
	fs.writeFile(`{CLASSES_DIR}/{className}.luau`, generateClassFile(className))
end

fs.writeFile(`{GENERATED_DIR}/Index.luau`, generateIndex())

-- ============================================================================================
-- 10. Relatório final
-- ============================================================================================

print("\n[generate-services] geração concluída.")
print(`  Fecho de classes geradas: {#closureNames} ({table.concat(closureNames, ", ")})`)
print(`  Manifest.luau: {#dump.Classes} entradas`)
print(
	`  MethodNames no fecho: {report.totalMethodsKept} mantidos, {report.totalMethodsExcludedSecurity} excluídos por Security, {report.totalMethodsExcludedCapability} excluídos por Capability`
)

table.sort(report.schemaExcludedByCapability)
print(`\n  Schema (Property/Event/Callback) excluído por Capability reservada ({#report.schemaExcludedByCapability}):`)
for _, entry in report.schemaExcludedByCapability do
	print(`    {entry}`)
end

table.sort(report.deprecatedEmitted)
print(`\n  Deprecated emitidas no schema/MethodNames ({#report.deprecatedEmitted}):`)
for _, entry in report.deprecatedEmitted do
	print(`    {entry}`)
end

local classesWithNonRepresentable = sortedKeys((function(): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for name in report.nonRepresentableDefaultsByClass do
		set[name] = true
	end
	return set
end)())
print(`\n  Defaults não representáveis nesta fase (Enum/DataType/Class/sentinela), por classe:`)
for _, className in classesWithNonRepresentable do
	print(`    {className}: {report.nonRepresentableDefaultsByClass[className]}`)
end

table.sort(report.notCoveredByRuntimeInstance)
print(`\n  Membros de Object/Instance emitidos no schema mas NÃO cobertos nativamente por runtime/Instance.luau ({#report.notCoveredByRuntimeInstance}):`)
for _, entry in report.notCoveredByRuntimeInstance do
	print(`    {entry}`)
end

table.sort(report.danglingObjectFunctions)
print(
	`\n  Funções de Object NÃO dobradas em Instance.MethodNames (gap conhecido, ver Decisão 1 -- IsA já é nativo, GetPropertyChangedSignal/isA ficam sem behavior nesta leva) ({#report.danglingObjectFunctions}):`
)
for _, entry in report.danglingObjectFunctions do
	print(`    {entry}`)
end

table.sort(report.emptyClasses)
print(`\n  Classes do fecho sem NENHUM Schema/MethodNames emitido (contêiner puro, Members == [] ou tudo filtrado) ({#report.emptyClasses}):`)
for _, className in report.emptyClasses do
	print(`    {className}`)
end

print("\n[generate-services] OK.")
process.exit(0)
