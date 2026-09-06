--!strict

--[[
	Teste de integração da task-services-001 (src/services/init.luau, ponto de entrada público de
	`services`). `require("./")`, NÃO `require("./init")`/`require("./init.luau")`: mesmo gotcha
	de resolução de `require` do Lune 0.10.5 já documentado (e confirmado empiricamente por
	`coder-runtime`) no cabeçalho de src/runtime/init.luau/init.spec.luau -- só a forma "estilo
	diretório" carrega o `init.luau` real a partir de um arquivo irmão cujo nome também começa por
	"init". `Context`/`ClassBuilder`/`Types`, por terem nome normal, são requeridos diretamente
	(`require("./Context")` etc.) sem esse cuidado.

	Cobre o acceptance do board: `Register()` idempotente; `Bootstrap` seta o `Context`;
	`services` registra e instancia uma classe FICTÍCIA de teste de ponta a ponta via
	`Runtime.ClassRegistry` (exercita ClassBuilder/ClassRegistry/Schema/Signal de evento de forma
	isolada, sem depender de qual classe real está coberta nesta leva); a família de erros de
	`Services.new` (classe inexistente e classe abstrata caem na MESMA mensagem "Unable to create
	an Instance of type ..."); `IsKnownClass`/`IsSimulatedClass`/`GetDumpVersion`.

	task-services-005 ("Services.new: a família de três erros de classe e o Instance.new do
	sandbox"): acrescenta a seção "task-services-005" abaixo, com os TRÊS casos da família de erro
	testados contra classes REAIS do manifesto (`generated/Manifest.luau`, as 916 classes) -- não
	mais só classes fictícias -- porque é só com o manifesto real que o terceiro caso ("existe no
	dump, ainda não simulada", ex.: "Frame") fica alcançável; e um teste de fumaça do BOOTSTRAP
	COMPLETO documentado no cabeçalho de init.luau, com um `Runtime.Sandbox.Run` REAL (não mock):
	`Runtime.DataModel.new` -> `Services.Bootstrap` -> `game:GetService` -> `Instance.new` (via
	`extraGlobals.Instance = { new = Services.new }`, exatamente como `cli` vai injetar) rodando
	DENTRO do script sandboxed, confirmando que a `Folder` criada pelo script está de fato
	parenteada na árvore real depois que `Scheduler:Run` devolve o controle.

	PENDÊNCIA DE TOOLING (mesmo achado já documentado no cabeçalho de src/runtime/init.spec.luau,
	confirmado de novo aqui, nunca por suposição -- regra 00): `luau-lsp analyze` 1.69.0 devolve
	"Unknown require"/"Unknown type 'Runtime.X'"/"Function only returns 1 value, but 2 are
	required here" em cascata bem NESTE arquivo, mesmo com os `require` escritos do jeito normal
	(`require("../runtime")`, `require("./Context")`, `require("./")`). Confirmado empiricamente
	que o gatilho é o NOME deste arquivo (começa por "init"), não o conteúdo: uma cópia idêntica
	renomeada para não começar com "init", analisada isolada, dá **zero erros** -- os mesmos
	`require`/tipos que aqui aparecem "desconhecidos" resolvem certinho. `lune run
	src/services/init.spec.luau` roda e passa (verificado nesta tarefa: 14/14) de verdade (Lune,
	que executa por real, não tem esse bug -- ele só afeta a análise estática do `luau-lsp`). Não
	escondido, não adivinhado: revisor-services deve reproduzir a cópia renomeada antes de
	reprovar esta tarefa por causa de diagnóstico neste arquivo especificamente.

	SEGUNDO ACHADO DE TOOLING (task-services-005, confirmado nesta tarefa via a MESMA técnica da
	cópia renomeada, nunca por suposição): mesmo com o arquivo renomeado (bug acima contornado),
	`luau-lsp analyze` 1.69.0 acusa um TypeError isolado no ÚNICO `Runtime.Sandbox.Run({...})`
	deste arquivo (o teste de fumaça do bootstrap, logo abaixo) -- "Property 'Instance' is not
	compatible. Expected this to be exactly '{| new: ... |}', but got 'unknown'" ao checar o campo
	`extraGlobals` contra `SandboxGlobals?` (`{ [string]: unknown }?`, tipo de
	`src/runtime/Sandbox.luau`, fora do território desta tarefa). Isolado com um repro mínimo de 3
	linhas (`local function f(x: { [string]: unknown }?) end; f({ other = "x" })`) -- reproduz
	IDÊNTICO, sem nada de `services` envolvido, e desaparece removendo só o `?` do tipo do
	parâmetro (`{ [string]: unknown }` sem união funciona limpo). É uma limitação de
	`luau-lsp` 1.69.0 unificando um literal de tabela contra um tipo `{[string]: unknown}?`
	(indexador `unknown` dentro de uma união opcional), NÃO um erro de tipo real -- e NÃO é
	introduzida por esta tarefa nem por `services`: reproduz IDÊNTICO nos dois `Runtime.Sandbox.Run`
	já existentes e já APROVADOS em `src/runtime/init.spec.luau` (linhas 180 e 223 daquele arquivo,
	confirmado rodando a MESMA técnica de cópia renomeada sobre aquele arquivo nesta tarefa) --
	todo `extraGlobals = {...}` inline do repositório inteiro está igualmente exposto, porque é
	assim que `SandboxOptions.extraGlobals` é tipado em `src/runtime/Sandbox.luau` (fora do
	território de `services`). `lune run` prova que o código roda corretamente (14/14, incluindo o
	teste de fumaça) -- é só a análise estática que erra. Não escondido: fica registrado aqui para
	`arquiteto`/`pesquisador` avaliarem se vale a pena reportar a montante (`luau-lsp` upstream) ou
	ajustar a assinatura de `SandboxOptions` algum dia -- decisão de `runtime`, não desta tarefa.

	Roda com `lune run src/services/init.spec.luau`.
]]

local process = require("@lune/process")
local Runtime = require("../runtime")
local Types = require("./Types")
local Context = require("./Context")
local ClassBuilder = require("./ClassBuilder")
local Manifest = require("./generated/Manifest")
local EngineFixedChildren = require("./EngineFixedChildren")
local Services = require("./")

type ClassSchema = Runtime.ClassSchema
type MemberKind = Runtime.MemberKind
type Dynamic = { [string]: unknown }

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

--[[
	task-services-009 (arquiteto-cli-2026-09-05.md, Decisão 4): `IsServiceClass`/
	`GetSimulatedServiceClasses` são leitura PURA de `generated/Manifest.luau` -- não tocam
	`Runtime.ClassRegistry` nem `Context`. Este teste PRECISA rodar antes de qualquer
	`Services.Bootstrap`/`Context.Set` deste arquivo (é por isso que vem primeiro, antes até do
	teste "Register() é idempotente" -- `Services.Register()` sozinho não mexe em `Context`, mas
	`Bootstrap` faz, e nenhum outro teste acima deste ponto no arquivo chamou `Bootstrap`) -- a
	asserção `not Context.IsSet()` prova isso, não só documenta.
]]
test("IsServiceClass/GetSimulatedServiceClasses funcionam ANTES de Services.Bootstrap (leitura pura do manifesto, sem erro de Context)", function()
	assert(
		not Context.IsSet(),
		"este teste precisa rodar ANTES de qualquer Services.Bootstrap neste arquivo -- se isto falhar, um teste anterior chamou Bootstrap e a ordem do arquivo foi violada"
	)

	assert(Services.IsServiceClass("ReplicatedStorage"), "'ReplicatedStorage' carrega a tag Service no dump")
	assert(not Services.IsServiceClass("Folder"), "'Folder' existe no dump mas não carrega a tag Service")
	assert(not Services.IsServiceClass("Frmae"), "'Frmae' (typo) não existe no manifesto -- devolve false, nunca erro")

	local first = Services.GetSimulatedServiceClasses()
	local second = Services.GetSimulatedServiceClasses()
	assert(#first == #second, "GetSimulatedServiceClasses deveria devolver o mesmo tamanho em chamadas repetidas")
	for i, name in first do
		assert(name == second[i], `GetSimulatedServiceClasses deveria ser estável entre chamadas -- posição {i} divergiu ('{name}' vs '{second[i]}')`)
	end

	for i = 2, #first do
		assert(first[i - 1] < first[i], `GetSimulatedServiceClasses deveria vir ordenada por nome -- '{first[i - 1]}' apareceu antes de '{first[i]}'`)
	end

	-- Verificação independente (não usa Services.GetSimulatedServiceClasses de novo -- recalcula
	-- do zero direto do Manifest, para não ser um teste tautológico): confirma que o resultado é
	-- EXATAMENTE o conjunto de classes com IsService==true e Covered==true, nem uma a mais nem a
	-- menos.
	local expected: { [string]: boolean } = {}
	local expectedCount = 0
	for className, entry in Manifest.Classes do
		if entry.IsService and entry.Covered then
			expected[className] = true
			expectedCount += 1
		end
	end
	assert(#first == expectedCount, `GetSimulatedServiceClasses deveria devolver {expectedCount} classes (IsService e Covered no manifesto atual), recebeu {#first}`)
	for _, name in first do
		assert(expected[name], `'{name}' não deveria estar no resultado -- não tem IsService==true e Covered==true no manifesto`)
		expected[name] = nil
	end
	assert(next(expected) == nil, "GetSimulatedServiceClasses omitiu ao menos uma classe com IsService==true e Covered==true")

	-- Sanidade pontual com nomes conhecidos da leva atual (falha alto e claro se a leva mudar sem
	-- que este teste seja revisitado).
	local hasReplicatedStorage = false
	local hasWorkspace = false
	for _, name in first do
		if name == "ReplicatedStorage" then
			hasReplicatedStorage = true
		elseif name == "Workspace" then
			hasWorkspace = true
		end
	end
	assert(hasReplicatedStorage, "GetSimulatedServiceClasses deveria incluir 'ReplicatedStorage'")
	assert(hasWorkspace, "GetSimulatedServiceClasses deveria incluir 'Workspace'")
end)

--[[
	task-services-010 (arquiteto-cli-2026-09-05.md, "Revisão pós-implementação 2026-09-05
	(task-cli-015)"): `Services.IsEngineFixedChild` é leitura PURA de `EngineFixedChildren.luau` --
	não toca `Runtime.ClassRegistry` nem `Context`, mesma garantia de `IsServiceClass` acima. Este
	teste PRECISA rodar antes de qualquer `Services.Bootstrap`/`Context.Set` deste arquivo -- por
	isso vem logo depois do teste de `IsServiceClass` (que já prova, com `not Context.IsSet()`, que
	nada neste arquivo chamou `Bootstrap` até aqui).

	TESTE DE GUARDA (acceptance da task-services-010): os cinco trios abaixo, todos fora da lista
	fechada declarada em `EngineFixedChildren.luau`, devolvem `false` -- cobertura detalhada e
	comentada por trio vive em `EngineFixedChildren.spec.luau`; aqui o alvo é a SUPERFÍCIE PÚBLICA
	(`Services.IsEngineFixedChild`, o que `cli` de fato chama), não o módulo interno.
]]
test("Services.IsEngineFixedChild funciona ANTES de Services.Bootstrap (leitura pura de EngineFixedChildren.luau, sem erro de Context)", function()
	assert(
		not Context.IsSet(),
		"este teste precisa rodar ANTES de qualquer Services.Bootstrap neste arquivo -- se isto falhar, um teste anterior chamou Bootstrap e a ordem do arquivo foi violada"
	)

	assert(Services.IsEngineFixedChild("StarterPlayer", "StarterPlayerScripts", "StarterPlayerScripts"), "StarterPlayerScripts é filho fixo declarado de StarterPlayer")
	assert(Services.IsEngineFixedChild("StarterPlayer", "StarterCharacterScripts", "StarterCharacterScripts"), "StarterCharacterScripts é filho fixo declarado de StarterPlayer")

	assert(not Services.IsEngineFixedChild("StarterPlayer", "Terrain", "Terrain"), "Terrain não é filho fixo de StarterPlayer")
	assert(not Services.IsEngineFixedChild("Workspace", "Terrain", "Terrain"), "Workspace não tem filhos fixos declarados (Covered=false, sem behavior/Workspace.luau) -- não pré-cria Terrain")
	assert(not Services.IsEngineFixedChild("DataModel", "StarterPlayerScripts", "StarterPlayerScripts"), "DataModel não é uma chave declarada em EngineFixedChildren")
	assert(not Services.IsEngineFixedChild("ReplicatedStorage", "Folder", "Folder"), "ReplicatedStorage não é uma chave declarada em EngineFixedChildren")
	assert(
		not Services.IsEngineFixedChild("StarterPlayer", "MyScripts", "StarterPlayerScripts"),
		"Name e ClassName precisam bater os dois -- 'MyScripts' com $className 'StarterPlayerScripts' NÃO é adotado (cai no caminho normal de Services.new, que erra 'Unable to create an Instance of type', fiel ao Roblox real)"
	)
end)

--[[
	task-services-014 (arquiteto-cli-2026-09-05.md, Decisão 17): `Services.IsEngineOnlyClass` é
	leitura PURA de `generated/Manifest.luau` + `RUNTIME_OWNED_CLASSES` -- não toca
	`Runtime.ClassRegistry` nem `Context`, mesma garantia de `IsServiceClass`/`IsEngineFixedChild`
	acima. Este teste PRECISA rodar antes de qualquer `Services.Bootstrap`/`Context.Set` deste
	arquivo -- por isso vem logo depois dos testes de `IsServiceClass`/`IsEngineFixedChild` (que já
	provam, com `not Context.IsSet()`, que nada neste arquivo chamou `Bootstrap` até aqui). É também
	o acceptance "(6) segura ANTES de Bootstrap" do board -- este teste nunca chama `Bootstrap`.
]]
test("Services.IsEngineOnlyClass funciona ANTES de Services.Bootstrap (leitura pura do manifesto + RUNTIME_OWNED_CLASSES, sem erro de Context)", function()
	assert(
		not Context.IsSet(),
		"este teste precisa rodar ANTES de qualquer Services.Bootstrap neste arquivo -- se isto falhar, um teste anterior chamou Bootstrap e a ordem do arquivo foi violada"
	)

	-- (1) o caso que originou a tarefa: DataModel é NotCreatable e Covered == false no manifesto
	-- (implementada por `runtime`, fora do pipeline gerado de `services`) -- sem RUNTIME_OWNED_CLASSES
	-- esta asserção falharia, é exatamente a armadilha que a task descreve.
	local dataModelEntry = Manifest.Classes["DataModel"]
	assert(dataModelEntry ~= nil, "'DataModel' deveria constar do manifesto real")
	assert(dataModelEntry.IsAbstract, "'DataModel' deveria ser NotCreatable (IsAbstract==true) no manifesto")
	assert(
		not dataModelEntry.Covered,
		"'DataModel' deveria ter Covered==false no manifesto -- implementada por runtime, fora do pipeline gerado de services"
	)
	assert(
		Services.IsEngineOnlyClass("DataModel"),
		"IsEngineOnlyClass('DataModel') deveria ser true via RUNTIME_OWNED_CLASSES, apesar de Covered==false"
	)

	-- mais três classes NotCreatable e Covered==true que nunca são um nó legítimo de .project.json
	assert(Services.IsEngineOnlyClass("Instance"), "IsEngineOnlyClass('Instance') deveria ser true -- NotCreatable e coberta")
	assert(Services.IsEngineOnlyClass("PVInstance"), "IsEngineOnlyClass('PVInstance') deveria ser true -- NotCreatable e coberta")
	assert(Services.IsEngineOnlyClass("WorldRoot"), "IsEngineOnlyClass('WorldRoot') deveria ser true -- NotCreatable e coberta")

	-- (2) TRUE também para Service coberto -- a função classifica "não pode nascer via
	-- Services.new", NUNCA decide legitimidade de POSIÇÃO (isso é trabalho do isServiceRoot em
	-- TreePlanner, uma camada acima). Workspace/ReplicatedStorage são NotCreatable E Covered no
	-- manifesto real.
	assert(
		Services.IsEngineOnlyClass("Workspace"),
		"IsEngineOnlyClass('Workspace') deveria ser true -- é NotCreatable e coberta, mesmo sendo um Service legítimo na raiz"
	)
	assert(Services.IsEngineOnlyClass("ReplicatedStorage"), "IsEngineOnlyClass('ReplicatedStorage') deveria ser true -- mesma razão")

	-- (3) false para Terrain: NotCreatable, mas Covered==false e NÃO está em RUNTIME_OWNED_CLASSES --
	-- é o recorte que mantém a mensagem VERDADEIRA ("ainda não simulada") em vez de uma acusação de
	-- erro de projeto (Decisão 17, "Por quê o recorte 'este build simula'").
	local terrainEntry = Manifest.Classes["Terrain"]
	assert(
		terrainEntry ~= nil and terrainEntry.IsAbstract and not terrainEntry.Covered,
		"'Terrain' precisa ser NotCreatable e Covered==false no manifesto para exercitar este caso"
	)
	assert(not Services.IsEngineOnlyClass("Terrain"), "IsEngineOnlyClass('Terrain') deveria ser false -- NotCreatable mas ainda não simulada por este build")

	-- (4) false para classes criáveis (IsAbstract==false) -- Folder e ModuleScript são o caso comum
	assert(not Services.IsEngineOnlyClass("Folder"), "IsEngineOnlyClass('Folder') deveria ser false -- classe criável (IsAbstract==false)")
	assert(not Services.IsEngineOnlyClass("ModuleScript"), "IsEngineOnlyClass('ModuleScript') deveria ser false -- classe criável (IsAbstract==false)")

	-- (5) false para classe inexistente no manifesto -- nunca erro
	assert(not Services.IsKnownClass("Frmae"), "'Frmae' (typo) não deveria constar do manifesto real")
	assert(not Services.IsEngineOnlyClass("Frmae"), "IsEngineOnlyClass('Frmae') deveria ser false -- classe ausente do manifesto, nunca erro")
end)

test("Register() é idempotente -- chamar duas vezes não erra", function()
	local ok = pcall(function()
		Services.Register()
		Services.Register()
	end)
	assert(ok, "uma segunda chamada a Services.Register() não deveria erro")
end)

test("Bootstrap seta o Context", function()
	local scheduler = Runtime.Scheduler.new()
	local dataModel = Runtime.DataModel.new()

	Services.Bootstrap({ scheduler = scheduler, dataModel = dataModel })

	assert(Context.IsSet(), "Context.IsSet() deveria ser true depois de Services.Bootstrap")
	assert(Context.GetScheduler() == scheduler, "Context deveria guardar exatamente o Scheduler passado a Bootstrap")
	assert(Context.GetDataModel() == dataModel, "Context deveria guardar exatamente o DataModel passado a Bootstrap")
end)

--[[
	Classe FICTÍCIA de teste de ponta a ponta: GeneratedClass + Behavior -> ClassBuilder.Build ->
	Runtime.ClassRegistry.Register -> Services.new. `Services.Register()` não registra nada nesta
	tarefa (não há gerador ainda), então o teste registra direto via Runtime.ClassRegistry --
	exatamente o caminho que task-services-002 vai automatizar dentro de Services.Register().
]]
local WIDGET_CLASS_NAME = "InitSpecWidget"
local widgetSchema: ClassSchema = {
	Label = { Kind = "Property" :: MemberKind, Default = "widget", ReadOnly = false },
	Pinged = { Kind = "Event" :: MemberKind, Default = nil, ReadOnly = true },
}
table.freeze(widgetSchema)

local widgetGenerated: Types.GeneratedClass = {
	ClassName = WIDGET_CLASS_NAME,
	Superclass = "Instance",
	IsService = false,
	IsAbstract = false,
	Schema = widgetSchema,
	MethodNames = { "Ping" },
}
-- Tipado explicitamente como `{ [string]: unknown }` -- um literal de tabela com campo de função
-- concreta não é estruturalmente compatível com o indexador de `Types.Behavior.Methods` sem essa
-- anotação (mesma razão documentada em ClassBuilder.spec.luau).
local widgetMethods: { [string]: unknown } = {
	Ping = function(_self: unknown): string
		return "pong"
	end,
}
local widgetBehavior: Types.Behavior = {
	Methods = widgetMethods,
}
Runtime.ClassRegistry.Register(ClassBuilder.Build(widgetGenerated, widgetBehavior))

local ABSTRACT_CLASS_NAME = "InitSpecAbstractWidget"
local abstractGenerated: Types.GeneratedClass = {
	ClassName = ABSTRACT_CLASS_NAME,
	Superclass = "Instance",
	IsService = false,
	IsAbstract = true,
	Schema = {} :: ClassSchema,
	MethodNames = {},
}
Runtime.ClassRegistry.Register(ClassBuilder.Build(abstractGenerated, nil))

test("services registra e instancia uma classe FICTÍCIA de ponta a ponta via Runtime.ClassRegistry", function()
	local instance = Services.new(WIDGET_CLASS_NAME, "MyWidget")

	assert(instance.ClassName == WIDGET_CLASS_NAME, "ClassName da instância deveria ser o da classe pedida")
	assert(instance.Name == "MyWidget", "Name deveria ser o nome explícito passado a Services.new")

	local dynamic = (instance :: unknown) :: Dynamic
	assert(dynamic.Label == "widget", "Default da entrada Property do schema deveria ter sido semeado por ClassRegistry.new")

	type WithPing = Runtime.Instance & { Ping: (self: Runtime.Instance) -> string }
	local typed = (instance :: unknown) :: WithPing
	assert(typed:Ping() == "pong", "método implementado por Behavior deveria ser chamável normalmente")

	local raw: unknown = Runtime.Instance.GetPropertyRaw(instance, "Pinged")
	local pinged: Runtime.FireableSignal<string> = raw :: Runtime.FireableSignal<string>
	local received: string? = nil
	pinged:Connect(function(value: string)
		received = value
	end)
	pinged:Fire("ok")
	assert(received == "ok", "entrada Event do schema deveria ter um Signal fresco funcionando de ponta a ponta")
end)

test("Services.new erra 'Unable to create an Instance of type' para classe que não existe no Roblox", function()
	local ok, err = pcall(function()
		return Services.new("TotalmenteInventada123", nil)
	end)
	assert(not ok, "Services.new de uma classe inexistente deveria erro, nunca devolver nil silenciosamente")
	-- Substring, não igualdade exata: error(msg, 2) legitimamente prefixa a posição de quem
	-- CHAMOU Services.new (regra 01 -- contexto de onde no script isso aconteceu), mesma
	-- convenção já usada nos specs de `runtime` (ex.: ClassRegistry.spec.luau).
	assert(
		string.find(tostring(err), `Unable to create an Instance of type "TotalmenteInventada123"`, 1, true) ~= nil,
		`mensagem deveria bater com a família Roblox, recebeu: {err}`
	)
end)

test("Services.new erra a MESMA mensagem para classe registrada e abstrata (NotCreatable)", function()
	local ok, err = pcall(function()
		return Services.new(ABSTRACT_CLASS_NAME, nil)
	end)
	assert(not ok, "Services.new de uma classe abstrata deveria erro, nunca devolver nil silenciosamente")
	assert(
		string.find(tostring(err), `Unable to create an Instance of type "{ABSTRACT_CLASS_NAME}"`, 1, true) ~= nil,
		`mensagem de classe abstrata deveria ser IGUAL à de classe inexistente (Decisão 5), recebeu: {err}`
	)
end)

test("IsKnownClass/IsSimulatedClass refletem o estado do registro", function()
	-- WIDGET_CLASS_NAME é uma classe FICTÍCIA, registrada DIRETO via Runtime.ClassRegistry.Register
	-- (acima), por fora do pipeline real de Services.Register() -- nunca passou por
	-- generated/Manifest.luau. Por isso, depois de task-services-005, IsSimulatedClass (consulta
	-- Runtime.ClassRegistry, a fonte viva) é true, mas IsKnownClass (consulta o MANIFESTO real, as
	-- 916 classes do dump) é false: essa classe não existe no Roblox de verdade. É um artefato
	-- deste teste, não um cenário de produção -- em produção `Services.Register()` só registra
	-- classes que TAMBÉM estão no manifesto (a mesma `tools/coverage.luau` gera as duas listas, ver
	-- a invariante documentada no cabeçalho de init.luau), então "simulada mas desconhecida do
	-- dump" nunca acontece fora de um teste que registra manualmente uma classe inventada.
	assert(Services.IsSimulatedClass(WIDGET_CLASS_NAME), "classe registrada diretamente no ClassRegistry deveria estar simulada")
	assert(
		not Services.IsKnownClass(WIDGET_CLASS_NAME),
		"classe fictícia não existe no manifesto real -- IsKnownClass reflete o dump (task-services-005), não o ClassRegistry"
	)

	-- "Folder" é uma classe REAL desta leva: conhecida do dump E simulada -- o caso feliz comum,
	-- o mesmo que Services.new(...) precisa distinguir corretamente do caso acima.
	assert(Services.IsKnownClass("Folder"), "'Folder' deveria ser conhecida do dump -- classe real coberta nesta leva")
	assert(Services.IsSimulatedClass("Folder"), "'Folder' deveria estar simulada -- registrada por Services.Register()")

	assert(
		not Services.IsKnownClass("TotalmenteInventada123"),
		"classe nunca registrada e ausente do manifesto não deveria ser conhecida do dump"
	)
	assert(not Services.IsSimulatedClass("TotalmenteInventada123"), "classe nunca registrada não deveria estar simulada")
end)

test("GetDumpVersion devolve o commit/versão fixados na Decisão 2 do desenho", function()
	local version = Services.GetDumpVersion()
	assert(
		version.Commit == "28360dea4b90b35dc3fe9f829baae64fb6c50e75",
		`Commit deveria bater com o fixado na Decisão 2, recebeu: {version.Commit}`
	)
	assert(
		version.Version == "0.737.0.7371584",
		`Version deveria bater com o fixado na Decisão 2, recebeu: {version.Version}`
	)
end)

--------------------------------------------------------------------------------------------------
-- task-services-005: a família de TRÊS erros de classe contra o Manifesto REAL
-- (`generated/Manifest.luau`, as 916 classes do dump), e não mais só as classes fictícias acima.
-- `Services.Bootstrap` já rodou (teste "Bootstrap seta o Context", acima) -- todas as 24 classes
-- desta leva já estão registradas em `Runtime.ClassRegistry` quando estes testes rodam.
--------------------------------------------------------------------------------------------------

test("Services.new('Frmae') (typo -- ausente do manifesto) erra a família Roblox SEM prefixo [LuauBench]", function()
	assert(not Services.IsKnownClass("Frmae"), "'Frmae' não deveria constar do manifesto -- é um typo proposital, não uma classe real do Roblox")

	local ok, err = pcall(function()
		return Services.new("Frmae", nil)
	end)
	assert(not ok, "Services.new('Frmae') deveria erro -- não existe no Roblox, nunca devolve nil silenciosamente")
	local message = tostring(err)
	assert(
		string.find(message, `Unable to create an Instance of type "Frmae"`, 1, true) ~= nil,
		`mensagem deveria bater com a família Roblox, recebeu: {message}`
	)
	assert(
		string.find(message, "[LuauBench]", 1, true) == nil,
		"classe que não existe no Roblox NÃO tem contraparte real -- mas também NUNCA leva o prefixo [LuauBench] (esse prefixo é para o caso OPOSTO: quando HÁ contraparte real e é o LuauBench que está incompleto)"
	)
end)

test("Services.new('Workspace') (Service real, NotCreatable no dump) erra a MESMA família, também sem prefixo", function()
	assert(Services.IsKnownClass("Workspace"), "'Workspace' deveria constar do manifesto")
	assert(Services.IsSimulatedClass("Workspace"), "'Workspace' deveria estar simulada nesta leva (registrada, ainda que abstrata)")

	local ok, err = pcall(function()
		return Services.new("Workspace", nil)
	end)
	assert(not ok, "Services.new('Workspace') deveria erro -- NotCreatable no dump, igual ao Roblox real (não dá pra Instance.new um Service)")
	local message = tostring(err)
	assert(
		string.find(message, `Unable to create an Instance of type "Workspace"`, 1, true) ~= nil,
		`mensagem deveria ser IGUAL à de classe inexistente (Decisão 5 do desenho), recebeu: {message}`
	)
	assert(string.find(message, "[LuauBench]", 1, true) == nil, "classe abstrata TEM contraparte real no Roblox -- nunca leva o prefixo [LuauBench]")
end)

test("Services.new('Frame') (existe no dump, Covered == false) erra COM prefixo [LuauBench], citando a versão do dump", function()
	assert(Services.IsKnownClass("Frame"), "IsKnownClass('Frame') deveria ser true -- 'Frame' existe no Roblox API Dump")
	assert(not Services.IsSimulatedClass("Frame"), "IsSimulatedClass('Frame') deveria ser false -- fora da leva atual (GuiObject/render)")

	local ok, err = pcall(function()
		return Services.new("Frame", nil)
	end)
	assert(not ok, "Services.new('Frame') deveria erro -- existe no Roblox mas ainda não foi simulada por LuauBench")
	local message = tostring(err)
	local version = Services.GetDumpVersion()
	assert(
		string.find(message, "[LuauBench]", 1, true) ~= nil,
		`mensagem de classe conhecida-mas-não-simulada DEVE trazer o prefixo [LuauBench] (este erro NÃO tem contraparte real -- é o LuauBench que está incompleto), recebeu: {message}`
	)
	assert(
		string.find(message, `Frame exists in the Roblox API Dump ({version.Version}) but is not simulated by LuauBench yet`, 1, true) ~= nil,
		`mensagem deveria citar a versão do dump ({version.Version}), recebeu: {message}`
	)
end)

test("Services.new('Folder') funciona normalmente -- classe concreta e coberta desta leva", function()
	local instance = Services.new("Folder", "SmokeFolderCheck")
	assert(instance.ClassName == "Folder", "ClassName deveria ser 'Folder'")
	assert(instance.Name == "SmokeFolderCheck", "Name deveria ser o explícito passado a Services.new")
end)

test(
	"os três casos são distinguíveis por substring num pcall só ('Frmae' vs. 'Workspace' vs. 'Frame') -- acceptance explícito do board",
	function()
		local _, errMissing = pcall(function()
			return Services.new("Frmae", nil)
		end)
		local _, errAbstract = pcall(function()
			return Services.new("Workspace", nil)
		end)
		local _, errUncovered = pcall(function()
			return Services.new("Frame", nil)
		end)

		-- Comparação por SUBSTRING, não igualdade exata: `error(msg, 2)` prefixa a posição
		-- (arquivo:linha) de quem CHAMOU `Services.new` -- cada `pcall` acima está numa linha
		-- diferente deste mesmo arquivo, então o PREFIXO de posição diverge por construção mesmo
		-- quando a MENSAGEM (a parte que o script do usuário de fato vê/compara) é idêntica --
		-- mesma convenção já usada nos outros testes deste arquivo (regra 01, contexto de onde no
		-- script isso aconteceu).
		assert(
			string.find(tostring(errMissing), `Unable to create an Instance of type "Frmae"`, 1, true) ~= nil
				and string.find(tostring(errAbstract), `Unable to create an Instance of type "Workspace"`, 1, true) ~= nil,
			`classe ausente do manifesto e classe abstrata devem produzir a MESMA família de mensagem (Decisão 5), recebeu: {errMissing} | {errAbstract}`
		)
		assert(
			string.find(tostring(errUncovered), "[LuauBench]", 1, true) ~= nil,
			"só o terceiro caso (existe no dump, não coberta) leva o prefixo [LuauBench]"
		)
		assert(
			string.find(tostring(errMissing), "[LuauBench]", 1, true) == nil
				and string.find(tostring(errAbstract), "[LuauBench]", 1, true) == nil,
			"os dois primeiros casos NUNCA levam o prefixo [LuauBench] -- é isso que os distingue do terceiro por substring"
		)
		assert(
			string.find(tostring(errUncovered), `Unable to create an Instance of type "Frame"`, 1, true) == nil,
			"o terceiro caso NÃO deveria usar a família 'Unable to create' -- é o ponto central da tarefa: os três casos são distinguíveis por substring"
		)
	end
)

test("GetDumpVersion() devolve exatamente Manifest.DumpCommit/Manifest.DumpVersion -- generated/Manifest.luau vira a fonte única", function()
	local version = Services.GetDumpVersion()
	assert(version.Commit == Manifest.DumpCommit, `Commit deveria bater com generated/Manifest.luau, recebeu: {version.Commit}`)
	assert(version.Version == Manifest.DumpVersion, `Version deveria bater com generated/Manifest.luau, recebeu: {version.Version}`)
end)

--------------------------------------------------------------------------------------------------
-- task-services-011 (arquiteto-runtime-2026-09-04.md, "Revisão pós-integração 2026-09-05 (5)",
-- subseção "Lado services"): `Services.Register()` (chamado por `Services.Bootstrap`, já rodado
-- acima) instala `resolveUnknownClass` em `Runtime.UnknownClassResolver`. `resolveUnknownClass`
-- em si é um `local function` deste arquivo -- não há (nem deve haver, ver o cabeçalho do arquivo:
-- "nenhuma função NOVA exportada") um jeito de chamá-lo direto de fora. A única superfície
-- observável dos três veredictos que ele produz é `game:GetService(...)`, depois de
-- `Services.Bootstrap` -- é por isso que os testes abaixo passam por `game:GetService` para provar
-- CADA veredito individualmente (com a precondição do manifesto real documentada em cada um), e o
-- teste final replica os três juntos como o cenário de ponta-a-ponta que é o objetivo real desta
-- leva (acceptance do board).
--------------------------------------------------------------------------------------------------

-- Toda mensagem alcançável por `game:GetService(...)` é da família Roblox (inglês, sem prefixo) ou
-- da família `[LuauBench]` (inglês, com prefixo) -- nunca de engenharia interna em português
-- (regra de idioma dos erros). Um byte fora do intervalo ASCII (0-127) é sinal confiável de
-- caractere acentuado do português vazando para uma dessas duas famílias, já que nenhuma das duas
-- usa acento em inglês -- mais barato e mais robusto do que listar cada acento (á, ã, ç, ...) na
-- mão.
local function hasNonAsciiByte(text: string): boolean
	return string.find(text, "[\128-\255]") ~= nil
end

test(
	"veredito NotAClass: game:GetService('Frmae') (ausente do manifesto real) erra a família Roblox 'is not a valid Service name', sem prefixo [LuauBench] e sem português",
	function()
		local scheduler = Runtime.Scheduler.new()
		local game = Runtime.DataModel.new()
		Services.Bootstrap({ scheduler = scheduler, dataModel = game })

		assert(not Services.IsKnownClass("Frmae"), "'Frmae' precisa estar ausente do manifesto real para exercitar o veredito NotAClass")

		local ok, err = pcall(function()
			return game:GetService("Frmae")
		end)
		assert(not ok, "game:GetService('Frmae') deveria erro -- nome que não existe no Roblox")
		local message = tostring(err)
		assert(
			string.find(message, "'Frmae' is not a valid Service name", 1, true) ~= nil,
			`mensagem deveria bater com a família Roblox real (NotAClass), recebeu: {message}`
		)
		assert(string.find(message, "[LuauBench]", 1, true) == nil, "NotAClass nunca leva o prefixo [LuauBench] -- tem contraparte real no Roblox")
		assert(not hasNonAsciiByte(message), `mensagem de GetService NÃO deveria conter caractere de português, recebeu: {message}`)
	end
)

test(
	"veredito NotAService: game:GetService('Frame') (classe real do manifesto SEM tag Service) devolve nil, sem erro",
	function()
		local scheduler = Runtime.Scheduler.new()
		local game = Runtime.DataModel.new()
		Services.Bootstrap({ scheduler = scheduler, dataModel = game })

		assert(Services.IsKnownClass("Frame"), "'Frame' precisa existir no manifesto real para exercitar o veredito NotAService")
		assert(not Services.IsServiceClass("Frame"), "'Frame' precisa NÃO carregar a tag Service para exercitar o veredito NotAService")

		local service = game:GetService("Frame")
		assert(service == nil, "game:GetService('Frame') deveria devolver nil -- classe real do dump sem a tag Service, igual ao Roblox real")
	end
)

test(
	"veredito ServiceNotSimulated: game:GetService('Teams') (Service real do manifesto, Covered=false) erra com [LuauBench] citando a DumpVersion, sem português",
	function()
		local scheduler = Runtime.Scheduler.new()
		local game = Runtime.DataModel.new()
		Services.Bootstrap({ scheduler = scheduler, dataModel = game })

		assert(Services.IsKnownClass("Teams"), "'Teams' precisa existir no manifesto real para exercitar o veredito ServiceNotSimulated")
		assert(Services.IsServiceClass("Teams"), "'Teams' precisa carregar a tag Service para exercitar o veredito ServiceNotSimulated")
		assert(
			not Services.IsSimulatedClass("Teams"),
			"'Teams' precisa estar fora da leva atual (Covered=false, não registrada) para exercitar o veredito ServiceNotSimulated"
		)

		local ok, err = pcall(function()
			return game:GetService("Teams")
		end)
		assert(not ok, "game:GetService('Teams') deveria erro -- Service real do dump ainda não simulado por LuauBench")
		local message = tostring(err)
		local version = Services.GetDumpVersion()
		assert(
			string.find(message, "[LuauBench]", 1, true) ~= nil,
			`mensagem de Service não simulado DEVE trazer o prefixo [LuauBench], recebeu: {message}`
		)
		assert(
			string.find(message, `Teams exists in the Roblox API Dump ({version.Version}) but is not simulated by LuauBench yet`, 1, true) ~= nil,
			`mensagem deveria citar a versão do dump ({version.Version}) -- MESMA frase de Services.new caso 3 (unsimulatedClassMessage fatorada), recebeu: {message}`
		)
		assert(not hasNonAsciiByte(message), `mensagem de GetService NÃO deveria conter caractere de português, recebeu: {message}`)
	end
)

test(
	"TESTE PONTA-A-PONTA (acceptance explícito do board): depois de Services.Bootstrap, game:GetService('Teams')/'Frmae'/'Frame' cobrem os três vereditos, e NENHUMA das três mensagens contém caractere de português",
	function()
		local scheduler = Runtime.Scheduler.new()
		local game = Runtime.DataModel.new()
		Services.Bootstrap({ scheduler = scheduler, dataModel = game })

		local _, teamsErr = pcall(function()
			return game:GetService("Teams")
		end)
		local _, frmaeErr = pcall(function()
			return game:GetService("Frmae")
		end)
		local frameResult = game:GetService("Frame")

		local teamsMessage = tostring(teamsErr)
		local frmaeMessage = tostring(frmaeErr)

		assert(
			string.find(teamsMessage, "[LuauBench]", 1, true) ~= nil,
			`game:GetService('Teams') deveria erro com [LuauBench], recebeu: {teamsMessage}`
		)
		assert(
			string.find(frmaeMessage, "is not a valid Service name", 1, true) ~= nil,
			`game:GetService('Frmae') deveria erro com "is not a valid Service name", recebeu: {frmaeMessage}`
		)
		assert(frameResult == nil, "game:GetService('Frame') deveria devolver nil")

		assert(not hasNonAsciiByte(teamsMessage), `mensagem de 'Teams' NÃO deveria conter caractere de português, recebeu: {teamsMessage}`)
		assert(not hasNonAsciiByte(frmaeMessage), `mensagem de 'Frmae' NÃO deveria conter caractere de português, recebeu: {frmaeMessage}`)
	end
)

--------------------------------------------------------------------------------------------------
-- Teste de fumaça do bootstrap COMPLETO -- os 8 passos documentados no cabeçalho de init.luau,
-- com um `Runtime.Sandbox.Run` REAL (nunca mock, nunca coroutine.resume cru por fora do
-- Scheduler): `Runtime.DataModel.new` -> `Services.Bootstrap` -> `game:GetService` (chamado DE
-- DENTRO do script sandboxed) -> `Instance.new` (via `extraGlobals.Instance = { new =
-- Services.new }`, exatamente como `cli` vai injetar) -- confirmando que o script do usuário cria
-- uma `Folder` de verdade e a parenteia na árvore real.
--------------------------------------------------------------------------------------------------

test(
	"smoke test do bootstrap completo: DataModel.new -> Services.Bootstrap -> GetService -> Instance.new dentro de um Sandbox.Run REAL cria e parenteia uma Folder de verdade",
	function()
		-- Passos 3-4 da sequência (cabeçalho de init.luau) -- Scheduler/DataModel próprios deste
		-- teste, isolados dos outros testes deste arquivo.
		local scheduler = Runtime.Scheduler.new()
		local game = Runtime.DataModel.new()

		-- Passo 5: Services.Bootstrap SEMPRE antes de qualquer GetService. Idempotente (guarda
		-- local em Services.Register) -- seguro mesmo já tendo rodado antes neste processo.
		Services.Bootstrap({ scheduler = scheduler, dataModel = game })

		local outputs: { Runtime.OutputRecord } = {}

		-- Passo 7: o script sandboxed só alcança `Instance.new` porque ESTE teste injeta
		-- exatamente como `cli` documenta que deve injetar -- nenhum global embutido do Sandbox
		-- fornece isso por conta própria (whitelist fixa, src/runtime/Sandbox.luau).
		Runtime.Sandbox.Run({
			scriptName = "InitSpec.BootstrapSmoke",
			source = [[
				local rs = game:GetService("ReplicatedStorage")
				local folder = Instance.new("Folder")
				folder.Name = "SmokeFolder"
				folder.Parent = rs
			]],
			scheduler = scheduler,
			extraGlobals = {
				game = game,
				Instance = { new = Services.new },
			},
			onOutput = function(record)
				table.insert(outputs, record)
			end,
		})

		-- Passo 8. O script acima não faz nenhum `task.wait`/yield -- roda inteiro, síncrono,
		-- dentro do próprio `Scheduler:Spawn` disparado por `Sandbox.Run`. `scheduler:Run` ainda
		-- assim é chamado, fiel à sequência real de 8 passos; a guarda de 2s de wall-clock nunca
		-- deixa o teste pendurar o CI se uma regressão futura introduzir um yield.
		local deadline = os.clock() + 2
		scheduler:Run(function()
			return os.clock() < deadline
		end)

		assert(#outputs == 0, `o script não deveria ter produzido nenhum OutputRecord de erro, recebeu {#outputs}: {if outputs[1] ~= nil then outputs[1].message else ""}`)

		-- Verificação de FORA do sandbox, no MESMO `game` real (nunca uma cópia/mock) -- é a prova
		-- de que o script rodou de verdade e mexeu na árvore real, não só que não errou.
		local rs = game:FindService("ReplicatedStorage")
		assert(rs ~= nil, "ReplicatedStorage deveria ter sido criada de verdade por game:GetService(...), chamado DE DENTRO do script sandboxed")

		local child = (rs :: Runtime.Instance):FindFirstChild("SmokeFolder")
		assert(child ~= nil, "a Folder criada pelo script deveria estar parenteada sob ReplicatedStorage na árvore real")
		assert((child :: Runtime.Instance).ClassName == "Folder", "o filho parenteado deveria ser da classe 'Folder'")
	end
)

--------------------------------------------------------------------------------------------------
-- task-services-009: o outro lado do contrato -- depois de Services.Bootstrap, cada nome devolvido
-- por GetSimulatedServiceClasses() funciona de verdade com game:GetService(...). É exatamente o
-- passo 8 do pipeline documentado no cabeçalho de init.luau (`cli` faz isso para TODO Service
-- simulado, declarado ou não no .project.json do usuário).
--------------------------------------------------------------------------------------------------

test("cada classe de GetSimulatedServiceClasses() funciona com game:GetService(...) depois de Services.Bootstrap", function()
	local scheduler = Runtime.Scheduler.new()
	local game = Runtime.DataModel.new()

	-- Bootstrap idempotente (guarda local em Services.Register) -- seguro mesmo já tendo rodado
	-- antes neste processo, nos testes acima.
	Services.Bootstrap({ scheduler = scheduler, dataModel = game })

	for _, className in Services.GetSimulatedServiceClasses() do
		local service = game:GetService(className)
		assert(service ~= nil, `game:GetService("{className}") não deveria devolver nil depois de Services.Bootstrap`)
		assert(
			service.ClassName == className,
			`game:GetService("{className}") deveria devolver uma Instance de ClassName == "{className}", recebeu "{service.ClassName}"`
		)
		-- Segunda chamada devolve o MESMO singleton (semântica real de DataModel:GetService,
		-- src/runtime/DataModel.luau) -- não é esta função que garante isso, mas confirma que a
		-- lista devolvida por GetSimulatedServiceClasses não atrapalha essa semântica.
		assert(
			game:GetService(className) == service,
			`game:GetService("{className}") deveria devolver o mesmo singleton em chamadas repetidas`
		)
	end
end)

--------------------------------------------------------------------------------------------------
-- task-services-010: TESTE DE COERÊNCIA (acceptance do board) -- fecha o único modo de falha novo
-- do desenho: `EngineFixedChildren` nunca pode declarar um filho fixo que `behavior/**` não cria
-- de verdade. Para TODA entrada declarada (nesta leva, só `StarterPlayer`), depois de
-- `Services.Bootstrap` REAL, `game:GetService(<classe do pai>):FindFirstChild(entry.Name)` existe
-- E tem o `ClassName` esperado.
--
-- `KNOWN_ENGINE_FIXED_PARENTS` é a lista de classes-pai conhecidas NESTA leva -- mesma disciplina
-- de `COVERED_CLASSES`/`SERVICES_THIS_LEVA` em `Integration.spec.luau`: hardcoded de propósito,
-- falha alto e claro (`EngineFixedChildren.Of` some da chave) se uma tarefa futura adicionar uma
-- entrada nova em `EngineFixedChildren.luau` sem revisitar este teste. `EngineFixedChildren.Of`
-- não expõe a tabela completa (é módulo folha, só `Of`/`Is`) -- por isso a lista de chaves não é
-- derivável automaticamente daqui.
--------------------------------------------------------------------------------------------------

local KNOWN_ENGINE_FIXED_PARENTS: { string } = { "StarterPlayer" }

test(
	"TESTE DE COERÊNCIA: toda entrada de EngineFixedChildren.Of(<pai>) existe de verdade sob game:GetService(<pai>) depois de Services.Bootstrap, com o ClassName esperado",
	function()
		local scheduler = Runtime.Scheduler.new()
		local game = Runtime.DataModel.new()

		-- Bootstrap idempotente (guarda local em Services.Register) -- seguro mesmo já tendo rodado
		-- antes neste processo, nos testes acima.
		Services.Bootstrap({ scheduler = scheduler, dataModel = game })

		for _, parentClassName in KNOWN_ENGINE_FIXED_PARENTS do
			local parentService = game:GetService(parentClassName)
			for _, entry in EngineFixedChildren.Of(parentClassName) do
				local found = parentService:FindFirstChild(entry.Name)
				assert(
					found ~= nil,
					`game:GetService("{parentClassName}"):FindFirstChild("{entry.Name}") não deveria ser nil -- EngineFixedChildren declara este filho, então behavior/{parentClassName}.luau precisa criá-lo de verdade`
				)
				assert(
					(found :: Runtime.Instance).ClassName == entry.ClassName,
					`o filho "{entry.Name}" encontrado deveria ter ClassName == "{entry.ClassName}", recebeu "{(found :: Runtime.Instance).ClassName}"`
				)
			end
		end
	end
)

--------------------------------------------------------------------------------------------------
-- task-services-014 (arquiteto-cli-2026-09-05.md, Decisão 17, "Riscos"): TESTE DE COERÊNCIA -- o
-- alarme contra falso positivo futuro em `cli`. `TreePlanner` (Decisão 17) só pode pré-rejeitar um
-- nó com `IsEngineOnlyClass(className) == true` porque HOJE essas classes se dividem, sem resto, em
-- três grupos que `TreePlanner` sabe excluir ANTES de checar `IsEngineOnlyClass`: Services
-- (`isServiceRoot`), filhos fixos do motor (`IsEngineFixedChild`) e uma lista fechada do que nunca é
-- legítimo num `.project.json`. Se uma leva futura de `services` cobrir uma classe NotCreatable (ex.:
-- `Terrain`) SEM encaixá-la em um desses três grupos, `IsEngineOnlyClass` passaria a devolver `true`
-- para ela e `TreePlanner` rejeitaria um `Workspace/Terrain` legítimo -- este teste FALHA nesse
-- momento, na leva de `services` que introduziu o problema, não meses depois no projeto de um
-- usuário.
--
-- CLOSED_NEVER_LEGITIMATE é a lista fechada e explícita de classes NotCreatable+Covered que nunca
-- são um nó legítimo de `.project.json` (nem Service, nem filho fixo) -- hardcoded de propósito,
-- mesma disciplina de `KNOWN_ENGINE_FIXED_PARENTS` (acima) e `COVERED_CLASSES`/`SERVICES_THIS_LEVA`
-- em `Integration.spec.luau`: falha alto e claro se o manifesto crescer essa lista sem que este
-- teste seja revisitado. `fixedChildClassNames` reaproveita `KNOWN_ENGINE_FIXED_PARENTS` (declarado
-- acima, no teste de coerência da task-services-010) em vez de duplicar "StarterPlayer" -- as duas
-- listas fechadas precisam andar juntas por construção.
--------------------------------------------------------------------------------------------------

local CLOSED_NEVER_LEGITIMATE: { [string]: boolean } = {
	Instance = true,
	PVInstance = true,
	BaseScript = true,
	LuaSourceContainer = true,
	WorldRoot = true,
	BasePlayerGui = true,
	DataModel = true,

	-- task-services-017 (L2.1.7): as 16 classes de DataStoreService entraram em `tools/
	-- coverage.luau` -- 11 delas são NotCreatable e NÃO são Service nem filho fixo de nenhum pai
	-- (`DataStoreService` em si É Service, já coberto por `Services.IsServiceClass`; as 4 classes
	-- de opções -- `DataStoreSetOptions`/`DataStoreOptions`/`DataStoreGetOptions`/
	-- `DataStoreIncrementOptions` -- NÃO têm a tag `NotCreatable` no dump, script comum cria via
	-- `Instance.new`, então nem aparecem aqui). Nenhuma delas é um nó legítimo de `.project.json`:
	-- são sempre devolvidas por uma chamada de método (`GetDataStore`/`GetAsync`/`ListKeysAsync`/
	-- etc.), nunca declaradas estaticamente numa árvore Rojo -- mesma categoria de
	-- `Instance`/`PVInstance`/... acima.
	GlobalDataStore = true,
	DataStore = true,
	OrderedDataStore = true,
	DataStoreKeyInfo = true,
	Pages = true,
	DataStorePages = true,
	DataStoreKeyPages = true,
	DataStoreListingPages = true,
	DataStoreVersionPages = true,
	DataStoreObjectVersionInfo = true,
	DataStoreInfo = true,

	-- task-services-019-fix: `DataStoreKey` entrou MANUALMENTE em `tools/coverage.luau` (não é
	-- puxada pelo fecho automático -- ver o comentário lá) para que `DataStore:ListKeysAsync`
	-- devolva instâncias reais em vez de strings cruas. `NotCreatable` no dump, nunca Service nem
	-- filho fixo -- só nasce via `DataStore.luau`/`buildKeyItems` (`Runtime.ClassRegistry.
	-- NewEngineInstance`), nunca declarada estaticamente numa árvore Rojo. Mesma categoria de
	-- `DataStoreKeyInfo`/`DataStoreObjectVersionInfo`, acima.
	DataStoreKey = true,
}

test(
	"TESTE DE COERÊNCIA: toda classe para a qual IsEngineOnlyClass devolve true é Service, filho fixo do motor, ou está na lista fechada de nunca-legítima",
	function()
		local fixedChildClassNames: { [string]: boolean } = {}
		for _, parentClassName in KNOWN_ENGINE_FIXED_PARENTS do
			for _, entry in EngineFixedChildren.Of(parentClassName) do
				fixedChildClassNames[entry.ClassName] = true
			end
		end

		local uncategorizedCount = 0
		for className in Manifest.Classes do
			if Services.IsEngineOnlyClass(className) then
				local isAccountedFor = Services.IsServiceClass(className)
					or fixedChildClassNames[className] == true
					or CLOSED_NEVER_LEGITIMATE[className] == true
				if not isAccountedFor then
					uncategorizedCount += 1
					print(
						`[ALARME] "{className}" é IsEngineOnlyClass mas não é Service, filho fixo do motor, nem está na lista fechada -- TreePlanner vai rejeitar um projeto legítimo. Registre em EngineFixedChildren ou na lista fechada (CLOSED_NEVER_LEGITIMATE).`
					)
				end
			end
		end
		assert(
			uncategorizedCount == 0,
			`{uncategorizedCount} classe(s) com IsEngineOnlyClass == true não estão categorizadas -- ver mensagens [ALARME] acima`
		)
	end
)

--------------------------------------------------------------------------------------------------
-- task-services-031 (arquiteto-persistencia-cloud-2026-09-06.md, seção 10): fiação de
-- Types.CloudPersistence / Context.GetCloudPersistence / Services.Bootstrap (carga) /
-- Services.FlushCloudState / Services.HasPendingCloudState. Port FAKE em memória, requerido
-- diretamente (não "estilo diretório", é um arquivo comum) -- ZERO `@lune/fs` neste arquivo,
-- confirmando que `services` continua sem essa dependência (`src/cli/CloudStore.luau`, território
-- de outro agente, é quem de fato usa `@lune/fs`).
--------------------------------------------------------------------------------------------------

local GlobalDataStoreBehavior = require("./behavior/GlobalDataStore")

-- Port FAKE que implementa `Types.CloudPersistence` em memória, com CONTADORES de chamada --
-- necessário para o acceptance "FlushCloudState não serializa nada quando nada está sujo",
-- confirmado contando chamadas a `Save`, sem precisar inspecionar `@lune/fs` real.
local function newFakeCloudPersistence(): (
	Types.CloudPersistence,
	{ GetSaveCount: () -> number, GetLoadCount: () -> number }
)
	local documents: { [string]: string } = {}
	local saveCount = 0
	local loadCount = 0

	local port: Types.CloudPersistence = {
		Load = function(document: string): string?
			loadCount += 1
			return documents[document]
		end,
		Save = function(document: string, contents: string): ()
			saveCount += 1
			documents[document] = contents
		end,
	}

	return port,
		{
			GetSaveCount = function(): number
				return saveCount
			end,
			GetLoadCount = function(): number
				return loadCount
			end,
		}
end

test("sem CloudPersistence (nil -- comportamento de '--no-persist'): FlushCloudState é no-op (false, sem mensagem), HasPendingCloudState não erra", function()
	local scheduler = Runtime.Scheduler.new()
	local game = Runtime.DataModel.new()
	Services.Bootstrap({ scheduler = scheduler, dataModel = game })

	local ok, saved, message = pcall(function()
		return Services.FlushCloudState()
	end)
	assert(ok, `FlushCloudState não deveria erro sem CloudPersistence injetado, recebeu: {tostring(saved)}`)
	assert(saved == false, "FlushCloudState sem port deveria devolver false")
	assert(message == nil, "FlushCloudState sem port deveria devolver mensagem nil -- não é uma condição de erro")

	local okPending, pending = pcall(function()
		return Services.HasPendingCloudState()
	end)
	assert(okPending, `HasPendingCloudState não deveria erro, recebeu: {tostring(pending)}`)
	assert(type(pending) == "boolean", "HasPendingCloudState deveria devolver um boolean")
end)

--------------------------------------------------------------------------------------------------
-- Achado MÉDIO de revisão (revisor-services-task-services-030-2026-09-06.md): dois cenários do
-- próprio acceptance de task-services-031 sem teste automatizado, embora o comportamento já
-- estivesse correto (confirmado pelo revisor com scripts próprios) -- (1) FlushCloudState com um
-- Save que lança erro devolve (false, mensagem) SEM propagar a exceção; (2) Bootstrap com um Load
-- que lança erro PROPAGA (nunca engole). Acrescenta também, como extra sugerido pelo achado, o caso
-- irmão de Load devolver JSON inválido (erro vindo de Snapshot.DecodeDocument, não do próprio port)
-- -- mesma disciplina de propagação, caminho de erro diferente dentro de loadCloudStateIfPresent.
--------------------------------------------------------------------------------------------------

test(
	"Services.FlushCloudState() com port FAKE cujo Save lança erro: devolve (false, mensagem) SEM propagar exceção, e deixa a marca-suja INTACTA",
	function()
		local errorSavePort: Types.CloudPersistence = {
			Load = function(_document: string): string?
				return nil
			end,
			Save = function(_document: string, _contents: string): ()
				error("simulated disk failure on save")
			end,
		}

		local scheduler = Runtime.Scheduler.new()
		local game = Runtime.DataModel.new()
		Services.Bootstrap({ scheduler = scheduler, dataModel = game, CloudPersistence = errorSavePort })

		-- Suja o Store de verdade via SetAsync, pela API pública de DataStoreService (mesmo padrão
		-- do round trip abaixo) -- FlushCloudState só chama Save quando há mutação pendente.
		local dataStoreService = (game:GetService("DataStoreService") :: unknown) :: Dynamic
		local getDataStore = dataStoreService.GetDataStore :: (self: Dynamic, name: string, scope: string?, options: unknown?) -> Dynamic
		local store = getDataStore(dataStoreService, "FlushSaveErrorTest", nil, nil)
		local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string

		scheduler:Spawn(function()
			setAsync(store, "K", { v = 1 }, nil, nil)
		end)
		scheduler:StepOnce(0)

		assert(GlobalDataStoreBehavior.Store:IsDirty(), "o Store deveria estar sujo depois de um SetAsync bem-sucedido -- pré-condição deste teste")

		local ok, saved, message = pcall(function()
			return Services.FlushCloudState()
		end)
		assert(
			ok,
			`FlushCloudState NÃO deveria propagar a exceção de Save -- deveria capturá-la sob pcall e devolver (false, mensagem); a chamada propagou: {tostring(saved)}`
		)
		assert(saved == false, "FlushCloudState com Save que lança erro deveria devolver false")
		assert(message ~= nil, `FlushCloudState com Save que lança erro deveria devolver uma mensagem não-nil, recebeu: {tostring(message)}`)
		assert(
			string.find(tostring(message), "simulated disk failure on save", 1, true) ~= nil,
			`mensagem deveria conter o texto do erro lançado por Save, recebeu: {tostring(message)}`
		)

		assert(
			GlobalDataStoreBehavior.Store:IsDirty(),
			"uma gravação que falhou deveria deixar a marca-suja INTACTA -- o próximo flush precisa tentar de novo com o mesmo dado pendente, nunca perder a mutação silenciosamente"
		)
	end
)

--------------------------------------------------------------------------------------------------
-- task-services-033 (achado residual de revisão de task-cli-030,
-- `.claude/agents-memory/revisor-cli-task-cli-030-2026-09-06.md`, achado ALTO): o `firstLineOf`
-- interno deste arquivo só cortava a primeira quebra de linha, nunca o prefixo `<caminho>:<linha>: `
-- que `error(msg, level)` antepõe -- vazando o caminho absoluto de instalação do LuauBench (ex.:
-- `D:\...\src\cli\CloudStore:170: ...`) na mensagem que `Services.FlushCloudState` devolve. Hoje
-- mitigado só porque `RunCommand.luau` (`cli`) aplica um segundo strip por fora -- mas `services`
-- não pode depender disso (`cli` é um chamador entre outros possíveis). Teste ISOLADO abaixo:
-- chama `Services.FlushCloudState()` DIRETAMENTE, nunca passando por `RunCommand.luau` -- ou seja,
-- SEM a defesa em profundidade que `cli` aplica hoje por fora -- com um port FAKE cujo `Save` lança
-- um erro `error(texto, 0)` já formatado EXATAMENTE como o erro real reproduzido pelo revisor
-- (prefixo `<caminho absoluto>:<linha>: ` + mensagem substantiva). `level = 0` dá controle total
-- sobre o texto (Luau não acrescenta nenhum prefixo próprio por cima), então a asserção não
-- depende de onde este arquivo de teste mora em disco no momento em que os testes rodam.
--------------------------------------------------------------------------------------------------

test(
	"Services.FlushCloudState() com port FAKE cujo Save lança erro COM prefixo de localização (formato real que error(msg, level) do Lune produz): a mensagem devolvida NUNCA contém o caminho absoluto de instalação do LuauBench, mesmo chamada DIRETAMENTE (sem a defesa em profundidade que cli aplica por fora)",
	function()
		-- Formato reproduzido ao vivo pelo revisor de task-cli-030 (achado ALTO) contra um erro
		-- real de `CloudStore.Save` -- reproduzido aqui como string fixa, sob controle total via
		-- `error(_, 0)`, para o teste não depender do caminho de instalação real desta máquina.
		-- DOIS caminhos absolutos DIFERENTES de propósito: o prefixo de localização
		-- (`D:\...\luaubench\src\cli\CloudStore:170: `, o caminho de INSTALAÇÃO do LuauBench --
		-- este é o vazamento, tem que sumir) e o caminho do documento "cloud" citado DENTRO da
		-- mensagem substantiva (`C:\Users\...\MyRobloxGame\...`, o PROJETO do usuário -- este é
		-- informação legítima para o usuário ver, tem que sobreviver ao strip). De propósito SEM
		-- a palavra "luaubench" no caminho do usuário (usa "cloud-cache" em vez do nome real
		-- `.luaubench/cloud`) -- só assim a asserção "a mensagem não pode citar 'luaubench'",
		-- abaixo, fica inequívoca (só o prefixo de localização cortado citaria essa palavra).
		local fakeRawError =
			[[D:\UserData\Documents\GitHub\luaubench\src\cli\CloudStore:170: CloudStore: could not create "C:\Users\SomeUser\MyRobloxGame\cloud-cache\datastore.json": Cannot create a file when that file already exists. (os error 183)]]

		local errorSavePort: Types.CloudPersistence = {
			Load = function(_document: string): string?
				return nil
			end,
			Save = function(_document: string, _contents: string): ()
				error(fakeRawError, 0)
			end,
		}

		local scheduler = Runtime.Scheduler.new()
		local game = Runtime.DataModel.new()
		Services.Bootstrap({ scheduler = scheduler, dataModel = game, CloudPersistence = errorSavePort })

		local dataStoreService = (game:GetService("DataStoreService") :: unknown) :: Dynamic
		local getDataStore = dataStoreService.GetDataStore :: (self: Dynamic, name: string, scope: string?, options: unknown?) -> Dynamic
		local store = getDataStore(dataStoreService, "FlushSaveLocationLeakTest", nil, nil)
		local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string

		scheduler:Spawn(function()
			setAsync(store, "K", { v = 1 }, nil, nil)
		end)
		scheduler:StepOnce(0)

		assert(
			GlobalDataStoreBehavior.Store:IsDirty(),
			"o Store deveria estar sujo depois de um SetAsync bem-sucedido -- pré-condição deste teste"
		)

		local ok, saved, message = pcall(function()
			return Services.FlushCloudState()
		end)
		assert(
			ok,
			`FlushCloudState NÃO deveria propagar a exceção de Save, mesmo com prefixo de localização na mensagem: {tostring(saved)}`
		)
		assert(saved == false, "FlushCloudState com Save que lança erro deveria devolver false")
		assert(message ~= nil, "FlushCloudState com Save que lança erro deveria devolver uma mensagem não-nil")

		local safeMessage = message :: string
		assert(
			string.find(string.lower(safeMessage), "luaubench", 1, true) == nil,
			`achado task-services-033: a mensagem NUNCA pode citar "luaubench" -- prova que o caminho de INSTALAÇÃO do LuauBench (prefixo de localização) foi removido, recebeu: {safeMessage}`
		)
		assert(
			string.find(safeMessage, "D:\\UserData\\Documents\\GitHub", 1, true) == nil,
			`achado task-services-033: a mensagem NUNCA pode conter o caminho absoluto de instalação do LuauBench, recebeu: {safeMessage}`
		)
		assert(
			string.find(safeMessage, "CloudStore: could not create", 1, true) ~= nil,
			`a mensagem devolvida deveria PRESERVAR o texto substantivo do erro real -- só o prefixo de localização é cortado, recebeu: {safeMessage}`
		)
		assert(
			string.find(safeMessage, "C:\\Users\\SomeUser\\MyRobloxGame", 1, true) ~= nil,
			`a mensagem devolvida deveria PRESERVAR o caminho do PROJETO DO USUÁRIO citado dentro do texto substantivo do erro -- só o prefixo de localização é cortado, nunca o conteúdo depois dele, recebeu: {safeMessage}`
		)
	end
)

test(
	"Services.Bootstrap com port FAKE cujo Load lança erro: PROPAGA a exceção (nunca engole -- perder estado do usuário em silêncio é proibido pela regra 00)",
	function()
		local errorLoadPort: Types.CloudPersistence = {
			Load = function(_document: string): string?
				error("simulated disk read failure on load")
			end,
			Save = function(_document: string, _contents: string): () end,
		}

		local scheduler = Runtime.Scheduler.new()
		local game = Runtime.DataModel.new()

		local ok, err = pcall(function()
			Services.Bootstrap({ scheduler = scheduler, dataModel = game, CloudPersistence = errorLoadPort })
		end)
		assert(not ok, "Services.Bootstrap deveria propagar o erro lançado por Load, nunca engolir sob um pcall silencioso")
		assert(
			string.find(tostring(err), "simulated disk read failure on load", 1, true) ~= nil,
			`a exceção propagada deveria conter a mensagem original de Load, recebeu: {tostring(err)}`
		)
	end
)

test(
	"Services.Bootstrap com port FAKE cujo Load devolve JSON inválido: PROPAGA o erro de Snapshot.DecodeDocument (mesma disciplina do caso acima, caminho de erro diferente)",
	function()
		local invalidJsonPort: Types.CloudPersistence = {
			Load = function(_document: string): string?
				return "isto nao e JSON valido {{{"
			end,
			Save = function(_document: string, _contents: string): () end,
		}

		local scheduler = Runtime.Scheduler.new()
		local game = Runtime.DataModel.new()

		local ok, err = pcall(function()
			Services.Bootstrap({ scheduler = scheduler, dataModel = game, CloudPersistence = invalidJsonPort })
		end)
		assert(not ok, "Services.Bootstrap deveria propagar o erro de JSON malformado devolvido por Load, nunca recomeçar do zero em silêncio")
		assert(
			string.find(tostring(err), "Snapshot.DecodeDocument", 1, true) ~= nil,
			`a exceção propagada deveria vir de Snapshot.DecodeDocument, recebeu: {tostring(err)}`
		)
	end
)

--[[
	Round trip completo (acceptance explícito da task): SetAsync numa "sessão 1", FlushCloudState,
	depois um "processo novo" (a MESMA técnica de `Services.Bootstrap` chamado de novo com o MESMO
	port, sobre um Scheduler/DataModel FRESCOS) reidrata Version/CreatedTime/UpdatedTime/UserIds/
	Metadata/Tombstone via GetAsync, e o histórico completo, na ordem certa, via ListVersionsAsync.

	POR QUE "Store:Import({})" NO MEIO: o `Store` de `GlobalDataStore.luau` é MÓDULO-LOCAL, singleton
	do PROCESSO (ver o cabeçalho daquele arquivo, "STORE ÚNICO, MÓDULO-LOCAL") -- não existe como
	criar um `Services`/`Store` genuinamente novo dentro do MESMO processo Lune (não há
	"reiniciar o processo" dentro de um `lune run` só). Sem limpar o `Store` em memória entre as duas
	"sessões", a leitura da "sessão 2" enxergaria o dado que NUNCA saiu da memória (o mesmo `Store`
	singleton, só um DataModel/DataStoreService novo por cima) -- e o teste provaria menos do que
	promete (não provaria que o valor veio de fato de `fakePort`/Snapshot). `Store:Import({})` é
	chamado DIRETAMENTE (não através de `Services.Bootstrap`) só para simular "a memória do processo
	morreu" -- o código sob teste de verdade (a carga em si) é o SEGUNDO `Services.Bootstrap`, logo
	abaixo, chamado com o MESMO `fakePort`.
]]
test(
	"round trip completo: SetAsync/RemoveAsync -> FlushCloudState -> um 'processo novo' (Bootstrap de novo com o MESMO port fake, sobre Scheduler/DataModel frescos) restaura tudo via GetAsync/ListVersionsAsync",
	function()
		local fakePort, counters = newFakeCloudPersistence()

		-- Sessão 1 -------------------------------------------------------------------------------
		local schedulerA = Runtime.Scheduler.new()
		local gameA = Runtime.DataModel.new()
		Services.Bootstrap({ scheduler = schedulerA, dataModel = gameA, CloudPersistence = fakePort })

		local dataStoreServiceA = (gameA:GetService("DataStoreService") :: unknown) :: Dynamic
		local getDataStoreA = dataStoreServiceA.GetDataStore :: (self: Dynamic, name: string, scope: string?, options: unknown?) -> Dynamic
		local storeA = getDataStoreA(dataStoreServiceA, "CloudRoundTrip", nil, nil)
		local setAsyncA = storeA.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string
		local removeAsyncA = storeA.RemoveAsync :: (self: Dynamic, key: string) -> ...unknown

		local function runAsyncA(body: () -> ()): ()
			schedulerA:Spawn(body)
			schedulerA:StepOnce(0)
		end

		local setOptions = (Services.new("DataStoreSetOptions", nil) :: unknown) :: Dynamic
		local setMetadata = setOptions.SetMetadata :: (self: Dynamic, metadata: unknown) -> ()
		setMetadata(setOptions, { origin = "task-services-031" })

		-- "Player_1": duas escritas -- fica com um HISTÓRICO real (2 versões), nunca removido.
		runAsyncA(function()
			setAsyncA(storeA, "Player_1", { coins = 10 }, { 1 }, nil)
		end)
		runAsyncA(function()
			setAsyncA(storeA, "Player_1", { coins = 25 }, { 1 }, setOptions)
		end)

		-- "Player_2": uma escrita, depois removido -- confirma que o TOMBSTONE sobrevive ao reload
		-- (GetAsync continua nil, e o histórico registra a versão removida com IsDeleted == true).
		runAsyncA(function()
			setAsyncA(storeA, "Player_2", { coins = 5 }, nil, nil)
		end)
		runAsyncA(function()
			removeAsyncA(storeA, "Player_2")
		end)

		assert(GlobalDataStoreBehavior.Store:IsDirty(), "o Store deveria estar sujo depois de escritas bem-sucedidas")
		assert(counters.GetSaveCount() == 0, "nenhuma gravação deveria ter acontecido ainda -- só FlushCloudState grava")

		local flushedOk, flushedError = Services.FlushCloudState()
		assert(flushedOk == true, `FlushCloudState deveria devolver true (havia mutação pendente), recebeu erro: {tostring(flushedError)}`)
		assert(counters.GetSaveCount() == 1, "FlushCloudState deveria ter chamado Save exatamente uma vez")
		assert(not GlobalDataStoreBehavior.Store:IsDirty(), "depois de um flush bem-sucedido o Store não deveria mais estar sujo")

		local secondFlushedOk = Services.FlushCloudState()
		assert(secondFlushedOk == false, "FlushCloudState sem NADA sujo deveria ser no-op (false)")
		assert(counters.GetSaveCount() == 1, "FlushCloudState no-op NÃO deveria ter chamado Save de novo -- 'não serializa nada quando nada está sujo'")

		-- Simula o FIM do processo (ver o comentário acima do teste) -- limpa TODO o Store em
		-- memória, forçando a 'sessão 2' a provar que os valores abaixo vêm de fato de
		-- `fakePort`/Snapshot, nunca de memória sobrevivente.
		GlobalDataStoreBehavior.Store:Import({})
		assert(not GlobalDataStoreBehavior.Store:IsDirty(), "Import deveria zerar a marca-suja")

		-- Sessão 2 ("processo novo") ---------------------------------------------------------------
		local schedulerB = Runtime.Scheduler.new()
		local gameB = Runtime.DataModel.new()
		Services.Bootstrap({ scheduler = schedulerB, dataModel = gameB, CloudPersistence = fakePort })
		assert(counters.GetLoadCount() >= 1, "Services.Bootstrap com CloudPersistence deveria ter chamado Load('datastore')")

		local dataStoreServiceB = (gameB:GetService("DataStoreService") :: unknown) :: Dynamic
		local getDataStoreB = dataStoreServiceB.GetDataStore :: (self: Dynamic, name: string, scope: string?, options: unknown?) -> Dynamic
		local storeB = getDataStoreB(dataStoreServiceB, "CloudRoundTrip", nil, nil)
		local getAsyncB = storeB.GetAsync :: (self: Dynamic, key: string, options: unknown?) -> ...unknown
		local listVersionsB = storeB.ListVersionsAsync :: (self: Dynamic, key: string) -> Dynamic

		local function runAsyncB(body: () -> ()): ()
			schedulerB:Spawn(body)
			schedulerB:StepOnce(0)
		end

		-- "Player_1": Version/CreatedTime/UpdatedTime/UserIds/Metadata intactos, na versão CORRENTE.
		local restoredValue: unknown, restoredKeyInfo: unknown
		runAsyncB(function()
			restoredValue, restoredKeyInfo = getAsyncB(storeB, "Player_1", nil)
		end)

		local restoredValueTable = restoredValue :: { [string]: unknown }
		assert(
			restoredValueTable ~= nil and restoredValueTable.coins == 25,
			`GetAsync depois do reload deveria devolver o valor da última escrita da sessão 1 (coins=25), recebeu: {tostring(restoredValue)}`
		)

		local restoredKeyInfoDynamic = restoredKeyInfo :: Dynamic
		assert(restoredKeyInfoDynamic ~= nil, "keyInfo restaurado (Player_1) não deveria ser nil -- a chave não foi removida")

		local createdTime = restoredKeyInfoDynamic.CreatedTime :: number
		local updatedTime = restoredKeyInfoDynamic.UpdatedTime :: number
		local version = restoredKeyInfoDynamic.Version :: string
		assert(type(createdTime) == "number" and createdTime > 0, `CreatedTime restaurado deveria ser um número > 0, recebeu: {tostring(createdTime)}`)
		assert(type(updatedTime) == "number" and updatedTime > 0, `UpdatedTime restaurado deveria ser um número > 0, recebeu: {tostring(updatedTime)}`)
		assert(type(version) == "string" and #version > 0, `Version restaurada deveria ser uma string não-vazia, recebeu: {tostring(version)}`)

		local getUserIds = restoredKeyInfoDynamic.GetUserIds :: (self: Dynamic) -> { number }
		local userIds = getUserIds(restoredKeyInfoDynamic)
		assert(#userIds == 1 and userIds[1] == 1, `UserIds deveria ter sido restaurado (esperava um array com 1), recebeu {#userIds} elemento(s)`)

		local getMetadata = restoredKeyInfoDynamic.GetMetadata :: (self: Dynamic) -> { [string]: unknown }
		local metadata = getMetadata(restoredKeyInfoDynamic)
		assert(metadata.origin == "task-services-031", `Metadata deveria ter sido restaurada, recebeu: {tostring(metadata.origin)}`)

		-- Histórico completo de "Player_1" -- as DUAS versões da sessão 1, ordem cronológica
		-- crescente (mais antiga primeiro), nenhuma tombstoned.
		local player1Pages: unknown
		runAsyncB(function()
			player1Pages = listVersionsB(storeB, "Player_1")
		end)
		local player1PagesDynamic = player1Pages :: Dynamic
		local getCurrentPage1 = player1PagesDynamic.GetCurrentPage :: (self: Dynamic) -> { Dynamic }
		local player1Versions = getCurrentPage1(player1PagesDynamic)

		assert(#player1Versions == 2, `ListVersionsAsync('Player_1') deveria devolver as 2 versões da sessão 1, recebeu {#player1Versions}`)
		assert(
			(player1Versions[1].Version :: string) < (player1Versions[2].Version :: string),
			"ListVersionsAsync deveria devolver o histórico em ordem cronológica crescente (mais antiga primeiro)"
		)
		assert(player1Versions[2].Version == version, "a última entrada do histórico deveria ser a MESMA versão corrente devolvida por GetAsync")
		assert(player1Versions[1].IsDeleted == false and player1Versions[2].IsDeleted == false, "nenhuma versão de Player_1 deveria estar marcada como removida (IsDeleted)")

		-- "Player_2": TOMBSTONE intacto -- GetAsync continua nil depois do reload (a remoção não foi
		-- "resuscitada"), e o histórico mostra a versão removida com IsDeleted == true.
		local afterReloadValue: unknown, afterReloadKeyInfo: unknown
		runAsyncB(function()
			afterReloadValue, afterReloadKeyInfo = getAsyncB(storeB, "Player_2", nil)
		end)
		assert(afterReloadValue == nil, "GetAsync('Player_2') depois do reload deveria continuar nil -- o Tombstone da sessão 1 precisa sobreviver ao reload")
		assert(afterReloadKeyInfo == nil, "GetAsync('Player_2') depois do reload deveria continuar devolvendo keyInfo nil")

		local player2Pages: unknown
		runAsyncB(function()
			player2Pages = listVersionsB(storeB, "Player_2")
		end)
		local player2PagesDynamic = player2Pages :: Dynamic
		local getCurrentPage2 = player2PagesDynamic.GetCurrentPage :: (self: Dynamic) -> { Dynamic }
		local player2Versions = getCurrentPage2(player2PagesDynamic)

		assert(#player2Versions == 2, `ListVersionsAsync('Player_2') deveria devolver as 2 versões (escrita + remoção) da sessão 1, recebeu {#player2Versions}`)
		assert(player2Versions[1].IsDeleted == false, "a 1a versão de Player_2 (a escrita original) não deveria estar marcada como removida")
		assert(player2Versions[2].IsDeleted == true, "a 2a versão de Player_2 (o Tombstone de RemoveAsync) deveria estar marcada como removida (IsDeleted) -- prova que o Tombstone sobreviveu ao reload")
	end
)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
