--!nonstrict
--[[
	Stopwatch : chronomètre précis (os.clock), sans boucle ni connexion.

	API
		Stopwatch.new() -> Stopwatch
		sw:Start()    sw:Stop()    sw:Reset()    sw:Restart()
		sw:Elapsed()  -> number (secondes)
		sw:Lap()      -> number (durée depuis le dernier Lap / Start)
		sw:Laps()     -> { number }
		sw:IsRunning() -> boolean
		Stopwatch.Measure(fn, ...) -> (seconds, ...results)

	Exemple
		local sw = Stopwatch.new(); sw:Start()
		doWork()
		print(sw:Elapsed())
]]

local Stopwatch = {}
Stopwatch.__index = Stopwatch

function Stopwatch.new()
	return setmetatable({
		_accumulated = 0,
		_startedAt = nil,
		_lastLap = 0,
		_laps = {},
	}, Stopwatch)
end

function Stopwatch:Start()
	if self._startedAt == nil then
		self._startedAt = os.clock()
	end
end

function Stopwatch:Elapsed(): number
	if self._startedAt then
		return self._accumulated + (os.clock() - self._startedAt)
	end
	return self._accumulated
end

function Stopwatch:Stop()
	if self._startedAt then
		self._accumulated = self:Elapsed()
		self._startedAt = nil
	end
end

function Stopwatch:Reset()
	self._accumulated = 0
	self._startedAt = nil
	self._lastLap = 0
	table.clear(self._laps)
end

function Stopwatch:Restart()
	self:Reset()
	self:Start()
end

function Stopwatch:Lap(): number
	local now = self:Elapsed()
	local lap = now - self._lastLap
	self._lastLap = now
	table.insert(self._laps, lap)
	return lap
end

function Stopwatch:Laps(): { number }
	return table.clone(self._laps)
end

function Stopwatch:IsRunning(): boolean
	return self._startedAt ~= nil
end

--- Mesure la durée d'une fonction. Retourne (secondes, ...résultats).
function Stopwatch.Measure(fn: (...any) -> ...any, ...: any): (number, ...any)
	local start = os.clock()
	local results = table.pack(fn(...))
	return os.clock() - start, table.unpack(results, 1, results.n)
end

return Stopwatch
