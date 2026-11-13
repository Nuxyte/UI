--!nonstrict
--[[
	VFX.Beam / Trail : lignes de lumière et traînées, nettoyées automatiquement.

	VFX.Beam(from, to, options?) -> handle
		from / to : Vector3 | BasePart | Attachment
		options : Color (Color3 | ColorSequence)   Width (0.3)   Transparency (0)   LightEmission (0.5)   Texture   TextureSpeed
		          Segments (10)   CurveSize0 / CurveSize1   FaceCamera (true)   Parent (workspace)
		          Duration   le beam disparaît seul après Duration s (fondu de FadeTime, défaut 0.2)
		handle:SetEndpoints(from?, to?)   handle:Remove()   handle.Beam   handle.Instances

	VFX.Trail(part, options?) -> handle
		options : Color   Width (1 : écart entre les deux attachements, le long de l'axe Y local)   Lifetime (0.4)
		          Transparency (0)   LightEmission (0.5)   Texture   MinLength (0.1)   FaceCamera (true)
		          Offset0 / Offset1 (Vector3, remplacent Width)
		handle:SetEnabled(bool)   handle:Remove()   (la traînée finit de s'estomper avant destruction)   handle.Trail
]]

local TweenService = game:GetService("TweenService")

local Lines = {}

local function carrier(position: Vector3): BasePart
	local part = Instance.new("Part")
	part.Name = "CoreBeamAnchor"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.Position = position
	return part
end

local function toColorSequence(color: any): ColorSequence?
	if color == nil then
		return nil
	elseif typeof(color) == "Color3" then
		return ColorSequence.new(color)
	elseif typeof(color) == "ColorSequence" then
		return color
	end
	error("Core.VFX : Color doit être un Color3 ou une ColorSequence", 3)
end

-- Retourne un Attachment utilisable ; `created` liste les instances que nous avons créées (à détruire).
local function resolveEndpoint(spec: any, parent: Instance, created: { Instance }, fnName: string): Attachment
	local kind = typeof(spec)
	if kind == "Vector3" then
		local anchor = carrier(spec)
		anchor.Parent = parent
		local attachment = Instance.new("Attachment")
		attachment.Parent = anchor
		table.insert(created, anchor)
		return attachment
	elseif kind == "Instance" then
		if spec:IsA("Attachment") then
			return spec
		elseif spec:IsA("BasePart") then
			local attachment = Instance.new("Attachment")
			attachment.Name = "CoreBeamAttachment"
			attachment.Parent = spec
			table.insert(created, attachment)
			return attachment
		end
	end
	error(("Core.VFX.%s : extrémité invalide (%s) — Vector3, BasePart ou Attachment attendu"):format(fnName, kind), 3)
end

function Lines.Beam(from: any, to: any, options: any?)
	local opts = options or {}
	local parent = opts.Parent or workspace
	local created: { Instance } = {}

	local a0 = resolveEndpoint(from, parent, created, "Beam")
	local a1 = resolveEndpoint(to, parent, created, "Beam")

	local width = opts.Width or 0.3
	local beam = Instance.new("Beam")
	beam.Name = "CoreBeam"
	beam.Attachment0, beam.Attachment1 = a0, a1
	beam.Width0, beam.Width1 = width, width
	beam.Segments = opts.Segments or 10
	beam.FaceCamera = opts.FaceCamera ~= false
	beam.LightEmission = if opts.LightEmission ~= nil then opts.LightEmission else 0.5
	beam.Transparency = NumberSequence.new(opts.Transparency or 0)
	local colors = toColorSequence(opts.Color)
	if colors then
		beam.Color = colors
	end
	if opts.Texture then
		beam.Texture = opts.Texture
		beam.TextureSpeed = opts.TextureSpeed or 1
		beam.TextureMode = Enum.TextureMode.Stretch
	end
	if opts.CurveSize0 then
		beam.CurveSize0 = opts.CurveSize0
	end
	if opts.CurveSize1 then
		beam.CurveSize1 = opts.CurveSize1
	end
	beam.Parent = parent

	local handle = { Beam = beam, Instances = created, _removed = false }

	function handle:SetEndpoints(newFrom: any?, newTo: any?)
		if self._removed then
			return
		end
		if newFrom ~= nil then
			beam.Attachment0 = resolveEndpoint(newFrom, parent, created, "Beam")
		end
		if newTo ~= nil then
			beam.Attachment1 = resolveEndpoint(newTo, parent, created, "Beam")
		end
	end

	function handle:Remove()
		if self._removed then
			return
		end
		self._removed = true
		beam:Destroy()
		for _, instance in created do
			instance:Destroy()
		end
	end

	if opts.Duration then
		local fade = math.min(opts.FadeTime or 0.2, opts.Duration)
		task.delay(opts.Duration - fade, function()
			if handle._removed then
				return
			end
			if fade > 0 then
				TweenService:Create(beam, TweenInfo.new(fade), { Width0 = 0, Width1 = 0 }):Play()
			end
			task.delay(fade, function()
				handle:Remove()
			end)
		end)
	end
	return handle
end

function Lines.Trail(part: BasePart, options: any?)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		error("Core.VFX.Trail : BasePart attendue", 2)
	end
	local opts = options or {}
	local half = (opts.Width or 1) / 2

	local a0 = Instance.new("Attachment")
	a0.Name = "CoreTrail0"
	a0.Position = opts.Offset0 or Vector3.new(0, half, 0)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Name = "CoreTrail1"
	a1.Position = opts.Offset1 or Vector3.new(0, -half, 0)
	a1.Parent = part

	local trail = Instance.new("Trail")
	trail.Name = "CoreTrail"
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Lifetime = opts.Lifetime or 0.4
	trail.MinLength = opts.MinLength or 0.1
	trail.FaceCamera = opts.FaceCamera ~= false
	trail.LightEmission = if opts.LightEmission ~= nil then opts.LightEmission else 0.5
	trail.Transparency = NumberSequence.new(opts.Transparency or 0)
	local colors = toColorSequence(opts.Color)
	if colors then
		trail.Color = colors
	end
	if opts.Texture then
		trail.Texture = opts.Texture
	end
	trail.Parent = part

	local handle = { Trail = trail, _removed = false }

	function handle:SetEnabled(enabled: boolean)
		trail.Enabled = enabled
	end

	function handle:Remove()
		if self._removed then
			return
		end
		self._removed = true
		trail.Enabled = false
		task.delay(trail.Lifetime, function()
			trail:Destroy()
			a0:Destroy()
			a1:Destroy()
		end)
	end
	return handle
end

return Lines
