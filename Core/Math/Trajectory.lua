--!strict
--[[
	Math.Trajectory
	Balistique : vitesses de lancement, positions prédites, durées, gravité.
	Convention : la gravité est une accélération POSITIVE (stud/s²) dirigée vers -Y.
	Par défaut : Config.Math.Gravity, sinon workspace.Gravity (196.2).

	GetGravity(g?)                                    -> number
	GravityFromJump(height, timeToApex)               -> g tel qu'un saut de `height` dure `timeToApex` jusqu'au sommet
	JumpVelocity(height, g?)                          -> vitesse verticale pour atteindre `height`

	CalculateLaunchVelocity(start, target, arcHeight?, g?) -> (velocity, flightTime)
		L'objet atteint `target` en passant par un sommet situé `arcHeight` studs AU-DESSUS du point
		le plus haut entre départ et cible (défaut 10). Toujours solvable.
	CalculateLaunchVelocityByTime(start, target, time, g?) -> (velocity, time)
	CalculateLaunchVelocityBySpeed(start, target, speed, g?, highArc?) -> (velocity, time) | nil
		nil si la cible est hors de portée à cette vitesse.

	PositionAt(start, velocity, t, g?)   VelocityAt(velocity, t, g?)
	FlightTime(startY, targetY, verticalVelocity, g?) -> number | nil
	ApexHeight(verticalVelocity, g?)     -> hauteur du sommet au-dessus du départ
	ApexTime(verticalVelocity, g?)       -> temps pour atteindre le sommet
	Points(start, velocity, steps, duration, g?) -> { Vector3 }    (pour visualiser / suivre une trajectoire)
	TravelTime(a, b, speed)              -> durée d'un déplacement rectiligne uniforme
	TravelTimeAccelerated(distance, acceleration, initialSpeed?) -> durée

	Exemple
		local v, t = Math.CalculateLaunchVelocity(startPos, targetPos, 15)
		part.AssemblyLinearVelocity = v
]]

local Trajectory = {}

local DEFAULT_GRAVITY = 196.2

-- Config est facultatif : le module reste utilisable seul. Résolu une seule fois.
local configResolved = false
local sharedConfig: any = nil

local function resolveConfig(): any
	if not configResolved then
		configResolved = true
		local parent = script.Parent and script.Parent.Parent
		local configModule = parent and parent:FindFirstChild("Config")
		if configModule and configModule:IsA("ModuleScript") then
			local ok, config = pcall(require, configModule)
			if ok then
				sharedConfig = config
			end
		end
	end
	return sharedConfig
end

function Trajectory.GetGravity(g: number?): number
	if g then
		return g
	end

	local config = resolveConfig()
	if type(config) == "table" and type(config.Math) == "table" and type(config.Math.Gravity) == "number" then
		return config.Math.Gravity
	end

	local ok, gravity = pcall(function()
		return workspace.Gravity
	end)
	if ok and type(gravity) == "number" then
		return gravity
	end
	return DEFAULT_GRAVITY
end

local getGravity = Trajectory.GetGravity

function Trajectory.GravityFromJump(height: number, timeToApex: number): number
	assert(height > 0 and timeToApex > 0, "Math.GravityFromJump : height et timeToApex doivent être > 0")
	return 2 * height / (timeToApex * timeToApex)
end

function Trajectory.JumpVelocity(height: number, g: number?): number
	assert(height >= 0, "Math.JumpVelocity : height doit être >= 0")
	return math.sqrt(2 * getGravity(g) * height)
end

function Trajectory.CalculateLaunchVelocity(start: Vector3, target: Vector3, arcHeight: number?, g: number?): (Vector3, number)
	local gravity = getGravity(g)
	local height = math.max(arcHeight or 10, 1e-3)

	local apexY = math.max(start.Y, target.Y) + height
	local vy = math.sqrt(2 * gravity * (apexY - start.Y))
	local timeUp = vy / gravity
	local timeDown = math.sqrt(2 * (apexY - target.Y) / gravity)
	local total = timeUp + timeDown

	local dx = (target.X - start.X) / total
	local dz = (target.Z - start.Z) / total
	return Vector3.new(dx, vy, dz), total
end

function Trajectory.CalculateLaunchVelocityByTime(start: Vector3, target: Vector3, time: number, g: number?): (Vector3, number)
	assert(time > 0, "Math.CalculateLaunchVelocityByTime : time doit être > 0")
	local gravity = getGravity(g)
	local delta = target - start
	return Vector3.new(delta.X / time, delta.Y / time + 0.5 * gravity * time, delta.Z / time), time
end

function Trajectory.CalculateLaunchVelocityBySpeed(
	start: Vector3,
	target: Vector3,
	speed: number,
	g: number?,
	highArc: boolean?
): (Vector3?, number?)
	local gravity = getGravity(g)
	local delta = target - start
	local flat = Vector3.new(delta.X, 0, delta.Z)
	local dx = flat.Magnitude
	local dy = delta.Y

	if dx < 1e-4 then
		-- Cible à la verticale.
		if speed * speed >= 2 * gravity * dy then
			local vy = speed
			local t = (vy + math.sqrt(math.max(vy * vy - 2 * gravity * dy, 0))) / gravity
			return Vector3.new(0, vy, 0), t
		end
		return nil, nil
	end

	local s2 = speed * speed
	local discriminant = s2 * s2 - gravity * (gravity * dx * dx + 2 * dy * s2)
	if discriminant < 0 then
		return nil, nil
	end

	local root = math.sqrt(discriminant)
	local tanTheta = ((if highArc then s2 + root else s2 - root)) / (gravity * dx)
	local cosTheta = 1 / math.sqrt(1 + tanTheta * tanTheta)
	local sinTheta = tanTheta * cosTheta

	local direction = flat / dx
	local velocity = direction * (speed * cosTheta) + Vector3.new(0, speed * sinTheta, 0)
	return velocity, dx / (speed * cosTheta)
end

function Trajectory.PositionAt(start: Vector3, velocity: Vector3, t: number, g: number?): Vector3
	return start + velocity * t + Vector3.new(0, -0.5 * getGravity(g) * t * t, 0)
end

function Trajectory.VelocityAt(velocity: Vector3, t: number, g: number?): Vector3
	return velocity + Vector3.new(0, -getGravity(g) * t, 0)
end

--- Temps pour atteindre l'altitude `targetY` en descente (ou montée si atteinte), nil si jamais atteinte.
function Trajectory.FlightTime(startY: number, targetY: number, verticalVelocity: number, g: number?): number?
	local gravity = getGravity(g)
	local discriminant = verticalVelocity * verticalVelocity + 2 * gravity * (startY - targetY)
	if discriminant < 0 then
		return nil
	end
	return (verticalVelocity + math.sqrt(discriminant)) / gravity
end

function Trajectory.ApexHeight(verticalVelocity: number, g: number?): number
	if verticalVelocity <= 0 then
		return 0
	end
	return verticalVelocity * verticalVelocity / (2 * getGravity(g))
end

function Trajectory.ApexTime(verticalVelocity: number, g: number?): number
	return math.max(verticalVelocity, 0) / getGravity(g)
end

function Trajectory.Points(start: Vector3, velocity: Vector3, steps: number, duration: number, g: number?): { Vector3 }
	assert(steps >= 1, "Math.Points : steps doit être >= 1")
	local gravity = getGravity(g)
	local points = table.create(steps + 1)
	for i = 0, steps do
		points[i + 1] = Trajectory.PositionAt(start, velocity, duration * i / steps, gravity)
	end
	return points
end

function Trajectory.TravelTime(a: Vector3, b: Vector3, speed: number): number
	assert(speed > 0, "Math.TravelTime : speed doit être > 0")
	return (b - a).Magnitude / speed
end

--- d = v0·t + ½·a·t²  résolu pour t.
function Trajectory.TravelTimeAccelerated(distance: number, acceleration: number, initialSpeed: number?): number
	local v0 = initialSpeed or 0
	if acceleration == 0 then
		assert(v0 > 0, "Math.TravelTimeAccelerated : vitesse et accélération nulles")
		return distance / v0
	end
	local discriminant = v0 * v0 + 2 * acceleration * distance
	assert(discriminant >= 0, "Math.TravelTimeAccelerated : distance inatteignable")
	return (-v0 + math.sqrt(discriminant)) / acceleration
end

return Trajectory
