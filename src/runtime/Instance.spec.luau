--!strict

--[[
	Teste da task-runtime-002 (classe base Instance: hierarquia + eventos + propriedade
	genérica). Cobre, na mesma tarefa da lógica que testa (regra 01): NewBase, reparenting +
	ordem dos eventos (ver comentário de risco em Instance.luau/setParent), GetChildren/
	GetDescendants, Find*, IsA/IsDescendantOf/IsAncestorOf, WaitForChild real (sem timeout
	bloqueando de verdade, com timeout expirando e com timeout resolvendo antes do prazo),
	propriedade genérica via GetPropertyRaw/SetPropertyRaw, ClearAllChildren e Destroy.

	Roda com `lune run src/runtime/Instance.spec.luau`. Depende do Signal.luau real
	(task-runtime-001) já presente em src/runtime/ no momento em que este teste foi escrito.
]]

local process = require("@lune/process")
local nativeTask = require("@lune/task")
local InstanceModule = require("./Instance")
local Scheduler = require("./Scheduler")
-- Módulo-folha interno do território (ver ThreadBroker.luau) -- não faz parte da API pública
-- reexportada por init.luau para services/cli, mas este é um teste de caixa-branca DENTRO do
-- próprio território runtime (mesmo padrão já usado em Integration.spec.luau/task-runtime-012):
-- precisa registrar uma segunda limpeza na MESMA thread para provar, de forma determinística,
-- que a Connection interna de WaitForChild já foi desconectada ANTES dela rodar (ver teste de
-- cancelamento abaixo, task-runtime-020).
local ThreadBroker = require("./ThreadBroker")

type Instance = InstanceModule.Instance

-- Helper usado só pelos testes NOVOS da task-runtime-016 (método de classe): permite escrever
-- sobre uma chave que a metatable pública de `Instance` não declara estaticamente (ex.: um nome
-- de método de classe concreta, ou um nome de propriedade genérica desconhecido), sem usar `any`
-- (regra 01) — mesmo padrão de cast em duas etapas via `unknown` já usado em Instance.luau:82.
type DynamicIndexable = { [string]: unknown }
local function asDynamic(instance: Instance): DynamicIndexable
	return (instance :: unknown) :: DynamicIndexable
end

local passedCount = 0
local totalCount = 0

-- Mesmo padrão de Signal.spec.luau: roda cada teste imediatamente e deixa um assert que falhar
-- estourar pra fora do chunk (traceback + exit code != 0 do próprio Lune), sem precisar de
-- pcall (cujo stub de tipo não modela bem função protegida com retorno `()` em --!strict).
local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

test("NewBase cria instância com ClassName correto e Name = ClassName quando omitido", function()
	local instance = InstanceModule.NewBase("Folder", nil)
	assert(instance.ClassName == "Folder", "ClassName deveria ser 'Folder'")
	assert(instance.Name == "Folder", "Name deveria cair para ClassName quando omitido")
	assert(instance.Parent == nil, "instância recém-criada não deveria ter Parent")
end)

test("NewBase respeita Name explícito", function()
	local instance = InstanceModule.NewBase("Folder", "Meu Folder")
	assert(instance.Name == "Meu Folder", "Name deveria ser o valor explícito passado")
end)

test("setar .Parent liga o filho na lista de filhos do pai", function()
	local parent = InstanceModule.NewBase("Folder", "Pai")
	local child = InstanceModule.NewBase("Folder", "Filho")

	child.Parent = parent

	assert(child.Parent == parent, "Parent do filho deveria refletir o pai novo")
	local children = parent:GetChildren()
	assert(#children == 1, "pai deveria ter exatamente 1 filho")
	assert(children[1] == child, "o filho na lista deveria ser o mesmo objeto")
end)

test("reparenting dispara os eventos na ordem documentada como hipótese", function()
	local oldParent = InstanceModule.NewBase("Folder", "PaiAntigo")
	local newParent = InstanceModule.NewBase("Folder", "PaiNovo")
	local child = InstanceModule.NewBase("Folder", "Filho")
	local grandchild = InstanceModule.NewBase("Folder", "Neto")
	grandchild.Parent = child
	child.Parent = oldParent

	local order: { string } = {}

	oldParent.ChildRemoved:Connect(function(removed: Instance)
		table.insert(order, `ChildRemoved(oldParent, {removed.Name})`)
	end)
	newParent.ChildAdded:Connect(function(added: Instance)
		table.insert(order, `ChildAdded(newParent, {added.Name})`)
	end)
	child.AncestryChanged:Connect(function(instance: Instance, currentParent: Instance?)
		local parentName = if currentParent then currentParent.Name else "nil"
		table.insert(order, `AncestryChanged({instance.Name}, {parentName})`)
	end)
	grandchild.AncestryChanged:Connect(function(instance: Instance, currentParent: Instance?)
		local parentName = if currentParent then currentParent.Name else "nil"
		table.insert(order, `AncestryChanged({instance.Name}, {parentName})`)
	end)
	child.Changed:Connect(function(propertyName: string)
		table.insert(order, `Changed(child, {propertyName})`)
	end)
	grandchild.Changed:Connect(function(propertyName: string)
		table.insert(order, `Changed(grandchild, {propertyName})`)
	end)

	child.Parent = newParent

	local expected = {
		"ChildRemoved(oldParent, Filho)",
		"ChildAdded(newParent, Filho)",
		"AncestryChanged(Filho, PaiNovo)",
		"AncestryChanged(Neto, Filho)",
		"Changed(child, Parent)",
	}
	assert(#order == #expected, `esperava {#expected} eventos, recebeu {#order}: {table.concat(order, " | ")}`)
	for i, expectedEvent in expected do
		assert(order[i] == expectedEvent, `evento {i} esperado '{expectedEvent}', recebeu '{order[i]}'`)
	end
	-- Changed('Parent') só dispara em quem foi diretamente reparentado, nunca nos descendentes.
	for _, entry in order do
		assert(entry ~= "Changed(grandchild, Parent)", "Changed('Parent') não deveria disparar no neto")
	end
end)

test("setar o mesmo Parent de novo não dispara nenhum evento", function()
	local parent = InstanceModule.NewBase("Folder", "Pai")
	local child = InstanceModule.NewBase("Folder", "Filho")
	child.Parent = parent

	local fired = false
	child.Changed:Connect(function()
		fired = true
	end)
	parent.ChildAdded:Connect(function()
		fired = true
	end)

	child.Parent = parent

	assert(not fired, "reatribuir o mesmo Parent não deveria disparar Changed/ChildAdded")
end)

test("não é possível parentear uma instância a si mesma", function()
	local instance = InstanceModule.NewBase("Folder", "X")
	local ok = pcall(function()
		instance.Parent = instance
	end)
	assert(not ok, "deveria erro ao tentar instance.Parent = instance")
end)

test("não é possível criar ciclo parenteando um pai sob seu próprio descendente", function()
	local a = InstanceModule.NewBase("Folder", "A")
	local b = InstanceModule.NewBase("Folder", "B")
	b.Parent = a

	local ok = pcall(function()
		a.Parent = b
	end)
	assert(not ok, "deveria erro ao criar ciclo (a sob seu próprio filho b)")
end)

test("GetDescendants retorna todos os descendentes em pré-ordem (raiz primeiro)", function()
	local root = InstanceModule.NewBase("Folder", "Root")
	local a = InstanceModule.NewBase("Folder", "A")
	local b = InstanceModule.NewBase("Folder", "B")
	local aa = InstanceModule.NewBase("Folder", "AA")
	a.Parent = root
	b.Parent = root
	aa.Parent = a

	local descendants = root:GetDescendants()
	assert(#descendants == 3, `esperava 3 descendentes, recebeu {#descendants}`)
	assert(descendants[1] == a, "primeiro descendente deveria ser A")
	assert(descendants[2] == aa, "segundo descendente deveria ser AA (filho de A, pré-ordem)")
	assert(descendants[3] == b, "terceiro descendente deveria ser B")
end)

test("FindFirstChild encontra por nome direto e recursivo", function()
	local root = InstanceModule.NewBase("Folder", "Root")
	local a = InstanceModule.NewBase("Folder", "A")
	local target = InstanceModule.NewBase("Folder", "Alvo")
	a.Parent = root
	target.Parent = a

	assert(root:FindFirstChild("Alvo") == nil, "não deveria achar não-recursivo")
	assert(root:FindFirstChild("Alvo", true) == target, "deveria achar recursivo")
	assert(root:FindFirstChild("A") == a, "deveria achar filho direto")
end)

test("FindFirstChildOfClass e FindFirstChildWhichIsA respeitam a cadeia de classes", function()
	local root = InstanceModule.NewBase("Folder", "Root")
	local part = InstanceModule.NewBase("Part", "P")
	InstanceModule.SetClassChain(part, { "Part", "BasePart", "PVInstance", "Instance" })
	part.Parent = root

	assert(root:FindFirstChildOfClass("Part") == part, "deveria achar por ClassName exato")
	assert(root:FindFirstChildOfClass("BasePart") == nil, "FindFirstChildOfClass não deveria olhar a cadeia")
	assert(root:FindFirstChildWhichIsA("BasePart") == part, "FindFirstChildWhichIsA deveria respeitar a cadeia (IsA)")
	assert(root:FindFirstChildWhichIsA("Folder") == nil, "não deveria achar classe fora da cadeia")
end)

test("FindFirstAncestor sobe a árvore procurando pelo nome", function()
	local root = InstanceModule.NewBase("Folder", "Root")
	local a = InstanceModule.NewBase("Folder", "A")
	local b = InstanceModule.NewBase("Folder", "B")
	a.Parent = root
	b.Parent = a

	assert(b:FindFirstAncestor("Root") == root, "deveria achar o ancestral pelo nome")
	assert(b:FindFirstAncestor("Inexistente") == nil, "nome inexistente deveria devolver nil")
end)

test("IsA usa a cadeia default (className + Instance) e a cadeia setada via SetClassChain", function()
	local part = InstanceModule.NewBase("Part", "P")
	assert(part:IsA("Part"), "IsA deveria bater com o próprio ClassName")
	assert(part:IsA("Instance"), "IsA deveria bater com Instance por padrão")
	assert(not part:IsA("BasePart"), "sem SetClassChain, não deveria bater com uma superclasse intermediária")

	InstanceModule.SetClassChain(part, { "Part", "BasePart", "PVInstance", "Instance" })
	assert(part:IsA("BasePart"), "após SetClassChain, deveria bater com a superclasse resolvida")
end)

test("IsDescendantOf e IsAncestorOf são simétricos e corretos", function()
	local root = InstanceModule.NewBase("Folder", "Root")
	local a = InstanceModule.NewBase("Folder", "A")
	a.Parent = root

	assert(a:IsDescendantOf(root), "A deveria ser descendente de Root")
	assert(root:IsAncestorOf(a), "Root deveria ser ancestral de A")
	assert(not root:IsDescendantOf(a), "Root não deveria ser descendente de A")
	assert(not a:IsDescendantOf(nil), "IsDescendantOf(nil) deveria ser falso")
end)

test("propriedade genérica: SetPropertyRaw/GetPropertyRaw funcionam e disparam Changed", function()
	local instance = InstanceModule.NewBase("Folder", "X")
	local changedProps: { string } = {}
	instance.Changed:Connect(function(propertyName: string)
		table.insert(changedProps, propertyName)
	end)

	assert(InstanceModule.GetPropertyRaw(instance, "Gravity") == nil, "propriedade não setada deveria ser nil")

	InstanceModule.SetPropertyRaw(instance, "Gravity", 196.2)
	assert(InstanceModule.GetPropertyRaw(instance, "Gravity") == 196.2, "GetPropertyRaw deveria devolver o valor setado")
	assert(#changedProps == 1 and changedProps[1] == "Gravity", "SetPropertyRaw deveria disparar Changed('Gravity')")
end)

test("renomear via .Name dispara Changed('Name')", function()
	local instance = InstanceModule.NewBase("Folder", "Antigo")
	local fired: { string } = {}
	instance.Changed:Connect(function(propertyName: string)
		table.insert(fired, propertyName)
	end)

	instance.Name = "Novo"

	assert(instance.Name == "Novo", "Name deveria ter mudado")
	assert(#fired == 1 and fired[1] == "Name", "deveria disparar Changed('Name') exatamente uma vez")
end)

test("ClassName é imutável", function()
	local instance = InstanceModule.NewBase("Folder", "X")
	local ok = pcall(function()
		instance.Name = instance.Name -- no-op só pra validar que o pcall abaixo é o que falha
	end)
	assert(ok, "reatribuir Name para o mesmo valor não deveria falhar")

	local ok2 = pcall(function()
		instance.ClassName = "Outro"
	end)
	assert(not ok2, "reatribuir ClassName deveria falhar")
end)

test("WaitForChild sem timeout bloqueia a coroutine chamadora até o filho existir de verdade", function()
	local parent = InstanceModule.NewBase("Folder", "Pai")
	local resultChild: Instance? = nil
	local finished = false

	local waiter = coroutine.create(function()
		local child = parent:WaitForChild("Alvo")
		resultChild = child
		finished = true
	end)

	local ok = coroutine.resume(waiter)
	assert(ok, "coroutine deveria iniciar sem erro")
	assert(coroutine.status(waiter) == "suspended", "deveria estar bloqueada esperando o filho aparecer")
	assert(not finished, "WaitForChild não deveria retornar antes do filho existir")

	local child = InstanceModule.NewBase("Folder", "Outronome")
	child.Parent = parent
	assert(not finished, "WaitForChild não deveria resolver com um filho de nome errado")

	local target = InstanceModule.NewBase("Folder", "Alvo")
	target.Parent = parent

	assert(finished, "WaitForChild deveria ter retornado depois do filho certo ser parenteado")
	assert(resultChild == target, "WaitForChild deveria devolver o filho certo")
end)

test("WaitForChild retorna imediatamente (sem yield) se o filho já existir", function()
	local parent = InstanceModule.NewBase("Folder", "Pai")
	local child = InstanceModule.NewBase("Folder", "JaExiste")
	child.Parent = parent

	local result = parent:WaitForChild("JaExiste")
	assert(result == child, "deveria devolver o filho já existente sem bloquear")
end)

test("WaitForChild com timeout retorna nil se o filho não aparecer a tempo", function()
	local parent = InstanceModule.NewBase("Folder", "Pai")
	local startedAt = os.clock()
	local result = parent:WaitForChild("NuncaVaiExistir", 0.05)
	local elapsed = os.clock() - startedAt

	assert(result == nil, "deveria devolver nil quando o timeout expira sem o filho aparecer")
	assert(elapsed >= 0.05, `deveria esperar pelo menos o timeout pedido (esperou {elapsed}s)`)
end)

test("WaitForChild com timeout devolve o filho se ele aparecer antes do prazo", function()
	local parent = InstanceModule.NewBase("Folder", "Pai")

	nativeTask.spawn(function()
		nativeTask.wait(0.03)
		local child = InstanceModule.NewBase("Folder", "Atrasado")
		child.Parent = parent
	end)

	local result = parent:WaitForChild("Atrasado", 1)
	assert(result ~= nil, "deveria encontrar o filho que apareceu antes do prazo")
	assert((result :: Instance).Name == "Atrasado", "deveria devolver o filho certo")
end)

test(
	"Cancelar um task.spawn real parado em WaitForChild(nome, timeout) desconecta a Connection de ChildAdded no momento do Cancel (task-runtime-020)",
	function()
		local scheduler = Scheduler.new()
		local parent = InstanceModule.NewBase("Folder", "Pai")

		local resolvedNaturally = false
		local handle = scheduler:Spawn(function()
			parent:WaitForChild("Alvo", 10)
			resolvedNaturally = true
		end)

		assert(
			coroutine.status(handle) == "suspended",
			"esperava a thread presa no ramo gerido (B) de WaitForChild sob o Scheduler"
		)

		-- Registra uma SEGUNDA limpeza na mesma thread, DEPOIS da que WaitForChild já registrou
		-- internamente (RunCleanups roda na ordem de registro -- ver ThreadBroker.luau). Quando
		-- Scheduler:Cancel chamar RunCleanups, a limpeza de Instance.luau (desconectar a
		-- Connection de ChildAdded) roda PRIMEIRO; só depois roda este probe. Nesse instante
		-- exato a coroutine ainda está "suspended" (Cancel só fecha com coroutine.close DEPOIS
		-- de RunCleanups retornar) e ThreadBroker já não tem mais driver para `handle` (Release
		-- roda antes de RunCleanups em Cancel) -- então, SE a Connection interna ainda estivesse
		-- conectada, criar aqui um filho chamado "Alvo" a encontraria viva e
		-- ThreadBroker.Resume cairia no fallback standalone (coroutine ainda suspensa ->
		-- coroutine.resume cru), resumindo `handle` de verdade e virando
		-- `resolvedNaturally = true`. Se a Connection já foi desconectada (comportamento
		-- corrigido por esta tarefa), este ChildAdded não encontra mais ninguém e nada acontece.
		local probeRanDuringCancel = false
		ThreadBroker.RegisterCleanup(handle, function()
			probeRanDuringCancel = true
			local phantom = InstanceModule.NewBase("Folder", "Alvo")
			phantom.Parent = parent
		end)

		scheduler:Cancel(handle)

		assert(probeRanDuringCancel, "a limpeza de instrumentação deveria ter rodado dentro de Scheduler:Cancel")
		assert(
			not resolvedNaturally,
			"a Connection de ChildAdded criada por WaitForChild deveria ter sido desconectada pelo cleanup que Instance.luau registra (roda ANTES deste probe, mesma ordem de RegisterCleanup) -- se ainda estivesse conectada, o ChildAdded disparado pelo probe (coroutine ainda 'suspended', antes de coroutine.close) teria resumido a thread de verdade"
		)
		assert(coroutine.status(handle) == "dead", "após Cancel, a coroutine deveria estar fechada (dead)")
	end
)

test("ClearAllChildren destrói todos os filhos (como Destroy em cada um)", function()
	local parent = InstanceModule.NewBase("Folder", "Pai")
	local a = InstanceModule.NewBase("Folder", "A")
	local b = InstanceModule.NewBase("Folder", "B")
	a.Parent = parent
	b.Parent = parent

	local aConn = a.Changed:Connect(function() end)

	parent:ClearAllChildren()

	assert(#parent:GetChildren() == 0, "pai não deveria ter mais filhos")
	assert(a.Parent == nil, "filho destruído deveria ter Parent nil")
	assert(not aConn.Connected, "Destroy deveria ter desconectado os listeners do filho")
end)

test("Destroy desconecta os sinais e impede reparentar depois", function()
	local parent = InstanceModule.NewBase("Folder", "Pai")
	local instance = InstanceModule.NewBase("Folder", "X")
	instance.Parent = parent

	local connection = instance.Changed:Connect(function() end)
	assert(connection.Connected, "connection deveria começar conectada")

	instance:Destroy()

	assert(not connection.Connected, "Destroy deveria desconectar os listeners de Changed")
	assert(instance.Parent == nil, "Destroy deveria desparentar a instância")
	assert(#parent:GetChildren() == 0, "pai não deveria mais listar a instância destruída como filha")

	local ok = pcall(function()
		instance.Parent = parent
	end)
	assert(not ok, "reparentar depois de Destroy deveria erro")
end)

test("Destroy é idempotente (chamar duas vezes não erra)", function()
	local instance = InstanceModule.NewBase("Folder", "X")
	instance:Destroy()
	local ok = pcall(function()
		instance:Destroy()
	end)
	assert(ok, "chamar Destroy duas vezes não deveria erro")
end)

test("GetFullName concatena os nomes da raiz até a própria instância", function()
	local root = InstanceModule.NewBase("Folder", "Root")
	local a = InstanceModule.NewBase("Folder", "A")
	local b = InstanceModule.NewBase("Folder", "B")
	a.Parent = root
	b.Parent = a

	assert(b:GetFullName() == "Root.A.B", `esperava 'Root.A.B', recebeu '{b:GetFullName()}'`)
end)

--[[
	Testes NOVOS da task-runtime-016 (Instance.SetClassMethods + acesso a membro de método de
	classe). Ver .claude/agents-memory/arquiteto-runtime-2026-09-04.md, seção "Revisão
	pós-integração 2026-09-04 (3) — acesso a membro". Nenhum dos 24 testes acima foi alterado.
]]

test("método de classe é servido por __index e chamável com ':'", function()
	local instance = InstanceModule.NewBase("TestClassMethodBasic", nil)
	local methods: InstanceModule.ClassMethods = {
		Greet = function(self: Instance): string
			return `Ola, {self.Name}`
		end,
	}
	table.freeze(methods)
	InstanceModule.SetClassMethods(instance, methods)

	type WithGreet = Instance & { Greet: (self: Instance) -> string }
	local typed = (instance :: unknown) :: WithGreet
	assert(typed:Greet() == "Ola, TestClassMethodBasic", "método de classe deveria ser chamável com ':' e receber self correto")
end)

test("escrever sobre método de classe erra", function()
	local instance = InstanceModule.NewBase("TestWriteClassMethod", nil)
	local methods: InstanceModule.ClassMethods = {
		Foo = function() end,
	}
	table.freeze(methods)
	InstanceModule.SetClassMethods(instance, methods)

	local ok, err = pcall(function()
		asDynamic(instance).Foo = nil
	end)
	assert(not ok, "escrever sobre um método de classe deveria erro")
	assert(
		string.find(tostring(err), "is a method of", 1, true) ~= nil,
		`mensagem de erro deveria dizer 'is a method of', recebeu: {err}`
	)
end)

test("escrever sobre método base de Instance erra", function()
	local instance = InstanceModule.NewBase("TestWriteBaseMethod", nil)
	local ok, err = pcall(function()
		asDynamic(instance).GetChildren = nil
	end)
	assert(not ok, "escrever sobre um método base de Instance deveria erro")
	assert(
		string.find(tostring(err), "is a method of", 1, true) ~= nil,
		`mensagem de erro deveria dizer 'is a method of', recebeu: {err}`
	)
end)

test("escrever sobre sinal erra", function()
	local instance = InstanceModule.NewBase("TestWriteSignal", nil)
	local ok, err = pcall(function()
		asDynamic(instance).Changed = nil
	end)
	assert(not ok, "escrever sobre um sinal deveria erro")
	assert(
		string.find(tostring(err), "is an event of", 1, true) ~= nil,
		`mensagem de erro deveria dizer 'is an event of', recebeu: {err}`
	)
end)

test("escrever sobre ClassName erra com a string confirmada contra o Roblox real", function()
	local instance = InstanceModule.NewBase("TestWriteClassName", nil)
	local ok, err = pcall(function()
		instance.ClassName = "Outro"
	end)
	assert(not ok, "escrever sobre ClassName deveria erro")
	assert(
		string.find(tostring(err), "Unable to assign property ClassName. Property is read only", 1, true) ~= nil,
		`mensagem de erro deveria ser a string confirmada do Roblox, recebeu: {err}`
	)
end)

test("SetClassMethods rejeita tabela de métodos não congelada", function()
	local instance = InstanceModule.NewBase("TestUnfrozenMethods", nil)
	local methods: InstanceModule.ClassMethods = {
		Foo = function() end,
	}
	-- NÃO congelada de propósito — SetClassMethods precisa rejeitar isto.
	local ok, err = pcall(function()
		InstanceModule.SetClassMethods(instance, methods)
	end)
	assert(not ok, "SetClassMethods deveria rejeitar uma tabela de métodos não congelada")
	assert(
		string.find(tostring(err), "congelada", 1, true) ~= nil,
		`mensagem de erro deveria mencionar 'congelada', recebeu: {err}`
	)
end)

test("SetClassMethods rejeita valor que não é função", function()
	local instance = InstanceModule.NewBase("TestNonFunctionMethod", nil)
	local methods: InstanceModule.ClassMethods = {
		Foo = 42,
	}
	table.freeze(methods)
	local ok, err = pcall(function()
		InstanceModule.SetClassMethods(instance, methods)
	end)
	assert(not ok, "SetClassMethods deveria rejeitar um valor que não é função")
	assert(
		string.find(tostring(err), "precisa ser uma função", 1, true) ~= nil,
		`mensagem de erro deveria mencionar 'precisa ser uma função', recebeu: {err}`
	)
end)

test("SetClassMethods rejeita chave que colide com a superfície fixa de Instance", function()
	local collidingKeys = { "Parent", "ClassName", "Changed", "GetChildren" }
	for _, key in collidingKeys do
		local instance = InstanceModule.NewBase("TestCollision_" .. key, nil)
		local methods: { [string]: unknown } = {}
		methods[key] = function() end
		table.freeze(methods)
		local ok, err = pcall(function()
			InstanceModule.SetClassMethods(instance, methods :: InstanceModule.ClassMethods)
		end)
		assert(not ok, `SetClassMethods deveria rejeitar a chave colidente '{key}'`)
		assert(
			string.find(tostring(err), "colide com a superfície fixa", 1, true) ~= nil,
			`mensagem de erro deveria mencionar a colisão para '{key}', recebeu: {err}`
		)
	end
end)

test("instância criada por NewBase direto (classMethods nil) mantém o comportamento de hoje", function()
	local instance = InstanceModule.NewBase("TestNoClassMethods", nil)

	-- Ler um nome desconhecido continua caindo no fallback de properties (nil), sem erro —
	-- SetClassMethods nunca foi chamado para esta instância.
	assert(asDynamic(instance).SomeUnknownName == nil, "ler nome desconhecido sem classMethods deveria devolver nil")

	-- Escrever um nome desconhecido continua criando propriedade genérica (mesma divergência
	-- conhecida documentada no comentário do fallback de __newindex).
	local fired: { string } = {}
	instance.Changed:Connect(function(propertyName: string)
		table.insert(fired, propertyName)
	end)
	asDynamic(instance).SomeUnknownName = "valor"
	assert(InstanceModule.GetPropertyRaw(instance, "SomeUnknownName") == "valor", "deveria ter criado a propriedade genérica")
	assert(#fired == 1 and fired[1] == "SomeUnknownName", "deveria disparar Changed para a propriedade nova")
end)

--[[
	Testes NOVOS da task-runtime-021 (resolução de filho por nome em __index/__newindex — ver
	comentário de HIPÓTESE NÃO CONFIRMADA no ponto exato do código, dentro de InstanceMeta.__index
	em Instance.luau, citando task-services-006). Nenhum dos 34 testes acima foi alterado.
]]

test("acessar por nome resolve para um filho direto quando não é membro (2 níveis, ReplicatedStorage.Modules)", function()
	local rs = InstanceModule.NewBase("ReplicatedStorage", nil)
	local modules = InstanceModule.NewBase("Folder", "Modules")
	modules.Parent = rs

	assert(asDynamic(rs).Modules == modules, "acessar rs.Modules deveria devolver o filho 'Modules'")
end)

test("acessar por nome resolve um neto encadeado (3 níveis, ReplicatedStorage.Modules.Combat)", function()
	local rs = InstanceModule.NewBase("ReplicatedStorage", nil)
	local modules = InstanceModule.NewBase("Folder", "Modules")
	local combat = InstanceModule.NewBase("ModuleScript", "Combat")
	modules.Parent = rs
	combat.Parent = modules

	local resolvedModules = asDynamic(rs).Modules
	assert(resolvedModules == modules, "rs.Modules deveria resolver o filho direto")
	assert(
		asDynamic(resolvedModules :: Instance).Combat == combat,
		"rs.Modules.Combat deveria resolver o neto encadeado, um nível de __index por vez"
	)
end)

test("propriedade de mesmo nome VENCE o filho homônimo (hipótese 'membro vence filho', ver comentário em Instance.luau)", function()
	local parent = InstanceModule.NewBase("Folder", "Pai")
	local homonymousChild = InstanceModule.NewBase("Folder", "Combat")
	homonymousChild.Parent = parent
	InstanceModule.SetPropertyRaw(parent, "Combat", "sou a propriedade, não o filho")

	assert(
		asDynamic(parent).Combat == "sou a propriedade, não o filho",
		"propriedade setada via SetPropertyRaw deveria vencer o filho homônimo"
	)
end)

test("campo fixo Name vence filho homônimo chamado 'Name'", function()
	local parent = InstanceModule.NewBase("Folder", "Pai")
	local homonymousChild = InstanceModule.NewBase("Folder", "Name")
	homonymousChild.Parent = parent

	assert(parent.Name == "Pai", "parent.Name deveria continuar sendo o Name da própria instância, não o filho")
	assert(parent:FindFirstChild("Name") == homonymousChild, "o filho 'Name' continua alcançável via FindFirstChild")
end)

test("método base Destroy vence filho homônimo chamado 'Destroy'", function()
	local parent = InstanceModule.NewBase("Folder", "Pai")
	local homonymousChild = InstanceModule.NewBase("Folder", "Destroy")
	homonymousChild.Parent = parent

	assert(typeof(asDynamic(parent).Destroy) == "function", "parent.Destroy deveria continuar sendo o método base, não o filho")
	assert(parent:FindFirstChild("Destroy") == homonymousChild, "o filho 'Destroy' continua alcançável via FindFirstChild")
end)

test("nome sem membro e sem filho continua devolvendo nil (modo leniente intacto)", function()
	local parent = InstanceModule.NewBase("Folder", "Pai")
	assert(asDynamic(parent).NomeQueNaoExiste == nil, "nome sem membro e sem filho deveria continuar nil")
end)

test("remover o filho (Parent = nil) faz a leitura por nome voltar a nil", function()
	local parent = InstanceModule.NewBase("Folder", "Pai")
	local child = InstanceModule.NewBase("Folder", "Temporario")
	child.Parent = parent

	assert(asDynamic(parent).Temporario == child, "deveria resolver o filho enquanto ele está parenteado")

	child.Parent = nil

	assert(asDynamic(parent).Temporario == nil, "depois de desparentar, a leitura por nome deveria voltar a nil")
end)

test(
	"escrever sobre um nome que hoje é filho cria propriedade genérica homônima sem afetar o filho (__newindex inalterado, comportamento correto fecha em task-runtime-018)",
	function()
		local parent = InstanceModule.NewBase("Folder", "Pai")
		local child = InstanceModule.NewBase("Folder", "Modules")
		child.Parent = parent

		asDynamic(parent).Modules = "não deveria afetar o filho"

		assert(
			InstanceModule.GetPropertyRaw(parent, "Modules") == "não deveria afetar o filho",
			"deveria ter criado a propriedade genérica com o valor atribuído"
		)
		assert(child.Parent == parent, "o filho não deveria ter sido desparentado nem destruído")
		assert(parent:FindFirstChild("Modules") == child, "o filho continua alcançável via FindFirstChild")
		assert(
			asDynamic(parent).Modules == "não deveria afetar o filho",
			"leitura por nome agora resolve a propriedade nova, que vence o filho (mesma ordem de __index)"
		)
	end
)

--[[
	Testes NOVOS da task-runtime-018 (ClassSchema/Instance.SetClassSchema — modo estrito de
	__index/__newindex). Ver .claude/agents-memory/arquiteto-services-2026-09-05.md, "Decisão 3"/
	"Decisão 4"/"Decisão 6". Nenhum dos 42 testes acima foi alterado. Cobertura de achatamento
	(schema herdado, override entre classes) fica em ClassRegistry.spec.luau -- aqui é caixa-branca
	sobre a mecânica de __index/__newindex, via InstanceModule.SetClassSchema direto.
]]

type ClassSchema = InstanceModule.ClassSchema

-- Helper só destes testes: monta e congela um ClassSchema bem-formado a partir de um mapa
-- nome -> descritor parcial (ReadOnly default para `false` quando omitido).
local function makeSchema(
	entries: { [string]: { Kind: InstanceModule.MemberKind, Default: unknown?, ReadOnly: boolean? } }
): ClassSchema
	local schema: ClassSchema = {}
	for key, entry in entries do
		schema[key] = {
			Kind = entry.Kind,
			Default = entry.Default,
			ReadOnly = if entry.ReadOnly ~= nil then entry.ReadOnly else false,
		}
	end
	table.freeze(schema)
	return schema
end

-- Helper só dos testes de VALIDAÇÃO abaixo: monta um schema com um descritor deliberadamente mal
-- formado (Kind fora da união, ReadOnly não-boolean) -- precisa escapar da checagem ESTÁTICA de
-- `MemberDescriptor` via cast em duas etapas por `unknown` (mesmo padrão de `asDynamic`, já usado
-- neste arquivo desde task-runtime-016), porque um `Kind` malformado não compilaria em --!strict
-- se escrito como um `MemberDescriptor` de verdade -- é exatamente por isso que a validação de
-- SetClassSchema existe: o schema vem do gerador de `services`, não do type-checker do LuauBench.
local function makeRawSchema(entries: { [string]: { [string]: unknown } }): ClassSchema
	local schema: { [string]: unknown } = {}
	for key, entry in entries do
		schema[key] = entry
	end
	table.freeze(schema)
	return (schema :: unknown) :: ClassSchema
end

test("instância COM ClassSchema: ler nome fora do schema erra com 'is not a valid member of'", function()
	local instance = InstanceModule.NewBase("TestSchemaUnknownRead", nil)
	InstanceModule.SetClassSchema(
		instance,
		makeSchema({
			Gravity = { Kind = "Property", Default = 196.2 },
		})
	)

	local ok, err = pcall(function()
		return asDynamic(instance).NomeQueNaoExisteNoSchema
	end)
	assert(not ok, "ler nome fora do schema deveria erro")
	assert(
		string.find(tostring(err), "is not a valid member of", 1, true) ~= nil,
		`mensagem deveria conter 'is not a valid member of', recebeu: {err}`
	)
end)

test("instância COM ClassSchema: escrever nome fora do schema erra com 'is not a valid member of'", function()
	local instance = InstanceModule.NewBase("TestSchemaUnknownWrite", nil)
	InstanceModule.SetClassSchema(
		instance,
		makeSchema({
			Gravity = { Kind = "Property", Default = 196.2 },
		})
	)

	local ok, err = pcall(function()
		asDynamic(instance).NomeQueNaoExisteNoSchema = 1
	end)
	assert(not ok, "escrever nome fora do schema deveria erro")
	assert(
		string.find(tostring(err), "is not a valid member of", 1, true) ~= nil,
		`mensagem deveria conter 'is not a valid member of', recebeu: {err}`
	)
end)

test("instância COM ClassSchema: escrever propriedade ReadOnly erra com a string confirmada", function()
	local instance = InstanceModule.NewBase("TestSchemaReadOnly", nil)
	InstanceModule.SetClassSchema(
		instance,
		makeSchema({
			SeatPart = { Kind = "Property", Default = "x", ReadOnly = true },
		})
	)

	local ok, err = pcall(function()
		asDynamic(instance).SeatPart = "outro"
	end)
	assert(not ok, "escrever propriedade ReadOnly do schema deveria erro")
	assert(
		string.find(tostring(err), "Unable to assign property SeatPart. Property is read only", 1, true) ~= nil,
		`mensagem deveria ser a string confirmada, recebeu: {err}`
	)
end)

test("ler propriedade do schema cujo Default é nil devolve nil SEM errar (caso que motivou o schema)", function()
	local instance = InstanceModule.NewBase("TestSchemaNilDefault", nil)
	InstanceModule.SetClassSchema(
		instance,
		makeSchema({
			SeatPart = { Kind = "Property", Default = nil, ReadOnly = false },
		})
	)

	local ok, result = pcall(function()
		return asDynamic(instance).SeatPart
	end)
	assert(ok, `ler propriedade do schema com Default nil não deveria erro, recebeu: {result}`)
	assert(result == nil, "propriedade do schema com Default nil deveria devolver nil")
end)

test("defaults do schema são semeados sem disparar Changed", function()
	local instance = InstanceModule.NewBase("TestSchemaSeedNoChanged", nil)
	local fired: { string } = {}
	instance.Changed:Connect(function(propertyName: string)
		table.insert(fired, propertyName)
	end)

	InstanceModule.SetClassSchema(
		instance,
		makeSchema({
			Gravity = { Kind = "Property", Default = 196.2 },
			SeatPart = { Kind = "Property", Default = nil },
		})
	)

	assert(
		#fired == 0,
		`SetClassSchema não deveria disparar Changed ao semear defaults, recebeu: {table.concat(fired, ", ")}`
	)
	assert(asDynamic(instance).Gravity == 196.2, "Gravity deveria ter sido semeada com o Default")
end)

test("escrever propriedade gravável do schema funciona e dispara Changed", function()
	local instance = InstanceModule.NewBase("TestSchemaWritable", nil)
	InstanceModule.SetClassSchema(
		instance,
		makeSchema({
			Gravity = { Kind = "Property", Default = 196.2, ReadOnly = false },
		})
	)

	local fired: { string } = {}
	instance.Changed:Connect(function(propertyName: string)
		table.insert(fired, propertyName)
	end)

	asDynamic(instance).Gravity = 50
	assert(asDynamic(instance).Gravity == 50, "escrever propriedade gravável do schema deveria mudar o valor")
	assert(#fired == 1 and fired[1] == "Gravity", "deveria disparar Changed('Gravity') exatamente uma vez")
end)

test("escrever sobre entrada Kind == 'Event' do schema erra 'is an event of'", function()
	local instance = InstanceModule.NewBase("TestSchemaEventWrite", nil)
	InstanceModule.SetClassSchema(
		instance,
		makeSchema({
			PlayerAdded = { Kind = "Event", Default = nil, ReadOnly = true },
		})
	)

	local ok, err = pcall(function()
		asDynamic(instance).PlayerAdded = nil
	end)
	assert(not ok, "escrever sobre um evento de classe do schema deveria erro")
	assert(
		string.find(tostring(err), "is an event of", 1, true) ~= nil,
		`mensagem deveria dizer 'is an event of', recebeu: {err}`
	)
end)

test("escrever sobre entrada Kind == 'Callback' do schema é permitido (assinável por design)", function()
	local instance = InstanceModule.NewBase("TestSchemaCallback", nil)
	InstanceModule.SetClassSchema(
		instance,
		makeSchema({
			OnInvoke = { Kind = "Callback", Default = nil, ReadOnly = false },
		})
	)

	local handler = function() end
	local ok = pcall(function()
		asDynamic(instance).OnInvoke = handler
	end)
	assert(ok, "escrever sobre um Callback do schema não deveria erro -- é assinável por design")
	assert(asDynamic(instance).OnInvoke == handler, "OnInvoke deveria refletir o valor atribuído")
end)

test("SetClassSchema cria um Signal fresco por instância para cada entrada Kind == 'Event' (nunca compartilhado)", function()
	local schema = makeSchema({
		PlayerAdded = { Kind = "Event", Default = nil, ReadOnly = true },
	})

	local instanceA = InstanceModule.NewBase("TestSchemaFreshSignalA", nil)
	local instanceB = InstanceModule.NewBase("TestSchemaFreshSignalB", nil)
	InstanceModule.SetClassSchema(instanceA, schema)
	InstanceModule.SetClassSchema(instanceB, schema)

	local signalA = asDynamic(instanceA).PlayerAdded
	local signalB = asDynamic(instanceB).PlayerAdded
	assert(signalA ~= nil and signalB ~= nil, "PlayerAdded deveria existir nas duas instâncias")
	assert(
		signalA ~= signalB,
		"cada instância deveria ter seu PRÓPRIO Signal, nunca compartilhado a partir do MESMO schema congelado"
	)
end)

test("SetClassSchema NÃO rejeita colisão com a superfície fixa de Instance (diferente de SetClassMethods)", function()
	local instance = InstanceModule.NewBase("TestSchemaInstanceCollision", nil)
	local ok = pcall(function()
		InstanceModule.SetClassSchema(
			instance,
			makeSchema({
				Name = { Kind = "Property", Default = "TestSchemaInstanceCollision", ReadOnly = false },
				Parent = { Kind = "Property", Default = nil, ReadOnly = false },
				ClassName = { Kind = "Property", Default = "TestSchemaInstanceCollision", ReadOnly = true },
				Changed = { Kind = "Event", Default = nil, ReadOnly = true },
			})
		)
	end)
	assert(ok, "SetClassSchema não deveria rejeitar um schema que contém Name/Parent/ClassName/Changed")

	-- Os passos 1-2 de __index continuam servindo esses nomes pelos campos fixos, não pelo
	-- schema -- ClassName continua imutável mesmo tendo entrado no schema como ReadOnly = true.
	assert(instance.Name == "TestSchemaInstanceCollision", "Name deveria continuar vindo do campo fixo")
	assert(instance.ClassName == "TestSchemaInstanceCollision", "ClassName deveria continuar vindo do campo fixo")
end)

test("SetClassSchema rejeita tabela de schema não congelada", function()
	local instance = InstanceModule.NewBase("TestSchemaUnfrozen", nil)
	local schema: ClassSchema = {
		Gravity = { Kind = "Property", Default = 196.2, ReadOnly = false },
	}
	-- NÃO congelada de propósito -- SetClassSchema precisa rejeitar isto.
	local ok, err = pcall(function()
		InstanceModule.SetClassSchema(instance, schema)
	end)
	assert(not ok, "SetClassSchema deveria rejeitar um schema não congelado")
	assert(
		string.find(tostring(err), "congelada", 1, true) ~= nil,
		`mensagem deveria mencionar 'congelada', recebeu: {err}`
	)
end)

test("SetClassSchema rejeita Kind fora de Property/Event/Callback", function()
	local instance = InstanceModule.NewBase("TestSchemaInvalidKind", nil)
	local schema = makeRawSchema({
		Foo = { Kind = "Bogus", Default = nil, ReadOnly = false },
	})

	local ok, err = pcall(function()
		InstanceModule.SetClassSchema(instance, schema)
	end)
	assert(not ok, "SetClassSchema deveria rejeitar um Kind fora de Property/Event/Callback")
	assert(
		string.find(tostring(err), "Kind de", 1, true) ~= nil,
		`mensagem deveria mencionar o Kind inválido, recebeu: {err}`
	)
end)

test("SetClassSchema rejeita ReadOnly que não é boolean", function()
	local instance = InstanceModule.NewBase("TestSchemaInvalidReadOnly", nil)
	local schema = makeRawSchema({
		Foo = { Kind = "Property", Default = nil, ReadOnly = "sim" },
	})

	local ok, err = pcall(function()
		InstanceModule.SetClassSchema(instance, schema)
	end)
	assert(not ok, "SetClassSchema deveria rejeitar ReadOnly que não é boolean")
	assert(
		string.find(tostring(err), "ReadOnly de", 1, true) ~= nil,
		`mensagem deveria mencionar o ReadOnly inválido, recebeu: {err}`
	)
end)

test("membro do schema vence filho homônimo mesmo quando o Default é nil", function()
	local parent = InstanceModule.NewBase("TestSchemaMemberVsChild", nil)
	InstanceModule.SetClassSchema(
		parent,
		makeSchema({
			SeatPart = { Kind = "Property", Default = nil, ReadOnly = false },
		})
	)
	local homonymousChild = InstanceModule.NewBase("Folder", "SeatPart")
	homonymousChild.Parent = parent

	assert(asDynamic(parent).SeatPart == nil, "membro do schema (mesmo com Default nil) deveria vencer o filho homônimo")
	assert(parent:FindFirstChild("SeatPart") == homonymousChild, "o filho continua alcançável via FindFirstChild")
end)

test("GetPropertyRaw/SetPropertyRaw NUNCA consultam o schema (via de engenharia abaixo do enforcement)", function()
	local instance = InstanceModule.NewBase("TestSchemaBypass", nil)
	InstanceModule.SetClassSchema(
		instance,
		makeSchema({
			Heartbeat = { Kind = "Event", Default = nil, ReadOnly = true },
		})
	)

	-- SetPropertyRaw escreve por cima de uma entrada Kind == "Event" (ReadOnly do ponto de vista
	-- do script) sem erro nenhum -- é exatamente o que `services` precisa para instalar o
	-- Heartbeat real do Scheduler sobre a entrada semeada por SetClassSchema.
	local ok = pcall(function()
		InstanceModule.SetPropertyRaw(instance, "Heartbeat", "valor de engenharia")
	end)
	assert(ok, "SetPropertyRaw não deveria consultar o schema nem errar sobre uma entrada Event/ReadOnly")
	assert(
		InstanceModule.GetPropertyRaw(instance, "Heartbeat") == "valor de engenharia",
		"GetPropertyRaw deveria devolver o valor bruto, sem checagem de schema"
	)
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
