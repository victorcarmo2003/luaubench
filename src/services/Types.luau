--!strict

--[[
	Módulo folha do território `services`: só tipos, sem lógica nenhuma. Existe para quebrar o
	ciclo de dependência que apareceria em `src/services/generated/classes/<X>.luau` ->
	`ClassBuilder.luau` -> `src/services/generated/Index.luau` -> `generated/classes/<X>.luau`
	de novo, se `ClassBuilder.luau` (que todo arquivo gerado precisa tipar corretamente para
	construir seu `Types.GeneratedClass`) importasse `generated/Index.luau` só para alcançar esse
	tipo. Ver .claude/agents-memory/arquiteto-services-2026-09-05.md, seção "Módulos" ->
	"src/services/Types.luau".

	Depende SÓ de `../runtime` (para os tipos `ClassSchema`/`Instance`/`Scheduler`/`DataModel`
	que compõem os tipos abaixo) -- nunca de ClassBuilder.luau, Context.luau, init.luau, nem de
	generated/**/behavior/** (regra 01: dependência circular entre módulos é erro de design,
	volta pro arquiteto antes de acontecer, nunca é resolvida "dando um jeito").
]]

local Runtime = require("../runtime")

-- O que o gerador (tools/generate-services.luau, task-services-002) emite por classe: espelha o
-- Roblox API Dump 1:1, sem comportamento nenhum -- o dump dá o "o quê", nunca o "como" (regra 03).
export type GeneratedClass = {
	ClassName: string,

	-- Já normalizado pelo gerador: `Superclass == "Object"` no dump vira a STRING "Instance"
	-- aqui (arquiteto-services-2026-09-05.md, "Decisão 1 -- Fecho transitivo automático":
	-- "Object nunca é emitido como classe; Instance é a raiz simulada do LuauBench"). Nunca `nil`
	-- -- todo GeneratedClass, inclusive o da própria classe "Instance", tem um valor aqui.
	Superclass: string,

	IsService: boolean, -- tag de classe "Service" do dump
	IsAbstract: boolean, -- tag de classe "NotCreatable" do dump

	-- Property/Event/Callback que ESTA classe declara -- nunca os herdados (o achatamento da
	-- cadeia inteira é responsabilidade de Runtime.ClassRegistry, não do gerador -- mesmo
	-- espelhamento do campo `Superclass` do dump, que também não redeclara membro herdado). Nunca
	-- `nil`: uma classe sem membro próprio emite `{}` (tabela vazia) -- ver ClassBuilder.luau para
	-- a consequência disso no modo estrito/leniente da instância.
	Schema: Runtime.ClassSchema,

	-- Function que ESTA classe declara -- nunca as herdadas, mesmo motivo do campo Schema acima.
	MethodNames: { string },
}

-- O que o autor humano escreve por classe (src/services/behavior/<ClassName>.luau). Nunca
-- gerado -- comportamento é sempre à mão (regra 03: o dump dá o "o quê", nunca o "como").
export type Behavior = {
	-- Chaves DEVEM estar em GeneratedClass.MethodNames da MESMA classe -- ClassBuilder.Build
	-- valida isso no load e erra alto se não bater (invariante 1 da regra 00 virando código
	-- verificável mecanicamente, não regra de revisão).
	Methods: { [string]: unknown }?,

	-- Roda DEPOIS de a instância já estar com a cadeia de classes, os métodos e o schema
	-- aplicados (Runtime.ClassRegistry.new garante essa ordem) -- nada gerado cria Initialize
	-- nesta leva (GeneratedClass não tem esse campo): é sempre este, ou nil.
	Initialize: ((instance: Runtime.Instance) -> ())?,
}

-- Passado a `Services.Bootstrap` por `cli`, uma única vez, antes de qualquer `GetService`. É o
-- que permite ao `Initialize` de uma classe (que só recebe `instance`, contrato de
-- Runtime.ClassDescriptor) alcançar o Scheduler/DataModel do processo corrente -- ver
-- Context.luau.
export type BootstrapOptions = {
	scheduler: Runtime.Scheduler,
	dataModel: Runtime.DataModel,

	-- task-services-026 (contrato coordenado com task-cli-026): permissão de rede, populada por
	-- `cli` (`RunCommand.luau`) a partir das flags `--allow-http`/`--allow-http-local`.
	-- `nil`/omitido == `false` em AMBOS -- default-off, o mesmo estado de um lugar Roblox
	-- recém-criado (`HttpEnabled` semeada `false`, ver `../.claude/agents-memory/arquiteto-
	-- services-2026-09-05.md`, L2.2.1). Lidos por `behavior/HttpService.luau` (`Initialize`, e a
	-- checagem de destino loopback/link-local/privado em `GetAsync`/`PostAsync`/`RequestAsync`)
	-- via `Context.IsHttpAllowed`/`Context.IsHttpLocalAllowed` -- nunca lidos direto daqui por
	-- nenhum `behavior/*.luau` (mesmo canal único que `Context.GetScheduler`/`GetDataModel` já
	-- são para `scheduler`/`dataModel`, acima).
	--
	-- `AllowHttp` controla se `HttpService.HttpEnabled` nasce `true` (o portão geral de rede).
	-- `AllowHttpLocal` controla só o endurecimento ADICIONAL do LuauBench sobre destinos
	-- loopback/link-local/privados (127.0.0.0/8, ::1, 169.254.0.0/16, 10/8, 172.16/12,
	-- 192.168/16, e o alias "localhost") -- é avaliado SÓ depois que `AllowHttp` já liberou
	-- `HttpEnabled`, então `AllowHttpLocal = true` sem `AllowHttp = true` nunca abre rede
	-- nenhuma, local ou não (os três métodos de rede continuam errando "not enabled" antes de
	-- qualquer checagem de destino) -- nunca abre a rede local sem a rede geral primeiro.
	AllowHttp: boolean?,
	AllowHttpLocal: boolean?,

	-- Correção coordenada com `task-cli-026`: canal de AUDITORIA de saída de rede, populado por
	-- `cli` (`RunCommand.luau`) a partir de `--verbose`. `nil`/omitido == sem auditoria nenhuma
	-- (comportamento de hoje, sem custo). Quando presente, `behavior/HttpService.luau` chama
	-- `(method, host)` UMA VEZ por requisição de saída de `GetAsync`/`PostAsync`/`RequestAsync`,
	-- ANTES de tocar `net.request` de verdade -- nunca quando a requisição é recusada antes
	-- disso (`HttpEnabled == false` ou destino privado sem `AllowHttpLocal`: nada saiu de
	-- verdade, nada para auditar). Lido só via `Context.NotifyHttpRequest` (`../Context.luau`),
	-- mesmo canal único que `AllowHttp`/`AllowHttpLocal` já usam -- `HttpService.luau` nunca lê
	-- `BootstrapOptions` direto. `method`/`host` são os dois ÚNICOS parâmetros de propósito: a
	-- auditoria não pode vazar corpo/headers (regra 00/07, dado do usuário não sai do LuauBench
	-- por um canal que o script não pediu).
	OnHttpRequest: ((method: string, host: string) -> ())?,

	-- task-services-032 (decisão do arquiteto, `.claude/agents-memory/arquiteto-persistencia-
	-- cloud-2026-09-06.md`, seção 7): canal de AUDITORIA de `MessagingService:PublishAsync`,
	-- populado por `cli` a partir de `--verbose` -- MESMO padrão de `OnHttpRequest`, acima, nunca
	-- um canal novo inventado. `MessagingService` NÃO ganha persistência (fiel: o Roblox real não
	-- tem mensagem pendente/fila/backlog -- persistir inventaria comportamento que a classe real
	-- não tem, proibido pela regra 00) -- isto é OBSERVABILIDADE, não estado. `nil`/omitido == sem
	-- auditoria nenhuma (comportamento de hoje, sem custo). Quando presente,
	-- `behavior/MessagingService.luau` chama `(topic, byteSize)` UMA VEZ por `PublishAsync`
	-- bem-sucedido, DEPOIS que a validação de tópico (1-80 caracteres) e tamanho (<=1024 bytes) já
	-- passou -- uma publicação que ERRA na validação nunca chega a chamar isto (nada foi publicado
	-- de verdade, nada para auditar). Lido só via `Context.NotifyMessagePublished`
	-- (`../Context.luau`), nunca direto daqui por `MessagingService.luau`. `topic`/`byteSize` são
	-- os dois ÚNICOS parâmetros de propósito: a auditoria NUNCA recebe o corpo da mensagem (regra
	-- 00/07, mesma disciplina de `OnHttpRequest` nunca logar corpo/headers).
	OnMessagePublished: ((topic: string, byteSize: number) -> ())?,

	-- task-services-031 (arquiteto-persistencia-cloud-2026-09-06.md, seção 10, "services expõe"):
	-- porta de persistência do estado "cloud" simulado (hoje: `DataStoreService`). Implementada por
	-- `cli` (`src/cli/CloudStore.luau`) -- `services` NUNCA chama `@lune/fs` (o caminho do arquivo
	-- em disco é relativo ao `.project.json` resolvido, informação que só `cli` tem; ver a seção 2
	-- do desenho para o raciocínio completo de por que `fs` mora em `cli`, não aqui).
	-- `nil`/omitido == SEM persistência nenhuma -- comportamento de hoje, e o que `--no-persist`
	-- produz. Lido só via `Context.GetCloudPersistence` (`./Context.luau`) -- nenhum
	-- `behavior/*.luau` lê `BootstrapOptions` direto, mesma disciplina de `AllowHttp`/
	-- `OnHttpRequest` acima.
	CloudPersistence: CloudPersistence?,
}

-- task-services-031 (arquiteto-persistencia-cloud-2026-09-06.md, seção 10): contrato de injeção
-- entre `cli` (implementa, via `src/cli/CloudStore.luau`) e `services` (consome, via
-- `Context.GetCloudPersistence` e `src/services/init.luau`, `Services.Bootstrap`/
-- `Services.FlushCloudState`). `document` é sempre um NOME LÓGICO opaco ("datastore" hoje,
-- "memorystore" numa leva futura -- ver a seção 8 do desenho), NUNCA um caminho de arquivo --
-- só `cli` (`CloudStore.luau`) decide como um nome vira caminho em disco.
export type CloudPersistence = {
	-- Devolve o documento serializado (string -- o formato exato é responsabilidade de
	-- `src/services/datastore/Snapshot.luau`, nunca deste tipo), ou `nil` se o documento nunca
	-- existiu. ERRA (nunca devolve `nil` silenciosamente) se o documento existe mas está ilegível
	-- -- perder o estado do usuário em silêncio é proibido (regra 00, invariante 2).
	Load: (document: string) -> string?,

	-- Grava atomicamente. Pode errar (disco cheio, permissão negada, etc.) -- quem chama trata: em
	-- `Services.FlushCloudState` (`./init.luau`), um erro aqui vira `(false, mensagem)`, nunca uma
	-- exceção propagada (perder persistência não deve derrubar a execução do script do usuário).
	Save: (document: string, contents: string) -> (),
}

-- Módulo folha: nada para exportar em valor, só os tipos acima. Todo ModuleScript do Lune
-- precisa devolver algo -- tabela vazia, de propósito, para deixar explícito que não há lógica
-- aqui (acceptance da tarefa: "Types.luau ... não tem lógica").
return {}
