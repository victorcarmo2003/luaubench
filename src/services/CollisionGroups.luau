--!strict

--[[
	Registro de grupos de colisão -- dado puro, SEM `Runtime.Instance`, SEM I/O -- task-services-023.
	LER .claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.5 -- Grupo 4", subseção
	"L2.5.1 -- Achado: os grupos de colisão pertencem ao `WorldRoot`, não ao `PhysicsService`", e
	.claude/agents-memory/pesquisa-services-leva2-pendencias-2026-09-05.md, item 3, ANTES de mexer
	aqui -- o desenho abaixo segue as duas ao pé da letra.

	QUEM É DONO DO ESTADO: este módulo NÃO é um singleton -- cada `WorldRoot`/`Workspace` (na
	prática, só existe um por processo, mas o mecanismo é genérico) tem o SEU PRÓPRIO
	`CollisionGroups.new()`, guardado como estado privado por instância em
	`behavior/WorldRoot.luau` (via `../InstanceState.luau`, chave `_LuauBenchCollisionGroups`).
	`behavior/PhysicsService.luau` NUNCA cria o seu próprio registro -- alcança o MESMO objeto
	desta instância de `Workspace` via `WorldRoot.GetRegistry(workspaceInstance)` (ver cabeçalho de
	`./behavior/PhysicsService.luau`) -- é isso que garante `PhysicsService:RegisterCollisionGroup("X")`
	seguido de `workspace:IsCollisionGroupRegistered("X")` devolver `true`, como no Roblox real
	(mesma verdade única, nunca duas cópias que pudessem dessincronizar).

	MODELO DE DADOS (decisão do arquiteto, L2.5.1): nomes registrados (lista ORDENADA, ordem de
	registro -- `"Default"` sempre primeiro) + matriz de colidibilidade PAR A PAR (nunca um esquema
	de id numérico/bitmask -- ver "DIVERGÊNCIA DECLARADA" abaixo). Ausência de uma entrada na matriz
	para um par == colidem (default do Roblox real, confirmado: "dois grupos recém-registrados
	colidem por padrão").

	FATOS CONFIRMADOS (honrados exatamente, ver pesquisa item 3 e o board da tarefa):
	- `GetMax() == 32` (`GetMaxCollisionGroups()` no Roblox real).
	- `"Default"` já vem registrado (`CollisionGroups.new()` semeia sozinho).
	- Dois grupos recém-registrados colidem entre si por padrão.
	- `"Default"` não pode ser registrado de novo, renomeado nem removido (doc oficial, citação
	  literal: "The name cannot be 'Default'." -- para `Register`; comportamento espelhado para
	  `Unregister`/`Rename` por semelhança de descrição, nenhuma das duas doc-strings distingue).

	NÃO CONFIRMADO -- decisões registradas, não inventadas às cegas (regra 00):
	- NOME DUPLICADO em `Register`: mantido IDEMPOTENTE (segunda chamada com o mesmo nome não erra)
	  -- princípio "em dúvida, incluir/permitir" da Decisão 3 do arquiteto. Fonte fraca EM
	  CONTRÁRIO registrada pela pesquisa (item 3): um blog de terceiros (gamertagmythras.com)
	  recomenda `pcall` "se um script puder rodar duas vezes", o que só faz sentido como conselho
	  defensivo se a segunda chamada PUDESSE falhar -- não é uma citação de erro ao vivo, é uma
	  recomendação de terceiro não-oficial. Revisitável se uma pesquisa futura achar citação verbatim.
	- `Unregister` de um nome NÃO registrado: tratado como NO-OP idempotente (mesma razão --
	  nenhuma fonte, oficial ou de comunidade, descreve este caso especificamente).
	- `Rename` de/para um nome já ocupado, ou `from` inexistente: erra (aproximação de boa-fé --
	  a doc oficial fala em "throws a runtime error in the following circumstances" sem listar
	  TODAS elas verbatim na pesquisa desta leva); `to == from` é NO-OP (nunca erro).
	- RESTRIÇÃO CLIENTE/SERVIDOR (`Unregister`/`Rename`, CONFIRMADA oficialmente só para essas
	  duas -- "throws a runtime error [...] if the method is called from a client"): O LuauBench
	  SEMPRE se apresenta como servidor (mesma decisão de `behavior/RunService.luau`:
	  `IsServer() -> true`, `IsClient() -> false`, sem RunContext de cliente simulado nesta leva) --
	  esta restrição NUNCA é observável aqui. DELIBERADAMENTE NÃO implementada como um branch
	  `if isClient() then error() end` permanentemente morto e impossível de testar honestamente
	  (regra 01: teste o que for prático executar de verdade) -- é uma DIVERGÊNCIA DECLARADA
	  (regra 00), não uma lacuna silenciosa: quando/se um modo `--client` existir, é aqui que o
	  branch condicional entra, num ponto só. `Register`/`CollisionGroupSetCollidable` NUNCA tiveram
	  essa restrição confirmada (pesquisa item 3) -- não recebem nem o comentário de divergência.

	DIVERGÊNCIA DECLARADA -- `GetRegisteredCollisionGroups()`: o Roblox real devolve um `Array` cujo
	formato exato de elemento não é documentado pelo dump (`ReturnType: {Category: "Group", Name:
	"Array"}`, sem tipo de elemento) nem foi confirmado por esta pesquisa. `WorldRoot.luau`/
	`PhysicsService.luau` (consumidores deste módulo) expõem só `{ Name: string }` por entrada --
	NUNCA um campo `Mask`/id numérico inventado: o modelo de dados desta leva é a matriz par a par
	(acima), não um esquema de bitmask por id, e forjar um `Mask` sintético a partir da matriz
	mentiria sobre uma numeração de id que o LuauBench nunca atribui. `GetRegisteredNames`, abaixo,
	devolve só os NOMES -- a decisão de forma de retorno da API pública é de quem consome
	(`behavior/WorldRoot.luau`).

	Depende só de Luau puro (`table.insert`/`table.remove`) -- nenhum `require` de `../runtime` nem
	de `Instance`, propositalmente (nome do módulo/decisão do arquiteto: "dado puro, sem Instance").
	Usado por `./behavior/WorldRoot.luau` (dono do estado, um `Registry` por instância de
	`Workspace`) e, transitivamente, por `./behavior/PhysicsService.luau` (vista legada, sem estado
	próprio).
]]

local CollisionGroups = {}

-- Confirmado oficialmente (pesquisa item 3, bônus: "GetMaxCollisionGroups() == 32 ... já estavam
-- corretos na doc oficial"). "Default" conta como um dos 32.
local MAX_GROUPS = 32

local DEFAULT_GROUP_NAME = "Default"

export type Registry = {
	-- Registra um novo grupo. Erra (família Roblox, aproximação de boa-fé -- ver cabeçalho,
	-- "FATOS CONFIRMADOS") se `name == "Default"` ou se o registro excederia `GetMax()`. Nome já
	-- registrado (e diferente de "Default") é NO-OP idempotente -- ver cabeçalho, "NÃO CONFIRMADO".
	Register: (self: Registry, name: string) -> (),

	-- Remove um grupo já registrado. Erra se `name == "Default"` (reservado, nunca removível).
	-- Nome não registrado é NO-OP idempotente -- ver cabeçalho. Limpa toda entrada da matriz de
	-- colidibilidade que referencia `name`, dos dois lados.
	Unregister: (self: Registry, name: string) -> (),

	IsRegistered: (self: Registry, name: string) -> boolean,

	-- Renomeia um grupo já registrado, preservando a posição na ordem de registro e toda entrada
	-- da matriz de colidibilidade que o referenciava. Erra se `from`/`to` for "Default", se `from`
	-- não estiver registrado, ou se `to` já estiver registrado (e for diferente de `from`).
	-- `to == from` é NO-OP.
	Rename: (self: Registry, from: string, to: string) -> (),

	-- Ordem de registro ("Default" sempre primeiro) -- cópia nova a cada chamada, nunca a tabela
	-- interna (um script que mutasse o retorno não pode corromper o registro).
	GetRegisteredNames: (self: Registry) -> { string },

	GetMax: (self: Registry) -> number,

	-- Erra se `name1`/`name2` não estiver registrado. `name1 == name2` é permitido (auto-colisão é
	-- um eixo real e independente no Roblox -- um grupo pode deixar de colidir consigo mesmo).
	SetCollidable: (self: Registry, name1: string, name2: string, collidable: boolean) -> (),

	-- Erra se `name1`/`name2` não estiver registrado. Par sem entrada explícita na matriz devolve
	-- `true` -- "dois grupos recém-registrados colidem por padrão" (fato confirmado, ver cabeçalho).
	AreCollidable: (self: Registry, name1: string, name2: string) -> boolean,
}

-- Erro em nível 2 -- culpa quem chamou o método do `Registry` (mesma convenção já usada por
-- `datastore/Value.luau` `AssertNameLength`/`RejectingSignal.luau`: uma mensagem família-Roblox,
-- sem prefixo `[LuauBench]`, culpando o call site imediato do script/behavior que violou o
-- contrato documentado do método real).
local function assertRegistered(registered: { [string]: boolean }, name: string): ()
	if not registered[name] then
		error(`'{name}' is not a registered collision group`, 2)
	end
end

function CollisionGroups.new(): Registry
	-- Ordem de registro -- "Default" sempre primeiro, nunca removido/reordenado por Unregister de
	-- outro nome (só `table.remove`/substituição de índice exatos, nunca um `table.sort`).
	local order: { string } = { DEFAULT_GROUP_NAME }
	local registered: { [string]: boolean } = { [DEFAULT_GROUP_NAME] = true }

	-- Matriz par a par, SIMÉTRICA por construção (toda escrita grava os dois sentidos) -- ausência
	-- de entrada (`matrix[a] == nil` OU `matrix[a][b] == nil`) significa "colidem" (default real).
	local matrix: { [string]: { [string]: boolean } } = {}

	local function removeFromOrder(name: string): ()
		for index, existing in order do
			if existing == name then
				table.remove(order, index)
				return
			end
		end
	end

	local self: Registry = {} :: Registry

	self.Register = function(_self: Registry, name: string): ()
		if name == DEFAULT_GROUP_NAME then
			error("The name cannot be 'Default'", 2)
		end
		if registered[name] then
			-- Idempotente -- ver cabeçalho, "NÃO CONFIRMADO" (nome duplicado).
			return
		end
		if #order >= MAX_GROUPS then
			error(`Cannot register more than {MAX_GROUPS} collision groups`, 2)
		end
		registered[name] = true
		table.insert(order, name)
	end

	self.Unregister = function(_self: Registry, name: string): ()
		if name == DEFAULT_GROUP_NAME then
			error("The name cannot be 'Default'", 2)
		end
		if not registered[name] then
			-- No-op idempotente -- ver cabeçalho, "NÃO CONFIRMADO" (nome não registrado).
			return
		end
		registered[name] = nil
		removeFromOrder(name)

		-- Limpa a matriz dos dois lados -- um grupo removido não pode deixar rastro que uma
		-- reutilização futura do mesmo nome herdaria por engano.
		matrix[name] = nil
		for _, row in matrix do
			row[name] = nil
		end
	end

	self.IsRegistered = function(_self: Registry, name: string): boolean
		return registered[name] == true
	end

	self.Rename = function(_self: Registry, from: string, to: string): ()
		if from == DEFAULT_GROUP_NAME or to == DEFAULT_GROUP_NAME then
			error("The name cannot be 'Default'", 2)
		end
		assertRegistered(registered, from)
		if to == from then
			return -- no-op -- ver cabeçalho, "NÃO CONFIRMADO"
		end
		if registered[to] then
			error(`'{to}' is already a registered collision group`, 2)
		end

		registered[from] = nil
		registered[to] = true
		for index, existing in order do
			if existing == from then
				order[index] = to
				break
			end
		end

		-- Migra as entradas da matriz que referenciam `from` para `to`, preservando o valor.
		matrix[to] = matrix[from]
		matrix[from] = nil
		for _, row in matrix do
			if row[from] ~= nil then
				row[to] = row[from]
				row[from] = nil
			end
		end
	end

	self.GetRegisteredNames = function(_self: Registry): { string }
		local copy = table.create(#order)
		for index, name in order do
			copy[index] = name
		end
		return copy
	end

	self.GetMax = function(_self: Registry): number
		return MAX_GROUPS
	end

	self.SetCollidable = function(_self: Registry, name1: string, name2: string, collidable: boolean): ()
		assertRegistered(registered, name1)
		assertRegistered(registered, name2)

		local row1 = matrix[name1]
		if row1 == nil then
			row1 = {}
			matrix[name1] = row1
		end
		row1[name2] = collidable

		if name1 ~= name2 then
			local row2 = matrix[name2]
			if row2 == nil then
				row2 = {}
				matrix[name2] = row2
			end
			row2[name1] = collidable
		end
	end

	self.AreCollidable = function(_self: Registry, name1: string, name2: string): boolean
		assertRegistered(registered, name1)
		assertRegistered(registered, name2)

		local row = matrix[name1]
		if row == nil then
			return true -- default real: colidem
		end
		local value = row[name2]
		if value == nil then
			return true
		end
		return value
	end

	return self
end

return CollisionGroups
