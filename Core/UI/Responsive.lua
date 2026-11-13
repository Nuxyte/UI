--!nonstrict
--[[
	UI.Responsive
	Outils d'interface adaptative.

	GetViewport() -> Vector2                         taille de l'écran en pixels
	GetBreakpoint(width?) -> "XS" | "SM" | "MD" | "LG" | "XL"      (< 480, < 768, < 1024, < 1440, au-delà)
	GetDevice() -> "Phone" | "Tablet" | "Desktop"
	IsMobile() -> boolean                            tactile sans clavier
	Observe(callback(viewport, breakpoint)) -> { Disconnect }    appelle tout de suite puis à chaque redimensionnement
	Scale(screenGui, options?) -> { Destroy, GetScale }
		Ajoute un UIScale qui adapte une interface dessinée pour une résolution de référence.
		options : Design (Vector2, défaut 1920x1080)  Min (0.5)  Max (2)  Mode "Fit" (défaut, min des deux axes) | "Width" | "Height"
	GetInset() -> Vector2, Vector2                   marges de la barre système (GuiService:GetGuiInset)

	Exemple
		UI.Responsive.Scale(screenGui, { Design = Vector2.new(1920, 1080) })
		UI.Responsive.Observe(function(size, bp) menu.Visible = bp ~= "XS" end)
]]

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Responsive = {}

local function getCamera()
	local camera = workspace.CurrentCamera
	if not camera then
		error("Core.UI.Responsive : workspace.CurrentCamera indisponible", 3)
	end
	return camera
end

function Responsive.GetViewport(): Vector2
	return getCamera().ViewportSize
end

function Responsive.GetBreakpoint(width: number?): string
	local w = width or Responsive.GetViewport().X
	if w < 480 then
		return "XS"
	elseif w < 768 then
		return "SM"
	elseif w < 1024 then
		return "MD"
	elseif w < 1440 then
		return "LG"
	end
	return "XL"
end

function Responsive.IsMobile(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function Responsive.GetDevice(): string
	if not Responsive.IsMobile() then
		return "Desktop"
	end
	local viewport = Responsive.GetViewport()
	return if math.min(viewport.X, viewport.Y) < 600 then "Phone" else "Tablet"
end

function Responsive.GetInset(): (Vector2, Vector2)
	return GuiService:GetGuiInset()
end

function Responsive.Observe(callback: (Vector2, string) -> ())
	local camera = getCamera()
	local connection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		local size = camera.ViewportSize
		callback(size, Responsive.GetBreakpoint(size.X))
	end)

	local size = camera.ViewportSize
	task.spawn(callback, size, Responsive.GetBreakpoint(size.X))

	return {
		Disconnect = function()
			connection:Disconnect()
		end,
	}
end

function Responsive.Scale(screenGui: Instance, options: any?)
	local opts = options or {}
	local design = opts.Design or Vector2.new(1920, 1080)
	local minScale = opts.Min or 0.5
	local maxScale = opts.Max or 2
	local mode = opts.Mode or "Fit"
	if mode ~= "Fit" and mode ~= "Width" and mode ~= "Height" then
		error("Core.UI.Responsive.Scale : Mode doit valoir Fit, Width ou Height", 2)
	end

	local scale = screenGui:FindFirstChild("_CoreResponsiveScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "_CoreResponsiveScale"
		scale.Parent = screenGui
	end

	local function update(size: Vector2)
		local sx, sy = size.X / design.X, size.Y / design.Y
		local value = if mode == "Width" then sx elseif mode == "Height" then sy else math.min(sx, sy)
		scale.Scale = math.clamp(value, minScale, maxScale)
	end

	local observer = Responsive.Observe(update)
	update(Responsive.GetViewport())

	return {
		GetScale = function()
			return scale.Scale
		end,
		Destroy = function()
			observer.Disconnect()
			scale:Destroy()
		end,
	}
end

return Responsive
