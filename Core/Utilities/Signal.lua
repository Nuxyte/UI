--!nonstrict
--[[
	Signal : système d'événements léger (liste chaînée, déconnexion en O(1)).

	API
		Signal.new()                    -> Signal
		Signal.fromRBX(rbxSignal)       -> Signal  (relais d'un RBXScriptSignal)
		signal:Connect(fn)              -> Connection
		signal:Once(fn)                 -> Connection
		signal:Wait()                   -> ...args   (yield)
		signal:Fire(...)                -- chaque handler dans son propre thread
		signal:DisconnectAll()
		signal:Count()                  -> number
		signal:Destroy()
		connection:Disconnect()
		connection.Connected            -> boolean

	Exemple
		local s = Signal.new()
		local c = s:Connect(function(x) print("reçu", x) end)
		s:Fire(42)
		c:Disconnect()
]]

local Connection = {}
Connection.__index = Connection

function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false

	local signal = self._signal
	local prev, nxt = self._prev, self._next

	if prev then
		prev._next = nxt
	else
		signal._head = nxt
	end
	if nxt then
		nxt._prev = prev
	else
		signal._tail = prev
	end
	-- `_next` est conservé volontairement : un Fire en cours peut encore itérer à travers ce nœud.
	self._prev = nil
	signal._count -= 1
end

Connection.Destroy = Connection.Disconnect

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({
		_head = nil,
		_tail = nil,
		_count = 0,
		_destroyed = false,
		_rbxConnection = nil,
	}, Signal)
end

--- Crée un Signal qui relaie un RBXScriptSignal (ex. `part.Touched`).
function Signal.fromRBX(rbxSignal: RBXScriptSignal)
	local signal = Signal.new()
	signal._rbxConnection = rbxSignal:Connect(function(...)
		signal:Fire(...)
	end)
	return signal
end

local function addConnection(self, fn, once: boolean)
	assert(type(fn) == "function", "Signal:Connect attend une fonction")

	local connection = setmetatable({
		Connected = not self._destroyed,
		_signal = self,
		_fn = fn,
		_once = once,
		_prev = nil,
		_next = nil,
	}, Connection)

	if self._destroyed then
		return connection
	end

	if self._tail then
		self._tail._next = connection
		connection._prev = self._tail
	else
		self._head = connection
	end
	self._tail = connection
	self._count += 1

	return connection
end

function Signal:Connect(fn: (...any) -> ())
	return addConnection(self, fn, false)
end

function Signal:Once(fn: (...any) -> ())
	return addConnection(self, fn, true)
end

function Signal:Wait(): ...any
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:Fire(...: any)
	local node = self._head
	if not node then
		return
	end

	-- Les connexions ajoutées pendant le Fire ne sont appelées qu'au Fire suivant.
	local last = self._tail
	while node do
		local nxt = node._next
		if node.Connected then
			if node._once then
				node:Disconnect()
			end
			task.spawn(node._fn, ...)
		end
		if node == last then
			break
		end
		node = nxt
	end
end

function Signal:DisconnectAll()
	local node = self._head
	while node do
		local nxt = node._next
		node.Connected = false
		node._prev = nil
		node = nxt
	end
	self._head = nil
	self._tail = nil
	self._count = 0
end

function Signal:Count(): number
	return self._count
end

function Signal:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	self:DisconnectAll()
	if self._rbxConnection then
		self._rbxConnection:Disconnect()
		self._rbxConnection = nil
	end
end

return Signal
