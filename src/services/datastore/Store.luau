--!strict

--[[
	O store de DataStore em memória -- dado puro, SEM `Runtime.Instance`, SEM I/O (fs/net), vivo
	enquanto o PROCESSO do LuauBench vive (persistência entre execuções fica para uma leva futura
	-- ver `.claude/agents-memory/arquiteto-services-2026-09-05.md`, "L2.1.2": "services NUNCA
	chama @lune/fs"; o contrato de injeção `Types.DataStorePersistence` é responsabilidade de uma
	tarefa futura que ENVOLVE `Instance`, fora do território desta tarefa).

	Território desta tarefa (task-services-017): só este módulo e `./Value.luau` (+ specs) --
	nenhum `behavior/*.luau` é criado aqui. Uma tarefa futura (`behavior/DataStoreService.luau`/
	`GlobalDataStore.luau`/etc.) vai: (a) chamar `Value.AssertNameLength`/`Value.Validate` ANTES de
	chamar os métodos deste módulo (este módulo NÃO valida nada -- ver "FRONTEIRA DE
	RESPONSABILIDADE" abaixo); (b) memoizar `GetDataStore(name, scope)` por `(name, scope)`,
	computando o `storeId` opaco que os métodos abaixo recebem (ex.: `name .. "\\1" .. scope`) --
	essa memoização É uma responsabilidade de Instance (cache de `DataStore`/`GlobalDataStore`
	reais) e por isso não mora aqui.

	FORMATO INTERNO: `(storeId, key) -> KeyRecord`, onde `KeyRecord` guarda o HISTÓRICO de versões
	daquela chave (nunca só a última) -- é o que permite `RemoveAsync` não apagar (L2.1.3:
	"RemoveAsync -> tombstone, versões antigas continuam legíveis"). `CreatedTime` mora no
	`KeyRecord` (constante -- é quando a CHAVE nasceu, a 1ª vez que alguém escreveu nela) e
	`UpdatedTime` mora em cada `VersionRecord` (quando AQUELA versão específica foi escrita) --
	mesma distinção que `DataStoreKeyInfo.CreatedTime`/`UpdatedTime` fazem no Roblox real.

	FRONTEIRA DE RESPONSABILIDADE (por que este módulo não valida nada): `./Value.luau` decide "o
	valor é válido?" (serializável, dentro do limite de tamanho); ESTE módulo decide "o que
	acontece com um valor já aceito?" (versionamento, tombstone, deep copy). Consequência: `Set`/
	`Update` aqui NUNCA erram por causa do CONTEÚDO de `value` -- um valor não serializável (ex.:
	uma função) passa por `Store.Set` sem erro nenhum (fica "guardado" como está, do jeito que um
	teste consegue observar isso sozinho, sem precisar simular `GlobalDataStore` inteiro). A tarefa
	futura que escrever `behavior/GlobalDataStore.luau` é quem CHAMA `Value.Validate(value)` antes
	de chamar `store:Set(...)`/dentro do `transform` de `store:Update(...)` -- nunca o contrário.

	DEEP COPY: aplicada nos DOIS lados de TODA leitura/escrita (`Value`, `UserIds`, `Metadata`) --
	nunca só no valor principal. Ver `./Value.luau`, cabeçalho, "DEEP COPY" para o raciocínio
	completo (por que isso não é opcional: sem cópia, mutar o retorno de `Get` alteraria o dado
	guardado -- um alias silencioso que esconderia uma classe inteira de bug real).

	VERSION (string): formato PRÓPRIO do LuauBench (`"{updatedTimeMillis}-{contador}"`, largura
	fixa para ordenar lexicograficamente igual à ordem de inserção) -- DIVERGÊNCIA DECLARADA (regra
	00): o Roblox real usa um identificador opaco cujo formato exato não é documentado
	publicamente; nenhuma pesquisa desta leva tentou reproduzi-lo byte-a-byte, e não haveria como
	confirmar sem uma chamada real ao serviço. O que importa para `ProfileStore`/scripts reais é só
	que `Version` seja uma STRING estável, única e (aqui, como bônus) ordenável -- não que tenha
	uma forma específica.

	CreatedTime/UpdatedTime (ms desde epoch, `int64` no dump): construídos com
	`require("@lune/datetime").now().unixTimestampMillis` -- módulo padrão do Lune (nenhuma
	dependência nova, regra 00), com granularidade de MILISSEGUNDO real (confirmado empiricamente:
	chamadas sucessivas em rajada produzem valores distintos a cada dezena de ms, não só a cada
	segundo). CORREÇÃO 2026-09-05 (revisão de task-services-017): a versão anterior deste módulo
	usava `os.time() * 1000`, que só tem granularidade de SEGUNDO -- isso fazia duas versões
	escritas dentro do mesmo segundo compartilharem o MESMO `UpdatedTime`, uma divergência de
	precisão real em relação ao Roblox (que guarda `int64` em ms de verdade). Não há mais essa
	divergência: `UpdatedTime`/`CreatedTime` aqui já têm a mesma granularidade de milissegundo que o
	Roblox documenta para `DataStoreKeyInfo.CreatedTime`/`UpdatedTime`.

	DECISÃO (não confirmada por pesquisa, registrada para o próximo agente não redescobrir):
	`Update` cujo `transform` devolve `nil` ABORTA a escrita e devolve `(nil, nil)` -- não o valor
	ANTERIOR. É o comportamento mais comumente descrito para `UpdateAsync` (a chamada "não fez
	nada", então não há valor novo para devolver), mas a pesquisa desta leva
	(pesquisa-datastore-2026-09-05.md) não cravou uma fonte primária para ESTE detalhe específico
	-- se uma pesquisa futura confirmar o contrário, é troca de 2 linhas em `Update`, não de
	arquitetura. Da mesma forma, `Remove` numa chave JÁ tombstoned (ou nunca escrita) é NO-OP
	idempotente (`(nil, nil)`, nenhuma versão nova) -- judgment call na ausência de fonte, não
	comportamento inventado com pretensão de certeza.

	Depende de `./Value.luau` (para `Value.DeepCopy` -- nunca reimplementado aqui, mesmo módulo,
	mesma disciplina de "uma fábrica só" que `.claude/rules/06-valuetypes.md` já pede para
	`Userdata.luau`) e de `@lune/datetime` (só para `DateTime.now().unixTimestampMillis`, ver
	"CreatedTime/UpdatedTime" acima -- módulo padrão do Lune, não uma dependência nova). Usado, em
	tarefas futuras, por `../behavior/GlobalDataStore.luau`/`DataStore.luau`/
	`OrderedDataStore.luau` (fora do território desta tarefa) -- por isso a API pública abaixo já
	cobre `Set`/`Get`/`Update`/`Remove` com a forma que esses `behavior`s vão precisar, mesmo sem
	existirem ainda.
]]

local DateTime = require("@lune/datetime")

local Value = require("./Value")

local Store = {}

-- ============================================================================================
-- Tipos públicos
-- ============================================================================================

export type VersionInfo = {
	Version: string,
	CreatedTime: number, -- ms desde epoch -- constante por CHAVE (não por versão)
	UpdatedTime: number, -- ms desde epoch -- desta versão especificamente
	UserIds: { number },
	Metadata: { [string]: unknown },
	Tombstone: boolean,
}

export type Transform = (oldValue: unknown, oldKeyInfo: VersionInfo?) -> (unknown, { number }?, { [string]: unknown }?)

export type Store = {
	-- Devolve (valor deep-copiado, keyInfo) da versão CORRENTE, ou (nil, nil) se a chave nunca
	-- existiu OU a versão corrente é um tombstone (RemoveAsync) -- espelha
	-- `GlobalDataStore:GetAsync`, L2.1.3.
	Get: (self: Store, storeId: string, key: string) -> (unknown, VersionInfo?),

	-- Cria uma NOVA versão (nunca sobrescreve a anterior -- ela continua no histórico) e devolve o
	-- `Version` dela. `userIds`/`metadata` ausentes viram `{}` -- espelha `GlobalDataStore:SetAsync`.
	Set: (
		self: Store,
		storeId: string,
		key: string,
		value: unknown,
		userIds: { number }?,
		metadata: { [string]: unknown }?
	) -> string,

	-- Lê a versão corrente (ou `(nil, nil)` se ausente/tombstoned), chama `transform(oldValue,
	-- oldKeyInfo)`; se o 1º retorno for `nil`, ABORTA (devolve `(nil, nil)`, nenhuma versão nova);
	-- senão cria uma nova versão com o valor/userIds/metadata devolvidos e repassa
	-- (valor deep-copiado, keyInfo) da versão NOVA -- espelha `GlobalDataStore:UpdateAsync`.
	Update: (self: Store, storeId: string, key: string, transform: Transform) -> (unknown, VersionInfo?),

	-- Devolve (valor deep-copiado, keyInfo) de ANTES da remoção, ou `(nil, nil)` se já
	-- ausente/tombstoned (no-op idempotente). Cria uma NOVA versão marcada `Tombstone = true` --
	-- NUNCA apaga o histórico anterior -- espelha `GlobalDataStore:RemoveAsync`, L2.1.3.
	Remove: (self: Store, storeId: string, key: string) -> (unknown, VersionInfo?),

	-- Primitiva de HISTÓRICO -- devolve (valor deep-copiado, keyInfo) de UMA versão específica por
	-- `Version` (a string devolvida por `Set`/`Update` em algum momento no passado), OU `(nil,
	-- nil)` se aquela `Version` nunca existiu naquela chave. Devolve a versão MESMO que ela (ou
	-- uma posterior) esteja tombstoned -- é o que prova "versões antigas continuam legíveis"
	-- (L2.1.3) mesmo depois de um `Remove`. NÃO é `GetVersionAsync`/`ListVersionsAsync`/
	-- `DataStoreVersionPages` (paginação, ordenação, filtro de data) -- esses ficam para a
	-- sub-leva B (L2.1.3, fora do território desta tarefa); isto é só o bloco de construção que
	-- eles vão empilhar em cima, sem precisar redesenhar `KeyRecord`/`VersionRecord`.
	GetVersion: (self: Store, storeId: string, key: string, version: string) -> (unknown, VersionInfo?),
}

-- ============================================================================================
-- Estado interno (privado a cada `Store.new()` -- dois stores nunca compartilham dado)
-- ============================================================================================

type VersionRecord = {
	Version: string,
	Value: unknown, -- já deep-copiado no momento em que a versão foi criada
	UpdatedTime: number,
	UserIds: { number },
	Metadata: { [string]: unknown },
	Tombstone: boolean,
}

type KeyRecord = {
	CreatedTime: number,
	Versions: { VersionRecord }, -- ordem cronológica de escrita; a corrente é sempre a última
}

function Store.new(): Store
	-- `[storeId][key] -> KeyRecord`. `storeId` é opaco para este módulo -- ver cabeçalho,
	-- "Território desta tarefa", item (b).
	local data: { [string]: { [string]: KeyRecord } } = {}
	local versionCounter = 0

	-- Milissegundo real (ver cabeçalho, "CreatedTime/UpdatedTime") -- `@lune/datetime` (não
	-- `os.time()`, que só dá granularidade de segundo).
	local function nowMillis(): number
		return DateTime.now().unixTimestampMillis
	end

	-- Largura fixa (13 dígitos cobre ms até o ano ~5138; 10 dígitos cobre 10 bilhões de escritas
	-- no processo) para que a ordem lexicográfica de `Version` bata com a ordem de inserção --
	-- ver cabeçalho, "VERSION (string)".
	local function nextVersion(updatedTime: number): string
		versionCounter += 1
		return string.format("%013d-%010d", updatedTime, versionCounter)
	end

	local function currentVersionOf(record: KeyRecord): VersionRecord
		return record.Versions[#record.Versions]
	end

	local function toVersionInfo(record: KeyRecord, version: VersionRecord): VersionInfo
		return {
			Version = version.Version,
			CreatedTime = record.CreatedTime,
			UpdatedTime = version.UpdatedTime,
			UserIds = Value.DeepCopy(version.UserIds),
			Metadata = Value.DeepCopy(version.Metadata),
			Tombstone = version.Tombstone,
		}
	end

	-- Lê a versão CORRENTE sem aplicar a regra de tombstone -- quem chama decide se um tombstone
	-- conta como "ausente" (Get/Update, que tratam tombstone como nil) ou não (Remove, que
	-- precisa do valor tombstoned para responder "já removido" sem criar mais uma versão).
	local function readCurrent(storeId: string, key: string): (KeyRecord?, VersionRecord?)
		local storeData = data[storeId]
		if storeData == nil then
			return nil, nil
		end
		local record = storeData[key]
		if record == nil then
			return nil, nil
		end
		return record, currentVersionOf(record)
	end

	-- Busca uma versão ESPECÍFICA pelo `Version` (string) no histórico da chave, independente de
	-- ser a corrente ou não, e independente de tombstone -- usada só por `GetVersion` (ver
	-- cabeçalho, "Primitiva de HISTÓRICO"). Histórico nunca é grande o bastante (uma escrita por
	-- chamada de `Set`/`Update`/`Remove`) para uma busca linear importar.
	local function findVersion(record: KeyRecord, versionId: string): VersionRecord?
		for _, version in record.Versions do
			if version.Version == versionId then
				return version
			end
		end
		return nil
	end

	-- Ponto ÚNICO de criação de versão -- `Set`/`Update`/`Remove` (via tombstone) passam por
	-- aqui, nunca duplicam a lógica de "criar KeyRecord se for a 1ª escrita" / "gerar Version" /
	-- "deep-copiar antes de guardar".
	local function writeVersion(
		storeId: string,
		key: string,
		value: unknown,
		userIds: { number }?,
		metadata: { [string]: unknown }?,
		tombstone: boolean
	): (KeyRecord, VersionRecord)
		local storeData = data[storeId]
		if storeData == nil then
			storeData = {}
			data[storeId] = storeData
		end

		local record = storeData[key]
		local now = nowMillis()
		if record == nil then
			record = { CreatedTime = now, Versions = {} }
			storeData[key] = record
		end

		local version: VersionRecord = {
			Version = nextVersion(now),
			Value = Value.DeepCopy(value), -- OBRIGATÓRIO na escrita -- ver cabeçalho, "DEEP COPY"
			UpdatedTime = now,
			UserIds = if userIds ~= nil then Value.DeepCopy(userIds) else {},
			Metadata = if metadata ~= nil then Value.DeepCopy(metadata) else {},
			Tombstone = tombstone,
		}
		table.insert(record.Versions, version)
		return record, version
	end

	local self: Store = {} :: Store

	self.Get = function(_self: Store, storeId: string, key: string): (unknown, VersionInfo?)
		local record, version = readCurrent(storeId, key)
		if record == nil or version == nil or version.Tombstone then
			return nil, nil
		end
		return Value.DeepCopy(version.Value), toVersionInfo(record, version)
	end

	self.Set = function(
		_self: Store,
		storeId: string,
		key: string,
		value: unknown,
		userIds: { number }?,
		metadata: { [string]: unknown }?
	): string
		local _record, version = writeVersion(storeId, key, value, userIds, metadata, false)
		return version.Version
	end

	self.Update = function(_self: Store, storeId: string, key: string, transform: Transform): (unknown, VersionInfo?)
		local record, version = readCurrent(storeId, key)

		local oldValue: unknown = nil
		local oldKeyInfo: VersionInfo? = nil
		if record ~= nil and version ~= nil and not version.Tombstone then
			oldValue = Value.DeepCopy(version.Value)
			oldKeyInfo = toVersionInfo(record, version)
		end

		local newValue, newUserIds, newMetadata = transform(oldValue, oldKeyInfo)
		if newValue == nil then
			-- Aborta -- ver cabeçalho, "DECISÃO (não confirmada por pesquisa)".
			return nil, nil
		end

		local newRecord, newVersion = writeVersion(storeId, key, newValue, newUserIds, newMetadata, false)
		return Value.DeepCopy(newVersion.Value), toVersionInfo(newRecord, newVersion)
	end

	self.Remove = function(_self: Store, storeId: string, key: string): (unknown, VersionInfo?)
		local record, version = readCurrent(storeId, key)
		if record == nil or version == nil or version.Tombstone then
			-- Já ausente/removido -- NO-OP idempotente, ver cabeçalho.
			return nil, nil
		end

		local previousValue = Value.DeepCopy(version.Value)
		local previousKeyInfo = toVersionInfo(record, version)

		-- Nova versão TOMBSTONE -- carrega o MESMO Value/UserIds/Metadata adiante (histórico
		-- preservado), só marca `Tombstone = true`. `RemoveAsync` real não pede esses argumentos
		-- de novo, então não há "novo valor" para receber aqui.
		writeVersion(storeId, key, version.Value, version.UserIds, version.Metadata, true)

		return previousValue, previousKeyInfo
	end

	self.GetVersion = function(_self: Store, storeId: string, key: string, version: string): (unknown, VersionInfo?)
		local storeData = data[storeId]
		if storeData == nil then
			return nil, nil
		end
		local record = storeData[key]
		if record == nil then
			return nil, nil
		end
		local found = findVersion(record, version)
		if found == nil then
			return nil, nil
		end
		-- Devolve MESMO se `found.Tombstone == true` -- ver cabeçalho, "Primitiva de HISTÓRICO":
		-- versões antigas continuam legíveis mesmo depois de um Remove.
		return Value.DeepCopy(found.Value), toVersionInfo(record, found)
	end

	return self
end

return Store
