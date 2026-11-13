--!nonstrict
--[[
	Movement.Path
	Déplacements vers un point ou le long d'un chemin, à vitesse constante.

	MoveTo(target, position, options?) -> Tween handle     (moteur Core.Tween : natif quand possible)
		options : Duration (s)  ou  Speed (studs/s)   — défaut Duration 1
		          Easing (défaut "QuadInOut")  Delay  OnComplete
		position : Vector3 (ou BasePart / Model / Attachment dont on prend la position à l'appel)

	FollowPath(target, points, options?) -> handle
		points : liste (>= 2) de Vector3 / BasePart / Attachment
		options : Speed (studs/s, défaut 16)
		          Smooth (défaut true)         spline Catmull-Rom passant par tous les points (si >= 3 points)
		          Loop   false (défaut) | true (boucle fermée) | "PingPong" (aller-retour)
		          Face   false | true | "Yaw"   oriente `target` selon la direction (true = 3D, "Yaw" = horizontal)
		          Pause  secondes d'arrêt à chaque waypoint (défaut 0)
		          OnWaypoint(index)   OnComplete()   (OnComplete seulement si Loop = false)
		handle:GetProgress() -> 0..1 (distance parcourue / longueur totale)    handle:GetLength() -> studs

	Patrol(target, points, options?) -> handle     FollowPath en aller-retour, sans lissage, avec Pause configurable

	Exemple
		Core.Movement.FollowPath(npc, { a, b, c }, { Speed = 12, Face = "Yaw", Loop = "PingPong", Pause = 1 })
]]

local Tween = require(script.Parent.Parent.Tween)
local Driver = require(script.Parent.Driver)
local Util = require(script.Parent.Util)
local Geometry = require(script.Parent.Parent.Math.Geometry)

local Path = {}

local SAMPLES_PER_SEGMENT = 24

function Path.MoveTo(target: Instance, position: any, options: any?)
	if not Util.IsMovable(target) then
		error("Core.Movement.MoveTo : la cible doit être une BasePart ou un Model", 2)
	end
	local goal = Util.Resolve(position)

	local opts = options or {}
	local duration = opts.Duration
	if duration == nil then
		if opts.Speed then
			if type(opts.Speed) ~= "number" or opts.Speed <= 0 then
				error("Core.Movement.MoveTo : Speed doit être > 0", 2)
			end
			duration = (goal - Util.GetPosition(target)).Magnitude / opts.Speed
		else
			duration = 1
		end
	end

	local meta = Driver.MetaFrom(opts, "MoveTo")
	local tween
	local token = Driver.Claim(target, meta, function(reason)
		if tween then
			tween.Reason = reason
			tween:Cancel()
		end
	end)
	if not token then
		return Driver.RejectedHandle(target, meta)
	end

	tween = Tween(target, { Position = goal }, {
		Duration = duration,
		Easing = opts.Easing or "QuadInOut",
		Delay = opts.Delay,
		OnComplete = opts.OnComplete,
	})
	tween.Completed:Connect(function()
		Driver.Release(token)
	end)
	return tween
end

local function buildPath(points: { Vector3 }, smooth: boolean, closed: boolean)
	local n = #points
	local segments = if closed then n else n - 1
	local useSpline = smooth and n >= 3

	local function at(u: number): Vector3
		if useSpline then
			return Geometry.Spline(points, u, closed)
		end
		local scaled = math.clamp(u, 0, 1) * segments
		local i = math.min(math.floor(scaled), segments - 1)
		return points[i + 1]:Lerp(points[(i + 1) % n + 1], scaled - i)
	end

	local count = segments * SAMPLES_PER_SEGMENT
	local samples = table.create(count + 1)
	local cumulative = table.create(count + 1)
	samples[1] = at(0)
	cumulative[1] = 0
	for i = 1, count do
		samples[i + 1] = at(i / count)
		cumulative[i + 1] = cumulative[i] + (samples[i + 1] - samples[i]).Magnitude
	end

	local total = cumulative[count + 1]

	local function positionAt(distance: number): Vector3
		local d = math.clamp(distance, 0, total)
		local low, high = 1, count + 1
		while high - low > 1 do
			local mid = (low + high) // 2
			if cumulative[mid] <= d then
				low = mid
			else
				high = mid
			end
		end
		local span = cumulative[high] - cumulative[low]
		local t = if span > 1e-9 then (d - cumulative[low]) / span else 0
		return samples[low]:Lerp(samples[high], t)
	end

	-- Distances des waypoints (le point de fermeture d'une boucle n'est pas compté deux fois).
	local waypoints = {}
	for k = 1, n do
		waypoints[k] = cumulative[(k - 1) * SAMPLES_PER_SEGMENT + 1]
	end

	return positionAt, total, waypoints
end

function Path.FollowPath(target: Instance, rawPoints: { any }, options: any?)
	if not Util.IsMovable(target) then
		error("Core.Movement.FollowPath : la cible doit être une BasePart ou un Model", 2)
	end
	if type(rawPoints) ~= "table" or #rawPoints < 2 then
		error("Core.Movement.FollowPath : au moins 2 points requis", 2)
	end

	local opts = options or {}
	local speed = opts.Speed or 16
	if type(speed) ~= "number" or speed <= 0 then
		error("Core.Movement.FollowPath : Speed doit être > 0", 2)
	end
	local loop = opts.Loop or false
	if loop ~= false and loop ~= true and loop ~= "PingPong" then
		error("Core.Movement.FollowPath : Loop doit valoir false, true ou 'PingPong'", 2)
	end

	local points = {}
	for i, point in rawPoints do
		points[i] = Util.Resolve(point)
	end

	local smooth = opts.Smooth ~= false
	local positionAt, total, waypoints = buildPath(points, smooth, loop == true)
	if total < 1e-6 then
		error("Core.Movement.FollowPath : longueur du chemin nulle", 2)
	end

	local pause = opts.Pause or 0
	local distance, direction, pauseLeft = 0, 1, 0

	local function place(d: number)
		local position = positionAt(d)
		if opts.Face then
			local ahead = positionAt(d + direction * 0.5)
			local look = ahead - position
			if opts.Face == "Yaw" then
				look = Vector3.new(look.X, 0, look.Z)
			end
			if look.Magnitude > 1e-4 then
				Util.SetCFrame(target, CFrame.lookAt(position, position + look))
				return
			end
		end
		Util.SetPosition(target, position)
	end

	place(0)

	local handle
	handle = Driver.Run(target, function(dt)
		if pauseLeft > 0 then
			pauseLeft -= dt
			if pauseLeft > 0 then
				return false
			end
			dt = -pauseLeft
			pauseLeft = 0
		end

		local previous = distance
		distance += direction * speed * dt

		-- Waypoints franchis pendant ce pas.
		for index, at in waypoints do
			local crossed
			if direction > 0 then
				crossed = at > previous and at <= distance
			else
				crossed = at < previous and at >= distance
			end
			if crossed then
				if opts.OnWaypoint then
					task.spawn(opts.OnWaypoint, index)
				end
				if pause > 0 then
					distance = at
					pauseLeft = pause
					break
				end
			end
		end

		if direction > 0 and distance >= total then
			if loop == false then
				place(total)
				return true
			elseif loop == true then
				distance -= total
			else
				distance = math.max(total - (distance - total), 0)
				direction = -1
			end
		elseif direction < 0 and distance <= 0 then
			distance = math.min(-distance, total)
			direction = 1
		end

		place(distance)
		return false
	end, function(status)
		if status == "Completed" and opts.OnComplete then
			task.spawn(opts.OnComplete)
		end
	end, Driver.MetaFrom(opts, "FollowPath"))

	handle.GetProgress = function()
		return distance / total
	end
	handle.GetLength = function()
		return total
	end
	return handle
end

function Path.Patrol(target: Instance, points: { any }, options: any?)
	local opts = table.clone(options or {})
	if opts.Loop == nil then
		opts.Loop = "PingPong"
	end
	if opts.Smooth == nil then
		opts.Smooth = false
	end
	if opts.Pause == nil then
		opts.Pause = 0.5
	end
	return Path.FollowPath(target, points, opts)
end

return Path
