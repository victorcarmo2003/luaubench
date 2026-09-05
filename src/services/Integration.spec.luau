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

	BLOQUEIO DE RUNTIME CONFIRMADO NESTA TAREFA (não contornável dentro do território de
	`services` -- ver o relatório do agente para o desenho do fix, despachado para
	`coder-runtime`): `Runtime.ClassRegistry.new` rejeita `IsAbstract == true`
	INCONDICIONALMENTE, e TODA classe `Service` desta leva (e `StarterPlayerScripts`/
	`StarterCharacterScripts`, que não são Service mas também são `NotCreatable`) carrega
	`IsAbstract = true` -- fiel ao dump. Isso bloqueia:
	(1) `game:GetService(...)` de QUALQUER Service desta leva (ReplicatedStorage/ServerStorage/
	    ServerScriptService/ReplicatedFirst/StarterPack/StarterGui/StarterPlayer/Workspace/
	    Lighting) -- `DataModel:GetService` (código de `runtime`) chama `ClassRegistry.new`
	    internamente e esbarra na mesma rejeição que deveria valer só para o script do usuário
	    tentando `Instance.new` direto.
	(2) A criação dos filhos fixos de `StarterPlayer` (`StarterPlayerScripts`/
	    `StarterCharacterScripts`), que teria que rodar dentro do `Initialize` de `StarterPlayer`
	    -- também bloqueado, e em dobro: nem o CONTAINER (`StarterPlayer`) nem os FILHOS são
	    instanciáveis hoje.
	Os testes marcados "BLOQUEIO CONHECIDO" abaixo são GATILHOS DE REGRESSÃO deliberados: eles
	afirmam o comportamento ERRADO de HOJE, com a mensagem exata. Se `coder-runtime` corrigir o
	bug, estes testes VÃO FALHAR -- é o sinal para atualizar cada um ao caminho feliz (documentado
	dentro de cada teste) e então implementar `behavior/StarterPlayer.luau`, que hoje não existe
	por não haver como testá-lo (ver `src/services/behavior/Index.luau`, cabeçalho).

	Onde a acceptance do board pede `rs.Modules.Combat`/`workspace:Set3dRenderingEnabled` (exemplos
	que dependem de `GetService`, hoje bloqueado), os testes abaixo usam classes REAIS e
	CONSTRUÍVEIS desta mesma leva como substituto equivalente (`Folder` no lugar de
	`ReplicatedStorage` para resolução de filho por nome; `Folder:GetPropertyChangedSignal(...)`
	no lugar de `workspace:Set3dRenderingEnabled` para método excluído por Security -- confirmado
	empiricamente nesta tarefa que `GetPropertyChangedSignal` NÃO está em `Instance.MethodNames`,
	logo não ganha stub `[LuauBench]`, e cai no fallback "is not a valid member of" de
	`Runtime.Instance`) -- o MECANISMO testado (resolução de filho, filtro de Security/Capabilities
	em `MethodNames`) é o mesmo independente de qual classe o exercita; a substituição está
	documentada aqui e no relatório da tarefa, nunca escondida.

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
-- 6. BLOQUEIO CONHECIDO -- gatilhos de regressão para o bug de runtime descoberto nesta tarefa
--    (ver cabeçalho do arquivo). Cada teste abaixo afirma o comportamento ERRADO de hoje; se
--    `coder-runtime` corrigir `ClassRegistry.new`/`DataModel.GetService`, estes testes FALHAM --
--    é o sinal para reescrevê-los ao caminho feliz descrito em cada comentário.
--------------------------------------------------------------------------------------------------

test(
	"BLOQUEIO CONHECIDO: game:GetService('ReplicatedStorage') ainda ERRA hoje (ClassRegistry.new rejeita IsAbstract mesmo vindo de GetService)",
	function()
		local scheduler = Runtime.Scheduler.new()
		local game = Runtime.DataModel.new()
		Services.Bootstrap({ scheduler = scheduler, dataModel = game })

		-- `game` já é `Runtime.DataModel`, que declara `GetService` tipado -- nenhum cast necessário.
		local ok, err = pcall(function()
			return game:GetService("ReplicatedStorage")
		end)

		-- CAMINHO FELIZ, quando corrigido: `ok` deveria ser `true`, o retorno deveria ser uma
		-- Instance com ClassName == "ReplicatedStorage", parenteada sob `game`, e uma SEGUNDA
		-- chamada a GetService("ReplicatedStorage") deveria devolver o MESMO objeto (rawequal).
		assert(
			not ok,
			"GATILHO DE REGRESSÃO: este teste espera que GetService ainda FALHE. Se passou a funcionar, o bug de " ..
				"src/runtime/ClassRegistry.luau (IsAbstract bloqueando construção interna de Service) foi corrigido -- " ..
				"reescreva este teste para o caminho feliz descrito no comentário acima."
		)
		assert(
			string.find(tostring(err), "'ReplicatedStorage' é abstrata, não pode ser instanciada", 1, true) ~= nil,
			`mensagem de erro mudou de forma inesperada -- reconfirme o repro antes de mexer, recebeu: {err}`
		)
	end
)

test(
	"BLOQUEIO CONHECIDO: filhos fixos de StarterPlayer (StarterPlayerScripts/StarterCharacterScripts) ainda não são construíveis",
	function()
		-- Mesmo bug do teste acima, no segundo call site que o desenho de task-services-003 pedia
		-- (StarterPlayer.Initialize criando estes 2 filhos). Testado direto via
		-- Runtime.ClassRegistry.new (o que um `behavior/StarterPlayer.luau` teria que chamar) --
		-- não há Services.new envolvido porque o problema é o mesmo em qualquer camada.
		local ok, err = pcall(function()
			return Runtime.ClassRegistry.new("StarterPlayerScripts", nil)
		end)

		-- CAMINHO FELIZ, quando corrigido: implementar src/services/behavior/StarterPlayer.luau
		-- com Initialize criando StarterPlayerScripts/StarterCharacterScripts e parenteando cada
		-- um a `self` (nunca setando o Parent da própria instância) -- ver a nota completa em
		-- src/services/behavior/Index.luau.
		assert(
			not ok,
			"GATILHO DE REGRESSÃO: este teste espera que a construção AINDA FALHE. Se passou a funcionar, implemente " ..
				"behavior/StarterPlayer.luau (ver o comentário no caminho feliz acima) e mova este teste para lá."
		)
		assert(
			string.find(tostring(err), "'StarterPlayerScripts' é abstrata, não pode ser instanciada", 1, true) ~= nil,
			`mensagem de erro mudou de forma inesperada, recebeu: {err}`
		)
	end
)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
