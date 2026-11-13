--!nonstrict
--[[
	Debounce : retarde l'exécution jusqu'à `delay` secondes après le DERNIER appel.

	API
		Debounce.new(fn, delay, options?) -> Debouncer
			options.Leading  (bool)  exécute aussi au premier appel d'une rafale (défaut false)
			options.Trailing (bool)  exécute à la fin de la rafale (défaut true)
		debouncer(...)  /  debouncer:Call(...)
		debouncer:Cancel()           -- annule l'exécution en attente
		debouncer:Flush()            -- exécute immédiatement l'appel en attente
		debouncer:Destroy()

	Exemple
		local save = Debounce.new(function() saveData() end, 2)
		save() save() save()   -- saveData() sera appelé une seule fois, 2 s après le dernier appel
]]

local Debounce = {}
Debounce.__index = Debounce

function Debounce.new(fn: (...any) -> (), delay: number, options: { Leading: boolean?, Trailing: boolean? }?)
	assert(type(fn) == "function", "Debounce.new : `fn` doit être une fonction")
	assert(type(delay) == "number" and delay >= 0, "Debounce.new : `delay` doit être un nombre >= 0")

	local leading = options and options.Leading or false
	local trailing = true
	if options and options.Trailing ~= nil then
		trailing = options.Trailing
	end

	return setmetatable({
		_fn = fn,
		_delay = delay,
		_leading = leading,
		_trailing = trailing,
		_thread = nil,
		_pendingArgs = nil,
		_destroyed = false,
	}, Debounce)
end

function Debounce:Call(...: any)
	if self._destroyed then
		return
	end

	local isBurstStart = self._thread == nil
	if self._thread then
		task.cancel(self._thread)
		self._thread = nil
	end

	if isBurstStart and self._leading then
		self._pendingArgs = nil
		task.spawn(self._fn, ...)
	elseif self._trailing then
		self._pendingArgs = table.pack(...)
	end

	self._thread = task.delay(self._delay, function()
		self._thread = nil
		local args = self._pendingArgs
		self._pendingArgs = nil
		if args and self._trailing then
			self._fn(table.unpack(args, 1, args.n))
		end
	end)
end

function Debounce:Cancel()
	if self._thread then
		task.cancel(self._thread)
		self._thread = nil
	end
	self._pendingArgs = nil
end

function Debounce:Flush()
	local args = self._pendingArgs
	self:Cancel()
	if args then
		task.spawn(self._fn, table.unpack(args, 1, args.n))
	end
end

function Debounce:Destroy()
	self:Cancel()
	self._destroyed = true
end

-- Permet `debouncer(...)`.
Debounce.__call = function(self, ...)
	return self:Call(...)
end

return Debounce
