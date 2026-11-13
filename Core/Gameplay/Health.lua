--!nonstrict
--[[
	Gameplay.Health : composant de vie générique (joueurs, PNJ, objets destructibles). À utiliser côté SERVEUR (autorité).

	Health.new(options?) -> health
		options : Max (Config.Gameplay.DefaultMaxHealth)   Health (= Max)   Regen (points/s, 0)   RegenDelay (3 s après un dégât)
		          Invulnerable (false)
		          OnDamage(amount, source, info) -> number?    modifie / annule (0) un dégât avant application (armure, bouclier...)

	health:Damage(amount, source?, info?) -> number   dégâts réellement infligés (0 si invulnérable / mort)
	health:Heal(amount) -> number                      soins réellement appliqués (0 si mort)
	health:Kill(source?)   health:Revive(amount?)   health:SetMax(max, keepRatio?)   health:SetHealth(value)
	health:Get() / GetMax() / Percent() / IsAlive() / SetInvulnerable(bool)
	health:Bind(humanoid)       reflète Health / MaxHealth sur un Humanoid (sens composant -> Humanoid)
	health:Destroy()

	Signaux : Changed(new, old, source)   Damaged(amount, source, info)   Healed(amount)   Died(source)   Revived()

	La régénération utilise la boucle partagée de Core.Engine.Scheduler, active uniquement tant qu'elle est nécessaire.

	Exemple
		local hp = Core.Gameplay.Health.new({ Max = 150, Regen = 5 })
		hp.Died:Connect(function(source) respawn() end)
		hp:Damage(40, attackerPlayer)
]]

local Config = require(script.Parent.Parent.Config)
local Driver = require(script.Parent.Parent.Engine.Scheduler)
local Signal = require(script.Parent.Parent.Utilities.Signal)

local Health = {}
Health.__index = Health

function Health.new(options: any?)
	local opts = options or {}
	local max = opts.Max or Config.Gameplay.DefaultMaxHealth
	if type(max) ~= "number" or max <= 0 then
		error("Core.Gameplay.Health : Max doit être un nombre > 0", 2)
	end
	local current = math.clamp(opts.Health or max, 0, max)

	return setmetatable({
		Changed = Signal.new(),
		Damaged = Signal.new(),
		Healed = Signal.new(),
		Died = Signal.new(),
		Revived = Signal.new(),
		_health = current,
		_max = max,
		_regen = opts.Regen or 0,
		_regenDelay = if opts.RegenDelay ~= nil then opts.RegenDelay else 3,
		_invulnerable = opts.Invulnerable == true,
		_onDamage = opts.OnDamage,
		_lastDamage = -math.huge,
		_regenHandle = nil,
		_humanoid = nil,
		_destroyed = false,
	}, Health)
end

function Health:_Set(value: number, source: any?)
	local old = self._health
	value = math.clamp(value, 0, self._max)
	if value == old then
		return
	end
	self._health = value
	if self._humanoid and self._humanoid.Parent then
		self._humanoid.MaxHealth = self._max
		self._humanoid.Health = value
	end
	self.Changed:Fire(value, old, source)
end

function Health:_StartRegen()
	if self._regen <= 0 or self._regenHandle or self._destroyed then
		return
	end
	self._regenHandle = Driver.Run(nil, function(dt)
		if self._health <= 0 or self._health >= self._max then
			return true
		end
		if os.clock() - self._lastDamage < self._regenDelay then
			return false
		end
		self:_Set(self._health + self._regen * dt)
		return self._health >= self._max
	end, function()
		self._regenHandle = nil
	end)
end

function Health:Damage(amount: number, source: any?, info: any?): number
	if type(amount) ~= "number" or amount < 0 then
		error("Core.Gameplay.Health:Damage : amount doit être un nombre >= 0", 2)
	end
	if self._health <= 0 or self._invulnerable or self._destroyed then
		return 0
	end
	if self._onDamage then
		amount = self._onDamage(amount, source, info) or 0
		if amount <= 0 then
			return 0
		end
	end

	local before = self._health
	self:_Set(before - amount, source)
	local applied = before - self._health
	self._lastDamage = os.clock()

	self.Damaged:Fire(applied, source, info)
	if self._health <= 0 then
		self.Died:Fire(source)
	else
		self:_StartRegen()
	end
	return applied
end

function Health:Heal(amount: number): number
	if type(amount) ~= "number" or amount < 0 then
		error("Core.Gameplay.Health:Heal : amount doit être un nombre >= 0", 2)
	end
	if self._health <= 0 or self._destroyed then
		return 0
	end
	local before = self._health
	self:_Set(before + amount)
	local applied = self._health - before
	if applied > 0 then
		self.Healed:Fire(applied)
	end
	return applied
end

function Health:Kill(source: any?)
	if self._health <= 0 or self._destroyed then
		return
	end
	self:_Set(0, source)
	self.Died:Fire(source)
end

function Health:Revive(amount: number?)
	if self._health > 0 or self._destroyed then
		return
	end
	self:_Set(amount or self._max)
	self.Revived:Fire()
end

function Health:SetHealth(value: number)
	if self._health <= 0 then
		return
	end
	self:_Set(value)
	if self._health <= 0 then
		self.Died:Fire(nil)
	end
end

function Health:SetMax(max: number, keepRatio: boolean?)
	if type(max) ~= "number" or max <= 0 then
		error("Core.Gameplay.Health:SetMax : max doit être un nombre > 0", 2)
	end
	local ratio = self._health / self._max
	self._max = max
	if keepRatio then
		self:_Set(max * ratio)
	elseif self._health > max then
		self:_Set(max)
	elseif self._humanoid and self._humanoid.Parent then
		self._humanoid.MaxHealth = max
	end
end

function Health:SetInvulnerable(value: boolean)
	self._invulnerable = value
end

function Health:Get(): number
	return self._health
end

function Health:GetMax(): number
	return self._max
end

function Health:Percent(): number
	return self._health / self._max
end

function Health:IsAlive(): boolean
	return self._health > 0
end

function Health:Bind(humanoid: Humanoid)
	if typeof(humanoid) ~= "Instance" or not humanoid:IsA("Humanoid") then
		error("Core.Gameplay.Health:Bind : Humanoid attendu", 2)
	end
	self._humanoid = humanoid
	humanoid.MaxHealth = self._max
	humanoid.Health = self._health
end

function Health:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	if self._regenHandle then
		self._regenHandle:Cancel()
		self._regenHandle = nil
	end
	for _, name in { "Changed", "Damaged", "Healed", "Died", "Revived" } do
		self[name]:Destroy()
	end
end

return Health
