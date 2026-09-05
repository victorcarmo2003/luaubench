--!strict

--[[
	Teste de integração de task-services-003 ("Primeira leva de classes reais: contêineres da
	árvore Rojo + Scripts + Workspace + Lighting"). Ver .claude/agents-memory/arquiteto-services-
	2026-09-05.md, "Decisão 5", ANTES de mexer aqui. Ao contrário de `init.spec.luau` (classes
	FICTÍCIAS montadas à mão, testando só a superfície de `init.luau`), este arquivo exercita as
	24 classes REAIS emitidas pelo gerador (task-services-002, `src/services/generated/**`) através
	de `Services.Register()`/`Services.new()` de ponta a ponta -- nunca lendo `generated/**`
	diretamente (regra 03: `cli`/testes de fora consomem só `require("../services")`, e este spec
	mora DENTRO de `src/services/`, mas segue a mesma disciplina por princípio).

	`require("./")`, NÃO `require("./init")`/`require("./init.luau")`: mesmo gotcha de resolução de
	`require` do Lune 0.10.5 já documentado em `init.spec.luau`/`src/runtime/init.spec.luau` -- só a
	forma "estilo diretório" carrega o `init.luau` real a partir de um arquivo irmão.

	BLOQUEIO DE RUNTIME RESOLVIDO NESTA RETOMADA (estava documentado aqui como bloqueio confirmado
	quando esta tarefa rodou pela primeira vez -- ver .claude/agents-memory/arquiteto-runtime-
	2026-09-04.md, seção "Revisão pós-integração 2026-09-05 (4)", e `task-runtime-023` no board
	para o desenho completo do fix): `Runtime.ClassRegistry.new` rejeitava `IsAbstract == true`
	INCONDICIONALMENTE, e TODA classe `Service` desta leva (e `StarterPlayerScripts`/
	`StarterCharacterScripts`, que não são Service mas também são `NotCreatable`) carrega
	`IsAbstract = true` -- fiel ao dump. Isso bloqueava:
	(1) `game:GetService(...)` de QUALQUER Service desta leva (ReplicatedStorage/ServerStorage/
	    ServerScriptService/ReplicatedFirst/StarterPack/StarterGui/StarterPlayer/Workspace/
	    Lighting) -- `DataModel:GetService` (código de `runtime`) chamava `ClassRegistry.new`
	    internamente e esbarrava na mesma rejeição que deveria valer só para o script do usuário
	    tentando `Instance.new` direto.
	(2) A criação dos filhos fixos de `StarterPlayer` (`StarterPlayerScripts`/
	    `StarterCharacterScripts`), que precisava rodar dentro do `Initialize` de `StarterPlayer`
	    -- também bloqueada, e em dobro: nem o CONTAINER (`StarterPlayer`) nem os FILHOS eram
	    instanciáveis.

	`task-runtime-023` resolveu com DOIS construtores em `Runtime.ClassRegistry`
	(`src/runtime/ClassRegistry.luau`): a via PÚBLICA (`ClassRegistry.new`) mantém a guarda de
	`IsAbstract` (script não pode `Instance.new` classe `NotCreatable` -- comportamento correto,
	igual ao Roblox real), e a via NOVA do motor (`ClassRegistry.NewEngineInstance`, mesma
	construção completa, SEM a guarda) passou a ser usada por `DataModel.GetService` (construção
	do singleton de Service) e por `behavior/StarterPlayer.luau` (criação dos dois filhos fixos --
	módulo novo desta retomada, com spec próprio em `behavior/StarterPlayer.spec.luau`). A seção
	"6" abaixo, que continha os dois testes-gatilho de regressão desta tarefa (o sinal deliberado
	de que o bug ainda existia), foi REESCRITA para o caminho feliz -- ver o comentário no início
	dela. Uma nova seção "1b", logo após a seção 1, cobre `game:GetService` de ponta a ponta para
	as 9 Services desta leva (as 8 listadas na retomada mais `Workspace`, testado pela mesma razão
	-- é Service+NotCreatable como as outras 8, e a cobertura fica mais completa sem custo extra).

	Onde a acceptance do board pede `rs.Modules.Combat`/`workspace:Set3dRenderingEnabled` (exemplos
	que dependem de `GetService` -- hoje DESBLOQUEADO, ver seção "1b"), as seções 2-5 abaixo
	continuam usando classes REAIS e CONSTRUÍVEIS desta mesma leva como substituto equivalente
	(`Folder` no lugar de `ReplicatedStorage` para resolução de filho por nome;
	`Folder:GetPropertyChangedSignal(...)` no lugar de `workspace:Set3dRenderingEnabled` para
	método excluído por Security -- confirmado empiricamente nesta tarefa que
	`GetPropertyChangedSignal` NÃO está em `Instance.MethodNames`, logo não ganha stub
	`[LuauBench]`, e cai no fallback "is not a valid member of" de `Runtime.Instance`) --
	deliberadamente MANTIDAS como estão: o MECANISMO testado (resolução de filho, filtro de
	Security/Capabilities em `MethodNames`) é o mesmo independente de qual classe o exercita, e a
	seção "1b" já cobre `ReplicatedStorage`/`Workspace` de verdade via `GetService` -- duplicar as
	seções 2-5 sobre a classe real não agregaria cobertura nova, só risco de diff desnecessário.

	Roda com `lune run src/services/Integration.spec.luau`.
]]

local process = require("@lune/process")
local Runtime = require("../runtime")
local Services = require("./")

type Dynamic = { [string]: unknown }

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

-- `Services.Register()` é idempotente (guarda local em init.luau) -- chamar aqui, antes de
-- qualquer teste, é seguro mesmo que outro spec do processo já tenha chamado.
Services.Register()

--------------------------------------------------------------------------------------------------
-- 1. Registro: as 24 classes desta leva (task-services-002) estão todas simuladas.
--------------------------------------------------------------------------------------------------

local COVERED_CLASSES: { string } = {
	"BasePlayerGui",
	"BaseScript",
	"Folder",
	"Instance",
	"Lighting",
	"LocalScript",
	"LuaSourceContainer",
	"Model",
	"ModuleScript",
	"PVInstance",
	"Players",
	"ReplicatedFirst",
	"ReplicatedStorage",
	"RunService",
	"Script",
	"ServerScriptService",
	"ServerStorage",
	"StarterCharacterScripts",
	"StarterGui",
	"StarterPack",
	"StarterPlayer",
	"StarterPlayerScripts",
	"Workspace",
	"WorldRoot",
}

-- Concretas (IsAbstract == false no dump, confirmado por grep em generated/classes/*.luau nesta
-- tarefa): as únicas 5 desta leva instanciáveis via Instance.new/Services.new. `Players` e
-- `RunService` JÁ estão no fecho gerado por task-services-002 (a leva inteira, ~24 classes) mas o
-- COMPORTAMENTO delas é escopo de task-services-004 -- aqui elas só são verificadas como
-- REGISTRADAS e ABSTRATAS (Service), nunca com comportamento.
local CONCRETE_CLASSES: { [string]: boolean } = {
	Folder = true,
	LocalScript = true,
	Model = true,
	ModuleScript = true,
	Script = true,
}

test("as 24 classes da leva estão registradas (Services.IsSimulatedClass)", function()
	for _, className in COVERED_CLASSES do
		assert(Services.IsSimulatedClass(className), `'{className}' deveria estar simulada depois de Services.Register()`)
		assert(Services.IsKnownClass(className), `'{className}' deveria ser conhecida (é simulada, logo conhecida)`)
	end
end)

test(
	"Instance.new (Services.new): as 5 classes concretas desta leva instanciam; as 19 abstratas ERRAM 'Unable to create an Instance of type'",
	function()
		for _, className in COVERED_CLASSES do
			if CONCRETE_CLASSES[className] then
				local instance = Services.new(className, nil)
				assert(instance.ClassName == className, `Services.new('{className}') deveria devolver ClassName == '{className}'`)
			else
				local ok, err = pcall(function()
					return Services.new(className, nil)
				end)
				assert(not ok, `Services.new('{className}') deveria erro -- é IsAbstract (NotCreatable) no dump`)
				assert(
					string.find(tostring(err), `Unable to create an Instance of type "{className}"`, 1, true) ~= nil,
					`mensagem deveria bater com a família Roblox (Decisão 5), recebeu: {err}`
				)
			end
		end
	end
)

--------------------------------------------------------------------------------------------------
-- 1b. game:GetService(...) funciona para as Services desta leva (task-runtime-023 destravou
--     Runtime.ClassRegistry.NewEngineInstance -- ver o cabeçalho do arquivo). Cobre as 8 Services
--     listadas na retomada de task-services-003 mais Workspace (mesmo mecanismo, Service +
--     NotCreatable como as outras). `Players`/`RunService` ENTRAM AQUI a partir de
--     task-services-004 -- estavam deliberadamente EXCLUÍDAS enquanto o COMPORTAMENTO delas não
--     existia (task-services-002 só as registrava). Este loop cobre só a superfície GENÉRICA de
--     Service (ClassName/Parent/singleton) -- a superfície ESPECÍFICA de cada uma
--     (rawequal(Heartbeat, scheduler.Heartbeat), RenderStepped errando, GetPlayers() vazio etc.)
--     tem spec dedicado em `behavior/RunService.spec.luau`/`behavior/Players.spec.luau`.
--------------------------------------------------------------------------------------------------

local SERVICES_THIS_LEVA: { string } = {
	"ReplicatedStorage",
	"ServerStorage",
	"ServerScriptService",
	"ReplicatedFirst",
	"StarterPack",
	"StarterGui",
	"StarterPlayer",
	"Lighting",
	"Workspace",
	"Players",
	"RunService",
}

test(
	"game:GetService funciona para as Services desta leva: singleton criado, ClassName correto, parenteado sob game, e chamada repetida devolve o MESMO objeto",
	function()
		local scheduler = Runtime.Scheduler.new()
		local game = Runtime.DataModel.new()
		Services.Bootstrap({ scheduler = scheduler, dataModel = game })

		for _, className in SERVICES_THIS_LEVA do
			local service = game:GetService(className)
			assert(
				service.ClassName == className,
				`GetService('{className}') deveria devolver ClassName == '{className}', recebeu '{service.ClassName}'`
			)
			assert(
				rawequal(service.Parent, game),
				`GetService('{className}') deveria parentear o singleton direto sob a raiz (game), igual ao Roblox real`
			)

			local second = game:GetService(className)
			assert(
				rawequal(service, second),
				`a segunda chamada a GetService('{className}') deveria devolver o MESMO objeto (singleton) -- rawequal falhou`
			)
		end
	end
)

--------------------------------------------------------------------------------------------------
-- 2. Resolução de filho por nome (task-runtime-021) com Instance REAL desta leva -- substitui
--    `rs.Modules.Combat` por `Folder`s reais parenteados, encadeado em 2 e 3 níveis, porque
--    `ReplicatedStorage` só existe via `GetService`, bloqueado (ver cabeçalho do arquivo).
--------------------------------------------------------------------------------------------------

test("Folder parenteado é alcançável por nome (2 e 3 níveis) -- fecha o buraco do arquiteto com Instance real", function()
	-- `Services.new` devolve `Runtime.Instance` de verdade -- `.Parent =` usa o campo tipado
	-- normalmente, sem cast nenhum.
	local root = Services.new("Folder", "Root")
	local modules = Services.new("Folder", "Modules")
	modules.Parent = root

	-- Acessar um FILHO por NOME (`root.Modules`) não é membro estático de `Runtime.Instance` --
	-- precisa de `Dynamic`, com cast em duas etapas por `unknown` (nunca `any`, regra 01).
	local rootDynamic = (root :: unknown) :: Dynamic
	assert(rootDynamic.Modules == modules, "2 níveis: root.Modules deveria resolver para o Folder filho 'Modules'")

	local combat = Services.new("Folder", "Combat")
	combat.Parent = modules

	local modulesDynamic = (rootDynamic.Modules :: unknown) :: Dynamic
	assert(modulesDynamic.Combat == combat, "3 níveis: root.Modules.Combat deveria resolver para o Folder neto 'Combat'")
end)

--------------------------------------------------------------------------------------------------
-- 3. Modo estrito (task-runtime-018) contra o schema REAL de "Instance", herdado por qualquer
--    classe concreta desta leva via achatamento de Runtime.ClassRegistry -- usando Folder.
--------------------------------------------------------------------------------------------------

test("modo estrito: ler um nome GENUINAMENTE ausente do dump (typo) erra 'is not a valid member of'", function()
	-- Cast em duas etapas por `unknown` -- mesmo padrão já usado em init.spec.luau (`Runtime.Instance`
	-- e `Dynamic` são estruturalmente não relacionados aos olhos do Luau; ir direto seria rejeitado).
	local folder = (Services.new("Folder", "F") :: unknown) :: Dynamic
	local ok, err = pcall(function()
		return folder.Frobnicate
	end)
	assert(not ok, "ler um nome que não existe no dump deveria erro (modo estrito)")
	assert(
		string.find(tostring(err), "Frobnicate is not a valid member of Folder", 1, true) ~= nil,
		`mensagem deveria bater com o formato confirmado, recebeu: {err}`
	)
end)

test("modo estrito: propriedade do schema cujo Default é nil (Archivable, herdado de Instance) lê nil SEM erro", function()
	-- Cast em duas etapas por `unknown` -- mesmo padrão já usado em init.spec.luau (`Runtime.Instance`
	-- e `Dynamic` são estruturalmente não relacionados aos olhos do Luau; ir direto seria rejeitado).
	local folder = (Services.new("Folder", "F") :: unknown) :: Dynamic
	local ok, value = pcall(function()
		return folder.Archivable
	end)
	assert(ok, "ler uma propriedade do schema com Default nil não deveria erro -- é o caso que motivou o schema inteiro")
	assert(value == nil, "Archivable deveria ler nil (ValueType não representável nesta fase, Decisão 3)")
end)

test("escrever propriedade ReadOnly (ClassName, herdado de Instance) erra com a string CONFIRMADA", function()
	-- Cast em duas etapas por `unknown` -- mesmo padrão já usado em init.spec.luau (`Runtime.Instance`
	-- e `Dynamic` são estruturalmente não relacionados aos olhos do Luau; ir direto seria rejeitado).
	local folder = (Services.new("Folder", "F") :: unknown) :: Dynamic
	local ok, err = pcall(function()
		folder.ClassName = "Whatever"
	end)
	assert(not ok, "escrever ClassName deveria erro -- é ReadOnly no schema de Instance")
	assert(
		string.find(tostring(err), "Unable to assign property ClassName. Property is read only", 1, true) ~= nil,
		`mensagem deveria bater com a string confirmada (task-runtime-018), recebeu: {err}`
	)
end)

test("escrever um Event do schema (AttributeChanged, herdado de Instance) erra 'is an event of ... and cannot be reassigned'", function()
	-- Cast em duas etapas por `unknown` -- mesmo padrão já usado em init.spec.luau (`Runtime.Instance`
	-- e `Dynamic` são estruturalmente não relacionados aos olhos do Luau; ir direto seria rejeitado).
	local folder = (Services.new("Folder", "F") :: unknown) :: Dynamic
	local ok, err = pcall(function()
		folder.AttributeChanged = 1
	end)
	assert(not ok, "escrever sobre um Event do schema deveria erro -- evento não é reatribuível")
	assert(
		string.find(tostring(err), "AttributeChanged is an event of Folder and cannot be reassigned", 1, true) ~= nil,
		`mensagem deveria bater com o formato da Decisão 3 (Kind == "Event"), recebeu: {err}`
	)
end)

--------------------------------------------------------------------------------------------------
-- 4. Método sem implementação (stub [LuauBench]) vs. método excluído por Security/Capabilities
--    (erra como membro inexistente) -- a distinção que a nota de revisão 2026-09-05 do board pede
--    para não confundir. `Clone` está em Instance.MethodNames sem Behavior -> stub.
--    `GetPropertyChangedSignal` NÃO está em Instance.MethodNames (excluído na origem, confirmado
--    empiricamente) -> cai no fallback "is not a valid member of" -- mesmo mecanismo do exemplo do
--    board (`workspace:Set3dRenderingEnabled`), só que numa classe alcançável sem GetService.
--------------------------------------------------------------------------------------------------

test("método no dump SEM implementação (Clone, herdado de Instance) erra com a mensagem [LuauBench]", function()
	-- Cast em duas etapas por `unknown` -- mesmo padrão já usado em init.spec.luau (`Runtime.Instance`
	-- e `Dynamic` são estruturalmente não relacionados aos olhos do Luau; ir direto seria rejeitado).
	local folder = (Services.new("Folder", "F") :: unknown) :: Dynamic
	local ok, err = pcall(function()
		return (folder.Clone :: (self: Dynamic) -> unknown)(folder)
	end)
	assert(not ok, "chamar um método sem implementação deveria erro, nunca retornar nil silenciosamente")
	assert(
		string.find(tostring(err), "[LuauBench] Instance:Clone() exists in the Roblox API Dump", 1, true) ~= nil,
		`mensagem deveria ter o prefixo [LuauBench] (regra 03), recebeu: {err}`
	)
end)

test(
	"método existente no Roblox real mas excluído por Security/Capabilities (GetPropertyChangedSignal) erra como MEMBRO INEXISTENTE, não [LuauBench]",
	function()
		-- Cast em duas etapas por `unknown` -- mesmo padrão já usado em init.spec.luau (`Runtime.Instance`
	-- e `Dynamic` são estruturalmente não relacionados aos olhos do Luau; ir direto seria rejeitado).
	local folder = (Services.new("Folder", "F") :: unknown) :: Dynamic
		local ok, err = pcall(function()
			return (folder.GetPropertyChangedSignal :: (self: Dynamic, propertyName: string) -> unknown)(folder, "Name")
		end)
		assert(not ok, "GetPropertyChangedSignal não está no schema/MethodNames simulado -- deveria erro")
		local message = tostring(err)
		assert(
			string.find(message, "GetPropertyChangedSignal is not a valid member of Folder", 1, true) ~= nil,
			`deveria errar como membro inexistente (fiel ao Roblox real para um método com Security elevada), recebeu: {message}`
		)
		assert(
			string.find(message, "[LuauBench]", 1, true) == nil,
			"NÃO deveria ter o prefixo [LuauBench] -- esse método não é 'ainda não simulado', ele não existe para um script comum"
		)
	end
)

--------------------------------------------------------------------------------------------------
-- 5. Script.Source: fora do schema por Capabilities.Read == ["PluginOrOpenCloud"] (Security é
--    None/None -- NÃO é PluginSecurity, correção da revisão 2026-09-05). Ler erra; `cli` grava/lê
--    por Get/SetPropertyRaw, que não passam pelo schema.
--------------------------------------------------------------------------------------------------

test("script.Source está FORA do schema -- ler erra (nunca string vazia, nunca o código-fonte)", function()
	local script = (Services.new("Script", "MyScript") :: unknown) :: Dynamic
	local ok, err = pcall(function()
		return script.Source
	end)
	assert(not ok, "ler script.Source deveria erro -- fiel ao Roblox, onde um script comum também não lê Source")
	assert(
		string.find(tostring(err), 'Source is not a valid member of Script "MyScript"', 1, true) ~= nil,
		`mensagem deveria ser a de membro inexistente do LuauBench (DIVERGÊNCIA DECLARADA: no Roblox real a família é ` ..
			`de capability -- "The current thread cannot read 'Source' (lacking capability PluginOrOpenCloud)" -- o ` ..
			`LuauBench não simula essa família e erra "is not a valid member of" no lugar; erra nos dois casos, ` ..
			`mensagem diferente, nunca silencioso), recebeu: {err}`
	)
end)

test("cli grava/lê script.Source por Get/SetPropertyRaw, que NÃO passam pelo schema", function()
	local script = Services.new("Script", "MyScript")
	Runtime.Instance.SetPropertyRaw(script, "Source", "return 1 + 1")
	local raw = Runtime.Instance.GetPropertyRaw(script, "Source")
	assert(raw == "return 1 + 1", "GetPropertyRaw deveria devolver exatamente o que SetPropertyRaw gravou")

	-- Confirma que o bypass é mesmo bypass: ler via `.Source` normal (schema) continua errando
	-- mesmo depois de SetPropertyRaw ter gravado um valor no storage interno.
	local scriptDynamic = (script :: unknown) :: Dynamic
	local ok = pcall(function()
		return scriptDynamic.Source
	end)
	assert(not ok, "SetPropertyRaw não deveria abrir a propriedade para leitura via schema -- ela continua fora dele")
end)

--------------------------------------------------------------------------------------------------
-- 6. StarterPlayer nasce com os dois filhos fixos (behavior/StarterPlayer.luau, retomada desta
--    tarefa) + regressão da via PÚBLICA continuando a rejeitar NotCreatable corretamente.
--
--    Os dois testes abaixo SUBSTITUEM os dois testes-gatilho de regressão ("BLOQUEIO CONHECIDO")
--    que existiam aqui enquanto `task-runtime-023` estava pendente -- eles afirmavam de propósito
--    o comportamento ERRADO de então (`game:GetService`/`ClassRegistry.new("StarterPlayerScripts")`
--    ambos errando "'{Classe}' é abstrata, não pode ser instanciada"). Com o fix aplicado, os dois
--    caminhos se separam como o desenho sempre previu: `GetService` (via do motor,
--    `NewEngineInstance`) passa a FUNCIONAR; a via pública (`ClassRegistry.new`, o que um script
--    tentando `Instance.new` alcançaria) continua ERRANDO -- mas com uma mensagem NOVA
--    (`task-runtime-023` trocou o texto de "é abstrata" para a frase que nomeia
--    NotCreatable/NewEngineInstance, ver `src/runtime/ClassRegistry.luau`). Cobertura unitária de
--    `behavior/StarterPlayer.luau` isolada (sem `GetService`/`DataModel` no meio) vive em
--    `behavior/StarterPlayer.spec.luau` -- os testes abaixo cobrem o caminho ponta a ponta.
--------------------------------------------------------------------------------------------------

test(
	"game:GetService('StarterPlayer') nasce com StarterPlayerScripts e StarterCharacterScripts, parenteados a ELE -- nunca a game",
	function()
		local scheduler = Runtime.Scheduler.new()
		local game = Runtime.DataModel.new()
		Services.Bootstrap({ scheduler = scheduler, dataModel = game })

		local starterPlayer = game:GetService("StarterPlayer")
		assert(
			rawequal(starterPlayer.Parent, game),
			"StarterPlayer deveria estar parenteado sob game -- é GetService quem parenteia, não o Initialize dele"
		)

		local starterPlayerScripts = starterPlayer:FindFirstChildOfClass("StarterPlayerScripts")
		local starterCharacterScripts = starterPlayer:FindFirstChildOfClass("StarterCharacterScripts")

		assert(starterPlayerScripts ~= nil, "StarterPlayer deveria nascer com um filho StarterPlayerScripts (behavior/StarterPlayer.luau, Initialize)")
		assert(starterCharacterScripts ~= nil, "StarterPlayer deveria nascer com um filho StarterCharacterScripts (behavior/StarterPlayer.luau, Initialize)")
		assert(
			rawequal((starterPlayerScripts :: Runtime.Instance).Parent, starterPlayer),
			"StarterPlayerScripts deveria estar parenteado a StarterPlayer -- NUNCA a game (contrato do campo Initialize: nunca mexe no Parent da própria instância recebida)"
		)
		assert(
			rawequal((starterCharacterScripts :: Runtime.Instance).Parent, starterPlayer),
			"StarterCharacterScripts deveria estar parenteado a StarterPlayer -- NUNCA a game"
		)

		-- Segunda chamada a GetService devolve o MESMO StarterPlayer (singleton) -- e portanto os
		-- MESMOS filhos, sem duplicar (o Initialize só roda uma vez, na primeira construção).
		local second = game:GetService("StarterPlayer")
		assert(rawequal(starterPlayer, second), "segunda chamada a GetService('StarterPlayer') deveria devolver o MESMO objeto")
	end
)

test(
	"a via PÚBLICA (Runtime.ClassRegistry.new) continua REJEITANDO StarterPlayerScripts -- script não pode Instance.new algo NotCreatable -- agora com a mensagem NOVA de task-runtime-023",
	function()
		local ok, err = pcall(function()
			return Runtime.ClassRegistry.new("StarterPlayerScripts", nil)
		end)
		assert(
			not ok,
			"a via pública (ClassRegistry.new) deveria continuar rejeitando StarterPlayerScripts -- só NewEngineInstance (a via do motor, usada por GetService/Initialize) pode criá-la"
		)
		local message = tostring(err)
		assert(
			string.find(
				message,
				"classe 'StarterPlayerScripts' não é criável por script (tag NotCreatable do Roblox API Dump); construção interna do motor usa ClassRegistry.NewEngineInstance",
				1,
				true
			) ~= nil,
			`mensagem deveria ser a NOVA de task-runtime-023, não a antiga "é abstrata, não pode ser instanciada" (regressão desta retomada), recebeu: {message}`
		)
	end
)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
