--!nonstrict
--[[
	Gameplay.Cooldown : temps de recharge. Sans boucle : un simple horodatage (os.clock) + un timer pour le signal Ready.

	Cooldown.new(duration) -> cooldown
		cooldown:Use() -> boolean       true et lance la recharge si prêt ; false sinon
		cooldown:IsReady() / Remaining() / Progress()   (Progress : 0 = vient de démarrer, 1 = prêt)
		cooldown:Reset()                prêt immédiatement      cooldown:SetDuration(d)     cooldown.Ready (Signal)

	Cooldown.Keyed(defaultDuration?) -> registre de recharges par clé (joueur, compétence, objet...)
		keyed:Use(key, duration?) -> boolean    keyed:IsReady(key)    keyed:Remaining(key)    keyed:Reset(key)    keyed:Clear()
		Une clé Instance est oubliée automatiquement quand elle est détruite ; les clés expirées sont purgées régulièrement.

	Exemple
		local dash = Core.Gameplay.Cooldown.new(2)
		if dash:Use() then performDash() end

		local perPlayer = Core.Gameplay.Cooldown.Keyed(5)     -- côté serveur : valider une action
		if not perPlayer:Use(player) then return end
]]

local Signal = require(script.Parent.Parent.Utilities.Signal)

local Cooldown = {}
Cooldown.__index = Cooldown

function Cooldown.new(duration: number)
	if type(duration) ~= "number" or duration < 0 then
		error("Core.Gameplay.Cooldown.new : duration (number >= 0) requis", 2)
	end
	return setmetatable({
		Ready = Signal.new(),
		_duration = duration,
		_readyAt = 0,
		_timer = nil,
	}, Cooldown)
end

function Cooldown:Remaining(): number
	return math.max(self._readyAt - os.clock(), 0)
end

function Cooldown:IsReady(): boolean
	return os.clock() >= self._readyAt
end

function Cooldown:Progress(): number
	if self._duration <= 0 then
		return 1
	end
	return 1 - math.clamp(self:Remaining() / self._duration, 0, 1)
end

function Cooldown:Use(): boolean
	if not self:IsReady() then
		return false
	end
	if self._duration > 0 then
		self._readyAt = os.clock() + self._duration
		self._timer = task.delay(self._duration, function()
			self._timer = nil
			self.Ready:Fire()
		end)
	end
	return true
end

function Cooldown:Reset()
	self._readyAt = 0
	if self._timer then
		pcall(task.cancel, self._timer)
		self._timer = nil
		self.Ready:Fire()
	end
end

function Cooldown:SetDuration(duration: number)
	if type(duration) ~= "number" or duration < 0 then
		error("Core.Gameplay.Cooldown:SetDuration : number >= 0 requis", 2)
	end
	self._duration = duration
end

function Cooldown:Destroy()
	if self._timer then
		pcall(task.cancel, self._timer)
		self._timer = nil
	end
	self.Ready:Destroy()
end

-- ---------------------------------------------------------------- Keyed
local Keyed = {}
Keyed.__index = Keyed

function Cooldown.Keyed(defaultDuration: number?)
	return setmetatable({ _default = defaultDuration or 1, _until = {}, _count = 0, _watch = {} }, Keyed)
end

function Keyed:_Purge()
	local now = os.clock()
	for key, readyAt in self._until do
		if now >= readyAt then
			self._until[key] = nil
			self._count -= 1
		end
	end
end

function Keyed:Use(key: any, duration: number?): boolean
	if key == nil then
		error("Core.Gameplay.Cooldown.Keyed:Use : clé requise", 2)
	end
	local now = os.clock()
	local readyAt = self._until[key]
	if readyAt and now < readyAt then
		return false
	end

	if readyAt == nil then
		self._count += 1
		if self._count > 128 then
			self:_Purge()
		end
		if typeof(key) == "Instance" and not self._watch[key] then
			self._watch[key] = key.Destroying:Once(function()
				self._watch[key] = nil
				if self._until[key] ~= nil then
					self._until[key] = nil
					self._count -= 1
				end
			end)
		end
	end
	self._until[key] = now + (duration or self._default)
	return true
end

function Keyed:Remaining(key: any): number
	local readyAt = self._until[key]
	return if readyAt then math.max(readyAt - os.clock(), 0) else 0
end

function Keyed:IsReady(key: any): boolean
	return self:Remaining(key) <= 0
end

function Keyed:Reset(key: any)
	if self._until[key] ~= nil then
		self._until[key] = nil
		self._count -= 1
	end
end

function Keyed:Clear()
	table.clear(self._until)
	self._count = 0
end

return Cooldown
