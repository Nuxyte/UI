--!nonstrict
--[[
	UI.Interaction
	Gestion des boutons (BindButton), effets de survol, glisser-déposer, infobulles.

	BindButton(button, options?) -> handle    (TextButton / ImageButton existant : effets + clic)
		options : OnClick()  OnHover()  OnLeave()  OnDown()
		          HoverScale (1.05)  ClickScale (0.95)  Debounce (0.1 s anti double-clic)
		handle.Clicked (Signal)   handle:SetEnabled(bool)   handle.Enabled   handle:Destroy()
		Les effets passent par un UIScale ("_CoreButtonScale") ajouté au bouton.

	Hover(gui, options?) -> { Destroy }
		options : Color (BackgroundColor3 au survol)  Duration (0.15)  OnEnter()  OnLeave()

	Draggable(gui, options?) -> { Destroy, IsDragging }
		options : Handle (zone de saisie, défaut gui)   Bounds (GuiObject limite, défaut le parent GuiObject ; false = aucune)
		          Axis "X" | "Y"   DragZIndex (ZIndex pendant le drag)
		          DropTargets  { GuiObject } | function() -> { GuiObject }
		          OnDragStart()  OnDrag(position)  OnDrop(target, gui) -> false pour refuser  OnDragEnd(target?)
		          ReturnOnFail (true : revient à la position de départ si aucun dépôt valide)

	Tooltip(gui, content, options?) -> { Destroy }
		content : string | function() -> string        options : Delay (0.4)  Offset (Vector2)
		Désactivé automatiquement sur les appareils tactiles.

	Exemple
		UI.BindButton(playButton, { OnClick = function() startGame() end })
		UI.Draggable(item, { DropTargets = { slot1, slot2 }, ReturnOnFail = true, OnDrop = function(slot) return slot:GetAttribute("Free") end })
]]

local UserInputService = game:GetService("UserInputService")

local Tween = require(script.Parent.Parent.Tween)
local Signal = require(script.Parent.Parent.Utilities.Signal)
local Maid = require(script.Parent.Parent.Utilities.Maid)
local Util = require(script.Parent.Util)

local Interaction = {}

local function safeCall(callback: (() -> ())?, ...: any)
	if callback then
		task.spawn(callback, ...)
	end
end

function Interaction.BindButton(button: GuiButton, options: any?)
	if typeof(button) ~= "Instance" or not button:IsA("GuiButton") then
		error("Core.UI.BindButton : TextButton ou ImageButton attendu", 2)
	end

	local opts = options or {}
	local hoverScale = opts.HoverScale or 1.05
	local clickScale = opts.ClickScale or 0.95
	local debounce = opts.Debounce or 0.1

	local scale = Util.EnsureScale(button, "_CoreButtonScale")
	local maid = Maid.new()
	local handle = { Clicked = Signal.new(), Enabled = true, Instance = button }
	local hovering, lastClick, destroyed = false, -math.huge, false

	local function scaleTo(target: number)
		Tween.Cancel(scale)
		Tween(scale, { Scale = target }, { Duration = 0.12, Easing = "QuadOut" })
	end

	maid:Give(button.MouseEnter:Connect(function()
		if not handle.Enabled then
			return
		end
		hovering = true
		scaleTo(hoverScale)
		safeCall(opts.OnHover)
	end))
	maid:Give(button.MouseLeave:Connect(function()
		hovering = false
		scaleTo(1)
		safeCall(opts.OnLeave)
	end))
	maid:Give(button.MouseButton1Down:Connect(function()
		if handle.Enabled then
			scaleTo(clickScale)
			safeCall(opts.OnDown)
		end
	end))
	maid:Give(button.MouseButton1Up:Connect(function()
		scaleTo(if hovering and handle.Enabled then hoverScale else 1)
	end))
	maid:Give(button.Activated:Connect(function()
		if not handle.Enabled then
			return
		end
		local now = os.clock()
		if now - lastClick < debounce then
			return
		end
		lastClick = now
		handle.Clicked:Fire()
		safeCall(opts.OnClick)
	end))

	function handle:SetEnabled(enabled: boolean)
		self.Enabled = enabled
		button.Interactable = enabled
		if not enabled then
			hovering = false
			scaleTo(1)
		end
	end

	function handle:Destroy()
		if destroyed then
			return
		end
		destroyed = true
		maid:Clean()
		Tween.Cancel(scale)
		scale:Destroy()
		self.Clicked:Destroy()
	end

	maid:Give(button.Destroying:Connect(function()
		handle:Destroy()
	end))

	return handle
end

function Interaction.Hover(gui: GuiObject, options: any?)
	local opts = options or {}
	local duration = opts.Duration or 0.15
	local original = gui.BackgroundColor3
	local maid = Maid.new()

	maid:Give(gui.MouseEnter:Connect(function()
		if opts.Color then
			Tween.Cancel(gui)
			Tween(gui, { BackgroundColor3 = opts.Color }, { Duration = duration })
		end
		safeCall(opts.OnEnter)
	end))
	maid:Give(gui.MouseLeave:Connect(function()
		if opts.Color then
			Tween.Cancel(gui)
			Tween(gui, { BackgroundColor3 = original }, { Duration = duration })
		end
		safeCall(opts.OnLeave)
	end))

	return {
		Destroy = function()
			maid:Clean()
		end,
	}
end

function Interaction.Draggable(gui: GuiObject, options: any?)
	local opts = options or {}
	local grip = opts.Handle or gui
	local maid = Maid.new()

	local dragging = false
	local active = nil
	local startPointer, startPosition, startAbsolute, startZ, bounds

	local function finish(pointer: Vector3)
		if not dragging then
			return
		end
		dragging = false
		active:Clean()
		if opts.DragZIndex then
			gui.ZIndex = startZ
		end

		local targets = opts.DropTargets
		if type(targets) == "function" then
			targets = targets()
		end

		local dropped = nil
		for _, target in targets or {} do
			if target ~= gui and Util.IsPointInside(target, Vector2.new(pointer.X, pointer.Y)) then
				dropped = target
				break
			end
		end

		local accepted = dropped ~= nil
		if dropped and opts.OnDrop then
			accepted = opts.OnDrop(dropped, gui) ~= false
		end
		if not accepted and opts.ReturnOnFail then
			Tween.Cancel(gui)
			Tween(gui, { Position = startPosition }, { Duration = 0.2, Easing = "QuadOut" })
		end
		safeCall(opts.OnDragEnd, if accepted then dropped else nil)
	end

	maid:Give(grip.InputBegan:Connect(function(input)
		if dragging then
			return
		end
		local inputType = input.UserInputType
		if inputType ~= Enum.UserInputType.MouseButton1 and inputType ~= Enum.UserInputType.Touch then
			return
		end

		dragging = true
		active = Maid.new()
		startPointer = input.Position
		startPosition = gui.Position
		startAbsolute = gui.AbsolutePosition
		startZ = gui.ZIndex
		if opts.DragZIndex then
			gui.ZIndex = opts.DragZIndex
		end

		bounds = opts.Bounds
		if bounds == nil and gui.Parent and gui.Parent:IsA("GuiObject") then
			bounds = gui.Parent
		end

		active:Give(UserInputService.InputChanged:Connect(function(moved)
			local movedType = moved.UserInputType
			if not dragging or (movedType ~= Enum.UserInputType.MouseMovement and movedType ~= Enum.UserInputType.Touch) then
				return
			end

			local dx = moved.Position.X - startPointer.X
			local dy = moved.Position.Y - startPointer.Y
			if opts.Axis == "X" then
				dy = 0
			elseif opts.Axis == "Y" then
				dx = 0
			end

			if bounds then
				local size = gui.AbsoluteSize
				local lowX = bounds.AbsolutePosition.X - startAbsolute.X
				local highX = bounds.AbsolutePosition.X + bounds.AbsoluteSize.X - (startAbsolute.X + size.X)
				local lowY = bounds.AbsolutePosition.Y - startAbsolute.Y
				local highY = bounds.AbsolutePosition.Y + bounds.AbsoluteSize.Y - (startAbsolute.Y + size.Y)
				dx = math.clamp(dx, math.min(lowX, highX), math.max(lowX, highX))
				dy = math.clamp(dy, math.min(lowY, highY), math.max(lowY, highY))
			end

			gui.Position = UDim2.new(
				startPosition.X.Scale,
				startPosition.X.Offset + dx,
				startPosition.Y.Scale,
				startPosition.Y.Offset + dy
			)
			safeCall(opts.OnDrag, gui.Position)
		end))

		active:Give(UserInputService.InputEnded:Connect(function(ended)
			if ended.UserInputType == inputType then
				finish(ended.Position)
			end
		end))

		safeCall(opts.OnDragStart)
	end))

	return {
		IsDragging = function()
			return dragging
		end,
		Destroy = function()
			if dragging then
				dragging = false
				active:Clean()
			end
			maid:Clean()
		end,
	}
end

local tip = nil

local function getTip()
	if tip and tip.screen.Parent then
		return tip
	end
	local Create = require(script.Parent.Create)
	local screen = Create.ScreenGui("CoreTooltip", { DisplayOrder = 900, IgnoreGuiInset = true })
	local frame = Create.Frame({
		Name = "Tip",
		Visible = false,
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = Color3.fromRGB(20, 22, 26),
		BackgroundTransparency = 0.1,
		ZIndex = 50,
		Corner = 6,
		Padding = 8,
		Parent = screen,
	})
	local label = Create.Label({
		AutomaticSize = Enum.AutomaticSize.XY,
		Text = "",
		TextSize = 14,
		ZIndex = 51,
		Parent = frame,
	})
	tip = { screen = screen, frame = frame, label = label }
	return tip
end

function Interaction.Tooltip(gui: GuiObject, content: any, options: any?)
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		return { Destroy = function() end }
	end

	local opts = options or {}
	local delaySeconds = opts.Delay or 0.4
	local offset = opts.Offset or Vector2.new(14, 18)
	local maid = Maid.new()
	local pending = nil

	local function place(x: number, y: number)
		getTip().frame.Position = UDim2.fromOffset(x + offset.X, y + offset.Y)
	end

	local function hide()
		if pending then
			pcall(task.cancel, pending)
			pending = nil
		end
		if tip and tip.frame.Parent then
			tip.frame.Visible = false
		end
	end

	maid:Give(gui.MouseEnter:Connect(function(x, y)
		hide()
		pending = task.delay(delaySeconds, function()
			pending = nil
			local text = if type(content) == "function" then content() else content
			if text == nil or text == "" then
				return
			end
			local t = getTip()
			t.label.Text = tostring(text)
			place(x, y)
			t.frame.Visible = true
		end)
	end))
	maid:Give(gui.MouseMoved:Connect(function(x, y)
		if tip and tip.frame.Visible then
			place(x, y)
		end
	end))
	maid:Give(gui.MouseLeave:Connect(hide))
	maid:Give(gui.Destroying:Connect(hide))

	return {
		Destroy = function()
			hide()
			maid:Clean()
		end,
	}
end

return Interaction
