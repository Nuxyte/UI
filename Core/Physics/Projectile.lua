--!nonstrict
--[[
	Physics.Projectile
	Projectiles CINÉMATIQUES (position calculée à chaque frame, collisions par Raycast/Spherecast balayés) :
	pas de tunneling à haute vitesse, déterministes, peu coûteux. Une seule connexion Heartbeat partagée.

	Projectile.Fire(options) -> handle
		Origin      Vector3 (requis)
		Départ — l'un de :
		  Velocity  Vector3
		  Target    Vector3 | Instance | function  avec  Speed (studs/s)  ou  ArcHeight  ou  Time   (voir Math.Trajectory)
		Gravity     multiplicateur de gravité (défaut 0 = trajectoire droite ; 1 = gravité du monde)
		Radius      > 0 : Spherecast (projectile "épais") ; sinon Raycast
		Lifetime    secondes (défaut 5)        MaxDistance   studs (défaut illimité)
		Ignore / Whitelist / CollisionGroup     filtres de collision
		Part        Instance existante à déplacer     |     Template  Instance clonée (détruite à la fin sauf KeepPart)
		Face        true : oriente l'objet selon la vitesse
		Pierce      nombre de cibles traversées avant de s'arrêter (0)
		Bounce      nombre de rebonds (0)    Restitution (0.6)  part de vitesse conservée au rebond
		Homing      { Target = Instance|Vector3|function, TurnRate = rad/s (défaut 3) }
		OnHit(hit) -> false pour ignorer cette collision (traverse)       hit = { Position, Normal, Instance, Distance, Velocity }
		OnStep(position, velocity, dt)
		OnEnd(reason)               reason : "Hit" | "Expired" | "MaxDistance" | "Cancelled"
	handle : .Position  .Velocity  .State  :Cancel()  :Wait()  .Hit (Signal)  .Ended (Signal) ; hérite de Engine.Scheduler

	Exemple
		Core.Physics.Projectile.Fire({
			Origin = muzzle.Position, Target = enemy.Position, ArcHeight = 8, Gravity = 1, Radius = 0.5,
			Template = ReplicatedStorage.Arrow, Face = true, Ignore = { character },
			OnHit = function(hit) damage(hit.Instance) end,
		})
]]

local Driver = require(script.Parent.Parent.Engine.Scheduler)
local Signal = require(script.Parent.Parent.Utilities.Signal)
local Geometry = require(script.Parent.Parent.Math.Geometry)
local Trajectory = require(script.Parent.Parent.Math.Trajectory)
local Cast = require(script.Parent.Cast)
local Util = require(script.Parent.Util)

local Projectile = {}

local function resolveVelocity(options: any): Vector3
	if options.Velocity ~= nil then
		if typeof(options.Velocity) ~= "Vector3" then
			error("Core.Physics.Projectile : Velocity doit être un Vector3", 3)
		end
		return options.Velocity
	end

	if options.Target == nil then
		error("Core.Physics.Projectile : Velocity ou Target requis", 3)
	end
	local target = Util.GetPosition(options.Target)
	local origin = options.Origin
	local gravity = Trajectory.GetGravity() * (options.Gravity or 0)

	if options.ArcHeight then
		if gravity <= 0 then
			error("Core.Physics.Projectile : ArcHeight exige Gravity > 0", 3)
		end
		return (Trajectory.CalculateLaunchVelocity(origin, target, options.ArcHeight, gravity))
	elseif options.Time then
		return (Trajectory.CalculateLaunchVelocityByTime(origin, target, options.Time, gravity))
	elseif options.Speed then
		if gravity > 0 then
			local velocity = Trajectory.CalculateLaunchVelocityBySpeed(origin, target, options.Speed, gravity)
			if not velocity then
				error("Core.Physics.Projectile : cible hors de portée à cette vitesse", 3)
			end
			return velocity
		end
		local direction = target - origin
		if direction.Magnitude < 1e-6 then
			error("Core.Physics.Projectile : origine et cible identiques", 3)
		end
		return direction.Unit * options.Speed
	end
	error("Core.Physics.Projectile : Target exige Speed, ArcHeight ou Time", 3)
end

function Projectile.Fire(options: any)
	if type(options) ~= "table" or typeof(options.Origin) ~= "Vector3" then
		error("Core.Physics.Projectile.Fire : options { Origin = Vector3, ... } requis", 2)
	end

	local velocity = resolveVelocity(options)
	local position = options.Origin
	local gravityAccel = Trajectory.GetGravity() * (options.Gravity or 0)
	local lifetime = options.Lifetime or 5
	local radius = options.Radius or 0
	local restitution = if options.Restitution ~= nil then options.Restitution else 0.6
	local maxBounces, maxPierce = options.Bounce or 0, options.Pierce or 0
	local homing = options.Homing

	local ignore = table.clone(options.Ignore or {})
	local castOptions = { Ignore = ignore, Whitelist = options.Whitelist, CollisionGroup = options.CollisionGroup }

	-- Objet visuel
	local visual = options.Part
	local ownsVisual = false
	if visual == nil and options.Template ~= nil then
		visual = options.Template:Clone()
		visual.Parent = workspace
		ownsVisual = not options.KeepPart
	end
	if visual then
		table.insert(ignore, visual)
	end

	local handle
	local elapsed, travelled, bounces, pierced = 0, 0, 0, 0
	local endReason = "Expired"

	local function orient()
		if not visual then
			return
		end
		local cf
		if options.Face and velocity.Magnitude > 1e-4 then
			cf = CFrame.lookAt(position, position + velocity)
		else
			cf = CFrame.new(position)
		end
		if visual:IsA("Model") then
			visual:PivotTo(cf)
		else
			visual.CFrame = cf
		end
	end
	orient()

	local hitSignal, endedSignal = Signal.new(), Signal.new()

	local function step(dt: number)
		elapsed += dt
		if elapsed >= lifetime then
			endReason = "Expired"
			return true
		end

		if gravityAccel ~= 0 then
			velocity += Vector3.new(0, -gravityAccel * dt, 0)
		end

		if homing then
			local goal = Util.GetPosition(homing.Target)
			local desired = goal - position
			local speed = velocity.Magnitude
			if desired.Magnitude > 1e-4 and speed > 1e-4 then
				local angle = Geometry.AngleBetween(velocity, desired)
				if angle > 1e-4 then
					local alpha = math.min(1, (homing.TurnRate or 3) * dt / angle)
					velocity = velocity.Unit:Lerp(desired.Unit, alpha).Unit * speed
				end
			end
		end

		local displacement = velocity * dt
		local distance = displacement.Magnitude
		if distance < 1e-9 then
			return false
		end

		local hit
		if radius > 0 then
			hit = Cast.Spherecast(position, radius, displacement, castOptions)
		else
			hit = Cast.Raycast(position, displacement, castOptions)
		end

		if hit then
			local info = {
				Position = hit.Position,
				Normal = hit.Normal,
				Instance = hit.Instance,
				Distance = (hit.Position - options.Origin).Magnitude,
				Velocity = velocity,
			}

			if options.OnHit and options.OnHit(info) == false then
				-- collision ignorée : on traverse cet objet
				table.insert(ignore, hit.Instance)
				position += displacement
				travelled += distance
			else
				hitSignal:Fire(info)
				if pierced < maxPierce then
					pierced += 1
					table.insert(ignore, hit.Instance)
					position += displacement
					travelled += distance
				elseif bounces < maxBounces then
					bounces += 1
					velocity = Geometry.Reflect(velocity, hit.Normal) * restitution
					position = hit.Position + hit.Normal * 0.01
				else
					position = hit.Position
					handle.Position = position
					orient()
					endReason = "Hit"
					return true
				end
			end
		else
			position += displacement
			travelled += distance
		end

		handle.Position, handle.Velocity = position, velocity
		orient()

		if options.OnStep then
			options.OnStep(position, velocity, dt)
		end
		if options.MaxDistance and travelled >= options.MaxDistance then
			endReason = "MaxDistance"
			return true
		end
		return false
	end

	handle = Driver.Run(visual, step, function(status)
		if status == "Cancelled" then
			endReason = "Cancelled"
		end
		if ownsVisual and visual then
			visual:Destroy()
		end
		if options.OnEnd then
			task.spawn(options.OnEnd, endReason)
		end
		endedSignal:Fire(endReason)
		endedSignal:DisconnectAll()
		hitSignal:DisconnectAll()
	end)

	handle.Position, handle.Velocity = position, velocity
	handle.Hit, handle.Ended = hitSignal, endedSignal
	return handle
end

return Projectile
