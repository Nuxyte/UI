--!nonstrict
--[[
	Core.Utilities
	Chargement paresseux des utilitaires. Chaque sous-module est totalement
	indépendant et peut aussi être `require`d directement.

		local Utilities = Core.Utilities
		local maid = Utilities.Maid.new()
		local signal = Utilities.Signal.new()

	Modules : Signal, Maid, Debounce, Throttle, Retry, Cache, Timer, Stopwatch,
	          Table, String, Pool
]]

local Utilities = {}

local NAMES = {
	Signal = true,
	Maid = true,
	Debounce = true,
	Throttle = true,
	Retry = true,
	Cache = true,
	Timer = true,
	Stopwatch = true,
	Table = true,
	String = true,
	Pool = true,
}

setmetatable(Utilities, {
	__index = function(self, key)
		if NAMES[key] then
			local module = require(script[key])
			rawset(self, key, module)
			return module
		end
		error(("Core.Utilities.%s n'existe pas"):format(tostring(key)), 2)
	end,
})

return Utilities
