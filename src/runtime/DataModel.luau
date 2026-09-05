--!strict

--[[
	DataModel: raiz da árvore simulada, equivalente a `game` no Roblox real. Ver
	.claude/agents-memory/arquiteto-runtime-2026-09-04.md, seção "DataModel.luau" (desenho
	original) e a nota sobre a cadeia de classes deixada na seção "Revisão pós-integração
	2026-09-04 (2)" (linha ~763 — pendência explícita desta tarefa, task-runtime-005).

	Depende de Instance.luau (base + as funções de engenharia interna SetClassChain e
	SetClassMethods, nenhuma reexportada por init.luau) e ClassRegistry.luau (para
	consultar/instanciar o ClassDescriptor de um Service dentro de GetService). NÃO conhece
	nenhum nome de Service concreto (regra 02) — GetService/FindService operam só por
	`className` (string) e pelo que ClassRegistry já sabe sobre essa classe.

	DECISÃO task-runtime-023 (bug bloqueante achado por coder-services, ver
	.claude/agents-memory/arquiteto-runtime-2026-09-04.md, seção "Revisão pós-integração
	2026-09-05 (4) — `NotCreatable` vs. abstrata: dois construtores em `ClassRegistry`):
	`GetService` passou a chamar `ClassRegistryModule.NewEngineInstance` em vez de
	`ClassRegistryModule.new`. Toda Service do Roblox API Dump carrega a tag `NotCreatable`
	(traduzida para `ClassDescriptor.IsAbstract`) — e mesmo assim o motor cria o singleton; essa
	tag barra `Instance.new`/`ClassRegistry.new` (a via PÚBLICA, com a política de script), nunca
	a construção do motor. `Instance.new("Workspace")` CONTINUA errando pelo caminho do script
	(via `Services.new`, que passa por `ClassRegistry.new`) — só a construção interna que
	`GetService` faz é que muda de via.

	DECISÃO DE CADEIA DE CLASSE (a pendência que este módulo precisa resolver explicitamente,
	não deixar implícita): `DataModel.new()` cria a raiz por dentro de `runtime`, sem passar por
	`ClassRegistry.new` — e não deveria passar. Não existe (e não deve existir) um jeito de
	instanciar um segundo DataModel via `Instance.new`/`ClassRegistry.new`: replicação
	client/server com múltiplos DataModel está fora do escopo do projeto (ver desenho, seção "O
	que deliberadamente NÃO fazer agora"). Registrar "DataModel" em ClassRegistry só para ganhar
	a resolução automática de cadeia abriria exatamente a porta indesejada
	(`ClassRegistry.new("DataModel")` criando um segundo game root do nada). Por isso a cadeia
	real do Roblox (`DataModel` -> `ServiceProvider` -> `Instance`) é aplicada AQUI, à mão, via
	`Instance.SetClassChain`, logo na construção. Sem essa decisão explícita, a raiz nasceria só
	com o chain default `{"DataModel", "Instance"}` que `Instance.NewBase` monta para qualquer
	ClassName desconhecido do registro, e `dataModel:IsA("ServiceProvider")` mentiria — divergência
	silenciosa do Roblox real, onde isso é `true`.

	DECISÃO task-runtime-030 (`GetService`/`FindService` de classe desconhecida, ver
	.claude/agents-memory/arquiteto-runtime-2026-09-04.md, seção "Revisão pós-integração
	2026-09-05 (5) — `GetService` de classe desconhecida: o resolvedor injetado por `services`", e
	pesquisa em .claude/agents-memory/pesquisa-getservice-comportamento-2026-09-05.md):
	`ClassRegistry.Get(className) == nil` (a classe não está registrada em `ClassRegistry`) NÃO é
	mais um único caso de erro em português. É a *ausência* de informação, e `ClassRegistry`
	sozinho não tem como distinguir três realidades por trás dela: (1) o nome não é classe nenhuma
	do Roblox ("Frmae") — o Roblox real ERRA; (2) é classe real do dump mas sem a tag `Service`
	("Frame"/"Folder") — o Roblox real devolve `nil`, SEM erro; (3) é Service real do dump, só que
	ainda não coberta por `services` nesta leva — mensagem `[LuauBench]` de cobertura. Quem tem o
	dado que separa os três é só `services` (o manifesto gerado do API Dump) — nunca `runtime`
	(regra 02: `runtime` não lê o dump, não conhece nome de classe concreta). Por isso o dado chega
	via `UnknownClassResolver`, um ponteiro de função opaco que `services` instala (dentro de
	`Services.Register()`) e que este módulo só consulta quando `ClassRegistry.Get` devolve `nil`
	— nunca antes disso, e `runtime` nunca sabe de onde a função veio nem o que ela consulta por
	dentro.

	DIVERGÊNCIA DECLARADA: o erro real do Roblox "singleton serviceName already exists" (lançado
	quando um Service já existe pendurado em outro `Object`, fora da árvore de serviços) NÃO tem
	contraparte aqui — é inalcançável neste desenho, porque só `GetService` cria singleton e ele
	sempre parenteia direto sob a raiz (`self`, a própria `DataModel`); não existe caminho para um
	Service já simulado aparecer "em outro lugar" antes de `GetService` rodar.

	task-runtime-033 (ver .claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.1.8 —
	Dependência dura: `game:BindToClose` é de `runtime`"): `BindToClose` REGISTRA um callback
	(estado privado por instância, `bindToCloseCallbacks` abaixo -- mapa fraco por chave, nunca
	uma propriedade -- ver o porquê no comentário daquele storage) e `DataModel.
	RunBindToCloseCallbacks` DISPARA e ESPERA todos os callbacks registrados de uma raiz antes de
	devolver o controle -- inclusive quando eles próprios yieldam (`Scheduler:Wait` dentro do
	callback, o padrão real do ProfileStore: `while ... do task.wait() end` esperando jobs de
	save terminarem). Cada callback roda em sua própria thread do `Scheduler` recebido
	(`Scheduler:Spawn` -- erro dentro de um callback já sai por `ThreadError`, como qualquer
	outro erro de thread do Scheduler, sem impedir os demais de rodar nem propagar para quem
	chamou `RunBindToCloseCallbacks`). `RunBindToCloseCallbacks` NÃO é instalado como método de
	instância (script nenhum aciona o próprio encerramento) -- é chamado por quem controla o
	ciclo de vida do processo (hoje ninguém dentro de `runtime`; `cli`, numa tarefa futura, chama
	isto depois que o `Scheduler:Run()` principal retorna, antes de encerrar o processo de
	verdade).

	DIVERGÊNCIA DECLARADA (task-runtime-033): o Roblox real aplica um timeout de ~30s no
	encerramento (um callback que não retorna a tempo é interrompido). Esta leva NÃO simula esse
	timeout, de propósito -- decisão explícita, não uma omissão. Um callback que nunca yielda de
	volta (`while true do end`) trava o encerramento do LuauBench para sempre, o mesmo risco já
	aceito e documentado em Scheduler.luau para qualquer thread gerida. A escolha é deliberada:
	o caso de uso real que motivou esta tarefa (ProfileStore aguardando jobs de save) precisa
	rodar até o fim para persistir de verdade, e um timeout arbitrário cortaria exatamente o
	comportamento que este mecanismo existe para viabilizar. Revisitar isso (dar um teto de
	tempo real) exige decisão do arquiteto, não escolha unilateral de `coder-runtime`.

	task-runtime-034 (ver .claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.3.3 —
	Dependência descoberta: `game.JobId`"): o padrão real para um assinante de MessagingService
	ignorar o próprio eco compara `message.Data.JobId` com `game.JobId`. Antes desta tarefa,
	`game.JobId` devolvia `nil` (DataModel é leniente, sem `ClassSchema`) e o filtro só
	funcionava por acidente (`nil ~= nil`). `JobId`/`PlaceId`/`GameId`/`PlaceVersion` são membros
	REAIS do dump (Security None, tag ReadOnly, dump fixado 09-05d) -- instalados via
	`InstanceModule.SetReadOnlyRawProperties` (Instance.luau, task-runtime-034), NÃO via
	`ClassSchema`: `DataModel` continua leniente (decisão de cadeia de classe já fixada acima --
	não existe segundo caminho de construção que justificasse `SetClassSchema` aqui), e
	`SetReadOnlyRawProperties` dá só a estas quatro chaves a mesma proteção de escrita que
	`ClassSchema.ReadOnly` daria a uma instância estrita, sem flipar a raiz inteira para o modo
	estrito.

	DIVERGÊNCIA DECLARADA (task-runtime-034): `JobId` é gerado UMA vez por PROCESSO (constante de
	módulo, `PROCESS_JOB_ID` abaixo -- calculada quando este arquivo é `require`ado pela primeira
	vez, não a cada `DataModel.new()`), então muda a cada execução do LuauBench -- não há
	servidor/replicação real por trás dele para manter estável entre execuções, e duas raízes
	criadas NO MESMO processo (ex.: teste de isolamento em DataModel.spec.luau) compartilham o
	mesmo `JobId`, de propósito (um processo Lune == um servidor). `PlaceId`/`GameId`/
	`PlaceVersion` ficam fixos em `0` -- o valor que o próprio Roblox usa para um lugar não
	publicado, coerente com o LuauBench, que não tem "lugar" nenhum.
]]

local InstanceModule = require("./Instance")
local ClassRegistryModule = require("./ClassRegistry")
local UnknownClassResolverModule = require("./UnknownClassResolver")
local SchedulerModule = require("./Scheduler")

type Instance = InstanceModule.Instance

export type DataModel = Instance & {
	GetService: (self: DataModel, className: string) -> Instance?,
	FindService: (self: DataModel, className: string) -> Instance?,
	-- task-runtime-033 (dump: `Function BindToClose(function)`, Security None) -- só REGISTRA;
	-- quem dispara e espera os callbacks é `DataModel.RunBindToCloseCallbacks`, abaixo (não é
	-- método de instância -- script nenhum aciona o próprio encerramento).
	BindToClose: (self: DataModel, callback: () -> ()) -> (),
	-- task-runtime-034 (dump: Security None, ReadOnly [dump 09-05d]) -- ver seção no cabeçalho
	-- deste módulo.
	JobId: string,
	PlaceId: number,
	GameId: number,
	PlaceVersion: number,
}

-- Único literal desta string em todo o arquivo (constante nomeada) -- o `pesquisador` deu
-- confiança só MÉDIA à persistência exata desta string até a build do dump fixado (é texto
-- interno do motor C++, não faz parte do API Dump em si, logo não é verificável contra a fonte de
-- verdade do projeto). Se algum dia precisar corrigir, é uma linha só. Aspas SIMPLES em volta do
-- nome, "Service" com S maiúsculo, sem prefixo, SEM "[LuauBench]" -- ao contrário do caso (3),
-- este tem contraparte real confirmada no Roblox (ver pesquisa-getservice-comportamento, seção 1,
-- citação byte-a-byte de repro no DevForum: `'Doge' is not a valid Service name`).
local function notAValidServiceNameMessage(className: string): string
	return `'{className}' is not a valid Service name`
end

-- task-runtime-034: um dígito hexadecimal minúsculo aleatório -- bloco de construção de
-- `generateProcessGuid`, abaixo. `math.random` do Lune (0.10.5) já sai semeado de forma distinta
-- por processo -- CONFIRMADO empiricamente nesta tarefa (dois `lune run` isolados do mesmo script
-- imprimindo `math.random()` sozinho deram sequências diferentes, sem nenhum `math.randomseed`
-- explícito no código) -- é o que garante "JobId diferente entre processos" do acceptance sem
-- precisar semear manualmente aqui.
local function randomHexDigit(): string
	return string.format("%x", math.random(0, 15))
end

-- GUID no formato `8-4-4-4-12` (minúsculo, sem chaves) -- mesmo formato do `JobId`/
-- `GenerateGUID(false)` reais do Roblox (confirmado em
-- .claude/agents-memory/pesquisa-http-messaging-2026-09-05.md, item 6: exemplo literal da doc
-- oficial, `db454790-7563-44ed-ab4b-397ff5df737b`). NÃO é um UUIDv4 RFC 4122 exato -- não força os
-- bits de versão/variante -- suficiente para ser praticamente único por processo e para bater a
-- FORMA que um script eventualmente inspecione, nunca para uma prova criptográfica de unicidade.
local function generateProcessGuid(): string
	local segmentLengths = { 8, 4, 4, 4, 12 }
	local segments: { string } = {}
	for _, length in segmentLengths do
		local chars = table.create(length)
		for i = 1, length do
			chars[i] = randomHexDigit()
		end
		table.insert(segments, table.concat(chars))
	end
	return table.concat(segments, "-")
end

-- Gerado UMA vez por PROCESSO, no carregamento deste módulo -- nunca a cada `DataModel.new()`
-- (ver DIVERGÊNCIA DECLARADA no cabeçalho do arquivo). Todo `DataModel` criado neste processo
-- compartilha o mesmo valor.
local PROCESS_JOB_ID: string = generateProcessGuid()

-- task-runtime-033: estado privado de `BindToClose` por instância -- mapa fraco por chave (mesmo
-- padrão de `internals` em Instance.luau), NUNCA gravado como propriedade (não usa
-- `Instance.GetPropertyRaw`/`SetPropertyRaw`): `DataModel` é uma instância LENIENTE (sem
-- `ClassSchema` instalado), então uma propriedade raw ficaria alcançável em LEITURA E ESCRITA por
-- qualquer script pelo caminho comum de `__index`/`__newindex` leniente (Instance.luau, passos
-- 5/6/9) -- diferente do canal "_LuauBench..." que `services` usa sobre instâncias ESTRITAS (ver
-- .claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.0.2"), que só fica invisível porque
-- o schema da classe não declara aquele nome. Este mapa, por ser module-local (nunca exposto fora
-- deste arquivo), fecha esse buraco por construção: nenhum script alcança `bindToCloseCallbacks`
-- de jeito nenhum.
local bindToCloseCallbacks: { [Instance]: { () -> () } } =
	(setmetatable({}, { __mode = "k" }) :: unknown) :: { [Instance]: { () -> () } }

-- Cadeia real do Roblox (`game:IsA("ServiceProvider")` é `true` no client real) — ver decisão no
-- cabeçalho do módulo. "ServiceProvider" nunca precisa de `ClassDescriptor` próprio: `IsA` só
-- percorre esta lista literal (Instance.luau, `Methods.IsA`), nunca consulta `ClassRegistry`.
local DATA_MODEL_CLASS_CHAIN: { string } = { "DataModel", "ServiceProvider", "Instance" }

-- GetService/FindService são instalados via `Instance.SetClassMethods` — o mesmo mecanismo que
-- task-runtime-016 construiu para método de classe de `services` — em vez de fechamento solto
-- atribuído por cima da instância ou de entrada em `data.properties`. É a única forma de ficarem
-- protegidos contra sobrescrita pelo script do usuário (`game.GetService = nil` erra, igual a
-- qualquer outro método de Instance) e indistinguíveis de um método "de verdade" ao ler via
-- `__index`: atribuir direto na tabela crua (`rawset`) bypassaria `__newindex` para sempre (Lua só
-- invoca `__newindex` quando a chave ainda NÃO existe na tabela crua), então não seria de fato
-- protegido; guardar como propriedade genérica cairia na mesma lacuna que task-runtime-016 fechou
-- para método de classe (ver Instance.luau, comentário de `SetClassMethods`).
local DataModelMethods: InstanceModule.ClassMethods = {
	-- Ordem exigida pelo desenho (task-runtime-030): `ClassRegistry.Get` PRIMEIRO, sempre --
	-- nunca `FindFirstChildOfClass` antes disso (era o bug do sequestro, ver "Reordenação"
	-- abaixo). Só quando a classe não está registrada é que o `UnknownClassResolver` entra em
	-- jogo, e só ele decide entre erro (duas famílias distintas) e `nil`.
	GetService = function(self: Instance, className: string): Instance?
		local descriptor = ClassRegistryModule.Get(className)

		if descriptor ~= nil then
			-- Caso (2), ramo registrado: classe real do dump que não é Service -> nil, igual ao
			-- Roblox real (confirmado por fonte primária: devolve nil sem erro, nunca cria nada).
			-- Esta guarda também é a REORDENAÇÃO que fecha o sequestro: `FindFirstChildOfClass`
			-- só roda DEPOIS de saber que `className` é mesmo um Service -- um `Folder` criado
			-- pelo usuário direto sob `game` não é mais devolvido por
			-- `game:GetService("Folder")`, porque `Folder` está registrado com IsService=false e
			-- este ramo retorna nil antes de sequer olhar para os filhos da raiz.
			if not descriptor.IsService then
				return nil
			end

			local existing = self:FindFirstChildOfClass(className)
			if existing ~= nil then
				return existing
			end

			-- `ClassRegistry.NewEngineInstance` (task-runtime-023), não `ClassRegistry.new`: toda
			-- Service do dump é `NotCreatable`, e `.new` rejeitaria incondicionalmente por
			-- `IsAbstract`. `NewEngineInstance` é a via do motor -- mesma construção completa,
			-- sem a guarda de política -- e `runtime/DataModel.luau:GetService` é um dos
			-- chamadores legítimos listados no cabeçalho de ClassRegistry.luau. Sem `name`
			-- explícito -> Name cai para o ClassName por default (Instance.NewBase), replicando
			-- "Name == ClassName" do Roblox real.
			local service = ClassRegistryModule.NewEngineInstance(className, nil)
			service.Parent = self
			return service
		end

		-- `descriptor == nil`: a classe não está em ClassRegistry. Só agora o resolvedor de
		-- `services` entra em jogo -- runtime não sabe (nem precisa saber) o que ele consulta por
		-- dentro.
		local verdict = UnknownClassResolverModule.Resolve(className)
		if verdict == nil then
			-- Erro de ENGENHARIA INTERNA, em português (regra de idioma dos erros internos, mesmo
			-- padrão de src/services/Context.luau): só alcançável se ninguém chamou
			-- `Services.Register()`/`Services.Bootstrap()` antes -- e nesse estado NENHUMA classe
			-- está registrada, então `GetService("Workspace")` também cairia aqui.
			-- Inalcançável por script de usuário real: `cli` sempre faz o Bootstrap antes de
			-- rodar qualquer script.
			error(
				`GetService: nenhum resolvedor de classe desconhecida instalado -- Services.Register()/Services.Bootstrap() precisa ter rodado antes de qualquer GetService (não é possível classificar '{className}')`,
				2
			)
		end

		if verdict.Kind == "NotAService" then
			-- Caso (2), ramo NÃO registrado: mesmo destino do ramo registrado acima (nil, sem
			-- erro) -- só a fonte da informação muda (resolvedor em vez de descriptor).
			return nil
		end
		if verdict.Kind == "ServiceNotSimulated" then
			-- Caso (3): a única família com contraparte que NÃO existe no Roblox real -- a
			-- mensagem já vem PRONTA de `services` (prefixo "[LuauBench]" etc.); `runtime` nunca
			-- a reformata, só repassa.
			error(verdict.Message, 2)
		end
		-- `verdict.Kind == "NotAClass"` (só resta este terceiro caso): caso (1), família Roblox
		-- real, string fixada na constante do topo do arquivo.
		error(notAValidServiceNameMessage(className), 2)
	end,

	-- Mesmo gate de `GetService`, incluído de propósito nesta mesma tarefa (task-runtime-030):
	-- corrigir um e não o outro deixaria as duas irmãs divergentes. `FindService` NUNCA consulta
	-- o resolvedor e NUNCA erra -- no Roblox real ele já devolve `nil` tanto para "Service que
	-- ainda não foi criado" quanto para "não é Service", e um nome inválido é indistinguível
	-- desses dois pela própria assinatura (`Instance?`, sem exceção).
	FindService = function(self: Instance, className: string): Instance?
		local descriptor = ClassRegistryModule.Get(className)
		if descriptor == nil or not descriptor.IsService then
			return nil
		end
		-- Nunca cria: só devolve o singleton se ele já existir como filho direto da raiz.
		return self:FindFirstChildOfClass(className)
	end,

	-- task-runtime-033: só REGISTRA -- nunca dispara nada aqui dentro. `self` (a própria raiz) é
	-- a chave do mapa fraco `bindToCloseCallbacks`, isolando os callbacks de cada `DataModel.new()`
	-- (mesma disciplina de isolamento já testada para GetService/FindService, ver
	-- DataModel.spec.luau, "cada DataModel.new() é uma raiz independente").
	BindToClose = function(self: Instance, callback: () -> ()): ()
		if typeof(callback) ~= "function" then
			-- APROXIMAÇÃO DE BOA-FÉ: string exata do Roblox real para este caso NÃO confirmada
			-- nesta tarefa (fora do escopo pesquisado) -- família comum de erro de argumento
			-- inválido do próprio Luau, adaptada ao nome do parâmetro real do dump.
			error(`Invalid argument #1 to 'BindToClose' (function expected, got {typeof(callback)})`, 2)
		end
		local callbacks = bindToCloseCallbacks[self]
		if callbacks == nil then
			callbacks = {}
			bindToCloseCallbacks[self] = callbacks
		end
		table.insert(callbacks, callback)
	end,
} :: InstanceModule.ClassMethods
table.freeze(DataModelMethods)

local DataModel = {}

function DataModel.new(): DataModel
	-- Name default cai para "DataModel" (o próprio ClassName, comportamento padrão de
	-- `Instance.NewBase` quando `name` é nil) — LuauBench não tem o conceito de "nome do
	-- lugar/jogo" do Roblox Cloud. Se `cli` quiser expor o nome do projeto Rojo como Name da
	-- raiz, seta `dataModel.Name = ...` depois de criada (Name é gravável via `__newindex`,
	-- normalmente, como qualquer outra Instance).
	local instance = InstanceModule.NewBase("DataModel", nil)
	InstanceModule.SetClassChain(instance, DATA_MODEL_CLASS_CHAIN)
	InstanceModule.SetClassMethods(instance, DataModelMethods)
	-- task-runtime-034: ver DIVERGÊNCIA DECLARADA no cabeçalho do módulo -- `JobId` é a mesma
	-- constante de processo para toda raiz criada aqui; `PlaceId`/`GameId`/`PlaceVersion` são
	-- sempre `0`.
	InstanceModule.SetReadOnlyRawProperties(instance, {
		JobId = PROCESS_JOB_ID,
		PlaceId = 0,
		GameId = 0,
		PlaceVersion = 0,
	})
	return (instance :: unknown) :: DataModel
end

-- task-runtime-033: dispara e ESPERA todos os callbacks registrados via `BindToClose` na raiz
-- `dataModel`, usando `scheduler` para criar e drenar as threads deles -- ver a seção completa no
-- cabeçalho deste módulo (semântica, divergência do timeout de 30s, e por que isto não é método de
-- instância). No-op se nenhum callback foi registrado.
function DataModel.RunBindToCloseCallbacks(dataModel: DataModel, scheduler: SchedulerModule.Scheduler): ()
	local instance = (dataModel :: unknown) :: Instance
	local callbacks = bindToCloseCallbacks[instance]
	if callbacks == nil or #callbacks == 0 then
		return
	end

	-- Cada callback vira uma thread do `scheduler` recebido -- `Scheduler:Spawn` já roda
	-- sincronamente até o primeiro yield/término e já protege contra erro (sai por `ThreadError`,
	-- nunca propaga, nunca impede os handles seguintes de serem criados). `handles` guarda cada
	-- `thread` devolvida só para saber quando TODAS morreram -- `coroutine.status` é primitiva pura
	-- do Luau, não precisa de nenhuma API nova do Scheduler para consultar.
	local handles: { thread } = {}
	for _, callback in callbacks do
		table.insert(handles, scheduler:Spawn(callback))
	end

	local function anyStillAlive(): boolean
		for _, handle in handles do
			if coroutine.status(handle) ~= "dead" then
				return true
			end
		end
		return false
	end

	-- `Scheduler:Run(shouldContinue)` já drena delayed/waiting/deferred e pulsa Heartbeat/Stepped
	-- a cada tique -- exatamente o que um callback que faz `Scheduler:Wait(...)` precisa para
	-- acordar de novo. O laço para assim que `anyStillAlive()` vira falso, mesmo que
	-- `Scheduler:IsAlive()` continue verdadeiro por outro motivo alheio a esta chamada (ex.: uma
	-- Connection de Heartbeat esquecida por outro script) -- a condição de `Run` é um "E", então o
	-- primeiro dos dois a virar falso decide.
	scheduler:Run(anyStillAlive)
end

return DataModel
