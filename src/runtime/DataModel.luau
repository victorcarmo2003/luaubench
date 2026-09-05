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
]]

local InstanceModule = require("./Instance")
local ClassRegistryModule = require("./ClassRegistry")
local UnknownClassResolverModule = require("./UnknownClassResolver")

type Instance = InstanceModule.Instance

export type DataModel = Instance & {
	GetService: (self: DataModel, className: string) -> Instance?,
	FindService: (self: DataModel, className: string) -> Instance?,
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
