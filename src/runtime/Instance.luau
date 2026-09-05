--!strict

--[[
	Classe base `Instance` do LuauBench: hierarquia (`Parent`/filhos), eventos universais
	(Changed/ChildAdded/ChildRemoved/AncestryChanged/Destroying) e propriedade genérica.

	É a única classe cujo comportamento `runtime` codifica por nome (ver
	.claude/agents-memory/arquiteto-runtime-2026-09-04.md, seção "Instance.luau") — todo
	Service concreto que `services` registra herda desta base via `NewBase` + as funções de
	engenharia interna (GetPropertyRaw/SetPropertyRaw/SetClassChain/SetClassMethods/
	SetClassSchema), nunca reimplementando hierarquia/eventos do zero.

	task-runtime-018 (ver .claude/agents-memory/arquiteto-services-2026-09-05.md, "Decisão 3"/
	"Decisão 4"/"Decisão 6"): toda instância tem um MODO, definido por `classSchema` em `Internal`
	ser `nil` ou não. LENIENTE (`classSchema == nil`) é o comportamento histórico deste arquivo —
	propriedade genérica lida/escrita sem checagem. ESTRITO (`classSchema ~= nil`, instalado por
	`ClassRegistry.new` via `Instance.SetClassSchema`) replica o Roblox real: ler/escrever um nome
	fora do schema erra. Os dois modos coexistem por instância — nunca um interruptor global.

	Depende de Signal.luau, ThreadBroker.luau e, só no ramo (C) de WaitForChild com timeout em
	thread NÃO gerida por um Scheduler (ver comentário dentro do método), de `@lune/task` —
	dependência que não constava no comentário de cabeçalho original (achado BAIXO 6 da
	revisão pós-integração 2026-09-04, corrigido aqui). NÃO importa ClassRegistry.luau
	(evitaria um require circular: ClassRegistry.new resolve a cadeia de superclasses e grava
	via SetClassChain, IsA só consulta esse cache local) nem Scheduler.luau — essa decisão do
	arquiteto continua valendo mesmo após o patch de ThreadBroker.luau: é um módulo-folha sem
	nenhuma dependência de Scheduler.luau, então suspender/retomar por ele nunca exige saber
	quem é o driver concreto (ver .claude/agents-memory/arquiteto-runtime-2026-09-04.md, seção
	"Revisão pós-integração 2026-09-04 — contrato Wait/resume").
]]

local SignalModule = require("./Signal")
local ThreadBroker = require("./ThreadBroker")
local nativeTask = require("@lune/task")

type Signal<T...> = SignalModule.Signal<T...>
type FireableSignal<T...> = SignalModule.FireableSignal<T...>

export type Instance = {
	ClassName: string,
	Name: string,
	Parent: Instance?,

	Changed: Signal<string>,
	ChildAdded: Signal<Instance>,
	ChildRemoved: Signal<Instance>,
	AncestryChanged: Signal<Instance, Instance?>,
	Destroying: Signal<>,

	GetChildren: (self: Instance) -> { Instance },
	GetDescendants: (self: Instance) -> { Instance },
	FindFirstChild: (self: Instance, name: string, recursive: boolean?) -> Instance?,
	FindFirstChildOfClass: (self: Instance, className: string) -> Instance?,
	FindFirstChildWhichIsA: (self: Instance, className: string) -> Instance?,
	FindFirstAncestor: (self: Instance, name: string) -> Instance?,
	WaitForChild: (self: Instance, name: string, timeout: number?) -> Instance?,
	IsA: (self: Instance, className: string) -> boolean,
	IsDescendantOf: (self: Instance, ancestor: Instance?) -> boolean,
	IsAncestorOf: (self: Instance, descendant: Instance) -> boolean,
	ClearAllChildren: (self: Instance) -> (),
	Destroy: (self: Instance) -> (),
	GetFullName: (self: Instance) -> string,
}

-- Tabela ACHATADA (métodos próprios + herdados) e CONGELADA de uma classe concreta, COMPARTILHADA
-- por todas as instâncias dela (ver Instance.SetClassMethods, abaixo). `unknown` no valor é o
-- tipo honesto, mesmo motivo de `properties: { [string]: unknown }`: o valor tipado que
-- `services`/o script enxergam vem da interseção declarada por `services`
-- (`export type Workspace = Runtime.Instance & { Raycast: (self: Workspace, ...) -> ... }`), não
-- deste storage. Decisão do arquiteto em arquiteto-runtime-2026-09-04.md, seção "Revisão
-- pós-integração 2026-09-04 (3) — acesso a membro" (task-runtime-016).
export type ClassMethods = { [string]: unknown }

-- Descritor de UM membro (Property/Event/Callback) de uma classe concreta, gerado por `services`
-- a partir do Roblox API Dump — nunca escrito à mão por engenharia de `runtime`. `Kind` existe
-- porque Property/Event/Callback moram no mesmo espaço de nomes de __index/__newindex mas se
-- comportam diferente na escrita: evento erra ("is an event of X and cannot be reassigned"),
-- Callback é assinável por design (ex.: BindableFunction.OnInvoke), só Property consulta
-- `ReadOnly`. `Default` já vem parseado pelo gerador (número/bool/string reais, nunca a string
-- bruta do dump) — `unknown` é o tipo honesto pelo mesmo motivo de `ClassMethods`, acima. Formato
-- fechado na revisão de arquitetura de `services`: ver
-- .claude/agents-memory/arquiteto-services-2026-09-05.md, "Decisão 3 — Formato do descritor de
-- membro" (task-runtime-018; substitui o `PropertyDescriptor` provisório do desenho original).
export type MemberKind = "Property" | "Event" | "Callback"

export type MemberDescriptor = {
	Kind: MemberKind,
	Default: unknown,
	ReadOnly: boolean,
}

-- Tabela ACHATADA (membros próprios + herdados) e CONGELADA de uma classe concreta, COMPARTILHADA
-- por todas as instâncias dela (ver Instance.SetClassSchema, abaixo) — mesmo padrão de
-- `ClassMethods`. Uma instância SEM ClassSchema instalado (`classSchema == nil` em `Internal`)
-- permanece no modo LENIENTE de hoje: propriedade genérica lida/escrita livremente, sem erro para
-- nome desconhecido. Uma instância COM ClassSchema entra no modo ESTRITO: ler/escrever um nome
-- fora do schema erra, replicando o Roblox real ("X is not a valid member of Y"). Ver "Decisão 4 —
-- Como task-runtime-018 entra" no mesmo arquivo de arquitetura, "Ordem final de __index"/"Ordem
-- final de __newindex" — a ordem exata que InstanceMeta segue abaixo.
export type ClassSchema = { [string]: MemberDescriptor }

-- Estado privado por Instance — nunca reexposto na metatable pública (só alcançável por quem
-- faz `require("./Instance")` direto, isto é, `runtime`/`services`, nunca o script do usuário).
type Internal = {
	className: string,
	name: string,
	parent: Instance?,
	children: { Instance },
	properties: { [string]: unknown },
	classChain: { string },
	destroyed: boolean,
	-- `nil` = instância criada direto por NewBase, sem classe concreta (comportamento de hoje,
	-- ver Instance.SetClassMethods). Só ClassRegistry.new grava aqui, via SetClassMethods.
	classMethods: ClassMethods?,
	-- `nil` = instância LENIENTE (comportamento de hoje: propriedade genérica sem checagem
	-- nenhuma). Não-nil = instância ESTRITA para os membros que o schema declara
	-- (task-runtime-018). Só ClassRegistry.new grava aqui, via Instance.SetClassSchema — que, no
	-- mesmo passo, já semeia os defaults desta instância (incluindo um Signal.new() fresco por
	-- entrada Kind == "Event") direto em `properties`, sem passar por SetPropertyRaw (que
	-- dispararia Changed para cada default semeado).
	classSchema: ClassSchema?,

	changed: FireableSignal<string>,
	childAdded: FireableSignal<Instance>,
	childRemoved: FireableSignal<Instance>,
	ancestryChanged: FireableSignal<Instance, Instance?>,
	destroying: FireableSignal<>,
}

-- Chaves com `__mode = "k"`: uma Instance sem mais referências externas pode ser coletada pelo
-- GC junto com seu estado interno, sem precisar de um Destroy() explícito para não vazar.
-- `setmetatable` devolve um tipo com `@metatable`, estruturalmente "não relacionado" ao tipo
-- de dicionário puro `{ [Instance]: Internal }` aos olhos do checker — cast em duas etapas via
-- `unknown` (nunca `any`, regra 01) para reconciliar.
local internals: { [Instance]: Internal } =
	(setmetatable({}, { __mode = "k" }) :: unknown) :: { [Instance]: Internal }

local function getInternal(instance: Instance): Internal
	local data = internals[instance]
	if data == nil then
		error("objeto não é uma Instance válida do LuauBench (estado interno ausente)", 3)
	end
	return data
end

local function collectDescendantsPreOrder(self: Instance, out: { Instance }): ()
	local data = getInternal(self)
	for _, child in data.children do
		table.insert(out, child)
		collectDescendantsPreOrder(child, out)
	end
end

-- Verdadeiro se `candidate` for `self` ou descender de `self` — usado para recusar um
-- reparenting que criaria um ciclo (ex.: `a.Parent = a`, ou `a.Parent = a:GetChildren()[1]`).
local function isSelfOrDescendant(self: Instance, candidate: Instance): boolean
	local current: Instance? = candidate
	while current ~= nil do
		if current == self then
			return true
		end
		current = getInternal(current).parent
	end
	return false
end

local function setName(self: Instance, newName: string): ()
	local data = getInternal(self)
	if data.name == newName then
		return
	end
	data.name = newName
	data.changed:Fire("Name")
end

local function setParent(self: Instance, newParent: Instance?): ()
	local data = getInternal(self)

	if data.destroyed then
		error(`não é possível reparentar '{data.name}': a Instance já foi destruída (Destroy trava Parent)`, 3)
	end

	if newParent ~= nil and internals[newParent] == nil then
		error("Parent precisa ser uma Instance válida do LuauBench ou nil", 3)
	end

	if newParent == data.parent then
		-- Setar o mesmo Parent de novo é idempotente: nenhum evento dispara (mesma semântica
		-- observável do Roblox real, onde reatribuir o Parent atual não gera Changed/ChildAdded).
		return
	end

	if newParent ~= nil then
		if newParent == self then
			error(`não é possível parentear '{data.name}' a si mesmo`, 3)
		end
		if isSelfOrDescendant(self, newParent) then
			error(`não é possível parentear '{data.name}' sob seu próprio descendente`, 3)
		end
	end

	local oldParent = data.parent

	--[[
		HIPÓTESE NÃO CONFIRMADA CONTRA O ROBLOX REAL (risco sinalizado explicitamente pelo
		arquiteto em arquiteto-runtime-2026-09-04.md, seção "Riscos e decisões" /
		"Ordem de eventos Parent/Changed/ChildAdded/AncestryChanged" — task-runtime-002 exige
		este comentário no ponto exato do disparo). A pesquisa salva até agora
		(pesquisa-scheduler-lune-2026-09-04.md) cobre task.wait/Heartbeat/Stepped/WaitForChild,
		mas NÃO cobre esta ordem especificamente. A ordem abaixo é o PONTO DE PARTIDA assumido
		pelo desenho, não um fato confirmado:

			(1) unlink do pai antigo / link no pai novo (estado interno primeiro)
			(2) ChildRemoved:Fire(self) no pai antigo (se havia um)
			(3) ChildAdded:Fire(self) no pai novo (se há um)
			(4) AncestryChanged:Fire(instancia, parentAtualDaInstancia) em `self` primeiro,
			    depois em cada descendente de `self`, em pré-ordem (raiz primeiro)
			(5) Changed:Fire("Parent") só em `self` (nunca nos descendentes)

		revisor-runtime / pesquisador precisam validar esta ordem contra o comportamento
		documentado/observado do Roblox real antes de tratá-la como definitiva.
	]]

	-- (1) unlink/link
	if oldParent ~= nil then
		local oldParentData = getInternal(oldParent)
		local index = table.find(oldParentData.children, self)
		if index ~= nil then
			table.remove(oldParentData.children, index)
		end
	end
	data.parent = newParent
	if newParent ~= nil then
		local newParentData = getInternal(newParent)
		table.insert(newParentData.children, self)
	end

	-- (2) ChildRemoved no pai antigo
	if oldParent ~= nil then
		getInternal(oldParent).childRemoved:Fire(self)
	end

	-- (3) ChildAdded no pai novo
	if newParent ~= nil then
		getInternal(newParent).childAdded:Fire(self)
	end

	-- (4) AncestryChanged em self e em cada descendente, raiz (self) primeiro
	data.ancestryChanged:Fire(self, newParent)
	local descendants: { Instance } = {}
	collectDescendantsPreOrder(self, descendants)
	for _, descendant in descendants do
		local descendantData = getInternal(descendant)
		descendantData.ancestryChanged:Fire(descendant, descendantData.parent)
	end

	-- (5) Changed('Parent') só em self
	data.changed:Fire("Parent")
end

local Methods = {}

function Methods.GetChildren(self: Instance): { Instance }
	local data = getInternal(self)
	local copy = table.create(#data.children)
	for i, child in data.children do
		copy[i] = child
	end
	return copy
end

function Methods.GetDescendants(self: Instance): { Instance }
	local out: { Instance } = {}
	collectDescendantsPreOrder(self, out)
	return out
end

function Methods.FindFirstChild(self: Instance, name: string, recursive: boolean?): Instance?
	local data = getInternal(self)
	for _, child in data.children do
		if getInternal(child).name == name then
			return child
		end
	end
	if recursive then
		for _, child in data.children do
			local found = Methods.FindFirstChild(child, name, true)
			if found ~= nil then
				return found
			end
		end
	end
	return nil
end

function Methods.FindFirstChildOfClass(self: Instance, className: string): Instance?
	local data = getInternal(self)
	for _, child in data.children do
		if getInternal(child).className == className then
			return child
		end
	end
	return nil
end

function Methods.FindFirstChildWhichIsA(self: Instance, className: string): Instance?
	local data = getInternal(self)
	for _, child in data.children do
		if Methods.IsA(child, className) then
			return child
		end
	end
	return nil
end

function Methods.FindFirstAncestor(self: Instance, name: string): Instance?
	local current = getInternal(self).parent
	while current ~= nil do
		local currentData = getInternal(current)
		if currentData.name == name then
			return current
		end
		current = currentData.parent
	end
	return nil
end

function Methods.IsA(self: Instance, className: string): boolean
	local data = getInternal(self)
	for _, chainClassName in data.classChain do
		if chainClassName == className then
			return true
		end
	end
	return false
end

function Methods.IsDescendantOf(self: Instance, ancestor: Instance?): boolean
	if ancestor == nil then
		return false
	end
	local current = getInternal(self).parent
	while current ~= nil do
		if current == ancestor then
			return true
		end
		current = getInternal(current).parent
	end
	return false
end

function Methods.IsAncestorOf(self: Instance, descendant: Instance): boolean
	return Methods.IsDescendantOf(descendant, self)
end

function Methods.ClearAllChildren(self: Instance): ()
	local data = getInternal(self)
	local snapshot = table.create(#data.children)
	for i, child in data.children do
		snapshot[i] = child
	end
	-- Documentação oficial do Roblox: "Destroys all of an Instance's children, as if calling
	-- :Destroy() on each of them" — não é um simples desparentar, os filhos são destruídos.
	for _, child in snapshot do
		Methods.Destroy(child)
	end
end

function Methods.GetFullName(self: Instance): string
	-- Aproximação: inclui todos os ancestrais até a raiz (Parent == nil), sem o tratamento
	-- especial que o Roblox real faz para omitir `game`/DataModel do início da string —
	-- Instance.luau não conhece o conceito de DataModel (regra 02: runtime não conhece
	-- Service/DataModel por nome), então essa exclusão fica a cargo de DataModel.luau
	-- (task-runtime-005) se for necessária. Divergência documentada, não silenciosa.
	local parts: { string } = {}
	local current: Instance? = self
	while current ~= nil do
		local currentData = getInternal(current)
		table.insert(parts, 1, currentData.name)
		current = currentData.parent
	end
	return table.concat(parts, ".")
end

function Methods.Destroy(self: Instance): ()
	local data = getInternal(self)
	if data.destroyed then
		-- Destroy em cima de algo já destruído é no-op silencioso (mesma semântica do
		-- Roblox real: chamar Destroy() de novo não é erro).
		return
	end

	data.destroying:Fire()

	local childrenSnapshot: { Instance } = table.create(#data.children)
	for i, child in data.children do
		childrenSnapshot[i] = child
	end
	for _, child in childrenSnapshot do
		Methods.Destroy(child)
	end

	-- Desparenta por cima do caminho normal (self.Parent = nil), então os eventos
	-- ChildRemoved/AncestryChanged/Changed('Parent') disparam com a mesma ordem documentada
	-- em setParent. `destroyed` só vira `true` DEPOIS deste desparentar, senão setParent
	-- rejeitaria a própria chamada por "instância já destruída".
	(self :: Instance).Parent = nil
	data.destroyed = true

	data.changed:DisconnectAll()
	data.childAdded:DisconnectAll()
	data.childRemoved:DisconnectAll()
	data.ancestryChanged:DisconnectAll()
	data.destroying:DisconnectAll()
end

-- Intervalo de poll usado só pelo ramo (C) de WaitForChild com timeout em thread NÃO gerida
-- — ver comentário dentro de Methods.WaitForChild sobre por que esse ramo ainda faz polling.
local WAIT_FOR_CHILD_POLL_INTERVAL = 0.01

function Methods.WaitForChild(self: Instance, name: string, timeout: number?): Instance?
	local existing = Methods.FindFirstChild(self, name)
	if existing ~= nil then
		return existing
	end

	local data = getInternal(self)

	-- (A) SEM timeout: inalterado, continua sendo o caminho de fidelidade máxima ao Roblox
	-- real (bloqueia de verdade, nunca retorna nil cedo). `childAdded:Wait()` num laço; a
	-- retomada agora passa por ThreadBroker.Resume automaticamente (patch de Signal.luau),
	-- sem este módulo precisar saber quem é o driver — liveThreads/ThreadError do Scheduler
	-- ficam corretos mesmo quando é este Wait() que conclui a thread.
	if timeout == nil then
		while true do
			local child = data.childAdded:Wait()
			if getInternal(child).name == name then
				return child
			end
		end
	end

	local co = coroutine.running()
	local driver = ThreadBroker.DriverOf(co)

	--[[
		RESOLVIDO (era achado GRAVE 1 da revisão pós-integração 2026-09-04 — ver
		.claude/agents-memory/revisor-runtime-signal-instance-scheduler-2026-09-04.md): o
		polling via `@lune/task.wait` nativo, usado incondicionalmente antes deste patch,
		competia com o laço síncrono de `Scheduler:Run()` pelo executor assíncrono do Lune e o
		timeout deixava de ser respeitado (chegava a não resolver em 2s de wall-clock para um
		timeout de 0.05s). A correção: distinguir se a thread chamadora é GERIDA por um
		Scheduler (adotada via ThreadBroker.Adopt, dentro de Spawn/Defer/Delay) e, se for,
		nunca usar timer nativo — delegar o "acorde em N segundos" para o próprio driver
		(`driver.WakeAfter`), que agenda na mesma fila que `Scheduler:Wait` já usa.
	]]

	-- (B) COM timeout, thread GERIDA: um único `coroutine.yield`; quem acorda é o driver, por
	-- ChildAdded (evento) ou WakeAfter (deadline) — o que vencer primeiro cancela o outro.
	-- Zero timer nativo do Lune envolvido, então os dois "schedulers" (o Scheduler.luau
	-- simulado e o executor assíncrono do Lune) deixam de competir pelo mesmo timeout.
	if driver ~= nil then
		local settled = false
		local found: Instance? = nil
		local cancelDeadline: (() -> ())? = nil
		local connection: SignalModule.Connection
		connection = data.childAdded:Connect(function(child: Instance)
			if settled or getInternal(child).name ~= name then
				return
			end
			settled = true
			found = child
			connection:Disconnect()
			if cancelDeadline ~= nil then
				cancelDeadline()
			end
			ThreadBroker.Resume(co, nil)
		end)
		-- task-runtime-020 (vazamento real fechado aqui, ver PENDÊNCIA DECLARADA em
		-- ThreadBroker.luau/Scheduler.luau deixada por task-runtime-011): se esta thread for
		-- cancelada (Scheduler:Cancel) enquanto ainda presa neste yield, a Connection acima
		-- nunca dispara nem é desconectada pelos dois caminhos normais logo abaixo -- sem este
		-- registro ela ficaria pendurada em `data.childAdded` para sempre. RunCleanups
		-- desconecta no MOMENTO do cancelamento, nunca espera ChildAdded disparar de novo (e
		-- nunca vai disparar por essa thread, já que Cancel fecha a coroutine em seguida).
		local unregisterCleanup = ThreadBroker.RegisterCleanup(co, function()
			connection:Disconnect()
		end)
		cancelDeadline = driver.WakeAfter(co, timeout :: number)
		coroutine.yield()
		-- Chegar aqui só é possível por resolução normal (match encontrado ou deadline
		-- vencido, ambos abaixo) -- nunca via Cancel/RunCleanups, que fecha a coroutine sem
		-- retomá-la. Desfaz o próprio registro de limpeza ANTES de qualquer Disconnect "pelo
		-- caminho normal" logo abaixo -- evita um Disconnect duplicado (inofensivo, mas
		-- redundante) se esta mesma thread terminar por outro caminho depois (ver
		-- ThreadBroker.RegisterCleanup, desregistro idempotente feito exatamente para isto).
		unregisterCleanup()
		if not settled then
			-- Quem acordou foi o deadline (WakeAfter), não o ChildAdded: desconecta a
			-- conexão pendente, senão ela ficaria viva esperando um filho que já deixou de
			-- importar para esta chamada.
			settled = true
			connection:Disconnect()
		end
		return if found ~= nil then found else Methods.FindFirstChild(self, name)
	end

	--[[
		(C) COM timeout, thread NÃO gerida por nenhum Scheduler (ex.: o chunk principal do
		próprio Lune — é exatamente o caso de Instance.spec.luau, que chama WaitForChild
		diretamente sem nenhum Scheduler:Spawn/Run envolvido). Sem um driver dono desta
		coroutine, suspendê-la com `coroutine.yield()` cru e esperar alguém de fora retomá-la
		é exatamente a classe de bug que este patch existe para eliminar (thread sem dono que
		ThreadBroker não consegue rotear) — então este ramo permanece fazendo polling via
		`task.wait` nativo do Lune sobre FindFirstChild, o código de antes do patch, linha por
		linha. Isso continua correto justamente porque, sem Scheduler simulado dirigindo um
		laço síncrono concorrente, não há dois timers competindo pelo mesmo executor
		assíncrono — a causa raiz do achado GRAVE 1 nunca se aplica aqui.
	]]
	local deadline = os.clock() + (timeout :: number)
	while os.clock() < deadline do
		local found = Methods.FindFirstChild(self, name)
		if found ~= nil then
			return found
		end
		local remaining = deadline - os.clock()
		local step = if remaining < WAIT_FOR_CHILD_POLL_INTERVAL then math.max(remaining, 0) else WAIT_FOR_CHILD_POLL_INTERVAL
		nativeTask.wait(step)
	end
	return Methods.FindFirstChild(self, name)
end

local SIGNAL_KEYS: { [string]: boolean } = {
	Changed = true,
	ChildAdded = true,
	ChildRemoved = true,
	AncestryChanged = true,
	Destroying = true,
}

-- Campos fixos que não são sinal nem método base, mas fazem parte da superfície fixa de Instance
-- para fins de colisão em Instance.SetClassMethods — ClassName/Name/Parent são interceptados à
-- mão em __newindex (setName/setParent/erro), não vêm de SIGNAL_KEYS nem da tabela Methods.
local FIXED_PROPERTY_KEYS: { [string]: boolean } = {
	ClassName = true,
	Name = true,
	Parent = true,
}

local InstanceMeta = {}

-- Ordem final fechada pelo arquiteto em .claude/agents-memory/arquiteto-services-2026-09-05.md,
-- "Decisão 4 — Como task-runtime-018 entra, e o buraco que ela abriria sozinha", "Ordem final de
-- __index" — seguida aqui literalmente, passo a passo.
InstanceMeta.__index = function(self: Instance, key: string): unknown
	local data = getInternal(self)

	-- Passo 1 — campos fixos. ClassName/Name/Parent NUNCA passam pelo schema: são tratados aqui,
	-- antes de qualquer olhada em `classSchema`, mesmo quando o schema de uma classe legitimamente
	-- os contém (ex.: o schema de "Instance" — ver Instance.SetClassSchema, que por isso NÃO
	-- rejeita essa "colisão" do jeito que SetClassMethods rejeitaria).
	if key == "ClassName" then
		return data.className
	elseif key == "Name" then
		return data.name
	elseif key == "Parent" then
		return data.parent
	end

	-- Passo 2 — sinais fixos de Instance.
	if key == "Changed" then
		return data.changed
	elseif key == "ChildAdded" then
		return data.childAdded
	elseif key == "ChildRemoved" then
		return data.childRemoved
	elseif key == "AncestryChanged" then
		return data.ancestryChanged
	elseif key == "Destroying" then
		return data.destroying
	end

	-- Passo 3 — métodos base de Instance.
	local method = ((Methods :: unknown) :: { [string]: unknown })[key]
	if method ~= nil then
		return method
	end

	-- Passo 4 — métodos da classe concreta (Workspace:Raycast, Players:GetPlayerByUserId, ...),
	-- instalados por ClassRegistry.new via Instance.SetClassMethods — consultados DEPOIS dos
	-- métodos base de Instance (ordem de caminho quente, não de semântica: colisão entre os dois
	-- já é rejeitada com erro alto em SetClassMethods) e ANTES do schema/propriedades, abaixo.
	if data.classMethods ~= nil then
		local classMethod = data.classMethods[key]
		if classMethod ~= nil then
			return classMethod
		end
	end

	-- Passos 5/6 — propriedade genérica, ramificando pelo MODO da instância (task-runtime-018):
	local classSchema = data.classSchema
	if classSchema ~= nil then
		-- (5) MODO ESTRITO: `key` é um membro que o schema declara -> devolve `data.properties[key]`
		-- mesmo que seja `nil` — é exatamente o caso que motivou o schema inteiro (ex.:
		-- Humanoid.SeatPart, ObjectValue.Value: propriedade válida com valor corrente nil, que uma
		-- tabela Lua não armazena, então presença em `properties` sozinha nunca serviria de schema).
		if classSchema[key] ~= nil then
			return data.properties[key]
		end
	else
		-- (6) MODO LENIENTE (`classSchema == nil`: instância criada por NewBase direto, ou a raiz
		-- do DataModel enquanto não for registrada por uma classe concreta) — comportamento de
		-- hoje, sem checagem nenhuma contra um schema que não existe para esta instância.
		local propertyValue = data.properties[key]
		if propertyValue ~= nil then
			return propertyValue
		end
	end

	--[[
		Passo 7 (task-runtime-021) — resolução de filho por nome, ex.:
		`ReplicatedStorage.Modules.Combat`. Sem isto, o modo estrito acima transformaria todo
		acesso a filho por nome (o padrão mais frequente do ecossistema Roblox) num erro barulhento
		em código válido.

		CONFIRMADO contra documentação oficial da Roblox (task-services-006, ver
		.claude/agents-memory/pesquisa-member-vs-child-2026-09-05.md, seção 1) — NÃO é mais
		hipótese (a versão anterior deste comentário, escrita por task-runtime-021, marcava isto
		como hipótese não confirmada; a pesquisa que a confirmaria rodou em paralelo e voltou antes
		deste patch). Citação literal do campo `description` do membro `FindFirstChild` da classe
		`Instance`, `Roblox/creator-docs`, `content/en-us/reference/engine/classes/Instance.yaml`:
		"Sometimes the Name of an object is the same as that of a property of its Parent. When
		using the dot operator, properties take precedence over children if they share a name." —
		MEMBRO VENCE FILHO é comportamento documentado oficialmente, não suposição do LuauBench; é
		por isso que os passos 1-6 acima rodam antes deste. `FindFirstChild(key)` continua sendo a
		forma explícita de alcançar o filho numa colisão dessas (é o próprio motivo, segundo a doc
		oficial, de FindFirstChild existir).

		A busca abaixo é NÃO-recursiva e devolve exatamente o que `FindFirstChild(key)` devolveria
		— comportamento reaproveitado, nunca duplicado.

		Custo de performance aceito nesta fase: esta busca é uma varredura LINEAR sobre os filhos
		(Methods.FindFirstChild) a cada miss de membro — o mesmo custo de uma chamada explícita a
		FindFirstChild, agora pago também no caminho implícito de __index. Se isso aparecer como
		gargalo real (árvores com muitos filhos diretos e acesso por nome em laço quente), um
		índice por nome é tarefa própria; não otimizado aqui.
	]]
	local child = Methods.FindFirstChild(self, key)
	if child ~= nil then
		return child
	end

	-- Passo 8 — fallback final, ramificando pelo mesmo MODO dos passos 5/6.
	if classSchema ~= nil then
		-- MODO ESTRITO: `key` não é membro do schema nem filho -> ERRO, replicando o Roblox real.
		-- String CONFIRMADA por citação verbatim de thread real (ver
		-- .claude/agents-memory/pesquisa-instance-member-access-2026-09-04.md, "Formato da
		-- mensagem"): `"HumanoidRootPart is not a valid member of Model \"Workspace.<username>\""`.
		-- A divergência que task-runtime-016 deixou registrada aqui (Roblox real erra, LuauBench
		-- devolvia nil) fica FECHADA para toda instância com schema instalado — só permanece,
		-- deliberadamente, no modo leniente logo abaixo.
		error(`{key} is not a valid member of {data.className} "{Methods.GetFullName(self)}"`, 2)
	end
	-- MODO LENIENTE: nome sem membro e sem filho continua devolvendo nil — preservado de propósito
	-- para instância sem ClassSchema instalado (opt-in por classe, ver ClassSchema acima e
	-- "Decisão 4"/"Por que o schema pode ser gradual sem risco" no desenho de services).
	return nil
end

InstanceMeta.__newindex = function(self: Instance, key: string, value: unknown): ()
	if key == "Parent" then
		setParent(self, value :: Instance?)
		return
	elseif key == "Name" then
		if typeof(value) ~= "string" then
			error(`Name precisa ser string, recebeu {typeof(value)}`, 2)
		end
		setName(self, value :: string)
		return
	end

	local data = getInternal(self)

	if key == "ClassName" then
		-- String CONFIRMADA contra o Roblox real (task-runtime-014, ver
		-- .claude/agents-memory/pesquisa-instance-member-access-2026-09-04.md, "Q1 parcial":
		-- property real-porém-readonly erra com mensagem específica confirmada).
		error("Unable to assign property ClassName. Property is read only", 2)
	elseif SIGNAL_KEYS[key] then
		-- APROXIMAÇÃO DE BOA-FÉ do LuauBench, string real do Roblox NÃO confirmada nesta sessão
		-- (pesquisa-instance-member-access-2026-09-04.md buscou ativamente e não achou; a melhor
		-- inferência dela, a família "is not a valid member of", foi rejeitada de propósito pelo
		-- arquiteto por ser enganosa aqui — {key} É um membro válido de {ClassName}. Ver
		-- arquiteto-runtime-2026-09-04.md, seção "Revisão pós-integração 2026-09-04 (3)", "Por
		-- que rejeitar a inferência do pesquisador para escrita sobre método").
		error(`Unable to assign property {key}. {key} is an event of {data.className} and cannot be reassigned`, 2)
	elseif ((Methods :: unknown) :: { [string]: unknown })[key] ~= nil then
		-- Mesma aproximação de boa-fé acima, para método BASE de Instance.
		error(`Unable to assign property {key}. {key} is a method of {data.className} and cannot be reassigned`, 2)
	elseif data.classMethods ~= nil and data.classMethods[key] ~= nil then
		-- Mesma aproximação de boa-fé acima, para método da CLASSE CONCRETA (NOVO —
		-- task-runtime-016 fecha a lacuna em que só métodos base eram protegidos, apontada na
		-- revisão (2), subseção "Pendência adjacente": sem isto o script do usuário conseguiria
		-- fazer `workspace.Raycast = nil`).
		error(`Unable to assign property {key}. {key} is a method of {data.className} and cannot be reassigned`, 2)
	end

	-- Passos 7/8/9 — propriedade genérica, ramificando pelo MODO da instância (task-runtime-018,
	-- mesmo split de InstanceMeta.__index acima). Ordem final: ver
	-- .claude/agents-memory/arquiteto-services-2026-09-05.md, "Decisão 4", "Ordem final de
	-- __newindex".
	local classSchema = data.classSchema
	if classSchema ~= nil then
		local descriptor = classSchema[key]
		if descriptor ~= nil then
			-- (7) MODO ESTRITO, `key` é membro do schema:
			if descriptor.Kind == "Event" then
				-- Evento de CLASSE (ex.: Players.PlayerAdded) — mesma aproximação de boa-fé já
				-- usada acima para os 5 sinais fixos de Instance: string real do Roblox para este
				-- caso não confirmada (ver comentário em SIGNAL_KEYS, acima).
				error(`Unable to assign property {key}. {key} is an event of {data.className} and cannot be reassigned`, 2)
			elseif descriptor.Kind == "Property" and descriptor.ReadOnly then
				-- String CONFIRMADA contra o Roblox real por convergência de múltiplos threads
				-- independentes do Developer Forum reportando exatamente esta frase para
				-- propriedades reais-porém-somente-leitura distintas (ver
				-- .claude/agents-memory/pesquisa-instance-member-access-2026-09-04.md, Q1).
				error(`Unable to assign property {key}. Property is read only`, 2)
			else
				-- Property gravável OU Callback (ex.: BindableFunction.OnInvoke) — assinável por
				-- design, sem erro (arquiteto-services-2026-09-05.md, "Decisão 6").
				data.properties[key] = value
				data.changed:Fire(key)
			end
			return
		end

		-- (8) MODO ESTRITO, `key` fora do schema (nem membro, nem sinal/método já tratados acima)
		-- -> ERRO, mesma família e mesma string confirmada usada no fallback de __index. Fecha,
		-- para toda instância com schema instalado, a divergência que task-runtime-016 deixou
		-- registrada aqui (Roblox real erra "X is not a valid member of Y", LuauBench criava
		-- propriedade genérica em silêncio).
		--
		-- Cobre também escrever sobre um nome que hoje só existe como FILHO (ex.: `rs.Modules = 1`
		-- quando `Modules` é uma pasta): task-services-006 confirma, por inferência forte a partir
		-- do mecanismo de atribuição de propriedade do Roblox real (que nunca consulta a lista de
		-- filhos — são estruturas internas separadas), que este caso cai na mesma família de erro,
		-- nunca cria propriedade nem afeta o filho (ver
		-- .claude/agents-memory/pesquisa-member-vs-child-2026-09-05.md, seção 1, "Limites e
		-- pegadinhas" — string exata para este cenário específico não confirmada literalmente,
		-- mas a família do erro sim).
		error(`{key} is not a valid member of {data.className} "{Methods.GetFullName(self)}"`, 2)
	end

	-- (9) MODO LENIENTE (`classSchema == nil`) — comportamento de hoje, preservado de propósito
	-- para instância sem ClassSchema instalado: cria propriedade genérica em silêncio e dispara
	-- Changed, mesmo para nome desconhecido ou nome que hoje só existe como filho.
	data.properties[key] = value
	data.changed:Fire(key)
end

local Instance = {}

function Instance.NewBase(className: string, name: string?): Instance
	local data: Internal = {
		className = className,
		name = if name ~= nil then name else className,
		parent = nil,
		children = {},
		properties = {},
		classChain = if className == "Instance" then { "Instance" } else { className, "Instance" },
		destroyed = false,
		classMethods = nil,
		classSchema = nil,

		changed = SignalModule.new(),
		childAdded = SignalModule.new(),
		childRemoved = SignalModule.new(),
		ancestryChanged = SignalModule.new(),
		destroying = SignalModule.new(),
	}

	--[[
		task-runtime-027 (dois achados GRAVE de revisor-runtime na revisão de task-runtime-026,
		ver .claude/agents-memory/revisor-runtime-whitelist-completa-2026-09-05.md): a partir de
		task-runtime-026, o Sandbox expõe `getmetatable`/`setmetatable`/`rawset`/`rawget` ao script
		do usuário (necessário para padrões OOP reais como ProfileStore). Sobre uma Instance que
		fosse uma tabela Luau comum (`setmetatable({}, InstanceMeta)`, o código deste módulo antes
		desta tarefa), um script comum conseguia: (1) ler `InstanceMeta` de verdade via
		`getmetatable(instancia)` — vazamento de detalhe interno impossível no Roblox real, onde
		Instance é userdata e `getmetatable(workspace) == nil`; (2) TROCAR a metatable de uma
		Instance já existente e compartilhada via `setmetatable(instancia, {})`, quebrando
		`__index`/`__newindex` para QUALQUER outro script/host que segure a mesma referência dali
		em diante; (3), independente dos dois acima, `rawset(instancia, chave, valor)`/`rawget`
		IGNORAM __index/__newindex por completo (não passam pela metatable) e gravavam/liam DIRETO
		na tabela crua da Instance — como essa tabela nasce e ficava vazia para sempre (todo estado
		real vive em `internals[self]`), uma única `rawset` bastava para que toda leitura NORMAL
		daquela chave (`instancia.Nome`) parasse de invocar `__index` (Lua só invoca `__index`
		quando a chave está ausente da tabela crua) — corrupção visível para QUALQUER código, dentro
		ou fora da thread atacante, que segurasse a mesma referência (exploit real do revisor:
		`rawset(target, "Name", "HIJACKED")`, `rawset(target, "Destroy", function() end)`).

		FIX INICIALMENTE TENTADO E REJEITADO, DOCUMENTADO AQUI PARA O PRÓXIMO AGENTE NÃO REPETIR O
		MESMO CAMINHO: a correção pedida pelo board era `InstanceMeta.__metatable = "..."` (fecha
		(1)/(2), convenção padrão Lua/Luau) SOMADA a `table.freeze(self)` no ponto de criação (fecha
		(3), mesma disciplina de SetClassMethods/SetClassSchema). Comprovado empiricamente (probes
		descartados, não fazem parte do repositório) que os DOIS são MUTUAMENTE EXCLUSIVOS sobre a
		MESMA tabela no Luau: `table.freeze(t)` recusa com
		"invalid argument #1 to 'freeze' (table has a protected metatable)" se a metatable atual de
		`t` já tiver `__metatable` setado; e `setmetatable`/`debug.setmetatable` (este último nem
		existe no Luau — só `info`/`traceback` em `debug`) sobre uma tabela JÁ congelada falha com
		"attempt to modify a readonly table" antes mesmo de chegar a essa checagem — não existe
		ordem de chamadas que produza as duas propriedades na MESMA tabela.

		FIX REAL: `self` deixa de ser uma tabela Luau e passa a ser USERDATA de verdade
		(`newproxy(true)`) — exatamente o que uma Instance É no Roblox real (regra 00: isto não é
		uma divergência de fidelidade, é uma correção QUE AUMENTA a fidelidade, fechando a lacuna
		"table fingindo ser Instance" que os dois achados exploraram). Nesse desenho:
		  - `rawset`/`rawget` sobre userdata erram nativamente "table expected, got userdata" —
		    mesma FAMÍLIA de erro que o Roblox real dá para `rawset(workspace, ...)` ("table
		    expected, got Instance"), sem precisar de `table.freeze` (que sequer se aplica a
		    userdata — não há tabela crua para congelar).
		  - `setmetatable(proxy, {})` erra nativamente "table expected, got userdata" — o Luau não
		    aceita userdata como primeiro argumento de `setmetatable` em NENHUM caso, protegido ou
		    não (verificado empiricamente) — fecha (2) sem precisar de `__metatable`.
		  - `getmetatable(proxy)` devolve exatamente o valor de `__metatable` que setamos abaixo
		    (mesma convenção do caso tabela, sem o conflito) — fecha (1).
		`newproxy(true)` cria uma metatable NOVA por chamada (não há como reaproveitar uma única
		metatable compartilhada para userdata, diferente do padrão anterior com `InstanceMeta`
		compartilhada) — custo aceito: uma tabela pequena (3 campos) a mais por Instance, desprezível
		perto do resto de `Internal` (5 Signals). `InstanceMeta.__index`/`__newindex` continuam
		sendo as MESMAS funções de sempre (toda a lógica dos passos 1-9 documentada acima, inalterada
		— só o objeto físico que carrega a metatable muda), só reatribuídas aqui por referência.
	]]
	local proxy = newproxy(true)
	local proxyMeta: { [string]: unknown } = (getmetatable(proxy) :: unknown) :: { [string]: unknown }
	proxyMeta.__index = InstanceMeta.__index
	proxyMeta.__newindex = InstanceMeta.__newindex
	proxyMeta.__metatable = "The metatable is locked"

	local self = (proxy :: unknown) :: Instance
	internals[self] = data
	return self
end

-- Via de engenharia abaixo do enforcement de ClassSchema — NUNCA consulta `data.classSchema`,
-- de propósito (Decisão 6 do desenho de services). É o que permite `services` instalar valores
-- sobre uma entrada `ReadOnly` (ex.: o Heartbeat do Scheduler sobre `RunService.Heartbeat`) e
-- `cli` guardar/ler `Script.Source` (fora do schema) sem passar pelo enforcement que
-- InstanceMeta.__index/__newindex aplicam ao script do usuário.
function Instance.GetPropertyRaw(instance: Instance, name: string): unknown
	local data = getInternal(instance)
	return data.properties[name]
end

-- Mesma via de engenharia de GetPropertyRaw, acima — nunca consulta o schema. Dispara Changed
-- normalmente (diferente da semeadura de defaults em SetClassSchema, que é silenciosa de
-- propósito): esta função representa uma MUDANÇA de propriedade feita por `services`/`cli`, não
-- o estado inicial de uma instância recém-criada.
function Instance.SetPropertyRaw(instance: Instance, name: string, value: unknown): ()
	local data = getInternal(instance)
	data.properties[name] = value
	data.changed:Fire(name)
end

function Instance.SetClassChain(instance: Instance, chain: { string }): ()
	local data = getInternal(instance)
	local copy = table.create(#chain)
	for i, className in chain do
		copy[i] = className
	end
	data.classChain = copy
end

-- Memoização da validação de SetClassMethods por IDENTIDADE da tabela de métodos (mapa fraco por
-- chave, mesmo padrão de `internals`, linha ~81 acima): ClassRegistry passa sempre a MESMA tabela
-- achatada+congelada para todas as instâncias de uma classe, então a varredura completa (abaixo)
-- roda uma vez por classe — instanciações seguintes da mesma classe só pagam este lookup.
local validatedClassMethodTables: { [ClassMethods]: boolean } =
	(setmetatable({}, { __mode = "k" }) :: unknown) :: { [ClassMethods]: boolean }

-- Chamada por ClassRegistry.new, DEPOIS de SetClassChain e ANTES de Initialize (mesma razão da
-- ordem decidida na revisão (2) para a cadeia de classes: a identidade de classe precisa estar
-- completa antes de qualquer código de `services` rodar, para que dentro do próprio Initialize
-- tanto `instance:IsA(ancestral)` quanto `instance:MetodoDaPropriaClasse()` já funcionem).
-- NÃO copia `methods`: guarda a REFERÊNCIA (uma tabela por classe, compartilhada por todas as
-- instâncias dela, nunca por instância). Erra alto (nunca deixa colisão vencer em silêncio) se:
-- a tabela não estiver congelada; algum valor não for função; alguma chave colidir com a
-- superfície fixa de Instance (ClassName/Name/Parent, os 5 sinais, os métodos base). Colisão é
-- bug do gerador de `services` e tem que estourar uma vez no load, nunca ser resolvida por ordem
-- de consulta em __index (task-runtime-016, arquiteto-runtime-2026-09-04.md, seção "Revisão
-- pós-integração 2026-09-04 (3)").
function Instance.SetClassMethods(instance: Instance, methods: ClassMethods): ()
	if validatedClassMethodTables[methods] == nil then
		if not table.isfrozen(methods) then
			error(
				"Instance.SetClassMethods: a tabela de métodos precisa estar congelada (table.freeze) antes de ser instalada — é compartilhada por todas as instâncias da classe e não pode ser mutável depois",
				2
			)
		end

		for key, value in methods do
			if typeof(value) ~= "function" then
				error(`Instance.SetClassMethods: o valor de '{key}' precisa ser uma função, recebeu {typeof(value)}`, 2)
			end
			if
				FIXED_PROPERTY_KEYS[key]
				or SIGNAL_KEYS[key]
				or ((Methods :: unknown) :: { [string]: unknown })[key] ~= nil
			then
				error(
					`Instance.SetClassMethods: a chave '{key}' colide com a superfície fixa de Instance (propriedade/evento/método base) — bug do gerador de services, corrigir lá`,
					2
				)
			end
		end

		validatedClassMethodTables[methods] = true
	end

	local data = getInternal(instance)
	data.classMethods = methods
end

local VALID_MEMBER_KINDS: { [string]: boolean } = {
	Property = true,
	Event = true,
	Callback = true,
}

-- Memoização da validação de SetClassSchema por IDENTIDADE da tabela de schema — mesmo padrão de
-- `validatedClassMethodTables`, acima: ClassRegistry passa sempre a MESMA tabela
-- achatada+congelada para todas as instâncias de uma classe, então a varredura completa roda uma
-- vez por classe.
local validatedClassSchemas: { [ClassSchema]: boolean } =
	(setmetatable({}, { __mode = "k" }) :: unknown) :: { [ClassSchema]: boolean }

-- Chamada por ClassRegistry.new, DEPOIS de SetClassChain/SetClassMethods e ANTES de Initialize
-- (mesma ordem e mesma razão já documentadas para SetClassMethods, acima). NÃO copia `schema`:
-- guarda a REFERÊNCIA (uma tabela por classe, compartilhada por todas as instâncias dela).
--
-- Mesma disciplina de SetClassMethods (validação memoizada por identidade, tabela precisa estar
-- congelada), MAS com uma diferença deliberada (arquiteto-services-2026-09-05.md, "Decisão 6",
-- item 3): NÃO rejeita colisão com a superfície fixa de Instance — o schema de "Instance" contém
-- legitimamente Name/Parent/ClassName/Changed, e InstanceMeta.__index/__newindex já tratam esses
-- nomes nos passos 1-2, antes de olhar o schema (ver acima). A validação aqui cobre só
-- congelamento e FORMA do descritor (Kind é um dos três valores válidos, ReadOnly é boolean) —
-- nunca o "o quê" do schema, que é responsabilidade do gerador de `services`.
--
-- Ao contrário de SetClassMethods (que só instala a referência), esta função também SEMEIA o
-- estado inicial da instância: para cada entrada do schema, grava o `Default` direto em
-- `data.properties` — ou, para `Kind == "Event"`, um `Signal.new()` FRESCO por instância (nunca
-- compartilhado da tabela congelada: um Signal é por instância, `Default` não serve pra isso,
-- arquiteto-services-2026-09-05.md, "Decisão 6", item 1). A semeadura roda SEM passar por
-- SetPropertyRaw de propósito — grava direto em `data.properties`, sem chamar `data.changed:Fire`
-- — porque o estado inicial de uma instância recém-criada não é uma "mudança" observável
-- (acceptance de task-runtime-018: "defaults do schema são semeados sem disparar Changed").
function Instance.SetClassSchema(instance: Instance, schema: ClassSchema): ()
	if validatedClassSchemas[schema] == nil then
		if not table.isfrozen(schema) then
			error(
				"Instance.SetClassSchema: a tabela de schema precisa estar congelada (table.freeze) antes de ser instalada — é compartilhada por todas as instâncias da classe e não pode ser mutável depois",
				2
			)
		end

		for key, descriptor in schema do
			if typeof(descriptor) ~= "table" then
				error(
					`Instance.SetClassSchema: o descritor de '{key}' precisa ser uma tabela (MemberDescriptor), recebeu {typeof(descriptor)}`,
					2
				)
			end
			if not VALID_MEMBER_KINDS[descriptor.Kind] then
				error(
					`Instance.SetClassSchema: Kind de '{key}' precisa ser "Property", "Event" ou "Callback", recebeu {tostring(descriptor.Kind)}`,
					2
				)
			end
			if typeof(descriptor.ReadOnly) ~= "boolean" then
				error(`Instance.SetClassSchema: ReadOnly de '{key}' precisa ser boolean, recebeu {typeof(descriptor.ReadOnly)}`, 2)
			end
		end

		validatedClassSchemas[schema] = true
	end

	local data = getInternal(instance)
	data.classSchema = schema

	for key, descriptor in schema do
		if descriptor.Kind == "Event" then
			data.properties[key] = SignalModule.new()
		else
			data.properties[key] = descriptor.Default
		end
	end
end

return Instance
