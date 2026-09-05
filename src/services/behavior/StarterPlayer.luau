--!strict

--[[
	Behavior de `StarterPlayer` -- retomada de task-services-003 depois de `task-runtime-023`
	destravar `Runtime.ClassRegistry.NewEngineInstance`. Ver
	.claude/agents-memory/arquiteto-runtime-2026-09-04.md, seção "Revisão pós-integração
	2026-09-05 (4) -- `NotCreatable` vs. abstrata: dois construtores em `ClassRegistry`", e o
	cabeçalho de `src/runtime/ClassRegistry.luau` (lista fechada de chamadores legítimos de
	`NewEngineInstance` -- este módulo é o chamador #2 dessa lista).

	task-services-010 (arquiteto-cli-2026-09-05.md, "Revisão pós-implementação 2026-09-05
	(task-cli-015)", subseção "Módulos" -> "src/services/behavior/StarterPlayer.luau"): a FONTE da
	informação de QUAIS filhos fixos existem e em que ORDEM deixou de estar escrita à mão aqui e
	passou a ser `../EngineFixedChildren.luau` (`EngineFixedChildren.Of("StarterPlayer")`) -- este
	módulo passou de FONTE a CONSUMIDOR dessa lista. Continua sendo o chamador #2 da lista fechada
	de `NewEngineInstance` (nada muda no contrato com `runtime`).

	`StarterPlayer` é `Service` (`IsService = true`) e `NotCreatable` (`IsAbstract = true`) no
	dump -- alcançável só por `game:GetService("StarterPlayer")` (que constrói o singleton via
	`Runtime.ClassRegistry.NewEngineInstance`, dentro de `src/runtime/DataModel.luau`). No Roblox
	real, `StarterPlayer` já nasce com dois filhos fixos: `StarterPlayerScripts` e
	`StarterCharacterScripts` -- ambos `NotCreatable` E `IsService = false` (confirmado em
	`src/services/generated/classes/StarterPlayerScripts.luau` e `.../StarterCharacterScripts.luau`
	-- ver task-services-002), logo INALCANÇÁVEIS por `game:GetService(...)` (que exige
	`IsService == true`) OU por um `Instance.new`/`Services.new` comum (que exige
	`IsAbstract == false`). O ÚNICO jeito de o LuauBench os criar é a via do motor
	(`NewEngineInstance`), exatamente como o Roblox real: o motor cria os dois quando o
	`StarterPlayer` nasce, nunca um script.

	Este `Initialize` roda DEPOIS de a instância de `StarterPlayer` já estar com a cadeia de
	classes, os métodos e o schema aplicados (`Runtime.ClassRegistry.NewEngineInstance` garante essa
	ordem -- ver o comentário dela) e ANTES de `DataModel.GetService` parentear `StarterPlayer` sob
	`game` -- mas isso não importa aqui: o contrato do campo `Initialize`
	(`src/runtime/ClassRegistry.luau`, comentário do campo) é claro que ele "só configura: não
	cria, não devolve nada" e NUNCA mexe no `Parent` da própria instância recebida -- só no dos
	filhos que ele mesmo cria, setando `Parent` para `instance` (o próprio `StarterPlayer`). Quem
	decide o `Parent` de `StarterPlayer` é `DataModel.GetService`, de fora.

	Nenhum `Methods`/comportamento além disso -- `StarterPlayer` não tem `MethodNames` no dump
	(confirmado em `generated/classes/StarterPlayer.luau`: `MethodNames = {}`), então este Behavior
	só precisa do `Initialize`.
]]

local Runtime = require("../../runtime")
local Types = require("../Types")
local EngineFixedChildren = require("../EngineFixedChildren")

local StarterPlayer: Types.Behavior = {
	Initialize = function(instance: Runtime.Instance): ()
		-- Ordem do array de `EngineFixedChildren.Of` É a ordem de criação (espelha a ordem usual
		-- do Explorer do Studio -- não confirmada como uma garantia formal do Roblox real, nenhuma
		-- fonte encontrada que documente ordem de filhos fixos como parte da API, mas é uma escolha
		-- estável e sem efeito observável: nenhum dos dois tem Schema/Behavior que dependa de ordem
		-- de irmãos). `child.Name` é passado EXPLICITAMENTE a `NewEngineInstance` -- sem isso, o
		-- campo `Name` de `EngineFixedChild` viraria decorativo (o `Default` de `NewEngineInstance`
		-- sem `name` explícito é `Name == ClassName`, que coincide com as duas entradas atuais só
		-- por acidente).
		for _, child in EngineFixedChildren.Of("StarterPlayer") do
			local created = Runtime.ClassRegistry.NewEngineInstance(child.ClassName, child.Name)
			created.Parent = instance
		end
	end,
}

return StarterPlayer
