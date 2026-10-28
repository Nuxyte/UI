--!nonstrict
--[[
	MalaphasUI - librairie d'UI Roblox (Luau) au style sombre / utilitaire.

	Placement : ModuleScript nommé "MalaphasUI" dans ReplicatedStorage.
	Usage     : local Library = require(ReplicatedStorage:WaitForChild("MalaphasUI"))

	API
	  Library:CreateWindow({Name, Size, ToggleKey, Parent})      -> Window
	  Window:CreateTab(name)                                     -> Tab
	  Tab:CreateSection(name, side)  (side = "Left" | "Right")   -> Groupbox
	  Groupbox:AddToggle({Name, Default, Flag, Callback})        -> {Value, Set, Get}
	  Groupbox:AddSlider({Name, Min, Max, Default, Increment, Suffix, Flag, Callback})
	  Groupbox:AddDropdown({Name, Options, Default, Flag, Callback})
	  Groupbox:AddButton({Name, Callback})
	  Groupbox:AddLabel(text)
	  Window:SetVisible(bool) / Window:Destroy()

	Library.Flags[flag]   -> valeur courante d'un élément
	Library.Options[flag] -> objet de l'élément (pour :Set(...))
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

local function tween(inst, props, time)
	TweenService:Create(inst, TweenInfo.new(time or 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
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

	local main = create("Frame", {
		Name = "Main",
		Size = size,
		Position = UDim2.new(0.5, -size.X.Offset / 2, 0.5, -size.Y.Offset / 2),
		BackgroundColor3 = T.Background,
		Active = true,
	}, gui)
	addStroke(main, T.Border)
	self.Main = main

	-- En-tête : titre / fil d'Ariane / fps
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
		Position = UDim2.new(1, -10, 0, 0),
		Size = UDim2.new(0, 160, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = T.SubText,
		TextSize = 10,
	}, header)

	create("Frame", { Position = UDim2.new(0, 0, 0, 26), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = T.Border }, main)

	-- Barre d'onglets horizontale
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

	-- Recherche
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

	-- Zone de contenu
	self.Content = create("Frame", {
		Position = UDim2.new(0, 10, 0, 90),
		Size = UDim2.new(1, -20, 1, -100),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	}, main)

	-- Overlay pour les listes déroulantes (au-dessus de tout)
	self.Overlay = create("TextButton", {
		Size = UDim2.fromScale(1, 1),
		ZIndex = 100,
		Visible = false,
	}, gui)
	self.Overlay.MouseButton1Click:Connect(function()
		self:_CloseDropdown()
	end)

	-- Déplacement de la fenêtre
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

	-- Touche d'affichage / masquage
	self:_Connect(UserInputService.InputBegan, function(input, processed)
		if not processed and input.KeyCode == self.ToggleKey then
			self:SetVisible(not gui.Enabled)
		end
	end)

	-- Compteur fps / ms
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
	return self
end

function Window:_Connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(self.Connections, c)
	return c
end

function Window:SetVisible(visible)
	self.Gui.Enabled = visible
	if not visible then
		self:_CloseDropdown()
	end
end

function Window:Destroy()
	self:_CloseDropdown()
	for _, c in ipairs(self.Connections) do
		c:Disconnect()
	end
	self.Gui:Destroy()
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
	self:_CloseDropdown()
	for _, t in ipairs(self.Tabs) do
		local active = t == tab
		t.Page.Visible = active
		t.Underline.Visible = active
		tween(t.Button, { TextColor3 = active and T.Accent or T.SubText })
	end
	self.ActiveTab = tab
	self.Breadcrumb.Text = string.upper(tab.Name) .. " / MAIN"
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
	tab.Underline = create("Frame", {
		Position = UDim2.new(0, 4, 1, -1),
		Size = UDim2.new(1, -8, 0, 1),
		BackgroundColor3 = T.Accent,
		Visible = false,
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

	tab.Page = create("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = T.Border,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Visible = false,
	}, self.Content)
	addPadding(tab.Page, 0, 0, 8, 0)

	local function column(xScale, xOffset)
		local col = create("Frame", {
			Position = UDim2.new(xScale, xOffset, 0, 0),
			Size = UDim2.new(0.5, -4, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, tab.Page)
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
-- Liste déroulante (overlay)
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

function Window:_OpenDropdown(anchor, options, current, onPick, onClose)
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
		local selected = opt == current
		local item = create("TextButton", {
			Size = UDim2.new(1, 0, 0, itemH),
			Text = tostring(opt),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = selected and T.Accent or T.SubText,
			BackgroundColor3 = T.ElementHover,
			LayoutOrder = i,
		}, list)
		addPadding(item, 6, 0, 6, 0)
		item.MouseEnter:Connect(function()
			item.BackgroundTransparency = 0
			item.TextColor3 = T.Accent
		end)
		item.MouseLeave:Connect(function()
			item.BackgroundTransparency = 1
			item.TextColor3 = selected and T.Accent or T.SubText
		end)
		item.MouseButton1Click:Connect(function()
			onPick(opt)
			self:_CloseDropdown()
		end)
	end
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

	local toggle = { Name = name, Value = false }

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
-- Dropdown
----------------------------------------------------------------------

function Groupbox:AddDropdown(o)
	o = o or {}
	local name = o.Name or "Dropdown"
	local options = o.Options or {}
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
		TextSize = 11,
	}, box)
	local arrow = create("TextLabel", {
		Position = UDim2.new(1, -14, 0, 0),
		Size = UDim2.fromOffset(10, 18),
		Text = "+",
		TextColor3 = T.SubText,
	}, box)

	local dropdown = { Name = name, Value = nil, Options = options }

	function dropdown:Set(value, silent)
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

	function dropdown:Get()
		return self.Value
	end

	function dropdown:Refresh(newOptions, keepValue)
		self.Options = newOptions
		if not keepValue or table.find(newOptions, self.Value) == nil then
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
		window:_OpenDropdown(box, dropdown.Options, dropdown.Value, function(picked)
			dropdown:Set(picked)
		end, function()
			arrow.Text = "+"
		end)
	end)

	dropdown:Set(o.Default ~= nil and o.Default or options[1], true)
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

return Library
