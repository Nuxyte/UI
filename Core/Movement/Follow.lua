--!nonstrict
--[[
	Movement.Follow
	Mouvements continus : suivi de cible, orbite, flottement.

	Follow(target, subject, options?) -> handle
		subject : BasePart | Model | Attachment | Vector3 | function() -> Vector3  (réévalué à chaque frame)
		options : Smoothing (défaut 6, plus grand = plus réactif ; indépendant du framerate)
		          Offset (Vector3, défaut 0)          décalage monde ajouté à la cible
		          StopDistance (défaut 0)             reste à cette distance de la cible
		          MaxSpeed (studs/s, défaut illimité)
		          Face (bool)                         oriente `target` vers sa direction de déplacement (axe Y seulement)
		Ne se termine jamais seul : utilisez handle:Cancel().

	Orbit(target, center, options?) -> handle
		options : Radius (10)  Speed (rad/s, 1 ; négatif = sens inverse)  Height (0)  Phase (0)
		          Normal (axe de rotation, défaut Y)  Face (bool, regarde le centre)  Duration (s, sinon infini)
		          OnComplete

	Hover(target, options?) -> handle         (flottement / lévitation sinusoïdale)
		options : Amplitude (1)  Frequency (0.5 Hz)  Axis (Vector3, défaut Y)  Spin (degrés/s autour de Y, 0)
		          Duration  RestoreOnStop (true : revient à la position de départ à l'arrêt)  OnComplete

	Exemple
		local follow = Core.Movement.Follow(pet, player.Character.HumanoidRootPart, { Offset = Vector3.new(3, 2, 0), Face = true })
		follow:Cancel()
]]

local Driver = require(script.Parent.Driver)
local Util = require(script.Parent.Util)
local Interpolation = require(script.Parent.Parent.Math.Interpolation)
local Geometry = require(script.Parent.Parent.Math.Geometry)

local Follow = {}

local function checkTarget(target: any, fn: string)
	if not Util.IsMovable(target) then
		error(("Core.Movement.%s : la cible doit être une BasePart ou un Model"):format(fn), 3)
	end
end

local function yawLook(from: Vector3, direction: Vector3): CFrame
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 1e-4 then
		return CFrame.new(from)
	end
	return CFrame.lookAt(from, from + flat)
end

function Follow.Follow(target: Instance, subject: any, options: any?)
	checkTarget(target, "Follow")
	Util.Resolve(subject) -- valide `subject` tout de suite (erreur claire à l'appel, pas dans la frame)

	local opts = options or {}
	local smoothing = opts.Smoothing or 6
	local offset = opts.Offset or Vector3.zero
	local stopDistance = opts.StopDistance or 0
	local maxSpeed = opts.MaxSpeed or math.huge

	return Driver.Run(target, function(dt)
		local position = Util.GetPosition(target)
		local goal = Util.Resolve(subject) + offset

		if stopDistance > 0 then
			local toGoal = goal - position
			local distance = toGoal.Magnitude
			if distance <= stopDistance then
				return
			end
			goal = goal - toGoal.Unit * stopDistance
		end

		local newPosition = Interpolation.Damp(position, goal, smoothing, dt)
		local step = newPosition - position
		local limit = maxSpeed * dt
		if step.Magnitude > limit then
			newPosition = position + step.Unit * limit
			step = newPosition - position
		end

		if opts.Face and step.Magnitude > 1e-4 then
			Util.SetCFrame(target, yawLook(newPosition, step))
		else
			Util.SetPosition(target, newPosition)
		end
	end, nil, Driver.MetaFrom(opts, "Follow"))
end

function Follow.Orbit(target: Instance, center: any, options: any?)
	checkTarget(target, "Orbit")
	Util.Resolve(center)

	local opts = options or {}
	local radius = opts.Radius or 10
	local speed = opts.Speed or 1
	local height = opts.Height or 0
	local angle = opts.Phase or 0
	local normal = opts.Normal
	local duration = opts.Duration
	local elapsed = 0

	return Driver.Run(target, function(dt)
		angle += speed * dt
		elapsed += dt

		local centerPosition = Util.Resolve(center)
		local up = if normal then normal.Unit else Vector3.yAxis
		local position = Geometry.PointOnCircle(centerPosition + up * height, radius, angle, normal)

		if opts.Face then
			Util.SetCFrame(target, CFrame.lookAt(position, centerPosition))
		else
			Util.SetPosition(target, position)
		end

		return duration ~= nil and elapsed >= duration
	end, function(status)
		if status == "Completed" and opts.OnComplete then
			task.spawn(opts.OnComplete)
		end
	end, Driver.MetaFrom(opts, "Orbit"))
end

function Follow.Hover(target: Instance, options: any?)
	checkTarget(target, "Hover")

	local opts = options or {}
	local amplitude = opts.Amplitude or 1
	local frequency = opts.Frequency or 0.5
	local axis = opts.Axis or Vector3.yAxis
	local spin = math.rad(opts.Spin or 0)
	local duration = opts.Duration
	local restore = opts.RestoreOnStop ~= false

	local startCFrame = Util.GetCFrame(target)
	local basePosition = startCFrame.Position
	local yaw = 0
	local elapsed = 0

	return Driver.Run(target, function(dt)
		elapsed += dt
		yaw += spin * dt

		local offset = axis * (amplitude * math.sin(2 * math.pi * frequency * elapsed))
		local rotation = startCFrame.Rotation
		if spin ~= 0 then
			rotation = CFrame.Angles(0, yaw, 0) * rotation
		end
		Util.SetCFrame(target, CFrame.new(basePosition + offset) * rotation)

		return duration ~= nil and elapsed >= duration
	end, function(status)
		if restore then
			Util.SetPosition(target, basePosition)
		end
		if status == "Completed" and opts.OnComplete then
			task.spawn(opts.OnComplete)
		end
	end, Driver.MetaFrom(opts, "Hover"))
end

return Follow
