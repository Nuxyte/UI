--!nonstrict
--[[
	UI.Create
	Création d'interfaces en une seule expression.

	Create(className, props?, children?) -> Instance
		props : toutes les propriétés + clés spéciales
			Parent        assigné en dernier
			Children      { Instance, ... }
			Corner        true | nombre (px) | UDim       -> UICorner
			Stroke        Color3 | { Color, Thickness, Transparency }   -> UIStroke
			Padding       nombre (px) | UDim              -> UIPadding (4 côtés)
			AspectRatio   nombre                           -> UIAspectRatioConstraint
			Events        { Activated = fn, MouseEnter = fn, ... }   -> connexions
		En cas d'erreur de propriété, l'Instance est détruite et l'erreur est explicite.

	Raccourcis avec valeurs par défaut sobres :
		Frame(props?, children?)   Label(props?)   Button(props?)   Image(props?)
		ScreenGui(name, props?)    crée dans PlayerGui (ResetOnSpawn = false)
	GetPlayerGui() -> PlayerGui

	Exemple
		local screen = UI.ScreenGui("Shop")
		UI.Frame({ Size = UDim2.fromOffset(300, 200), Corner = 12, Padding = 12, Parent = screen }, {
			UI.Label({ Text = "Boutique", Size = UDim2.new(1, 0, 0, 24) }),
		})
]]

local Players = game:GetService("Players")

local Create = {}

local SPECIAL = {
	Parent = true,
	Children = true,
	Corner = true,
	Stroke = true,
	Padding = true,
	AspectRatio = true,
	Events = true,
}

local function toUDim(value: any, fallback: UDim): UDim
	if typeof(value) == "UDim" then
		return value
	elseif type(value) == "number" then
		return UDim.new(0, value)
	end
	return fallback
end

local function merge(defaults: { [string]: any }, props: { [string]: any }?): { [string]: any }
	local result = table.clone(defaults)
	if props then
		for key, value in props do
			result[key] = value
		end
	end
	return result
end

function Create.GetPlayerGui(timeout: number?): Instance
	local player = Players.LocalPlayer
	if not player then
		error("Core.UI : LocalPlayer indisponible (l'UI fonctionne côté client uniquement)", 3)
	end
	return player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui", timeout or 10)
end

local function decorate(instance: Instance, props: { [string]: any })
	if props.Corner ~= nil and props.Corner ~= false then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = toUDim(if props.Corner == true then 8 else props.Corner, UDim.new(0, 8))
		corner.Parent = instance
	end

	if props.Stroke ~= nil and props.Stroke ~= false then
		local spec = props.Stroke
		if typeof(spec) == "Color3" then
			spec = { Color = spec }
		end
		local stroke = Instance.new("UIStroke")
		stroke.Color = spec.Color or Color3.new(0, 0, 0)
		stroke.Thickness = spec.Thickness or 1
		if spec.Transparency then
			stroke.Transparency = spec.Transparency
		end
		stroke.Parent = instance
	end

	if props.Padding ~= nil then
		local amount = toUDim(props.Padding, UDim.new(0, 0))
		local padding = Instance.new("UIPadding")
		padding.PaddingTop = amount
		padding.PaddingBottom = amount
		padding.PaddingLeft = amount
		padding.PaddingRight = amount
		padding.Parent = instance
	end

	if props.AspectRatio then
		local ratio = Instance.new("UIAspectRatioConstraint")
		ratio.AspectRatio = props.AspectRatio
		ratio.Parent = instance
	end

	if props.Events then
		for eventName, callback in props.Events do
			instance[eventName]:Connect(callback)
		end
	end
end

function Create.Create(className: string, props: { [string]: any }?, children: { Instance }?): Instance
	if type(className) ~= "string" then
		error("Core.UI.Create : `className` doit être une chaîne", 2)
	end
	local config = props or {}

	local ok, instance = pcall(Instance.new, className)
	if not ok then
		error(("Core.UI.Create : classe invalide '%s'"):format(className), 2)
	end

	local applied, err = pcall(function()
		for key, value in config do
			if not SPECIAL[key] then
				instance[key] = value
			end
		end
		decorate(instance, config)
		for _, child in children or config.Children or {} do
			child.Parent = instance
		end
	end)
	if not applied then
		instance:Destroy()
		error(("Core.UI.Create : %s"):format(tostring(err)), 2)
	end

	if config.Parent ~= nil then
		instance.Parent = config.Parent
	end
	return instance
end

local WHITE = Color3.new(1, 1, 1)

function Create.Frame(props: { [string]: any }?, children: { Instance }?): Frame
	return Create.Create("Frame", merge({
		BackgroundColor3 = Color3.fromRGB(32, 34, 40),
		BorderSizePixel = 0,
	}, props), children)
end

function Create.Label(props: { [string]: any }?, children: { Instance }?): TextLabel
	return Create.Create("TextLabel", merge({
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		TextColor3 = WHITE,
		TextSize = 16,
	}, props), children)
end

function Create.Button(props: { [string]: any }?, children: { Instance }?): TextButton
	return Create.Create("TextButton", merge({
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(52, 120, 246),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		TextColor3 = WHITE,
		TextSize = 16,
	}, props), children)
end

function Create.Image(props: { [string]: any }?, children: { Instance }?): ImageLabel
	return Create.Create("ImageLabel", merge({
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, props), children)
end

function Create.ScreenGui(name: string, props: { [string]: any }?): ScreenGui
	return Create.Create("ScreenGui", merge({
		Name = name,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Create.GetPlayerGui(),
	}, props))
end

return Create
