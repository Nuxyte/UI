--!nonstrict
--[[
	UI.Animate
	Ouverture / fermeture animées, transition d'écran, effet "punch".

	Open(gui, options?)  Close(gui, options?)  Toggle(gui, options?)  -> Sequence | nil (nil si rien à faire)
		options : Style    "Pop" (défaut) | "Scale" | "Fade" | "FromBottom" | "FromTop" | "FromLeft" | "FromRight"
		          Duration (0.3)   Easing (surcharge)   OnComplete()
		Le fondu couvre `gui` et tous ses descendants GuiObject / texte / image / UIStroke présents à la 1re utilisation.
		"Pop" et "Scale" utilisent un UIScale ("_CoreScale") : mettez AnchorPoint = (0.5, 0.5) pour un zoom centré.
		Les styles "From*" animent Position : à éviter pour un enfant d'un UIListLayout.
		Close masque (Visible = false) puis remet l'objet à son état de repos : on peut rouvrir ensuite.
	IsOpen(gui) -> boolean
	Transition(callback, options?)    fondu vers une couleur, exécute callback (peut yield), fondu retour. Bloquant.
		options : Duration (0.5)  Color (noir)  DisplayOrder (1000)
	Punch(gui, scale?, duration?)     petit rebond d'échelle (feedback de clic / gain)

	Exemple
		UI.Open(shopFrame, { Style = "FromBottom" })
		UI.Transition(function() teleportPlayer() end, { Duration = 0.6 })
]]

local Tween = require(script.Parent.Parent.Tween)
local Util = require(script.Parent.Util)

local Animate = {}

local states = setmetatable({}, { __mode = "k" })

local STYLES = {
	Pop = { scale = 0.75, fade = true, openEasing = "BackOut", closeEasing = "BackIn" },
	Scale = { scale = 0, fade = false, openEasing = "QuadOut", closeEasing = "QuadIn" },
	Fade = { fade = true, openEasing = "QuadOut", closeEasing = "QuadIn" },
	FromBottom = { offset = UDim2.fromScale(0, 1), fade = false, openEasing = "QuartOut", closeEasing = "QuartIn" },
	FromTop = { offset = UDim2.fromScale(0, -1), fade = false, openEasing = "QuartOut", closeEasing = "QuartIn" },
	FromLeft = { offset = UDim2.fromScale(-1, 0), fade = false, openEasing = "QuartOut", closeEasing = "QuartIn" },
	FromRight = { offset = UDim2.fromScale(1, 0), fade = false, openEasing = "QuartOut", closeEasing = "QuartIn" },
}

local function collectFades(gui: Instance): { { any } }
	local list = {}
	local function add(instance: Instance, property: string)
		local value = (instance :: any)[property]
		if value < 1 then
			table.insert(list, { instance, property, value })
		end
	end
	local function visit(instance: Instance)
		if instance:IsA("GuiObject") then
			add(instance, "BackgroundTransparency")
		end
		if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
			add(instance, "TextTransparency")
		end
		if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
			add(instance, "ImageTransparency")
		end
		if instance:IsA("UIStroke") then
			add(instance, "Transparency")
		end
	end
	visit(gui)
	for _, descendant in gui:GetDescendants() do
		visit(descendant)
	end
	return list
end

local function getState(gui: GuiObject)
	local state = states[gui]
	if not state then
		state = {
			home = gui.Position,
			fades = collectFades(gui),
			scale = Util.EnsureScale(gui),
			sequence = nil,
			closing = false,
		}
		states[gui] = state
	end
	return state
end

local function restore(gui: GuiObject, state)
	gui.Position = state.home
	state.scale.Scale = 1
	for _, entry in state.fades do
		entry[1][entry[2]] = entry[3]
	end
end

local function play(gui: GuiObject, opening: boolean, options: any?)
	if typeof(gui) ~= "Instance" or not gui:IsA("GuiObject") then
		error("Core.UI.Open/Close : GuiObject attendu", 3)
	end
	local opts = options or {}
	local style = opts.Style or "Pop"
	local definition = STYLES[style]
	if not definition then
		error(("Core.UI : style d'animation inconnu '%s'"):format(tostring(style)), 3)
	end

	local state = getState(gui)

	if opening then
		if gui.Visible and not state.closing and not state.sequence then
			return nil
		end
	elseif not gui.Visible or state.closing then
		return nil
	end

	if state.sequence then
		state.sequence:Cancel()
		state.sequence = nil
	end

	local duration = opts.Duration or 0.3
	local easing = opts.Easing or (if opening then definition.openEasing else definition.closeEasing)
	local specs = {}

	if opening then
		state.closing = false
		restore(gui, state)
		gui.Visible = true

		if definition.scale then
			state.scale.Scale = definition.scale
			table.insert(specs, { state.scale, { Scale = 1 } })
		end
		if definition.offset then
			gui.Position = state.home + definition.offset
			table.insert(specs, { gui, { Position = state.home } })
		end
		if definition.fade then
			for _, entry in state.fades do
				entry[1][entry[2]] = 1
				table.insert(specs, { entry[1], { [entry[2]] = entry[3] } })
			end
		end
	else
		state.closing = true
		if definition.scale then
			table.insert(specs, { state.scale, { Scale = definition.scale } })
		end
		if definition.offset then
			table.insert(specs, { gui, { Position = state.home + definition.offset } })
		end
		if definition.fade then
			for _, entry in state.fades do
				table.insert(specs, { entry[1], { [entry[2]] = 1 } })
			end
		end
	end

	local function finish()
		state.sequence = nil
		if not opening then
			state.closing = false
			gui.Visible = false
			restore(gui, state)
		end
		if opts.OnComplete then
			task.spawn(opts.OnComplete)
		end
	end

	local sequence = Tween.Sequence()
	if #specs == 0 then
		sequence:Delay(duration)
	end
	for _, spec in specs do
		sequence:Join(spec[1], spec[2], { Duration = duration, Easing = easing })
	end
	sequence:OnComplete(finish)
	state.sequence = sequence
	sequence:Play()
	return sequence
end

function Animate.Open(gui: GuiObject, options: any?)
	return play(gui, true, options)
end

function Animate.Close(gui: GuiObject, options: any?)
	return play(gui, false, options)
end

function Animate.IsOpen(gui: GuiObject): boolean
	local state = states[gui]
	return gui.Visible and not (state ~= nil and state.closing)
end

function Animate.Toggle(gui: GuiObject, options: any?)
	if Animate.IsOpen(gui) then
		return Animate.Close(gui, options)
	end
	return Animate.Open(gui, options)
end

function Animate.Transition(callback: (() -> ())?, options: any?)
	local opts = options or {}
	local half = (opts.Duration or 0.5) / 2
	local Create = require(script.Parent.Create)

	local screen = Create.ScreenGui("CoreTransition", {
		DisplayOrder = opts.DisplayOrder or 1000,
		IgnoreGuiInset = true,
	})
	local cover = Create.Frame({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = opts.Color or Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		ZIndex = 10,
		Parent = screen,
	})

	Tween(cover, { BackgroundTransparency = 0 }, { Duration = half, Easing = "QuadInOut" }):Wait()
	local ok, err = true, nil
	if callback then
		ok, err = pcall(callback)
	end
	Tween(cover, { BackgroundTransparency = 1 }, { Duration = half, Easing = "QuadInOut" }):Wait()
	screen:Destroy()

	if not ok then
		error(err, 2)
	end
end

function Animate.Punch(gui: GuiObject, amount: number?, duration: number?)
	local scale = Util.EnsureScale(gui)
	local total = duration or 0.25
	Tween.Cancel(scale)
	scale.Scale = 1
	return Tween.Sequence()
		:Append(scale, { Scale = amount or 1.1 }, { Duration = total / 2, Easing = "QuadOut" })
		:Append(scale, { Scale = 1 }, { Duration = total / 2, Easing = "BackOut" })
		:Play()
end

return Animate
