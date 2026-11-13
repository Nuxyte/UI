--!nonstrict
--[[
	VFX.Shake / Flash / Highlight : retours visuels instantanés.

	VFX.Shake(magnitude, duration, options?) -> handle        (CLIENT) secousse de caméra
		magnitude : amplitude en studs (translation) ; la rotation en est dérivée (options.Rotation = 0..n, défaut 1)
		options : Frequency (Config.VFX.ShakeFrequency)   FadeIn (0.05)   FadeOut (0.4)   Rotation (1)
		Plusieurs secousses s'additionnent. Aucune boucle de rendu n'existe hors secousse.
		handle:Cancel()      VFX.StopShake()  annule toutes les secousses

	VFX.Flash(color?, duration?, options?) -> handle           (CLIENT) flash plein écran
		color (blanc)   duration (0.4)   options : Transparency (0.3 : opacité initiale = 1 - Transparency)   DisplayOrder (100)

	VFX.Highlight(target, options?) -> handle                  (client ou serveur) contour / remplissage Highlight
		options : FillColor   OutlineColor   FillTransparency (0.5)   OutlineTransparency (0)   DepthMode ("Occluded" | "AlwaysOnTop")
		          Duration (disparition en fondu après Duration s)   Pulse (période en s : la couleur de remplissage "respire")
		handle:Remove()   handle.Highlight
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Config = require(script.Parent.Parent.Config)

local Screen = {}

local BIND_NAME = "CoreVFXShake"

local function requireClient(fnName: string)
	if not RunService:IsClient() then
		error(("Core.VFX.%s : disponible côté client uniquement"):format(fnName), 3)
	end
end

-- ---------------------------------------------------------------- Shake
local shakes = {}
local bound = false

local function applyShakes()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local now = os.clock()
	local offset, rx, ry, rz = Vector3.zero, 0, 0, 0

	local i = 1
	while i <= #shakes do
		local shake = shakes[i]
		local t = now - shake.start
		if t >= shake.duration then
			table.remove(shakes, i)
		else
			local envelope = math.min(t / shake.fadeIn, 1) * math.min((shake.duration - t) / shake.fadeOut, 1)
			local amp = shake.magnitude * envelope
			local f, s = t * shake.frequency, shake.seed
			offset += Vector3.new(math.noise(f, s, 0), math.noise(f, s, 10), math.noise(f, s, 20)) * amp
			local rot = amp * shake.rotation * 0.05
			rx += math.noise(f, s, 30) * rot
			ry += math.noise(f, s, 40) * rot
			rz += math.noise(f, s, 50) * rot
			i += 1
		end
	end

	camera.CFrame = camera.CFrame * CFrame.new(offset) * CFrame.Angles(rx, ry, rz)

	if #shakes == 0 and bound then
		bound = false
		RunService:UnbindFromRenderStep(BIND_NAME)
	end
end

function Screen.Shake(magnitude: number, duration: number, options: any?)
	requireClient("Shake")
	if type(magnitude) ~= "number" or type(duration) ~= "number" or duration <= 0 then
		error("Core.VFX.Shake : (magnitude: number, duration: number > 0)", 2)
	end
	local opts = options or {}
	local shake = {
		start = os.clock(),
		duration = duration,
		magnitude = magnitude,
		frequency = opts.Frequency or Config.VFX.ShakeFrequency,
		fadeIn = math.max(opts.FadeIn or 0.05, 1e-3),
		fadeOut = math.max(opts.FadeOut or 0.4, 1e-3),
		rotation = opts.Rotation or 1,
		seed = math.random() * 1000,
	}
	table.insert(shakes, shake)

	if not bound then
		bound = true
		RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, applyShakes)
	end

	return {
		Cancel = function()
			local index = table.find(shakes, shake)
			if index then
				table.remove(shakes, index)
			end
			if #shakes == 0 and bound then
				bound = false
				RunService:UnbindFromRenderStep(BIND_NAME)
			end
		end,
	}
end

function Screen.StopShake()
	table.clear(shakes)
	if bound then
		bound = false
		RunService:UnbindFromRenderStep(BIND_NAME)
	end
end

-- ---------------------------------------------------------------- Flash
local flashGui: ScreenGui? = nil

local function getFlashGui(order: number): ScreenGui
	if flashGui and flashGui.Parent then
		return flashGui
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "CoreVFXFlash"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = order
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	flashGui = gui
	return gui
end

function Screen.Flash(color: Color3?, duration: number?, options: any?)
	requireClient("Flash")
	local opts = options or {}
	local length = duration or 0.4

	local frame = Instance.new("Frame")
	frame.Name = "Flash"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BorderSizePixel = 0
	frame.Active = false
	frame.BackgroundColor3 = color or Color3.new(1, 1, 1)
	frame.BackgroundTransparency = if opts.Transparency ~= nil then opts.Transparency else 0.3
	frame.Parent = getFlashGui(opts.DisplayOrder or 100)

	local tween = TweenService:Create(frame, TweenInfo.new(length, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 })
	tween:Play()
	local done = false
	local function finish()
		if not done then
			done = true
			frame:Destroy()
		end
	end
	task.delay(length, finish)
	return {
		Frame = frame,
		Cancel = function()
			tween:Cancel()
			finish()
		end,
	}
end

-- ---------------------------------------------------------------- Highlight
function Screen.Highlight(target: Instance, options: any?)
	if typeof(target) ~= "Instance" then
		error("Core.VFX.Highlight : Instance attendue (Model ou BasePart)", 2)
	end
	local opts = options or {}

	local highlight = Instance.new("Highlight")
	highlight.Name = "CoreHighlight"
	highlight.Adornee = target
	highlight.FillColor = opts.FillColor or Color3.new(1, 1, 1)
	highlight.OutlineColor = opts.OutlineColor or highlight.FillColor
	highlight.FillTransparency = if opts.FillTransparency ~= nil then opts.FillTransparency else 0.5
	highlight.OutlineTransparency = if opts.OutlineTransparency ~= nil then opts.OutlineTransparency else 0
	highlight.DepthMode = if opts.DepthMode == "AlwaysOnTop" then Enum.HighlightDepthMode.AlwaysOnTop else Enum.HighlightDepthMode.Occluded
	highlight.Parent = target

	local handle = { Highlight = highlight, _removed = false }
	local pulseTween

	if opts.Pulse then
		local base = highlight.FillTransparency
		pulseTween = TweenService:Create(
			highlight,
			TweenInfo.new(opts.Pulse / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ FillTransparency = math.min(base + 0.4, 1) }
		)
		pulseTween:Play()
	end

	function handle:Remove()
		if self._removed then
			return
		end
		self._removed = true
		if pulseTween then
			pulseTween:Cancel()
		end
		highlight:Destroy()
	end

	-- se retire seul si la cible est détruite
	target.Destroying:Once(function()
		handle:Remove()
	end)

	if opts.Duration then
		local fade = math.min(0.25, opts.Duration)
		task.delay(opts.Duration - fade, function()
			if handle._removed then
				return
			end
			if pulseTween then
				pulseTween:Cancel()
			end
			TweenService:Create(highlight, TweenInfo.new(fade), { FillTransparency = 1, OutlineTransparency = 1 }):Play()
			task.delay(fade, function()
				handle:Remove()
			end)
		end)
	end
	return handle
end

return Screen
