--!nonstrict
--[[
	Tween.Sequence
	Séquences et timelines de tweens (style DOTween). Pause / reprise / annulation supportées.

	API (toutes les méthodes de construction retournent la séquence => chaînage)
		Core.Tween.Sequence()
			:Append(target, props, options?)   -- tween qui démarre APRÈS l'étape précédente
			:Join(target, props, options?)     -- tween qui démarre EN MÊME TEMPS que le dernier Append
			:Delay(seconds)                    -- pause entre deux étapes
			:Call(fn)                          -- exécute fn à cet endroit de la séquence
			:SetLoops(n)                       -- n répétitions supplémentaires (-1 = infini)
			:OnComplete(fn)
			:Play()
		sequence:Pause()   sequence:Resume()   sequence:Cancel()
		sequence:Wait()    -> "Completed" | "Cancelled"   (yield)
		sequence.Completed (Signal)   sequence.State ("Idle"|"Playing"|"Paused"|"Completed"|"Cancelled")
		sequence:Destroy()

	Exemple
		Core.Tween.Sequence()
			:Append(frame, { Position = UDim2.fromScale(0.5, 0.5) }, { Duration = 0.4, Easing = "BackOut" })
			:Join(frame, { BackgroundTransparency = 0 }, 0.4)
			:Delay(1)
			:Call(function() print("visible") end)
			:Append(frame, { Position = UDim2.fromScale(0.5, 1.5) }, 0.3)
			:Play()
]]

local Signal = require(script.Parent.Parent.Utilities.Signal)

local Sequence = {}
Sequence.__index = Sequence

--- `create(target, props, options) -> handle` et `makeDelay(seconds) -> handle` sont injectés par Tween.
function Sequence.new(create: (any, any, any) -> any, makeDelay: (number) -> any)
	return setmetatable({
		State = "Idle",
		Completed = Signal.new(),
		_create = create,
		_makeDelay = makeDelay,
		_steps = {},
		_loops = 0,
		_onComplete = nil,
		_token = nil,
		_current = nil,
		_pausedThread = nil,
	}, Sequence)
end

-- Construction ----------------------------------------------------------

local function checkIdle(self, method: string)
	if self.State == "Playing" or self.State == "Paused" then
		error(("Sequence:%s : impossible de modifier une séquence en cours de lecture"):format(method), 3)
	end
end

function Sequence:Append(target: any, props: { [string]: any }, options: any?)
	checkIdle(self, "Append")
	table.insert(self._steps, { Kind = "Group", Specs = { { Target = target, Props = props, Options = options } } })
	return self
end

function Sequence:Join(target: any, props: { [string]: any }, options: any?)
	checkIdle(self, "Join")
	local last = self._steps[#self._steps]
	if last and last.Kind == "Group" then
		table.insert(last.Specs, { Target = target, Props = props, Options = options })
	else
		table.insert(self._steps, { Kind = "Group", Specs = { { Target = target, Props = props, Options = options } } })
	end
	return self
end

function Sequence:Delay(seconds: number)
	checkIdle(self, "Delay")
	assert(type(seconds) == "number" and seconds >= 0, "Sequence:Delay : durée >= 0 requise")
	table.insert(self._steps, { Kind = "Delay", Time = seconds })
	return self
end

function Sequence:Call(fn: () -> ())
	checkIdle(self, "Call")
	assert(type(fn) == "function", "Sequence:Call : fonction requise")
	table.insert(self._steps, { Kind = "Call", Fn = fn })
	return self
end

function Sequence:SetLoops(count: number)
	checkIdle(self, "SetLoops")
	assert(type(count) == "number", "Sequence:SetLoops : nombre requis")
	self._loops = if count < 0 then -1 else math.floor(count)
	return self
end

function Sequence:OnComplete(fn: () -> ())
	assert(type(fn) == "function", "Sequence:OnComplete : fonction requise")
	self._onComplete = fn
	return self
end

-- Exécution -------------------------------------------------------------

function Sequence:_finish(status: string, token: any)
	if token ~= self._token then
		return
	end
	self.State = status
	self._current = nil
	self.Completed:Fire(status)
	self.Completed:DisconnectAll()
	if status == "Completed" and self._onComplete then
		task.spawn(self._onComplete)
	end
end

function Sequence:_runStep(step: any, token: any)
	if step.Kind == "Call" then
		local ok, err = pcall(step.Fn)
		if not ok then
			warn(("[Core.Tween.Sequence] erreur dans Call : %s"):format(tostring(err)))
		end
		return
	end

	local handles = {}
	if step.Kind == "Delay" then
		handles[1] = self._makeDelay(step.Time)
	else
		for _, spec in step.Specs do
			table.insert(handles, self._create(spec.Target, spec.Props, spec.Options))
		end
	end

	self._current = handles

	local pending = #handles
	local allDone = false
	local waiting = false
	local thread = coroutine.running()

	for _, handle in handles do
		handle.Completed:Connect(function()
			pending -= 1
			if pending == 0 then
				allDone = true
				if waiting then
					task.spawn(thread)
				end
			end
		end)
	end

	for _, handle in handles do
		handle:Play()
	end

	if not allDone then
		waiting = true
		coroutine.yield()
	end

	if self._token == token then
		self._current = nil
	end
end

function Sequence:_run(token: any)
	local loops = 0
	while true do
		for _, step in self._steps do
			if self._token ~= token then
				return
			end
			if self.State == "Paused" then
				self._pausedThread = coroutine.running()
				coroutine.yield()
				if self._token ~= token then
					return
				end
			end
			self:_runStep(step, token)
		end

		if self._token ~= token then
			return
		end
		loops += 1
		if self._loops ~= -1 and loops > self._loops then
			break
		end
	end
	self:_finish("Completed", token)
end

function Sequence:Play()
	if self.State == "Paused" then
		return self:Resume()
	end
	if self.State == "Playing" then
		return self
	end
	if #self._steps == 0 then
		error("Sequence:Play : la séquence est vide", 2)
	end

	local token = {}
	self._token = token
	self.State = "Playing"

	task.spawn(function()
		local ok, err = pcall(self._run, self, token)
		if not ok then
			warn(("[Core.Tween.Sequence] séquence interrompue : %s"):format(tostring(err)))
			if self._current then
				for _, handle in self._current do
					handle:Cancel()
				end
			end
			self:_finish("Cancelled", token)
		end
	end)

	return self
end

function Sequence:Pause()
	if self.State ~= "Playing" then
		return self
	end
	self.State = "Paused"
	if self._current then
		for _, handle in self._current do
			handle:Pause()
		end
	end
	return self
end

function Sequence:Resume()
	if self.State ~= "Paused" then
		return self
	end
	self.State = "Playing"
	if self._current then
		for _, handle in self._current do
			handle:Resume()
		end
	end
	local thread = self._pausedThread
	if thread then
		self._pausedThread = nil
		task.spawn(thread)
	end
	return self
end

function Sequence:Cancel()
	if self.State ~= "Playing" and self.State ~= "Paused" then
		return self
	end

	local token = self._token
	local current = self._current
	local pausedThread = self._pausedThread
	self._pausedThread = nil

	self:_finish("Cancelled", token)
	self._token = nil -- invalide le thread d'exécution

	if current then
		for _, handle in current do
			handle:Cancel()
		end
	end
	if pausedThread then
		task.spawn(pausedThread)
	end
	return self
end

function Sequence:Wait(): string
	if self.State == "Completed" or self.State == "Cancelled" then
		return self.State
	end
	if self.State == "Idle" then
		error("Sequence:Wait : la séquence n'a pas été lancée (appelez :Play() d'abord)", 2)
	end
	return self.Completed:Wait()
end

function Sequence:Destroy()
	self:Cancel()
	self.Completed:Destroy()
	table.clear(self._steps)
end

return Sequence
