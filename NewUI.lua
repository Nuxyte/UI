--!nonstrict
--[[
	NicoTine Modern v1.1 - modern Roblox UI library (Luau). Single ModuleScript, no dependencies.
	Style: sidebar tabs, rounded cards, switch toggles, animated popups, toasts, dialogs.

	Placement : ModuleScript "NicoTineModern" in ReplicatedStorage, or loadstring() it in an executor.
	Usage     : local UI = require(ReplicatedStorage:WaitForChild("NicoTineModern"))

	WINDOW
	  UI:CreateWindow({Title, SubTitle, Icon, Size, Theme, ToggleKey, Parent, Launcher, ConfirmClose,
	                   SidebarWidth, MinSize, OnClose})  -> Window
	      Parent: default is gethui() / CoreGui (stays clickable above the Esc menu in executors),
	              falling back to PlayerGui when those are not allowed (normal LocalScripts / Studio).
	  Window:AddTab({Title, Icon}) | Window:CreateTab(name, icon)   -> Tab
	  Window:AddTabDivider(text?)
	  Window:SelectTab(tab)
	  Window:Notify({Title, Content, Duration, Type, Icon})   Type = "info" | "success" | "warning" | "error"
	  Window:Dialog({Title, Content, Buttons = {{Title, Callback, Primary}}})
	  Window:SetVisible(bool) / Toggle() / Minimize()   -- hide to the launcher pill (or ToggleKey)
	  Window:SetTitle(text) / SetSubTitle(text)
	  Window:Destroy()

	CONTAINERS (Tab and Section share the same Add* methods)
	  Tab:AddSection(name | {Title, Collapsible, Collapsed})  -> Section

	ELEMENTS   (every option table accepts Name or Title, Description, Flag, Callback)
	  AddToggle({Name, Description, Default, Flag, Callback})
	  AddSlider({Name, Min, Max, Default, Increment, Suffix, Flag, Callback})
	  AddDropdown({Name, Options, Default, Multi, Searchable, Flag, Callback})
	  AddButton({Name, Description, Variant = "Primary"|nil, Callback})
	  AddColorPicker({Name, Default, Flag, Callback})
	  AddTextbox({Name, Default, Placeholder, Numeric, MultiLine, ClearTextOnFocus, Flag, Callback})
	  AddKeybind({Name, Default, Mode = "Press"|"Toggle"|"Hold", Flag, Callback, OnChanged})
	  AddLabel(text)    AddParagraph({Title, Content})    AddDivider(text?)
	  Every element: :Set(value, silent) :Get() :SetTitle() :SetDescription() :SetVisible(bool) :Destroy()
	  Dropdown also :Refresh(options, keepValue) -> {droppedValues};  Button also :SetEnabled(bool) :SetText()

	THEMES (live)
	  UI:SetTheme("Midnight") or UI:SetTheme({Accent = Color3.fromRGB(...)})
	  UI:RegisterTheme(name, table)   UI:GetTheme()
	  Presets: Dark, Midnight, Light, Ocean, Rose, Mint, Amber
	  Keys: Background Surface SurfaceHover Stroke Text SubText Accent AccentText Success Warning Danger

	EXTRAS
	  UI:Notify({...})                      -- global toast, no window needed
	  UI:RegisterIcon(name, assetId)        -- then Icon = "name"
	  UI:ExportConfig() -> JSON string      UI:ImportConfig(json) -> true | false, reason
	  UI:SaveConfig(name) / LoadConfig(name) / ListConfigs()   -- need an executor with writefile
	  UI.Flags[flag] -> value               UI.Options[flag] -> element
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local Library = {
	Version = "1.1.0",
	Flags = {},
	Options = {},
	Windows = {},
	Themes = {},
	ThemeOrder = {},
	Icons = {},
	Theme = nil,
	ThemeName = "Dark",
	Font = Enum.Font.GothamMedium,
	FontBold = Enum.Font.GothamBold,
	ConfigFolder = "NicoTineModern",
	_binds = {},
	_guiCount = 0,
	_notifOrder = 0,
}

local Window = {}
Window.__index = Window
local Container = {}
Container.__index = Container
local Tab = setmetatable({}, { __index = Container })
Tab.__index = Tab
local Section = setmetatable({}, { __index = Container })
Section.__index = Section

--------------------------------------------------------------------------------
-- Small utilities
--------------------------------------------------------------------------------

local TI_FAST = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TI_MED = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TI_SLOW = TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local function tween(inst, info, props)
	local t = TweenService:Create(inst, info, props)
	t:Play()
	return t
end

local function copy(t)
	local o = {}
	for k, v in pairs(t) do
		o[k] = v
	end
	return o
end

local function cloneOpts(o)
	if type(o) == "string" then
		return { Name = o }
	end
	return copy(o or {})
end

local function safe(cb, ...)
	if type(cb) ~= "function" then
		return
	end
	local args = table.pack(...)
	task.spawn(function()
		local ok, err = pcall(cb, table.unpack(args, 1, args.n))
		if not ok then
			warn("[NicoTine] callback error: " .. tostring(err))
		end
	end)
end

local function viewport()
	local cam = workspace.CurrentCamera
	return cam and cam.ViewportSize or Vector2.new(1280, 720)
end

local function resolveIcon(icon)
	if icon == nil then
		return nil
	end
	if type(icon) == "number" then
		return "rbxassetid://" .. icon
	end
	if type(icon) == "string" then
		local reg = Library.Icons[icon]
		if reg ~= nil then
			return type(reg) == "number" and ("rbxassetid://" .. reg) or tostring(reg)
		end
		return icon
	end
	return nil
end

local function decimals(inc)
	local d = string.match(tostring(inc), "%.(%d+)")
	return d and #d or 0
end

local function snap(v, min, max, inc)
	inc = (inc and inc > 0) and inc or 1
	v = math.floor((v - min) / inc + 0.5) * inc + min
	v = tonumber(string.format("%." .. decimals(inc) .. "f", v)) or v
	return math.clamp(v, min, max)
end

local function toHex(c)
	return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function nextOrder(c)
	c._order = (c._order or 0) + 1
	return c._order
end

local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
	return c
end

local function pad(inst, t, r, b, l)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, t)
	p.PaddingRight = UDim.new(0, r)
	p.PaddingBottom = UDim.new(0, b)
	p.PaddingLeft = UDim.new(0, l)
	p.Parent = inst
	return p
end

local function layout(inst, dir, padding, ha, va)
	local l = Instance.new("UIListLayout")
	l.FillDirection = dir == "H" and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, padding or 0)
	if ha then
		l.HorizontalAlignment = ha
	end
	if va then
		l.VerticalAlignment = va
	end
	l.Parent = inst
	return l
end

local function isPress(i)
	return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
end

local function isMove(i)
	return i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch
end

-- A chevron drawn from two bars (no font or asset needed). Points down; use Rotation to turn it.
local function chevron(parent, bindFn, win)
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(12, 8)
	holder.Parent = parent
	for i = 1, 2 do
		local bar = win:_make("Frame", {
			Parent = holder,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(i == 1 and 3.5 or 8.5, 4),
			Size = UDim2.fromOffset(7, 2),
			Rotation = i == 1 and 45 or -45,
			BorderSizePixel = 0,
		}, { BackgroundColor3 = bindFn or "SubText" })
		corner(bar, 1)
	end
	return holder
end

--------------------------------------------------------------------------------
-- Themes
--------------------------------------------------------------------------------

local function C(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function addTheme(name, t)
	Library.Themes[name] = t
	if not table.find(Library.ThemeOrder, name) then
		table.insert(Library.ThemeOrder, name)
	end
end

addTheme("Dark", {
	Background = C(17, 17, 19), Surface = C(25, 25, 28), SurfaceHover = C(34, 34, 38), Stroke = C(42, 42, 47),
	Text = C(238, 238, 240), SubText = C(138, 138, 146), Accent = C(255, 145, 77), AccentText = C(30, 17, 6),
	Success = C(72, 199, 142), Warning = C(245, 181, 68), Danger = C(240, 98, 98),
})
addTheme("Midnight", {
	Background = C(10, 12, 20), Surface = C(17, 20, 32), SurfaceHover = C(26, 30, 47), Stroke = C(33, 38, 58),
	Text = C(230, 234, 245), SubText = C(124, 133, 160), Accent = C(56, 189, 248), AccentText = C(5, 20, 32),
	Success = C(72, 199, 142), Warning = C(245, 181, 68), Danger = C(240, 98, 98),
})
addTheme("Light", {
	Background = C(245, 246, 248), Surface = C(255, 255, 255), SurfaceHover = C(238, 240, 244), Stroke = C(224, 227, 233),
	Text = C(24, 27, 33), SubText = C(107, 114, 128), Accent = C(37, 99, 235), AccentText = C(255, 255, 255),
	Success = C(22, 163, 100), Warning = C(202, 138, 4), Danger = C(220, 60, 60),
})
addTheme("Ocean", {
	Background = C(11, 20, 26), Surface = C(16, 30, 39), SurfaceHover = C(23, 43, 55), Stroke = C(30, 56, 70),
	Text = C(226, 238, 244), SubText = C(120, 152, 168), Accent = C(20, 184, 166), AccentText = C(4, 26, 24),
	Success = C(72, 199, 142), Warning = C(245, 181, 68), Danger = C(240, 98, 98),
})
addTheme("Rose", {
	Background = C(22, 16, 19), Surface = C(32, 22, 27), SurfaceHover = C(44, 31, 37), Stroke = C(58, 40, 48),
	Text = C(244, 232, 236), SubText = C(160, 130, 140), Accent = C(244, 63, 94), AccentText = C(255, 255, 255),
	Success = C(72, 199, 142), Warning = C(245, 181, 68), Danger = C(255, 110, 110),
})
addTheme("Mint", {
	Background = C(14, 22, 19), Surface = C(20, 32, 27), SurfaceHover = C(28, 45, 38), Stroke = C(38, 60, 50),
	Text = C(230, 244, 237), SubText = C(122, 156, 138), Accent = C(52, 211, 153), AccentText = C(5, 28, 20),
	Success = C(72, 199, 142), Warning = C(245, 181, 68), Danger = C(240, 98, 98),
})
addTheme("Amber", {
	Background = C(22, 19, 14), Surface = C(32, 28, 20), SurfaceHover = C(44, 38, 27), Stroke = C(60, 52, 36),
	Text = C(245, 238, 225), SubText = C(160, 148, 122), Accent = C(245, 158, 11), AccentText = C(28, 18, 2),
	Success = C(72, 199, 142), Warning = C(245, 181, 68), Danger = C(240, 98, 98),
})

Library.Theme = copy(Library.Themes.Dark)

local function resolveKey(k)
	if type(k) == "function" then
		return k()
	end
	return k
end

function Library:RegisterTheme(name, t)
	local full = copy(self.Themes.Dark)
	for k, v in pairs(t) do
		if typeof(v) == "Color3" then
			full[k] = v
		end
	end
	addTheme(name, full)
end

function Library:GetTheme()
	return copy(self.Theme)
end

function Library:_bind(gui, inst, prop, key)
	table.insert(self._binds, { gui = gui, inst = inst, prop = prop, key = key })
	inst[prop] = self.Theme[resolveKey(key)]
end

function Library:_refresh(animate)
	local alive = {}
	for _, b in ipairs(self._binds) do
		if b.inst.Parent ~= nil and b.gui.Parent ~= nil and b.inst:IsDescendantOf(b.gui) then
			table.insert(alive, b)
			local target = self.Theme[resolveKey(b.key)]
			if target ~= nil then
				if animate then
					tween(b.inst, TI_MED, { [b.prop] = target })
				else
					b.inst[b.prop] = target
				end
			end
		end
	end
	self._binds = alive
end

function Library:SetTheme(arg)
	local t
	if type(arg) == "string" then
		local preset = self.Themes[arg]
		if not preset then
			warn("[NicoTine] unknown theme '" .. arg .. "'")
			return
		end
		t = copy(preset)
		self.ThemeName = arg
	elseif type(arg) == "table" then
		t = copy(self.Theme)
		for k, v in pairs(arg) do
			if typeof(v) == "Color3" and t[k] ~= nil then
				t[k] = v
			end
		end
		self.ThemeName = "Custom"
	else
		return
	end
	self.Theme = t
	self:_refresh(true)
end

function Library:RegisterIcon(name, id)
	self.Icons[name] = id
end

--------------------------------------------------------------------------------
-- GUI helpers
--------------------------------------------------------------------------------

function Library:_makeIn(gui, class, props, theme, children)
	local inst = Instance.new(class)
	local parent = nil
	for k, v in pairs(props or {}) do
		if k == "Parent" then
			parent = v
		else
			inst[k] = v
		end
	end
	for _, ch in ipairs(children or {}) do
		ch.Parent = inst
	end
	if theme then
		for prop, key in pairs(theme) do
			self:_bind(gui, inst, prop, key)
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Window:_make(class, props, theme, children)
	return Library:_makeIn(self.Gui, class, props, theme, children)
end

function Window:_stroke(inst, key)
	return self:_make("UIStroke", {
		Parent = inst, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, { Color = key or "Stroke" })
end

local function newGui(name, order)
	Library._guiCount = Library._guiCount + 1
	local g = Instance.new("ScreenGui")
	g.Name = name .. "_" .. Library._guiCount
	g.ResetOnSpawn = false
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.IgnoreGuiInset = true
	g.DisplayOrder = order or 999990
	g.OnTopOfCoreBlur = true
	return g
end

-- Rayfield-style parenting: protected containers first, PlayerGui as the fallback.
local function mount(gui, parent)
	if parent then
		gui.Parent = parent
		return
	end
	pcall(function()
		if typeof(gethui) == "function" then
			gui.Parent = gethui()
		elseif syn and syn.protect_gui then
			syn.protect_gui(gui)
			gui.Parent = game:GetService("CoreGui")
		else
			gui.Parent = game:GetService("CoreGui")
		end
	end)
	if gui.Parent == nil then
		gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	end
end

--------------------------------------------------------------------------------
-- Notifications (global, independent from windows)
--------------------------------------------------------------------------------

function Library:_notifHolder()
	if self._notifGui and self._notifGui.Parent ~= nil then
		return self._notifGui, self._notifHolderFrame
	end
	local gui = newGui("NicoTineToasts", 999999)
	mount(gui)
	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.AnchorPoint = Vector2.new(1, 1)
	holder.Position = UDim2.new(1, -16, 1, -16)
	holder.Size = UDim2.new(0, 300, 1, -32)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	layout(holder, "V", 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Bottom)
	self._notifGui = gui
	self._notifHolderFrame = holder
	return gui, holder
end

function Library:Notify(opts)
	opts = cloneOpts(opts)
	local gui, holder = self:_notifHolder()
	local kind = string.lower(opts.Type or "info")
	local colorKey = kind == "success" and "Success" or kind == "warning" and "Warning" or kind == "error" and "Danger" or "Accent"
	local duration = tonumber(opts.Duration) or 4
	self._notifOrder = self._notifOrder + 1

	local wrap = self:_makeIn(gui, "Frame", {
		Parent = holder, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, LayoutOrder = self._notifOrder,
	})
	local card = self:_makeIn(gui, "Frame", {
		Parent = wrap, Position = UDim2.fromOffset(330, 0), Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y, BorderSizePixel = 0,
	}, { BackgroundColor3 = "Surface" })
	corner(card, 10)
	self:_makeIn(gui, "UIStroke", { Parent = card, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, { Color = "Stroke" })
	local inner = Instance.new("Frame")
	inner.BackgroundTransparency = 1
	inner.Size = UDim2.new(1, 0, 0, 0)
	inner.AutomaticSize = Enum.AutomaticSize.Y
	inner.Parent = card
	pad(inner, 12, 14, 12, 14)
	layout(inner, "V", 5)

	local head = Instance.new("Frame")
	head.BackgroundTransparency = 1
	head.Size = UDim2.new(1, 0, 0, 18)
	head.LayoutOrder = 1
	head.Parent = inner
	layout(head, "H", 8, nil, Enum.VerticalAlignment.Center)
	local iconId = resolveIcon(opts.Icon)
	if iconId then
		self:_makeIn(gui, "ImageLabel", {
			Parent = head, Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, Image = iconId, LayoutOrder = 1,
		}, { ImageColor3 = colorKey })
	else
		local dot = self:_makeIn(gui, "Frame", {
			Parent = head, Size = UDim2.fromOffset(8, 8), BorderSizePixel = 0, LayoutOrder = 1,
		}, { BackgroundColor3 = colorKey })
		corner(dot, 4)
	end
	self:_makeIn(gui, "TextLabel", {
		Parent = head, Size = UDim2.new(1, -24, 1, 0), BackgroundTransparency = 1, Text = tostring(opts.Title or "Notification"),
		Font = self.FontBold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 2,
	}, { TextColor3 = "Text" })
	local body = opts.Content or opts.Text
	if body and body ~= "" then
		self:_makeIn(gui, "TextLabel", {
			Parent = inner, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
			Text = tostring(body), Font = self.Font, TextSize = 13, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top, LayoutOrder = 2,
		}, { TextColor3 = "SubText" })
	end
	local track = self:_makeIn(gui, "Frame", {
		Parent = inner, Size = UDim2.new(1, 0, 0, 3), BorderSizePixel = 0, LayoutOrder = 3,
	}, { BackgroundColor3 = "Stroke" })
	corner(track, 2)
	local fill = self:_makeIn(gui, "Frame", { Parent = track, Size = UDim2.fromScale(1, 1), BorderSizePixel = 0 }, { BackgroundColor3 = colorKey })
	corner(fill, 2)

	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		local t = tween(card, TI_MED, { Position = UDim2.fromOffset(330, 0) })
		t.Completed:Connect(function()
			wrap:Destroy()
		end)
	end
	local hit = Instance.new("TextButton")
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.fromScale(1, 1)
	hit.Text = ""
	hit.ZIndex = 5
	hit.Parent = card
	hit.MouseButton1Click:Connect(close)

	tween(card, TI_MED, { Position = UDim2.fromOffset(0, 0) })
	tween(fill, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) })
	task.delay(duration, close)
	return { Close = close }
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------

function Library:CreateWindow(config)
	config = config or {}
	local win = setmetatable({}, Window)
	win.Tabs = {}
	win._conns = {}
	win._query = ""
	win._tabOrder = 0
	win.Visible = true
	win.ToggleKey = config.ToggleKey or Enum.KeyCode.RightShift
	win.MinSize = config.MinSize or Vector2.new(440, 290)

	if config.Theme then
		self:SetTheme(config.Theme)
	end

	local gui = newGui("NicoTineModern", 999990)
	win.Gui = gui
	mount(gui, config.Parent)

	-- size: clamp to the screen, smaller default on touch devices
	local vp = viewport()
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local size = config.Size or (touchOnly and UDim2.fromOffset(520, 320) or UDim2.fromOffset(620, 420))
	local w = math.clamp(size.X.Offset + size.X.Scale * vp.X, win.MinSize.X, math.max(win.MinSize.X, vp.X - 24))
	local h = math.clamp(size.Y.Offset + size.Y.Scale * vp.Y, win.MinSize.Y, math.max(win.MinSize.Y, vp.Y - 24))
	local sidebarW = config.SidebarWidth or 160

	local root = win:_make("Frame", {
		Name = "Root", Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(w, h), BackgroundTransparency = 1,
	})
	win.Root = root
	local scale = Instance.new("UIScale")
	scale.Parent = root
	win._scale = scale

	win:_make("ImageLabel", {
		Parent = root, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 6), Size = UDim2.new(1, 56, 1, 56),
		BackgroundTransparency = 1, Image = "rbxassetid://6014261993", ImageColor3 = Color3.new(0, 0, 0), ImageTransparency = 0.55,
		ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(49, 49, 450, 450), ZIndex = 0,
	})

	local main = win:_make("CanvasGroup", {
		Name = "Main", Parent = root, Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, GroupTransparency = 1,
	}, { BackgroundColor3 = "Background" })
	corner(main, 10)
	win:_stroke(main)
	win.Main = main

	-- top bar --------------------------------------------------------------
	local top = win:_make("Frame", { Parent = main, Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1 })
	local drag = win:_make("TextButton", {
		Parent = top, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
	})
	local titleHolder = win:_make("Frame", {
		Parent = top, Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -110, 1, 0), BackgroundTransparency = 1,
	})
	layout(titleHolder, "H", 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local iconId = resolveIcon(config.Icon)
	if iconId then
		win:_make("ImageLabel", {
			Parent = titleHolder, Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 1, Image = iconId, LayoutOrder = 1,
		}, { ImageColor3 = "Accent" })
	end
	win._titleLabel = win:_make("TextLabel", {
		Parent = titleHolder, Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1,
		Text = tostring(config.Title or config.Name or "NicoTine"), Font = Library.FontBold, TextSize = 15, LayoutOrder = 2,
	}, { TextColor3 = "Text" })
	win._subLabel = win:_make("TextLabel", {
		Parent = titleHolder, Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1,
		Text = tostring(config.SubTitle or ""), Font = Library.Font, TextSize = 13, LayoutOrder = 3,
	}, { TextColor3 = "SubText" })

	local ctrls = win:_make("Frame", {
		Parent = top, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(64, 28),
		BackgroundTransparency = 1,
	})
	layout(ctrls, "H", 4, nil, Enum.VerticalAlignment.Center)
	local function ctrlButton(order, dangerHover)
		local b = win:_make("TextButton", {
			Parent = ctrls, Size = UDim2.fromOffset(30, 28), BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
			LayoutOrder = order, BorderSizePixel = 0,
		}, { BackgroundColor3 = dangerHover and "Danger" or "SurfaceHover" })
		corner(b, 7)
		b.MouseEnter:Connect(function()
			tween(b, TI_FAST, { BackgroundTransparency = dangerHover and 0.15 or 0 })
		end)
		b.MouseLeave:Connect(function()
			tween(b, TI_FAST, { BackgroundTransparency = 1 })
		end)
		return b
	end
	local minBtn = ctrlButton(1, false)
	local minBar = win:_make("Frame", {
		Parent = minBtn, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(11, 2),
		BorderSizePixel = 0,
	}, { BackgroundColor3 = "SubText" })
	corner(minBar, 1)
	local closeBtn = ctrlButton(2, true)
	for i = 1, 2 do
		local bar = win:_make("Frame", {
			Parent = closeBtn, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(13, 2),
			Rotation = i == 1 and 45 or -45, BorderSizePixel = 0,
		}, { BackgroundColor3 = "SubText" })
		corner(bar, 1)
	end
	win:_make("Frame", { Parent = main, Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0 }, { BackgroundColor3 = "Stroke" })

	-- sidebar + content ----------------------------------------------------
	local body = win:_make("Frame", { Parent = main, Position = UDim2.fromOffset(0, 47), Size = UDim2.new(1, 0, 1, -47), BackgroundTransparency = 1 })
	local sidebar = win:_make("Frame", { Parent = body, Size = UDim2.new(0, sidebarW, 1, 0), BackgroundTransparency = 1 })
	win:_make("Frame", { Parent = sidebar, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 1, 1, 0), BorderSizePixel = 0 }, { BackgroundColor3 = "Stroke" })

	local searchBox = win:_make("Frame", {
		Parent = sidebar, Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 0, 32), BorderSizePixel = 0,
	}, { BackgroundColor3 = "Surface" })
	corner(searchBox, 8)
	local searchStroke = win:_stroke(searchBox)
	local search = win:_make("TextBox", {
		Parent = searchBox, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), BackgroundTransparency = 1,
		Text = "", PlaceholderText = "Search", ClearTextOnFocus = false, Font = Library.Font, TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, { TextColor3 = "Text", PlaceholderColor3 = "SubText" })
	search.Focused:Connect(function()
		tween(searchStroke, TI_FAST, { Color = Library.Theme.Accent })
	end)
	search.FocusLost:Connect(function()
		tween(searchStroke, TI_FAST, { Color = Library.Theme.Stroke })
	end)
	search:GetPropertyChangedSignal("Text"):Connect(function()
		win._query = string.lower(search.Text)
		win:_Refilter()
	end)

	win.TabList = win:_make("ScrollingFrame", {
		Parent = sidebar, Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 1, -52), BackgroundTransparency = 1,
		BorderSizePixel = 0, ScrollBarThickness = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	})
	-- sliding highlight behind the active tab, then the holder that lays the tab buttons out
	win.Indicator = win:_make("Frame", {
		Parent = win.TabList, Size = UDim2.fromOffset(0, 34), BorderSizePixel = 0, BackgroundTransparency = 0.86, Visible = false,
	}, { BackgroundColor3 = "Accent" })
	corner(win.Indicator, 8)
	win:_make("UIStroke", { Parent = win.Indicator, Thickness = 1, Transparency = 0.72, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, { Color = "Accent" })
	win.TabHolder = win:_make("Frame", { Parent = win.TabList, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 })
	pad(win.TabHolder, 4, 10, 10, 10)
	layout(win.TabHolder, "V", 4)

	win.Content = win:_make("Frame", {
		Parent = body, Position = UDim2.fromOffset(sidebarW, 0), Size = UDim2.new(1, -sidebarW, 1, 0), BackgroundTransparency = 1,
		ClipsDescendants = true,
	})

	-- resize handle --------------------------------------------------------
	local grip = win:_make("TextButton", {
		Parent = main, AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(20, 20),
		BackgroundTransparency = 1, Text = "", ZIndex = 20,
	})
	for _, p in ipairs({ { 13, 5 }, { 9, 9 }, { 5, 13 }, { 13, 13 }, { 13, 9 }, { 9, 13 } }) do
		local d = win:_make("Frame", { Parent = grip, Position = UDim2.fromOffset(p[1], p[2]), Size = UDim2.fromOffset(2, 2), BorderSizePixel = 0, BackgroundTransparency = 0.4 }, { BackgroundColor3 = "SubText" })
		corner(d, 1)
	end

	-- popup layer ------------------------------------------------------------
	win.PopupLayer = win:_make("TextButton", {
		Parent = gui, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 100, Visible = false,
	})
	win.PopupLayer.MouseButton1Click:Connect(function()
		win:_ClosePopup()
	end)

	-- launcher pill ----------------------------------------------------------
	if config.Launcher ~= false then
		local pill = win:_make("TextButton", {
			Parent = gui, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -50), Size = UDim2.fromOffset(0, 34),
			AutomaticSize = Enum.AutomaticSize.X, Text = "", AutoButtonColor = false, BorderSizePixel = 0, Visible = false, ZIndex = 50,
		}, { BackgroundColor3 = "Surface" })
		corner(pill, 17)
		win:_stroke(pill)
		pad(pill, 0, 16, 0, 16)
		win:_make("TextLabel", {
			Parent = pill, Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1,
			Text = tostring(config.Title or config.Name or "NicoTine"), Font = Library.Font, TextSize = 13,
		}, { TextColor3 = "Text" })
		pill.MouseButton1Click:Connect(function()
			win:SetVisible(true)
		end)
		win._pill = pill
	end

	-- input: drag, resize, toggle key ----------------------------------------
	local dragging, dragStart, startPos = false, nil, nil
	drag.InputBegan:Connect(function(i)
		if isPress(i) then
			dragging, dragStart, startPos = true, i.Position, root.Position
		end
	end)
	local resizing, rStart, rSize, rPos = false, nil, nil, nil
	grip.InputBegan:Connect(function(i)
		if isPress(i) then
			resizing, rStart, rSize, rPos = true, i.Position, root.AbsoluteSize, root.Position
		end
	end)
	table.insert(win._conns, UserInputService.InputChanged:Connect(function(i)
		if not isMove(i) then
			return
		end
		local avp = gui.AbsoluteSize.X > 0 and gui.AbsoluteSize or viewport()
		if dragging then
			local d = i.Position - dragStart
			local x = math.clamp(startPos.X.Offset + d.X, -startPos.X.Scale * avp.X, (1 - startPos.X.Scale) * avp.X)
			local y = math.clamp(startPos.Y.Offset + d.Y, -startPos.Y.Scale * avp.Y, (1 - startPos.Y.Scale) * avp.Y)
			root.Position = UDim2.new(startPos.X.Scale, x, startPos.Y.Scale, y)
		elseif resizing then
			local d = i.Position - rStart
			local nw = math.clamp(rSize.X + d.X, win.MinSize.X, math.max(win.MinSize.X, avp.X - 12))
			local nh = math.clamp(rSize.Y + d.Y, win.MinSize.Y, math.max(win.MinSize.Y, avp.Y - 12))
			root.Size = UDim2.fromOffset(nw, nh)
			root.Position = UDim2.new(rPos.X.Scale, rPos.X.Offset + (nw - rSize.X) / 2, rPos.Y.Scale, rPos.Y.Offset + (nh - rSize.Y) / 2)
		end
	end))
	table.insert(win._conns, UserInputService.InputEnded:Connect(function(i)
		if isPress(i) then
			dragging, resizing = false, false
		end
	end))
	table.insert(win._conns, UserInputService.InputBegan:Connect(function(i, gp)
		if i.KeyCode == win.ToggleKey and not gp and not UserInputService:GetFocusedTextBox() then
			win:SetVisible(not win.Visible)
		end
	end))

	minBtn.MouseButton1Click:Connect(function()
		win:SetVisible(false)
	end)
	closeBtn.MouseButton1Click:Connect(function()
		if config.ConfirmClose then
			win:Dialog({
				Title = "Close window?",
				Content = "The interface will be removed until you run the script again.",
				Buttons = {
					{ Title = "Cancel" },
					{ Title = "Close", Primary = true, Callback = function()
						safe(config.OnClose)
						win:Destroy()
					end },
				},
			})
		else
			safe(config.OnClose)
			win:Destroy()
		end
	end)

	table.insert(self.Windows, win)

	-- open animation
	scale.Scale = 0.94
	tween(main, TI_MED, { GroupTransparency = 0 })
	tween(scale, TI_MED, { Scale = 1 })
	return win
end

function Window:SetVisible(v)
	v = v and true or false
	if v == self.Visible or not self.Root then
		return
	end
	self.Visible = v
	if v then
		self.Root.Visible = true
		self.Main.GroupTransparency = 1
		self._scale.Scale = 0.94
		tween(self.Main, TI_MED, { GroupTransparency = 0 })
		tween(self._scale, TI_MED, { Scale = 1 })
		if self._pill then
			local t = tween(self._pill, TI_MED, { Position = UDim2.new(0.5, 0, 0, -50) })
			t.Completed:Connect(function()
				if self.Visible and self._pill then
					self._pill.Visible = false
				end
			end)
		end
	else
		self:_ClosePopup()
		tween(self.Main, TI_FAST, { GroupTransparency = 1 })
		tween(self._scale, TI_FAST, { Scale = 0.94 })
		task.delay(0.17, function()
			if not self.Visible and self.Root and self.Root.Parent then
				self.Root.Visible = false
			end
		end)
		if self._pill then
			self._pill.Visible = true
			tween(self._pill, TI_MED, { Position = UDim2.new(0.5, 0, 0, 14) })
		end
	end
end

function Window:Toggle()
	self:SetVisible(not self.Visible)
end
Window.Minimize = function(self)
	self:SetVisible(false)
end

function Window:SetTitle(t)
	self._titleLabel.Text = tostring(t)
end

function Window:SetSubTitle(t)
	self._subLabel.Text = tostring(t)
end

function Window:Notify(opts)
	return Library:Notify(opts)
end

function Window:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	for _, c in ipairs(self._conns) do
		c:Disconnect()
	end
	local idx = table.find(Library.Windows, self)
	if idx then
		table.remove(Library.Windows, idx)
	end
	for flag, opt in pairs(Library.Options) do
		if opt.Window == self then
			Library.Options[flag] = nil
			Library.Flags[flag] = nil
		end
	end
	if self.Gui then
		self.Gui:Destroy()
	end
end

function Library:Destroy()
	for i = #self.Windows, 1, -1 do
		self.Windows[i]:Destroy()
	end
	if self._notifGui then
		self._notifGui:Destroy()
		self._notifGui = nil
	end
end

function Library:GetWindow(title)
	for _, w in ipairs(self.Windows) do
		if w._titleLabel and w._titleLabel.Text == title then
			return w
		end
	end
	return nil
end

-- popups ---------------------------------------------------------------------

function Window:_ClosePopup()
	local p = self._popup
	if not p then
		return
	end
	self._popup = nil
	if p.onClose then
		p.onClose()
	end
	local f = p.frame
	tween(f, TI_FAST, { GroupTransparency = 1 })
	task.delay(0.16, function()
		f:Destroy()
	end)
	if self.PopupLayer then
		self.PopupLayer.Visible = false
	end
end

function Window:_Popup(anchor, width, height, build, onClose)
	self:_ClosePopup()
	local layer = self.PopupLayer
	layer.Visible = true
	local pop = self:_make("CanvasGroup", {
		Parent = layer, Size = UDim2.fromOffset(width, height), BorderSizePixel = 0, GroupTransparency = 1, ZIndex = 101,
	}, { BackgroundColor3 = "Surface" })
	corner(pop, 10)
	self:_stroke(pop)
	local ap, as = anchor.AbsolutePosition, anchor.AbsoluteSize
	local vp = self.Gui.AbsoluteSize.X > 0 and self.Gui.AbsoluteSize or viewport()
	local x = math.clamp(ap.X + as.X - width, 8, math.max(8, vp.X - width - 8))
	local y = ap.Y + as.Y + 6
	local dir = 1
	if y + height > vp.Y - 8 then
		y = ap.Y - height - 6
		dir = -1
	end
	y = math.max(8, y)
	pop.Position = UDim2.fromOffset(x, y + 6 * dir)
	tween(pop, TI_FAST, { GroupTransparency = 0, Position = UDim2.fromOffset(x, y) })
	self._popup = { frame = pop, onClose = onClose }
	build(pop)
	return pop
end

-- dialog ---------------------------------------------------------------------

function Window:Dialog(opts)
	opts = cloneOpts(opts)
	local layer = self:_make("TextButton", {
		Parent = self.Gui, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1,
		Text = "", AutoButtonColor = false, ZIndex = 200,
	})
	tween(layer, TI_MED, { BackgroundTransparency = 0.5 })
	local card = self:_make("CanvasGroup", {
		Parent = layer, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(340, 0),
		AutomaticSize = Enum.AutomaticSize.Y, BorderSizePixel = 0, GroupTransparency = 1,
	}, { BackgroundColor3 = "Surface" })
	corner(card, 12)
	self:_stroke(card)
	local sc = Instance.new("UIScale")
	sc.Scale = 0.92
	sc.Parent = card
	tween(card, TI_MED, { GroupTransparency = 0 })
	tween(sc, TI_MED, { Scale = 1 })
	local inner = Instance.new("Frame")
	inner.BackgroundTransparency = 1
	inner.Size = UDim2.new(1, 0, 0, 0)
	inner.AutomaticSize = Enum.AutomaticSize.Y
	inner.Parent = card
	pad(inner, 18, 18, 16, 18)
	layout(inner, "V", 8)
	self:_make("TextLabel", {
		Parent = inner, Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Text = tostring(opts.Title or "Notice"),
		Font = Library.FontBold, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1,
	}, { TextColor3 = "Text" })
	if opts.Content and opts.Content ~= "" then
		self:_make("TextLabel", {
			Parent = inner, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
			Text = tostring(opts.Content), Font = Library.Font, TextSize = 13, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top, LayoutOrder = 2,
		}, { TextColor3 = "SubText" })
	end
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 40)
	row.LayoutOrder = 3
	row.Parent = inner
	layout(row, "H", 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Bottom)
	local function close()
		tween(layer, TI_FAST, { BackgroundTransparency = 1 })
		tween(card, TI_FAST, { GroupTransparency = 1 })
		tween(sc, TI_FAST, { Scale = 0.92 })
		task.delay(0.17, function()
			layer:Destroy()
		end)
	end
	local buttons = opts.Buttons or { { Title = "OK", Primary = true } }
	for i, b in ipairs(buttons) do
		local primary = b.Primary
		local btn = self:_make("TextButton", {
			Parent = row, Size = UDim2.fromOffset(0, 32), AutomaticSize = Enum.AutomaticSize.X, Text = "", AutoButtonColor = false,
			BorderSizePixel = 0, LayoutOrder = i,
		}, { BackgroundColor3 = primary and "Accent" or "SurfaceHover" })
		corner(btn, 8)
		pad(btn, 0, 16, 0, 16)
		self:_make("TextLabel", {
			Parent = btn, Size = UDim2.fromOffset(0, 32), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1,
			Text = tostring(b.Title or "OK"), Font = Library.Font, TextSize = 13,
		}, { TextColor3 = primary and "AccentText" or "Text" })
		btn.MouseButton1Click:Connect(function()
			close()
			safe(b.Callback)
		end)
	end
	return { Close = close }
end

-- search filter ----------------------------------------------------------------

local function applyFilter(item, q)
	local vis
	if item.children then
		local selfMatch = q == "" or string.find(item.text, q, 1, true) ~= nil
		local any = false
		for _, c in ipairs(item.children) do
			if applyFilter(c, selfMatch and "" or q) then
				any = true
			end
		end
		vis = selfMatch or any
	else
		vis = q == "" or string.find(item.text, q, 1, true) ~= nil
	end
	local show = vis and not item.hidden
	item.frame.Visible = show
	return show
end

function Window:_Refilter()
	for _, tab in ipairs(self.Tabs) do
		for _, item in ipairs(tab._items) do
			applyFilter(item, self._query)
		end
	end
end

-- tabs -------------------------------------------------------------------------

function Window:AddTabDivider(text)
	self._tabOrder = self._tabOrder + 1
	if text and text ~= "" then
		self:_make("TextLabel", {
			Parent = self.TabHolder, Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Text = string.upper(text),
			Font = Library.FontBold, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = self._tabOrder,
		}, { TextColor3 = "SubText" })
	else
		self:_make("Frame", { Parent = self.TabHolder, Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0, LayoutOrder = self._tabOrder }, { BackgroundColor3 = "Stroke" })
	end
end

function Window:AddTab(a, icon)
	local title = type(a) == "table" and (a.Title or a.Name) or tostring(a)
	if type(a) == "table" and a.Icon then
		icon = a.Icon
	end
	local win = self
	local tab = setmetatable({ Window = self, Title = title, _items = {}, _order = 0, Active = false }, Tab)
	self._tabOrder = self._tabOrder + 1

	local btn = self:_make("TextButton", {
		Parent = self.TabHolder, Size = UDim2.new(1, 0, 0, 34), Text = "", AutoButtonColor = false, BorderSizePixel = 0,
		BackgroundTransparency = 1, LayoutOrder = self._tabOrder,
	})
	local iconId = resolveIcon(icon)
	local iconLabel
	if iconId then
		iconLabel = self:_make("ImageLabel", {
			Parent = btn, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(18, 18),
			BackgroundTransparency = 1, Image = iconId,
		}, { ImageColor3 = function()
			return tab.Active and "Accent" or "SubText"
		end })
	end
	local label = self:_make("TextLabel", {
		Parent = btn, Position = UDim2.fromOffset(iconId and 38 or 14, 0), Size = UDim2.new(1, -(iconId and 46 or 22), 1, 0),
		BackgroundTransparency = 1, Text = title, Font = Library.Font, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, { TextColor3 = function()
		return tab.Active and "Accent" or "SubText"
	end })

	-- page = CanvasGroup (for the fade) around a ScrollingFrame (for the slide)
	local wrap = self:_make("CanvasGroup", {
		Parent = self.Content, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, GroupTransparency = 1, Visible = false,
	})
	local page = self:_make("ScrollingFrame", {
		Parent = wrap, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
	}, { ScrollBarImageColor3 = "Stroke" })
	pad(page, 12, 14, 14, 12)
	layout(page, "V", 10)
	tab.Page = wrap
	tab.Scroll = page
	tab.Content = page
	tab.Button = btn

	function tab:_SetActive(a)
		self.Active = a
		tween(label, TI_FAST, { TextColor3 = Library.Theme[a and "Accent" or "SubText"] })
		if iconLabel then
			tween(iconLabel, TI_FAST, { ImageColor3 = Library.Theme[a and "Accent" or "SubText"] })
		end
	end
	-- move the sliding highlight onto this tab
	function tab:_Place(animate)
		local tl, ind = win.TabList, win.Indicator
		if not btn.Parent or btn.AbsoluteSize.X <= 0 then
			return
		end
		local p = btn.AbsolutePosition - tl.AbsolutePosition + tl.CanvasPosition
		local pos = UDim2.fromOffset(p.X, p.Y)
		local size = UDim2.fromOffset(btn.AbsoluteSize.X, btn.AbsoluteSize.Y)
		ind.Visible = true
		if animate then
			tween(ind, TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = pos, Size = size })
		else
			ind.Position = pos
			ind.Size = size
		end
	end
	btn:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
		if win.CurrentTab == tab then
			tab:_Place(false)
		end
	end)
	btn.MouseEnter:Connect(function()
		if not tab.Active then
			tween(label, TI_FAST, { TextColor3 = Library.Theme.Text })
		end
	end)
	btn.MouseLeave:Connect(function()
		if not tab.Active then
			tween(label, TI_FAST, { TextColor3 = Library.Theme.SubText })
		end
	end)
	btn.MouseButton1Click:Connect(function()
		self:SelectTab(tab)
	end)

	table.insert(self.Tabs, tab)
	if #self.Tabs == 1 then
		self:SelectTab(tab)
	end
	return tab
end
Window.CreateTab = Window.AddTab

function Window:SelectTab(tab)
	if self.CurrentTab == tab then
		return
	end
	self:_ClosePopup()
	local first = self.CurrentTab == nil
	local prev = self.CurrentTab
	if prev then
		prev.Page.Visible = false
		prev:_SetActive(false)
	end
	self.CurrentTab = tab
	tab:_SetActive(true)
	tab:_Place(not first)
	tab.Page.GroupTransparency = 1
	tab.Scroll.Position = UDim2.fromOffset(0, 16)
	tab.Page.Visible = true
	tween(tab.Page, TI_MED, { GroupTransparency = 0 })
	tween(tab.Scroll, TI_MED, { Position = UDim2.fromOffset(0, 0) })
end

function Tab:Select()
	self.Window:SelectTab(self)
end

--------------------------------------------------------------------------------
-- Container: shared builders for Tab and Section
--------------------------------------------------------------------------------

-- A group is one bordered, rounded container; its rows are separated by 1px hairlines
-- (the gap between rows shows the container's Stroke color).
local function makeGroup(win, parent, order)
	local g = win:_make("CanvasGroup", {
		Parent = parent, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BorderSizePixel = 0, LayoutOrder = order,
	}, { BackgroundColor3 = "Stroke" })
	corner(g, 10)
	win:_stroke(g)
	layout(g, "V", 1)
	return g
end

local function rowOrder(c)
	c._rowOrder = (c._rowOrder or 0) + 1
	return c._rowOrder
end

-- where the next element goes: a Section's own group, or an implicit group inside a Tab
function Container:_Parent()
	if self._isSection then
		return self.Content, self._items
	end
	if not self._group then
		self._group = makeGroup(self.Window, self.Content, nextOrder(self))
		self._groupItems = {}
		self._rowOrder = 0
		table.insert(self._items, { frame = self._group, children = self._groupItems, hidden = false, text = "" })
	end
	return self._group, self._groupItems
end

local function newShell(self, horizontal)
	local win = self.Window
	local parent = self:_Parent()
	local outer = win:_make("Frame", {
		Parent = parent, Size = UDim2.new(1, 0, 0, 44), AutomaticSize = Enum.AutomaticSize.Y, BorderSizePixel = 0,
		LayoutOrder = rowOrder(self),
	}, { BackgroundColor3 = "Surface" })
	local inner = win:_make("TextButton", {
		Parent = outer, Size = UDim2.new(1, 0, 0, 44), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
		BorderSizePixel = 0, Text = "", AutoButtonColor = false,
	})
	pad(inner, 10, 14, 10, 14)
	layout(inner, horizontal and "H" or "V", horizontal and 12 or 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	-- primary buttons set the "Primary" attribute so hover uses the accent instead of the surface colors
	inner.MouseEnter:Connect(function()
		local p = outer:GetAttribute("Primary")
		tween(outer, TI_FAST, { BackgroundColor3 = p and Library.Theme.Accent:Lerp(Color3.new(1, 1, 1), 0.12) or Library.Theme.SurfaceHover })
	end)
	inner.MouseLeave:Connect(function()
		local p = outer:GetAttribute("Primary")
		tween(outer, TI_FAST, { BackgroundColor3 = p and Library.Theme.Accent or Library.Theme.Surface })
	end)
	return outer, inner
end

local function newText(win, parent, title, desc, width)
	local g = win:_make("Frame", {
		Parent = parent, BackgroundTransparency = 1, Size = width or UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1,
	})
	layout(g, "V", 2)
	local t = win:_make("TextLabel", {
		Parent = g, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), AutomaticSize = Enum.AutomaticSize.Y, Text = title,
		TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
		Font = Library.Font, TextSize = 14, LayoutOrder = 1,
	}, { TextColor3 = "Text" })
	local d = win:_make("TextLabel", {
		Parent = g, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = desc or "",
		TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		Font = Library.Font, TextSize = 12, LayoutOrder = 2, Visible = desc ~= nil and desc ~= "",
	}, { TextColor3 = "SubText" })
	return g, t, d
end

local function newRow(self, opts, ctrlW, ctrlH, stacked)
	local win = self.Window
	local outer, inner = newShell(self, not stacked)
	local title = tostring(opts.Name or opts.Title or "")
	local desc = opts.Description or opts.Desc
	local width = (not stacked and ctrlW > 0) and UDim2.new(1, -(ctrlW + 12), 0, 0) or UDim2.new(1, 0, 0, 0)
	local g, t, d = newText(win, inner, title, desc, width)
	local ctrl = nil
	if ctrlW > 0 or stacked then
		ctrl = win:_make("Frame", {
			Parent = inner, BackgroundTransparency = 1, LayoutOrder = 2,
			Size = stacked and UDim2.new(1, 0, 0, ctrlH) or UDim2.fromOffset(ctrlW, ctrlH),
		})
	end
	return { Row = outer, Inner = inner, Title = t, Desc = d, Ctrl = ctrl, Group = g }
end

local function listen(win, el, signal, fn)
	local c = signal:Connect(fn)
	table.insert(el._conns, c)
	table.insert(win._conns, c)
	return c
end

-- common element surface: flag registration, visibility, titles, destroy
local function finish(self, el, r, opts, kind)
	local win = self.Window
	el.Kind = kind
	el.Flag = opts.Flag
	el.Window = win
	el.Frame = r.Row
	local item = {
		frame = r.Row, hidden = false,
		text = string.lower(tostring(opts.Name or opts.Title or "") .. " " .. tostring(opts.Description or opts.Desc or "")),
	}
	local _, list = self:_Parent()
	table.insert(list, item)
	el._list = list
	function el:SetVisible(v)
		item.hidden = not v
		win:_Refilter()
	end
	function el:SetTitle(t)
		r.Title.Text = tostring(t)
		item.text = string.lower(tostring(t))
	end
	function el:SetDescription(t)
		r.Desc.Text = t and tostring(t) or ""
		r.Desc.Visible = t ~= nil and t ~= ""
	end
	function el:Destroy()
		if self._destroyed then
			return
		end
		self._destroyed = true
		for _, c in ipairs(self._conns) do
			c:Disconnect()
		end
		local idx = table.find(self._list, item)
		if idx then
			table.remove(self._list, idx)
		end
		if self.Flag and Library.Options[self.Flag] == self then
			Library.Options[self.Flag] = nil
			Library.Flags[self.Flag] = nil
		end
		r.Row:Destroy()
	end
	el.Container = self
	if opts.Flag then
		Library.Options[opts.Flag] = el
		Library.Flags[opts.Flag] = el:Get()
	end
	return el
end

local function setFlag(el, value)
	if el.Flag then
		Library.Flags[el.Flag] = value
	end
end

-- Section ----------------------------------------------------------------------

function Container:AddSection(a)
	local win = self.Window
	local title = type(a) == "table" and tostring(a.Title or a.Name or "Section") or tostring(a or "Section")
	local collapsible = not (type(a) == "table" and a.Collapsible == false)
	local collapsed = type(a) == "table" and a.Collapsed == true

	self._group = nil -- a section ends the implicit group of a tab
	local frame = win:_make("Frame", {
		Parent = self.Content, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
		LayoutOrder = nextOrder(self),
	})
	layout(frame, "V", 6)
	local header = win:_make("TextButton", {
		Parent = frame, Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, LayoutOrder = 1,
	})
	win:_make("TextLabel", {
		Parent = header, Position = UDim2.fromOffset(2, 0), Size = UDim2.new(1, -28, 1, 0), BackgroundTransparency = 1,
		Text = title, Font = Library.FontBold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
	}, { TextColor3 = "Text" })
	local arrow
	if collapsible then
		arrow = chevron(header, "SubText", win)
		arrow.AnchorPoint = Vector2.new(1, 0.5)
		arrow.Position = UDim2.new(1, -4, 0.5, 0)
	end
	local content = makeGroup(win, frame, 2)

	local sec = setmetatable({ Window = win, Title = title, Content = content, Frame = frame, _items = {}, _order = 0, _rowOrder = 0, _isSection = true, Tab = self.Tab or self }, Section)
	sec.Collapsed = collapsed
	local function apply()
		content.Visible = not sec.Collapsed
		if arrow then
			tween(arrow, TI_FAST, { Rotation = sec.Collapsed and -90 or 0 })
		end
	end
	apply()
	if collapsible then
		header.MouseButton1Click:Connect(function()
			sec.Collapsed = not sec.Collapsed
			apply()
		end)
	end
	function sec:SetCollapsed(c)
		self.Collapsed = c and true or false
		apply()
	end
	table.insert(self._items, { frame = frame, children = sec._items, hidden = false, text = string.lower(title) })
	return sec
end
Container.CreateSection = Container.AddSection

-- Toggle -----------------------------------------------------------------------

function Container:AddToggle(opts)
	opts = cloneOpts(opts)
	local win = self.Window
	local r = newRow(self, opts, 44, 24)
	local value = opts.Default == true
	local el = { _conns = {} }

	local track = win:_make("TextButton", {
		Parent = r.Ctrl, Size = UDim2.fromOffset(44, 24), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
		Text = "", AutoButtonColor = false, BorderSizePixel = 0,
	}, { BackgroundColor3 = function()
		return value and "Accent" or "Stroke"
	end })
	corner(track, 12)
	local knob = win:_make("Frame", {
		Parent = track, AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(18, 18), BorderSizePixel = 0,
		Position = UDim2.new(0, value and 23 or 3, 0.5, 0),
	}, { BackgroundColor3 = function()
		return value and "AccentText" or "SubText"
	end })
	corner(knob, 9)

	local function render()
		tween(track, TI_FAST, { BackgroundColor3 = Library.Theme[value and "Accent" or "Stroke"] })
		tween(knob, TI_FAST, {
			Position = UDim2.new(0, value and 23 or 3, 0.5, 0),
			BackgroundColor3 = Library.Theme[value and "AccentText" or "SubText"],
		})
	end
	local function set(v, silent)
		v = v and true or false
		if v == value then
			return
		end
		value = v
		render()
		setFlag(el, value)
		if not silent then
			safe(opts.Callback, value)
		end
	end
	function el:Set(v, silent)
		set(v, silent)
	end
	function el:Get()
		return value
	end
	listen(win, el, r.Inner.MouseButton1Click, function()
		set(not value)
	end)
	listen(win, el, track.MouseButton1Click, function()
		set(not value)
	end)
	return finish(self, el, r, opts, "boolean")
end

-- Slider -----------------------------------------------------------------------

function Container:AddSlider(opts)
	opts = cloneOpts(opts)
	local win = self.Window
	local outer, inner = newShell(self, false)
	local title = tostring(opts.Name or opts.Title or "")
	local min, max = tonumber(opts.Min) or 0, tonumber(opts.Max) or 100
	if max <= min then
		max = min + 1
	end
	local inc = tonumber(opts.Increment) or 1
	local suffix = opts.Suffix and tostring(opts.Suffix) or ""
	local dec = decimals(inc > 0 and inc or 1)
	local value = snap(tonumber(opts.Default) or min, min, max, inc)
	local el = { _conns = {} }

	local head = win:_make("Frame", { Parent = inner, Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, LayoutOrder = 1 })
	local titleLabel = win:_make("TextLabel", {
		Parent = head, Size = UDim2.new(1, -70, 1, 0), BackgroundTransparency = 1, Text = title, Font = Library.Font, TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	}, { TextColor3 = "Text" })
	local valueLabel = win:_make("TextLabel", {
		Parent = head, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(70, 18),
		BackgroundTransparency = 1, Font = Library.Font, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right,
	}, { TextColor3 = "SubText" })
	local desc = opts.Description or opts.Desc
	local descLabel = win:_make("TextLabel", {
		Parent = inner, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Text = desc or "",
		TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Font = Library.Font,
		TextSize = 12, LayoutOrder = 2, Visible = desc ~= nil and desc ~= "",
	}, { TextColor3 = "SubText" })
	local hit = win:_make("TextButton", {
		Parent = inner, Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, LayoutOrder = 3,
	})
	local bar = win:_make("Frame", {
		Parent = hit, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(1, 0, 0, 6), BorderSizePixel = 0,
	}, { BackgroundColor3 = "Stroke" })
	corner(bar, 3)
	local fill = win:_make("Frame", { Parent = bar, Size = UDim2.fromScale(0, 1), BorderSizePixel = 0 }, { BackgroundColor3 = "Accent" })
	corner(fill, 3)
	local knob = win:_make("Frame", {
		Parent = bar, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(14, 14), BorderSizePixel = 0,
	}, { BackgroundColor3 = "AccentText" })
	corner(knob, 7)
	win:_make("UIStroke", { Parent = knob, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, { Color = "Accent" })

	local function render(animate)
		local f = (value - min) / (max - min)
		valueLabel.Text = string.format("%." .. dec .. "f", value) .. suffix
		local info = animate and TweenInfo.new(0.08, Enum.EasingStyle.Quad) or TweenInfo.new(0)
		tween(fill, info, { Size = UDim2.fromScale(f, 1) })
		tween(knob, info, { Position = UDim2.fromScale(f, 0.5) })
	end
	local function apply(v, silent)
		v = snap(v, min, max, inc)
		if v == value then
			return
		end
		value = v
		render(true)
		setFlag(el, value)
		if not silent then
			safe(opts.Callback, value)
		end
	end
	render(false)

	local dragging = false
	local function fromX(x)
		local rel = math.clamp((x - bar.AbsolutePosition.X) / math.max(1, bar.AbsoluteSize.X), 0, 1)
		apply(min + (max - min) * rel)
	end
	listen(win, el, hit.InputBegan, function(i)
		if isPress(i) then
			dragging = true
			fromX(i.Position.X)
		end
	end)
	listen(win, el, UserInputService.InputChanged, function(i)
		if dragging and isMove(i) then
			fromX(i.Position.X)
		end
	end)
	listen(win, el, UserInputService.InputEnded, function(i)
		if isPress(i) then
			dragging = false
		end
	end)

	function el:Set(v, silent)
		if tonumber(v) then
			apply(tonumber(v), silent)
		end
	end
	function el:Get()
		return value
	end
	function el:SetMin(n)
		min = n
		if max <= min then
			max = min + 1
		end
		value = snap(value, min, max, inc)
		render(false)
		setFlag(el, value)
	end
	function el:SetMax(n)
		max = n
		if max <= min then
			min = max - 1
		end
		value = snap(value, min, max, inc)
		render(false)
		setFlag(el, value)
	end
	-- the shared surface expects r.Title / r.Desc
	local r = { Row = outer, Title = titleLabel, Desc = descLabel }
	return finish(self, el, r, opts, "number")
end

-- Dropdown ---------------------------------------------------------------------

function Container:AddDropdown(opts)
	opts = cloneOpts(opts)
	local win = self.Window
	local r = newRow(self, opts, 150, 30)
	local multi = opts.Multi == true
	local searchable = opts.Searchable == true
	local options = {}
	for _, o in ipairs(opts.Options or opts.Values or {}) do
		table.insert(options, tostring(o))
	end
	local selected = {} -- name -> true
	local single = nil
	local el = { _conns = {} }

	local function applyDefault(d)
		selected, single = {}, nil
		if multi then
			if type(d) == "table" then
				for _, v in ipairs(d) do
					if table.find(options, tostring(v)) then
						selected[tostring(v)] = true
					end
				end
			end
		elseif d ~= nil and table.find(options, tostring(d)) then
			single = tostring(d)
		end
	end
	applyDefault(opts.Default)

	local btn = win:_make("TextButton", {
		Parent = r.Ctrl, Size = UDim2.fromScale(1, 1), Text = "", AutoButtonColor = false, BorderSizePixel = 0,
	}, { BackgroundColor3 = "Background" })
	corner(btn, 7)
	local btnStroke = win:_stroke(btn)
	local label = win:_make("TextLabel", {
		Parent = btn, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -30, 1, 0), BackgroundTransparency = 1, Font = Library.Font,
		TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	}, { TextColor3 = "Text" })
	local arrow = chevron(btn, "SubText", win)
	arrow.AnchorPoint = Vector2.new(1, 0.5)
	arrow.Position = UDim2.new(1, -9, 0.5, 0)

	local function getValue()
		if multi then
			local out = {}
			for _, o in ipairs(options) do
				if selected[o] then
					table.insert(out, o)
				end
			end
			return out
		end
		return single
	end
	local function display()
		if multi then
			local v = getValue()
			label.Text = #v > 0 and table.concat(v, ", ") or "None"
		else
			label.Text = single or "None"
		end
	end
	display()

	local function commit(silent)
		display()
		local v = getValue()
		setFlag(el, v)
		if not silent then
			safe(opts.Callback, v)
		end
	end

	local function open()
		local rowH = 28
		local searchH = searchable and 40 or 0
		local h = math.min(#options * rowH + 10, 200) + searchH
		local filter = ""
		local list
		local function render()
			for _, ch in ipairs(list:GetChildren()) do
				if ch:IsA("TextButton") then
					ch:Destroy()
				end
			end
			for i, o in ipairs(options) do
				if filter == "" or string.find(string.lower(o), filter, 1, true) then
					local on = multi and selected[o] or (not multi and single == o)
					local item = win:_make("TextButton", {
						Parent = list, Size = UDim2.new(1, 0, 0, 26), Text = "", AutoButtonColor = false, BorderSizePixel = 0,
						BackgroundTransparency = 1, LayoutOrder = i,
					}, { BackgroundColor3 = "SurfaceHover" })
					corner(item, 6)
					win:_make("TextLabel", {
						Parent = item, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -30, 1, 0), BackgroundTransparency = 1, Text = o,
						Font = Library.Font, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
					}, { TextColor3 = on and "Accent" or "Text" })
					if on then
						local dot = win:_make("Frame", {
							Parent = item, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(6, 6), BorderSizePixel = 0,
						}, { BackgroundColor3 = "Accent" })
						corner(dot, 3)
					end
					item.MouseEnter:Connect(function()
						tween(item, TI_FAST, { BackgroundTransparency = 0.3 })
					end)
					item.MouseLeave:Connect(function()
						tween(item, TI_FAST, { BackgroundTransparency = 1 })
					end)
					item.MouseButton1Click:Connect(function()
						if multi then
							selected[o] = not selected[o] or nil
							commit(false)
							render()
						else
							single = o
							commit(false)
							win:_ClosePopup()
						end
					end)
				end
			end
		end
		tween(arrow, TI_FAST, { Rotation = 180 })
		tween(btnStroke, TI_FAST, { Color = Library.Theme.Accent })
		win:_Popup(btn, math.max(btn.AbsoluteSize.X, 170), math.max(h, 48), function(pop)
			if searchable then
				local box = win:_make("Frame", { Parent = pop, Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, 26), BorderSizePixel = 0 }, { BackgroundColor3 = "Background" })
				corner(box, 6)
				win:_stroke(box)
				local tb = win:_make("TextBox", {
					Parent = box, Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -16, 1, 0), BackgroundTransparency = 1, Text = "",
					PlaceholderText = "Search...", ClearTextOnFocus = false, Font = Library.Font, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
				}, { TextColor3 = "Text", PlaceholderColor3 = "SubText" })
				tb:GetPropertyChangedSignal("Text"):Connect(function()
					filter = string.lower(tb.Text)
					render()
				end)
			end
			list = win:_make("ScrollingFrame", {
				Parent = pop, Position = UDim2.fromOffset(0, searchH), Size = UDim2.new(1, 0, 1, -searchH), BackgroundTransparency = 1,
				BorderSizePixel = 0, ScrollBarThickness = 3, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
			}, { ScrollBarImageColor3 = "Stroke" })
			pad(list, 5, 5, 5, 5)
			layout(list, "V", 2)
			render()
		end, function()
			if arrow.Parent then
				tween(arrow, TI_FAST, { Rotation = 0 })
				tween(btnStroke, TI_FAST, { Color = Library.Theme.Stroke })
			end
		end)
	end
	listen(win, el, btn.MouseButton1Click, open)

	function el:Set(v, silent)
		applyDefault(v)
		commit(silent)
	end
	function el:Get()
		return getValue()
	end
	function el:Refresh(newOptions, keepValue)
		local prev = multi and getValue() or (single and { single } or {})
		options = {}
		for _, o in ipairs(newOptions or {}) do
			table.insert(options, tostring(o))
		end
		local dropped = {}
		for _, p in ipairs(prev) do
			if not table.find(options, p) then
				table.insert(dropped, p)
			end
		end
		if keepValue then
			local keep = {}
			for _, p in ipairs(prev) do
				if table.find(options, p) then
					table.insert(keep, p)
				end
			end
			applyDefault(multi and keep or keep[1])
		else
			applyDefault(nil)
		end
		commit(false)
		return dropped
	end
	return finish(self, el, r, opts, "dropdown")
end

-- Button -----------------------------------------------------------------------

function Container:AddButton(opts)
	opts = cloneOpts(opts)
	local win = self.Window
	local primary = opts.Variant == "Primary" or opts.Primary == true
	local r = newRow(self, opts, 14, 10)
	local el = { _conns = {} }
	local enabled = true

	local arrow = chevron(r.Ctrl, primary and "AccentText" or "SubText", win)
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Position = UDim2.fromScale(0.5, 0.5)
	arrow.Rotation = -90
	if primary then
		r.Row:SetAttribute("Primary", true)
		win:_bindPrimary(r)
	end
	listen(win, el, r.Inner.MouseButton1Click, function()
		if not enabled then
			return
		end
		local from = primary and Library.Theme.Accent:Lerp(Color3.new(1, 1, 1), 0.2) or Library.Theme.Accent
		r.Row.BackgroundColor3 = from
		tween(r.Row, TI_SLOW, { BackgroundColor3 = primary and Library.Theme.Accent or Library.Theme.SurfaceHover })
		safe(opts.Callback)
	end)
	function el:Set() end
	function el:Get()
		return nil
	end
	function el:SetText(t)
		self:SetTitle(t)
	end
	function el:SetEnabled(b)
		enabled = b and true or false
		tween(r.Row, TI_FAST, { BackgroundTransparency = enabled and 0 or 0.5 })
		tween(r.Title, TI_FAST, { TextTransparency = enabled and 0 or 0.5 })
	end
	return finish(self, el, r, opts, "button")
end

function Window:_bindPrimary(r)
	Library:_bind(self.Gui, r.Row, "BackgroundColor3", "Accent")
	Library:_bind(self.Gui, r.Title, "TextColor3", "AccentText")
end

-- Color picker -----------------------------------------------------------------

function Container:AddColorPicker(opts)
	opts = cloneOpts(opts)
	local win = self.Window
	local r = newRow(self, opts, 44, 26)
	local el = { _conns = {} }
	local value = typeof(opts.Default) == "Color3" and opts.Default or Color3.fromRGB(255, 255, 255)
	local h, s, v = value:ToHSV()
	local redraw = nil

	local swatch = win:_make("TextButton", {
		Parent = r.Ctrl, Size = UDim2.fromScale(1, 1), Text = "", AutoButtonColor = false, BorderSizePixel = 0, BackgroundColor3 = value,
	})
	corner(swatch, 7)
	win:_stroke(swatch)

	local function commit(silent)
		value = Color3.fromHSV(h, s, v)
		swatch.BackgroundColor3 = value
		setFlag(el, value)
		if redraw then
			redraw()
		end
		if not silent then
			safe(opts.Callback, value)
		end
	end

	local function open()
		local conns = {}
		win:_Popup(swatch, 224, 206, function(pop)
			local svBox = Instance.new("Frame")
			svBox.Position = UDim2.fromOffset(12, 12)
			svBox.Size = UDim2.new(1, -24, 0, 120)
			svBox.BorderSizePixel = 0
			svBox.Parent = pop
			corner(svBox, 6)
			local white = Instance.new("Frame")
			white.Size = UDim2.fromScale(1, 1)
			white.BorderSizePixel = 0
			white.BackgroundColor3 = Color3.new(1, 1, 1)
			white.Parent = svBox
			corner(white, 6)
			local g1 = Instance.new("UIGradient")
			g1.Transparency = NumberSequence.new(0, 1)
			g1.Parent = white
			local black = Instance.new("Frame")
			black.Size = UDim2.fromScale(1, 1)
			black.BorderSizePixel = 0
			black.BackgroundColor3 = Color3.new(0, 0, 0)
			black.Parent = svBox
			corner(black, 6)
			local g2 = Instance.new("UIGradient")
			g2.Rotation = 90
			g2.Transparency = NumberSequence.new(1, 0)
			g2.Parent = black
			local svHit = Instance.new("TextButton")
			svHit.Size = UDim2.fromScale(1, 1)
			svHit.BackgroundTransparency = 1
			svHit.Text = ""
			svHit.ZIndex = 3
			svHit.Parent = svBox
			local svCur = Instance.new("Frame")
			svCur.AnchorPoint = Vector2.new(0.5, 0.5)
			svCur.Size = UDim2.fromOffset(12, 12)
			svCur.BackgroundTransparency = 1
			svCur.ZIndex = 4
			svCur.Parent = svBox
			corner(svCur, 6)
			local st = Instance.new("UIStroke")
			st.Color = Color3.new(1, 1, 1)
			st.Thickness = 2
			st.Parent = svCur

			local hueBar = Instance.new("Frame")
			hueBar.Position = UDim2.fromOffset(12, 142)
			hueBar.Size = UDim2.new(1, -24, 0, 14)
			hueBar.BorderSizePixel = 0
			hueBar.BackgroundColor3 = Color3.new(1, 1, 1)
			hueBar.Parent = pop
			corner(hueBar, 7)
			local pts = {}
			for i = 0, 6 do
				table.insert(pts, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6 >= 1 and 0.999 or i / 6, 1, 1)))
			end
			local g3 = Instance.new("UIGradient")
			g3.Color = ColorSequence.new(pts)
			g3.Parent = hueBar
			local hueHit = Instance.new("TextButton")
			hueHit.Size = UDim2.fromScale(1, 1)
			hueHit.BackgroundTransparency = 1
			hueHit.Text = ""
			hueHit.ZIndex = 3
			hueHit.Parent = hueBar
			local hueCur = Instance.new("Frame")
			hueCur.AnchorPoint = Vector2.new(0.5, 0.5)
			hueCur.Size = UDim2.new(0, 6, 1, 6)
			hueCur.BackgroundColor3 = Color3.new(1, 1, 1)
			hueCur.BorderSizePixel = 0
			hueCur.ZIndex = 4
			hueCur.Parent = hueBar
			corner(hueCur, 3)
			local hst = Instance.new("UIStroke")
			hst.Color = Color3.new(0, 0, 0)
			hst.Transparency = 0.6
			hst.Parent = hueCur

			local hexBox = win:_make("TextBox", {
				Parent = pop, Position = UDim2.fromOffset(12, 166), Size = UDim2.new(1, -24, 0, 28), BorderSizePixel = 0, Text = "",
				ClearTextOnFocus = false, Font = Library.Font, TextSize = 13,
			}, { BackgroundColor3 = "Background", TextColor3 = "Text" })
			corner(hexBox, 6)
			win:_stroke(hexBox)

			redraw = function()
				svBox.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
				svCur.Position = UDim2.fromScale(s, 1 - v)
				hueCur.Position = UDim2.fromScale(h, 0.5)
				if not hexBox:IsFocused() then
					hexBox.Text = toHex(value)
				end
			end
			redraw()

			local dragSV, dragHue = false, false
			local function svFrom(p)
				s = math.clamp((p.X - svBox.AbsolutePosition.X) / math.max(1, svBox.AbsoluteSize.X), 0, 1)
				v = 1 - math.clamp((p.Y - svBox.AbsolutePosition.Y) / math.max(1, svBox.AbsoluteSize.Y), 0, 1)
				commit(false)
			end
			local function hueFrom(p)
				h = math.clamp((p.X - hueBar.AbsolutePosition.X) / math.max(1, hueBar.AbsoluteSize.X), 0, 1)
				commit(false)
			end
			svHit.InputBegan:Connect(function(i)
				if isPress(i) then
					dragSV = true
					svFrom(i.Position)
				end
			end)
			hueHit.InputBegan:Connect(function(i)
				if isPress(i) then
					dragHue = true
					hueFrom(i.Position)
				end
			end)
			table.insert(conns, UserInputService.InputChanged:Connect(function(i)
				if isMove(i) then
					if dragSV then
						svFrom(i.Position)
					elseif dragHue then
						hueFrom(i.Position)
					end
				end
			end))
			table.insert(conns, UserInputService.InputEnded:Connect(function(i)
				if isPress(i) then
					dragSV, dragHue = false, false
				end
			end))
			hexBox.FocusLost:Connect(function()
				local hex = string.match(hexBox.Text, "^#?(%x%x%x%x%x%x)$")
				if hex then
					local c = Color3.fromRGB(tonumber(string.sub(hex, 1, 2), 16), tonumber(string.sub(hex, 3, 4), 16), tonumber(string.sub(hex, 5, 6), 16))
					h, s, v = c:ToHSV()
					commit(false)
				else
					hexBox.Text = toHex(value)
				end
			end)
		end, function()
			redraw = nil
			for _, c in ipairs(conns) do
				c:Disconnect()
			end
		end)
	end
	listen(win, el, swatch.MouseButton1Click, open)
	listen(win, el, r.Inner.MouseButton1Click, open)

	function el:Set(c, silent)
		if typeof(c) == "Color3" then
			h, s, v = c:ToHSV()
			commit(silent)
		end
	end
	function el:Get()
		return value
	end
	return finish(self, el, r, opts, "color")
end

-- Textbox ----------------------------------------------------------------------

function Container:AddTextbox(opts)
	opts = cloneOpts(opts)
	local win = self.Window
	local multiLine = opts.MultiLine == true
	local numeric = opts.Numeric == true
	local r
	if multiLine then
		r = newRow(self, opts, 0, 76, true)
	else
		r = newRow(self, opts, 170, 30)
	end
	local el = { _conns = {} }
	local value = opts.Default ~= nil and tostring(opts.Default) or ""
	if numeric then
		value = tonumber(value) or 0
	end

	local box = win:_make("Frame", { Parent = r.Ctrl, Size = UDim2.fromScale(1, 1), BorderSizePixel = 0 }, { BackgroundColor3 = "Background" })
	corner(box, 7)
	local stroke = win:_stroke(box)
	local tb = win:_make("TextBox", {
		Parent = box, Position = UDim2.fromOffset(10, multiLine and 6 or 0), Size = UDim2.new(1, -20, 1, multiLine and -12 or 0), BackgroundTransparency = 1,
		Text = tostring(value), PlaceholderText = tostring(opts.Placeholder or ""), ClearTextOnFocus = opts.ClearTextOnFocus == true,
		Font = Library.Font, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, MultiLine = multiLine, TextWrapped = multiLine,
		TextYAlignment = multiLine and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center, TextTruncate = Enum.TextTruncate.None,
	}, { TextColor3 = "Text", PlaceholderColor3 = "SubText" })

	listen(win, el, tb.Focused, function()
		tween(stroke, TI_FAST, { Color = Library.Theme.Accent })
	end)
	listen(win, el, tb.FocusLost, function(enter)
		tween(stroke, TI_FAST, { Color = Library.Theme.Stroke })
		if numeric then
			local n = tonumber(tb.Text)
			if n then
				value = n
			else
				stroke.Color = Library.Theme.Danger
				tween(stroke, TweenInfo.new(0.4), { Color = Library.Theme.Stroke })
				tb.Text = tostring(value)
				return
			end
		else
			value = tb.Text
		end
		setFlag(el, value)
		safe(opts.Callback, value, enter)
	end)

	function el:Set(x, silent)
		if numeric then
			x = tonumber(x)
			if not x then
				return
			end
		else
			x = tostring(x or "")
		end
		value = x
		tb.Text = tostring(x)
		setFlag(el, value)
		if not silent then
			safe(opts.Callback, value, false)
		end
	end
	function el:Get()
		return value
	end
	listen(win, el, r.Inner.MouseButton1Click, function()
		tb:CaptureFocus()
	end)
	return finish(self, el, r, opts, numeric and "number" or "string")
end

-- Keybind ----------------------------------------------------------------------

function Container:AddKeybind(opts)
	opts = cloneOpts(opts)
	local win = self.Window
	local r = newRow(self, opts, 90, 28)
	local el = { _conns = {} }
	local mode = opts.Mode or "Press"
	local key = typeof(opts.Default) == "EnumItem" and opts.Default or nil
	local state = false
	local listening = false

	local btn = win:_make("TextButton", {
		Parent = r.Ctrl, Size = UDim2.fromScale(1, 1), Text = "", AutoButtonColor = false, BorderSizePixel = 0,
	}, { BackgroundColor3 = "Background" })
	corner(btn, 7)
	local stroke = win:_stroke(btn)
	local label = win:_make("TextLabel", {
		Parent = btn, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Library.Font, TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, { TextColor3 = "Text" })
	local function display()
		label.Text = listening and "..." or (key and key.Name or "None")
		tween(stroke, TI_FAST, { Color = listening and Library.Theme.Accent or Library.Theme.Stroke })
	end
	display()

	local function setKey(k, silent)
		key = k
		listening = false
		display()
		setFlag(el, key)
		if not silent then
			safe(opts.OnChanged, key)
		end
	end
	listen(win, el, btn.MouseButton1Click, function()
		listening = true
		display()
	end)
	listen(win, el, btn.MouseButton2Click, function()
		setKey(nil)
	end)
	listen(win, el, UserInputService.InputBegan, function(i, gp)
		if listening then
			if i.UserInputType == Enum.UserInputType.Keyboard then
				if i.KeyCode == Enum.KeyCode.Escape then
					listening = false
					display()
				elseif i.KeyCode == Enum.KeyCode.Backspace then
					setKey(nil)
				else
					setKey(i.KeyCode)
				end
			end
			return
		end
		if gp or not key or i.KeyCode ~= key or UserInputService:GetFocusedTextBox() then
			return
		end
		if mode == "Toggle" then
			state = not state
			safe(opts.Callback, state)
		elseif mode == "Hold" then
			state = true
			safe(opts.Callback, true)
		else
			safe(opts.Callback, true)
		end
	end)
	listen(win, el, UserInputService.InputEnded, function(i)
		if mode == "Hold" and key and i.KeyCode == key and state then
			state = false
			safe(opts.Callback, false)
		end
	end)

	function el:Set(k, silent)
		if typeof(k) == "EnumItem" or k == nil then
			setKey(k, silent)
		elseif type(k) == "string" then
			local ok, e = pcall(function()
				return Enum.KeyCode[k]
			end)
			if ok and e then
				setKey(e, silent)
			end
		end
	end
	function el:Get()
		return key
	end
	function el:GetState()
		return state
	end
	return finish(self, el, r, opts, "keybind")
end

-- Label / Paragraph / Divider --------------------------------------------------

function Container:AddLabel(a)
	local opts = type(a) == "table" and cloneOpts(a) or { Name = tostring(a or "") }
	local r = newRow(self, opts, 0, 0)
	local el = { _conns = {} }
	r.Title.TextSize = 13
	self.Window:_bindSub(r.Title)
	function el:SetText(t)
		self:SetTitle(t)
	end
	function el:SetColor(c)
		r.Title.TextColor3 = c
	end
	function el:Set(t)
		self:SetTitle(t)
	end
	function el:Get()
		return r.Title.Text
	end
	return finish(self, el, r, opts, "label")
end

function Window:_bindSub(label)
	Library:_bind(self.Gui, label, "TextColor3", "SubText")
end

function Container:AddParagraph(a)
	local opts = cloneOpts(a)
	opts.Description = opts.Content or opts.Description
	local r = newRow(self, opts, 0, 0)
	local el = { _conns = {} }
	function el:Set(t)
		self:SetDescription(t)
	end
	function el:Get()
		return r.Desc.Text
	end
	return finish(self, el, r, opts, "paragraph")
end

function Container:AddDivider(text)
	local win = self.Window
	local parent, list = self:_Parent()
	local hasText = text and text ~= ""
	local frame = win:_make("Frame", {
		Parent = parent, Size = UDim2.new(1, 0, 0, hasText and 26 or 8), BorderSizePixel = 0, LayoutOrder = rowOrder(self),
	}, { BackgroundColor3 = "Background" })
	if hasText then
		win:_make("TextLabel", {
			Parent = frame, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -28, 1, 0), BackgroundTransparency = 1,
			Text = string.upper(tostring(text)), Font = Library.FontBold, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
		}, { TextColor3 = "SubText" })
	end
	local item = { frame = frame, hidden = false, text = string.lower(tostring(text or "")) }
	table.insert(list, item)
	local d = { Frame = frame }
	function d:SetVisible(v)
		item.hidden = not v
		win:_Refilter()
	end
	function d:Destroy()
		local pos = table.find(list, item)
		if pos then
			table.remove(list, pos)
		end
		frame:Destroy()
	end
	return d
end

--------------------------------------------------------------------------------
-- Config
--------------------------------------------------------------------------------

function Library:ExportConfig()
	local out = {}
	for flag, opt in pairs(self.Options) do
		local k, v = opt.Kind, opt:Get()
		if k == "boolean" or k == "number" or k == "string" then
			out[flag] = v
		elseif k == "dropdown" then
			if v ~= nil then
				out[flag] = v
			end
		elseif k == "color" and typeof(v) == "Color3" then
			out[flag] = { math.floor(v.R * 255 + 0.5), math.floor(v.G * 255 + 0.5), math.floor(v.B * 255 + 0.5) }
		elseif k == "keybind" then
			out[flag] = v and v.Name or false
		end
	end
	return HttpService:JSONEncode(out)
end

function Library:ImportConfig(json)
	local ok, data = pcall(function()
		return HttpService:JSONDecode(json)
	end)
	if not ok or type(data) ~= "table" then
		return false, "malformed JSON"
	end
	local applied = 0
	for flag, v in pairs(data) do
		local opt = self.Options[flag]
		if opt then
			local k = opt.Kind
			local good = false
			if k == "boolean" and type(v) == "boolean" then
				opt:Set(v)
				good = true
			elseif k == "number" and type(v) == "number" then
				opt:Set(v)
				good = true
			elseif k == "string" and type(v) == "string" then
				opt:Set(v)
				good = true
			elseif k == "dropdown" and (type(v) == "string" or type(v) == "table") then
				opt:Set(v)
				good = true
			elseif k == "color" and type(v) == "table" and #v == 3 and type(v[1]) == "number" and type(v[2]) == "number" and type(v[3]) == "number" then
				opt:Set(Color3.fromRGB(v[1], v[2], v[3]))
				good = true
			elseif k == "keybind" and (v == false or type(v) == "string") then
				opt:Set(v == false and nil or v)
				good = true
			end
			if good then
				applied = applied + 1
			end
		end
	end
	if applied == 0 then
		return false, "nothing applied"
	end
	return true
end

local function fsReady()
	return typeof(writefile) == "function" and typeof(readfile) == "function" and typeof(isfile) == "function"
end

function Library:SaveConfig(name)
	if not fsReady() then
		return false, "file functions not available"
	end
	local ok, err = pcall(function()
		if typeof(makefolder) == "function" and typeof(isfolder) == "function" and not isfolder(self.ConfigFolder) then
			makefolder(self.ConfigFolder)
		end
		writefile(self.ConfigFolder .. "/" .. name .. ".json", self:ExportConfig())
	end)
	return ok, err
end

function Library:LoadConfig(name)
	if not fsReady() then
		return false, "file functions not available"
	end
	local path = self.ConfigFolder .. "/" .. name .. ".json"
	if not isfile(path) then
		return false, "config not found"
	end
	return self:ImportConfig(readfile(path))
end

function Library:ListConfigs()
	local out = {}
	if typeof(listfiles) == "function" and typeof(isfolder) == "function" and isfolder(self.ConfigFolder) then
		for _, f in ipairs(listfiles(self.ConfigFolder)) do
			local n = string.match(f, "([^/\\]+)%.json$")
			if n then
				table.insert(out, n)
			end
		end
	end
	return out
end

return Library
