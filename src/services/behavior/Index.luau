--!strict

--[[
	Mapa `ClassName -> Behavior`, escrito À MÃO de propósito (não gerado -- o gerador nunca deve
	poder apagar esta lista curada). Ver .claude/agents-memory/arquiteto-services-2026-09-05.md,
	seção "Módulos" -> "src/services/behavior/Index.luau": "É a lista curada do que tem
	comportamento, e o gerador nunca deve poder apagá-la."

	task-services-003 (primeira leva de classes reais: contêineres da árvore Rojo + Scripts +
	Workspace + Lighting) — LER .claude/agents-memory/arquiteto-services-2026-09-05.md, "Decisão 5"
	antes de mexer aqui.

	A imensa maioria das 24 classes desta leva é contêiner puro (ReplicatedStorage tem
	`Members == []` no dump, por exemplo) e legitimamente dispensa `Behavior` — `ClassBuilder.Build`
	já cobre todo `MethodNames` sem implementação com o stub `[LuauBench] ... not simulated by
	LuauBench yet` (regra 03: nunca stub silencioso). Isso é o esperado, não uma lacuna desta
	tarefa.

	`StarterPlayer` é a ÚNICA classe desta leva com `Behavior` de verdade: `Initialize` cria os
	filhos fixos `StarterPlayerScripts`/`StarterCharacterScripts` (ver `./StarterPlayer.luau`).

	HISTÓRICO (retomada de task-services-003): na primeira passada desta tarefa, este mapa ficou
	vazio e `StarterPlayer` não pôde ser escrito -- `Runtime.ClassRegistry.new`, o ÚNICO criador de
	instância que `services` tinha acesso, rejeitava `IsAbstract == true` INCONDICIONALMENTE, e
	`StarterPlayer`/`StarterPlayerScripts`/`StarterCharacterScripts` são todas `NotCreatable` no
	dump (fiel ao Roblox real, onde também não dá para `Instance.new("StarterPlayer")`). Isso
	bloqueava tanto `game:GetService("StarterPlayer")` quanto a criação dos filhos fixos por
	QUALQUER caminho, tornando um `Initialize` aqui código morto e intestável (regra 01: teste na
	MESMA tarefa da lógica que cobre). `task-runtime-023` resolveu o bloqueio separando a política
	de "script não pode `Instance.new` isto" (que continua em `ClassRegistry.new`, a via pública) da
	construção do motor (`ClassRegistry.NewEngineInstance`, nova via SEM essa guarda, usada por
	`DataModel.GetService` e -- agora -- por `./StarterPlayer.luau`). Ver
	.claude/agents-memory/arquiteto-runtime-2026-09-04.md, seção "Revisão pós-integração 2026-09-05
	(4)", para o desenho completo do fix.

	Todas as outras 23 classes desta leva continuam registradas por `Services.Register()` (ver
	../init.luau) SEM Behavior — contêiner puro, nenhuma precisa de `Initialize`/`Methods` próprio.
]]

local Types = require("../Types")

local BehaviorIndex: { [string]: Types.Behavior } = {
	StarterPlayer = require("./StarterPlayer") :: Types.Behavior,
}

return BehaviorIndex
