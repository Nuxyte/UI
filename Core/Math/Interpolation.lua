--!strict
--[[
	Math.Interpolation
	Lerp générique (number, Vector2, Vector3, Color3, CFrame, UDim, UDim2) et fonctions associées.

	Lerp(a, b, t)                 interpolation linéaire (t non borné)
	SmoothLerp(a, b, t)           lerp avec courbe SmoothStep (départ/arrivée doux)
	Damp(a, b, smoothing, dt)     lerp exponentiel INDÉPENDANT du framerate (pour caméras, suivi)
	InverseLerp(a, b, v)          position de v entre a et b (0..1 si dans l'intervalle)
	Remap(v, inMin, inMax, outMin, outMax, clamp?)
	Clamp(v, min, max)
	Normalize(v, min, max)        InverseLerp borné à [0,1]
	SmoothStep(edge0, edge1, x)   Hermite 3x²-2x³
	SmootherStep(edge0, edge1, x) Hermite d'ordre 5
	MoveTowards(current, target, maxDelta)  number ou Vector2/3
	Wrap(v, min, max)  PingPong(t, length)  Round(v, step)  Approximately(a, b, epsilon?)

	Exemple
		Math.Lerp(0, 100, 0.25)                         --> 25
		Math.Damp(current, target, 10, dt)               -- dans un Heartbeat
		Math.Remap(5, 0, 10, 100, 200)                   --> 150
]]

local Interpolation = {}

local function lerpNumber(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function Interpolation.Lerp(a: any, b: any, t: number): any
	local kind = typeof(a)
	if kind ~= typeof(b) then
		error(("Math.Lerp : types différents (%s / %s)"):format(kind, typeof(b)), 2)
	end

	if kind == "number" then
		return lerpNumber(a, b, t)
	elseif kind == "UDim" then
		return UDim.new(lerpNumber(a.Scale, b.Scale, t), lerpNumber(a.Offset, b.Offset, t))
	elseif kind == "Vector2" or kind == "Vector3" or kind == "Color3" or kind == "CFrame" or kind == "UDim2" then
		return a:Lerp(b, t)
	end

	error(("Math.Lerp : type non supporté (%s)"):format(kind), 2)
end

local Lerp = Interpolation.Lerp

function Interpolation.Clamp(v: number, min: number, max: number): number
	if min > max then
		min, max = max, min
	end
	return math.clamp(v, min, max)
end

function Interpolation.InverseLerp(a: number, b: number, v: number): number
	if a == b then
		return 0
	end
	return (v - a) / (b - a)
end

function Interpolation.Normalize(v: number, min: number, max: number): number
	return math.clamp(Interpolation.InverseLerp(min, max, v), 0, 1)
end

function Interpolation.Remap(v: number, inMin: number, inMax: number, outMin: number, outMax: number, clamp: boolean?): number
	local t = Interpolation.InverseLerp(inMin, inMax, v)
	if clamp then
		t = math.clamp(t, 0, 1)
	end
	return lerpNumber(outMin, outMax, t)
end

function Interpolation.SmoothStep(edge0: number, edge1: number, x: number): number
	local t = math.clamp(Interpolation.InverseLerp(edge0, edge1, x), 0, 1)
	return t * t * (3 - 2 * t)
end

function Interpolation.SmootherStep(edge0: number, edge1: number, x: number): number
	local t = math.clamp(Interpolation.InverseLerp(edge0, edge1, x), 0, 1)
	return t * t * t * (t * (t * 6 - 15) + 10)
end

function Interpolation.SmoothLerp(a: any, b: any, t: number): any
	local s = math.clamp(t, 0, 1)
	return Lerp(a, b, s * s * (3 - 2 * s))
end

--- Lerp exponentiel : `smoothing` plus grand = convergence plus rapide. Indépendant du framerate.
function Interpolation.Damp(a: any, b: any, smoothing: number, dt: number): any
	return Lerp(a, b, 1 - math.exp(-smoothing * dt))
end

function Interpolation.MoveTowards(current: any, target: any, maxDelta: number): any
	if type(current) == "number" then
		local delta = target - current
		if math.abs(delta) <= maxDelta then
			return target
		end
		return current + math.sign(delta) * maxDelta
	end

	local delta = target - current
	local distance = delta.Magnitude
	if distance <= maxDelta or distance == 0 then
		return target
	end
	return current + delta / distance * maxDelta
end

function Interpolation.Wrap(v: number, min: number, max: number): number
	local range = max - min
	if range == 0 then
		return min
	end
	return min + (v - min) % range
end

function Interpolation.PingPong(t: number, length: number): number
	if length == 0 then
		return 0
	end
	local wrapped = t % (length * 2)
	return length - math.abs(wrapped - length)
end

function Interpolation.Round(v: number, step: number?): number
	local s = step or 1
	if s == 0 then
		return v
	end
	return math.round(v / s) * s
end

function Interpolation.Approximately(a: number, b: number, epsilon: number?): boolean
	return math.abs(a - b) <= (epsilon or 1e-5)
end

return Interpolation
