--!strict

--[[
	Mapa `ClassName -> Behavior`, escrito À MÃO de propósito (não gerado -- o gerador nunca deve
	poder apagar esta lista curada). Ver .claude/agents-memory/arquiteto-services-2026-09-05.md,
	seção "Módulos" -> "src/services/behavior/Index.luau": "É a lista curada do que tem
	comportamento, e o gerador nunca deve poder apagá-la."

	task-services-003 (primeira leva de classes reais: contêineres da árvore Rojo + Scripts +
	Workspace + Lighting) — LER .claude/agents-memory/arquiteto-services-2026-09-05.md, "Decisão 5"
	antes de mexer aqui.

	POR QUE ESTE MAPA ESTÁ VAZIO NESTA LEVA (não por preguiça, por um bloqueio de `runtime`
	confirmado empiricamente nesta tarefa — ver o relatório do agente para o desenho do fix):

	A imensa maioria das 24 classes desta leva é contêiner puro (ReplicatedStorage tem
	`Members == []` no dump, por exemplo) e legitimamente dispensa `Behavior` — `ClassBuilder.Build`
	já cobre todo `MethodNames` sem implementação com o stub `[LuauBench] ... not simulated by
	LuauBench yet` (regra 03: nunca stub silencioso). Isso é o esperado, não uma lacuna desta
	tarefa.

	A ÚNICA classe desta leva que o desenho pede comportamento de verdade é `StarterPlayer`
	(Initialize criando os filhos fixos `StarterPlayerScripts`/`StarterCharacterScripts`). Essa
	tarefa NÃO pôde ser cumprida: `StarterPlayer` é `Service` no dump, e TODO `Service` coberto
	nesta leva carrega a tag `NotCreatable`, que o gerador traduz corretamente para
	`GeneratedClass.IsAbstract = true` (fiel ao dump — no Roblox real também não dá para
	`Instance.new("StarterPlayer")`). O problema é que `Runtime.ClassRegistry.new` — o ÚNICO
	criador de instância que `services` tem acesso — REJEITA `IsAbstract == true`
	INCONDICIONALMENTE, sem distinguir "script tentando dar `Instance.new` numa classe não-criável"
	(o caso real que a tag deveria bloquear) de "o próprio motor construindo o singleton do Service
	internamente" (o que `game:GetService(...)` e a criação dos filhos fixos de `StarterPlayer`
	precisam fazer, e que o Roblox real permite mesmo sendo `NotCreatable` para o script). Confirmado
	rodando de verdade nesta tarefa: `game:GetService("ReplicatedStorage")` e
	`Runtime.ClassRegistry.new("StarterPlayerScripts")` erram ambos
	"'{Classe}' é abstrata, não pode ser instanciada" (src/runtime/ClassRegistry.luau, dentro de
	`ClassRegistry.new`), MESMO quando o chamador é código interno de `runtime`/`services`, não o
	script do usuário.

	Consequência: `StarterPlayer` em si não pode ser instanciado por NENHUM caminho hoje (nem
	`game:GetService`, nem um `Runtime.ClassRegistry.new` direto em teste) — um `Initialize` aqui
	seria código morto, nunca exercitável, e regra 01 exige teste na MESMA tarefa da lógica que
	cobre. Escrever agora um `behavior/StarterPlayer.luau` que ninguém consegue rodar nem testar
	seria pior que não escrever nada. Fica como pendência EXPLÍCITA (não um stub silencioso): a
	tarefa que fecha isso precisa primeiro de uma mudança em `src/runtime/ClassRegistry.luau` (fora
	do território deste agente — `coder-services` não toca `src/runtime/`), despachada para
	`coder-runtime` (ver relatório desta tarefa para o desenho exato do fix proposto). Quando esse
	fix existir, este mapa ganha `["StarterPlayer"] = require("./StarterPlayer")`.

	Todas as 24 classes desta leva são registradas por `Services.Register()` (ver ../init.luau)
	SEM Behavior — o que este mapa vazio já expressa corretamente hoje.
]]

local Types = require("../Types")

local BehaviorIndex: { [string]: Types.Behavior } = {}

return BehaviorIndex
