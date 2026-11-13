--!nonstrict
--[[
	Physics.Cast
	Raycast / Spherecast / Blockcast simplifiés et requêtes de zone.

	Options communes (toutes facultatives) :
		Ignore {Instance}   exclus (et leurs descendants)        Whitelist {Instance}  seuls ceux-là (prioritaire sur Ignore)
		CollisionGroup "nom"   IgnoreWater (défaut true)   RespectCanCollide (bool)

	Raycast(origin, direction, options?)            -> RaycastResult | nil
		direction : Vector3 dont la LONGUEUR est la portée ; options.Distance impose la portée (direction normalisée)
	Spherecast(origin, radius, direction, options?) -> RaycastResult | nil
	Blockcast(cframe, size, direction, options?)    -> RaycastResult | nil
	RaycastBetween(a, b, options?)                  -> RaycastResult | nil     (a -> b)
	HasLineOfSight(a, b, options?)                  -> boolean                 (rien entre a et b)
	GetPartsInRadius(center, radius, options?)     -> { BasePart }       options.MaxParts
	GetPartsInBox(cframe, size, options?)           -> { BasePart }
	GetCharactersInRadius(center, radius, options?) -> { Model }          Models avec Humanoid, triés par distance

	SetHook(fn | nil)   fn(kind, origin, direction, result, extra) appelé à chaque cast (utilisé par Debug pour dessiner)

	Exemple
		local hit = Core.Physics.Raycast(origin, direction, { Distance = 100, Ignore = { character } })
		if hit then print(hit.Instance, hit.Position) end
]]

local Cast = {}

local hook = nil

function Cast.SetHook(fn: any)
	hook = fn
end

local function raycastParams(options: any?)
	local params = RaycastParams.new()
	local opts = options or {}
	if opts.Whitelist then
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = opts.Whitelist
	else
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = opts.Ignore or {}
	end
	params.IgnoreWater = opts.IgnoreWater ~= false
	if opts.RespectCanCollide ~= nil then
		params.RespectCanCollide = opts.RespectCanCollide
	end
	if opts.CollisionGroup then
		params.CollisionGroup = opts.CollisionGroup
	end
	return params
end

local function overlapParams(options: any?)
	local params = OverlapParams.new()
	local opts = options or {}
	if opts.Whitelist then
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = opts.Whitelist
	else
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = opts.Ignore or {}
	end
	if opts.MaxParts then
		params.MaxParts = opts.MaxParts
	end
	if opts.CollisionGroup then
		params.CollisionGroup = opts.CollisionGroup
	end
	return params
end

local function resolveDirection(direction: Vector3, options: any?): Vector3
	if options and options.Distance then
		if direction.Magnitude < 1e-9 then
			error("Core.Physics : direction nulle", 3)
		end
		return direction.Unit * options.Distance
	end
	return direction
end

local function check(origin: any, direction: any, fn: string)
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		error(("Core.Physics.%s : origin et direction doivent être des Vector3"):format(fn), 3)
	end
end

function Cast.Raycast(origin: Vector3, direction: Vector3, options: any?)
	check(origin, direction, "Raycast")
	local vector = resolveDirection(direction, options)
	local result = workspace:Raycast(origin, vector, raycastParams(options))
	if hook then
		hook("Ray", origin, vector, result, options)
	end
	return result
end

function Cast.Spherecast(origin: Vector3, radius: number, direction: Vector3, options: any?)
	check(origin, direction, "Spherecast")
	if type(radius) ~= "number" or radius <= 0 then
		error("Core.Physics.Spherecast : radius doit être > 0", 2)
	end
	local vector = resolveDirection(direction, options)
	local result = workspace:Spherecast(origin, radius, vector, raycastParams(options))
	if hook then
		hook("Sphere", origin, vector, result, { Radius = radius })
	end
	return result
end

function Cast.Blockcast(cframe: CFrame, size: Vector3, direction: Vector3, options: any?)
	if typeof(cframe) ~= "CFrame" or typeof(size) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		error("Core.Physics.Blockcast : (CFrame, Vector3 size, Vector3 direction) attendus", 2)
	end
	local vector = resolveDirection(direction, options)
	local result = workspace:Blockcast(cframe, size, vector, raycastParams(options))
	if hook then
		hook("Block", cframe.Position, vector, result, { Size = size })
	end
	return result
end

function Cast.RaycastBetween(a: Vector3, b: Vector3, options: any?)
	return Cast.Raycast(a, b - a, { Ignore = options and options.Ignore, Whitelist = options and options.Whitelist, CollisionGroup = options and options.CollisionGroup, IgnoreWater = options and options.IgnoreWater })
end

function Cast.HasLineOfSight(a: Vector3, b: Vector3, options: any?): boolean
	return Cast.RaycastBetween(a, b, options) == nil
end

function Cast.GetPartsInRadius(center: Vector3, radius: number, options: any?): { BasePart }
	if typeof(center) ~= "Vector3" or type(radius) ~= "number" or radius <= 0 then
		error("Core.Physics.GetPartsInRadius : (Vector3 center, number radius > 0)", 2)
	end
	local parts = workspace:GetPartBoundsInRadius(center, radius, overlapParams(options))
	if hook then
		hook("Overlap", center, Vector3.zero, parts, { Radius = radius })
	end
	return parts
end

function Cast.GetPartsInBox(cframe: CFrame, size: Vector3, options: any?): { BasePart }
	if typeof(cframe) ~= "CFrame" or typeof(size) ~= "Vector3" then
		error("Core.Physics.GetPartsInBox : (CFrame, Vector3 size)", 2)
	end
	local parts = workspace:GetPartBoundsInBox(cframe, size, overlapParams(options))
	if hook then
		hook("OverlapBox", cframe.Position, Vector3.zero, parts, { Size = size, CFrame = cframe })
	end
	return parts
end

local function charactersFromParts(parts: { BasePart }, center: Vector3): { Model }
	local seen, entries = {}, {}
	for _, part in parts do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and not seen[model] and model:FindFirstChildOfClass("Humanoid") then
			seen[model] = true
			table.insert(entries, { model = model, distance = (model:GetPivot().Position - center).Magnitude })
		end
	end
	table.sort(entries, function(a, b)
		return a.distance < b.distance
	end)
	local models = {}
	for i, entry in entries do
		models[i] = entry.model
	end
	return models
end

Cast.CharactersFromParts = charactersFromParts

function Cast.GetCharactersInRadius(center: Vector3, radius: number, options: any?): { Model }
	return charactersFromParts(Cast.GetPartsInRadius(center, radius, options), center)
end

return Cast
