--!strict

--[[
	UnknownClassResolver: classifica um `className` que `ClassRegistry.Get` não conhece. Desenho
	completo em .claude/agents-memory/arquiteto-runtime-2026-09-04.md, seção "Revisão
	pós-integração 2026-09-05 (5) — `GetService` de classe desconhecida: o resolvedor injetado
	por `services`" (task-runtime-030). Comportamento real do Roblox confirmado por fonte
	primária em .claude/agents-memory/pesquisa-getservice-comportamento-2026-09-05.md.

	POR QUE ISTO NÃO É `ClassRegistry`: são duas perguntas diferentes. `ClassRegistry` responde
	"quais classes eu sei construir" (as ~24 cobertas por `services` nesta leva). Este módulo
	responde "o que o território de cima sabe sobre um nome que eu não conheço" — e a resposta
	inclui as ~916 classes do Roblox API Dump que `services` conhece mas `ClassRegistry` nunca
	registra (não são cobertas, ou são reais porém não-Service, ex.: "Frame"/"Folder"). Fundir as
	duas perguntas num só módulo foi a opção (a) do desenho, REJEITADA: obrigaria registrar as 916
	classes em `ClassRegistry`, invertendo o significado de `ClassRegistry.IsRegistered`
	(`Services.IsSimulatedClass` quebra, `Services.new` passaria a construir stub vazio em
	silêncio para classe não simulada — proibido pela regra 03) e abrindo brecha na guarda
	`IsAbstract` de `ClassRegistry.new`. Manter as duas perguntas em módulos separados evita essa
	fusão.

	ESTADO GLOBAL MUTÁVEL, um ponteiro de função por processo — mesma invariante já documentada em
	`ClassRegistry.luau` (registro nunca desfeito) e em `src/services/Context.luau:Set` (mesmo
	padrão, mesma justificativa, citado aqui de propósito porque é o precedente que este módulo
	segue): um processo por execução do `luaubench run`, sem reset. `Set` SOBRESCREVE
	silenciosamente numa segunda chamada — não existe cenário legítimo de troca de resolvedor no
	meio de um processo, então não há necessidade de rejeitar a segunda chamada, só de nunca ficar
	sem NENHUM depois que `services` instalar o dele (o próprio `Services.Register()` já é
	idempotente por guarda local, então essa idempotência chega de graça aqui também).

	CONTRATO OBRIGATÓRIO do resolvedor instalado via `Set`, documentado aqui porque `runtime`
	nunca valida isto em runtime (validar exigiria confiar menos em `services` do que o contrato
	entre territórios já pressupõe):
	  - PURO: consulta de tabela / dado já resolvido, sem efeito colateral observável.
	  - TOTAL: responde para QUALQUER `className: string`, inclusive `""` — nunca `nil`,
	    nunca uma tabela com `Kind` fora dos três listados abaixo.
	  - NUNCA chama `error()`: um `error()' dentro do resolvedor subiria direto para o script do
	    usuário como uma falha inesperada de LuauBench, não como o erro estruturado que
	    `DataModel:GetService` decide formatar. Quem decide o que fazer com cada veredito —
	    inclusive quando errar — é `DataModel`, porque é ele que conhece o nível de erro certo
	    (aponta para a linha do `game:GetService(...)` no script do usuário), não este módulo.

	`Resolve` devolve `nil` SE E SOMENTE SE nenhum resolvedor foi instalado ainda (ex.: um spec de
	`runtime` puro, sem `services`, ou `cli` chamando algo antes de `Services.Register()`/
	`Services.Bootstrap()`). Isso NUNCA levanta erro aqui — só `DataModel` decide como reportar a
	ausência.

	Módulo folha: ZERO `require`, nem de `Instance.luau`. Não menciona API Dump, manifesto,
	cobertura nem versão — esse vocabulário é de `services` (regra de idioma: `runtime` só fala a
	língua do motor Roblox; `services` fala a língua de cobertura do LuauBench). A mensagem
	`ServiceNotSimulated.Message` chega PRONTA de `services`; este módulo nunca a formata nem a
	reformata.

	Depende de: nada. Usado por: `DataModel.luau` (consulta via `Resolve`), `services` (instala
	via `Set`, dentro de `Services.Register()`). Reexportado por `init.luau`: só `Set` + os dois
	tipos abaixo — `Resolve` fica interno ao território (mesmo precedente de
	`Instance.NewBase`/`SetClassChain`/`SetClassMethods`: `services`/`cli` não têm uso legítimo
	para ele).
]]

export type UnknownClassVerdict =
	{ Kind: "NotAClass" }
	| { Kind: "NotAService" }
	| { Kind: "ServiceNotSimulated", Message: string }

export type UnknownClassResolver = (className: string) -> UnknownClassVerdict

local UnknownClassResolver = {}

-- Estado privado do módulo -- um processo por execução do LuauBench, sem função de reset (mesma
-- invariante de ClassRegistry/Context, ver cabeçalho acima).
local installed: UnknownClassResolver? = nil

-- Chamado só por `Services.Register()` -- sobrescreve silenciosamente numa segunda chamada (ver
-- cabeçalho acima); não existe `UnknownClassResolver.Reset`/`Unset`.
function UnknownClassResolver.Set(resolver: UnknownClassResolver): ()
	installed = resolver
end

-- `nil` <=> nenhum resolvedor instalado. NUNCA levanta erro -- quem decide o que fazer com a
-- ausência é `DataModel`, que tem o nível de erro certo para apontar o script do usuário.
function UnknownClassResolver.Resolve(className: string): UnknownClassVerdict?
	if installed == nil then
		return nil
	end
	return installed(className)
end

return UnknownClassResolver
