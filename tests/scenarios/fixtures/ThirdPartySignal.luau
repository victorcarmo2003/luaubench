-- Fixture: biblioteca de Signal "de terceiros" (estilo comum no ecossistema Roblox: um
-- Signal/Connection próprio do projeto, não o Signal.luau do LuauBench).
--
-- Origem: D:\UserData\Documents\Roblox-Games\PLANE\src\shared\Modux\src\Signal.luau (também
-- presente, byte a byte igual, em AnimeFallen/Towers/Frozen_Faithless/Hide-or-Hit/CodeBreaker/
-- RunningSmth/TheGame/SquishObby/BallBrawl/Modux — é o Signal do framework "Modux" que o
-- usuário reaproveita entre os próprios jogos). Trecho reduzido: mantidos só Connect/Fire/Wait/
-- DisconnectAll (comportamento relevante pro cenário); omitidos Block/Unblock/
-- GetConnectionCount do original, que não mudam o que este cenário testa.
--
-- Preservado de propósito, IGUAL ao original: SEM `--!strict` (o arquivo real do usuário não
-- tem), `Signal.__index = Signal` genérico (não tipado), e o detalhe mais importante para o
-- cenário -- `Signal:Wait()` faz `coroutine.resume(thread, ...)` CRU (linha ~20 abaixo), o
-- mesmo padrão que já foi achado GRAVE dentro do próprio Signal.luau do LuauBench antes do
-- ThreadBroker existir (ver Scheduler.luau, comentário de topo). Aqui o objetivo é o oposto:
-- confirmar se o Scheduler do LuauBench aguenta uma biblioteca de terceiros que NUNCA passa
-- pelo ThreadBroker, sem quebrar o bookkeeping de liveThreads/IsAlive.
--
-- Também preservado do original: `Signal:Fire()` ignora o valor de retorno de
-- `pcall(connection._callback, ...)` além de re-lançar com `error(...)` se falhar -- ou seja,
-- um erro de callback aqui propaga OU (pior, no caminho de Wait) é descartado silenciosamente,
-- porque o callback de Wait devolve pelo `coroutine.resume` cru, cujo `ok`/`err` nem é lido.
-- Isso é uma característica do código de terceiros sendo testado, não do LuauBench -- ver
-- comentário no cenário que usa este fixture.

local Signal = {} :: any
Signal.__index = Signal

function Signal.new()
	local self = setmetatable({}, Signal)
	self._connections = {}
	self._blocked = false
	return self
end

function Signal:Connect(callback)
	if type(callback) ~= "function" then
		error("Callback deve ser uma função", 2)
	end

	local connection = {
		Connected = true,
		_callback = callback,
		_signal = self,
	}

	-- Metatable com __newindex: escrever `connection.Connected = false` direto (sem chamar
	-- :Disconnect()) já remove a conexão da lista -- é o padrão "proxytable interceptando
	-- escrita" que o testador foi instruído a cobrir, encontrado de verdade neste arquivo.
	local connectionMeta = {
		__newindex = function(t, k, v)
			if k == "Connected" then
				if not v and rawget(t, "Connected") then
					for i, conn in ipairs(self._connections) do
						if conn == t then
							table.remove(self._connections, i)
							rawset(t, "Connected", false)
							break
						end
					end
				else
					rawset(t, k, v)
				end
			else
				rawset(t, k, v)
			end
		end,
	}

	setmetatable(connection, connectionMeta)
	table.insert(self._connections, connection)

	function connection:Disconnect()
		self.Connected = false
	end

	return connection
end

function Signal:Fire(...)
	if self._blocked then
		return
	end

	local connections = {}
	for _, conn in ipairs(self._connections) do
		table.insert(connections, conn)
	end

	for _, connection in ipairs(connections) do
		if connection.Connected then
			local success, err = pcall(connection._callback, ...)
			if not success then
				error("Erro ao executar callback: " .. tostring(err), 2)
			end
		end
	end
end

-- Idêntico ao original: coroutine.resume CRU, sem passar pelo ThreadBroker do LuauBench e sem
-- checar o (ok, err) do resume.
function Signal:Wait()
	local thread = coroutine.running()
	if not thread then
		error("Wait() deve ser chamado em uma coroutine", 2)
	end

	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		coroutine.resume(thread, ...)
	end)

	return coroutine.yield()
end

function Signal:DisconnectAll()
	for _, conn in ipairs(self._connections) do
		conn.Connected = false
	end
	self._connections = {}
end

setmetatable(Signal, {
	__call = function(_self)
		return Signal.new()
	end,
})

return Signal
