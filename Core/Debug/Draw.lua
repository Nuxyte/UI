--!nonstrict
--[[
	Debug.Line / Point / Sphere / Box / Arrow / Path / Text : visualisations 3D temporaires (HandleAdornments).
	Les tracés ne sont dessinés que lorsque le mode debug est actif (Debug.SetEnabled(true) / Config.Debug) :
	le code de visualisation peut donc rester en place en production sans coût (les appels retournent nil).

	options communes : Color (Color3)   Duration (secondes, défaut Config.DebugTools.DrawLifetime ; math.huge = permanent)
	                   Transparency (0)   AlwaysOnTop (true)
	Debug.Line(a, b, options?)                    Thickness (0.1)
	Debug.Point(position, options?)               Size (0.5 : rayon)
	Debug.Sphere(center, radius, options?)        Transparency par défaut 0.7
	Debug.Box(cframe | position, size, options?)  Transparency par défaut 0.7
	Debug.Arrow(origin, vector, options?)         flèche dont la longueur est celle du vecteur
	Debug.Path(points, options?)                  segments + points
	Debug.Text(position, text, options?)          étiquette flottante (Size 14)
	Debug.Clear()          Debug.DrawCount() -> number     (plafond Config.DebugTools.MaxDrawings : les plus anciens disparaissent)
	Debug.SetEnabled(bool)   Debug.IsEnabled()   Debug.ShowCasts(bool)   (visualise les Core.Physics.Raycast & co.)
	Chaque fonction de tracé retourne un handle { Remove = function } (ou nil si le debug est désactivé).
]]

local Config = require(script.Parent.Parent.Config)

local Draw = {}

local drawings = {} -- ordre d'apparition : { instance, ... }
local folder: Folder? = nil
local carrierCount = 0

local function getFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local existing = workspace:FindFirstChild(Config.DebugTools.Folder)
	if existing then
		folder = existing
	else
		local created = Instance.new("Folder")
		created.Name = Config.DebugTools.Folder
		created.Parent = workspace
		folder = created
	end
	return folder
end

local function remove(instance: Instance)
	local index = table.find(drawings, instance)
	if index then
		table.remove(drawings, index)
	end
	instance:Destroy()
end

local function register(instance: Instance, options: any?)
	local duration = (options and options.Duration) or Config.DebugTools.DrawLifetime
	instance.Parent = getFolder()
	table.insert(drawings, instance)

	while #drawings > Config.DebugTools.MaxDrawings do
		remove(drawings[1])
	end
	if duration ~= math.huge then
		task.delay(duration, function()
			if table.find(drawings, instance) then
				remove(instance)
			end
		end)
	end
	return {
		Remove = function()
			if table.find(drawings, instance) then
				remove(instance)
			end
		end,
		Instance = instance,
	}
end

local function adornment(className: string, options: any?, defaultTransparency: number?): any
	local adorn = Instance.new(className)
	adorn.Adornee = workspace.Terrain
	adorn.Color3 = (options and options.Color) or Color3.new(1, 0.2, 0.2)
	adorn.Transparency = if options and options.Transparency ~= nil then options.Transparency else (defaultTransparency or 0)
	adorn.AlwaysOnTop = not (options and options.AlwaysOnTop == false)
	adorn.ZIndex = 1
	return adorn
end

function Draw.IsEnabled(): boolean
	return Config.Debug == true
end

local castHookActive = false

local function installCastHook()
	local Cast = require(script.Parent.Parent.Physics.Cast)
	Cast.SetHook(function(kind: string, origin: Vector3, vector: Vector3, result: any, extra: any)
		if not Config.Debug then
			return
		end
		if kind == "Ray" or kind == "Sphere" or kind == "Block" then
			local hit = result ~= nil
			local finish = if hit then result.Position else origin + vector
			Draw.Line(origin, finish, { Color = if hit then Color3.new(1, 0.2, 0.2) else Color3.new(0.2, 1, 0.2), Duration = 0.5 })
			if hit then
				Draw.Point(finish, { Color = Color3.new(1, 1, 0), Duration = 0.5, Size = 0.3 })
			end
			if kind == "Sphere" then
				Draw.Sphere(origin, extra.Radius, { Color = Color3.new(0.3, 0.6, 1), Duration = 0.5, Transparency = 0.85 })
			end
		elseif kind == "Overlap" then
			Draw.Sphere(origin, extra.Radius, { Color = Color3.new(0.3, 0.6, 1), Duration = 0.5 })
		elseif kind == "OverlapBox" then
			Draw.Box(extra.CFrame, extra.Size, { Color = Color3.new(0.3, 0.6, 1), Duration = 0.5 })
		end
	end)
end

function Draw.ShowCasts(enabled: boolean)
	if enabled then
		Config.Debug = true
		installCastHook()
		castHookActive = true
	elseif castHookActive then
		require(script.Parent.Parent.Physics.Cast).SetHook(nil)
		castHookActive = false
	end
end

function Draw.Clear()
	for i = #drawings, 1, -1 do
		local instance = table.remove(drawings, i)
		instance:Destroy()
	end
end

function Draw.SetEnabled(enabled: boolean)
	Config.Debug = enabled == true
	if not enabled then
		Draw.Clear()
		Draw.ShowCasts(false)
	end
end

function Draw.DrawCount(): number
	return #drawings
end

function Draw.Line(a: Vector3, b: Vector3, options: any?)
	if not Config.Debug then
		return nil
	end
	if typeof(a) ~= "Vector3" or typeof(b) ~= "Vector3" then
		error("Core.Debug.Line : deux Vector3 attendus", 2)
	end
	local length = (b - a).Magnitude
	if length < 1e-6 then
		return Draw.Point(a, options)
	end
	local line = adornment("LineHandleAdornment", options)
	line.Length = length
	line.Thickness = (options and options.Thickness) or 0.1
	line.CFrame = CFrame.lookAt(a, b)
	return register(line, options)
end

function Draw.Point(position: Vector3, options: any?)
	if not Config.Debug then
		return nil
	end
	if typeof(position) ~= "Vector3" then
		error("Core.Debug.Point : Vector3 attendu", 2)
	end
	local sphere = adornment("SphereHandleAdornment", options)
	sphere.Radius = (options and options.Size) or 0.5
	sphere.CFrame = CFrame.new(position)
	return register(sphere, options)
end

function Draw.Sphere(center: Vector3, radius: number, options: any?)
	if not Config.Debug then
		return nil
	end
	if typeof(center) ~= "Vector3" or type(radius) ~= "number" or radius <= 0 then
		error("Core.Debug.Sphere : (Vector3 center, number radius > 0)", 2)
	end
	local sphere = adornment("SphereHandleAdornment", options, 0.7)
	sphere.Radius = radius
	sphere.CFrame = CFrame.new(center)
	return register(sphere, options)
end

function Draw.Box(placement: any, size: Vector3, options: any?)
	if not Config.Debug then
		return nil
	end
	local cframe = if typeof(placement) == "Vector3" then CFrame.new(placement) else placement
	if typeof(cframe) ~= "CFrame" or typeof(size) ~= "Vector3" then
		error("Core.Debug.Box : (CFrame | Vector3, Vector3 size) attendus", 2)
	end
	local box = adornment("BoxHandleAdornment", options, 0.7)
	box.Size = size
	box.CFrame = cframe
	return register(box, options)
end

function Draw.Arrow(origin: Vector3, vector: Vector3, options: any?)
	if not Config.Debug then
		return nil
	end
	if typeof(origin) ~= "Vector3" or typeof(vector) ~= "Vector3" then
		error("Core.Debug.Arrow : (Vector3 origin, Vector3 vector) attendus", 2)
	end
	local length = vector.Magnitude
	if length < 1e-6 then
		return Draw.Point(origin, options)
	end

	local tip = origin + vector
	local direction = vector / length
	local reference = if math.abs(direction.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis
	local side = direction:Cross(reference).Unit
	local up = side:Cross(direction)
	local head = math.min(length * 0.25, 1)

	local parts = {
		Draw.Line(origin, tip, options),
		Draw.Line(tip, tip - direction * head + side * head * 0.5, options),
		Draw.Line(tip, tip - direction * head - side * head * 0.5, options),
		Draw.Line(tip, tip - direction * head + up * head * 0.5, options),
		Draw.Line(tip, tip - direction * head - up * head * 0.5, options),
	}
	return {
		Remove = function()
			for _, part in parts do
				part.Remove()
			end
		end,
	}
end

function Draw.Path(points: { Vector3 }, options: any?)
	if not Config.Debug then
		return nil
	end
	if type(points) ~= "table" or #points == 0 then
		error("Core.Debug.Path : liste de Vector3 non vide requise", 2)
	end
	local parts = {}
	for i, point in points do
		table.insert(parts, Draw.Point(point, { Color = options and options.Color, Duration = options and options.Duration, Size = 0.3 }))
		if i > 1 then
			table.insert(parts, Draw.Line(points[i - 1], point, options))
		end
	end
	return {
		Remove = function()
			for _, part in parts do
				part.Remove()
			end
		end,
	}
end

function Draw.Text(position: Vector3, text: string, options: any?)
	if not Config.Debug then
		return nil
	end
	if typeof(position) ~= "Vector3" then
		error("Core.Debug.Text : Vector3 attendu", 2)
	end
	local anchor = Instance.new("Part")
	anchor.Name = "CoreDebugText"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Position = position

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(200, 30)
	billboard.AlwaysOnTop = not (options and options.AlwaysOnTop == false)
	billboard.Adornee = anchor
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = tostring(text)
	label.TextColor3 = (options and options.Color) or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.TextSize = (options and options.Size) or 14
	label.Font = Enum.Font.Code
	label.Parent = billboard

	return register(anchor, options)
end

return Draw
