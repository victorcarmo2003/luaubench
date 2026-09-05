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
			connect(listeners, function(...: T...)
				ThreadBroker.Resume(co, table.pack(...) :: ThreadBroker.PackedArgs)
			end, true)
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
