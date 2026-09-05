--!strict

--[[
	Sistema de eventos genérico (Signal/Connection) do LuauBench.

	Usado por Instance.luau (Changed/ChildAdded/...), Scheduler.luau (Heartbeat/Stepped/
	ThreadError) e, futuramente, por `services` (ex: Touched de BasePart). Contrato congelado
	em .claude/agents-memory/arquiteto-runtime-2026-09-04.md, seção "Signal.luau".

	Depende de ThreadBroker.luau (módulo-folha sem dependência nenhuma de módulo do runtime,
	ver ThreadBroker.luau), que passa a ser a raiz da árvore de módulos no lugar deste arquivo
	— ver seção "Revisão pós-integração 2026-09-04 — contrato Wait/resume" do desenho: Wait()
	precisava de um jeito de retomar a thread chamadora pelo ponto único de resume do driver
	que a gerir (sem importar Scheduler.luau diretamente, o que criaria ciclo de require), e
	ThreadBroker é esse canal por identidade de thread.

	task-runtime-020 (fecha a PENDÊNCIA DECLARADA por task-runtime-011 em ThreadBroker.luau/
	Scheduler.luau): Wait() também chama ThreadBroker.RegisterCleanup para desconectar o
	próprio listener interno se a thread chamadora for cancelada (Scheduler:Cancel) antes do
	próximo Fire — sem isso o listener ficava pendurado em `listeners` para sempre. Isto NÃO é
	uma dependência nova: este módulo já importa ThreadBroker.luau (linha 18) desde a revisão
	acima só para `ThreadBroker.Resume`; `RegisterCleanup` usa o mesmo require. O invariante de
	módulo-folha original mirava dependência de Scheduler/Instance (que criaria ciclo ou
	acoplaria Signal a um driver concreto), não outro módulo-folha como ThreadBroker.
]]

local ThreadBroker = require("./ThreadBroker")

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Wait: (self: Signal<T...>) -> T...,
	DisconnectAll: (self: Signal<T...>) -> (),
}

-- Capacidade de disparo NÃO é exposta em `Signal<T...>` — só quem possui o objeto
-- (Instance.luau, Scheduler.luau, uma classe de `services`) importa este tipo.
export type FireableSignal<T...> = Signal<T...> & {
	Fire: (self: FireableSignal<T...>, T...) -> (),
}

-- Um Listener É uma Connection (superset estrutural: `Connected`/`Disconnect` + bookkeeping
-- interno de disparo). Usar o MESMO objeto como item da lista interna e como handle
-- devolvido por Connect/Once evita ter duas fontes de verdade para o estado "conectado" —
-- quando Fire desconecta um listener de Once automaticamente, a Connection que o chamador
-- guardou já reflete `Connected = false` sem sincronização extra.
type Listener<T...> = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
	callback: (T...) -> (),
	once: boolean,
}

-- Registra um novo listener na lista interna do Signal e devolve o próprio listener,
-- que satisfaz estruturalmente o tipo público `Connection` (tem Connected + Disconnect,
-- mais os campos internos `callback`/`once` invisíveis para quem só enxerga `Connection`).
local function connect<T...>(listeners: { Listener<T...> }, callback: (T...) -> (), once: boolean): Listener<T...>
	local listener: Listener<T...>
	listener = {
		Connected = true,
		callback = callback,
		once = once,
		Disconnect = function(_self: Connection)
			if not listener.Connected then
				return
			end
			listener.Connected = false
			local index = table.find(listeners, listener)
			if index then
				table.remove(listeners, index)
			end
		end,
	}
	table.insert(listeners, listener)
	return listener
end

local Signal = {}

function Signal.new<T...>(): FireableSignal<T...>
	local listeners: { Listener<T...> } = {}

	local self: FireableSignal<T...>
	self = {
		Connect = function(_self: Signal<T...>, callback: (T...) -> ()): Connection
			return connect(listeners, callback, false)
		end,

		Once = function(_self: Signal<T...>, callback: (T...) -> ()): Connection
			return connect(listeners, callback, true)
		end,

		-- Cede a coroutine chamadora até o próximo Fire: registra um Once que, ao disparar,
		-- roteia a retomada por ThreadBroker.Resume em vez de um `coroutine.resume` direto.
		-- Se esta thread é gerida por um Scheduler (adotada via ThreadBroker.Adopt), quem
		-- retoma é o ponto único de resume dele — liveThreads e ThreadError ficam corretos,
		-- e um erro na continuação vira ThreadError em vez de propagar para dentro do Fire.
		-- Sem driver (uso standalone, ex: Signal.spec.luau), o broker faz o `coroutine.resume`
		-- cru — mesmo comportamento de hoje.
		Wait = function(_self: Signal<T...>): T...
			local co = coroutine.running()
			local unregisterCleanup: (() -> ())? = nil
			local listener = connect(listeners, function(...: T...)
				-- task-runtime-020: se o Fire chegou a disparar este listener antes de
				-- qualquer cancelamento, desfaz o próprio registro de limpeza no ThreadBroker
				-- ANTES de retomar -- sem isto, uma thread que chama Wait() em laço (ex.:
				-- Instance:WaitForChild ramo A, "while true do data.childAdded:Wait() end")
				-- acumularia uma entrada morta em ThreadBroker.cleanups[co] por iteração,
				-- nunca liberada até a thread morrer de vez (ver ThreadBroker.RegisterCleanup:
				-- o desregistro devolvido é idempotente, feito exatamente para este uso).
				if unregisterCleanup ~= nil then
					unregisterCleanup()
				end
				ThreadBroker.Resume(co, table.pack(...) :: ThreadBroker.PackedArgs)
			end, true)
			-- task-runtime-020 (vazamento real fechado aqui, ver PENDÊNCIA DECLARADA em
			-- ThreadBroker.luau/Scheduler.luau deixada por task-runtime-011): se esta thread
			-- for cancelada (Scheduler:Cancel) enquanto ainda presa neste Wait(), o listener
			-- acima nunca dispara -- sem este registro ele ficaria pendurado em `listeners`
			-- para sempre. RunCleanups desconecta no MOMENTO do cancelamento, nunca espera
			-- este Signal disparar de novo.
			--
			-- DECISÃO DE DEPENDÊNCIA (não é uma dependência nova de fato, é uma leitura
			-- atualizada do desenho original): este módulo já importa ThreadBroker.luau desde
			-- a "Revisão pós-integração 2026-09-04 -- contrato Wait/resume" (ver cabeçalho
			-- deste arquivo e de ThreadBroker.luau), exatamente para rotear
			-- `ThreadBroker.Resume` acima sem reintroduzir um require de Scheduler.luau (que
			-- criaria ciclo). Chamar `ThreadBroker.RegisterCleanup` usa esse MESMO require já
			-- existente -- não adiciona nenhuma aresta nova ao grafo de dependências do
			-- território, e não recria o ciclo que a proibição original evitava (Signal ->
			-- Scheduler): ThreadBroker.luau continua módulo-folha, sem importar nada (ver
			-- ThreadBroker.luau, linhas 20-24, que já documenta "Signal.luau -> ThreadBroker"
			-- como aresta aceita do grafo). O invariante "módulo-folha sem dependência de
			-- outro módulo do runtime", tal como escrito originalmente, mirava a dependência
			-- de Scheduler/Instance (que criaria ciclo ou acoplaria Signal a um driver
			-- concreto) -- não outro módulo-folha como ThreadBroker, que foi desenhado
			-- deliberadamente para ser a raiz da árvore no lugar deste arquivo.
			unregisterCleanup = ThreadBroker.RegisterCleanup(co, function()
				listener:Disconnect()
			end)
			return coroutine.yield()
		end,

		DisconnectAll = function(_self: Signal<T...>)
			for _, listener in listeners do
				listener.Connected = false
			end
			table.clear(listeners)
		end,

		Fire = function(_self: FireableSignal<T...>, ...: T...)
			-- Dispara sobre uma cópia da lista de listeners: Connect/Disconnect feito por um
			-- callback durante este mesmo Fire não altera esta rodada de disparo — mesma
			-- garantia do Roblox real (quem conecta durante um Fire só recebe o próximo).
			local snapshot: { Listener<T...> } = {}
			for _, listener in listeners do
				table.insert(snapshot, listener)
			end

			-- Cada listener é isolado por um pcall individual: erro em um NUNCA cancela os
			-- listeners seguintes do mesmo disparo (fidelidade ao Roblox real, onde cada
			-- conexão roda na própria coroutine). Se a thread hospedeira (quem chamou Fire) é
			-- gerida, o erro vira ThreadError na hora via ThreadBroker.ReportError e o laço
			-- segue; se não há dono, o PRIMEIRO erro é acumulado e só re-lançado DEPOIS do
			-- laço inteiro rodar — preserva "erro escapa de Fire" para uso standalone e para
			-- o fireProtected de Scheduler.luau.
			--
			-- ATENÇÃO: `pcall(listener.callback, ...)` NÃO tipa em --!strict (o stub do pcall
			-- dá "Function only returns 1 value, but 2 are required here" quando a função
			-- protegida retorna `()` — verificado com luau-lsp). A forma que tipa limpo é a
			-- mesma já usada em Scheduler.fireProtected: closure com pack variádico explícito.
			local pendingError: string? = nil
			for _, listener in snapshot do
				if listener.Connected then
					if listener.once then
						listener.Connected = false
						local index = table.find(listeners, listener)
						if index then
							table.remove(listeners, index)
						end
					end
					local ok, err = pcall(function(...: T...)
						listener.callback(...)
					end, ...)
					if not ok then
						local message = tostring(err)
						if not ThreadBroker.ReportError(coroutine.running(), message) and pendingError == nil then
							pendingError = message
						end
					end
				end
			end
			if pendingError ~= nil then
				error(pendingError, 0)
			end
		end,
	}

	return self
end

return Signal
