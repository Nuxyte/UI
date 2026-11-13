--!nonstrict
--[[
	VFX.Emit / Play : effets de particules préfabriqués (un modèle d'effet = Part, Attachment ou Model contenant
	des ParticleEmitter / Beam / Trail / Light / Sound...).

	Attributs reconnus sur les ParticleEmitter du modèle :
		EmitCount   nombre de particules émises par Play (défaut 1)      EmitDelay   délai avant l'émission (s)

	VFX.Emit(container, count?) -> number     émet sur tous les ParticleEmitter (container lui-même inclus) ; retourne leur nombre
	VFX.SetEnabled(container, enabled) -> number   active/désactive émetteurs, beams, trails, lights
	VFX.GetDuration(container) -> number     durée utile (délai + durée de vie max des particules)

	VFX.Play(template, options?) -> handle
		options : Position (Vector3) | CFrame      emplacement (si Follow absent)
		          Follow     BasePart    suit cette pièce (Attachment : enfant de la pièce ; Part/Model : WeldConstraint)
		          Parent     Instance    parent de l'effet (défaut workspace)
		          Count      remplace EmitCount          Duration   durée des émetteurs continus (défaut Config.VFX.DefaultDuration)
		          Pool       true (défaut) : réutilise les instances (sauf Follow)
		handle:Stop()   arrête l'émission ; l'instance est libérée quand les dernières particules ont disparu
		handle.Instance   handle.Finished (Signal)
]]

local Config = require(script.Parent.Parent.Config)
local Pool = require(script.Parent.Parent.Utilities.Pool)
local Signal = require(script.Parent.Parent.Utilities.Signal)

local Emit = {}

local function eachEffect(container: Instance, className: string, fn: (Instance) -> ())
	if container:IsA(className) then
		fn(container)
	end
	for _, descendant in container:GetDescendants() do
		if descendant:IsA(className) then
			fn(descendant)
		end
	end
end

function Emit.Emit(container: Instance, count: number?): number
	if typeof(container) ~= "Instance" then
		error("Core.VFX.Emit : Instance attendue", 2)
	end
	local found = 0
	eachEffect(container, "ParticleEmitter", function(emitter)
		found += 1
		local amount = count or emitter:GetAttribute("EmitCount") or 1
		local delay = emitter:GetAttribute("EmitDelay")
		if type(delay) == "number" and delay > 0 then
			task.delay(delay, function()
				if emitter.Parent then
					emitter:Emit(amount)
				end
			end)
		else
			emitter:Emit(amount)
		end
	end)
	if found == 0 then
		error("Core.VFX.Emit : aucun ParticleEmitter trouvé dans " .. container.Name, 2)
	end
	return found
end

local TOGGLEABLE = { "ParticleEmitter", "Beam", "Trail", "Light", "Smoke", "Fire", "Sparkles" }

function Emit.SetEnabled(container: Instance, enabled: boolean): number
	if typeof(container) ~= "Instance" then
		error("Core.VFX.SetEnabled : Instance attendue", 2)
	end
	local changed = 0
	for _, className in TOGGLEABLE do
		eachEffect(container, className, function(effect)
			effect.Enabled = enabled
			changed += 1
		end)
	end
	return changed
end

function Emit.GetDuration(container: Instance): number
	local longest = 0
	eachEffect(container, "ParticleEmitter", function(emitter)
		local delay = emitter:GetAttribute("EmitDelay")
		longest = math.max(longest, emitter.Lifetime.Max + (if type(delay) == "number" then delay else 0))
	end)
	return longest
end

-- Recopie l'état Enabled du modèle sur une instance recyclée (Stop() l'a désactivée).
local function syncEnabled(template: Instance, instance: Instance)
	local function collect(root: Instance): { Instance }
		local list = {}
		for _, className in TOGGLEABLE do
			eachEffect(root, className, function(effect)
				table.insert(list, effect)
			end)
		end
		return list
	end
	local from, to = collect(template), collect(instance)
	for i, effect in from do
		if to[i] and to[i].ClassName == effect.ClassName then
			to[i].Enabled = effect.Enabled
		end
	end
end

local function hasContinuous(container: Instance): boolean
	local continuous = false
	eachEffect(container, "ParticleEmitter", function(emitter)
		if emitter.Enabled then
			continuous = true
		end
	end)
	return continuous
end

-- Pools par modèle (clé faible : le pool disparaît avec le modèle)
local pools = setmetatable({}, { __mode = "k" })

local function carrierPart(): BasePart
	local part = Instance.new("Part")
	part.Name = "CoreVFX"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	return part
end

local function poolFor(template: Instance)
	local pool = pools[template]
	if not pool then
		pool = Pool.new({
			MaxIdle = Config.VFX.PoolSize,
			Create = function()
				local clone
				if template:IsA("Attachment") then
					clone = carrierPart()
					template:Clone().Parent = clone
				else
					clone = template:Clone()
				end
				return clone
			end,
			Reset = function(instance)
				instance.Parent = nil
			end,
		})
		pools[template] = pool
	end
	return pool
end

local function placeRoot(instance: Instance, cframe: CFrame)
	if instance:IsA("Model") then
		instance:PivotTo(cframe)
	elseif instance:IsA("BasePart") then
		instance.CFrame = cframe
	end
end

function Emit.Play(template: Instance, options: any?)
	if typeof(template) ~= "Instance" or not (template:IsA("BasePart") or template:IsA("Attachment") or template:IsA("Model")) then
		error("Core.VFX.Play : modèle d'effet (BasePart, Attachment ou Model) attendu", 2)
	end
	local opts = options or {}
	local follow = opts.Follow
	if follow ~= nil and not (typeof(follow) == "Instance" and follow:IsA("BasePart")) then
		error("Core.VFX.Play : Follow doit être une BasePart", 2)
	end

	local cframe = opts.CFrame or (opts.Position and CFrame.new(opts.Position)) or (follow and follow.CFrame) or CFrame.new()
	local usePool = opts.Pool ~= false and follow == nil
	local pool = usePool and poolFor(template) or nil

	local instance, attachedClone
	if follow and template:IsA("Attachment") then
		-- l'attachement est cloné directement dans la pièce suivie
		attachedClone = template:Clone()
		attachedClone.Parent = follow
		instance = attachedClone
	else
		instance = if pool then pool:Get() else (if template:IsA("Attachment") then carrierPart() else template:Clone())
		if not pool and template:IsA("Attachment") then
			template:Clone().Parent = instance
		end
		if pool then
			syncEnabled(template, instance)
		end
		placeRoot(instance, cframe)
		instance.Parent = opts.Parent or workspace
		if follow then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = follow
			weld.Part1 = if instance:IsA("Model") then instance.PrimaryPart else instance
			weld.Parent = instance
			if instance:IsA("BasePart") then
				instance.Anchored = false
			end
		end
	end

	local finished = Signal.new()
	local handle = { Instance = instance, Finished = finished, _done = false }

	local function release()
		if handle._done then
			return
		end
		handle._done = true
		if pool then
			pool:Release(instance)
		else
			instance:Destroy()
		end
		finished:Fire()
		finished:Destroy()
	end

	local lingering = Emit.GetDuration(instance)
	local continuous = hasContinuous(instance)
	local activeFor = if continuous then (opts.Duration or Config.VFX.DefaultDuration) else 0

	if not continuous or opts.Count then
		-- burst (les émetteurs continus ne sont pas "Emit"és : ils tournent déjà)
		pcall(Emit.Emit, instance, opts.Count) -- pas d'émetteur (Beam seul...) : rien à émettre
	end

	function handle:Stop()
		if self._done or self._stopping then
			return
		end
		self._stopping = true
		Emit.SetEnabled(instance, false)
		task.delay(lingering, release)
	end

	task.delay(activeFor, function()
		handle:Stop()
	end)
	return handle
end

return Emit
