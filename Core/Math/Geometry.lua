--!strict
--[[
	Math.Geometry
	Géométrie, intersections, courbes de Bézier et chemins.

	Vecteurs
		Distance(a, b)  HorizontalDistance(a, b)  AngleBetween(a, b)  SignedAngle(a, b, axis)
		Project(v, onto)  ProjectOnPlane(v, normal)  Reflect(v, normal)
		DirectionTo(from, to)  LookRotation(from, to, up?)  RotateTowards(cf, targetPos, alpha)
	Intersections
		RayPlane(origin, dir, planePoint, planeNormal)  -> Vector3?, t?
		RaySphere(origin, dir, center, radius)          -> Vector3?, t?   (premier point d'entrée)
		SegmentIntersection2D(a1, a2, b1, b2)           -> Vector2?       (plan XZ si Vector3)
		ClosestPointOnSegment(point, a, b)              -> Vector3
	Points
		PointOnLine(a, b, t)  PointsOnLine(a, b, count)
		PointOnCircle(center, radius, angle, normal?)   -> Vector3  (angle en radians)
		PointsOnCircle(center, radius, count, normal?, startAngle?) -> { Vector3 }
	Courbes
		QuadraticBezier(p0, p1, p2, t)  CubicBezier(p0, p1, p2, p3, t)  BezierTangent(...)
		Bezier(points, t)               (de Casteljau, n points de contrôle)
		CatmullRom(p0, p1, p2, p3, t)   (passe par p1 -> p2)
		Spline(points, t, closed?)      (Catmull-Rom sur toute la liste, t dans [0,1])
		SamplePath(fn, count)           -> { points } où fn(t in [0,1]) -> point
		PathLength(fn, samples?)        -> longueur approchée

	Exemple
		local p = Math.QuadraticBezier(a, control, b, 0.5)
		for _, pos in Math.PointsOnCircle(center, 10, 8) do ... end
]]

local Geometry = {}

function Geometry.Distance(a: any, b: any): number
	return (a - b).Magnitude
end

function Geometry.HorizontalDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

--- Angle non signé en radians, dans [0, π].
function Geometry.AngleBetween(a: Vector3, b: Vector3): number
	local magnitude = a.Magnitude * b.Magnitude
	if magnitude == 0 then
		return 0
	end
	return math.acos(math.clamp(a:Dot(b) / magnitude, -1, 1))
end

--- Angle signé en radians, dans [-π, π], autour de `axis`.
function Geometry.SignedAngle(a: Vector3, b: Vector3, axis: Vector3): number
	return math.atan2(axis.Unit:Dot(a:Cross(b)), a:Dot(b))
end

function Geometry.Project(v: Vector3, onto: Vector3): Vector3
	local denominator = onto:Dot(onto)
	if denominator == 0 then
		return Vector3.zero
	end
	return onto * (v:Dot(onto) / denominator)
end

function Geometry.ProjectOnPlane(v: Vector3, normal: Vector3): Vector3
	return v - Geometry.Project(v, normal)
end

function Geometry.Reflect(v: Vector3, normal: Vector3): Vector3
	local n = normal.Unit
	return v - 2 * v:Dot(n) * n
end

function Geometry.DirectionTo(from: Vector3, to: Vector3): Vector3
	local delta = to - from
	if delta.Magnitude < 1e-9 then
		return Vector3.zero
	end
	return delta.Unit
end

function Geometry.LookRotation(from: Vector3, to: Vector3, up: Vector3?): CFrame
	if (to - from).Magnitude < 1e-9 then
		return CFrame.new(from)
	end
	return CFrame.lookAt(from, to, up or Vector3.yAxis)
end

--- Fait pivoter `cf` vers `targetPos` ; alpha ∈ [0,1] (1 = regarde exactement la cible).
function Geometry.RotateTowards(cf: CFrame, targetPos: Vector3, alpha: number): CFrame
	if (targetPos - cf.Position).Magnitude < 1e-9 then
		return cf
	end
	return cf:Lerp(CFrame.lookAt(cf.Position, targetPos), math.clamp(alpha, 0, 1))
end

function Geometry.RayPlane(origin: Vector3, direction: Vector3, planePoint: Vector3, planeNormal: Vector3): (Vector3?, number?)
	local denominator = planeNormal:Dot(direction)
	if math.abs(denominator) < 1e-9 then
		return nil, nil -- parallèle
	end
	local t = planeNormal:Dot(planePoint - origin) / denominator
	if t < 0 then
		return nil, nil
	end
	return origin + direction * t, t
end

function Geometry.RaySphere(origin: Vector3, direction: Vector3, center: Vector3, radius: number): (Vector3?, number?)
	local oc = origin - center
	local a = direction:Dot(direction)
	local b = 2 * oc:Dot(direction)
	local c = oc:Dot(oc) - radius * radius
	local discriminant = b * b - 4 * a * c
	if a == 0 or discriminant < 0 then
		return nil, nil
	end

	local root = math.sqrt(discriminant)
	local t = (-b - root) / (2 * a)
	if t < 0 then
		t = (-b + root) / (2 * a) -- origine à l'intérieur de la sphère
	end
	if t < 0 then
		return nil, nil
	end
	return origin + direction * t, t
end

--- Intersection de deux segments dans le plan (Vector2, ou Vector3 projeté sur XZ).
function Geometry.SegmentIntersection2D(a1: any, a2: any, b1: any, b2: any): Vector2?
	local function toVec2(v: any): Vector2
		if typeof(v) == "Vector3" then
			return Vector2.new(v.X, v.Z)
		end
		return v
	end

	local p, p2, q, q2 = toVec2(a1), toVec2(a2), toVec2(b1), toVec2(b2)
	local r = p2 - p
	local s = q2 - q
	local denominator = r.X * s.Y - r.Y * s.X
	if math.abs(denominator) < 1e-9 then
		return nil -- parallèles ou colinéaires
	end

	local qp = q - p
	local t = (qp.X * s.Y - qp.Y * s.X) / denominator
	local u = (qp.X * r.Y - qp.Y * r.X) / denominator
	if t < 0 or t > 1 or u < 0 or u > 1 then
		return nil
	end
	return p + r * t
end

function Geometry.ClosestPointOnSegment(point: Vector3, a: Vector3, b: Vector3): Vector3
	local ab = b - a
	local lengthSquared = ab:Dot(ab)
	if lengthSquared == 0 then
		return a
	end
	local t = math.clamp((point - a):Dot(ab) / lengthSquared, 0, 1)
	return a + ab * t
end

function Geometry.PointOnLine(a: any, b: any, t: number): any
	return a + (b - a) * t
end

function Geometry.PointsOnLine(a: any, b: any, count: number): { any }
	assert(count >= 2, "Math.PointsOnLine : count doit être >= 2")
	local points = table.create(count)
	for i = 1, count do
		points[i] = a + (b - a) * ((i - 1) / (count - 1))
	end
	return points
end

-- Base orthonormée (right, forward) du plan de normale `normal`.
local function planeBasis(normal: Vector3?): (Vector3, Vector3)
	if normal == nil then
		return Vector3.xAxis, Vector3.zAxis
	end
	local n = normal.Unit
	local reference = if math.abs(n.Y) < 0.99 then Vector3.yAxis else Vector3.xAxis
	local right = n:Cross(reference).Unit
	local forward = n:Cross(right)
	return right, forward
end

--- Point du cercle de centre `center` et rayon `radius` à l'angle `angle` (radians).
--- `normal` : normale du plan du cercle (défaut Y = cercle horizontal).
function Geometry.PointOnCircle(center: Vector3, radius: number, angle: number, normal: Vector3?): Vector3
	local right, forward = planeBasis(normal)
	return center + right * (math.cos(angle) * radius) + forward * (math.sin(angle) * radius)
end

function Geometry.PointsOnCircle(center: Vector3, radius: number, count: number, normal: Vector3?, startAngle: number?): { Vector3 }
	assert(count >= 1, "Math.PointsOnCircle : count doit être >= 1")
	local points = table.create(count)
	local offset = startAngle or 0
	for i = 1, count do
		points[i] = Geometry.PointOnCircle(center, radius, offset + (i - 1) / count * 2 * math.pi, normal)
	end
	return points
end

function Geometry.QuadraticBezier(p0: any, p1: any, p2: any, t: number): any
	local u = 1 - t
	return p0 * (u * u) + p1 * (2 * u * t) + p2 * (t * t)
end

function Geometry.CubicBezier(p0: any, p1: any, p2: any, p3: any, t: number): any
	local u = 1 - t
	return p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
end

--- Tangente (non normalisée) d'une Bézier cubique.
function Geometry.BezierTangent(p0: any, p1: any, p2: any, p3: any, t: number): any
	local u = 1 - t
	return (p1 - p0) * (3 * u * u) + (p2 - p1) * (6 * u * t) + (p3 - p2) * (3 * t * t)
end

--- Bézier de degré quelconque (algorithme de de Casteljau).
function Geometry.Bezier(points: { any }, t: number): any
	local n = #points
	assert(n >= 2, "Math.Bezier : au moins 2 points de contrôle")
	local work = table.clone(points)
	for level = n - 1, 1, -1 do
		for i = 1, level do
			work[i] = work[i] + (work[i + 1] - work[i]) * t
		end
	end
	return work[1]
end

function Geometry.CatmullRom(p0: any, p1: any, p2: any, p3: any, t: number): any
	local t2 = t * t
	local t3 = t2 * t
	return (
		p1 * 2
		+ (p2 - p0) * t
		+ (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2
		+ (p1 * 3 - p0 - p2 * 3 + p3) * t3
	) * 0.5
end

--- Spline passant par tous les points. `t` ∈ [0,1] sur l'ensemble du chemin.
function Geometry.Spline(points: { any }, t: number, closed: boolean?): any
	local n = #points
	assert(n >= 2, "Math.Spline : au moins 2 points")

	local segments = if closed then n else n - 1
	local scaled = math.clamp(t, 0, 1) * segments
	local index = math.min(math.floor(scaled), segments - 1)
	local localT = scaled - index

	local function at(i: number): any
		if closed then
			return points[(i - 1) % n + 1]
		end
		return points[math.clamp(i, 1, n)]
	end

	return Geometry.CatmullRom(at(index), at(index + 1), at(index + 2), at(index + 3), localT)
end

function Geometry.SamplePath(fn: (number) -> any, count: number): { any }
	assert(count >= 2, "Math.SamplePath : count doit être >= 2")
	local points = table.create(count)
	for i = 1, count do
		points[i] = fn((i - 1) / (count - 1))
	end
	return points
end

function Geometry.PathLength(fn: (number) -> any, samples: number?): number
	local count = samples or 32
	local length = 0
	local previous = fn(0)
	for i = 1, count do
		local current = fn(i / count)
		length += (current - previous).Magnitude
		previous = current
	end
	return length
end

return Geometry
