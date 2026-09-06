--!strict

--[[
	Behavior de `DataStoreOptions` -- task-services-018. LER
	.claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.1.3", ANTES de mexer aqui.

	`AllScopes` já é uma propriedade GRAVÁVEL comum do schema gerado (`Kind = "Property", Default =
	false, ReadOnly = false` -- ver `generated/classes/DataStoreOptions.luau`) -- não precisa de
	nenhum código aqui, o runtime já cobre leitura/escrita sozinho.

	`SetExperimentalFeatures({v2 = true})` -- o ÚNICO método desta classe -- é aceito e IGNORADO
	(no-op) DE PROPÓSITO: o `ProfileStore` (a lib que define o caso de uso central do projeto,
	CLAUDE.md) chama isto SEMPRE, incondicionalmente, no seu bootstrap -- errar aqui derrubaria a
	lib inteira no primeiro `GetDataStore`. Não há "v2" simulado nesta leva (nem geral -- `services`
	não distingue "features experimentais" de DataStore de nenhuma forma), então não implementar é
	o comportamento fiel possível: aceitar a chamada sem fingir que alguma feature mudou.
]]

local Runtime = require("../../runtime")

-- Anotação explícita de `{ [string]: unknown }` -- mesmo padrão de `RunService.luau`/`Lighting.luau`.
local Methods: { [string]: unknown } = {
	SetExperimentalFeatures = function(_self: Runtime.Instance, _experimentalFeatures: unknown): ()
		-- no-op deliberado -- ver cabeçalho.
	end,
}

local DataStoreOptionsBehavior = {
	Methods = Methods,
}

return DataStoreOptionsBehavior
