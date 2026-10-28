--!nonstrict
--[[
	MalaphasUI v2 - dark utility-style Roblox UI library (Luau).

	Placement : ModuleScript named "MalaphasUI" in ReplicatedStorage.
	Usage     : local Library = require(ReplicatedStorage:WaitForChild("MalaphasUI"))

	API
	  Library:CreateWindow({Name, Size, ToggleKey, Parent, OnClose})  -> Window
	  Window:CreateTab(name)                                          -> Tab
	  Window:Notify({Title, Text, Duration})
	  Window:SetVisible(bool) / Window:Close() / Window:Destroy()

	  Tab:CreateSection(name, side)   side = "Left" | "Right"        -> Groupbox

	  Groupbox:AddToggle({Name, Default, Flag, Callback})
	      toggle:AddColorPicker({Default, Flag, Callback})   -- swatch on the same row
	  Groupbox:AddSlider({Name, Min, Max, Default, Increment, Suffix, Flag, Callback})
	  Groupbox:AddDropdown({Name, Options, Default, Multi, Flag, Callback})
	  Groupbox:AddButton({Name, Callback})
	  Groupbox:AddColorPicker({Name, Default, Flag, Callback})
	  Groupbox:AddTextbox({Name, Default, Placeholder, Numeric, ClearTextOnFocus, Flag, Callback})
	  Groupbox:AddKeybind({Name, Default, Mode, Flag, Callback, OnChanged})   Mode = "Press" | "Toggle" | "Hold"
	  Groupbox:AddLabel(text)

	Every element has :Set(value, silent) and :Get().
	Library.Flags[flag]   -> current value
	Library.Options[flag] -> the element object
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Library = {
	Flags = {},
	Options = {},
	Windows = {},
}

Library.Theme = {
	Background = Color3.fromRGB(18, 18, 18),
	Panel = Color3.fromRGB(23, 23, 23),
	PanelHeader = Color3.fromRGB(27, 27, 27),
	Element = Color3.fromRGB(32, 32, 32),
	ElementHover = Color3.fromRGB(44, 44, 44),
	ElementPress = Color3.fromRGB(70, 70, 70),
	Border = Color3.fromRGB(48, 48, 48),
	BorderHover = Color3.fromRGB(105, 105, 105),
	Track = Color3.fromRGB(40, 40, 40),
	Text = Color3.fromRGB(225, 225, 225),
	SubText = Color3.fromRGB(135, 135, 135),
	Accent = Color3.fromRGB(255, 255, 255),
	Danger = Color3.fromRGB(255, 90, 90),
	Font = Enum.Font.Gotham,
	FontMedium = Enum.Font.GothamMedium,
	TextSize = 12,
}
local T = Library.Theme

local Window, Tab, Groupbox = {}, {}, {}
Window.__index = Window
Tab.__index = Tab
Groupbox.__index = Groupbox

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function create(class, props, parent)
	local inst = Instance.new(class)
	if inst:IsA("GuiObject") then
		inst.BorderSizePixel = 0
	end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		inst.BackgroundTransparency = 1
		inst.Font = T.Font
		inst.TextSize = T.TextSize
		inst.TextColor3 = T.Text
		inst.Text = ""
	end
	if inst:IsA("GuiButton") then
		inst.AutoButtonColor = false
	end
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function addStroke(parent, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color or T.Border
	s.Thickness = thickness or 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function addPadding(parent, l, t, r, b)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, l or 0)
	p.PaddingTop = UDim.new(0, t or 0)
	p.PaddingRight = UDim.new(0, r or 0)
	p.PaddingBottom = UDim.new(0, b or 0)
	p.Parent = parent
	return p
end

local function addList(parent, padding, horizontal)
	local l = Instance.new("UIListLayout")
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, padding or 0)
	if horizontal then
		l.FillDirection = Enum.FillDirection.Horizontal
	end
	l.Parent = parent
	return l
end

local function addCorner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 4)
	c.Parent = parent
	return c
end

local function tween(inst, props, time, style)
	TweenService:Create(
		inst,
		TweenInfo.new(time or 0.12, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		props
	):Play()
end

local function decimalsOf(n)
	local d = tostring(n):match("%.(%d+)")
	return d and #d or 0
end

local function register(flag, obj)
	if flag then
		Library.Flags[flag] = obj.Value
		Library.Options[flag] = obj
	end
end

local function isPointer(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function isMove(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------

function Library:CreateWindow(config)
	config = config or {}
	local self = setmetatable({}, Window)
	self.Name = config.Name or "Window"
	self.Tabs = {}
	self.ActiveTab = nil
	self.Connections = {}
	self.ToggleKey = config.ToggleKey or Enum.KeyCode.RightShift
	self.OnClose = config.OnClose
	self.Visible = false
	self._notifyOrder = 0

	local size = config.Size or UDim2.fromOffset(600, 400)
	local parent = config.Parent or Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = create("ScreenGui", {
		Name = "UILibrary_" .. self.Name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 1000,
	}, parent)
	self.Gui = gui

	-- CanvasGroup = whole window can fade in/out
	local main = create("CanvasGroup", {
		Name = "Main",
		Size = size,
		Position = UDim2.new(0.5, -size.X.Offset / 2, 0.5, -size.Y.Offset / 2),
		BackgroundColor3 = T.Background,
		GroupTransparency = 1,
		Active = true,
	}, gui)
	addStroke(main, T.Border)
	self.Main = main

	self.Scale = Instance.new("UIScale")
	self.Scale.Scale = 0.95
	self.Scale.Parent = main

	-- Header: title / breadcrumb / fps / close
	local header = create("Frame", {
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundColor3 = T.PanelHeader,
	}, main)

	create("TextLabel", {
		Text = self.Name,
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(0, 200, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = T.FontMedium,
	}, header)

	self.Breadcrumb = create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(0, 200, 1, 0),
		TextColor3 = T.SubText,
		TextSize = 10,
	}, header)

	self.Stats = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -34, 0, 0),
		Size = UDim2.new(0, 160, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = T.SubText,
		TextSize = 10,
	}, header)

	local closeBtn = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 28, 1, 0),
		Text = "X",
		Font = T.FontMedium,
		TextSize = 11,
		TextColor3 = T.SubText,
	}, header)
	closeBtn.MouseEnter:Connect(function()
		tween(closeBtn, { TextColor3 = T.Danger })
	end)
	closeBtn.MouseLeave:Connect(function()
		tween(closeBtn, { TextColor3 = T.SubText })
	end)
	closeBtn.MouseButton1Click:Connect(function()
		self:Close()
	end)

	create("Frame", { Position = UDim2.new(0, 0, 0, 26), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = T.Border }, main)

	-- Horizontal tab bar
	create("Frame", { Position = UDim2.new(0, 0, 0, 55), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = T.Border }, main)
	self.TabHolder = create("ScrollingFrame", {
		Position = UDim2.new(0, 6, 0, 27),
		Size = UDim2.new(1, -12, 0, 28),
		BackgroundTransparency = 1,
		ScrollBarThickness = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
	}, main)
	addList(self.TabHolder, 0, true)

	-- Search
	self.SearchBox = create("TextBox", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 62),
		Size = UDim2.fromOffset(140, 20),
		BackgroundTransparency = 0,
		BackgroundColor3 = T.Panel,
		PlaceholderText = "search...",
		PlaceholderColor3 = T.SubText,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 11,
	}, main)
	addStroke(self.SearchBox, T.Border)
	addPadding(self.SearchBox, 6, 0, 6, 0)
	self:_Connect(self.SearchBox:GetPropertyChangedSignal("Text"), function()
		self:_ApplySearch()
	end)

	-- Content area
	self.Content = create("Frame", {
		Position = UDim2.new(0, 10, 0, 90),
		Size = UDim2.new(1, -20, 1, -100),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	}, main)

	-- Notifications (bottom right)
	self.NotifyHolder = create("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.new(0, 240, 1, -32),
		BackgroundTransparency = 1,
	}, gui)
	local nl = addList(self.NotifyHolder, 6)
	nl.VerticalAlignment = Enum.VerticalAlignment.Bottom
	nl.HorizontalAlignment = Enum.HorizontalAlignment.Right

	-- Overlay for dropdowns / color picker popups (above everything)
	self.Overlay = create("TextButton", {
		Size = UDim2.fromScale(1, 1),
		ZIndex = 100,
		Visible = false,
	}, gui)
	self.Overlay.MouseButton1Click:Connect(function()
		self:_CloseDropdown()
	end)

	-- Window dragging
	local dragging, dragStart, startPos = false, nil, nil
	header.InputBegan:Connect(function(input)
		if isPointer(input) then
			dragging = true
			dragStart = input.Position
			startPos = main.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	self:_Connect(UserInputService.InputChanged, function(input)
		if dragging and isMove(input) then
			local d = input.Position - dragStart
			main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)

	-- Show / hide key
	self:_Connect(UserInputService.InputBegan, function(input, processed)
		if not processed and input.KeyCode == self.ToggleKey then
			self:SetVisible(not self.Visible)
		end
	end)

	-- fps / ms counter
	local frames, acc = 0, 0
	self:_Connect(RunService.RenderStepped, function(dt)
		frames += 1
		acc += dt
		if acc >= 0.5 then
			self.Stats.Text = string.format("%d fps  -  %d ms", math.floor(frames / acc + 0.5), math.floor(acc / frames * 1000 + 0.5))
			frames, acc = 0, 0
		end
	end)

	table.insert(Library.Windows, self)
	self:SetVisible(true) -- fade-in
	return self
end

function Window:_Connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(self.Connections, c)
	return c
end

function Window:SetVisible(visible)
	if self.Visible == visible then
		return
	end
	self.Visible = visible
	if visible then
		self.Main.Visible = true
		tween(self.Main, { GroupTransparency = 0 }, 0.22)
		tween(self.Scale, { Scale = 1 }, 0.22, Enum.EasingStyle.Back)
	else
		self:_CloseDropdown()
		tween(self.Main, { GroupTransparency = 1 }, 0.16)
		tween(self.Scale, { Scale = 0.95 }, 0.16)
		task.delay(0.17, function()
			if not self.Visible and self.Main and self.Main.Parent then
				self.Main.Visible = false
			end
		end)
	end
end

function Window:Close()
	if self._closing then
		return
	end
	self._closing = true
	if self.OnClose then
		task.spawn(self.OnClose)
	end
	self:SetVisible(false)
	task.delay(0.2, function()
		self:Destroy()
	end)
end

function Window:Destroy()
	self:_CloseDropdown()
	for _, c in ipairs(self.Connections) do
		c:Disconnect()
	end
	local i = table.find(Library.Windows, self)
	if i then
		table.remove(Library.Windows, i)
	end
	self.Gui:Destroy()
end

function Window:Notify(o)
	o = o or {}
	local duration = o.Duration or 4
	self._notifyOrder += 1

	local n = create("CanvasGroup", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = T.Panel,
		GroupTransparency = 1,
		LayoutOrder = self._notifyOrder,
	}, self.NotifyHolder)
	addStroke(n, T.Border)
	addList(n, 0)

	local body = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
	}, n)
	addList(body, 3)
	addPadding(body, 10, 8, 10, 8)

	create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 14),
		Text = o.Title or self.Name,
		Font = T.FontMedium,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
	}, body)
	create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = o.Text or "",
		TextColor3 = T.SubText,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = 2,
	}, body)

	local barBack = create("Frame", {
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = T.Track,
		LayoutOrder = 2,
	}, n)
	local fill = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.Accent }, barBack)

	tween(n, { GroupTransparency = 0 }, 0.2)
	tween(fill, { Size = UDim2.fromScale(0, 1) }, duration, Enum.EasingStyle.Linear)
	task.delay(duration, function()
		if n.Parent then
			tween(n, { GroupTransparency = 1 }, 0.25)
			task.delay(0.26, function()
				n:Destroy()
			end)
		end
	end)
end

function Window:_ApplySearch()
	local tab = self.ActiveTab
	if not tab then
		return
	end
	local q = string.lower(self.SearchBox.Text)
	for _, gb in ipairs(tab.Groupboxes) do
		local titleMatch = q == "" or string.find(string.lower(gb.Name), q, 1, true) ~= nil
		local any = titleMatch
		for _, el in ipairs(gb.Elements) do
			local match = titleMatch or string.find(string.lower(el.Name), q, 1, true) ~= nil
			el.Frame.Visible = match
			any = any or match
		end
		gb.Frame.Visible = any
	end
end

function Window:SelectTab(tab)
	if self.ActiveTab == tab then
		return
	end
	self:_CloseDropdown()

	for _, t in ipairs(self.Tabs) do
		local active = t == tab
		tween(t.Button, { TextColor3 = active and T.Accent or T.SubText }, 0.15)
		tween(t.Underline, { Size = active and UDim2.new(1, -8, 0, 1) or UDim2.new(0, 0, 0, 1) }, 0.22)
		if not active then
			t.Page.Visible = false
		end
	end

	self.ActiveTab = tab
	self.Breadcrumb.Text = string.upper(tab.Name) .. " / MAIN"

	-- Page transition: fade + slide up
	tab.Page.Position = UDim2.fromOffset(0, 14)
	tab.Page.GroupTransparency = 1
	tab.Page.Visible = true
	tween(tab.Page, { Position = UDim2.fromOffset(0, 0), GroupTransparency = 0 }, 0.24, Enum.EasingStyle.Cubic)

	self:_ApplySearch()
end

function Window:CreateTab(name)
	local tab = setmetatable({}, Tab)
	tab.Window = self
	tab.Name = name
	tab.Groupboxes = {}

	local width = TextService:GetTextSize(name, T.TextSize, T.Font, Vector2.new(1000, 100)).X + 20
	tab.Button = create("TextButton", {
		Size = UDim2.new(0, width, 1, 0),
		Text = name,
		TextColor3 = T.SubText,
		LayoutOrder = #self.Tabs + 1,
	}, self.TabHolder)

	-- Underline grows from the center when the tab becomes active
	tab.Underline = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, -1),
		Size = UDim2.new(0, 0, 0, 1),
		BackgroundColor3 = T.Accent,
	}, tab.Button)

	tab.Button.MouseEnter:Connect(function()
		if self.ActiveTab ~= tab then
			tween(tab.Button, { TextColor3 = T.Text })
		end
	end)
	tab.Button.MouseLeave:Connect(function()
		if self.ActiveTab ~= tab then
			tween(tab.Button, { TextColor3 = T.SubText })
		end
	end)
	tab.Button.MouseButton1Click:Connect(function()
		self:SelectTab(tab)
	end)

	tab.Page = create("CanvasGroup", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		Visible = false,
	}, self.Content)

	tab.Scroll = create("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = T.Border,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, tab.Page)
	addPadding(tab.Scroll, 0, 0, 8, 0)

	local function column(xScale, xOffset)
		local col = create("Frame", {
			Position = UDim2.new(xScale, xOffset, 0, 0),
			Size = UDim2.new(0.5, -4, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, tab.Scroll)
		addList(col, 8)
		return col
	end
	tab.Columns = { Left = column(0, 0), Right = column(0.5, 4) }

	table.insert(self.Tabs, tab)
	if #self.Tabs == 1 then
		self:SelectTab(tab)
	end
	return tab
end

----------------------------------------------------------------------
-- Overlay popups (dropdown list, color picker)
----------------------------------------------------------------------

function Window:_CloseDropdown()
	if self._dropList then
		self._dropList:Destroy()
		self._dropList = nil
	end
	self.Overlay.Visible = false
	local onClose = self._dropOnClose
	self._dropOnClose = nil
	if onClose then
		onClose()
	end
end

function Window:_OpenPopup(position, size, build, onClose)
	self:_CloseDropdown()
	self.Overlay.Visible = true
	self._dropOnClose = onClose
	local frame = create("Frame", {
		Position = UDim2.fromOffset(position.X, position.Y),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = T.Panel,
		Active = true, -- swallow clicks so the overlay does not close the popup
	}, self.Overlay)
	addStroke(frame, T.Border)
	self._dropList = frame
	build(frame)
end

function Window:_OpenDropdown(anchor, options, current, onPick, onClose, multi)
	self:_CloseDropdown()
	local itemH = 20
	local height = math.min(#options, 6) * itemH
	local pos = anchor.AbsolutePosition
	local y = pos.Y + anchor.AbsoluteSize.Y + 2
	if y + height > self.Gui.AbsoluteSize.Y then
		y = pos.Y - height - 2
	end

	self.Overlay.Visible = true
	self._dropOnClose = onClose

	local list = create("ScrollingFrame", {
		BackgroundColor3 = T.Panel,
		Position = UDim2.fromOffset(pos.X, y),
		Size = UDim2.fromOffset(anchor.AbsoluteSize.X, height),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = T.Border,
	}, self.Overlay)
	addStroke(list, T.Border)
	addList(list, 0)
	self._dropList = list

	for i, opt in ipairs(options) do
		local function isSelected()
			if multi then
				return current[opt] == true
			end
			return opt == current
		end

		local item = create("TextButton", {
			Size = UDim2.new(1, 0, 0, itemH),
			Text = tostring(opt),
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundColor3 = T.ElementHover,
			LayoutOrder = i,
		}, list)
		addPadding(item, 6, 0, 6, 0)
		local mark = create("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.fromOffset(4, 4),
			BackgroundColor3 = T.Accent,
		}, item)

		local function paint(hovered)
			local sel = isSelected()
			item.TextColor3 = (sel or hovered) and T.Accent or T.SubText
			mark.Visible = sel
		end
		paint(false)

		item.MouseEnter:Connect(function()
			item.BackgroundTransparency = 0
			paint(true)
		end)
		item.MouseLeave:Connect(function()
			item.BackgroundTransparency = 1
			paint(false)
		end)
		item.MouseButton1Click:Connect(function()
			onPick(opt)
			if multi then
				paint(true)
			else
				self:_CloseDropdown()
			end
		end)
	end
end

----------------------------------------------------------------------
-- Color picker (shared by Groupbox:AddColorPicker and toggle:AddColorPicker)
----------------------------------------------------------------------

local function createPicker(window, host, o, offsetX)
	local default = o.Default or Color3.new(1, 1, 1)
	local h, s, v = default:ToHSV()

	local swatch = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -offsetX, 0.5, 0),
		Size = UDim2.fromOffset(22, 12),
		BackgroundTransparency = 0,
		BackgroundColor3 = default,
	}, host)
	local swatchStroke = addStroke(swatch, T.Border)
	swatch.MouseEnter:Connect(function()
		tween(swatchStroke, { Color = T.BorderHover })
	end)
	swatch.MouseLeave:Connect(function()
		tween(swatchStroke, { Color = T.Border })
	end)

	local picker = { Name = o.Name or "Color", Value = default }
	local refreshPopup = nil

	local function apply(silent)
		local color = Color3.fromHSV(h, s, v)
		picker.Value = color
		swatch.BackgroundColor3 = color
		if o.Flag then
			Library.Flags[o.Flag] = color
		end
		if refreshPopup then
			refreshPopup()
		end
		if not silent and o.Callback then
			task.spawn(o.Callback, color)
		end
	end

	function picker:Set(color, silent)
		h, s, v = color:ToHSV()
		apply(silent)
	end

	function picker:Get()
		return self.Value
	end

	swatch.MouseButton1Click:Connect(function()
		local width, height = 168, 152
		local pos = swatch.AbsolutePosition
		local viewport = window.Gui.AbsoluteSize
		local x = math.clamp(pos.X + swatch.AbsoluteSize.X - width, 4, viewport.X - width - 4)
		local y = pos.Y + swatch.AbsoluteSize.Y + 4
		if y + height > viewport.Y then
			y = pos.Y - height - 4
		end

		window:_OpenPopup(Vector2.new(x, y), Vector2.new(width, height), function(frame)
			-- Saturation / value square
			local sv = create("Frame", {
				Position = UDim2.fromOffset(8, 8),
				Size = UDim2.fromOffset(152, 100),
				BackgroundColor3 = Color3.fromHSV(h, 1, 1),
			}, frame)
			local white = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1) }, sv)
			local g1 = Instance.new("UIGradient")
			g1.Transparency = NumberSequence.new(0, 1)
			g1.Parent = white
			local black = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0) }, sv)
			local g2 = Instance.new("UIGradient")
			g2.Rotation = 90
			g2.Transparency = NumberSequence.new(1, 0)
			g2.Parent = black
			local svCursor = create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(8, 8),
				BackgroundTransparency = 1,
			}, sv)
			addCorner(svCursor, 4)
			addStroke(svCursor, Color3.new(1, 1, 1), 1)
			local svHit = create("TextButton", { Size = UDim2.fromScale(1, 1) }, sv)

			-- Hue bar
			local hue = create("Frame", {
				Position = UDim2.fromOffset(8, 114),
				Size = UDim2.fromOffset(152, 10),
				BackgroundColor3 = Color3.new(1, 1, 1),
			}, frame)
			local keys = {}
			for i = 0, 6 do
				table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 1, 1)))
			end
			local g3 = Instance.new("UIGradient")
			g3.Color = ColorSequence.new(keys)
			g3.Parent = hue
			local hueMarker = create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(3, 14),
				BackgroundColor3 = Color3.new(1, 1, 1),
			}, hue)
			addStroke(hueMarker, Color3.new(0, 0, 0), 1)
			local hueHit = create("TextButton", { Size = UDim2.fromScale(1, 1) }, hue)

			-- Hex input
			local hex = create("TextBox", {
				Position = UDim2.fromOffset(8, 130),
				Size = UDim2.fromOffset(152, 16),
				BackgroundTransparency = 0,
				BackgroundColor3 = T.Element,
				ClearTextOnFocus = false,
				TextSize = 11,
			}, frame)
			addStroke(hex, T.Border)

			refreshPopup = function()
				sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
				svCursor.Position = UDim2.fromScale(s, 1 - v)
				hueMarker.Position = UDim2.fromScale(h, 0.5)
				if not hex:IsFocused() then
					hex.Text = "#" .. picker.Value:ToHex()
				end
			end
			refreshPopup()

			hex.FocusLost:Connect(function()
				local ok, color = pcall(Color3.fromHex, hex.Text)
				if ok and color then
					picker:Set(color)
				else
					refreshPopup()
				end
			end)

			local draggingSV, draggingHue = false, false
			local function updateSV(pos3)
				s = math.clamp((pos3.X - sv.AbsolutePosition.X) / sv.AbsoluteSize.X, 0, 1)
				v = 1 - math.clamp((pos3.Y - sv.AbsolutePosition.Y) / sv.AbsoluteSize.Y, 0, 1)
				apply()
			end
			local function updateHue(pos3)
				h = math.clamp((pos3.X - hue.AbsolutePosition.X) / hue.AbsoluteSize.X, 0, 1)
				apply()
			end

			svHit.InputBegan:Connect(function(input)
				if isPointer(input) then
					draggingSV = true
					updateSV(input.Position)
				end
			end)
			hueHit.InputBegan:Connect(function(input)
				if isPointer(input) then
					draggingHue = true
					updateHue(input.Position)
				end
			end)

			local conns = {}
			table.insert(conns, UserInputService.InputChanged:Connect(function(input)
				if isMove(input) then
					if draggingSV then
						updateSV(input.Position)
					elseif draggingHue then
						updateHue(input.Position)
					end
				end
			end))
			table.insert(conns, UserInputService.InputEnded:Connect(function(input)
				if isPointer(input) then
					draggingSV, draggingHue = false, false
				end
			end))
			frame.Destroying:Connect(function()
				for _, c in ipairs(conns) do
					c:Disconnect()
				end
			end)
		end, function()
			refreshPopup = nil
		end)
	end)

	return picker
end

----------------------------------------------------------------------
-- Tab / Groupbox
----------------------------------------------------------------------

function Tab:CreateSection(name, side)
	local column = self.Columns[side or "Left"] or self.Columns.Left
	local gb = setmetatable({}, Groupbox)
	gb.Tab = self
	gb.Window = self.Window
	gb.Name = name
	gb.Elements = {}
	gb._order = 0

	gb.Frame = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = T.Panel,
		LayoutOrder = #self.Groupboxes + 1,
	}, column)
	addStroke(gb.Frame, T.Border)
	addList(gb.Frame, 0)

	local title = create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 0,
		BackgroundColor3 = T.PanelHeader,
		Text = name,
		Font = T.FontMedium,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 0,
	}, gb.Frame)
	addPadding(title, 8, 0, 0, 0)

	create("Frame", { Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = T.Border, LayoutOrder = 1 }, gb.Frame)

	gb.Content = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
	}, gb.Frame)
	addList(gb.Content, 6)
	addPadding(gb.Content, 8, 8, 8, 8)

	table.insert(self.Groupboxes, gb)
	return gb
end
Tab.CreateGroupbox = Tab.CreateSection

function Groupbox:_Row(height)
	self._order += 1
	return create("Frame", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
		LayoutOrder = self._order,
	}, self.Content)
end

function Groupbox:_Register(name, frame)
	table.insert(self.Elements, { Name = name, Frame = frame })
end

----------------------------------------------------------------------
-- Label
----------------------------------------------------------------------

function Groupbox:AddLabel(text)
	local row = self:_Row(16)
	local label = create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		Text = text or "",
		TextColor3 = T.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
	}, row)
	self:_Register(text or "", row)
	local obj = {}
	function obj:SetText(t)
		label.Text = t
	end
	return obj
end

----------------------------------------------------------------------
-- Toggle
----------------------------------------------------------------------

function Groupbox:AddToggle(o)
	o = o or {}
	local name = o.Name or "Toggle"
	local window = self.Window
	local row = self:_Row(20)

	local box = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(12, 12),
		BackgroundColor3 = T.Element,
	}, row)
	local boxStroke = addStroke(box, T.Border)
	local mark = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = T.Accent,
		BackgroundTransparency = 1,
	}, box)
	local label = create("TextLabel", {
		Position = UDim2.fromOffset(20, 0),
		Size = UDim2.new(1, -20, 1, 0),
		Text = name,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = T.SubText,
	}, row)
	local hit = create("TextButton", { Size = UDim2.fromScale(1, 1) }, row)

	local toggle = { Name = name, Value = false, _pickers = 0 }

	function toggle:Set(value, silent)
		value = not not value
		local changed = value ~= self.Value
		self.Value = value
		tween(mark, { BackgroundTransparency = value and 0 or 1 })
		tween(boxStroke, { Color = value and T.Accent or T.Border })
		tween(label, { TextColor3 = value and T.Text or T.SubText })
		if o.Flag then
			Library.Flags[o.Flag] = value
		end
		if changed and not silent and o.Callback then
			task.spawn(o.Callback, value)
		end
	end

	function toggle:Get()
		return self.Value
	end

	-- Adds a color swatch on the right of this toggle's row (stackable)
	function toggle:AddColorPicker(opts)
		opts = opts or {}
		opts.Name = opts.Name or name
		local picker = createPicker(window, row, opts, self._pickers * 28)
		self._pickers += 1
		register(opts.Flag, picker)
		return picker
	end

	hit.MouseEnter:Connect(function()
		if not toggle.Value then
			tween(boxStroke, { Color = T.BorderHover })
		end
	end)
	hit.MouseLeave:Connect(function()
		if not toggle.Value then
			tween(boxStroke, { Color = T.Border })
		end
	end)
	hit.MouseButton1Click:Connect(function()
		toggle:Set(not toggle.Value)
	end)

	toggle:Set(o.Default == true, true)
	register(o.Flag, toggle)
	self:_Register(name, row)
	return toggle
end

----------------------------------------------------------------------
-- Slider
----------------------------------------------------------------------

function Groupbox:AddSlider(o)
	o = o or {}
	local name = o.Name or "Slider"
	local min, max = o.Min or 0, o.Max or 100
	local inc = o.Increment or 1
	local suffix = o.Suffix or ""
	local decimals = decimalsOf(inc)
	local window = self.Window

	local row = self:_Row(30)
	create("TextLabel", {
		Size = UDim2.new(1, -70, 0, 14),
		Text = name,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = T.SubText,
	}, row)
	local valueLabel = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(70, 14),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = T.Text,
	}, row)

	local hit = create("TextButton", {
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.new(1, 0, 0, 12),
	}, row)
	local track = create("Frame", {
		Position = UDim2.new(0, 0, 0.5, -2),
		Size = UDim2.new(1, 0, 0, 4),
		BackgroundColor3 = T.Track,
	}, hit)
	local fill = create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = T.Accent,
	}, track)

	local slider = { Name = name, Value = min }

	local function snap(v)
		v = math.clamp(v, min, max)
		v = min + math.floor((v - min) / inc + 0.5) * inc
		v = math.clamp(v, min, max)
		return tonumber(string.format("%." .. decimals .. "f", v))
	end

	function slider:Set(value, silent)
		value = snap(value)
		local changed = value ~= self.Value
		self.Value = value
		local alpha = (max > min) and (value - min) / (max - min) or 0
		fill.Size = UDim2.new(alpha, 0, 1, 0)
		valueLabel.Text = string.format("%." .. decimals .. "f", value) .. suffix
		if o.Flag then
			Library.Flags[o.Flag] = value
		end
		if changed and not silent and o.Callback then
			task.spawn(o.Callback, value)
		end
	end

	function slider:Get()
		return self.Value
	end

	local dragging = false
	local function updateFromX(x)
		local alpha = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		slider:Set(min + (max - min) * alpha)
	end

	hit.InputBegan:Connect(function(input)
		if isPointer(input) then
			dragging = true
			updateFromX(input.Position.X)
		end
	end)
	window:_Connect(UserInputService.InputChanged, function(input)
		if dragging and isMove(input) then
			updateFromX(input.Position.X)
		end
	end)
	window:_Connect(UserInputService.InputEnded, function(input)
		if isPointer(input) then
			dragging = false
		end
	end)

	slider:Set(o.Default ~= nil and o.Default or min, true)
	register(o.Flag, slider)
	self:_Register(name, row)
	return slider
end

----------------------------------------------------------------------
-- Dropdown (single or multi)
----------------------------------------------------------------------

function Groupbox:AddDropdown(o)
	o = o or {}
	local name = o.Name or "Dropdown"
	local options = o.Options or {}
	local multi = o.Multi == true
	local window = self.Window

	local row = self:_Row(22)
	create("TextLabel", {
		Size = UDim2.new(1, -104, 1, 0),
		Text = name,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = T.SubText,
	}, row)

	local box = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(98, 18),
		BackgroundTransparency = 0,
		BackgroundColor3 = T.Element,
	}, row)
	local boxStroke = addStroke(box, T.Border)
	local valueLabel = create("TextLabel", {
		Position = UDim2.fromOffset(6, 0),
		Size = UDim2.new(1, -22, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextSize = 11,
	}, box)
	local arrow = create("TextLabel", {
		Position = UDim2.new(1, -14, 0, 0),
		Size = UDim2.fromOffset(10, 18),
		Text = "+",
		TextColor3 = T.SubText,
	}, box)

	local dropdown = { Name = name, Value = nil, Options = options }
	local selected = {} -- multi mode: map option -> true (mutated in place, never reassigned)

	local function commitMulti(silent)
		local list, labels = {}, {}
		for _, opt in ipairs(dropdown.Options) do
			if selected[opt] then
				table.insert(list, opt)
				table.insert(labels, tostring(opt))
			end
		end
		dropdown.Value = list
		valueLabel.Text = #list == 0 and "none" or table.concat(labels, ", ")
		if o.Flag then
			Library.Flags[o.Flag] = list
		end
		if not silent and o.Callback then
			task.spawn(o.Callback, list)
		end
	end

	function dropdown:Set(value, silent)
		if multi then
			table.clear(selected)
			if type(value) == "table" then
				for _, opt in ipairs(value) do
					selected[opt] = true
				end
			elseif value ~= nil then
				selected[value] = true
			end
			commitMulti(silent)
		else
			local changed = value ~= self.Value
			self.Value = value
			valueLabel.Text = value ~= nil and tostring(value) or "..."
			if o.Flag then
				Library.Flags[o.Flag] = value
			end
			if changed and not silent and o.Callback then
				task.spawn(o.Callback, value)
			end
		end
	end

	function dropdown:Get()
		return self.Value
	end

	function dropdown:Refresh(newOptions, keepValue)
		self.Options = newOptions
		if multi then
			if not keepValue then
				table.clear(selected)
			end
			commitMulti(true)
		elseif not keepValue or table.find(newOptions, self.Value) == nil then
			self:Set(newOptions[1], true)
		end
	end

	box.MouseEnter:Connect(function()
		tween(boxStroke, { Color = T.BorderHover })
	end)
	box.MouseLeave:Connect(function()
		tween(boxStroke, { Color = T.Border })
	end)
	box.MouseButton1Click:Connect(function()
		arrow.Text = "-"
		window:_OpenDropdown(box, dropdown.Options, multi and selected or dropdown.Value, function(picked)
			if multi then
				selected[picked] = not selected[picked] or nil
				commitMulti(false)
			else
				dropdown:Set(picked)
			end
		end, function()
			arrow.Text = "+"
		end, multi)
	end)

	if multi then
		dropdown:Set(o.Default or {}, true)
	else
		dropdown:Set(o.Default ~= nil and o.Default or options[1], true)
	end
	register(o.Flag, dropdown)
	self:_Register(name, row)
	return dropdown
end

----------------------------------------------------------------------
-- Button
----------------------------------------------------------------------

function Groupbox:AddButton(o)
	o = o or {}
	local name = o.Name or "Button"
	self._order += 1

	local button = create("TextButton", {
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 0,
		BackgroundColor3 = T.Element,
		Text = name,
		LayoutOrder = self._order,
	}, self.Content)
	local stroke = addStroke(button, T.Border)

	button.MouseEnter:Connect(function()
		tween(button, { BackgroundColor3 = T.ElementHover })
		tween(stroke, { Color = T.BorderHover })
	end)
	button.MouseLeave:Connect(function()
		tween(button, { BackgroundColor3 = T.Element })
		tween(stroke, { Color = T.Border })
	end)
	button.MouseButton1Down:Connect(function()
		tween(button, { BackgroundColor3 = T.ElementPress }, 0.06)
	end)
	button.MouseButton1Up:Connect(function()
		tween(button, { BackgroundColor3 = T.ElementHover }, 0.15)
	end)
	button.MouseButton1Click:Connect(function()
		if o.Callback then
			task.spawn(o.Callback)
		end
	end)

	self:_Register(name, button)
	local obj = {}
	function obj:SetText(t)
		button.Text = t
	end
	return obj
end

----------------------------------------------------------------------
-- Color picker row
----------------------------------------------------------------------

function Groupbox:AddColorPicker(o)
	o = o or {}
	local name = o.Name or "Color"
	local row = self:_Row(20)
	create("TextLabel", {
		Size = UDim2.new(1, -30, 1, 0),
		Text = name,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = T.SubText,
	}, row)
	local picker = createPicker(self.Window, row, o, 0)
	register(o.Flag, picker)
	self:_Register(name, row)
	return picker
end

----------------------------------------------------------------------
-- Textbox
----------------------------------------------------------------------

function Groupbox:AddTextbox(o)
	o = o or {}
	local name = o.Name or "Textbox"
	local row = self:_Row(22)
	create("TextLabel", {
		Size = UDim2.new(1, -124, 1, 0),
		Text = name,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = T.SubText,
	}, row)

	local box = create("TextBox", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(116, 18),
		BackgroundTransparency = 0,
		BackgroundColor3 = T.Element,
		PlaceholderText = o.Placeholder or "...",
		PlaceholderColor3 = T.SubText,
		ClearTextOnFocus = o.ClearTextOnFocus == true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 11,
		ClipsDescendants = true,
	}, row)
	local stroke = addStroke(box, T.Border)
	addPadding(box, 6, 0, 6, 0)

	local textbox = { Name = name, Value = o.Default or "" }

	function textbox:Set(value, silent)
		self.Value = value
		box.Text = tostring(value)
		if o.Flag then
			Library.Flags[o.Flag] = value
		end
		if not silent and o.Callback then
			task.spawn(o.Callback, value)
		end
	end

	function textbox:Get()
		return self.Value
	end

	box.Focused:Connect(function()
		tween(stroke, { Color = T.Accent })
	end)
	box.FocusLost:Connect(function()
		tween(stroke, { Color = T.Border })
		if o.Numeric then
			local n = tonumber(box.Text)
			if n then
				textbox:Set(n)
			else
				box.Text = tostring(textbox.Value)
			end
		else
			textbox:Set(box.Text)
		end
	end)
	box.MouseEnter:Connect(function()
		if not box:IsFocused() then
			tween(stroke, { Color = T.BorderHover })
		end
	end)
	box.MouseLeave:Connect(function()
		if not box:IsFocused() then
			tween(stroke, { Color = T.Border })
		end
	end)

	textbox:Set(o.Default or "", true)
	register(o.Flag, textbox)
	self:_Register(name, row)
	return textbox
end

----------------------------------------------------------------------
-- Keybind
----------------------------------------------------------------------

function Groupbox:AddKeybind(o)
	o = o or {}
	local name = o.Name or "Keybind"
	local mode = o.Mode or "Press" -- "Press" | "Toggle" | "Hold"
	local window = self.Window

	local row = self:_Row(22)
	create("TextLabel", {
		Size = UDim2.new(1, -94, 1, 0),
		Text = name,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = T.SubText,
	}, row)

	local box = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(88, 18),
		BackgroundTransparency = 0,
		BackgroundColor3 = T.Element,
		TextSize = 10,
	}, row)
	local stroke = addStroke(box, T.Border)

	local kb = { Name = name, Value = o.Default, State = false }
	local binding = false

	local function display()
		if binding then
			box.Text = "[ ... ]"
		else
			box.Text = "[" .. (kb.Value and kb.Value.Name or "None") .. "]"
		end
	end

	function kb:Set(key, silent)
		self.Value = key
		binding = false
		display()
		if o.Flag then
			Library.Flags[o.Flag] = key
		end
		if not silent and o.OnChanged then
			task.spawn(o.OnChanged, key)
		end
	end

	function kb:Get()
		return self.Value
	end

	box.MouseEnter:Connect(function()
		tween(stroke, { Color = T.BorderHover })
	end)
	box.MouseLeave:Connect(function()
		tween(stroke, { Color = binding and T.Accent or T.Border })
	end)
	box.MouseButton1Click:Connect(function()
		binding = true
		tween(stroke, { Color = T.Accent })
		display()
	end)

	window:_Connect(UserInputService.InputBegan, function(input, processed)
		if binding then
			if input.UserInputType == Enum.UserInputType.Keyboard then
				tween(stroke, { Color = T.Border })
				if input.KeyCode == Enum.KeyCode.Escape then
					kb:Set(nil)
				else
					kb:Set(input.KeyCode)
				end
			end
			return
		end
		if processed or not kb.Value or input.KeyCode ~= kb.Value then
			return
		end
		if mode == "Hold" then
			kb.State = true
			if o.Callback then
				task.spawn(o.Callback, true)
			end
		elseif mode == "Toggle" then
			kb.State = not kb.State
			if o.Callback then
				task.spawn(o.Callback, kb.State)
			end
		elseif o.Callback then
			task.spawn(o.Callback)
		end
	end)
	window:_Connect(UserInputService.InputEnded, function(input)
		if mode == "Hold" and kb.Value and input.KeyCode == kb.Value then
			kb.State = false
			if o.Callback then
				task.spawn(o.Callback, false)
			end
		end
	end)

	display()
	register(o.Flag, kb)
	self:_Register(name, row)
	return kb
end

return Library
