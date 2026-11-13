--!nonstrict
--[[
	Math.Motion
	Mouvements procéduraux : oscillations, orbites, ressorts, inertie.

	Oscillate(time, amplitude?, frequency?, phase?, offset?)   offset + amplitude·sin(2π·f·t + phase)
	Wave(kind, time, amplitude?, frequency?, phase?, offset?)  kind: "Sine"|"Cosine"|"Triangle"|"Square"|"Saw"
	Orbit(center, radius, angularSpeed, time, phase?, normal?) -> Vector3  (angularSpeed en rad/s)
	CircularMotion(center, radius, period, time, normal?)      -> Vector3  (un tour en `period` s)
	Spring.new(initial, options?) -> Spring   ressort amorti (number, Vector2, Vector3)
		options.Stiffness (défaut 120)  options.Mass (1)  options.DampingRatio (1 = critique)
		spring:Update(dt, target?) -> value   spring:Impulse(velocity)   spring:Reset(value)
		spring:IsSettled(epsilon?) -> boolean spring.Position / spring.Velocity / spring.Target
	SmoothDamp(current, target, velocity, smoothTime, dt) -> (newValue, newVelocity)   (type "inertie")
	Inertia(velocity, friction, dt) -> velocity amortie exponentiellement (indépendante du framerate)

	Exemple
		local spring = Math.Spring.new(Vector3.zero, { Stiffness = 200 })
		RunService.Heartbeat:Connect(function(dt) part.Position = spring:Update(dt, goal) end)
]]

local Geometry = require(script.Parent.Geometry)

local Motion = {}

function Motion.Oscillate(time: number, amplitude: number?, frequency: number?, phase: number?, offset: number?): number
	return (offset or 0) + (amplitude or 1) * math.sin(2 * math.pi * (frequency or 1) * time + (phase or 0))
end

function Motion.Wave(kind: string, time: number, amplitude: number?, frequency: number?, phase: number?, offset: number?): number
	local a = amplitude or 1
	local cycle = (frequency or 1) * time + (phase or 0) / (2 * math.pi)
	local fractional = cycle - math.floor(cycle) -- [0,1)
	local value: number

	if kind == "Sine" then
		value = math.sin(2 * math.pi * cycle)
	elseif kind == "Cosine" then
		value = math.cos(2 * math.pi * cycle)
	elseif kind == "Triangle" then
		value = 1 - 4 * math.abs(fractional - 0.5)
	elseif kind == "Square" then
		value = if fractional < 0.5 then 1 else -1
	elseif kind == "Saw" then
		value = 2 * fractional - 1
	else
		error(("Math.Wave : type d'onde inconnu '%s'"):format(tostring(kind)), 2)
	end

	return (offset or 0) + a * value
end

function Motion.Orbit(center: Vector3, radius: number, angularSpeed: number, time: number, phase: number?, normal: Vector3?): Vector3
	return Geometry.PointOnCircle(center, radius, (phase or 0) + angularSpeed * time, normal)
end

function Motion.CircularMotion(center: Vector3, radius: number, period: number, time: number, normal: Vector3?): Vector3
	assert(period ~= 0, "Math.CircularMotion : period ne peut pas être 0")
	return Geometry.PointOnCircle(center, radius, 2 * math.pi * time / period, normal)
end

-- Ressort ---------------------------------------------------------------

local Spring = {}
Spring.__index = Spring

local MAX_DT = 0.1
local SUBSTEP = 1 / 120

function Spring.new(initial: any, options: { Stiffness: number?, Mass: number?, DampingRatio: number? }?)
	local opts = options or {}
	local kind = typeof(initial)
	assert(
		kind == "number" or kind == "Vector2" or kind == "Vector3",
		"Math.Spring.new : type supporté = number, Vector2, Vector3"
	)

	local zero: any = if kind == "number" then 0 elseif kind == "Vector2" then Vector2.zero else Vector3.zero

	return setmetatable({
		Position = initial,
		Velocity = zero,
		Target = initial,
		_zero = zero,
		_stiffness = opts.Stiffness or 120,
		_mass = opts.Mass or 1,
		_ratio = opts.DampingRatio or 1,
	}, Spring)
end

function Spring:Update(dt: number, target: any?): any
	if target ~= nil then
		self.Target = target
	end

	dt = math.clamp(dt, 0, MAX_DT)
	if dt == 0 then
		return self.Position
	end

	local k, m = self._stiffness, self._mass
	local damping = 2 * self._ratio * math.sqrt(k * m)
	local steps = math.max(math.ceil(dt / SUBSTEP), 1)
	local h = dt / steps

	local position, velocity, goal = self.Position, self.Velocity, self.Target
	for _ = 1, steps do
		local acceleration = ((goal - position) * k - velocity * damping) / m
		velocity += acceleration * h
		position += velocity * h
	end

	self.Position, self.Velocity = position, velocity
	return position
end

function Spring:Impulse(velocity: any)
	self.Velocity += velocity
end

function Spring:Reset(value: any)
	self.Position = value
	self.Target = value
	self.Velocity = self._zero
end

function Spring:IsSettled(epsilon: number?): boolean
	local e = epsilon or 1e-3
	local delta = self.Target - self.Position
	local distance = if type(delta) == "number" then math.abs(delta) else delta.Magnitude
	local speed = if type(self.Velocity) == "number" then math.abs(self.Velocity) else self.Velocity.Magnitude
	return distance < e and speed < e
end

Motion.Spring = Spring

-- Inertie ---------------------------------------------------------------

--- SmoothDamp (même formulation que Unity). Fonctionne avec number, Vector2, Vector3.
function Motion.SmoothDamp(current: any, target: any, velocity: any, smoothTime: number, dt: number): (any, any)
	local time = math.max(smoothTime, 1e-4)
	local omega = 2 / time
	local x = omega * dt
	local decay = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)

	local change = current - target
	local temp = (velocity + change * omega) * dt
	local newVelocity = (velocity - temp * omega) * decay
	local output = target + (change + temp) * decay
	return output, newVelocity
end

function Motion.Inertia(velocity: any, friction: number, dt: number): any
	return velocity * math.exp(-friction * dt)
end

return Motion
