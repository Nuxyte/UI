--!nonstrict
--[[
	Throttle : exécute `fn` au maximum une fois toutes les `interval` secondes.

	API
		Throttle.new(fn, interval, options?) -> Throttler
			options.Leading  (bool) exécute immédiatement au 1er appel (défaut true)
			options.Trailing (bool) rejoue le dernier appel ignoré à la fin de l'intervalle (défaut false)
		throttler(...)  /  throttler:Call(...)   -> boolean (true si exécuté tout de suite)
		throttler:Cancel()
		throttler:Destroy()

	Exemple
		local fire = Throttle.new(function() shoot() end, 0.25)
		fire()   -- exécuté
		fire()   -- ignoré (< 0.25 s)
]]

local Throttle = {}
Throttle.__index = Throttle

function Throttle.new(fn: (...any) -> (), interval: number, options: { Leading: boolean?, Trailing: boolean? }?)
	assert(type(fn) == "function", "Throttle.new : `fn` doit être une fonction")
	assert(type(interval) == "number" and interval >= 0, "Throttle.new : `interval` doit être un nombre >= 0")

	local leading = true
	if options and options.Leading ~= nil then
		leading = options.Leading
	end

	local trailing = options and options.Trailing or false
	assert(leading or trailing, "Throttle.new : Leading et Trailing ne peuvent pas être tous deux désactivés")

	return setmetatable({
		_fn = fn,
		_interval = interval,
		_leading = leading,
		_trailing = trailing,
		_lastRun = -math.huge,
		_thread = nil,
		_pendingArgs = nil,
		_destroyed = false,
	}, Throttle)
end

function Throttle:Call(...: any): boolean
	if self._destroyed then
		return false
	end

	local now = os.clock()
	local elapsed = now - self._lastRun

	if elapsed >= self._interval then
		self._lastRun = now
		if self._leading then
			self._pendingArgs = nil
			task.spawn(self._fn, ...)
			return true
		end
		-- Leading désactivé : cet appel ouvre simplement la fenêtre (exécuté en Trailing).
	end

	if self._trailing then
		self._pendingArgs = table.pack(...)
		if not self._thread then
			local wait = math.max(self._interval - (os.clock() - self._lastRun), 0)
			self._thread = task.delay(wait, function()
				self._thread = nil
				local args = self._pendingArgs
				self._pendingArgs = nil
				if args then
					self._lastRun = os.clock()
					self._fn(table.unpack(args, 1, args.n))
				end
			end)
		end
	end

	return false
end

function Throttle:Cancel()
	if self._thread then
		task.cancel(self._thread)
		self._thread = nil
	end
	self._pendingArgs = nil
end

function Throttle:Destroy()
	self:Cancel()
	self._destroyed = true
end

Throttle.__call = function(self, ...)
	return self:Call(...)
end

return Throttle
