--!nonstrict
--[[
	Gameplay.Stats : statistiques avec modificateurs (buffs / debuffs / équipement).
	Valeur finale = (base + Σ Add) × Π Multiply, bornée par Limits si défini.

	Stats.new(base, limits?) -> stats
		base   { Speed = 16, Damage = 10 }          limits { Speed = { Min = 0, Max = 40 } }
	stats:Get(name) -> number          stats:GetBase(name)      stats:SetBase(name, value)
	stats:AddModifier(name, mod) -> handle
		mod : Add (number)   Multiply (number)   Duration (s, retrait automatique)   Source (any, pour RemoveSource)
		handle:Remove()      handle.Active
	stats:RemoveSource(source) -> number      retire tous les modificateurs d'une source
	stats:GetAll() -> { [name] = value }
	Signal Changed(name, new, old)

	Exemple
		local stats = Core.Gameplay.Stats.new({ Speed = 16 }, { Speed = { Max = 32 } })
		local buff = stats:AddModifier("Speed", { Multiply = 1.5, Duration = 5, Source = "Sprint" })
		humanoid.WalkSpeed = stats:Get("Speed")      -- 24
]]

local Signal = require(script.Parent.Parent.Utilities.Signal)

local Stats = {}
Stats.__index = Stats

function Stats.new(base: { [string]: number }, limits: any?)
	if type(base) ~= "table" then
		error("Core.Gameplay.Stats.new : table de valeurs de base requise", 2)
	end
	for name, value in base do
		if type(name) ~= "string" or type(value) ~= "number" then
			error("Core.Gameplay.Stats.new : la base doit être { [string] = number }", 2)
		end
	end
	return setmetatable({
		Changed = Signal.new(),
		_base = table.clone(base),
		_limits = limits or {},
		_mods = {},
		_cache = {},
	}, Stats)
end

function Stats:_Compute(name: string): number
	local base = self._base[name]
	if base == nil then
		error(("Core.Gameplay.Stats : statistique inconnue '%s'"):format(name), 3)
	end
	local add, multiply = 0, 1
	local list = self._mods[name]
	if list then
		for _, mod in list do
			add += mod.Add or 0
			multiply *= mod.Multiply or 1
		end
	end
	local value = (base + add) * multiply
	local limit = self._limits[name]
	if limit then
		if limit.Min then
			value = math.max(value, limit.Min)
		end
		if limit.Max then
			value = math.min(value, limit.Max)
		end
	end
	return value
end

function Stats:Get(name: string): number
	local cached = self._cache[name]
	if cached == nil then
		cached = self:_Compute(name)
		self._cache[name] = cached
	end
	return cached
end

function Stats:_Refresh(name: string, old: number)
	self._cache[name] = nil
	local new = self:Get(name)
	if new ~= old then
		self.Changed:Fire(name, new, old)
	end
end

function Stats:GetBase(name: string): number
	local base = self._base[name]
	if base == nil then
		error(("Core.Gameplay.Stats : statistique inconnue '%s'"):format(tostring(name)), 2)
	end
	return base
end

function Stats:SetBase(name: string, value: number)
	if type(value) ~= "number" then
		error("Core.Gameplay.Stats:SetBase : number requis", 2)
	end
	local old = if self._base[name] ~= nil then self:Get(name) else nil
	self._base[name] = value
	self._cache[name] = nil
	local new = self:Get(name)
	if new ~= old then
		self.Changed:Fire(name, new, old)
	end
end

function Stats:AddModifier(name: string, mod: any)
	if self._base[name] == nil then
		error(("Core.Gameplay.Stats:AddModifier : statistique inconnue '%s'"):format(tostring(name)), 2)
	end
	if type(mod) ~= "table" or (mod.Add == nil and mod.Multiply == nil) then
		error("Core.Gameplay.Stats:AddModifier : { Add = n } et/ou { Multiply = n } requis", 2)
	end

	local old = self:Get(name)
	local entry = { Add = mod.Add, Multiply = mod.Multiply, Source = mod.Source }
	local list = self._mods[name]
	if not list then
		list = {}
		self._mods[name] = list
	end
	table.insert(list, entry)
	self:_Refresh(name, old)

	local handle = { Active = true }
	function handle:Remove()
		if not self.Active then
			return
		end
		self.Active = false
		local index = table.find(list, entry)
		if index then
			local before = Stats.Get(self._owner, name)
			table.remove(list, index)
			self._owner:_Refresh(name, before)
		end
	end
	handle._owner = self

	if mod.Duration then
		task.delay(mod.Duration, function()
			handle:Remove()
		end)
	end
	return handle
end

function Stats:RemoveSource(source: any): number
	local removed = 0
	for name, list in self._mods do
		local old = self:Get(name)
		local changed = false
		for i = #list, 1, -1 do
			if list[i].Source == source then
				table.remove(list, i)
				removed += 1
				changed = true
			end
		end
		if changed then
			self:_Refresh(name, old)
		end
	end
	return removed
end

function Stats:GetAll(): { [string]: number }
	local all = {}
	for name in self._base do
		all[name] = self:Get(name)
	end
	return all
end

function Stats:Destroy()
	self.Changed:Destroy()
end

return Stats
