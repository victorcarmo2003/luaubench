--!strict

--[[
	Política de execução e disparo (arquiteto-cli-2026-09-05.md, Decisão 11, "O que executa, em
	que ordem, e o que só é carregado" -- LER A DECISÃO INTEIRA antes de mexer aqui). É o módulo
	que decide, para cada `Script`/`LocalScript`/`ModuleScript` já materializado por
	`TreeMaterializer` (task-cli-004), se ele roda de verdade, e em que ordem.

	REGRA DE ELEGIBILIDADE (Decisão 11, verbatim):
	- `Script` roda se (a) é descendente de um contêiner de `RunPolicy.ServerScriptContainers`
	  (default `{"ServerScriptService", "Workspace"}` -- aproximação declarada, pendente de
	  `task-cli-007`/pesquisador confirmar a lista exata de RunContext Legacy contra um servidor
	  Roblox real) e (b) `Enabled ~= false` (o default do schema gerado é `nil`, não `true` --
	  `BaseScript.luau` gerado, `Schema.Enabled.Default = nil` -- então `Enabled ~= false` já
	  cobre o caso comum de a propriedade nunca ter sido setada).
	- `LocalScript` NUNCA executa -- LuauBench é servidor (`RunService:IsServer() == true`,
	  decisão já fechada no desenho de `services`). É carregado (`Source` já materializado por
	  `TreeMaterializer`, disponível via `require`/inspeção), e o sumário final conta quantos
	  foram -- nunca omitido em silêncio (regra 00).
	- `ModuleScript` nunca executa sozinho -- só via `require` (Decisão 5, `ModuleLoader.luau`).
	  Não aparece em nenhum campo do `RunSummary`: não é nem "executado" nem "pulado", porque
	  nunca foi candidato a rodar como script de entrada -- é exatamente a semântica real do
	  Roblox (um `ModuleScript` sozinho, sem `require`, nunca faz nada).

	ORDEM DE EXECUÇÃO (Decisão 11, "determinística -- profundidade primeiro, contêineres na ordem
	de `ServerScriptContainers`, irmãos por nome"; DIVERGÊNCIA DECLARADA: o Roblox real NÃO
	garante nenhuma ordem entre `Script`s -- esta é *uma* ordem estável, escolhida para depuração
	reprodutível, nunca uma tentativa de replicar uma ordem real que não existe):
	`tree.Scripts` (produzido por `TreeMaterializer.Materialize`) já vem em pré-ordem (nó antes
	dos filhos) com irmãos ordenados por nome -- mas numa única lista FLAT cobrindo a árvore
	inteira, com os `Roots` (contêineres de topo) na ordem alfabética que `TreePlanner` usa para
	QUALQUER filho (Decisão 6/8), não na ordem de `ServerScriptContainers`. Coincide com o default
	(`ServerScriptService` < `Workspace` alfabeticamente), mas não seria fiel a uma
	`ServerScriptContainers` customizada com ordem diferente -- por isso este módulo NÃO confia na
	ordem relativa entre contêineres da lista `tree.Scripts`: agrupa explicitamente por contêiner,
	na ordem de `RunPolicy.ServerScriptContainers`, preservando (dentro de cada grupo) a ordem
	relativa original de `tree.Scripts` -- que já é profundidade+nome corretos dentro daquele
	contêiner, sem precisar reandar a árvore.

	`Scheduler:Spawn` (chamado por `Runtime.Sandbox.Run`, dentro de `runScript` abaixo) roda a
	função do script ATÉ O PRIMEIRO YIELD/término antes de devolver -- combinado com este módulo
	chamando `runScript` sequencialmente (nunca em paralelo) para cada script elegível, isso é o
	que garante "script N+1 só é spawnado depois que N cedeu ou terminou" (Decisão 11).

	Depende de `TreeMaterializer.luau` (só TIPOS -- `MaterializedTree`/`MaterializedScript`/
	`PlanNode`, nenhuma função), `../runtime` (`Sandbox.Run`, `Instance.GetPropertyRaw`, tipos),
	`ModuleLoader.luau` e `ScriptEnvironment.luau` (para montar o `require`/`extraGlobals` de cada
	Script elegível -- o MESMO par usado por `ModuleLoader` para um `ModuleScript` requerido,
	Decisão 5). NUNCA `../services` diretamente -- quem decide `Instance.new`/`game`/`workspace`
	é sempre `ScriptEnvironment.luau` (regra 00: um único lugar decide o que um script enxerga).
]]

local Runtime = require("../runtime")
local ModuleLoader = require("./ModuleLoader")
local ScriptEnvironment = require("./ScriptEnvironment")
local TreeMaterializer = require("./TreeMaterializer")

export type RunPolicy = {
	ServerScriptContainers: { string },
	-- Reservado para um futuro modo `--client` (fora desta leva -- arquiteto-cli-2026-09-05.md,
	-- "Escopo da leva 1", "Não entra"). `ScriptRunner.Run` IGNORA este campo nesta leva: um
	-- `LocalScript` nunca executa, mesmo que alguém construa um `RunPolicy` com
	-- `RunLocalScripts = true` -- é o tipo público já preparado para a extensão futura, sem
	-- implementar comportamento que ninguém pediu ainda (regra 00: nunca fingir suporte).
	RunLocalScripts: boolean,
}

export type RunSummary = {
	Executed: number,
	SkippedLocalScripts: number,
	SkippedByContainer: number,
	SkippedDisabled: number,
}

export type RunContext = {
	Scheduler: Runtime.Scheduler,
	Game: Runtime.DataModel,
	Workspace: Runtime.Instance,
	-- `_G`/`shared` do run inteiro -- UMA tabela de cada, compartilhada entre TODOS os scripts
	-- (top-level e módulos requeridos) do mesmo `luaubench run` (mesma disciplina de
	-- `ScriptEnvironment.EnvironmentContext`/`ModuleLoaderOptions`; quem cria as duas tabelas é
	-- `RunCommand`, task-cli-006, nunca este módulo).
	GlobalTable: { [string]: unknown },
	SharedTable: { [string]: unknown },
	-- Compartilhado entre TODOS os `ModuleLoader` que este `ScriptRunner.Run` cria (um por Script
	-- elegível) -- é o que garante que dois Scripts diferentes requerendo o MESMO `ModuleScript`
	-- vejam o cache compartilhado (ver cabeçalho de `ModuleLoader.luau`, "por que uma instância
	-- por Script"). Criado por `RunCommand` via `ModuleLoader.NewCache()`.
	ModuleCache: ModuleLoader.ModuleCache,
	OnOutput: (record: Runtime.OutputRecord) -> (),
	Policy: RunPolicy,
}

local ScriptRunner = {}

-- Default de `RunPolicy.ServerScriptContainers` (Decisão 11) -- aproximação declarada, pendente
-- de confirmação de pesquisador (task-cli-007) contra a lista exata de contêineres de
-- `RunContext.Legacy` num servidor Roblox real.
function ScriptRunner.DefaultPolicy(): RunPolicy
	return {
		ServerScriptContainers = { "ServerScriptService", "Workspace" },
		RunLocalScripts = false,
	}
end

-- Resolve os NOMES de `RunPolicy.ServerScriptContainers` para as Instances de verdade, na MESMA
-- ordem da lista -- um nome sem Instance correspondente sob `game` (contêiner customizado que o
-- projeto não declarou, e que não está entre `Services.GetSimulatedServiceClasses()`) é
-- simplesmente omitido: nenhum Script pode estar "dentro" de um contêiner que não existe, então
-- não há nada a fazer além de ele nunca aparecer na lista de elegíveis (cai em
-- `SkippedByContainer` mais abaixo, junto com qualquer outro Script fora de todo contêiner).
-- `FindFirstChild` (não-recursivo) porque um contêiner de `ServerScriptContainers` é sempre um
-- filho DIRETO do `DataModel` (Service, ou um Folder de topo em tese) -- nunca aninhado.
local function resolveContainers(game: Runtime.DataModel, containerNames: { string }): { Runtime.Instance }
	local containers: { Runtime.Instance } = {}
	for _, name in containerNames do
		local found = game:FindFirstChild(name)
		if found ~= nil then
			table.insert(containers, found)
		end
	end
	return containers
end

-- Cast de fronteira (mesmo padrão de `TreeMaterializer.applyProperties`): lemos a propriedade
-- "Enabled" por nome fixo, mas o tipo público `Runtime.Instance` não a declara genericamente (só
-- a interseção `BaseScript`/`Script`, que `services` declara e `cli` nunca importa por nome --
-- regra 03, "cli nunca conhece nome de classe"). Quem chama garante, pelo `Node.ClassName ==
-- "Script"` já checado antes, que `instance` É de fato um `Script`/`BaseScript` de verdade -- o
-- cast só amplia o que o COMPILADOR enxerga, a leitura real continua passando pelo `__index` do
-- runtime (que resolve contra o `ClassSchema` de verdade).
local function isScriptDisabled(instance: Runtime.Instance): boolean
	local readable = (instance :: unknown) :: { Enabled: unknown }
	return readable.Enabled == false
end

-- Roda UM `Script` elegível: monta um `ModuleLoader`/`require` PRÓPRIO deste Script (Decisão 5 --
-- "por que uma instância por Script", `ModuleLoader.luau`), monta o `extraGlobals` via
-- `ScriptEnvironment.Build` (o MESMO par `game`/`workspace`/`script`/`Instance.new`/`_G`/`shared`
-- que qualquer `ModuleScript` requerido enxerga, só que `script` aponta para este próprio Script),
-- lê `Source` via `GetPropertyRaw` (canal reservado pelo desenho de `services`, Decisão 5 de
-- `cli` -- `Source` nunca passa pelo schema) e chama `Runtime.Sandbox.Run` de verdade.
local function runScript(entry: TreeMaterializer.MaterializedScript, context: RunContext): ()
	local loader = ModuleLoader.new({
		Scheduler = context.Scheduler,
		ScriptName = entry.FullName,
		OnOutput = context.OnOutput,
		Cache = context.ModuleCache,
		Game = context.Game,
		Workspace = context.Workspace,
		GlobalTable = context.GlobalTable,
		SharedTable = context.SharedTable,
	})

	local environmentContext: ScriptEnvironment.EnvironmentContext = {
		Game = context.Game,
		Workspace = context.Workspace,
		GlobalTable = context.GlobalTable,
		SharedTable = context.SharedTable,
		Require = function(target: unknown): unknown
			return loader:Require(target)
		end,
	}
	local globals = ScriptEnvironment.Build(environmentContext, entry.Instance)

	-- Mesmo fallback de `ModuleLoader.requireModule`: um Script criado só em memória (sem
	-- `Source` gravado -- não deveria acontecer vindo de `TreeMaterializer`, que sempre grava a
	-- partir de um arquivo real, mas é defesa em profundidade barata) vira corpo vazio em vez de
	-- propagar `nil` para `Sandbox.Run` (que espera `string`).
	local rawSource = Runtime.Instance.GetPropertyRaw(entry.Instance, "Source")
	local sourceText: string
	if typeof(rawSource) == "string" then
		sourceText = rawSource
	else
		sourceText = ""
	end

	-- Resultado (`SandboxResult{thread}`) descartado de propósito: `ScriptRunner` não precisa
	-- rastrear o handle -- é o `Scheduler` (via `scheduler:Run(shouldContinue)`, chamado por
	-- `RunCommand` depois que `ScriptRunner.Run` retorna) que decide quando threads pendentes
	-- (scripts que cederam) continuam.
	Runtime.Sandbox.Run({
		scriptName = entry.FullName,
		source = sourceText,
		scheduler = context.Scheduler,
		extraGlobals = globals,
		onOutput = context.OnOutput,
	})
end

-- API pública. `tree` já materializado por `TreeMaterializer.Materialize` (task-cli-004) --
-- `game`/hierarquia/Source/`$properties` já aplicados; este módulo só decide QUAIS `Script`s de
-- `tree.Scripts` rodam, em que ordem, e conta o resto.
function ScriptRunner.Run(tree: TreeMaterializer.MaterializedTree, context: RunContext): RunSummary
	local summary: RunSummary = {
		Executed = 0,
		SkippedLocalScripts = 0,
		SkippedByContainer = 0,
		SkippedDisabled = 0,
	}

	-- LocalScript: contado incondicionalmente, independente de container -- Decisão 11 não faz
	-- nenhuma distinção de container para LocalScript (nunca executa em lugar nenhum).
	for _, entry in tree.Scripts do
		if entry.Node.ClassName == "LocalScript" then
			summary.SkippedLocalScripts += 1
		end
	end

	local containers = resolveContainers(context.Game, context.Policy.ServerScriptContainers)

	-- `assigned`: marca todo `Script` já atribuído a ALGUM contêiner -- evita contá-lo duas vezes
	-- se, por acaso, dois contêineres da política estivessem aninhados um dentro do outro (caso
	-- de borda não coberto por fixture, mas barato de proteger: o PRIMEIRO contêiner da lista que
	-- contém o Script vence, coerente com "contêineres na ordem de ServerScriptContainers").
	local assigned: { [Runtime.Instance]: boolean } = {}
	local orderedEligible: { TreeMaterializer.MaterializedScript } = {}

	for _, container in containers do
		for _, entry in tree.Scripts do
			if entry.Node.ClassName == "Script" and not assigned[entry.Instance] and entry.Instance:IsDescendantOf(container) then
				assigned[entry.Instance] = true
				table.insert(orderedEligible, entry)
			end
		end
	end

	-- Todo `Script` que sobrou sem contêiner (ex.: sob `ReplicatedStorage`) -> carregado, nunca
	-- executado, contado (Decisão 11: "carregado mas não executado -- fiel ao Roblox").
	for _, entry in tree.Scripts do
		if entry.Node.ClassName == "Script" and not assigned[entry.Instance] then
			summary.SkippedByContainer += 1
		end
	end

	for _, entry in orderedEligible do
		if isScriptDisabled(entry.Instance) then
			summary.SkippedDisabled += 1
		else
			runScript(entry, context)
			summary.Executed += 1
		end
	end

	return summary
end

return ScriptRunner
