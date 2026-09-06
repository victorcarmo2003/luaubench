--!strict

--[[
	Behavior de `GlobalDataStore` -- task-services-018. LER
	.claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.1.3"/"L2.1.4"/"L2.1.5"/"L2.1.6",
	ANTES de mexer aqui. Constrói EM CIMA de `../AsyncCall.luau` (task-016, ponto único de yield) e
	`../datastore/Value.luau`/`../datastore/Store.luau` (task-017, validação/versionamento) -- este
	módulo NÃO reimplementa nada disso, só orquestra.

	`GlobalDataStore` é herdada por `DataStore`/`OrderedDataStore` (ver `generated/classes/
	DataStore.luau`/`OrderedDataStore.luau`, `Superclass = "GlobalDataStore"`) -- os `Methods`
	instalados aqui (na classe `GlobalDataStore`, registrada separadamente por `behavior/Index.luau`)
	chegam a QUALQUER instância de `DataStore`/`OrderedDataStore` via o achatamento de métodos que
	`Runtime.ClassRegistry.resolveClassMethods` já faz percorrendo a cadeia de classes -- nenhuma
	duplicação necessária em `behavior/DataStore.luau`/`OrderedDataStore.luau` (que nem existem
	nesta tarefa: `GetVersionAsync`/`ListVersionsAsync`/`ListKeysAsync`/`GetSortedAsync` ficam com o
	stub `[LuauBench]` do `ClassBuilder`, sub-leva B, fora do território desta tarefa).

	STORE ÚNICO, MÓDULO-LOCAL: `GlobalDataStore`/`DataStore`/`OrderedDataStore`/`DataStoreService`
	são, na prática, um serviço-só (`DataStoreService` é singleton, L2.0.2 último parágrafo) -- o
	`Store.new()` que guarda o dado de verdade mora aqui (não em `DataStoreService.luau`) porque é
	AQUI que os métodos que de fato leem/escrevem (`GetAsync`/`SetAsync`/`UpdateAsync`/`RemoveAsync`/
	`IncrementAsync`) vivem. `DataStoreService.luau` só precisa alcançar `StoreIdState` (exportado
	abaixo) para marcar, em cada instância que cria, QUAL storeId opaco ela endereça -- nunca o
	`Store` em si.

	`_LuauBenchStoreId`: estado privado por instância (L2.0.2) -- setado pela fábrica de
	`DataStoreService.luau` (`GetDataStore`/`GetGlobalDataStore`/`GetOrderedDataStore`), lido em
	TODO método abaixo via `storeIdOf`. Uma instância de `DataStore`/`OrderedDataStore`/
	`GlobalDataStore` que chegasse aqui SEM essa chave setada seria um bug de `services` (só a
	fábrica de `DataStoreService.luau` cria essas instâncias -- não há `Instance.new`/`Services.new`
	alcançável para elas, `IsAbstract = true` nas três) -- por isso o erro em `storeIdOf` é de
	ENGENHARIA INTERNA, em português.

	task-services-019 (sub-leva B): `./DataStore.luau` (`GetVersionAsync`/`ListVersionsAsync`/
	`ListKeysAsync`) é um SEGUNDO CONSUMIDOR deste módulo, além de `./DataStoreService.luau` -- por
	isso o `return` no final deste arquivo agora também exporta `Store`/`StoreIdOf`/`KeyInfoOrNil`
	(ver o comentário ali). Nenhuma linha de COMPORTAMENTO deste arquivo mudou nessa tarefa.

	task-services-020 (`OrderedDataStore`/`GetSortedAsync` -- LER
	.claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.1.3", e `./OrderedDataStore.luau`,
	cabeçalho, ANTES de mexer aqui): acrescenta a validação "valor precisa ser INTEIRO" que
	`OrderedDataStore` exige em `SetAsync`/`UpdateAsync`/`IncrementAsync` -- `GlobalDataStore`/
	`DataStore` continuam aceitando qualquer valor serializável, sem essa restrição.

	POR QUE A VALIDAÇÃO ENTRA AQUI, E NÃO EM `./OrderedDataStore.luau` (DESVIO DE TERRITÓRIO
	DECLARADO -- reportar ao chat principal): `SetAsync`/`UpdateAsync`/`IncrementAsync` são membros
	que o Roblox API Dump declara em `GlobalDataStore` (`generated/classes/OrderedDataStore.luau`,
	`MethodNames = { "GetSortedAsync" }` -- SÓ isso; os três nomes acima nem aparecem lá, porque o
	dump nunca redeclara um membro herdado). `ClassBuilder.Build` (`src/services/ClassBuilder.luau`,
	passo (a)) só aceita, no `behavior.Methods` de UMA classe, chaves que existem no `MethodNames`
	DELA MESMA -- registrar um `SetAsync` próprio em `behavior/OrderedDataStore.luau` estouraria
	"método 'SetAsync' não existe em 'OrderedDataStore' segundo o Roblox API Dump" no load
	(confirmado tentando: `ClassBuilder.Build` não conhece o MethodNames herdado, só o da própria
	`GeneratedClass`). Não há como sobrescrever SÓ para a subclasse através do achatamento de
	`Runtime.ClassRegistry.resolveClassMethods` sem alterar `ClassBuilder.luau`/`src/services/
	init.luau` (fora do território desta tarefa -- `.claude/tasks.json`, task-services-020: só
	`behavior/OrderedDataStore.luau` + spec + `behavior/Index.luau`/spec -- e mudança que afetaria
	TODAS as classes de `services`, não só esta família). Por isso a validação entra AQUI: dentro da
	MESMA função que já atende `GlobalDataStore`/`DataStore`/`OrderedDataStore` via achatamento de
	classe (ver "STORE ÚNICO, MÓDULO-LOCAL" acima), gated por `self.ClassName == "OrderedDataStore"`
	-- reaproveita a lógica inteira de `store:Set`/`store:Update` sem duplicar UMA linha dela, que é
	exatamente o pedido explícito da tarefa despachante: "confira como resolver isso sem duplicar
	toda a lógica de GlobalDataStore.luau". Ver `checkIntegerForOrderedDataStore`, abaixo, para a
	checagem em si, e `./OrderedDataStore.luau` para o resto da tarefa (GetSortedAsync + remoção
	permanente). Reportado como possível melhoria futura de `ClassBuilder`/gerador (aceitar, na
	validação, o MethodNames herdado de um fecho pré-computado) -- fora do escopo desta tarefa.

	POSITIVIDADE NÃO EXIGIDA: a tarefa despachante e a pesquisa desta leva
	(pesquisa-datastore-2026-09-05.md) só confirmam "inteiro" -- nenhuma fonte primária confirma
	"só positivo". `checkIntegerForOrderedDataStore` aceita qualquer inteiro finito (positivo,
	negativo, zero); nunca inventa uma restrição de sinal sem confirmação (regra 00).
]]

local Runtime = require("../../runtime")
local InstanceState = require("../InstanceState")
local AsyncCall = require("../AsyncCall")
local Value = require("../datastore/Value")
local Store = require("../datastore/Store")
local DataStoreKeyInfoBehavior = require("./DataStoreKeyInfo")
local DataStoreSetOptionsGenerated = require("../generated/classes/DataStoreSetOptions")
local DataStoreIncrementOptionsGenerated = require("../generated/classes/DataStoreIncrementOptions")

-- Store ÚNICO, vivo enquanto o processo vive -- ver cabeçalho, "STORE ÚNICO, MÓDULO-LOCAL".
local store: Store.Store = Store.new()

-- Exportado (ver cabeçalho): `DataStoreService.luau` seta esta chave em toda instância que cria.
local StoreIdState = InstanceState.new("_LuauBenchStoreId") :: InstanceState.InstanceStateAccessor<string>

local function storeIdOf(instance: Runtime.Instance): string
	local id = StoreIdState.Get(instance)
	if id == nil then
		error(
			"engenharia interna: instância de GlobalDataStore/DataStore/OrderedDataStore sem '_LuauBenchStoreId' -- só DataStoreService.luau (GetDataStore/GetGlobalDataStore/GetOrderedDataStore) pode criar essas instâncias, e sempre seta esta chave antes de devolvê-las",
			2
		)
	end
	return id
end

-- `nil` vira `nil` (chave inexistente/tombstoned) -- senão constrói um `DataStoreKeyInfo` fresco
-- via a fábrica de `./DataStoreKeyInfo.luau` (nunca um objeto memoizado -- o Roblox real também
-- devolve um NOVO `DataStoreKeyInfo` a cada `GetAsync`/`SetAsync`/etc.).
local function keyInfoOrNil(versionInfo: Store.VersionInfo?): Runtime.Instance?
	if versionInfo == nil then
		return nil
	end
	return DataStoreKeyInfoBehavior.New(versionInfo)
end

--[[
	Extrai `Metadata` de um `options: unknown` (`DataStoreSetOptions`/`DataStoreIncrementOptions`,
	opcional) recebido por `SetAsync`/`IncrementAsync`. TOLERANTE: `nil`, um valor de tipo errado, ou
	qualquer erro ao ler `.ClassName`/chamar `:GetMetadata()` devolve `nil` sem erro nenhum --
	DIVERGÊNCIA DECLARADA (regra 00): o Roblox real provavelmente rejeitaria um `options` de tipo
	errado com um erro de argumento nativo (`invalid argument #4 (DataStoreSetOptions expected)`);
	esta simulação, por não ser coberta pelo acceptance desta tarefa e para manter o caminho feliz
	(o único usado por ProfileStore e por scripts reais) simples, prefere ignorar silenciosamente um
	`options` malformado a inventar uma mensagem `[LuauBench]`/família Roblox não confirmada para
	esse caso.

	`pcall` é necessário aqui (não é o "pcall silencioso" que a regra 01 proíbe -- não há erro real
	de script sendo engolido, só uma tentativa de leitura sobre um valor de tipo desconhecido que
	pode ser QUALQUER coisa vinda do script: número, boolean, string, outro userdata sem
	`.ClassName`): indexar `.ClassName` sobre um valor que não é uma `Instance` do LuauBench (ex.: um
	número) erraria "attempt to index a number value" sem a proteção.
]]
local function extractMetadata(options: unknown): { [string]: unknown }?
	if options == nil then
		return nil
	end

	local metadata: { [string]: unknown }? = nil
	local ok = pcall(function()
		local instanceValue = options :: Runtime.Instance
		local className = instanceValue.ClassName
		if className == "DataStoreSetOptions" then
			metadata = (options :: DataStoreSetOptionsGenerated.DataStoreSetOptions):GetMetadata()
		elseif className == "DataStoreIncrementOptions" then
			metadata = (options :: DataStoreIncrementOptionsGenerated.DataStoreIncrementOptions):GetMetadata()
		end
	end)

	if not ok then
		return nil
	end
	return metadata
end

--[[
	task-services-020 -- ver o cabeçalho deste arquivo, "task-services-020", para o porquê desta
	função morar aqui em vez de `./OrderedDataStore.luau`.

	Não-lançante -- devolve `(true)` se `value` é aceitável para `self`, ou `(false, mensagem)`
	caso contrário. QUALQUER `self` que não seja um `OrderedDataStore` (GlobalDataStore/DataStore)
	sempre aceita -- a restrição de "só inteiro" é EXCLUSIVA de OrderedDataStore (L2.1.3, despacho
	da tarefa). Mensagem na família Roblox (aproximação de boa-fé -- string exata não confirmada
	por fonte primária, mesma disciplina de `datastore/Value.luau`).
]]
local function checkIntegerForOrderedDataStore(self: Runtime.Instance, value: unknown): (boolean, string?)
	if self.ClassName ~= "OrderedDataStore" then
		return true, nil
	end

	if type(value) ~= "number" then
		return false, `OrderedDataStore values must be integers (got {type(value)})`
	end

	local numberValue = value :: number
	-- `numberValue ~= numberValue` detecta NaN; `math.huge`/`-math.huge` são não-finitos -- nenhum
	-- dos dois é um inteiro válido.
	if numberValue ~= numberValue or numberValue == math.huge or numberValue == -math.huge then
		return false, "OrderedDataStore values must be integers (got a non-finite number)"
	end

	if math.floor(numberValue) ~= numberValue then
		return false, `OrderedDataStore values must be integers (got {numberValue})`
	end

	return true, nil
end

-- Lançante -- nível 2, mesma convenção de `Value.AssertNameLength`/`Value.Validate` (chamados
-- diretamente de dentro de `SetAsync`, abaixo): culpa quem chamou esta função diretamente.
local function assertIntegerForOrderedDataStore(self: Runtime.Instance, value: unknown): ()
	local ok, message = checkIntegerForOrderedDataStore(self, value)
	if not ok then
		error(message, 2)
	end
end

-- Anotação explícita de `{ [string]: unknown }` -- mesmo padrão de `RunService.luau`/`Lighting.luau`.
local Methods: { [string]: unknown } = {
	-- Doc oficial: `GlobalDataStore:GetAsync(key, options?): Tuple` -- Yields. `(value, keyInfo)`;
	-- chave inexistente -> `(nil, nil)` (L2.1.3). `options` (`DataStoreGetOptions.UseCache`) é
	-- aceito e IGNORADO -- ver `DataStoreGetOptions.luau`/`generated/classes/DataStoreGetOptions.luau`
	-- e a justificativa completa em L2.1.3 (cache de 4s por servidor, inobservável num processo só).
	GetAsync = function(self: Runtime.Instance, key: string, _options: unknown?): (unknown, Runtime.Instance?)
		Value.AssertNameLength(key, "key")
		AsyncCall.Yield("GlobalDataStore:GetAsync")

		local value, versionInfo = store:Get(storeIdOf(self), key)
		return value, keyInfoOrNil(versionInfo)
	end,

	-- Doc oficial: `GlobalDataStore:SetAsync(key, value, userIds?, options?): Variant` -- Yields,
	-- devolve a STRING de versão da escrita (L2.1.3). Validação de `value` (serializável + tamanho)
	-- ANTES do Yield -- mesma disciplina de checagem síncrona de argumento antes da "chamada de
	-- rede" que o Roblox real também faria (erro de argumento não deveria depender de round-trip).
	SetAsync = function(self: Runtime.Instance, key: string, value: unknown, userIds: { number }?, options: unknown?): string
		Value.AssertNameLength(key, "key")
		Value.Validate(value)
		-- task-services-020: no-op para GlobalDataStore/DataStore -- só valida de verdade quando
		-- `self` é um OrderedDataStore (ver cabeçalho, "task-services-020").
		assertIntegerForOrderedDataStore(self, value)
		AsyncCall.Yield("GlobalDataStore:SetAsync")

		return store:Set(storeIdOf(self), key, value, userIds, extractMetadata(options))
	end,

	--[[
		Doc oficial: `GlobalDataStore:UpdateAsync(key, transformFunction): Tuple` -- Yields.
		`transformFunction` recebe `(oldValue, keyInfo)`, devolve `(newValue, userIds?, metadata?)`;
		`newValue == nil` ABORTA a escrita; retorno de `UpdateAsync` é `(newValue, newKeyInfo)`
		(L2.1.3). "The callback function cannot yield" (doc oficial, citação literal, L2.1.5) --
		detectado rodando a transform em `coroutine.create`+`coroutine.resume`: se a coroutine não
		ficar `dead` depois do resume, ela YIELDOU -- aborta a escrita (mesma semântica de "transform
		devolveu nil") e ERRA, DEPOIS de `store:Update` retornar, aqui mesmo em `Methods.UpdateAsync`
		(nível 2 aponta pro call site do script -- levantar o erro DENTRO do fechamento `wrapped`,
		vários frames mais fundo, exigiria contar a profundidade exata de `Store.Update`, frágil e
		acoplado à implementação dele; melhor: o fechamento só GRAVA um upvalue `yielded`/
		`yieldTraceback`, e quem de fato chama `error()` é este método, no nível certo).
	]]
	UpdateAsync = function(self: Runtime.Instance, key: string, transformFunction: unknown): (unknown, Runtime.Instance?)
		Value.AssertNameLength(key, "key")

		if type(transformFunction) ~= "function" then
			error(`invalid argument #2 to 'UpdateAsync' (function expected, got {type(transformFunction)})`, 2)
		end
		local userTransform = transformFunction :: (unknown, Runtime.Instance?) -> (unknown, { number }?, { [string]: unknown }?)

		AsyncCall.Yield("GlobalDataStore:UpdateAsync")

		local yielded = false
		local yieldTraceback: string? = nil
		-- task-services-020: só != nil quando `self` é OrderedDataStore E a transform devolveu um
		-- valor NÃO-nil que não é inteiro -- mesmo padrão de upvalue de `yielded`/`yieldTraceback`
		-- acima (o erro de verdade é levantado FORA deste fechamento, depois de `store:Update`
		-- retornar, ver o comentário do método, acima).
		local invalidIntegerMessage: string? = nil

		local wrapped: Store.Transform = function(oldValue: unknown, oldKeyInfo: Store.VersionInfo?): (unknown, { number }?, { [string]: unknown }?)
			local oldKeyInfoInstance = keyInfoOrNil(oldKeyInfo)

			-- Empacota os 3 retornos da transform num ÚNICO valor (`{unknown}`) para que
			-- `coroutine.resume` sempre devolva exatamente 2 valores (`ok`, `result`) -- mesma
			-- disciplina de 2 valores já usada em `src/runtime/Scheduler.luau` (`resumeThread`,
			-- `local ok, err = coroutine.resume(co, ...)`), evitando qualquer ambiguidade de
			-- tipagem de retorno variádico de `coroutine.resume` sobre uma função com múltiplos
			-- retornos.
			local co = coroutine.create(function(): { unknown }
				local newValue, newUserIds, newMetadata = userTransform(oldValue, oldKeyInfoInstance)
				return { newValue, newUserIds, newMetadata }
			end)

			local ok, result = coroutine.resume(co)

			if coroutine.status(co) ~= "dead" then
				-- Yieldou (ex.: `task.wait()` dentro da transform) -- PROIBIDO pela doc oficial.
				-- Aborta a escrita; o erro de verdade é levantado FORA deste fechamento (ver
				-- cabeçalho do método, acima).
				yielded = true
				yieldTraceback = debug.traceback(co)
				coroutine.close(co)
				return nil, nil, nil
			end

			if not ok then
				-- Erro de verdade DENTRO da transform do usuário (ela chamou `error()`/uma chamada
				-- que falhou) -- repassa TAL COMO VEIO, nível 0: `result` já é a mensagem
				-- inteiramente formatada (com posição, se a transform usou o nível default) --
				-- mesma disciplina de "repassar erro de pcall sem alterar" já usada em
				-- `AsyncCall.luau`/`Value.luau`.
				error(result, 0)
			end

			local packed = result :: { unknown }
			local newValue = packed[1]

			-- task-services-020: `newValue == nil` já é ABORTO normal de UpdateAsync (semântica de
			-- sempre, nenhuma mudança aqui) -- só valida quando a transform de fato quer ESCREVER um
			-- valor novo. Não-lançante (`checkIntegerForOrderedDataStore`) de propósito: lançar AQUI
			-- DENTRO do fechamento, vários frames dentro de `Store.Update`, teria o mesmo problema de
			-- nível de erro já documentado para `yielded`, acima -- por isso só GRAVA o upvalue e
			-- aborta a escrita; quem lança é `Methods.UpdateAsync`, depois de `store:Update` voltar.
			if newValue ~= nil then
				local ok2, message2 = checkIntegerForOrderedDataStore(self, newValue)
				if not ok2 then
					invalidIntegerMessage = message2
					return nil, nil, nil
				end
			end

			return newValue, packed[2] :: { number }?, packed[3] :: { [string]: unknown }?
		end

		local newValue, newVersionInfo = store:Update(storeIdOf(self), key, wrapped)

		if yielded then
			error(
				`The callback function cannot yield -- DataStoreService:UpdateAsync's transform function yielded (e.g. task.wait or another suspending call inside it); the Roblox engine does not support this and it would fail in production. [LuauBench] traceback at the point of yielding:\n{yieldTraceback or "?"}`,
				2
			)
		end

		if invalidIntegerMessage ~= nil then
			-- task-services-020: `self` é OrderedDataStore e a transform tentou escrever um valor
			-- não-inteiro -- a escrita já foi abortada dentro de `wrapped`, acima.
			error(invalidIntegerMessage, 2)
		end

		return newValue, keyInfoOrNil(newVersionInfo)
	end,

	-- Doc oficial: `GlobalDataStore:RemoveAsync(key): Tuple` -- Yields. `(valorAnterior, keyInfo)`
	-- de ANTES da remoção, `(nil, nil)` se já ausente/tombstoned (no-op idempotente) -- L2.1.3, via
	-- `Store.Remove` (tombstone, histórico preservado -- task-017).
	--
	-- task-services-020 (OrderedDataStore, "REMOÇÃO PERMANENTE"): esta função NÃO muda para
	-- OrderedDataStore -- continua criando um tombstone em `store` (via `Store.Remove`, task-017),
	-- igual a GlobalDataStore/DataStore. A permanência exigida pelo despacho da tarefa ("a remoção
	-- em OrderedDataStore é PERMANENTE, SEM tombstone -- diferente de GlobalDataStore/DataStore")
	-- é alcançada por CONSTRUÇÃO, sem precisar de um caminho de remoção real diferente:
	-- `OrderedDataStore` (Superclass = "GlobalDataStore" no dump) NUNCA ganha `GetVersionAsync`/
	-- `ListVersionsAsync` -- esses dois são membros de "DataStore" (ver `./DataStore.luau`,
	-- cabeçalho), fora da cadeia de superclasses de OrderedDataStore -- e `GetSortedAsync`
	-- (`./OrderedDataStore.luau`) só lê a versão CORRENTE de cada chave via `store:Get`, que já
	-- trata tombstone como ausente. Resultado observável por QUALQUER script: uma vez removida, a
	-- chave NUNCA MAIS aparece em `GetAsync`/`IncrementAsync`/`GetSortedAsync` de um
	-- OrderedDataStore, e não existe NENHUM método alcançável nesta classe capaz de ler o
	-- tombstone de volta -- ou seja, permanente, sem exigir um "hard delete" real dentro de
	-- `datastore/Store.luau`. Documentado aqui (em vez de reescrever `Store.luau`, fora do
	-- território desta tarefa) por ser a decisão mais simples que satisfaz o acceptance sem tocar
	-- um módulo compartilhado por toda a família DataStore.
	RemoveAsync = function(self: Runtime.Instance, key: string): (unknown, Runtime.Instance?)
		Value.AssertNameLength(key, "key")
		AsyncCall.Yield("GlobalDataStore:RemoveAsync")

		local previousValue, previousVersionInfo = store:Remove(storeIdOf(self), key)
		return previousValue, keyInfoOrNil(previousVersionInfo)
	end,

	--[[
		Doc oficial: `GlobalDataStore:IncrementAsync(key, delta = 1, userIds?, options?): Variant`
		-- Yields, devolve o valor JÁ incrementado (L2.1.3). Chave inexistente parte de 0 (mesma
		convenção do Roblox real: a primeira chamada "cria" a chave). Erra se o valor corrente NÃO
		é número -- via a mesma disciplina de upvalue de `UpdateAsync` acima (a transform interna é
		ESCRITA POR NÓS, nunca pelo script -- não precisa da checagem de yield de `UpdateAsync`,
		só precisa poder erguer o erro de "não é número" no NÍVEL CERTO, apontando pro call site do
		script, não pra linha interna de `Store.Update`).

		task-services-020: quando `self` é um OrderedDataStore, o RESULTADO `base + actualDelta`
		(não `actualDelta` isolado -- um delta fracionário sobre uma base inteira ainda pode, em
		tese, resultar num inteiro, embora seja um caso raro) também passa por
		`checkIntegerForOrderedDataStore`, mesmo padrão de upvalue não-lançante de `notANumber`.
	]]
	IncrementAsync = function(self: Runtime.Instance, key: string, delta: number?, userIds: { number }?, options: unknown?): (unknown, Runtime.Instance?)
		Value.AssertNameLength(key, "key")
		local actualDelta = if delta ~= nil then delta else 1

		AsyncCall.Yield("GlobalDataStore:IncrementAsync")

		local notANumber = false
		local invalidIntegerMessage: string? = nil

		local newValue, newVersionInfo = store:Update(storeIdOf(self), key, function(oldValue: unknown, _oldKeyInfo: Store.VersionInfo?): (unknown, { number }?, { [string]: unknown }?)
			local base: number
			if oldValue == nil then
				base = 0
			elseif type(oldValue) == "number" then
				base = oldValue :: number
			else
				notANumber = true
				return nil, nil, nil -- aborta -- erro real levantado abaixo, fora da transform
			end

			local computed = base + actualDelta
			local ok, message = checkIntegerForOrderedDataStore(self, computed)
			if not ok then
				invalidIntegerMessage = message
				return nil, nil, nil -- aborta -- erro real levantado abaixo, fora da transform
			end

			return computed, userIds, extractMetadata(options)
		end)

		if notANumber then
			-- Aproximação de boa-fé, família Roblox -- string exata NÃO CONFIRMADA (mesma
			-- disciplina de datastore/Value.luau e DataStoreSetOptions.luau para casos análogos).
			error(`{key} is not a number and cannot be incremented`, 2)
		end

		if invalidIntegerMessage ~= nil then
			error(invalidIntegerMessage, 2)
		end

		return newValue, keyInfoOrNil(newVersionInfo)
	end,
}

-- Módulo devolve `{ Methods, StoreIdState, Store, StoreIdOf, KeyInfoOrNil }` -- MAIS do que
-- `Types.Behavior` declara, mesmo padrão e mesma razão de `./DataStoreKeyInfo.luau` (ver o
-- comentário lá): `behavior/Index.luau` faz `require("./GlobalDataStore") :: Types.Behavior`
-- (downcast seguro), `./DataStoreService.luau` faz `require("./GlobalDataStore")` sem cast para
-- alcançar `.StoreIdState`.
--
-- `Store`/`StoreIdOf`/`KeyInfoOrNil` ACRESCENTADOS em task-services-019 (sub-leva B:
-- `GetVersionAsync`/`ListVersionsAsync`/`ListKeysAsync`, ver `./DataStore.luau`) -- ÚNICA mudança
-- deste arquivo nessa tarefa (o resto acima é o já aprovado por task-018, intocado). Necessário
-- porque `./DataStore.luau` precisa do MESMO `store` singleton (nunca um segundo `Store.new()` --
-- ver cabeçalho, "STORE ÚNICO, MÓDULO-LOCAL": um segundo store seria invisível para
-- `GetAsync`/`SetAsync`, quebrando a premissa "escreva com SetAsync, leia versão antiga com
-- GetVersionAsync") e da MESMA disciplina de resolução de `_LuauBenchStoreId`/construção de
-- `DataStoreKeyInfo` que este módulo já usa -- nunca uma segunda cópia dessas duas funções que
-- pudesse divergir (ex.: uma mensagem de erro de engenharia diferente para o mesmo caso).
return {
	Methods = Methods,
	StoreIdState = StoreIdState,
	Store = store,
	StoreIdOf = storeIdOf,
	KeyInfoOrNil = keyInfoOrNil,
}
