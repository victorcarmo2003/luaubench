--!strict

--[[
	Superfície PÚBLICA ÚNICA do território `valuetypes` (task-valuetypes-007). Desenho completo em
	.claude/agents-memory/arquiteto-valuetypes-2026-09-05.md, seção 3.1 ("init.luau -- superfície
	pública única").

	`services`/`cli` fazem `require("../valuetypes")` -- NUNCA `require("../valuetypes/types/
	Vector3")` nem qualquer outro módulo interno (`Float32`, `Userdata`, `types/*`,
	`generated/*` são todos privados deste território). Mesmo contrato que `runtime`/`services` já
	têm entre si (regra 06).

	## NOTA DE TIPAGEM OBRIGATÓRIA (D4 -- divergência declarada, seção 3.1 do desenho)

	O valor em runtime de TODO value type deste território é `userdata` de verdade (`newproxy(true)`
	via `Userdata.Define`, ver `Userdata.luau`) -- e o Luau NÃO deixa declarar campo em `userdata`.
	Por isso, `export type Vector3`/`CFrame`/`Color3`/`UDim`/`UDim2`/`Enum`/`EnumItem`/`Enums`
	abaixo são tipos NOMINAIS OPACOS: cada `types/*.luau` já os declara como
	`typeof(setmetatable({} :: { ...campos... }, { ...metamétodos... }))` (uma "vitrine" estática
	só pra dar assinatura tipada entre módulos) e este arquivo só REEXPORTA essa mesma vitrine, sem
	adicionar nem afrouxar nada. Quem checa de verdade em RUNTIME é `Userdata.luau:sharedIndex`
	(via `GetProperty`/`Methods` do `Descriptor` de cada tipo) -- o Luau não valida `v.Foo` em
	tempo de ANÁLISE contra o dono real de `v`, só contra a vitrine.

	Consequência prática (divergência com o Roblox real, documentada aqui e nunca escondida): no
	Studio, o `luau-lsp` conhece `Vector3` nativamente e acusa `Vector3.new(1,2,3).Nope` ANTES de
	rodar o script; aqui, o mesmo erro só aparece em RUNTIME, via `__index`
	("Nope is not a valid member of Vector3"). Corrigir isso exigiria emitir definições de tipo
	Luau (`.d.luau`) pro `luau-lsp` do usuário -- um sistema próprio, explicitamente FORA de escopo
	(desenho §10, item 2: "Não emitir definições de tipo Luau para o luau-lsp do usuário"). Não é
	uma tarefa esquecida -- é uma decisão já tomada pelo arquiteto.

	## Bridge com `runtime` (Decisão 4 do desenho, task-runtime-032 -- território VIZINHO, não este)

	`ValueTypes.TypeNameOf` alimenta `Runtime.TypeNameResolver.Set(ValueTypes.TypeNameOf)` -- quem
	faz essa injeção é `cli` (composition root, task futura `task-cli-025`), NUNCA este módulo nem
	`runtime` diretamente (regra 06: "`src/runtime/**` nunca contém a string 'valuetypes'" -- a
	ponte é sempre um resolvedor injetado de FORA). `init.luau` só PRODUZ a função; não faz
	`require("../runtime")` em lugar nenhum deste arquivo.

	Depende de: `Float32` (indiretamente, via `types/*`), `Userdata`, `Catalog`, `Decode`,
	`types/{Vector3,Vector2,CFrame,Color3,UDim,UDim2,Enum}`. Nenhuma dependência de `runtime`/
	`services`/`cli` (leva 1 -- módulo-folha do território, ver desenho §2). Usado por: `services`/
	`cli` (`require("../valuetypes")`, tarefas futuras `task-services-015`/`task-cli-025`).

	## GOTCHA DO LUNE (confirmado empiricamente nesta tarefa, mesmo já documentado em
	## `src/runtime/init.luau`/`src/services/init.luau`/`src/cli/init.luau` -- reproduzido aqui,
	## não repetido por suposição)

	Quando este arquivo é carregado pela forma "estilo diretório" (`require("../valuetypes")` de
	fora, `require("./")` de um irmão dentro do próprio `src/valuetypes/`), o Lune identifica o
	chunk pelo caminho do PRÓPRIO DIRETÓRIO (`src/valuetypes`), não por `src/valuetypes/init`. Isso
	desloca a base de resolução dos `require` relativos DENTRO deste arquivo em um nível:
	`require("./Userdata")` aqui resolveria para `src/Userdata` (o diretório `src`, não
	`src/valuetypes/Userdata`) -- confirmado rodando `lune run` isolado sobre `init.spec.luau` antes
	desta correção (erro real: `"could not resolve child component 'Userdata'"`). Por isso todo
	`require` abaixo usa `./valuetypes/Xxx` em vez de `./Xxx`: é o caminho que, combinado com a
	base deslocada acima, aponta de volta pro arquivo certo (`src/valuetypes/Xxx`). Nenhum outro
	módulo de `src/valuetypes/` precisa deste ajuste -- o gotcha é específico de arquivos
	literalmente chamados `init.luau` carregados no estilo diretório; `Decode.luau`/`Catalog.luau`/
	`types/*.luau` têm identidade de chunk normal e resolvem `./Vizinho` do jeito óbvio (os
	specs deles já confirmam isso).
]]

local Userdata = require("./valuetypes/Userdata")
local Catalog = require("./valuetypes/Catalog")
local Decode = require("./valuetypes/Decode")

local Vector3Module = require("./valuetypes/types/Vector3")
local Vector2Module = require("./valuetypes/types/Vector2")
local Color3Module = require("./valuetypes/types/Color3")
local UDimModule = require("./valuetypes/types/UDim")
local UDim2Module = require("./valuetypes/types/UDim2")
local CFrameModule = require("./valuetypes/types/CFrame")
local EnumModule = require("./valuetypes/types/Enum")

-- ================================================================================================
-- Tipos reexportados -- ver "NOTA DE TIPAGEM OBRIGATÓRIA" acima. Cada um é a MESMA vitrine opaca
-- já declarada no módulo dono; este arquivo não redefine nenhuma.
-- ================================================================================================

export type Vector3 = Vector3Module.Vector3
export type Vector2 = Vector2Module.Vector2
export type Color3 = Color3Module.Color3
export type UDim = UDimModule.UDim
export type UDim2 = UDim2Module.UDim2
export type CFrame = CFrameModule.CFrame
export type Enum = EnumModule.Enum
export type EnumItem = EnumModule.EnumItem
export type Enums = EnumModule.Enums

export type CatalogEntry = Catalog.CatalogEntry
export type DecodeSuccess = Decode.DecodeSuccess
export type DecodeFailure = Decode.DecodeFailure
export type DecodeResult = Decode.DecodeResult

local ValueTypes = {}

ValueTypes.Vector3 = Vector3Module
ValueTypes.Vector2 = Vector2Module
ValueTypes.Color3 = Color3Module
ValueTypes.UDim = UDimModule
ValueTypes.UDim2 = UDim2Module
ValueTypes.CFrame = CFrameModule
-- O global `Enum` do Roblox real É o objeto "Enums" raiz (confusão de nomenclatura do próprio
-- Roblox, ver types/Enum.luau) -- `require("./types/Enum")` já devolve esse objeto diretamente,
-- não uma tabela com `.new`/etc (Enum não tem construtor, é um namespace navegável).
ValueTypes.Enum = EnumModule

ValueTypes.Decode = Decode
ValueTypes.Catalog = Catalog

-- Registro data-driven nome -> construtor, usado por `BuildGlobals` abaixo. Deliberadamente
-- SEPARADO de `Catalog.SimulatedNames()` (que é a fonte da VERDADE sobre quais nomes são
-- "Simulated = true") -- este registro é só "ONDE está o construtor de cada um", e
-- `BuildGlobals` cruza os dois e ERRA ALTO E CEDO se um nome marcado Simulated=true no Catalog
-- não tiver entrada aqui (bug de sincronização entre os dois arquivos, nunca um global faltando
-- silenciosamente -- mesma disciplina de `Userdata.Define` contra TypeName duplicado e do guard
-- de nome duplicado em `Catalog.luau`).
local CONSTRUCTOR_BY_NAME: { [string]: unknown } = {
	Vector3 = Vector3Module,
	Vector2 = Vector2Module,
	Color3 = Color3Module,
	UDim = UDimModule,
	UDim2 = UDim2Module,
	CFrame = CFrameModule,
	Enum = EnumModule,
}

-- Tabela NOVA a cada chamada (mesmo contrato de `UnsimulatedGlobals.Build()`, que `cli` já usa
-- pro mesmo fim) -- `ScriptEnvironment.Build` (cli, task futura) sobrepõe isto por cima de
-- `UnsimulatedGlobals.Build()` pra montar o `env` de um script; se duas chamadas compartilhassem a
-- mesma tabela, um script poderia mutar o global de OUTRO script/run através dela.
function ValueTypes.BuildGlobals(): { [string]: unknown }
	local globals: { [string]: unknown } = {}
	for _, name in Catalog.SimulatedNames() do
		local constructor = CONSTRUCTOR_BY_NAME[name]
		if constructor == nil then
			error(
				`ValueTypes.BuildGlobals: '{name}' está Simulated=true em Catalog.luau mas init.luau não tem um construtor registrado (CONSTRUCTOR_BY_NAME) -- bug de sincronização entre Catalog.luau e init.luau`,
				2
			)
		end
		globals[name] = constructor
	end
	return globals
end

-- Bridge com `runtime` -- ver cabeçalho, "Bridge com runtime". Delega inteiramente pra
-- `Userdata.TypeNameOf` (a única fonte de verdade de "este valor é um value type nosso, e qual
-- TypeName ele tem") -- não reimplementa a lógica aqui.
function ValueTypes.TypeNameOf(value: unknown): string?
	return Userdata.TypeNameOf(value)
end

return ValueTypes
