--!strict

--[[
	`InstancePlan` (`TreePlanner.luau`, task-cli-003) -> `DataModel` real (arquiteto-cli-2026-09-
	05.md, Decisões 4, 5 e 7 -- LER ESSAS TRÊS INTEIRAS antes de mexer aqui). É o primeiro módulo
	de `cli` que toca `runtime`/`services` de verdade: `TreePlanner` deliberadamente não conhece
	nenhum dos dois (Decisão 3, "planejar antes de materializar"), então é AQUI que o plano puro
	vira Instance simulada.

	Nó com `IsServiceRoot` -> `game:GetService(ClassName)` (singleton do motor, parenteado direto
	sob a raiz). Todo o resto -> `Services.new(ClassName, Name)` seguido de `.Parent = pai`.

	NUNCA `Runtime.ClassRegistry.NewEngineInstance` -- o cabeçalho de `src/runtime/init.luau`
	("LISTA FECHADA de chamadores legítimos") lista só `runtime/DataModel.luau` (dentro de
	`GetService`) e `services` (dentro de um `Behavior.Initialize`) como chamadores válidos; `cli`
	está explicitamente listado como "NUNCA". A razão declarada lá: `$className` vem de um arquivo
	do usuário (entrada NÃO CONFIÁVEL), e `NewEngineInstance` não tem a guarda de `IsAbstract`
	(`NotCreatable`) que `Instance.new`/`Services.new` têm -- usá-la aqui deixaria um
	`"$className": "Workspace"` num nó comum passar como instância malformada em silêncio, em vez
	de errar como "Unable to create an Instance of type ...". `revisor-cli` confirma isto por grep
	(critério de aceite do board).

	`Source` de Script/LocalScript/ModuleScript vai por `Runtime.Instance.SetPropertyRaw` --
	`Source` está FORA do schema (capability `PluginOrOpenCloud`, desenho de `services`, revisão
	A.4) e `Get/SetPropertyRaw` NUNCA consultam o schema por design (Decisão 6.2 de `services`):
	é exatamente o canal que aquele desenho já reservou para isto, e mantém `script.Source`
	ilegível pelo script simulado do usuário (`__index`/`__newindex` do `runtime` só conhecem o
	que está no `ClassSchema`) -- fiel ao Roblox, onde `Source` também não é lido por um script
	rodando dentro do próprio jogo.

	`$properties` vai pela via PÚBLICA de escrita, nunca por `SetPropertyRaw` (Decisão 7): a chave
	vem do `.project.json` (entrada não confiável, pode ser um typo tipo "Gravty"), e
	`SetPropertyRaw` IGNORA o schema -- gravaria uma propriedade fantasma que o script depois não
	conseguiria LER (o `__index` estrito erraria "Gravty is not a valid member of ..."), um erro
	dez passos depois da causa real. Em vez disso: `local writable = (instance :: unknown) :: {
	[string]: unknown }` -- um dos casts de fronteira deste módulo (o outro é o narrowing do
	resultado de `pcall(Services.new)`, mais abaixo), cada um comentado no próprio ponto de uso
	-- e a escrita roda dentro de `pcall`, deixando o `__newindex` REAL do runtime (que já sabe
	validar contra o `ClassSchema` e devolver a mensagem certa da família Roblox) fazer o
	enforcement. Falha -> `Diagnostic` de erro citando `NodePath` + o nome da propriedade + a
	mensagem do motor (via `pcall`), NUNCA derruba `Materialize` -- o resto da árvore continua
	sendo materializado.

	DEFESA EM PROFUNDIDADE (não pedida por `TreePlanner`, mas barata e consistente com a regra 00
	"nunca stack trace cru"/"nunca crash por entrada não confiável"): `Services.new` pode falhar
	de verdade para um `"$className"` explícito que `TreePlanner` nunca valida contra
	`services` (Decisão 4: `TreePlanner` só valida a INFERÊNCIA de Service, não que todo
	`$className` explícito seja uma classe real/simulada) -- ex.: um typo ("Frmae") ou uma classe
	real do dump ainda não coberta por esta leva ("Frame"). Sem isto, um `.project.json`
	perfeitamente bem-formado, mas citando uma classe que `services` não cria, derrubaria
	`Materialize` inteiro com um `error()` cru. `Services.new` já devolve mensagens de ótima
	qualidade (família Roblox real, ou o prefixo `[LuauBench] ... not simulated yet`) -- este
	módulo só embrulha em `pcall` e cita o `NodePath`, nunca reconstrói a mensagem.

	Pela MESMA razão, o ramo `IsServiceRoot` valida `Services.IsServiceClass`/
	`Services.IsSimulatedClass` ANTES de chamar `game:GetService` -- `DataModel.GetService`
	(`runtime`) devolve erro em PORTUGUÊS voltado a quem programa o motor ("classe não registrada
	em ClassRegistry"), nunca pensado para chegar a um usuário final; validar antes evita que esse
	texto interno vaze para um `Diagnostic` e garante uma mensagem em inglês, na família
	`[LuauBench] ... not simulated yet`, para uma Service real do dump só ainda não coberta por
	esta leva (ex.: "Teams", "Chat" -- a leva 1 de `services` cobre só os 9 Services core, ver
	`.claude/agents-memory/arquiteto-services-2026-09-05.md`, "Prioridade de cobertura"). O
	`Name ~= ClassName`/`not IsServiceClass` continuam como defesa em profundidade pura (só
	alcançáveis com um `InstancePlan` montado à mão, fora de `TreePlanner.Plan` -- ver comentário
	de cada `Messages.Materialize*` correspondente).

	Raiz com `$className ~= "DataModel"` -> erro dedicado (Decisão 14): projeto de modelo/pacote
	não tem `game`. `TreePlanner` NUNCA valida isso (ele só sabe resolver ClassName -- decidir se
	o resultado serve para `luaubench run` é responsabilidade de quem materializa), então é
	AQUI que a checagem mora, antes de qualquer Instance ser criada.

	Devolve `Scripts` NA ORDEM DETERMINÍSTICA DO PLANO -- pré-ordem (nó antes dos filhos),
	seguindo `plan.Roots` e depois `PlanNode.Children`, ambos já ordenados por `TreePlanner`
	(Decisão 6/8: `table.sort` sobre o nome do filho) -- para que `ScriptRunner` (task-cli-006)
	não precise reandar a árvore para descobrir a ordem de execução.

	NÃO requer `TreePlanner.luau` para nada além de TIPOS (`PlanNode`/`InstancePlan`) -- não chama
	nenhuma função de lá. Requer `../runtime` e `../services` (os agregadores públicos dos dois
	territórios vizinhos, nunca um módulo interno de `generated/`/`behavior/`) -- é o contrato
	"cli -> runtime"/"cli -> services" do desenho, seção "Contrato entre territórios".
]]

local Runtime = require("../runtime")
local Services = require("../services")
local Diagnostics = require("./Diagnostics")
local Messages = require("./Messages")
local TreePlanner = require("./TreePlanner")

export type MaterializedScript = {
	Instance: Runtime.Instance,
	Node: TreePlanner.PlanNode,
	FullName: string,
}

export type MaterializedTree = {
	Game: Runtime.DataModel,
	Scripts: { MaterializedScript },
}

local TreeMaterializer = {}

-- As três classes que `ScriptRunner` (task-cli-006) precisa localizar depois -- carregadas mas
-- só `Script` de fato executa (política de execução é território daquela tarefa, não desta).
local SCRIPT_CLASS_NAMES: { [string]: boolean } = {
	Script = true,
	LocalScript = true,
	ModuleScript = true,
}

-- task-cli-010 (correção de revisão, achado MÉDIO de revisor-cli-runcommand-2026-09-05.md): o
-- `__newindex` real de `runtime` levanta o erro de `$properties` inválido com `error(msg, 2)`
-- (`Instance.luau:662`/`688`/etc) -- nível 2 aponta para o CALL SITE de quem chamou o `__newindex`,
-- que aqui é sempre a closure `writable[key] = value` dentro do `pcall`, logo abaixo, em
-- `applyProperties`. Isso faz o Luau prefixar `tostring(err)` com a localização de QUEM CHAMOU
-- (`<chunk deste módulo>:<linha>: `) em vez da localização de dentro do `__newindex` -- e o "chunk
-- deste módulo", do jeito que o Lune nomeia um chunk `require`ido, é o CAMINHO ABSOLUTO EM DISCO de
-- `TreeMaterializer.luau` (ex.: `D:\...\src\cli\TreeMaterializer:136: `). Diferente do erro de
-- SCRIPT DO USUÁRIO (onde o call site É o arquivo do usuário, e citá-lo é correto/fiel ao Roblox --
-- ver `OutputFormatter.luau`), aqui o call site é SEMPRE um módulo interno do CLI: repassar
-- `tostring(err)` cru vazaria o caminho de instalação do LuauBench no disco de quem roda, violando
-- a regra 04 ("nunca stack trace cru do parser" -- mesma categoria de vazamento de detalhe de
-- implementação).
--
-- `stripEngineErrorLocation`, abaixo, corta esse prefixo pelo mesmo princípio que
-- `OutputFormatter.tryReattributeModuleError` já usa para o marcador `[string "..."]:<n>: ` de erro
-- de módulo requerido: casar o padrão `<algo>:<número>: ` e devolver só o que vem DEPOIS. A âncora
-- `^.-:%d+: ` (início da string, `.-` não-guloso) é o que garante casar o PRIMEIRO `:<número>: `
-- encontrado, não um `: ` qualquer em qualquer posição -- importante porque a MENSAGEM REAL do
-- motor pode conter `: ` dela mesma (ex.: "field: Gravty" citado por outros diagnósticos deste
-- arquivo) e até `:<dígitos>:` sem ser localização (ex.: um horário "5:00" hipotético dentro do
-- texto) -- `.-` expande caractere a caractere até o resto do padrão casar pela primeira vez, então
-- qualquer `:<dígitos>: ` que apareça DEPOIS do primeiro nunca é escolhido por engano. Caminho no
-- Windows tem colchete `D:\` logo no início, mas `:` seguido de `\` (não dígito) nunca casa
-- `%d+`, então `.-` continua expandindo até o `:136: ` de verdade -- confirmado por reprodução
-- manual antes de escrever este código (`lune run` contra o erro real de `$properties.Gravty`).
--
-- Esta função vive AQUI, não em `Messages.luau` -- o cabeçalho daquele arquivo é explícito
-- ("nenhuma lógica de ramificação além de formatação simples"; decisão sobre O QUE mostrar é de
-- quem chama), e decidir SE um prefixo de localização deve ser cortado (via `string.match`) é uma
-- decisão, não formatação pura -- mesmo lugar onde `OutputFormatter.tryReattributeModuleError` mora
-- pela mesma razão. Se o padrão não casar (erro sem prefixo de localização reconhecível -- caso
-- defensivo, não observado na prática), devolve `rawError` sem alteração: nunca esconde a mensagem
-- real do motor por excesso de zelo.
local function stripEngineErrorLocation(rawError: string): string
	local rest = string.match(rawError, "^.-:%d+: (.*)$")
	if rest == nil then
		return rawError
	end
	return rest
end

-- Aplica `$properties` (já filtrado para boolean/number/string por `TreePlanner`, Decisão 7) pela
-- via PÚBLICA de escrita -- deixa o `__newindex` real do runtime validar contra o `ClassSchema` e
-- devolver a mensagem certa (nome inválido, propriedade somente-leitura, evento/método
-- protegido). Ordem alfabética das chaves: `PlanNode.Properties` é um mapa Lua sem ordem própria,
-- e diagnósticos em ordem determinística são o que torna um teste com múltiplas propriedades
-- inválidas no mesmo nó reproduzível.
local function applyProperties(instance: Runtime.Instance, node: TreePlanner.PlanNode, bag: Diagnostics.Bag): ()
	local propertyNames: { string } = {}
	for key in node.Properties do
		table.insert(propertyNames, key)
	end
	table.sort(propertyNames)

	for _, key in propertyNames do
		local value = node.Properties[key]

		-- Cast de fronteira (Decisão 7): `Runtime.Instance` é um tipo de campos
		-- NOMEADOS (o schema de cada classe concreta é uma interseção fechada, decidida por
		-- `services`) -- não existe assinatura estática para "escreva a propriedade cujo nome é
		-- esta string que veio de um arquivo JSON em disco". O cast widening por `unknown` (nunca
		-- um `any` disfarçado -- o valor É de fato uma Instance em runtime) é o que permite indexar
		-- por uma chave dinâmica; a VALIDAÇÃO real (a chave existe? é gravável?) continua 100% a
		-- cargo do `__newindex` verdadeiro, chamado logo abaixo dentro do `pcall` -- este cast não
		-- pula NENHUM enforcement, só muda o tipo que o compilador enxerga do lado esquerdo do `=`.
		local writable = (instance :: unknown) :: { [string]: unknown }
		local ok, err = pcall(function()
			writable[key] = value
		end)

		if not ok then
			bag:Add({
				Severity = "error",
				Code = "materialize/invalid-property",
				Message = Messages.MaterializePropertyAssignmentFailed(node.NodePath, key, stripEngineErrorLocation(tostring(err))),
				NodePath = node.NodePath,
				Field = key,
			})
		end
	end
end

-- Cria a Instance de UM nó (Service ou não) e aplica `Source`/`$properties`. Devolve `nil` se a
-- criação falhou de verdade (classe inválida/não simulada, Service não coberto, defesas em
-- profundidade de Decisão 4) -- quem chama já colocou o `Diagnostic` correspondente no `bag` e
-- pula a subárvore inteira (sem Instance criada, não há onde parentear os filhos).
local function createInstance(node: TreePlanner.PlanNode, parent: Runtime.Instance, game: Runtime.DataModel, bag: Diagnostics.Bag): Runtime.Instance?
	if node.IsServiceRoot then
		-- Defesa em profundidade #1 (Decisão 4): TreePlanner (plan/service-name-mismatch) já barra
		-- isto no caminho normal -- só alcançável com um InstancePlan montado à mão.
		if node.Name ~= node.ClassName then
			bag:Add({
				Severity = "error",
				Code = "materialize/service-name-mismatch",
				Message = Messages.MaterializeServiceNameMismatch(node.NodePath, node.Name, node.ClassName),
				NodePath = node.NodePath,
			})
			return nil
		end

		-- Defesa em profundidade #2: TreePlanner só marca IsServiceRoot depois de confirmar
		-- Services.IsServiceClass -- só alcançável com um InstancePlan montado à mão.
		if not Services.IsServiceClass(node.ClassName) then
			bag:Add({
				Severity = "error",
				Code = "materialize/not-a-service",
				Message = Messages.MaterializeNotAService(node.NodePath, node.ClassName),
				NodePath = node.NodePath,
			})
			return nil
		end

		-- Caso REAL e alcançável por um projeto de usuário legítimo: a classe É uma Service do
		-- dump, mas esta leva de `services` ainda não a cobre (ex.: "Teams"). Validado ANTES de
		-- chamar `game:GetService` de propósito -- `DataModel.GetService` erraria em português,
		-- voltado a quem programa `runtime`, nunca pensado para chegar a um usuário final.
		if not Services.IsSimulatedClass(node.ClassName) then
			local dump = Services.GetDumpVersion()
			bag:Add({
				Severity = "error",
				Code = "materialize/service-not-simulated",
				Message = Messages.MaterializeServiceNotSimulated(node.NodePath, node.ClassName, dump.Version),
				NodePath = node.NodePath,
			})
			return nil
		end

		return game:GetService(node.ClassName)
	end

	-- Resto: `Services.new` (NUNCA `Runtime.ClassRegistry.NewEngineInstance` -- ver cabeçalho
	-- deste arquivo) + `.Parent = pai`. `pcall` porque `Services.new` pode falhar de verdade para
	-- um "$className" explícito que TreePlanner nunca valida contra `services` (typo, ou classe
	-- real ainda não simulada) -- ver cabeçalho, "DEFESA EM PROFUNDIDADE".
	-- Tipo de retorno do closure anotado como `unknown` (nunca o tipo de sucesso real) -- mesmo
	-- protocolo já usado em `TreePlanner.luau` (`readMetaFile`/`resolveCore`, `pcall(function():
	-- unknown ... end)`) para todo `pcall` cujo caminho de falha devolve algo que NÃO é do tipo de
	-- sucesso (aqui, a mensagem de erro do `error()`, não uma `Runtime.Instance`) -- anotar o tipo
	-- de sucesso direto no closure tornaria o valor de erro EM CASO DE FALHA erroneamente tipado
	-- como `Runtime.Instance`.
	local ok, resultOrError = pcall(function(): unknown
		return Services.new(node.ClassName, node.Name)
	end)

	if not ok then
		bag:Add({
			Severity = "error",
			Code = "materialize/invalid-class",
			Message = Messages.MaterializeInvalidClass(node.NodePath, node.ClassName, tostring(resultOrError)),
			NodePath = node.NodePath,
		})
		return nil
	end

	local instance = resultOrError :: Runtime.Instance
	instance.Parent = parent
	return instance
end

-- Materializa UM nó e recursa nos filhos, em pré-ordem (nó antes dos filhos) -- é essa ordem,
-- combinada com `PlanNode.Children` já vir ordenado por nome (TreePlanner), que dá a ordem
-- DETERMINÍSTICA do plano exigida pelo acceptance.
local function materializeNode(node: TreePlanner.PlanNode, parent: Runtime.Instance, game: Runtime.DataModel, scripts: { MaterializedScript }, bag: Diagnostics.Bag): ()
	local instance = createInstance(node, parent, game, bag)
	if instance == nil then
		-- Erro já registrado no bag por createInstance -- subárvore inteira pulada (sem Instance
		-- própria, não há onde parentear os filhos; regra 00: nunca crash, mas também nunca
		-- materializar um filho "flutuando" sem o pai que o projeto pedia).
		return
	end

	-- Source (Decisão 5) -- via SetPropertyRaw, fora do schema, invisível ao script.
	if node.Source ~= nil then
		Runtime.Instance.SetPropertyRaw(instance, "Source", node.Source)
	end

	-- $properties (Decisão 7) -- via pública, um Diagnostic por propriedade que falhar, nunca
	-- interrompe o resto do nó nem da árvore.
	applyProperties(instance, node, bag)

	if SCRIPT_CLASS_NAMES[node.ClassName] then
		table.insert(scripts, {
			Instance = instance,
			Node = node,
			FullName = instance:GetFullName(),
		})
	end

	for _, child in node.Children do
		materializeNode(child, instance, game, scripts, bag)
	end
end

-- API pública. `game` já precisa existir (`Runtime.DataModel.new()`, criado por `RunCommand`,
-- task-cli-006) -- este módulo nunca cria o `DataModel`, só o povoa (mesma separação de
-- responsabilidade do resto do território: quem monta o pipeline decide QUANDO criar o
-- DataModel/Scheduler/Bootstrap, este módulo só sabe POVOAR um que já existe).
function TreeMaterializer.Materialize(plan: TreePlanner.InstancePlan, game: Runtime.DataModel, bag: Diagnostics.Bag): MaterializedTree
	-- Decisão 14: raiz que não resolve para "DataModel" -> erro dedicado, ANTES de qualquer
	-- Instance ser criada (mesma disciplina de "falha antes de mutar" de TreePlanner, Decisão 3).
	if plan.RootClassName ~= "DataModel" then
		bag:Add({
			Severity = "error",
			Code = "materialize/root-not-datamodel",
			Message = Messages.MaterializeRootNotDataModel(plan.RootClassName),
			ProjectPath = plan.ProjectPath,
		})
		return { Game = game, Scripts = {} }
	end

	local scripts: { MaterializedScript } = {}
	for _, root in plan.Roots do
		materializeNode(root, game, game, scripts, bag)
	end

	return { Game = game, Scripts = scripts }
end

return TreeMaterializer
