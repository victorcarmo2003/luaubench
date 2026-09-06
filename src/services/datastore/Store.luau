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

	EXPORT/IMPORT/MARCA-SUJA (task-services-030, desenho:
	`.claude/agents-memory/arquiteto-persistencia-cloud-2026-09-06.md`, seção 5) -- acrescenta bulk
	e marca-suja para permitir persistência local do estado "cloud" entre execuções sucessivas do
	LuauBench, SEM que este módulo passe a saber o que é JSON/arquivo/caminho (essa fronteira
	continua exatamente como o resto do cabeçalho já declara -- `services` nunca chama `@lune/fs`,
	ver `.claude/agents-memory/arquiteto-services-2026-09-05.md`, "L2.1.2").

	- `Export`: devolve o estado inteiro DEEP-COPIADO como `Snapshot` (tipo abaixo), aplicando PODA
	  POR IDADE de 30 dias -- retenção CONFIRMADA (não é número inventado, regra 00) por
	  `.claude/agents-memory/pesquisa-datastore-2026-09-05.md`, linha 127: "versões antigas
	  continuam acessíveis por 30 dias via `ListVersionsAsync`/`GetVersionAsync`". Toda versão
	  NÃO-CORRENTE com `UpdatedTime` mais velho que 30 dias é descartada do snapshot; a versão
	  CORRENTE nunca é podada, mesmo velha -- do contrário a chave inteira desapareceria do
	  snapshot, o que não é "expirar histórico velho", é perder a chave.
	- `Import`: substitui o estado inteiro. VALIDA a forma do snapshot ANTES de tocar em qualquer
	  estado interno (tudo-ou-nada -- nunca aceita parcialmente, nunca deixa o `Store` num estado
	  misto entre o antigo e o novo se o meio do snapshot for inválido). Recusa com mensagem clara
	  apontando o `storeId`/`key`/campo problemático -- nunca um erro genérico de indexação.
	  OBRIGATORIAMENTE restaura `versionCounter = max(contador de toda versão do snapshot) + 1`:
	  sem isso, a garantia que este módulo já declara acima ("VERSION (string)": largura fixa para
	  que ordem lexicográfica == ordem de inserção) quebraria em SILÊNCIO na 2ª execução do
	  processo -- uma escrita nova no mesmo milissegundo de uma versão importada com contador maior
	  ordenaria ANTES dela. O contador é extraído do próprio formato que `nextVersion` já produz
	  (`"%013d-%010d"`, os 10 dígitos depois do `-`) -- nenhum formato novo, só parse do que este
	  módulo mesmo escreve.
	- `IsDirty`/`ClearDirty`: marca síncrona O(1), TRUE a cada escrita bem-sucedida que passa por
	  `writeVersion` (`Set`, `Update` que não abortou, `Remove` que não foi no-op -- exatamente as
	  três operações que criam uma versão nova de verdade). `Import` também zera a marca (o estado
	  recém-carregado não tem "mudança não persistida" nenhuma). Este módulo NÃO persiste nada
	  sozinho -- `IsDirty`/`ClearDirty` só sinalizam para quem CONSOME `Export` (fora deste módulo,
	  tarefa futura) se vale a pena pagar o custo de serializar de novo.
]]

local DateTime = require("@lune/datetime")

local Value = require("./Value")

local Store = {}

-- Retenção de histórico -- CONFIRMADA (não inventada, regra 00) por
-- `.claude/agents-memory/pesquisa-datastore-2026-09-05.md`, linha 127. Usada só por `Store.Export`
-- (ver cabeçalho, "EXPORT/IMPORT/MARCA-SUJA").
local RETENTION_MILLIS = 30 * 24 * 60 * 60 * 1000

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

-- ACRESCENTADO em task-services-030 (ver cabeçalho, "EXPORT/IMPORT/MARCA-SUJA") -- forma em memória
-- de UMA versão dentro de um snapshot. Estruturalmente igual a `VersionRecord` (privado, abaixo),
-- exposta com nome próprio porque é contrato PÚBLICO entre `Store.Export`/`Store.Import` e quem
-- os consome -- nunca o mesmo tipo que o estado interno, mesmo que hoje tenham os mesmos campos
-- (um puder divergir do outro sem quebrar a API pública).
export type StoredVersion = {
	Version: string,
	Value: unknown, -- valor Luau cru, já deep-copiado; envelopar para JSON é responsabilidade de quem serializa (fora deste módulo)
	UpdatedTime: number,
	UserIds: { number },
	Metadata: { [string]: unknown },
	Tombstone: boolean,
}

-- Histórico de UMA chave dentro de um snapshot -- `Versions` já vem com a poda de 30 dias aplicada
-- (ver `Store.Export`), em ordem cronológica crescente, sempre com pelo menos 1 elemento (a
-- corrente nunca é podada).
export type StoredKey = {
	CreatedTime: number,
	Versions: { StoredVersion },
}

-- Estado inteiro de um `Store`: `[storeId][key] -> StoredKey`. `storeId` continua opaco para este
-- módulo (ver cabeçalho, "Território desta tarefa", item (b)).
export type Snapshot = { [string]: { [string]: StoredKey } }

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
	-- `DataStoreVersionPages` (paginação, ordenação, filtro de data) -- ver `ListVersions`/
	-- `ListKeys` abaixo (task-services-019, sub-leva B) para o bloco de construção que
	-- `../behavior/DataStore.luau` empilha em cima disto, sem precisar redesenhar
	-- `KeyRecord`/`VersionRecord`.
	GetVersion: (self: Store, storeId: string, key: string, version: string) -> (unknown, VersionInfo?),

	-- ACRESCENTADO em task-services-019 (sub-leva B: `GetVersionAsync`/`ListVersionsAsync`/
	-- `ListKeysAsync`, ver `../behavior/DataStore.luau`) -- exatamente o "bloco de construção"
	-- que o comentário de `GetVersion`, acima, já antecipava desde task-017. Devolve TODO o
	-- HISTÓRICO de versões de `key` (deep-copiado, MESMO as tombstoned -- histórico completo,
	-- sem filtro nenhum, L2.1.3), em ORDEM CRONOLÓGICA CRESCENTE (mais antiga primeiro -- a mesma
	-- ordem de inserção de `record.Versions`). `{}` se a chave nunca existiu neste `storeId`.
	-- Filtro de data/ordenação/paginação são responsabilidade de quem chama (`DataStore.luau`) --
	-- este módulo continua sem saber o que é `Pages`/paginação, mesma fronteira de
	-- responsabilidade do cabeçalho ("FRONTEIRA DE RESPONSABILIDADE").
	ListVersions: (self: Store, storeId: string, key: string) -> { VersionInfo },

	-- ACRESCENTADO em task-services-019 -- lista TODAS as chaves conhecidas de `storeId` (mesmo as
	-- cuja versão corrente é tombstone -- quem decide excluir removidas é `ListKeysAsync`, via
	-- `excludeDeleted`, em `DataStore.luau`; este módulo só expõe o dado cru), cada uma com o
	-- `VersionInfo` (deep-copiado) da sua versão CORRENTE. ORDEM: alfabética (`table.sort` sobre a
	-- string da chave) -- o Roblox real não documenta uma ordem específica para `ListKeysAsync`;
	-- ordem determinística e testável é preferível a depender da ordem de iteração de `pairs`
	-- (que não é estável entre execuções). `{}` se `storeId` nunca recebeu nenhuma escrita.
	ListKeys: (self: Store, storeId: string) -> { { Key: string, Current: VersionInfo } },

	-- ACRESCENTADO em task-services-030 -- ver cabeçalho, "EXPORT/IMPORT/MARCA-SUJA". Estado
	-- inteiro, DEEP-COPIADO (mesma disciplina de "DEEP COPY" do cabeçalho -- mutar o snapshot
	-- devolvido nunca afeta este `Store`), com a poda por idade de 30 dias já aplicada. Não
	-- conhece JSON, arquivo ou caminho -- isso é responsabilidade de quem chama.
	Export: (self: Store) -> Snapshot,

	-- Substitui o estado inteiro. Valida a forma do snapshot ANTES de mudar qualquer estado
	-- interno (tudo-ou-nada) e ERRA com mensagem clara apontando o campo problemático se malformado
	-- -- nunca aceita parcialmente, nunca crasha genérico. Restaura `versionCounter` a partir do
	-- maior contador visto em qualquer versão do snapshot (ver cabeçalho -- sem isso a garantia de
	-- ordenação lexicográfica de `Version` quebra em silêncio numa 2ª execução). Zera a marca-suja
	-- (o estado recém-carregado não tem mudança pendente nenhuma).
	Import: (self: Store, snapshot: Snapshot) -> (),

	-- `true` desde a última escrita bem-sucedida (Set/Update não-abortado/Remove não-no-op) até o
	-- próximo `ClearDirty`/`Import`. `false` recém-`Store.new()`.
	IsDirty: (self: Store) -> boolean,

	-- Zera a marca-suja -- chamado por quem acabou de persistir o resultado de `Export`. Este
	-- módulo nunca chama isto sozinho (não sabe quando uma persistência de verdade aconteceu).
	ClearDirty: (self: Store) -> (),
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

	-- Marca-suja (ver cabeçalho, "EXPORT/IMPORT/MARCA-SUJA") -- `true` desde a última escrita
	-- bem-sucedida até o próximo `ClearDirty`/`Import`. `false` recém-`Store.new()`.
	local dirty = false

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

		-- Ponto ÚNICO de marca-suja -- toda escrita que passa por aqui É uma mutação de verdade
		-- (Set sempre; Update só quando não abortou; Remove só quando não era no-op -- exatamente
		-- as três chamam `writeVersion`). Ver cabeçalho, "EXPORT/IMPORT/MARCA-SUJA".
		dirty = true

		return record, version
	end

	-- Extrai o contador de `nextVersion` (os 10 dígitos depois do último `-`) -- usado só por
	-- `Import` para restaurar `versionCounter` (ver cabeçalho). `nil` se `versionString` não bate
	-- com o formato que este módulo mesmo produz (defensivo -- não deveria acontecer para um
	-- snapshot que veio de `Export` deste módulo, mas nunca panica por causa disso).
	local function parseVersionCounter(versionString: string): number?
		local counterPart = string.match(versionString, "%-(%d+)$")
		if counterPart == nil then
			return nil
		end
		return tonumber(counterPart)
	end

	-- Valida a FORMA de um `Snapshot` recebido por `Import`, campo a campo, devolvendo a primeira
	-- mensagem de erro encontrada (ou `nil` se válido). Não confia no tipo estático de `snapshot`
	-- -- trata como dado externo desconhecido (pode ter vindo de um arquivo em disco, de fora deste
	-- módulo) e valida em runtime, exatamente a disciplina que "recusa snapshot malformado" pede.
	-- Não muda `data`/`versionCounter` -- só inspeciona; `Import` só aplica DEPOIS de validar tudo
	-- (tudo-ou-nada, ver cabeçalho).
	local function validateSnapshot(snapshot: Snapshot): string?
		local rawSnapshot = snapshot :: unknown
		if type(rawSnapshot) ~= "table" then
			return `snapshot must be a table (got {type(rawSnapshot)})`
		end

		for storeId, storeData in rawSnapshot :: { [unknown]: unknown } do
			if type(storeId) ~= "string" then
				return `snapshot has a non-string storeId key ({tostring(storeId)})`
			end
			if type(storeData) ~= "table" then
				return `snapshot["{storeId}"] must be a table of keys (got {type(storeData)})`
			end

			for key, rawKeyRecord in storeData :: { [unknown]: unknown } do
				if type(key) ~= "string" then
					return `snapshot["{storeId}"] has a non-string key ({tostring(key)})`
				end
				if type(rawKeyRecord) ~= "table" then
					return `snapshot["{storeId}"]["{key}"] must be a table (got {type(rawKeyRecord)})`
				end

				local keyRecord = rawKeyRecord :: { [string]: unknown }
				if type(keyRecord.CreatedTime) ~= "number" then
					return `snapshot["{storeId}"]["{key}"].CreatedTime must be a number`
				end
				if type(keyRecord.Versions) ~= "table" then
					return `snapshot["{storeId}"]["{key}"].Versions must be a table (array)`
				end

				local versions = keyRecord.Versions :: { unknown }
				if #versions == 0 then
					return `snapshot["{storeId}"]["{key}"].Versions must not be empty (a key with no versions cannot exist)`
				end

				for index, rawVersion in versions do
					if type(rawVersion) ~= "table" then
						return `snapshot["{storeId}"]["{key}"].Versions[{index}] must be a table (got {type(rawVersion)})`
					end

					local version = rawVersion :: { [string]: unknown }
					if type(version.Version) ~= "string" then
						return `snapshot["{storeId}"]["{key}"].Versions[{index}].Version must be a string`
					end
					if type(version.UpdatedTime) ~= "number" then
						return `snapshot["{storeId}"]["{key}"].Versions[{index}].UpdatedTime must be a number`
					end
					if type(version.UserIds) ~= "table" then
						return `snapshot["{storeId}"]["{key}"].Versions[{index}].UserIds must be a table (array)`
					end
					if type(version.Metadata) ~= "table" then
						return `snapshot["{storeId}"]["{key}"].Versions[{index}].Metadata must be a table`
					end
					if type(version.Tombstone) ~= "boolean" then
						return `snapshot["{storeId}"]["{key}"].Versions[{index}].Tombstone must be a boolean`
					end
					-- `Value` pode ser qualquer coisa, inclusive `nil` -- este módulo não valida
					-- serializabilidade (ver cabeçalho, "FRONTEIRA DE RESPONSABILIDADE").
				end
			end
		end

		return nil
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

	self.ListVersions = function(_self: Store, storeId: string, key: string): { VersionInfo }
		local storeData = data[storeId]
		if storeData == nil then
			return {}
		end
		local record = storeData[key]
		if record == nil then
			return {}
		end

		-- `record.Versions` já está em ordem cronológica crescente (append-only, ver
		-- `writeVersion`) -- nenhum `table.sort` necessário aqui; ordenar/inverter por
		-- `sortDirection` é responsabilidade de quem chama (ver o tipo `ListVersions`, acima).
		local result: { VersionInfo } = table.create(#record.Versions)
		for index, version in record.Versions do
			result[index] = toVersionInfo(record, version)
		end
		return result
	end

	self.ListKeys = function(_self: Store, storeId: string): { { Key: string, Current: VersionInfo } }
		local storeData = data[storeId]
		if storeData == nil then
			return {}
		end

		-- Ordem alfabética determinística -- ver o tipo `ListKeys`, acima, para o porquê.
		local keys: { string } = {}
		for key in storeData do
			table.insert(keys, key)
		end
		table.sort(keys)

		local result: { { Key: string, Current: VersionInfo } } = table.create(#keys)
		for index, key in keys do
			local record = storeData[key]
			result[index] = { Key = key, Current = toVersionInfo(record, currentVersionOf(record)) }
		end
		return result
	end

	self.Export = function(_self: Store): Snapshot
		local now = nowMillis()
		local snapshot: Snapshot = {}

		for storeId, storeData in data do
			local exportedStoreData: { [string]: StoredKey } = {}

			for key, record in storeData do
				local versions = record.Versions
				local lastIndex = #versions

				-- Poda por idade (ver cabeçalho): descarta versão NÃO-CORRENTE mais velha que
				-- `RETENTION_MILLIS`. A corrente (última do array) nunca é podada, mesmo velha.
				local prunedVersions: { StoredVersion } = {}
				for index, version in versions do
					local isCurrent = index == lastIndex
					if isCurrent or (now - version.UpdatedTime) <= RETENTION_MILLIS then
						table.insert(prunedVersions, {
							Version = version.Version,
							Value = Value.DeepCopy(version.Value),
							UpdatedTime = version.UpdatedTime,
							UserIds = Value.DeepCopy(version.UserIds),
							Metadata = Value.DeepCopy(version.Metadata),
							Tombstone = version.Tombstone,
						})
					end
				end

				exportedStoreData[key] = {
					CreatedTime = record.CreatedTime,
					Versions = prunedVersions,
				}
			end

			snapshot[storeId] = exportedStoreData
		end

		return snapshot
	end

	self.Import = function(_self: Store, snapshot: Snapshot): ()
		local errorMessage = validateSnapshot(snapshot)
		if errorMessage ~= nil then
			error(`Store.Import: malformed snapshot -- {errorMessage}`, 2)
		end

		-- Reconstrói o estado interno inteiro ANTES de substituir `data`/`versionCounter` -- se
		-- algo desse errado no meio (não deveria, já validado acima), o `Store` continuaria com o
		-- estado ANTIGO intacto em vez de ficar pela metade. Também calcula, na mesma passada, o
		-- maior contador de versão visto (ver cabeçalho, "restaura `versionCounter`").
		local newData: { [string]: { [string]: KeyRecord } } = {}
		local maxCounter = 0

		for storeId, storeData in snapshot do
			local newStoreData: { [string]: KeyRecord } = {}

			for key, keyRecord in storeData do
				local newVersions: { VersionRecord } = table.create(#keyRecord.Versions)
				for index, version in keyRecord.Versions do
					newVersions[index] = {
						Version = version.Version,
						Value = Value.DeepCopy(version.Value),
						UpdatedTime = version.UpdatedTime,
						UserIds = Value.DeepCopy(version.UserIds),
						Metadata = Value.DeepCopy(version.Metadata),
						Tombstone = version.Tombstone,
					}

					local counter = parseVersionCounter(version.Version)
					if counter ~= nil and counter > maxCounter then
						maxCounter = counter
					end
				end

				newStoreData[key] = {
					CreatedTime = keyRecord.CreatedTime,
					Versions = newVersions,
				}
			end

			newData[storeId] = newStoreData
		end

		data = newData
		versionCounter = maxCounter + 1
		-- Estado recém-carregado não tem mudança pendente nenhuma -- ver cabeçalho.
		dirty = false
	end

	self.IsDirty = function(_self: Store): boolean
		return dirty
	end

	self.ClearDirty = function(_self: Store): ()
		dirty = false
	end

	return self
end

return Store
