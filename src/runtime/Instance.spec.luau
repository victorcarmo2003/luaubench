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

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
