--!nonstrict
--[[
	Movement.Physical
	Mouvements pilotés par la PHYSIQUE Roblox (contrairement aux autres, cinématiques).
	À appeler côté serveur, ou côté client sur un objet dont le client a la propriété réseau (son personnage).

	Dash(subject, direction, options?) -> handle
		Propulse `subject` (BasePart / Model avec HumanoidRootPart ou PrimaryPart) dans `direction`.
		options : Distance (20)  Duration (0.25)  KeepY (false : mouvement horizontal, gravité neutralisée pendant le dash)
		          OnComplete
		Utilise un LinearVelocity temporaire, retiré automatiquement (fin, annulation ou destruction du sujet).

	Knockback(subject, direction, force, options?) -> impulse: Vector3
		Applique une impulsion (ApplyImpulse) ; `force` = changement de vitesse en studs/s (indépendant de la masse).
		options : Upward (0.35)  part verticale ajoutée à la direction horizontale

	Exemple
		Core.Movement.Dash(character, root.CFrame.LookVector, { Distance = 25, Duration = 0.2 })
		Core.Movement.Knockback(enemy, enemy.HumanoidRootPart.Position - hitPosition, 60)
]]

local Driver = require(script.Parent.Driver)
local Util = require(script.Parent.Util)

local Physical = {}

function Physical.Dash(subject: Instance, direction: Vector3, options: any?)
	local root = Util.GetRoot(subject)
	if not root then
		error("Core.Movement.Dash : aucune BasePart racine trouvée (BasePart, PrimaryPart ou HumanoidRootPart)", 2)
	end
	if typeof(direction) ~= "Vector3" then
		error("Core.Movement.Dash : direction (Vector3) requise", 2)
	end

	local opts = options or {}
	local distance = opts.Distance or 20
	local duration = opts.Duration or 0.25
	if duration <= 0 or distance <= 0 then
		error("Core.Movement.Dash : Distance et Duration doivent être > 0", 2)
	end

	local aim = Vector3.new(direction.X, if opts.KeepY then direction.Y else 0, direction.Z)
	if aim.Magnitude < 1e-4 then
		error("Core.Movement.Dash : direction nulle", 2)
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "CoreDashAttachment"
	attachment.Parent = root

	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "CoreDash"
	velocity.Attachment0 = attachment
	velocity.MaxForce = math.huge
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.VectorVelocity = aim.Unit * (distance / duration)
	velocity.Parent = root

	local elapsed = 0
	return Driver.Run(root, function(dt)
		elapsed += dt
		return elapsed >= duration
	end, function(status)
		velocity:Destroy()
		attachment:Destroy()
		if status == "Completed" and opts.OnComplete then
			task.spawn(opts.OnComplete)
		end
	end, Driver.MetaFrom(opts, "Dash"))
end

function Physical.Knockback(subject: Instance, direction: Vector3, force: number, options: any?): Vector3
	local root = Util.GetRoot(subject)
	if not root then
		error("Core.Movement.Knockback : aucune BasePart racine trouvée", 2)
	end
	if typeof(direction) ~= "Vector3" or type(force) ~= "number" then
		error("Core.Movement.Knockback : (subject, direction: Vector3, force: number)", 2)
	end

	local upward = if options and options.Upward ~= nil then options.Upward else 0.35
	local flat = Vector3.new(direction.X, 0, direction.Z)
	local aim = (if flat.Magnitude > 1e-4 then flat.Unit else Vector3.zero) + Vector3.new(0, upward, 0)
	if aim.Magnitude < 1e-4 then
		error("Core.Movement.Knockback : direction nulle (donnez une direction ou Upward > 0)", 2)
	end

	local impulse = aim.Unit * force * root.AssemblyMass
	root:ApplyImpulse(impulse)
	return impulse
end

return Physical
