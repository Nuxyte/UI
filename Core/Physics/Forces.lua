--!nonstrict
--[[
	Physics.Forces
	Manipulation simplifiée de la physique Roblox (objets NON ancrés). À utiliser côté serveur, ou côté client
	sur un objet dont le client a la propriété réseau.

	Launch(subject, velocity, options?) -> BasePart       fixe la vitesse linéaire (options.Add = true : l'ajoute à l'actuelle)
	LaunchTo(subject, target, arcHeight?, options?) -> velocity, flightTime
		lance vers `target` (Vector3 | Instance) ; arcHeight = hauteur du sommet au-dessus du point le plus haut (défaut 10)
	Impulse(subject, impulse, atPosition?)                impulsion brute (masse × vitesse)
	Push(subject, velocityChange, atPosition?)            variation de vitesse (indépendante de la masse)
	AngularImpulse(subject, impulse)
	Force(subject, force, options?) -> handle             force continue ; options : Duration (s)  Relative (repère de l'objet)
	SetGravity(subject, gravity) -> handle                gravité personnalisée : nombre = multiplicateur (0 = apesanteur,
	                                                      0.5 = lune, -1 = inversée) ou Vector3 = accélération (studs/s²)
	Pull(subject, target, options?) -> handle             attire l'objet vers Vector3 / BasePart (AlignPosition)
		options : Responsiveness (20)  MaxForce (inf)  MaxVelocity (inf)  Rigid (false)
		handle:SetTarget(target)
	Field(options) -> handle                              champ d'attraction (strength > 0) ou de répulsion (< 0)
		options : Center (Vector3|Instance|function)  Radius  Strength (accélération en studs/s² au centre)
		          Falloff "Linear" (défaut) | "Inverse" | "Constant"   MinDistance (1)   Duration
		          Targets : { Instance } | function() -> { Instance } | "Tag"   (BasePart / Model)
	Explode(center, radius, force, options?) -> { BasePart }   souffle : change la vitesse des assemblages non ancrés
		options : Falloff "Linear"  UpwardBias (0.3)  Ignore  Whitelist
	handle.Remove() / handle:Remove() sur Force, SetGravity, Pull ; Field : Cancel()

	Exemple
		Core.Physics.Launch(ball, Core.Math.CalculateLaunchVelocity(a, b, 15))
		local g = Core.Physics.SetGravity(crate, 0.2); g:Remove()
]]

local CollectionService = game:GetService("CollectionService")

local Driver = require(script.Parent.Parent.Engine.Scheduler)
local Trajectory = require(script.Parent.Parent.Math.Trajectory)
local Cast = require(script.Parent.Cast)
local Util = require(script.Parent.Util)

local Forces = {}

local function requireUnanchored(root: BasePart, fnName: string)
	if root.Anchored then
		error(("Core.Physics.%s : l'objet est ancré (Anchored = true), la physique n'a aucun effet"):format(fnName), 3)
	end
end

local function makeAttachment(root: BasePart, name: string): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Parent = root
	return attachment
end

function Forces.Launch(subject: any, velocity: Vector3, options: any?): BasePart
	local root = Util.RequireRoot(subject, "Launch")
	if typeof(velocity) ~= "Vector3" then
		error("Core.Physics.Launch : velocity (Vector3) requis", 2)
	end
	requireUnanchored(root, "Launch")

	if options and options.Add then
		root.AssemblyLinearVelocity += velocity
	else
		root.AssemblyLinearVelocity = velocity
	end
	return root
end

function Forces.LaunchTo(subject: any, target: any, arcHeight: number?, options: any?): (Vector3, number)
	local root = Util.RequireRoot(subject, "LaunchTo")
	requireUnanchored(root, "LaunchTo")
	local goal = Util.GetPosition(target)
	local velocity, flightTime = Trajectory.CalculateLaunchVelocity(root.Position, goal, arcHeight or 10)
	Forces.Launch(root, velocity, options)
	return velocity, flightTime
end

function Forces.Impulse(subject: any, impulse: Vector3, atPosition: Vector3?)
	local root = Util.RequireRoot(subject, "Impulse")
	requireUnanchored(root, "Impulse")
	if atPosition then
		root:ApplyImpulseAtPosition(impulse, atPosition)
	else
		root:ApplyImpulse(impulse)
	end
end

function Forces.Push(subject: any, velocityChange: Vector3, atPosition: Vector3?)
	local root = Util.RequireRoot(subject, "Push")
	Forces.Impulse(root, velocityChange * root.AssemblyMass, atPosition)
end

function Forces.AngularImpulse(subject: any, impulse: Vector3)
	local root = Util.RequireRoot(subject, "AngularImpulse")
	requireUnanchored(root, "AngularImpulse")
	root:ApplyAngularImpulse(impulse)
end

local function removable(instances: { Instance }, extra: { [string]: any }?)
	local handle = extra or {}
	local removed = false
	function handle.Remove()
		if removed then
			return
		end
		removed = true
		for _, instance in instances do
			instance:Destroy()
		end
		if handle._timer then
			pcall(task.cancel, handle._timer)
			handle._timer = nil
		end
	end
	return handle
end

function Forces.Force(subject: any, force: Vector3, options: any?)
	local root = Util.RequireRoot(subject, "Force")
	requireUnanchored(root, "Force")
	if typeof(force) ~= "Vector3" then
		error("Core.Physics.Force : force (Vector3) requise", 2)
	end

	local opts = options or {}
	local attachment = makeAttachment(root, "CoreForceAttachment")
	local vectorForce = Instance.new("VectorForce")
	vectorForce.Name = "CoreForce"
	vectorForce.Attachment0 = attachment
	vectorForce.ApplyAtCenterOfMass = true
	vectorForce.RelativeTo = if opts.Relative then Enum.ActuatorRelativeTo.Attachment0 else Enum.ActuatorRelativeTo.World
	vectorForce.Force = force
	vectorForce.Parent = root

	local handle = removable({ vectorForce, attachment }, { Instance = vectorForce })
	function handle.SetForce(newForce: Vector3)
		vectorForce.Force = newForce
	end
	if opts.Duration then
		handle._timer = task.delay(opts.Duration, handle.Remove)
	end
	return handle
end

function Forces.SetGravity(subject: any, gravity: any)
	local root = Util.RequireRoot(subject, "SetGravity")
	requireUnanchored(root, "SetGravity")

	local worldGravity = Trajectory.GetGravity()
	local desired
	if type(gravity) == "number" then
		desired = Vector3.new(0, -worldGravity * gravity, 0)
	elseif typeof(gravity) == "Vector3" then
		desired = gravity
	else
		error("Core.Physics.SetGravity : nombre (multiplicateur) ou Vector3 (accélération) attendu", 2)
	end

	-- La gravité du monde s'applique toujours ; on ajoute la différence sous forme de force (m × Δa).
	local delta = desired - Vector3.new(0, -worldGravity, 0)
	return Forces.Force(root, delta * root.AssemblyMass)
end

function Forces.Pull(subject: any, target: any, options: any?)
	local root = Util.RequireRoot(subject, "Pull")
	requireUnanchored(root, "Pull")
	local opts = options or {}

	local attachment0 = makeAttachment(root, "CorePullAttachment")
	local align = Instance.new("AlignPosition")
	align.Name = "CorePull"
	align.Attachment0 = attachment0
	align.Responsiveness = opts.Responsiveness or 20
	align.MaxForce = opts.MaxForce or math.huge
	align.MaxVelocity = opts.MaxVelocity or math.huge
	align.RigidityEnabled = opts.Rigid == true
	align.Parent = root

	local anchorAttachment = nil
	local handle = removable({ align, attachment0 }, { Instance = align })

	function handle:SetTarget(newTarget: any)
		if anchorAttachment and anchorAttachment.Parent then
			if anchorAttachment:GetAttribute("CoreTemp") then
				anchorAttachment:Destroy()
			end
		end
		anchorAttachment = nil

		if typeof(newTarget) == "Vector3" then
			align.Mode = Enum.PositionAlignmentMode.OneAttachment
			align.Position = newTarget
		elseif typeof(newTarget) == "Instance" and newTarget:IsA("BasePart") then
			align.Mode = Enum.PositionAlignmentMode.TwoAttachment
			anchorAttachment = makeAttachment(newTarget, "CorePullTarget")
			anchorAttachment:SetAttribute("CoreTemp", true)
			align.Attachment1 = anchorAttachment
		else
			error("Core.Physics.Pull : cible Vector3 ou BasePart attendue", 2)
		end
	end
	handle:SetTarget(target)

	local baseRemove = handle.Remove
	function handle.Remove()
		if anchorAttachment and anchorAttachment:GetAttribute("CoreTemp") then
			anchorAttachment:Destroy()
		end
		baseRemove()
	end
	return handle
end

local FALLOFF = {
	Linear = function(distance: number, radius: number): number
		return math.max(1 - distance / radius, 0)
	end,
	Inverse = function(distance: number, radius: number): number
		local d = math.max(distance, 1)
		return if distance <= radius then 1 / (d * d) else 0
	end,
	Constant = function(distance: number, radius: number): number
		return if distance <= radius then 1 else 0
	end,
}

local function collectTargets(spec: any): { Instance }
	if type(spec) == "function" then
		return spec()
	elseif type(spec) == "string" then
		return CollectionService:GetTagged(spec)
	end
	return spec or {}
end

function Forces.Field(options: any)
	if type(options) ~= "table" or options.Center == nil or type(options.Radius) ~= "number" or type(options.Strength) ~= "number" then
		error("Core.Physics.Field : options { Center, Radius, Strength, Targets } requis", 2)
	end
	local falloff = FALLOFF[options.Falloff or "Linear"]
	if not falloff then
		error(("Core.Physics.Field : Falloff inconnu '%s' (Linear, Inverse, Constant)"):format(tostring(options.Falloff)), 2)
	end

	local minDistance = options.MinDistance or 1
	local elapsed = 0

	return Driver.Run(nil, function(dt)
		local center = Util.GetPosition(options.Center)

		for _, target in collectTargets(options.Targets) do
			local root = Util.GetRoot(target)
			if root and not root.Anchored then
				local toCenter = center - root.Position
				local distance = toCenter.Magnitude
				if distance <= options.Radius and distance > 1e-6 then
					local factor = falloff(math.max(distance, minDistance), options.Radius)
					local acceleration = toCenter.Unit * (options.Strength * factor)
					root:ApplyImpulse(acceleration * root.AssemblyMass * dt)
				end
			end
		end

		elapsed += dt
		return options.Duration ~= nil and elapsed >= options.Duration
	end)
end

function Forces.Explode(center: Vector3, radius: number, force: number, options: any?): { BasePart }
	local opts = options or {}
	local falloff = FALLOFF[opts.Falloff or "Linear"]
	if not falloff then
		error("Core.Physics.Explode : Falloff inconnu (Linear, Inverse, Constant)", 2)
	end
	local upward = if opts.UpwardBias ~= nil then opts.UpwardBias else 0.3

	local affected, seen = {}, {}
	for _, part in Cast.GetPartsInRadius(center, radius, { Ignore = opts.Ignore, Whitelist = opts.Whitelist }) do
		local root = part.AssemblyRootPart or part
		if not seen[root] and not root.Anchored then
			seen[root] = true
			local offset = root.Position - center
			local distance = offset.Magnitude
			local factor = falloff(distance, radius)
			if factor > 0 then
				local direction = if distance > 1e-6 then offset.Unit else Vector3.yAxis
				local aim = (direction + Vector3.new(0, upward, 0)).Unit
				root:ApplyImpulse(aim * force * factor * root.AssemblyMass)
				table.insert(affected, root)
			end
		end
	end
	return affected
end

return Forces
