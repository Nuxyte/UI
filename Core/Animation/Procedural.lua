--!nonstrict
--[[
	Animation.Procedural : animation par clés SANS asset, qui pilote directement les Motor6D.Transform d'un rig.
	Utile pour des rigs sans AnimationId, des prototypes, ou des effets (secousse, respiration, tête qui tourne).
	Une seule connexion Heartbeat partagée (Core.Engine.Scheduler), active tant qu'un clip joue.

	Procedural.Play(model, clip, options?) -> handle
		clip = {
			Duration  = 1.2,                      secondes (> 0)
			Looped    = false,
			Easing    = "SineInOut",              nom d'easing Core.Tween (défaut "Linear")
			Keyframes = {
				{ Time = 0,   Pose = { Head = CFrame.new() } },
				{ Time = 0.6, Pose = { Head = CFrame.Angles(0, math.rad(40), 0), Torso = CFrame.new(0, 0.2, 0) } },
				{ Time = 1.2, Pose = { Head = CFrame.new() } },
			},
		}
		Pose : { [nomDeJoint] = CFrame } — CFrame appliqué à Motor6D.Transform (relatif à la pose de repos).
		       Un joint est trouvé par le nom du Motor6D ou par le nom de sa Part1. Chaque joint est interpolé entre SES clés ;
		       avant la première / après la dernière on maintient la valeur de la clé.
		options : Speed (1)   Weight (1 : 0 = repos, 1 = pose complète)   Looped (écrase clip.Looped)
		          Group (string)   un nouveau clip du même groupe sur ce modèle annule l'ancien
	handle (Core.Engine.Scheduler) : :Pause() :Resume() :Cancel() :Wait() .State .Completed ; :SetSpeed(s) :SetWeight(w) .Time
	À la fin / à l'annulation les joints reviennent à CFrame.new() (repos).

	Procedural.Validate(clip, model?) -> true          lève une erreur détaillée si le clip est invalide (ou si un joint manque)
	Procedural.Stop(model)                             annule tous les clips du modèle
	Procedural.GetActive(model) -> number

	Deux clips qui écrivent le même joint se disputent le Transform (le dernier gagne) : utilisez Group pour les rendre exclusifs.
]]

local Driver = require(script.Parent.Parent.Engine.Scheduler)
local Easing = require(script.Parent.Parent.Tween.Easing)

local Procedural = {}

local active: { [Instance]: { any } } = setmetatable({}, { __mode = "k" })
local grouped: { [Instance]: { [string]: any } } = setmetatable({}, { __mode = "k" })

local function validateClip(clip: any)
	if type(clip) ~= "table" then
		error("Core.Animation.Procedural : clip (table) requis", 3)
	end
	if type(clip.Duration) ~= "number" or clip.Duration <= 0 then
		error("Core.Animation.Procedural : clip.Duration doit être un nombre > 0", 3)
	end
	if type(clip.Keyframes) ~= "table" or #clip.Keyframes == 0 then
		error("Core.Animation.Procedural : clip.Keyframes (liste non vide) requis", 3)
	end
	if clip.Easing ~= nil then
		local ok = pcall(Easing.Get, clip.Easing)
		if not ok then
			error(("Core.Animation.Procedural : Easing inconnu '%s'"):format(tostring(clip.Easing)), 3)
		end
	end

	local last = -math.huge
	for index, frame in clip.Keyframes do
		if type(frame) ~= "table" or type(frame.Time) ~= "number" or type(frame.Pose) ~= "table" then
			error(("Core.Animation.Procedural : keyframe #%d invalide ({ Time = number, Pose = table } attendu)"):format(index), 3)
		end
		if frame.Time < 0 or frame.Time > clip.Duration then
			error(("Core.Animation.Procedural : keyframe #%d : Time %g hors de [0, Duration]"):format(index, frame.Time), 3)
		end
		if frame.Time <= last then
			error(("Core.Animation.Procedural : keyframe #%d : les Time doivent être strictement croissants"):format(index), 3)
		end
		last = frame.Time
		for joint, cframe in frame.Pose do
			if type(joint) ~= "string" or typeof(cframe) ~= "CFrame" then
				error(("Core.Animation.Procedural : keyframe #%d : Pose doit être { [string] = CFrame }"):format(index), 3)
			end
		end
	end
end

local function findJoints(model: Instance, clip: any): { [string]: Instance }
	local wanted = {}
	for _, frame in clip.Keyframes do
		for joint in frame.Pose do
			wanted[joint] = true
		end
	end

	local joints = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") then
			if wanted[descendant.Name] and not joints[descendant.Name] then
				joints[descendant.Name] = descendant
			end
			local part1 = descendant.Part1
			if part1 and wanted[part1.Name] and not joints[part1.Name] then
				joints[part1.Name] = descendant
			end
		end
	end

	local missing = {}
	for joint in wanted do
		if not joints[joint] then
			table.insert(missing, joint)
		end
	end
	if #missing > 0 then
		table.sort(missing)
		error(("Core.Animation.Procedural : joint(s) introuvable(s) dans %s : %s"):format(model.Name, table.concat(missing, ", ")), 3)
	end
	return joints
end

function Procedural.Validate(clip: any, model: Instance?): boolean
	validateClip(clip)
	if model then
		findJoints(model, clip)
	end
	return true
end

-- Pour chaque joint : liste triée { time, cframe } extraite des keyframes.
local function buildTracks(clip: any): { [string]: { { time: number, cframe: CFrame } } }
	local tracks = {}
	for _, frame in clip.Keyframes do
		for joint, cframe in frame.Pose do
			local track = tracks[joint]
			if not track then
				track = {}
				tracks[joint] = track
			end
			table.insert(track, { time = frame.Time, cframe = cframe })
		end
	end
	return tracks
end

local function sample(track: { { time: number, cframe: CFrame } }, t: number, ease: (number) -> number): CFrame
	local first, last = track[1], track[#track]
	if t <= first.time then
		return first.cframe
	elseif t >= last.time then
		return last.cframe
	end
	for i = 2, #track do
		local b = track[i]
		if t <= b.time then
			local a = track[i - 1]
			return a.cframe:Lerp(b.cframe, ease((t - a.time) / (b.time - a.time)))
		end
	end
	return last.cframe
end

local function release(model: Instance, handle: any)
	local list = active[model]
	if list then
		local index = table.find(list, handle)
		if index then
			table.remove(list, index)
		end
	end
	local slots = grouped[model]
	if slots and handle._group and slots[handle._group] == handle then
		slots[handle._group] = nil
	end
end

function Procedural.Play(model: Instance, clip: any, options: any?)
	if typeof(model) ~= "Instance" then
		error("Core.Animation.Procedural.Play : modèle (Instance) requis", 2)
	end
	validateClip(clip)
	local opts = options or {}
	local joints = findJoints(model, clip)
	local tracks = buildTracks(clip)
	local ease = Easing.Get(clip.Easing or "Linear")
	local looped = if opts.Looped ~= nil then opts.Looped else clip.Looped == true
	local duration = clip.Duration

	local group = opts.Group
	if group ~= nil then
		if type(group) ~= "string" then
			error("Core.Animation.Procedural.Play : Group doit être une chaîne", 2)
		end
		local previous = grouped[model] and grouped[model][group]
		if previous then
			previous:Cancel()
		end
	end

	local state = { time = 0, speed = opts.Speed or 1, weight = if opts.Weight ~= nil then opts.Weight else 1 }
	local identity = CFrame.new()

	local function apply()
		for name, joint in joints do
			local cframe = sample(tracks[name], state.time, ease)
			if state.weight < 1 then
				cframe = identity:Lerp(cframe, state.weight)
			end
			joint.Transform = cframe
		end
	end

	local handle
	handle = Driver.Run(model, function(dt)
		state.time += dt * state.speed
		if looped then
			state.time %= duration
			handle.Time = state.time
			apply()
			return false
		end
		if state.time >= duration then
			state.time = duration
			handle.Time = duration
			apply()
			return true
		end
		handle.Time = state.time
		apply()
		return false
	end, function()
		for _, joint in joints do
			if joint.Parent then
				joint.Transform = identity
			end
		end
		release(model, handle)
	end)

	handle.Time = 0
	handle._group = group
	handle.Clip = clip
	function handle:SetSpeed(speed: number)
		if type(speed) ~= "number" then
			error("Core.Animation.Procedural : speed (number) requis", 2)
		end
		state.speed = speed
	end
	function handle:SetWeight(weight: number)
		if type(weight) ~= "number" or weight < 0 or weight > 1 then
			error("Core.Animation.Procedural : weight doit être entre 0 et 1", 2)
		end
		state.weight = weight
	end

	active[model] = active[model] or {}
	table.insert(active[model], handle)
	if group then
		grouped[model] = grouped[model] or {}
		grouped[model][group] = handle
	end

	apply() -- pose initiale immédiate
	return handle
end

function Procedural.Stop(model: Instance)
	local list = active[model]
	if list then
		for _, handle in table.clone(list) do
			handle:Cancel()
		end
	end
end

function Procedural.GetActive(model: Instance): number
	local list = active[model]
	return if list then #list else 0
end

return Procedural
