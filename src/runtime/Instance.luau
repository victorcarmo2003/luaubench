--!strict

--[[
	Classe base `Instance` do LuauBench: hierarquia (`Parent`/filhos), eventos universais
	(Changed/ChildAdded/ChildRemoved/AncestryChanged/Destroying) e propriedade genérica.

	É a única classe cujo comportamento `runtime` codifica por nome (ver
	.claude/agents-memory/arquiteto-runtime-2026-09-04.md, seção "Instance.luau") — todo
	Service concreto que `services` registra herda desta base via `NewBase` + as funções de
	engenharia interna (GetPropertyRaw/SetPropertyRaw/SetClassChain), nunca reimplementando
	hierarquia/eventos do zero.

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

InstanceMeta.__index = function(self: Instance, key: string): unknown
	local data = getInternal(self)

	if key == "ClassName" then
		return data.className
	elseif key == "Name" then
		return data.name
	elseif key == "Parent" then
		return data.parent
	elseif key == "Changed" then
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

	local method = ((Methods :: unknown) :: { [string]: unknown })[key]
	if method ~= nil then
		return method
	end

	-- Métodos da classe concreta (Workspace:Raycast, Players:GetPlayerByUserId, ...), instalados
	-- por ClassRegistry.new via Instance.SetClassMethods — consultados DEPOIS dos métodos base de
	-- Instance (ordem de caminho quente, não de semântica: colisão entre os dois já é rejeitada
	-- com erro alto em SetClassMethods) e ANTES de data.properties (task-runtime-016, ver
	-- arquiteto-runtime-2026-09-04.md, seção "Revisão pós-integração 2026-09-04 (3)").
	if data.classMethods ~= nil then
		local classMethod = data.classMethods[key]
		if classMethod ~= nil then
			return classMethod
		end
	end

	-- DIVERGÊNCIA CONHECIDA E ACEITA (task-runtime-016): no Roblox real, ler um nome que a classe
	-- não declara ERRA ("X is not a valid member of Y", formato confirmado por citação verbatim
	-- em .claude/agents-memory/pesquisa-instance-member-access-2026-09-04.md). Aqui, sem um schema
	-- de propriedades por classe (que só o Roblox API Dump fornece e que `services` ainda não gera
	-- — fecha em task-runtime-018), uma propriedade genérica já setada é servida abaixo; se não
	-- houver propriedade com esse nome, a chave passa para a busca por filho (task-runtime-021,
	-- logo abaixo) antes de finalmente cair em nil.
	local propertyValue = data.properties[key]
	if propertyValue ~= nil then
		return propertyValue
	end

	--[[
		task-runtime-021 — resolução de filho por nome (ex.: `ReplicatedStorage.Modules.Combat`).
		Ver .claude/agents-memory/arquiteto-services-2026-09-05.md, seção "Decisão 4 — Como
		task-runtime-018 entra, e o buraco que ela abriria sozinha", "Ordem final de __index"
		(passos 6/7): sem isto, o modo estrito que task-runtime-018 liga transformaria todo acesso
		a filho por nome (o padrão mais frequente do ecossistema Roblox) num erro barulhento em
		código válido.

		HIPÓTESE NÃO CONFIRMADA CONTRA O ROBLOX REAL (mesmo protocolo de task-runtime-002 para a
		ordem de eventos de reparenting): a pesquisa que confirmaria isto, task-services-006
		("Confirmar contra o Roblox real: membro vs. filho no __index, ..."), está rodando em
		paralelo e NÃO tinha respondido no momento em que este código foi escrito. Duas coisas são
		assumidas aqui, nenhuma confirmada:
		(a) MEMBRO VENCE FILHO — por isso a checagem de `propertyValue` acima roda ANTES desta
		    busca por filho, e os campos fixos/sinais/métodos (passos 1-4, topo desta função) já
		    interceptam a chave antes de chegarmos aqui. Em colisão real (ex.: um filho chamado
		    "Name" ou "Destroy", ou uma propriedade genérica cujo nome também é o de um filho), a
		    hipótese é que a Instance real do Roblox devolveria o membro/propriedade, nunca o
		    filho — `FindFirstChild(key)` continua sendo a forma explícita de alcançar o filho
		    nesse caso (ver testes correspondentes em Instance.spec.luau).
		(b) A busca abaixo é não-recursiva e devolve exatamente o que `FindFirstChild(key)`
		    devolveria — comportamento reaproveitado, nunca duplicado.

		Se task-services-006 devolver o oposto (filho vence membro, ou uma regra mais específica
		por tipo de membro), esta ordem muda e os testes que a fixam mudam junto — decisão de
		revisor-runtime/arquiteto, não assumida por esta tarefa.

		Custo de performance aceito nesta fase: esta busca é uma varredura LINEAR sobre os filhos
		(Methods.FindFirstChild) a cada miss de membro — o mesmo custo de uma chamada explícita a
		FindFirstChild, agora pago também no caminho implícito de __index. Se isso aparecer como
		gargalo real (árvores com muitos filhos diretos e acesso por nome em laço quente), um
		índice por nome é tarefa própria; não otimizado aqui.
	]]
	return Methods.FindFirstChild(self, key)
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

	-- DIVERGÊNCIA CONHECIDA E ACEITA (task-runtime-016, mesma causa do fallback de __index acima):
	-- no Roblox real, escrever um nome que a classe não declara ERRA ("X is not a valid member of
	-- Y"); escrever propriedade conhecida-porém-somente-leitura erraria com a string CONFIRMADA
	-- "Unable to assign property {key}. Property is read only". Sem um schema de propriedades por
	-- classe (que só o Roblox API Dump fornece — `services` ainda não gera), LuauBench não
	-- consegue distinguir "nome desconhecido" de "propriedade genérica legítima" aqui: cria a
	-- propriedade em silêncio e dispara Changed. Fecha em task-runtime-018 quando o schema
	-- existir (ver .claude/agents-memory/pesquisa-instance-member-access-2026-09-04.md).
	--
	-- task-runtime-021 (resolução de filho por nome, só em __index — ver comentário lá acima) NÃO
	-- estende este fallback de propósito: escrever sobre um nome que hoje só existe como FILHO
	-- (ex.: `rs.Modules = 1` quando `rs.Modules` é uma pasta) continua caindo aqui e cria uma
	-- propriedade genérica homônima — o filho em si não é desparentado nem afetado, só passa a
	-- ficar "encoberto" em leituras futuras por essa propriedade nova (propriedade vence filho,
	-- mesma ordem de __index). O comportamento CORRETO para este caso no Roblox real — erra,
	-- substitui, ou é rejeitado de outra forma — depende do schema e é decisão de
	-- task-runtime-018 (ver .claude/agents-memory/arquiteto-services-2026-09-05.md, "Decisão 4",
	-- "Ordem final de __newindex", passo 7, e a nota logo abaixo dela). É também uma das perguntas
	-- em aberto na pesquisa task-services-006 ("o que acontece ao ESCREVER num nome que é filho").
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

		changed = SignalModule.new(),
		childAdded = SignalModule.new(),
		childRemoved = SignalModule.new(),
		ancestryChanged = SignalModule.new(),
		destroying = SignalModule.new(),
	}

	local self = (setmetatable({}, InstanceMeta) :: unknown) :: Instance
	internals[self] = data
	return self
end

function Instance.GetPropertyRaw(instance: Instance, name: string): unknown
	local data = getInternal(instance)
	return data.properties[name]
end

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

return Instance
