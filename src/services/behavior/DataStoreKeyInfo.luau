--!strict

--[[
	Behavior de `DataStoreKeyInfo` -- task-services-018. LER
	.claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.1.3"/"L2.1.6", ANTES de mexer aqui.

	`DataStoreKeyInfo` NUNCA nasce via `Instance.new`/`Services.new` (é `NotCreatable` no dump, ver
	`generated/classes/DataStoreKeyInfo.luau`) -- só via a fábrica `New`, exportada abaixo, chamada
	por `./GlobalDataStore.luau` toda vez que `GetAsync`/`SetAsync`/`UpdateAsync`/`RemoveAsync`
	devolve um `Store.VersionInfo` não-nil (L2.0.3, chamador #3 da lista fechada de
	`ClassRegistry.NewEngineInstance`: "services, dentro de um Behavior.Methods, para construir um
	objeto do motor que o método real DEVOLVE e que não é filho de ninguém").

	`New` NÃO faz parte do contrato `Types.Behavior` (que só conhece `Methods`/`Initialize`) --
	fica exportada ao lado de `Methods` no mesmo módulo, e `./GlobalDataStore.luau` alcança as duas
	com um `require("./DataStoreKeyInfo")` direto (intra-`behavior`, nunca via `behavior/Index.luau`,
	que só enxerga o par Methods/Initialize ao montar `BehaviorIndex`).

	CreatedTime/UpdatedTime/Version SÃO propriedades do schema gerado (`ReadOnly = true`, `Default =
	nil` -- ver `generated/classes/DataStoreKeyInfo.luau`), logo esta instância é ESTRITA
	(`ClassRegistry.NewEngineInstance` sempre chama `Instance.SetClassSchema`, mesmo para um schema
	só com 3 entradas -- confirmado lendo `src/runtime/ClassRegistry.luau`/`resolveClassSchema`:
	`hasAny` fica `true` porque `Generated.Schema` é uma tabela não-nil, ainda que kilo-vazia em
	outras classes desta leva). Escritos via `Runtime.Instance.SetPropertyRaw` -- a via de
	engenharia que NUNCA consulta o schema (Decisão 6, item 2) e por isso ignora o `ReadOnly = true`
	declarado ali; o enforcement de ESCRITA normal do script continua vindo do próprio schema
	(`ClassSchema.ReadOnly` já bloqueia `keyInfo.CreatedTime = x` na via comum de `__newindex`,
	passo 7 -- ver `src/runtime/Instance.luau`).

	DECISÃO REGISTRADA (diverge do texto originalmente sugerido para esta task, que citava
	`Instance.SetReadOnlyRawProperties` por analogia com `DataModel.JobId`/`PlaceId`):
	`SetReadOnlyRawProperties` NÃO é acessível daqui -- `src/runtime/init.luau` só reexporta
	`GetPropertyRaw`/`SetPropertyRaw` em `Runtime.Instance` (confirmado por leitura direta de
	`src/runtime/init.luau`, 2026-09-05: "Só GetPropertyRaw/SetPropertyRaw -- NewBase/SetClassChain/
	SetClassMethods/SetClassSchema ficam de fora"). Além disso, o próprio cabeçalho de
	`Instance.SetReadOnlyRawProperties` (Instance.luau, task-runtime-034) limita seu uso a instância
	LENIENTE ("ESCOPO EXPLICITAMENTE LIMITADO A INSTÂNCIA LENIENTE... `DataModel` é o único
	consumidor hoje e nunca terá `ClassSchema` instalado") -- `DataStoreKeyInfo` É estrita (parágrafo
	acima), então mesmo se a função fosse exportada aqui, usá-la seria incorreto (uma chave gravada
	por ela mas ausente do schema ficaria inacessível em LEITURA, o que não é o caso: as 3 chaves
	JÁ estão no schema). `SetPropertyRaw` é o mecanismo certo -- e é exatamente o que `RunService.luau`
	já usa para sobrescrever `Heartbeat`/`Stepped` (também `ReadOnly` só implicitamente, via serem
	Event) e o que `Lighting.luau` usa para reescrever `ClockTime`/`TimeOfDay`.

	Metadata/UserIds NÃO são propriedades do schema (a doc real também só os expõe via
	`GetMetadata()`/`GetUserIds()`, nunca como campo legível por ponto) -- estado privado por
	instância (L2.0.2), guardado via `InstanceState`. `versionInfo.Metadata`/`versionInfo.UserIds`
	JÁ chegam deep-copiados por `../datastore/Store.luau` (`toVersionInfo`) -- guardados como estão;
	a cópia defensiva de SAÍDA acontece em `Methods.GetMetadata`/`GetUserIds`, na LEITURA (mesma
	razão de `Value.luau`, cabeçalho, "DEEP COPY": sem isso, mutar o retorno de `GetMetadata()`
	alteraria o estado privado desta instância entre chamadas -- um alias silencioso).
]]

local Runtime = require("../../runtime")
local InstanceState = require("../InstanceState")
local Value = require("../datastore/Value")
local Store = require("../datastore/Store")

local MetadataState = InstanceState.new("_LuauBenchMetadata") :: InstanceState.InstanceStateAccessor<{ [string]: unknown }>
local UserIdsState = InstanceState.new("_LuauBenchUserIds") :: InstanceState.InstanceStateAccessor<{ number }>

-- Anotação explícita de `{ [string]: unknown }` necessária para o literal de tabela com campos
-- de função concreta ser aceito onde `Types.Behavior.Methods` espera um mapa indexado por string,
-- não um record "sealed" -- mesmo padrão já usado em `RunService.luau`/`Lighting.luau`.
local Methods: { [string]: unknown } = {
	-- Doc oficial: `DataStoreKeyInfo:GetMetadata(): Dictionary`. Nunca `nil` -- uma chave nunca
	-- escrita por `New` (não deveria acontecer -- todo `New` seta as duas) devolve `{}`.
	GetMetadata = function(self: Runtime.Instance): { [string]: unknown }
		local metadata = MetadataState.Get(self)
		if metadata == nil then
			return {}
		end
		return Value.DeepCopy(metadata)
	end,

	-- Doc oficial: `DataStoreKeyInfo:GetUserIds(): Array`. Mesma disciplina de GetMetadata acima.
	GetUserIds = function(self: Runtime.Instance): { number }
		local userIds = UserIdsState.Get(self)
		if userIds == nil then
			return {}
		end
		return Value.DeepCopy(userIds)
	end,
}

-- Fábrica interna (ver cabeçalho) -- consumida só por `./GlobalDataStore.luau`.
local function new(versionInfo: Store.VersionInfo): Runtime.Instance
	local instance = Runtime.ClassRegistry.NewEngineInstance("DataStoreKeyInfo")

	Runtime.Instance.SetPropertyRaw(instance, "CreatedTime", versionInfo.CreatedTime)
	Runtime.Instance.SetPropertyRaw(instance, "UpdatedTime", versionInfo.UpdatedTime)
	Runtime.Instance.SetPropertyRaw(instance, "Version", versionInfo.Version)

	MetadataState.Set(instance, versionInfo.Metadata)
	UserIdsState.Set(instance, versionInfo.UserIds)

	return instance
end

-- Módulo devolve `{ Methods, New }` -- MAIS do que `Types.Behavior` declara (só `Methods`/
-- `Initialize`), de propósito: `behavior/Index.luau` faz `require("./DataStoreKeyInfo") ::
-- Types.Behavior` (downcast seguro -- campo extra `New` é ignorado por quem só enxerga o tipo
-- Behavior), enquanto `./GlobalDataStore.luau` faz `require("./DataStoreKeyInfo")` sem cast, para
-- alcançar `.New` (o tipo natural, mais largo, inferido aqui, sem anotação `Types.Behavior` que
-- rejeitaria o campo extra por excesso de propriedade num literal).
return {
	Methods = Methods,
	New = new,
}
