--!nonstrict
--[[
	Animation.Tracks : lecture d'AnimationTracks avec cache, groupes exclusifs et handles.

	Animation.Play(subject, source, options?) -> handle
		subject : Model | Humanoid | AnimationController | Animator      (l'Animator est créé au besoin)
		source  : id (123 | "123" | "rbxassetid://123") ou Instance Animation
		options : Looped (bool)   Priority ("Core" | "Idle" | "Movement" | "Action" | "Action2".."Action4" | Enum.AnimationPriority)
		          Weight (1)   Speed (1)   FadeIn (Config.Animation.DefaultFade)   TimePosition (s)
		          Group (string)   lancer une animation d'un groupe arrête, avec le même fondu, celle du même groupe
		          Restart (false)  relance depuis le début si la piste joue déjà (sinon on met seulement à jour Speed / Weight)
	handle : :Stop(fade?)  :Pause()  :Resume()  :SetSpeed(s)  :SetWeight(w, fade?)  :IsPlaying()
	         :OnMarker(name, fn) -> connexion     :WaitForMarker(name) -> yield jusqu'au marqueur
	         .Track (AnimationTrack)  .Ended (Signal, tiré à la fin de la piste)  :Wait()   .Group  .Id
	Pause = vitesse 0 (Roblox n'a pas de pause native) : la piste reste "en lecture".

	Animation.Stop(subject, source, fade?)        arrête une piste lancée par Core.Animation
	Animation.StopAll(subject, fade?) -> number   arrête toutes celles de ce sujet (les autres animations Roblox sont intactes)
	Animation.GetPlaying(subject) -> { handle }
	Animation.Preload(sources) -> { ids en échec }

	Les pistes sont chargées une seule fois par Animator et mises en cache ; tout est libéré quand l'Animator est détruit.

	Exemple
		local run = Core.Animation.Play(character, 507767714, { Looped = true, Group = "Locomotion", Priority = "Movement" })
		run:OnMarker("Footstep", function() Core.Audio.Play(stepSound) end)
		Core.Animation.Play(character, attackAnim, { Group = "Action", Priority = "Action", FadeIn = 0.05 })
]]

local ContentProvider = game:GetService("ContentProvider")

local Config = require(script.Parent.Parent.Config)
local Signal = require(script.Parent.Parent.Utilities.Signal)
local Util = require(script.Parent.Util)

local Tracks = {}

type Record = { track: any, animation: Instance, owned: boolean, handle: any? }

local caches: { [Instance]: { [string]: Record } } = setmetatable({}, { __mode = "k" })
local groups: { [Instance]: { [string]: any } } = setmetatable({}, { __mode = "k" })

local function cacheFor(animator: Instance): { [string]: Record }
	local cache = caches[animator]
	if not cache then
		cache = {}
		caches[animator] = cache
		groups[animator] = {}
		animator.Destroying:Once(function()
			for _, record in cache do
				if record.handle then
					record.handle._finished = true
				end
				if record.owned then
					record.animation:Destroy()
				end
			end
			caches[animator] = nil
			groups[animator] = nil
		end)
	end
	return cache
end

local function resolvePriority(priority: any): any
	if priority == nil then
		return nil
	end
	if typeof(priority) == "EnumItem" then
		return priority
	end
	local item = if type(priority) == "string" then Enum.AnimationPriority[priority] else nil
	if item == nil then
		error(("Core.Animation.Play : Priority inconnue '%s' (Core, Idle, Movement, Action, Action2..Action4)"):format(tostring(priority)), 4)
	end
	return item
end

local function newHandle(animator: Instance, record: Record, id: string, group: string?)
	local track = record.track
	local handle = { Track = track, Id = id, Group = group, Ended = Signal.new(), _finished = false, _paused = false, _speed = 1 }

	function handle:IsPlaying(): boolean
		return not self._finished and track.IsPlaying
	end

	function handle:Stop(fade: number?)
		if self._finished then
			return
		end
		track:Stop(if fade ~= nil then fade else Config.Animation.DefaultFade)
	end

	function handle:Pause()
		if not self._finished and not self._paused then
			self._paused = true
			track:AdjustSpeed(0)
		end
	end

	function handle:Resume()
		if not self._finished and self._paused then
			self._paused = false
			track:AdjustSpeed(self._speed)
		end
	end

	function handle:SetSpeed(speed: number)
		if type(speed) ~= "number" then
			error("Core.Animation : speed (number) requis", 2)
		end
		self._speed = speed
		if not self._paused and not self._finished then
			track:AdjustSpeed(speed)
		end
	end

	function handle:SetWeight(weight: number, fade: number?)
		if type(weight) ~= "number" or weight < 0 then
			error("Core.Animation : weight (number >= 0) requis", 2)
		end
		if not self._finished then
			track:AdjustWeight(weight, fade)
		end
	end

	function handle:OnMarker(name: string, fn: (...any) -> ())
		return track:GetMarkerReachedSignal(name):Connect(fn)
	end

	function handle:WaitForMarker(name: string): ...any
		return track:GetMarkerReachedSignal(name):Wait()
	end

	function handle:Wait()
		if not self._finished then
			self.Ended:Wait()
		end
	end

	track.Ended:Once(function()
		if handle._finished then
			return
		end
		handle._finished = true
		record.handle = nil
		local slot = groups[animator]
		if slot and group and slot[group] == handle then
			slot[group] = nil
		end
		handle.Ended:Fire()
		handle.Ended:Destroy()
	end)

	return handle
end

function Tracks.Play(subject: any, source: any, options: any?)
	local opts = options or {}
	local animator = Util.GetAnimator(subject, true)
	local cache = cacheFor(animator)

	local animation, owned, id
	if typeof(source) == "Instance" then
		if not source:IsA("Animation") then
			error("Core.Animation.Play : un modèle doit être une Animation", 2)
		end
		animation, owned, id = source, false, source.AnimationId
	else
		id = Util.NormalizeId(source)
	end

	local record = cache[id]
	if not record then
		if not animation then
			animation = Instance.new("Animation")
			animation.AnimationId = id
			owned = true
		end
		local ok, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if not ok then
			if owned then
				animation:Destroy()
			end
			error(("Core.Animation.Play : chargement impossible de '%s' : %s"):format(id, tostring(track)), 2)
		end
		record = { track = track, animation = animation, owned = owned, handle = nil }
		cache[id] = record
	end
	local track = record.track

	local priority = resolvePriority(opts.Priority)
	if priority then
		track.Priority = priority
	end
	if opts.Looped ~= nil then
		track.Looped = opts.Looped
	end
	local speed = opts.Speed or 1
	local weight = if opts.Weight ~= nil then opts.Weight else 1
	local fade = if opts.FadeIn ~= nil then opts.FadeIn else Config.Animation.DefaultFade

	-- déjà en lecture : simple mise à jour, sauf Restart
	local existing = record.handle
	if existing and existing:IsPlaying() and not opts.Restart then
		existing:SetSpeed(speed)
		existing:SetWeight(weight, fade)
		return existing
	end

	-- groupe exclusif
	local group = opts.Group
	if group ~= nil then
		if type(group) ~= "string" then
			error("Core.Animation.Play : Group doit être une chaîne", 2)
		end
		local previous = groups[animator][group]
		if previous and previous ~= existing and not previous._finished then
			previous:Stop(fade)
		end
	end

	if existing and existing:IsPlaying() then
		track:Stop(0)
	end

	local handle = newHandle(animator, record, id, group)
	handle._speed = speed
	record.handle = handle
	if group then
		groups[animator][group] = handle
	end

	track:Play(fade, weight, speed)
	if opts.TimePosition then
		track.TimePosition = opts.TimePosition
	end
	return handle
end

function Tracks.Stop(subject: any, source: any, fade: number?)
	local animator = Util.GetAnimator(subject, false)
	local cache = animator and caches[animator]
	if not cache then
		return
	end
	local id = if typeof(source) == "Instance" then source.AnimationId else Util.NormalizeId(source)
	local record = cache[id]
	if record and record.handle then
		record.handle:Stop(fade)
	end
end

function Tracks.StopAll(subject: any, fade: number?): number
	local animator = Util.GetAnimator(subject, false)
	local cache = animator and caches[animator]
	if not cache then
		return 0
	end
	local stopped = 0
	for _, record in cache do
		if record.handle and record.handle:IsPlaying() then
			record.handle:Stop(fade)
			stopped += 1
		end
	end
	return stopped
end

function Tracks.GetPlaying(subject: any): { any }
	local animator = Util.GetAnimator(subject, false)
	local cache = animator and caches[animator]
	local list = {}
	if cache then
		for _, record in cache do
			if record.handle and record.handle:IsPlaying() then
				table.insert(list, record.handle)
			end
		end
	end
	return list
end

function Tracks.Preload(sources: { any }): { string }
	local instances, created, failed = {}, {}, {}
	for _, source in sources do
		if typeof(source) == "Instance" then
			table.insert(instances, source)
		else
			local animation = Instance.new("Animation")
			animation.AnimationId = Util.NormalizeId(source)
			table.insert(instances, animation)
			table.insert(created, animation)
		end
	end
	ContentProvider:PreloadAsync(instances, function(contentId: string, status: Enum.AssetFetchStatus)
		if status ~= Enum.AssetFetchStatus.Success then
			table.insert(failed, contentId)
		end
	end)
	for _, animation in created do
		animation:Destroy()
	end
	return failed
end

return Tracks
