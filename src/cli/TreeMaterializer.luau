--!strict

--[[
	`InstancePlan` (`TreePlanner.luau`, task-cli-003) -> `DataModel` real (arquiteto-cli-2026-09-
	05.md, Decisões 4, 5 e 7 -- LER ESSAS TRÊS INTEIRAS antes de mexer aqui). É o primeiro módulo
	de `cli` que toca `runtime`/`services` de verdade: `TreePlanner` deliberadamente não conhece
	nenhum dos dois (Decisão 3, "planejar antes de materializar"), então é AQUI que o plano puro
	vira Instance simulada.

	Três caminhos em `createInstance`, NUNCA dois (correção task-cli-016, arquiteto-cli-2026-09-
	05.md, seção "Revisão pós-implementação 2026-09-05 (task-cli-015) -- filho fixo do motor:
	adotar, não criar" -- LER A SEÇÃO INTEIRA antes de mexer aqui):

	1. `IsServiceRoot` -> `game:GetService(ClassName)` (singleton do motor, parenteado direto sob
	   a raiz).
	2. `Services.IsEngineFixedChild(parent.ClassName, node.Name, node.ClassName)` -> ADOTA a
	   Instance que `behavior/<Pai>.luau` já criou dentro do pai no bootstrap
	   (`parent:FindFirstChild(node.Name)`), NUNCA cria uma nova. É o caso de
	   `StarterPlayerScripts`/`StarterCharacterScripts` dentro de `StarterPlayer`: esses filhos são
	   `IsAbstract = true` (não instanciáveis por `Instance.new`, fiel ao Roblox real) E já nascem
	   pré-criados pelo `Initialize` do Service pai -- uma API de CRIAÇÃO aqui produziria um IRMÃO
	   DUPLICADO de mesmo nome (o do motor, vazio, e o do `.project.json`, com os scripts do
	   usuário), e `FindFirstChild`/acesso por ponto no script do usuário resolveria para o
	   PRIMEIRO (o do motor) -- trocaria o erro alto de hoje (`materialize/invalid-class`) por uma
	   DIVERGÊNCIA SILENCIOSA, exatamente o que a regra 00 proíbe. O Rojo real, sincronizando
	   contra um `DataModel` vivo, também nunca instancia esses nós -- ele faz merge dentro do
	   filho que o motor já criou. Devolve a instância adotada SEM tocar em `.Parent` -- ela já
	   está parenteada pelo motor, e reatribuir o MESMO pai (ainda que hoje seja um no-op de
	   disparo, `Instance.spec.luau`, "reatribuir o mesmo Parent não deveria disparar
	   Changed/ChildAdded") não tem nenhum motivo para acontecer aqui. `parent.ClassName` (da
	   Instance já materializada, não do `PlanNode` planejado) é a única informação nova
	   necessária, e já está disponível -- `PlanNode` NÃO ganha campo novo, `TreePlanner.luau` NÃO
	   é tocado.
	3. Todo o resto -> `Services.new(ClassName, Name)` seguido de `.Parent = pai`.

	Os ramos são mutuamente exclusivos por construção: `IsServiceRoot` só é `true` quando o pai é
	o `DataModel`, e `DataModel` não é chave de `EngineFixedChildren` -- e a ordem (1, depois 2,
	depois 3) preserva byte a byte o comportamento de todo projeto que já materializava sem erro
	antes desta correção.

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

	CORREÇÃO task-cli-038 (arquiteto-rojo-properties-2026-09-07.md, seções D4/4/5 -- LER ANTES de
	mexer em `applyProperties`): a Decisão 7 original ("`$properties` vai pela via PÚBLICA de
	escrita, nunca por `SetPropertyRaw`") tratava `$properties` como se fosse ESCRITA DE SCRIPT --
	e por isso herdava, sem querer, o gate de `Security`/`ReadOnly` que só faz sentido para um
	`Script` do projeto lendo/escrevendo em runtime. Pesquisa confirmada contra o código-fonte real
	do Rojo (`pesquisa-rojo-properties-security-2026-09-07.md`): `rojo build` é um caminho de
	DESERIALIZAÇÃO/HIDRATAÇÃO que nunca consulta Security/Scriptability/Serialization ao aplicar
	`$properties` -- só valida que o NOME existe como `Property` na cadeia de classes e que a FORMA
	do JSON bate com o `DataType`. Isso derrubava o template padrão do `rojo init`
	(`Lighting.Technology`, `Workspace.FilteringEnabled`), que antes desta correção nem chegava a
	existir no schema ou errava "Property is read only".

	`applyProperties`, abaixo, agora bifurca por instância (uma vez por nó, nunca por propriedade):

	CAMINHO A -- instância ESTRITA (`Runtime.ClassRegistry.IsRegistered(ClassName) == true`, todo
	nó real do projeto): `Name`/`Parent`/`ClassName` são SKIP com warning
	`materialize/structural-property-ignored` (paridade literal com `project.rs:234-260`, que só
	trata `Name`/`Parent` como caso especial via `log::warn!`+`continue`; `ClassName` entra pela
	MESMA regra por analogia estrutural -- no LuauBench é estado FORA de `data.properties`, e
	gravar cru seria estado morto e silencioso). Daí resolve o `MemberDescriptor` no schema
	ACHATADO (`findMemberDescriptor`, que a partir de task-services-035 também enxerga as entradas
	`ScriptVisible = false` -- "existe estruturalmente" é o eixo certo para hidratação, não "o
	script enxerga"): descritor `nil` -> `materialize/invalid-property`
	(`Messages.MaterializePropertyNotAMember`, mesma frase que o `__newindex` real produziria, mas
	CONSTRUÍDA aqui -- ver por quê, abaixo); `Kind ~= "Property"` (Event/Callback) ->
	`materialize/invalid-property` (`Messages.MaterializePropertyNotAProperty`) -- é a barreira
	dura que garante que NENHUM evento vira gravável por projeto, mesmo para um valor primitivo
	que passaria batido pelo decode. Passadas as duas guardas, a escrita é por
	`Runtime.Instance.SetPropertyRaw(instance, key, value)` -- ignora `ReadOnly` E `ScriptVisible`,
	exatamente como o `rojo build` real ignora `scriptability`/`serialization`. `Messages.
	MaterializePropertyNotAMember`/`MaterializePropertyNotAProperty` precisam CONSTRUIR a frase (não
	colher de um `pcall`): não existe mais nenhum `__newindex` real sendo chamado neste caminho para
	produzi-la sozinho -- essas duas guardas (nome inexistente/Kind errado) SÃO alcançáveis sem
	efeito colateral nenhum. A escrita em si, porém, PRECISA de `pcall` (CORREÇÃO DE REVISÃO,
	achado do revisor de task-cli-038): `SetPropertyRaw` dispara `Changed:Fire` de forma SÍNCRONA,
	que pode invocar um listener que `services` já conectou no bootstrap (ex.:
	`behavior/Lighting.luau`, "TimeOfDay") e que pode `error()`ar sobre um valor que passou pelo
	decode de FORMA (A3) mas é semanticamente inválido (ex.: `"not-a-real-time"` é uma `string`
	válida, mas `parseTimeOfDay` a rejeita) -- ver o comentário completo no ponto de uso, abaixo,
	para a cadeia exata (`Signal.Fire` re-lança o primeiro erro quando a thread chamadora não é
	gerida pelo `ThreadBroker`, o caso de `Materialize` rodando antes do `scheduler:Run`).

	CAMINHO B -- instância LENIENTE (só `game`/DataModel, `IsRegistered == false`): INTOCADO --
	`local writable = (instance :: unknown) :: { [string]: unknown }` -- um dos casts de fronteira
	deste módulo (o outro é o narrowing do resultado de `pcall(Services.new)`, mais abaixo), cada
	um comentado no próprio ponto de uso -- e a escrita roda dentro de `pcall`, deixando o
	`__newindex` REAL do runtime (que já sabe validar contra o `ClassSchema`/`readOnlyRawKeys` e
	devolver a mensagem certa da família Roblox) fazer o enforcement. Falha -> `Diagnostic` de erro
	citando `NodePath` + o nome da propriedade + a mensagem do motor (via `pcall`), NUNCA derruba
	`Materialize`. DV-2 (declarada no desenho): `PlaceId`/`JobId`/`GameId`/`PlaceVersion` continuam
	recusadas aqui -- são estado do HOST que o próprio LuauBench define, não estado do projeto; o
	Rojo real as aceitaria, mas abrir isso é decisão de usuário fora do escopo desta tarefa.

	Em AMBOS os caminhos: a decodificação (`resolvePropertyValue`/`ValueTypes.Decode.FromRojoJson`,
	os 3 diagnósticos que ela já produzia) é INALTERADA -- só a guarda de ENTRADA (Caminho A) e o
	mecanismo de ESCRITA final divergem.

	DV-1 (declarada no desenho): um valor hidratado numa propriedade `ScriptVisible = false` fica
	só no DOM -- nenhum comportamento simulado reage a ele (`Lighting.Technology = Voxel` não muda
	render nenhum, porque não há render). DV-6 (declarada no desenho): `$properties.Source` num
	`Script`/`ModuleScript` agora É aceito (a partir de task-services-035, `Source` existe no schema
	achatado como `ScriptVisible = false`) e SOBRESCREVE o `Source` vindo do `$path` -- a escrita de
	`node.Source` via `SetPropertyRaw` roda ANTES de `applyProperties` em `materializeNode`, então a
	segunda escrita (via `$properties`) vence. O Rojo real também aceita `Source` em `$properties`
	e não concede poder novo (o `$path` do próprio projeto já traz código arbitrário).

	task-cli-025 (arquiteto-valuetypes-2026-09-05.md, seção 3.4 "cli" / Decisão 5, seção 7):
	`TreePlanner` deixou de filtrar `$properties` não-primitivo (array/objeto do JSON) -- o valor
	bruto atravessa o plano intacto (`TreePlanner.PlanPropertyValue`), porque só AQUI, depois que a
	Instance real existe, o `MemberDescriptor` (`ValueType`/`ValueCategory`) de uma classe REAL é
	conhecível. `applyProperties`/`resolvePropertyValue` (abaixo) interceptam TODO valor
	não-primitivo ANTES da escrita e chamam `ValueTypes.Decode.FromRojoJson` -- nunca gravam um
	array/objeto cru via `writable[key] = value` (o `__newindex` real, em modo estrito, escreveria
	qualquer valor num Property gravável sem checar o tipo, o que corromperia silenciosamente um
	`Vector3`/`Color3` real com uma tabela crua -- exatamente o que a invariante 2 do projeto
	proíbe). Requer `../valuetypes` (o agregador público daquele território, nunca um módulo
	interno) -- primeira vez que `cli` toca aquele território.

	DEFESA EM PROFUNDIDADE (não pedida por `TreePlanner`, mas barata e consistente com a regra 00
	"nunca stack trace cru"/"nunca crash por entrada não confiável"): `Services.new` pode falhar
	de verdade para um `"$className"` explícito que `TreePlanner` nunca valida contra
	`services` (Decisão 4: `TreePlanner` só valida a INFERÊNCIA de Service, não que todo
	`$className` explícito seja uma classe real/simulada) -- ex.: um typo ("Frmae") ou uma classe
	real do dump ainda não coberta por esta leva ("Frame"). Sem isto, um `.project.json`
	perfeitamente bem-formado, mas citando uma classe que `services` não cria, derrubaria
	`Materialize` inteiro com um `error()` cru. `Services.new` devolve mensagens de bom CONTEÚDO
	(família Roblox real, ou o prefixo `[LuauBench] ... not simulated yet`) -- mas, CORREÇÃO
	task-cli-011 (achado ALTO de `revisor-cli-pathleak-fix-2026-09-05.md`): o comentário anterior
	aqui afirmava que isso bastava para "nunca vazar" e estava ERRADO -- `Services.new`
	(`src/services/init.luau`) levanta essas mensagens com `error(msg, 2)`, exatamente como o
	`__newindex` real do runtime (ver `stripEngineErrorLocation`, abaixo). Nível 2 aponta para o
	CALL SITE de quem chama `Services.new` dentro do `pcall`, que é sempre este módulo -- sem
	tratamento, `tostring(resultOrError)` vazaria o mesmo caminho absoluto em disco + linha interna
	do LuauBench que `applyProperties` já vazava antes de task-cli-010. Este módulo aplica a MESMA
	`stripEngineErrorLocation` também aqui (ver `createInstance`), então nunca reconstrói a
	mensagem -- só remove o prefixo de localização interna e cita o `NodePath`.

	Pela MESMA razão, o ramo `IsServiceRoot` valida `Services.IsServiceClass`/
	`Services.IsSimulatedClass` ANTES de chamar `game:GetService` -- e CONTINUA validando depois de
	task-runtime-030/task-cli-017 (`DataModel:GetService` passou de `-> Instance` para
	`-> Instance?`, ver .claude/agents-memory/arquiteto-runtime-2026-09-04.md, seção "Revisão
	pós-integração 2026-09-05 (5)", subseção "Riscos e decisões" -- ATUALIZAÇÃO DE COMENTÁRIO,
	comportamento inalterado): o motivo NÃO É MAIS "`DataModel.GetService` erraria em português"
	-- desde aquela tarefa, `GetService` para uma Service real do dump ainda não coberta já devolve
	a própria mensagem `[LuauBench] ... not simulated yet` em inglês (via o
	`UnknownClassResolver` que `services` instala em `Register()`), sem texto interno em português
	vazando. A pré-validação fica por DUAS razões que continuam verdadeiras: (1) o `Diagnostic`
	`materialize/service-not-simulated` cita o `NodePath` do nó no `.project.json` -- informação
	que `GetService` não tem e não pode ter, e sem ela o usuário não sabe ONDE no projeto está a
	Service não coberta; (2) sem a pré-validação, este ramo precisaria envolver
	`game:GetService(node.ClassName)` num `pcall` e aplicar `stripEngineErrorLocation` (mesmo
	tratamento do `pcall(Services.new(...))` logo abaixo) só para não derrubar `Materialize` com um
	`error()` não tratado -- a pré-validação mantém este caminho um simples `if`/`nil`, sem
	duplicar aquele padrão de `pcall`+strip por um segundo motivo. Cobertura de "Teams", "Chat" etc.
	segue a leva 1 de `services` (só os 9 Services core, ver
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
local ValueTypes = require("../valuetypes")
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

-- task-cli-025 (arquiteto-valuetypes-2026-09-05.md, seção 3.4 "cli", item (b)): índice O(1)
-- DERIVADO de `ValueTypes.Catalog.SimulatedNames()` -- nunca uma lista mantida à mão aqui (mesma
-- disciplina de `src/cli/UnsimulatedGlobals.luau`, que também deriva do mesmo `Catalog`). Usado por
-- `resolvePropertyValue` para decidir se um `ValueType` de categoria `"DataType"` já tem módulo em
-- `src/valuetypes/types/` (leva 1: Vector3/Vector2/Color3/CFrame/UDim/UDim2) ou ainda não (leva 2:
-- Rect/NumberRange/TweenInfo/...) -- ANTES de chamar `ValueTypes.Decode.FromRojoJson`, nunca depois
-- (a distinção entre "tipo não simulado" e "forma indecodificável" fica mais limpa consultando o
-- Catalog primeiro do que tentando inferir a partir da frase de erro do `Decode`). Construído uma
-- vez no load do módulo -- `Catalog` é dado ESTÁTICO por processo (mesma razão de
-- `UnsimulatedGlobals.luau` construir os `SENTINELS` uma única vez).
local SIMULATED_VALUE_TYPE_NAMES: { [string]: boolean } = {}
for _, name in ValueTypes.Catalog.SimulatedNames() do
	SIMULATED_VALUE_TYPE_NAMES[name] = true
end

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
-- task-cli-011 (correção de revisão, achado ALTO de revisor-cli-pathleak-fix-2026-09-05.md): a
-- MESMA classe de vazamento acontece em `createInstance`, mais abaixo, no `pcall(Services.new(...))`
-- -- `Services.new` (`src/services/init.luau`) também levanta com `error(msg, 2)`, e o call site
-- dentro do `pcall` também é sempre este módulo. Reproduzido com um `"$className": "Frmae"`
-- (typo): sem tratamento, a mensagem final citava `D:\...\TreeMaterializer:252: Unable to create
-- an Instance of type "Frmae"`. Por isso esta função é usada nos DOIS pontos deste arquivo onde um
-- erro vindo de dentro de `runtime`/`services` é embrulhado em `pcall` -- não é uma função
-- exclusiva de `$properties`.
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
--
-- Correção pontual (achado ALTO de revisão de task-cli-030): exportada como
-- `TreeMaterializer.StripEngineErrorLocation` -- `RunCommand.luau` tinha um `firstLineOf` PRÓPRIO
-- que só cortava a mensagem crua na primeira quebra de linha (mesma disciplina de
-- `CloudStore.firstLineOf`/`services/init.luau firstLineOf`, que tratam da stack traceback
-- multi-linha do Lune) mas NUNCA removia o prefixo `<caminho absoluto>:<linha>: ` que `error(msg,
-- <nível>)` antepõe -- vazando o caminho de instalação do LuauBench (ex.:
-- `D:\...\src\services:335:`, `D:\...\CloudStore:227:`) nas mensagens `[cloud/state-unreadable]`/
-- `[cloud/save-failed]`. É a MESMA classe de vazamento que esta função já resolve para
-- `applyProperties`/`createInstance` logo abaixo -- reusada em vez de duplicada (regra 01: uma
-- função, não duas cópias que podem divergir em silêncio). Continua sendo chamada localmente pelo
-- nome curto `stripEngineErrorLocation` nos dois pontos deste arquivo; a atribuição ao módulo é só
-- para tornar a MESMA implementação alcançável de fora (`RunCommand.luau`, que já `require`s este
-- módulo para os tipos `PlanNode`/`InstancePlan`).
local function stripEngineErrorLocation(rawError: string): string
	local rest = string.match(rawError, "^.-:%d+: (.*)$")
	if rest == nil then
		return rawError
	end
	return rest
end
TreeMaterializer.StripEngineErrorLocation = stripEngineErrorLocation

-- task-cli-025 (item b): resolve o `MemberDescriptor` de UMA propriedade -- é o que diz, pra um
-- array/objeto bruto do JSON, qual `ValueType`/`ValueCategory` decodificar contra (a mesma
-- ambiguidade que motivou todo o desenho de `ValueTypes.Decode`: "Lighting.Ambient" e
-- "Baseplate.Position" chegam aqui como o MESMO array de 3 números, e só o `MemberDescriptor` da
-- classe/propriedade diz qual é Color3 e qual é Vector3).
--
-- task-cli-028-fix (BUG REAL, testador + orquestrador confirmando por leitura de código): a MESMA
-- ambiguidade vale pra `string` -- "LockFirstPerson" (StarterPlayer.CameraMode) é a forma Rojo
-- padrão de um item de Enum via `$properties` (ver `Decode.luau`, `decodeEnum`: só aceita
-- `string`), e é indistinguível de uma `string` primitiva de verdade (`Name`, `ScriptSource`) só
-- olhando `typeof(raw)` -- as duas são `"string"`. É por isso que `resolvePropertyValue`, abaixo,
-- também consulta este `MemberDescriptor` para o caso `string`, não só array/objeto.
--
-- task-cli-027 (fecha a limitação declarada em task-cli-025, ver `.claude/agents-memory/
-- revisor-cli-task-cli-025-2026-09-05.md`): `runtime` passou a expor `ClassRegistry.
-- GetFlattenedSchema(className)` (task-runtime-036) -- o MESMO achatamento (própria classe + toda a
-- cadeia de superclasses) que `ClassRegistry.new`/`NewEngineInstance` já usava só internamente para
-- instalar o schema na Instance no momento da criação. Antes desta tarefa, `findMemberDescriptor`
-- só enxergava `ClassRegistry.Get(className).Schema` -- o schema PRÓPRIO, nunca o herdado (mesmo
-- espelhamento do campo `Superclass` do dump que o comentário de `ClassDescriptor.Schema` documenta)
-- -- então uma propriedade herdada (ex.: `Instance.Capabilities`, presente em TODA classe;
-- `BaseScript.LinkedSource`, herdada por `Script`/`LocalScript`) caía sempre no diagnóstico genérico
-- `materialize/property-shape-unknown`, mesmo sendo uma propriedade real e conhecida.
--
-- `GetFlattenedSchema` devolve SEMPRE uma tabela indexável (nunca `nil` -- `EMPTY_SCHEMA` congelada
-- quando nenhum elo da cadeia declara `Schema`, ver `ClassRegistry.luau`), mas ERRA (nível 2) para
-- `className` NÃO REGISTRADO -- distinção importante de "classe real sem esta propriedade". A ÚNICA
-- Instance que chega aqui com um `ClassName` não registrado em `ClassRegistry` é `game`/`DataModel`
-- (a raiz é construída à mão por `DataModel.luau`, NUNCA passa por `ClassRegistry.Register` -- ver
-- `DATA_MODEL_CLASS_CHAIN` naquele módulo): toda OUTRA Instance que chega em `resolvePropertyValue`
-- veio de `game:GetService(...)`, de um filho fixo adotado, ou de `Services.new(...)` -- os três
-- exigem uma classe já registrada (`ClassRegistry.new`/`NewEngineInstance` recusam classe
-- desconhecida). Por isso a checagem `IsRegistered` abaixo, ANTES de chamar `GetFlattenedSchema` --
-- preserva o comportamento de antes desta tarefa para "DataModel" (devolvia `nil` via
-- `ClassRegistry.Get`, modo LENIENTE) em vez de deixar o `error(..., 2)` de `GetFlattenedSchema`
-- vazar e derrubar `Materialize` inteiro para um `$properties` de raiz não-primitivo.
local function findMemberDescriptor(className: string, propertyName: string): Runtime.MemberDescriptor?
	if not Runtime.ClassRegistry.IsRegistered(className) then
		return nil
	end
	return Runtime.ClassRegistry.GetFlattenedSchema(className)[propertyName]
end

-- task-cli-025 (item b, Decisão 5/seção 7 do desenho de valuetypes): devolve o valor FINAL pronto
-- pra escrever, ou `nil` se a propriedade deve ser PULADA (o `Diagnostic` correspondente já foi
-- adicionado ao `bag` internamente). `raw` NUNCA é um `nil` de verdade aqui (chamador só itera
-- chaves que de fato existem em `properties` -- `$properties` nunca carrega `null`, ver
-- `JsonValue.luau`), então devolver `nil` nunca é ambíguo com "grave nil de propósito".
--
-- Primitivo (boolean/number/string) -- grava DIRETO, comportamento IDÊNTICO ao de antes desta
-- tarefa (o `__newindex` real decide se o nome/tipo faz sentido). Não-primitivo (array/objeto) --
-- NUNCA escrito cru: o `__newindex` real, em modo ESTRITO, escreve QUALQUER valor num Property
-- gravável SEM checar o tipo (ver `Instance.luau`, ramo "Property gravável ou Callback") -- um
-- array cru escrito direto num `Vector3`/`Color3` REAL seria a corrupção silenciosa que a
-- invariante 2 do projeto proíbe. Por isso todo array/objeto passa OBRIGATORIAMENTE por
-- `ValueTypes.Decode.FromRojoJson` antes de qualquer escrita.
--
-- task-cli-028-fix: `string` é o MESMO caso -- `typeof(raw)` NUNCA distingue uma `string`
-- primitiva de verdade (`Name`) de uma `string` que é a forma Rojo de um item de Enum
-- (`CameraMode = "LockFirstPerson"`), então `string` não pode mais ser um atalho incondicional.
-- `boolean`/`number` continuam podendo (nenhuma forma ambígua do `Decode` usa esses kinds --
-- `decodeEnum` só aceita `string`, `dataTypeDecoders` só aceitam array/objeto), então continuam
-- sem pagar o custo de `findMemberDescriptor` -- IDÊNTICO ao de antes desta correção.
local function resolvePropertyValue(className: string, key: string, raw: TreePlanner.PlanPropertyValue, nodePath: string, bag: Diagnostics.Bag): unknown?
	local rawKind = typeof(raw)
	if rawKind == "boolean" or rawKind == "number" then
		return raw
	end

	-- Resolvido AQUI (uma única vez) tanto para o caso `string` (decidir se é Enum ou primitivo)
	-- quanto para array/objeto (forma sempre não-primitiva, já precisava do descriptor antes desta
	-- correção) -- nunca duas buscas pela mesma propriedade nesta chamada.
	local descriptor = findMemberDescriptor(className, key)
	local isEnumProperty = descriptor ~= nil and descriptor.Kind == "Property" and descriptor.ValueCategory == "Enum"

	if rawKind == "string" and not isEnumProperty then
		-- String comum (`Name`, `ScriptSource`, ou qualquer propriedade sem `MemberDescriptor` de
		-- Enum -- inclusive sem `MemberDescriptor` NENHUM, ex.: nome inválido/instância em modo
		-- LENIENTE) -- grava DIRETO, comportamento IDÊNTICO ao de antes desta correção.
		return raw
	end

	if descriptor == nil or descriptor.Kind ~= "Property" then
		-- Sem MemberDescriptor de Property conhecido: LuauBench não tem como saber que tipo este
		-- array/objeto deveria virar. Cobre o modo LENIENTE (instância sem ClassSchema instalado,
		-- ex.: a raiz `game`/DataModel), um nome genuinamente inválido, e a limitação de herança
		-- declarada acima em `findMemberDescriptor`.
		bag:Add({
			Severity = "warning",
			Code = "materialize/property-shape-unknown",
			Message = Messages.MaterializePropertyShapeUnknown(nodePath, key),
			NodePath = nodePath,
			Field = key,
		})
		return nil
	end

	local valueType = descriptor.ValueType
	local valueCategory = descriptor.ValueCategory
	if valueType == nil or valueCategory == nil then
		-- `Kind == "Property"` deveria sempre trazer ValueType/ValueCategory não-nil (só
		-- Event/Callback os dispensam, ver `Runtime.MemberDescriptor`) -- inconsistência interna de
		-- `services`/`runtime`, tratada com a MESMA mensagem defensiva acima (nunca escreve cru).
		bag:Add({
			Severity = "warning",
			Code = "materialize/property-shape-unknown",
			Message = Messages.MaterializePropertyShapeUnknown(nodePath, key),
			NodePath = nodePath,
			Field = key,
		})
		return nil
	end

	-- "Enum" é um `valueCategory` (não um nome de tipo) -- o `ValueType` de uma propriedade Enum é
	-- o nome do enum ESPECÍFICO (ex. "Material", "KeyCode"), que `Catalog` não lista um a um: o que
	-- `Catalog` sabe é se o GLOBAL `Enum` (o namespace inteiro) está simulado -- se estiver, TODOS
	-- os enums do dump estão disponíveis via `generated/EnumData` (ver arquiteto-valuetypes-2026-
	-- 09-05.md, §"Enum inflar o startup"). Por isso o índice consultado muda por categoria.
	local catalogLookupName = if valueCategory == "Enum" then "Enum" else valueType
	if (valueCategory == "DataType" or valueCategory == "Enum") and not SIMULATED_VALUE_TYPE_NAMES[catalogLookupName] then
		bag:Add({
			Severity = "warning",
			Code = "materialize/property-type-not-simulated",
			Message = Messages.MaterializePropertyTypeNotSimulated(nodePath, key, valueType),
			NodePath = nodePath,
			Field = key,
		})
		return nil
	end

	-- Categoria "Primitive"/"Class"/"Group" com valor NÃO-primitivo (ex.: um array pra uma
	-- propriedade `float`) também passa por aqui -- `Decode.FromRojoJson` já sabe recusar essas
	-- categorias explicitamente ("só 'DataType'/'Enum' têm forma ambígua"), e o resultado vira
	-- `materialize/undecodable-property` abaixo, nunca uma escrita crua.
	local decoded = ValueTypes.Decode.FromRojoJson(valueType, valueCategory, raw)
	if decoded.Ok then
		return decoded.Value
	end

	bag:Add({
		Severity = "error",
		Code = "materialize/undecodable-property",
		Message = Messages.MaterializeUndecodableProperty(nodePath, key, valueType, decoded.Reason),
		NodePath = nodePath,
		Field = key,
	})
	return nil
end

-- Aplica `$properties` pela via PÚBLICA de escrita -- deixa o `__newindex` real do runtime validar
-- contra o `ClassSchema` e devolver a mensagem certa (nome inválido, propriedade somente-leitura,
-- evento/método protegido). Ordem alfabética das chaves: `PlanNode.Properties` é um mapa Lua sem
-- ordem própria, e diagnósticos em ordem determinística são o que torna um teste com múltiplas
-- propriedades inválidas no mesmo nó reproduzível.
--
-- task-cli-018 (Decisão 15, Parte 2): assinatura `(instance, properties, nodePath, bag)` --
-- `properties`/`nodePath` soltos, não lidos de dentro de um `PlanNode` -- porque
-- `InstancePlan.RootProperties` não pertence a nenhum `PlanNode` (a raiz nunca vira um `PlanNode`,
-- Decisão 3) e `Materialize` reusa esta MESMA função pra aplicar `$properties` da raiz de topo no
-- `game`.
--
-- task-cli-025 (Decisão 5/seção 7 do desenho de valuetypes): `properties[key]` agora é a forma
-- BRUTA do JSON (`TreePlanner.PlanPropertyValue`, ver aquele módulo) -- `resolvePropertyValue`,
-- acima, decide o valor FINAL a escrever (primitivo direto, ou decodificado via `ValueTypes.Decode`
-- pra array/objeto) e adiciona qualquer `Diagnostic` de "não decodificável"/"tipo não
-- simulado"/"forma desconhecida" ANTES de chegar aqui -- `applyProperties` só cuida da ESCRITA em
-- si (e do `materialize/invalid-property` que só o `__newindex` real sabe produzir).
-- task-cli-038 (D4): as três chaves ESTRUTURAIS que o CAMINHO A recusa sempre, ANTES de resolver
-- qualquer descritor -- ver Messages.MaterializeStructuralPropertyIgnored para o porquê de cada
-- uma. Tabela module-local (não recriada por chamada) pelo mesmo motivo de SCRIPT_CLASS_NAMES,
-- acima -- conjunto fixo, nunca deriva de dado de entrada.
local STRUCTURAL_PROPERTY_NAMES: { [string]: boolean } = {
	Name = true,
	Parent = true,
	ClassName = true,
}

local function applyProperties(instance: Runtime.Instance, properties: { [string]: TreePlanner.PlanPropertyValue }, nodePath: string, bag: Diagnostics.Bag): ()
	local propertyNames: { string } = {}
	for key in properties do
		table.insert(propertyNames, key)
	end
	table.sort(propertyNames)

	-- task-cli-038: CAMINHO decidido UMA VEZ por nó (nunca por propriedade individual) -- é a
	-- MESMA pergunta que `findMemberDescriptor` já faz internamente (`IsRegistered`), então nunca
	-- diverge do que a resolução de descritor, abaixo, também enxerga. Toda Instance que chega
	-- aqui vinda de `game:GetService(...)`/adoção de filho fixo/`Services.new(...)` tem
	-- `ClassSchema` instalado (registrada); só a raiz `game`/`DataModel` não (construída à mão,
	-- nunca via `ClassRegistry.Register` -- ver `findMemberDescriptor`, acima).
	local isStrict = Runtime.ClassRegistry.IsRegistered(instance.ClassName)

	for _, key in propertyNames do
		if isStrict then
			-- CAMINHO A (instância ESTRITA) -- ver o cabeçalho deste arquivo, "CORREÇÃO
			-- task-cli-038", para o desenho completo.
			if STRUCTURAL_PROPERTY_NAMES[key] then
				-- A1 (DV-5): paridade literal com o Rojo real -- skip com warning, NUNCA escreve.
				bag:Add({
					Severity = "warning",
					Code = "materialize/structural-property-ignored",
					Message = Messages.MaterializeStructuralPropertyIgnored(nodePath, key),
					NodePath = nodePath,
					Field = key,
				})
				continue
			end

			-- A2: resolve o descritor no schema ACHATADO e barra qualquer coisa que não seja
			-- `Kind == "Property"` ANTES de decodificar/escrever -- é a barreira dura que garante
			-- que $properties nunca torna um Event/Callback gravável por projeto, mesmo para um
			-- valor PRIMITIVO que `resolvePropertyValue`, abaixo, devolveria direto sem consultar
			-- descritor nenhum (ver aquela função, ramo boolean/number).
			local descriptor = findMemberDescriptor(instance.ClassName, key)
			if descriptor == nil then
				bag:Add({
					Severity = "error",
					Code = "materialize/invalid-property",
					Message = Messages.MaterializePropertyNotAMember(nodePath, key, instance.ClassName, instance:GetFullName()),
					NodePath = nodePath,
					Field = key,
				})
				continue
			end
			if descriptor.Kind ~= "Property" then
				bag:Add({
					Severity = "error",
					Code = "materialize/invalid-property",
					Message = Messages.MaterializePropertyNotAProperty(nodePath, key, instance.ClassName, descriptor.Kind),
					NodePath = nodePath,
					Field = key,
				})
				continue
			end

			-- A3: decodificação INALTERADA -- `resolvePropertyValue` já adiciona o Diagnostic
			-- correspondente (undecodable/type-not-simulated/shape-unknown) e devolve `nil` quando
			-- a propriedade deve ser pulada.
			local valueToWrite = resolvePropertyValue(instance.ClassName, key, properties[key], nodePath, bag)
			if valueToWrite == nil then
				continue
			end

			-- A4: `SetPropertyRaw` ignora `ReadOnly` E `ScriptVisible`, exatamente como o `rojo
			-- build` real ignora `scriptability`/`serialization` ao hidratar $properties
			-- (pesquisa-rojo-properties-security-2026-09-07.md).
			--
			-- CORREÇÃO DE REVISÃO (achado do revisor de task-cli-038, regressão real): `SetPropertyRaw`
			-- dispara `Changed:Fire(key)` de forma SÍNCRONA (`Instance.luau`, `SetPropertyRaw`) --
			-- que pode invocar um listener que `services` já conectou no bootstrap (ex.:
			-- `behavior/Lighting.luau`, o listener de `TimeOfDay`, que chama `parseTimeOfDay` e
			-- `error()`a pra qualquer string malformada). A3 só valida FORMA (ValueType/
			-- ValueCategory via `ValueTypes.Decode`) -- "not-a-real-time" é uma STRING perfeitamente
			-- válida pro decode de uma propriedade `string`, então NÃO sobra "nenhum caminho de erro
			-- real" como o comentário original desta função afirmava: o erro pode vir de FORA deste
			-- módulo, de um listener de `services` reagindo à mudança. `Signal.Fire` (`Signal.luau`)
			-- isola cada listener com `pcall` individual, mas RE-LANÇA o primeiro erro depois do
			-- laço quando a thread chamadora não é gerida pelo `ThreadBroker` (o caso aqui --
			-- `Materialize` roda antes do `scheduler:Run`, fora de qualquer coroutine gerida) -- sem
			-- proteção, esse erro escapa cru de `SetPropertyRaw` e derruba `Materialize`/
			-- `luaubench run` inteiro, reabrindo a MESMA classe de vazamento de path (caminho
			-- absoluto de instalação em disco) que task-cli-010/011 já fecharam. Por isso a escrita
			-- também vai por `pcall` + `stripEngineErrorLocation` (MESMO padrão já usado no Caminho
			-- B, abaixo, e no `pcall(Services.new(...))` de `createInstance` -- reusado, nunca
			-- duplicado) -- vira o MESMO `Diagnostic` `materialize/invalid-property` de sempre,
			-- nunca um crash cru.
			local ok, err = pcall(function()
				Runtime.Instance.SetPropertyRaw(instance, key, valueToWrite)
			end)
			if not ok then
				bag:Add({
					Severity = "error",
					Code = "materialize/invalid-property",
					Message = Messages.MaterializePropertyAssignmentFailed(nodePath, key, stripEngineErrorLocation(tostring(err))),
					NodePath = nodePath,
					Field = key,
				})
			end
			continue
		end

		-- CAMINHO B (instância LENIENTE, DV-2) -- INTOCADO: só `game`/DataModel chega aqui.
		local valueToWrite = resolvePropertyValue(instance.ClassName, key, properties[key], nodePath, bag)
		if valueToWrite == nil then
			-- `resolvePropertyValue` já adicionou o Diagnostic correspondente -- pula a escrita,
			-- resto do nó continua.
			continue
		end

		-- Cast de fronteira (Decisão 7 original, ainda válida para o caminho LENIENTE):
		-- `Runtime.Instance` é um tipo de campos NOMEADOS (o schema de cada classe concreta é uma
		-- interseção fechada, decidida por `services`) -- não existe assinatura estática para
		-- "escreva a propriedade cujo nome é esta string que veio de um arquivo JSON em disco". O
		-- cast widening por `unknown` (nunca um `any` disfarçado -- o valor É de fato uma Instance
		-- em runtime) é o que permite indexar por uma chave dinâmica; a VALIDAÇÃO real (a chave
		-- existe? é gravável?) continua 100% a cargo do `__newindex` verdadeiro, chamado logo
		-- abaixo dentro do `pcall` -- este cast não pula NENHUM enforcement, só muda o tipo que o
		-- compilador enxerga do lado esquerdo do `=`.
		local writable = (instance :: unknown) :: { [string]: unknown }
		local ok, err = pcall(function()
			writable[key] = valueToWrite
		end)

		if not ok then
			bag:Add({
				Severity = "error",
				Code = "materialize/invalid-property",
				Message = Messages.MaterializePropertyAssignmentFailed(nodePath, key, stripEngineErrorLocation(tostring(err))),
				NodePath = nodePath,
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
		-- chamar `game:GetService` de propósito -- NÃO porque `GetService` erraria em português
		-- (task-runtime-030 fechou isso: `GetService` já devolve `[LuauBench] ... not simulated
		-- yet` em inglês para este caso, via `UnknownClassResolver`), mas porque (a) o `Diagnostic`
		-- abaixo cita `node.NodePath`, informação que `GetService` não tem, e (b) sem a
		-- pré-validação este ramo precisaria de `pcall` + `stripEngineErrorLocation` (como o
		-- `pcall(Services.new(...))` mais abaixo) só para não derrubar `Materialize` -- ver o
		-- cabeçalho deste arquivo, mesmo parágrafo, para a citação completa do desenho.
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

	-- Ramo 2 (task-cli-016): filho fixo do motor -- ADOTA a Instance que `behavior/<Pai>.luau` já
	-- criou dentro de `parent` no bootstrap, NUNCA cria uma nova (ver cabeçalho deste arquivo e
	-- arquiteto-cli-2026-09-05.md, seção "task-cli-015", para o porquê: criar produziria um irmão
	-- duplicado de mesmo nome, e o script do usuário resolveria para o do motor, vazio).
	-- `parent.ClassName` é a Instance JÁ MATERIALIZADA (não o `ClassName` planejado) -- garante que
	-- só um `StarterPlayer` de verdade (o singleton, único jeito de `parent` chegar aqui com essa
	-- classe) pode ter um filho adotado; um `$className: "StarterPlayer"` num nó qualquer nem chega
	-- a existir, porque `Services.new("StarterPlayer")` já erra antes por `IsAbstract`.
	if Services.IsEngineFixedChild(parent.ClassName, node.Name, node.ClassName) then
		local existing = parent:FindFirstChild(node.Name)

		-- Defesa em profundidade (mesma categoria de materialize/service-name-mismatch/
		-- not-a-service, acima): só alcançável se `EngineFixedChildren.luau` declarar um filho que
		-- o `Initialize` do `behavior/<Pai>.luau` correspondente não cria de fato --
		-- inconsistência interna de `services` entre seus dois próprios módulos, nunca um erro do
		-- `.project.json` do usuário. Nenhum projeto real alcança este ramo hoje (task-services-010
		-- tem teste de coerência cobrindo justamente isto do lado de `services`).
		if existing == nil then
			bag:Add({
				Severity = "error",
				Code = "materialize/fixed-child-missing",
				Message = Messages.MaterializeFixedChildMissing(node.NodePath, node.ClassName, parent.ClassName),
				NodePath = node.NodePath,
			})
			return nil
		end

		if existing.ClassName ~= node.ClassName then
			bag:Add({
				Severity = "error",
				Code = "materialize/fixed-child-class-mismatch",
				Message = Messages.MaterializeFixedChildClassMismatch(node.NodePath, node.ClassName, existing.ClassName),
				NodePath = node.NodePath,
			})
			return nil
		end

		-- Devolve SEM tocar em `.Parent` -- já está parenteado pelo motor. Reatribuir o mesmo pai
		-- dispararia ChildRemoved/ChildAdded/AncestryChanged espúrios se algum dia deixasse de ser
		-- tratado como no-op (divergência de eventos, regra 02) -- e não há nenhum motivo para
		-- escrever num campo que já está correto.
		return existing
	end

	-- Ramo 3: `Services.new` (NUNCA `Runtime.ClassRegistry.NewEngineInstance` -- ver cabeçalho
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
		-- task-cli-011: `Services.new` levanta com `error(msg, 2)` (`src/services/init.luau`),
		-- então o call site apontado é este `pcall`, dentro de `TreeMaterializer.luau` -- mesmo
		-- vazamento de caminho absoluto em disco + linha interna que `applyProperties` já tinha
		-- (task-cli-010). `stripEngineErrorLocation` (ver cabeçalho e comentário acima da função,
		-- mais acima neste arquivo) remove só esse prefixo, preservando a mensagem real do motor
		-- ("Unable to create an Instance of type ..." ou "[LuauBench] ... not simulated yet").
		bag:Add({
			Severity = "error",
			Code = "materialize/invalid-class",
			Message = Messages.MaterializeInvalidClass(node.NodePath, node.ClassName, stripEngineErrorLocation(tostring(resultOrError))),
			NodePath = node.NodePath,
		})
		return nil
	end

	local instance = resultOrError :: Runtime.Instance

	-- task-cli-012 (avaliação de defesa em profundidade, achado BAIXO de revisor-cli na revisão de
	-- task-cli-011): esta atribuição NÃO está em `pcall`, ao contrário de `applyProperties`/do
	-- `pcall(Services.new(...))` logo acima -- avaliado explicitamente se `setParent`
	-- (`src/runtime/Instance.luau`) poderia lançar aqui e vazar path/linha interna do mesmo jeito.
	-- Reconfirmado (2026-09-05) contra o `setParent` real: as quatro condições de erro lá
	-- (`data.destroyed`; `newParent` fora de `internals` do runtime; `newParent == self`;
	-- `isSelfOrDescendant(self, newParent)`) são TODAS inalcançáveis aqui por construção, não por
	-- sorte de dado de entrada: `instance` acabou de sair de `Services.new` (linha acima) --
	-- SEMPRE uma Instance nova via `Runtime.ClassRegistry.new` (confirmado lendo
	-- `src/services/init.luau`, `Services.new`: os 4 ramos de erro nunca devolvem uma Instance
	-- existente, só criam ou erram) -- nunca destruída, sem filhos, e distinta de `parent`; `parent`
	-- é sempre uma `Runtime.Instance` já materializada por uma chamada anterior de
	-- `materializeNode`/`Materialize` (nunca um valor arbitrário do `.project.json`), logo sempre
	-- presente em `internals`. Nenhuma das tarefas que tocaram este arquivo depois do achado
	-- (task-cli-016: novo ramo 2, retorna ANTES de chegar aqui; task-cli-018/020: só
	-- `TreePlanner`/resolução de raiz, não tocam `createInstance`) alterou essa garantia. Decisão:
	-- NÃO envolver em `pcall` -- proteção sem nenhum caminho de erro real para cobrir seria
	-- complexidade sem benefício (mesmo princípio já usado para os dois "defesa em profundidade #1/#2"
	-- de `IsServiceRoot`, acima, que também não usam `pcall`+`stripEngineErrorLocation` por não
	-- envolverem chamada a `runtime`/`services` capaz de errar de forma imprevisível). Se um dia
	-- `createInstance` passar a reparentar uma Instance JÁ EXISTENTE (não recém-criada) -- não é o
	-- caso hoje -- esta análise precisa ser refeita.
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
	applyProperties(instance, node.Properties, node.NodePath, bag)

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

	-- task-cli-018 (Decisão 15, Parte 2): `$properties` da raiz de TOPO -- antes descartado em
	-- silêncio (`TreePlanner.planProjectTree` só devolvia `ClassName`). Reusa a MESMA
	-- `applyProperties` que qualquer `PlanNode` já usa (mesmo caminho de `Diagnostic`
	-- `materialize/invalid-property` pra nome inválido/propriedade somente-leitura) -- direto no
	-- `game` (já confirmado `DataModel` pela checagem acima), ANTES de materializar os `Roots`.
	-- `nodePath` fixo em "tree": é o valor que `ProjectFile.Read`/`TreePlanner` sempre usam pra
	-- nomear a raiz de um projeto de TOPO (`parseNode(treeObject, "tree", ...)`), o mesmo já usado
	-- pelo warning `plan/root-source-ignored` (`TreePlanner.Plan`).
	applyProperties(game, plan.RootProperties, "tree", bag)

	local scripts: { MaterializedScript } = {}
	for _, root in plan.Roots do
		materializeNode(root, game, game, scripts, bag)
	end

	return { Game = game, Scripts = scripts }
end

return TreeMaterializer
