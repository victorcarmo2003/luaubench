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
]]

local InstanceModule = require("./Instance")
local ClassRegistryModule = require("./ClassRegistry")

type Instance = InstanceModule.Instance

export type DataModel = Instance & {
	GetService: (self: DataModel, className: string) -> Instance,
	FindService: (self: DataModel, className: string) -> Instance?,
}

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
	GetService = function(self: Instance, className: string): Instance
		local existing = self:FindFirstChildOfClass(className)
		if existing ~= nil then
			return existing
		end

		local descriptor = ClassRegistryModule.Get(className)
		if descriptor == nil then
			error(`GetService: classe '{className}' não registrada em ClassRegistry`, 2)
		end
		if not descriptor.IsService then
			error(
				`GetService: '{className}' está registrada mas não é um Service (ClassDescriptor.IsService == false)`,
				2
			)
		end

		-- `ClassRegistry.new` sem `name` explícito -> Name cai para o ClassName por default
		-- (Instance.NewBase), replicando exatamente "Name == ClassName" do Roblox real.
		local service = ClassRegistryModule.new(className, nil)
		service.Parent = self
		return service
	end,

	FindService = function(self: Instance, className: string): Instance?
		-- Nunca cria: só devolve o singleton se ele já existir como filho direto da raiz.
		return self:FindFirstChildOfClass(className)
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
	return (instance :: unknown) :: DataModel
end

return DataModel
