--!nonstrict
--[[
	UI.Widgets
	Notifications et barres de progression.

	Notify(message, options?) -> handle
		options : Type "Info" (défaut) | "Success" | "Warning" | "Error"
		          Title (texte en gras au-dessus)   Duration (3 s ; 0 = reste jusqu'au clic)   MaxVisible (5)
		Les notifications s'empilent en haut à droite ; au-delà de MaxVisible elles sont mises en file d'attente.
		Un clic ferme la notification.
		handle:Close()   handle.Closed (Signal)

	ProgressBar(options?) -> bar
		options : Size  Position  AnchorPoint  Parent  Value (0..1)  BackgroundColor  FillColor  Corner (8)
		          ShowText (true : affiche le pourcentage)
		bar.Instance (Frame)   bar:Set(value, animate?, duration?)   bar:Get()   bar:SetText(text|nil)
		bar:SetColor(color3)   bar.Changed (Signal)   bar:Destroy()

	Exemple
		UI.Notify("Bienvenue !", { Type = "Success", Title = "Salut" })
		local bar = UI.ProgressBar({ Parent = screen, Size = UDim2.fromOffset(300, 18) })
		bar:Set(0.6)
]]

local Tween = require(script.Parent.Parent.Tween)
local Signal = require(script.Parent.Parent.Utilities.Signal)
local Create = require(script.Parent.Create)
local Animate = require(script.Parent.Animate)

local Widgets = {}

local COLORS = {
	Info = Color3.fromRGB(52, 120, 246),
	Success = Color3.fromRGB(46, 160, 90),
	Warning = Color3.fromRGB(230, 160, 30),
	Error = Color3.fromRGB(215, 60, 60),
}

local DEFAULT_MAX_VISIBLE = 5

local layer = nil

local function getLayer()
	if layer and layer.screen.Parent then
		return layer
	end

	local screen = Create.ScreenGui("CoreNotifications", { DisplayOrder = 800, IgnoreGuiInset = true })
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right

	local container = Create.Frame({
		Name = "Container",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(300, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = screen,
	}, { list })

	layer = { screen = screen, container = container, active = {}, queue = {}, counter = 0 }
	return layer
end

local function show(current, entry)
	local handle, opts = entry.handle, entry.options
	current.counter += 1
	table.insert(current.active, entry)

	local text = entry.message
	if opts.Title then
		text = ("<b>%s</b>\n%s"):format(opts.Title, entry.message)
	end

	local frame = Create.Button({
		Name = "Notification",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.fromRGB(28, 30, 36),
		Text = text,
		RichText = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 15,
		Font = Enum.Font.GothamMedium,
		LayoutOrder = current.counter,
		Corner = 8,
		Stroke = { Color = COLORS[opts.Type or "Info"], Thickness = 2 },
		Padding = 12,
		Visible = false,
		Parent = current.container,
	})
	entry.frame = frame

	local function close()
		if handle.Closing then
			return
		end
		handle.Closing = true

		local index = table.find(current.active, entry)
		if index then
			table.remove(current.active, index)
		end

		local function finalize()
			frame:Destroy()
			handle.Closed:Fire()
		end
		if Animate.Close(frame, { Style = "Pop", Duration = 0.2, OnComplete = finalize }) == nil then
			finalize()
		end

		local nextEntry = table.remove(current.queue, 1)
		if nextEntry then
			show(current, nextEntry)
		end
	end
	entry.close = close

	frame.Activated:Connect(close)
	Animate.Open(frame, { Style = "Pop", Duration = 0.25 })

	local duration = if opts.Duration == nil then 3 else opts.Duration
	if duration > 0 then
		task.delay(duration, close)
	end
end

function Widgets.Notify(message: string, options: any?)
	local opts = options or {}
	local kind = opts.Type or "Info"
	if not COLORS[kind] then
		error(("Core.UI.Notify : Type inconnu '%s' (Info, Success, Warning, Error)"):format(tostring(kind)), 2)
	end

	local current = getLayer()
	local handle = { Closed = Signal.new(), Closing = false }
	local entry = { handle = handle, message = tostring(message), options = opts }

	function handle:Close()
		if entry.close then
			entry.close()
		else
			-- encore en file d'attente : on la retire simplement
			local index = table.find(current.queue, entry)
			if index then
				table.remove(current.queue, index)
			end
			self.Closing = true
			self.Closed:Fire()
		end
	end

	if #current.active >= (opts.MaxVisible or DEFAULT_MAX_VISIBLE) then
		table.insert(current.queue, entry)
	else
		show(current, entry)
	end
	return handle
end

function Widgets.ProgressBar(options: any?)
	local opts = options or {}
	local fillColor = opts.FillColor or Color3.fromRGB(52, 120, 246)
	local corner = opts.Corner or 8

	local frame = Create.Frame({
		Name = "ProgressBar",
		Size = opts.Size or UDim2.fromOffset(240, 16),
		Position = opts.Position,
		AnchorPoint = opts.AnchorPoint,
		BackgroundColor3 = opts.BackgroundColor or Color3.fromRGB(40, 42, 50),
		ClipsDescendants = true,
		Corner = corner,
		Parent = opts.Parent,
	})
	local fill = Create.Frame({
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = fillColor,
		Corner = corner,
		Parent = frame,
	})
	local label = nil
	if opts.ShowText ~= false then
		label = Create.Label({
			Name = "Text",
			Size = UDim2.fromScale(1, 1),
			Text = "0%",
			TextSize = 12,
			ZIndex = 2,
			Parent = frame,
		})
	end

	local bar = { Instance = frame, Changed = Signal.new(), _value = 0, _customText = nil }

	local function refreshText()
		if label then
			label.Text = bar._customText or ("%d%%"):format(math.floor(bar._value * 100 + 0.5))
		end
	end

	function bar:Set(value: number, animate: boolean?, duration: number?)
		if type(value) ~= "number" or value ~= value then
			error("ProgressBar:Set : nombre requis", 2)
		end
		value = math.clamp(value, 0, 1)
		self._value = value

		Tween.Cancel(fill)
		if animate == false then
			fill.Size = UDim2.fromScale(value, 1)
		else
			Tween(fill, { Size = UDim2.fromScale(value, 1) }, { Duration = duration or 0.25, Easing = "QuadOut" })
		end
		refreshText()
		self.Changed:Fire(value)
	end

	function bar:Get(): number
		return self._value
	end

	function bar:SetText(text: string?)
		self._customText = text
		refreshText()
	end

	function bar:SetColor(color: Color3)
		fill.BackgroundColor3 = color
	end

	function bar:Destroy()
		Tween.Cancel(fill)
		self.Changed:Destroy()
		frame:Destroy()
	end

	if opts.Value then
		bar:Set(opts.Value, false)
	end
	return bar
end

return Widgets
