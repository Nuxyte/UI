--!nonstrict
--[[
	Audio.Groups : SoundGroups hiérarchiques (Master > Music / SFX / UI / Voice / Ambient / ...), créés à la demande.

	Audio.GetGroup(name) -> SoundGroup        "Master" ou n'importe quel nom (créé sous Master)
	Audio.SetVolume(group, volume, fade?)     volume >= 0 ; fade en secondes (Tween natif)
	Audio.GetVolume(group) -> number          volume voulu (même si le groupe est coupé)
	Audio.Mute(group, muted)  Audio.IsMuted(group) -> boolean   (le volume voulu est conservé)
	Audio.Duck(group, amount, options?) -> handle     baisse temporairement le volume à `amount` × volume (0..1)
		options : Fade (0.3)    Duration (restauration automatique)    handle:Release()
	Audio.FadeTo(sound, volume, time?) -> Tween      fondu d'un Sound ou d'un SoundGroup

	Exemple
		Audio.SetVolume("Music", 0.4)
		local duck = Audio.Duck("Music", 0.25, { Fade = 0.2 }); ... ; duck:Release()
]]

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(script.Parent.Parent.Config)

local Groups = {}

-- volume voulu par groupe (indépendant du mute / du ducking)
local desired = setmetatable({}, { __mode = "k" })
local muted = setmetatable({}, { __mode = "k" })
local duckFactors = setmetatable({}, { __mode = "k" }) -- group -> { [duck] = factor }

local master: SoundGroup? = nil

local function getMaster(): SoundGroup
	if master and master.Parent then
		return master
	end
	local existing = SoundService:FindFirstChild("Master")
	if existing and existing:IsA("SoundGroup") then
		master = existing
	else
		local created = Instance.new("SoundGroup")
		created.Name = "Master"
		created.Volume = Config.Audio.MasterVolume
		created.Parent = SoundService
		master = created
	end
	if desired[master] == nil then
		desired[master] = master.Volume
	end
	return master
end

function Groups.GetGroup(name: string): SoundGroup
	if type(name) ~= "string" or name == "" then
		error("Core.Audio.GetGroup : nom de groupe (string) requis", 2)
	end
	local root = getMaster()
	if name == "Master" then
		return root
	end
	local group = root:FindFirstChild(name)
	if not group then
		group = Instance.new("SoundGroup")
		group.Name = name
		group.Parent = root
		desired[group] = group.Volume
	elseif not group:IsA("SoundGroup") then
		error(("Core.Audio.GetGroup : '%s' existe déjà et n'est pas un SoundGroup"):format(name), 2)
	end
	return group
end

local function resolve(group: any, fnName: string): SoundGroup
	if typeof(group) == "Instance" and group:IsA("SoundGroup") then
		return group
	end
	if type(group) == "string" then
		return Groups.GetGroup(group)
	end
	error(("Core.Audio.%s : groupe (nom ou SoundGroup) attendu"):format(fnName), 3)
end

local function effectiveVolume(group: SoundGroup): number
	if muted[group] then
		return 0
	end
	local volume = desired[group]
	if volume == nil then
		volume = group.Volume
		desired[group] = volume
	end
	local ducks = duckFactors[group]
	if ducks then
		for _, factor in ducks do
			volume *= factor
		end
	end
	return volume
end

local fades = setmetatable({}, { __mode = "k" })

local function apply(group: SoundGroup, fade: number?)
	local previous = fades[group]
	if previous then
		previous:Cancel()
		fades[group] = nil
	end
	local target = effectiveVolume(group)
	if fade and fade > 0 then
		local tween = TweenService:Create(group, TweenInfo.new(fade, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Volume = target })
		fades[group] = tween
		tween:Play()
	else
		group.Volume = target
	end
end

function Groups.SetVolume(group: any, volume: number, fade: number?)
	if type(volume) ~= "number" or volume < 0 then
		error("Core.Audio.SetVolume : volume (number >= 0) requis", 2)
	end
	local g = resolve(group, "SetVolume")
	desired[g] = volume
	apply(g, fade)
end

function Groups.GetVolume(group: any): number
	local g = resolve(group, "GetVolume")
	return desired[g] or g.Volume
end

function Groups.Mute(group: any, isMuted: boolean)
	local g = resolve(group, "Mute")
	if desired[g] == nil then
		desired[g] = g.Volume
	end
	muted[g] = isMuted and true or nil
	apply(g)
end

function Groups.IsMuted(group: any): boolean
	return muted[resolve(group, "IsMuted")] == true
end

function Groups.Duck(group: any, amount: number, options: any?)
	if type(amount) ~= "number" or amount < 0 or amount > 1 then
		error("Core.Audio.Duck : amount doit être entre 0 et 1", 2)
	end
	local g = resolve(group, "Duck")
	local opts = options or {}
	local fade = if opts.Fade ~= nil then opts.Fade else 0.3
	if desired[g] == nil then
		desired[g] = g.Volume
	end

	local ducks = duckFactors[g]
	if not ducks then
		ducks = {}
		duckFactors[g] = ducks
	end
	local handle = { Group = g, _released = false }
	ducks[handle] = amount
	apply(g, fade)

	function handle:Release()
		if self._released then
			return
		end
		self._released = true
		ducks[self] = nil
		apply(g, fade)
	end

	if opts.Duration then
		task.delay(opts.Duration, function()
			handle:Release()
		end)
	end
	return handle
end

function Groups.FadeTo(target: Instance, volume: number, time: number?): Tween
	if typeof(target) ~= "Instance" or not (target:IsA("Sound") or target:IsA("SoundGroup")) then
		error("Core.Audio.FadeTo : Sound ou SoundGroup attendu", 2)
	end
	local tween = TweenService:Create(target, TweenInfo.new(time or 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Volume = volume })
	tween:Play()
	return tween
end

-- Crée les groupes déclarés dans la config (appelé au premier accès au module)
function Groups._Init()
	for _, name in Config.Audio.Groups do
		Groups.GetGroup(name)
	end
end

return Groups
