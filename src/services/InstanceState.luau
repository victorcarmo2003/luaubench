--!strict

--[[
	Estado privado por instância para `services` guardar informação que o script do usuário NUNCA
	deve enxergar como propriedade -- ex.: qual store lógico um `DataStore` endereça, o cursor de
	um `Pages`, o alvo/alpha corrente de um `Tween`, o metadata de um `DataStoreKeyInfo`. Extensão
	do LuauBench, portanto FORA do namespace simulado de qualquer classe real (regra 00) -- vive em
	módulo próprio, ao lado de AsyncCall.luau/Context.luau/RejectingSignal.luau. Ver
	.claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.0.2 -- Estado privado de
	`services`: propriedade raw fora do schema", desenho completo.

	MECANISMO: `InstanceMeta.__index`/`__newindex` (src/runtime/Instance.luau), no MODO ESTRITO
	(instância com `ClassSchema` instalado), só enxergam uma chave se `classSchema[key] ~= nil` --
	caso contrário caem no fallback de "membro/filho" e terminam no erro real do Roblox ("X is not
	a valid member of Y"). Uma chave que nunca entra em NENHUM `ClassSchema` é, por construção,
	INALCANÇÁVEL por qualquer acesso normal de propriedade do script (`instance.Foo`) -- só
	alcançável pela via de engenharia `Runtime.Instance.GetPropertyRaw`/`SetPropertyRaw`, que
	NUNCA consulta o schema (Decisão 6, item 2, do desenho de `services`). É o MESMO canal que
	`cli` já usa para `Script.Source` (fora do schema por `Capabilities.Read == ["PluginOrOpenCloud"]`,
	A.4); esta leva o generaliza e o NOMEIA, porque quatro classes precisam dele nesta leva 2:
	`DataStore`/`OrderedDataStore`, `Pages`, `DataStoreKeyInfo`, `Tween`.

	REGRA DURA, cobrável em revisão: toda chave usada por `InstanceState.new` começa com
	`_LuauBench` -- garante colisão zero com qualquer nome de membro que uma versão futura do dump
	venha a introduzir naquela classe (o único jeito de este canal virar um bug silencioso).
	Validado no PRÓPRIO `.new`, na hora da chamada -- errar aqui é erro de ENGENHARIA INTERNA (quem
	chama `InstanceState.new` é sempre outro módulo de `services`, escrito à mão, nunca o script do
	usuário), por isso em português (mesma "regra de idioma dos erros" de `ClassBuilder.luau`).

	NÃO é para Service SINGLETON (`DataStoreService`/`HttpService`/`MessagingService`/
	`PhysicsService`/`SoundService`): esses guardam estado em `local` de módulo do próprio
	`behavior/<X>.luau` -- um Service tem exatamente uma instância por processo, então não há
	"por instância" a distinguir ali (ver L2.0.2, último parágrafo, e o gatilho registrado sobre
	um futuro watch mode que reinicie o `DataModel` sem reiniciar o processo).

	Consumidores previstos por tarefas futuras: DataStore/OrderedDataStore, Pages,
	DataStoreKeyInfo, WorldRoot, Tween -- esta tarefa só constrói o mecanismo genérico, não o usa.

	Depende só de `../runtime` (`GetPropertyRaw`/`SetPropertyRaw`). Nenhum estado próprio de
	módulo -- `InstanceState.new(key)` é só uma fábrica de fechamentos fechados sobre `key`.
]]

local Runtime = require("../runtime")

local InstanceState = {}

-- Prefixo obrigatório de toda chave (ver cabeçalho, "REGRA DURA").
local REQUIRED_PREFIX = "_LuauBench"

-- Par Get/Set tipado que `InstanceState.new` devolve. `Get` é sempre `T?` -- uma instância recém
-- criada nunca teve `Set` chamado para esta chave (SetClassSchema nunca semeia default aqui,
-- porque esta chave nunca está em nenhum ClassSchema -- ver cabeçalho, "MECANISMO").
export type InstanceStateAccessor<T> = {
	Get: (instance: Runtime.Instance) -> T?,
	Set: (instance: Runtime.Instance, value: T) -> (),
}

-- `key` nunca vem de um script do usuário -- vem sempre de outro módulo de `services`, escrito à
-- mão, escolhendo o nome da chave privada (ex.: `InstanceState.new("_LuauBenchStoreId")` dentro de
-- `behavior/DataStore.luau`). Por isso o erro abaixo é em português (engenharia interna), mesma
-- convenção de `ClassBuilder.luau`/`Context.luau`.
function InstanceState.new<T>(key: string): InstanceStateAccessor<T>
	if string.sub(key, 1, string.len(REQUIRED_PREFIX)) ~= REQUIRED_PREFIX then
		error(
			`InstanceState.new: a chave '{key}' precisa começar com '{REQUIRED_PREFIX}' -- regra dura de L2.0.2 (arquiteto-services-2026-09-05.md), garante colisão zero com membro futuro do Roblox API Dump`,
			2
		)
	end

	local self: InstanceStateAccessor<T> = {
		Get = function(instance: Runtime.Instance): T?
			return Runtime.Instance.GetPropertyRaw(instance, key) :: T?
		end,

		Set = function(instance: Runtime.Instance, value: T): ()
			Runtime.Instance.SetPropertyRaw(instance, key, value)
		end,
	}
	return self
end

return InstanceState
