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
}

-- Módulo folha: nada para exportar em valor, só os tipos acima. Todo ModuleScript do Lune
-- precisa devolver algo -- tabela vazia, de propósito, para deixar explícito que não há lógica
-- aqui (acceptance da tarefa: "Types.luau ... não tem lógica").
return {}
