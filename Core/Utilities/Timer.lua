--!nonstrict
--[[
	Timer : minuteur pausable basé sur task.delay (aucune connexion RunService).

	API
		Timer.new(duration, callback?, options?) -> Timer
			options.Repeat   true = se relance indéfiniment ; nombre = répétitions supplémentaires
		timer:Start()   timer:Pause()   timer:Resume()   timer:Stop()   timer:Reset()
		timer:TimeLeft()   -> number
		timer:IsRunning()  -> boolean
		timer.Finished     -> Signal (déclenché à chaque fin de cycle)
		timer:Destroy()

	Exemple
		local t = Timer.new(5, function() print("5 s écoulées") end)
		t:Start()
]]

local Signal = require(script.Parent.Signal)

local Timer = {}
Timer.__index = Timer

function Timer.new(duration: number, callback: (() -> ())?, options: { Repeat: (boolean | number)? }?)
	assert(type(duration) == "number" and duration >= 0, "Timer.new : `duration` doit être un nombre >= 0")

	local repeatOption = options and options.Repeat
	local repeats = 0
	if repeatOption == true then
		repeats = -1
	elseif type(repeatOption) == "number" then
		repeats = math.floor(repeatOption)
	end

	local self = setmetatable({
		Finished = Signal.new(),
		_duration = duration,
		_callback = callback,
		_repeats = repeats,
		_repeatsLeft = repeats,
		_remaining = duration,
		_startedAt = 0,
		_thread = nil,
		_running = false,
	}, Timer)

	return self
end

function Timer:_schedule()
	self._startedAt = os.clock()
	self._thread = task.delay(self._remaining, function()
		self._thread = nil
		self._running = false
		self._remaining = self._duration

		if self._callback then
			task.spawn(self._callback)
		end
		self.Finished:Fire()

		if self._repeatsLeft ~= 0 then
			if self._repeatsLeft > 0 then
				self._repeatsLeft -= 1
			end
			self._running = true
			self:_schedule()
		end
	end)
end

function Timer:Start()
	if self._running then
		return
	end
	self._remaining = self._duration
	self._repeatsLeft = self._repeats
	self._running = true
	self:_schedule()
end

function Timer:Pause()
	if not self._running then
		return
	end
	self._remaining = math.max(self._remaining - (os.clock() - self._startedAt), 0)
	self._running = false
	if self._thread then
		task.cancel(self._thread)
		self._thread = nil
	end
end

function Timer:Resume()
	if self._running or self._remaining <= 0 then
		return
	end
	self._running = true
	self:_schedule()
end

function Timer:Stop()
	self._running = false
	if self._thread then
		task.cancel(self._thread)
		self._thread = nil
	end
	self._remaining = self._duration
end

Timer.Reset = Timer.Stop

function Timer:TimeLeft(): number
	if self._running then
		return math.max(self._remaining - (os.clock() - self._startedAt), 0)
	end
	return self._remaining
end

function Timer:IsRunning(): boolean
	return self._running
end

function Timer:Destroy()
	self:Stop()
	self.Finished:Destroy()
end

return Timer
