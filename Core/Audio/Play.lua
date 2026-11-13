--!nonstrict
--[[
	Audio.Play / PlayAt / Preload / StopAll : effets sonores poolés avec variations et fondus.

	source : id d'asset (number | "123" | "rbxassetid://123") ou Sound utilisé comme modèle (cloné)

	Audio.Play(source, options?) -> handle
		options : Group ("SFX")   Volume (1)   Pitch (1 : PlaybackSpeed)
		          VolumeVariation / PitchVariation (0..1 : écart relatif aléatoire, ex. 0.1 = ±10 %)
		          Loop   TimePosition   FadeIn (s)
		          At (Vector3)    son 3D à cette position        Follow (BasePart)   son 3D attaché à cette pièce
		          RollOff { Min, Max }   Parent (instance qui porte le son)
	Audio.PlayAt(source, position, options?) -> handle     raccourci de { At = position }

	handle:Stop(fade?)   handle:Pause()   handle:Resume()   handle:SetVolume(v, fade?)   handle:IsPlaying()
	handle.Sound   handle.Ended (Signal, tiré à la fin, après Stop ou à la destruction)   handle:Wait()

	Audio.Preload(assets) -> { échecs }      assets : liste d'ids / Sounds ; bloque jusqu'à la fin du chargement
	Audio.StopAll(group?, fade?)             arrête les sons lancés par Core.Audio (d'un groupe ou tous)
	Audio.Normalize(source) -> string        "123" / 123 -> "rbxassetid://123"

	Côté serveur le son est entendu par tous les joueurs ; côté client, uniquement par le joueur local.
]]

local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")

local Config = require(script.Parent.Parent.Config)
local Pool = require(script.Parent.Parent.Utilities.Pool)
local Signal = require(script.Parent.Parent.Utilities.Signal)
local Groups = require(script.Parent.Groups)

local Play = {}

function Play.Normalize(source: any): string
	if type(source) == "number" then
		return "rbxassetid://" .. tostring(math.floor(source))
	elseif type(source) == "string" then
		if source:match("^%d+$") then
			return "rbxassetid://" .. source
		end
		return source
	end
	error("Core.Audio : id d'asset invalide (number ou string attendu)", 3)
end

local soundPool = nil
local function getPool()
	if not soundPool then
		soundPool = Pool.new({
			MaxIdle = Config.Audio.PoolSize,
			Create = function()
				return Instance.new("Sound")
			end,
			Reset = function(sound)
				sound:Stop()
				sound.SoundId = ""
				sound.Volume = 0.5
				sound.PlaybackSpeed = 1
				sound.Looped = false
				sound.TimePosition = 0
				sound.SoundGroup = nil
				sound.Parent = nil
			end,
		})
	end
	return soundPool
end

local activeHandles = {} -- handle -> true (pour StopAll)

local function carrier(position: Vector3): BasePart
	local part = Instance.new("Part")
	part.Name = "CoreAudioEmitter"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.Position = position
	return part
end

local function vary(base: number, variation: number?): number
	if variation and variation > 0 then
		return base * (1 + (math.random() * 2 - 1) * variation)
	end
	return base
end

function Play.Play(source: any, options: any?)
	local opts = options or {}
	local pooled = typeof(source) ~= "Instance"

	local sound: Sound
	if pooled then
		sound = getPool():Get()
		sound.SoundId = Play.Normalize(source)
	else
		if not source:IsA("Sound") then
			error("Core.Audio.Play : un modèle doit être un Sound", 2)
		end
		sound = source:Clone()
	end

	local baseVolume = vary(if opts.Volume ~= nil then opts.Volume else (if pooled then 1 else sound.Volume), opts.VolumeVariation)
	sound.Volume = if opts.FadeIn and opts.FadeIn > 0 then 0 else baseVolume
	sound.PlaybackSpeed = vary(opts.Pitch or (if pooled then 1 else sound.PlaybackSpeed), opts.PitchVariation)
	sound.Looped = opts.Loop == true or (not pooled and opts.Loop == nil and sound.Looped)
	sound.TimePosition = opts.TimePosition or 0
	sound.SoundGroup = Groups.GetGroup(opts.Group or "SFX")

	local rolloff = opts.RollOff or Config.Audio.DefaultRollOff
	local spatial = opts.At ~= nil or opts.Follow ~= nil
	if spatial then
		sound.RollOffMinDistance = rolloff.Min
		sound.RollOffMaxDistance = rolloff.Max
	end

	local emitter: BasePart? = nil
	if opts.Follow ~= nil then
		if typeof(opts.Follow) ~= "Instance" or not opts.Follow:IsA("BasePart") then
			error("Core.Audio.Play : Follow doit être une BasePart", 2)
		end
		sound.Parent = opts.Follow
	elseif opts.At ~= nil then
		if typeof(opts.At) ~= "Vector3" then
			error("Core.Audio.Play : At doit être un Vector3", 2)
		end
		emitter = carrier(opts.At)
		emitter.Parent = workspace
		sound.Parent = emitter
	else
		sound.Parent = opts.Parent or SoundService
	end

	local handle = { Sound = sound, Ended = Signal.new(), Group = sound.SoundGroup, _finished = false }
	local endedConnection: any = nil
	local destroyingConnection: any = nil

	local function finish()
		if handle._finished then
			return
		end
		handle._finished = true
		activeHandles[handle] = nil
		if endedConnection then
			endedConnection:Disconnect()
		end
		if destroyingConnection then
			destroyingConnection:Disconnect()
		end
		if pooled then
			getPool():Release(sound)
		else
			sound:Destroy()
		end
		if emitter then
			emitter:Destroy()
		end
		handle.Ended:Fire()
		handle.Ended:Destroy()
	end

	activeHandles[handle] = true
	endedConnection = sound.Ended:Connect(finish)
	destroyingConnection = sound.Destroying:Connect(finish)

	function handle:Stop(fade: number?)
		if self._finished then
			return
		end
		if fade and fade > 0 then
			local tween = Groups.FadeTo(sound, 0, fade)
			tween.Completed:Once(finish)
		else
			sound:Stop()
			finish()
		end
	end

	function handle:Pause()
		sound:Pause()
	end

	function handle:Resume()
		sound:Resume()
	end

	function handle:SetVolume(volume: number, fade: number?)
		if fade and fade > 0 then
			Groups.FadeTo(sound, volume, fade)
		else
			sound.Volume = volume
		end
	end

	function handle:IsPlaying(): boolean
		return not self._finished and sound.IsPlaying
	end

	function handle:Wait()
		if not self._finished then
			self.Ended:Wait()
		end
	end

	sound:Play()
	if opts.FadeIn and opts.FadeIn > 0 then
		Groups.FadeTo(sound, baseVolume, opts.FadeIn)
	end
	return handle
end

function Play.PlayAt(source: any, position: Vector3, options: any?)
	local opts = table.clone(options or {})
	opts.At = position
	return Play.Play(source, opts)
end

function Play.Preload(assets: { any }): { string }
	local instances, created = {}, {}
	for _, asset in assets do
		if typeof(asset) == "Instance" then
			table.insert(instances, asset)
		else
			local sound = Instance.new("Sound")
			sound.SoundId = Play.Normalize(asset)
			table.insert(instances, sound)
			table.insert(created, sound)
		end
	end

	local failed = {}
	ContentProvider:PreloadAsync(instances, function(contentId: string, status: Enum.AssetFetchStatus)
		if status ~= Enum.AssetFetchStatus.Success then
			table.insert(failed, contentId)
		end
	end)
	for _, sound in created do
		sound:Destroy()
	end
	return failed
end

function Play.StopAll(group: any?, fade: number?)
	local filter = if group ~= nil then Groups.GetGroup(if type(group) == "string" then group else group.Name) else nil
	local list = {}
	for handle in activeHandles do
		if filter == nil or handle.Group == filter then
			table.insert(list, handle)
		end
	end
	for _, handle in list do
		handle:Stop(fade)
	end
	return #list
end

return Play
