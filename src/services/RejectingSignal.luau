--!strict

--[[
	Um Signal que existe, é legível como propriedade, e RECUSA conexão -- extensão do LuauBench,
	portanto FORA do namespace simulado de qualquer classe real (regra 00: extensão deliberada
	nunca vive dentro do namespace de uma classe do Roblox) -- vive em módulo próprio de
	`services`, nunca em `runtime` (que não pode conhecer classe por nome, regra 02) e nunca em
	`generated/` (comportamento é sempre à mão, regra 03).

	Motivação e desenho completo: .claude/agents-memory/arquiteto-services-2026-09-05.md, seção
	"Revisão pós-integração 2026-09-05 -- Capabilities e RenderStepped", parte B ("RunService.
	RenderStepped: LuauBench simula a produção (RCC), não o bug do Studio"). Resumo: conectar em
	`RunService.RenderStepped` erra no LuauBench porque "existe e nunca dispara" era o
	comportamento de um BUG RECONHECIDO do Studio (ticket aberto pela Roblox), não do Roblox real
	-- e o LuauBench já se declara `IsStudio() == false`/`IsServer() == true`. Isto NÃO abre o
	escopo de contexto client/server: o LuauBench é servidor fixo, então a `message` recebida
	aqui é um VALOR CONSTANTE deste build, não uma consulta a um subsistema de RunContext que
	não existe nesta leva -- quando um `--client` existir um dia, é essa `message` que passa a
	ser condicional, num ponto só (a chamada de `RejectingSignal.new` em `behavior/RunService.luau`).

	Estruturalmente compatível com `Runtime.Signal<...>`: `Connect`/`Once`/`Wait` erram com a
	`message` recebida no construtor, em NÍVEL 2 -- culpa o call site do script do usuário
	(mesma convenção de erro de acesso a membro já usada em `src/runtime/Instance.luau`).
	`DisconnectAll` é NO-OP: nunca existiu conexão real para desfazer, então não há nada para
	limpar -- não seria coerente essa chamada errar quando `Connect` (a única forma de produzir
	algo para desconectar) também erra.

	`ConnectParallel` NÃO existe em `Runtime.Signal<T...>` (confirmado por leitura de
	src/runtime/Signal.luau) e NÃO é inventado aqui -- superfície fixa, nunca estendida por conta
	própria (regra 00).

	Tipo de retorno `Runtime.Signal<...unknown>` (pack variádico de `unknown`, nunca `any`) de
	propósito: quem instala este objeto (`behavior/RunService.luau`) grava via
	`Runtime.Instance.SetPropertyRaw`, cujo parâmetro `value` é `unknown` -- não há um alvo
	tipado e fixo (ex.: `Signal<number>`) que este módulo precisasse satisfazer estruturalmente
	na hora da atribuição, então um pack variádico não-comprometido é o tipo mais honesto que
	`RejectingSignal.new` pode declarar sem fingir saber a aridade real do evento que vai
	substituir. Confirmado por `luau-lsp analyze` (--!strict, sem `any`) nesta tarefa que
	`Signal<...unknown>` tipa limpo como instanciação de um pack genérico `T...` -- não foi
	necessário o `:: unknown ::` de contingência que o desenho previa como aceitável.

	Depende só de `../runtime` (para o tipo `Signal`/`Connection`). Usado por
	`behavior/RunService.luau`.
]]

local Runtime = require("../runtime")

local RejectingSignal = {}

function RejectingSignal.new(message: string): Runtime.Signal<...unknown>
	local self: Runtime.Signal<...unknown>
	self = {
		Connect = function(_self: Runtime.Signal<...unknown>, _callback: (...unknown) -> ()): Runtime.Connection
			error(message, 2)
		end,

		Once = function(_self: Runtime.Signal<...unknown>, _callback: (...unknown) -> ()): Runtime.Connection
			error(message, 2)
		end,

		Wait = function(_self: Runtime.Signal<...unknown>): ...unknown
			error(message, 2)
		end,

		-- No-op: nunca houve conexão real para desfazer (ver cabeçalho do módulo).
		DisconnectAll = function(_self: Runtime.Signal<...unknown>): () end,
	}
	return self
end

return RejectingSignal
