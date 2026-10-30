--!nonstrict
--[[
	MalaphasUI v4.2 - dark utility-style Roblox UI library (Luau).

	Placement : ModuleScript named "MalaphasUI" in ReplicatedStorage.
	Usage     : local Library = require(ReplicatedStorage:WaitForChild("MalaphasUI"))

	WINDOW
	  Library:CreateWindow({Name, Size, ToggleKey, Parent, OnClose, Icon, Theme, AboveMenu, MaxVisible})  -> Window
	      MaxVisible (default 5): max notifications on screen; beyond that the oldest fades out early
	                              (also readable / writable as Window.MaxVisible)
	      The window auto-scales down (never up) to fit small screens and re-clamps itself on-screen
	      whenever the camera viewport changes.
	      Size: UDim2.new(0, 600, 0, 400) (a Scale part is converted with the screen size)
	      AboveMenu (default true): UI stays visible and clickable above the Roblox escape menu
	                                (ScreenGui.OnTopOfCoreBlur). Same option on CreateWatermark.
	      Theme = preset name ("Crimson") or a table of colors, applied at creation
	  Window:CreateTab(name, icon?, opts?)      -> Tab
	      opts = { categoriesOnly = true }: no implicit "Main" page; use :CreateCategory only
	      (calling :CreateSection on such a tab warns and returns nil)
	  Window:Notify({Title, Text, Duration, Icon})
	  Window:SetAboveMenu(bool)                 -- stay visible / clickable above the Roblox escape menu
	  Window:SetMinimized(bool)                 -- collapse to the title bar ("-" button / double-click title)
	  Window:SetVisible(bool)                   -- full hide (ToggleKey)
	  Window:Close() / Window:Destroy()

	TABS & CATEGORIES
	  Tab:CreateSection(name, side, icon?, order?)      -- side = "Left" | "Right"; goes in an implicit "Main" page
	  Tab:CreateCategory(name, icon?, order?)           -> Category (sub-page of the tab, shown in a scrollable bar)
	  Category:CreateSection(name, side, icon?, order?) -> Groupbox
	      order (optional) = LayoutOrder of the section / category button (default: creation order)

	ELEMENTS (Groupbox)
	  AddToggle({Name, Default, Icon, Flag, Callback})
	      toggle:AddColorPicker({Default, Flag, Callback})   -- swatch on the same row (opts table is never mutated)
	  AddSlider({Name, Min, Max, Default, Increment, Suffix, Flag, Callback})
	      slider:SetMin(n) / slider:SetMax(n)    -- change the range, re-snaps the current value
	      double-click the value to type a number (invalid input flashes the border red)
	  AddDropdown({Name, Options, Default, Multi, Searchable, Flag, Callback})
	      Searchable = true adds a live filter box inside the popup
	      dropdown:Refresh(newOptions, keepValue) -> table of dropped values (previous selection not in newOptions)
	  AddButton({Name, Icon, Callback})
	      button:SetText(t) / :SetIcon(icon) / :SetVisible(bool) / :SetEnabled(bool)
	  AddColorPicker({Name, Default, Flag, Callback})
	  AddTextbox({Name, Default, Placeholder, Numeric, MultiLine, ClearTextOnFocus, Flag, Callback})
	      MultiLine = true: wrapped, 48px tall, text aligned to the top
	  AddKeybind({Name, Default, Mode, Flag, Callback, OnChanged})   Mode = "Press" | "Toggle" | "Hold"
	      right-click the key box -> "Unbind"
	  AddLabel(text)                            -> {SetText, SetColor(color | themeKey | nil), SetVisible, Destroy}
	  AddDivider(text?)                         -> {Frame, SetVisible, Destroy}
	  AddImage({Image, Height, ScaleType, Rounded, Border, Color, Callback})
	      -> {Set, Get, SetVisible(bool), SetOpacity(0..1), Destroy}
	  AddThemeEditor({Keys})                    -- preset dropdown + one color picker per theme color
	                                               (flags are namespaced per editor: "theme_<id>_<Key>")

	  Every element returned by the Add* functions has :Destroy() (idempotent: removes the row, the
	  Library.Flags / Library.Options entries and its input connections).

	THEMING (live, everything updates instantly)
	  Library:SetTheme("Crimson")               -- preset: Default, Crimson, Ocean, Violet, Emerald, Amber, Light
	  Library:SetTheme({Accent = Color3.fromRGB(255, 80, 80), Background = ...})
	  Library:GetTheme()
	  Library:RegisterPreset("Name", { Accent = ..., ... })   -- custom preset (missing keys come from Default);
	                                                             listed by every AddThemeEditor
	  (in Studio, SetTheme warns about unknown keys in a table)
	  Theme keys: Background, Panel, PanelHeader, Element, ElementHover, ElementPress,
	              Border, BorderHover, Track, Text, SubText, Accent, Danger

	ICONS & IMAGES
	  An icon can be: an asset id number (123456), "rbxassetid://123456", a registered name, or a table
	  {Image = ..., RectOffset = Vector2, RectSize = Vector2 (spritesheets), Color = Color3, Tint = false | "Accent"}
	  Monochrome icons are tinted with the theme (follow active / inactive state). Use Tint = false for
	  full-color images, or Color = Color3 for a fixed color.
	  Library:RegisterIcon("settings", 123456) / Library:RegisterIcons({ settings = 123456, ... })
	  Library:GetAvatar(userId)                 -- yields; returns (image, nil) or (nil, errorMessage)

	EXTRAS
	  Library:CreateWatermark({Name, Position, AboveMenu})  -> {SetText, SetVisible, Destroy}
	  Library:GetWindow(name)                   -> first window whose Name == name, or nil
	  Library:ExportConfig()  -> JSON string of every Flag (theme colors included if you use AddThemeEditor)
	  Library:ImportConfig(json) -> true | (false, reason)
	      every value is type-checked against its element (boolean / number / string|list / Color3 / KeyCode|nil);
	      invalid or unknown entries are skipped silently; returns false only if the JSON is malformed
	      or nothing at all could be applied

	Every element has :Set(value, silent) and :Get().
	Library.Flags[flag]   -> current value
	Library.Options[flag] -> the element object
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local HttpService = game:GetService("HttpService")
local StatsService = game:GetService("Stats")

local Library = {
	Flags = {},
	Options = {},
	Windows = {},
	Icons = {},
}

----------------------------------------------------------------------
-- Theme presets
----------------------------------------------------------------------

local function gray(v)
	return Color3.fromRGB(v, v, v)
end

local function darkPreset(accent, tint)
	local function g(v)
		return gray(v):Lerp(tint, 0.12)
	end
	return {
		Background = g(18),
		Panel = g(23),
		PanelHeader = g(27),
		Element = g(32),
		ElementHover = g(44),
		ElementPress = g(70),
		Border = g(48),
		BorderHover = g(105),
		Track = g(40),
		Text = gray(225),
		SubText = g(135),
		Accent = accent,
		Danger = Color3.fromRGB(255, 90, 90),
	}
end

Library.Presets = {
	Default = {
		Background = gray(18),
		Panel = gray(23),
		PanelHeader = gray(27),
		Element = gray(32),
		ElementHover = gray(44),
		ElementPress = gray(70),
		Border = gray(48),
		BorderHover = gray(105),
		Track = gray(40),
		Text = gray(225),
		SubText = gray(135),
		Accent = gray(255),
		Danger = Color3.fromRGB(255, 90, 90),
	},
	Crimson = darkPreset(Color3.fromRGB(235, 65, 80), Color3.fromRGB(200, 40, 60)),
	Ocean = darkPreset(Color3.fromRGB(70, 160, 255), Color3.fromRGB(30, 90, 200)),
	Violet = darkPreset(Color3.fromRGB(170, 110, 255), Color3.fromRGB(110, 60, 220)),
	Emerald = darkPreset(Color3.fromRGB(60, 215, 140), Color3.fromRGB(30, 170, 100)),
	Amber = darkPreset(Color3.fromRGB(255, 180, 50), Color3.fromRGB(200, 140, 30)),
	Light = {
		Background = gray(238),
		Panel = gray(248),
		PanelHeader = gray(230),
		Element = gray(222),
		ElementHover = gray(210),
		ElementPress = gray(190),
		Border = gray(200),
		BorderHover = gray(130),
		Track = gray(208),
		Text = gray(30),
		SubText = gray(105),
		Accent = Color3.fromRGB(20, 110, 255),
		Danger = Color3.fromRGB(220, 50, 50),
	},
}
Library.PresetOrder = { "Default", "Crimson", "Ocean", "Violet", "Emerald", "Amber", "Light" }

Library.Theme = {
	Font = Enum.Font.Gotham,
	FontMedium = Enum.Font.GothamMedium,
	TextSize = 12,
}
for k, v in pairs(Library.Presets.Default) do
	Library.Theme[k] = v
end
local T = Library.Theme

local Window, Tab, Category, Groupbox = {}, {}, {}, {}
Window.__index = Window
Tab.__index = Tab
Category.__index = Category
Groupbox.__index = Groupbox

----------------------------------------------------------------------
-- Theme bindings: every themed color is registered so SetTheme can
-- repaint the whole UI instantly.
----------------------------------------------------------------------

local COLOR_PROPS = {
	BackgroundColor3 = true,
	TextColor3 = true,
	PlaceholderColor3 = true,
	ScrollBarImageColor3 = true,
	ImageColor3 = true,
	Color = true,
}

local bindings = {}

-- Drops bindings of destroyed instances. Only called from refreshTheme / Window:Destroy:
-- an instance being created is not parented yet, so pruning inside bind() would
-- wrongly discard it (it would then never follow theme changes).
local function prune()
	local alive = {}
	for _, b in ipairs(bindings) do
		if b.inst:IsDescendantOf(game) then
			table.insert(alive, b)
		end
	end
	bindings = alive
end

-- source = theme key (string) or function returning a Color3
local function bind(inst, prop, source)
	local fn = source
	if type(source) == "string" then
		fn = function()
			return T[source]
		end
	end
	inst[prop] = fn()
	table.insert(bindings, { inst = inst, prop = prop, fn = fn })
end

local function refreshTheme()
	prune()
	for _, b in ipairs(bindings) do
		b.inst[b.prop] = b.fn()
	end
end

function Library:SetTheme(theme)
	if type(theme) == "string" then
		theme = Library.Presets[theme]
		if not theme then
			return false
		end
	end
	if type(theme) ~= "table" then
		return false
	end
	local studio = RunService:IsStudio()
	for k, v in pairs(theme) do
		if typeof(v) == "Color3" and typeof(T[k]) == "Color3" then
			T[k] = v
		elseif studio and Library.Presets.Default[k] == nil and k ~= "Font" and k ~= "FontMedium" and k ~= "TextSize" then
			-- Studio-only hint: behavior is unchanged (unknown keys are still ignored)
			warn("[MalaphasUI] SetTheme: unknown theme key '" .. tostring(k) .. "'")
		end
	end
	refreshTheme()
	return true
end

-- Adds a custom preset. Missing keys fall back to Default so a partial preset never leaves holes.
-- AddThemeEditor dropdowns share Library.PresetOrder, so the new preset shows up in them too.
function Library:RegisterPreset(name, theme)
	if type(name) ~= "string" or name == "" or type(theme) ~= "table" then
		return false
	end
	local preset = {}
	for k, v in pairs(Library.Presets.Default) do
		preset[k] = v
	end
	for k, v in pairs(theme) do
		if typeof(v) == "Color3" and preset[k] ~= nil then
			preset[k] = v
		end
	end
	Library.Presets[name] = preset
	if not table.find(Library.PresetOrder, name) then
		table.insert(Library.PresetOrder, name)
	end
	return true
end

-- First window whose Name matches (windows are removed from the list when destroyed)
function Library:GetWindow(name)
	for _, w in ipairs(Library.Windows) do
		if w.Name == name then
			return w
		end
	end
	return nil
end

function Library:GetTheme()
	local copy = {}
	for k, v in pairs(T) do
		if typeof(v) == "Color3" then
			copy[k] = v
		end
	end
	return copy
end

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

-- Color props given as a string (theme key) or a function are bound to the theme.
local function create(class, props, parent)
	local inst = Instance.new(class)
	if inst:IsA("GuiObject") then
		inst.BorderSizePixel = 0
	end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		inst.BackgroundTransparency = 1
		inst.Font = T.Font
		inst.TextSize = T.TextSize
		inst.Text = ""
		if props.TextColor3 == nil then
			props.TextColor3 = "Text"
		end
	end
	if inst:IsA("GuiButton") then
		inst.AutoButtonColor = false
	end
	for k, v in pairs(props) do
		if COLOR_PROPS[k] and (type(v) == "string" or type(v) == "function") then
			bind(inst, k, v)
		else
			inst[k] = v
		end
	end
	inst.Parent = parent
	return inst
end

-- color: theme key / function / Color3 (default "Border")
local function addStroke(parent, color, thickness)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	if typeof(color) == "Color3" then
		s.Color = color
	else
		bind(s, "Color", color or "Border")
	end
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
		obj._flag = flag
	end
end

-- Removes an element's flag entries (only if they still point at that element)
local function clearFlag(obj)
	local flag = obj._flag
	if flag and Library.Options[flag] == obj then
		Library.Options[flag] = nil
		Library.Flags[flag] = nil
	end
end

-- Shallow copy so the caller's option tables are never mutated
local function cloneOpts(t)
	local copy = {}
	if type(t) == "table" then
		for k, v in pairs(t) do
			copy[k] = v
		end
	end
	return copy
end

local function isPointer(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function isMove(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
end

-- Drag `target` by grabbing `handle`. Returns the global InputChanged connection.
local function makeDraggable(handle, target)
	local dragging, dragStart, startPos = false, nil, nil
	handle.InputBegan:Connect(function(input)
		if isPointer(input) then
			dragging = true
			dragStart = input.Position
			startPos = target.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	return UserInputService.InputChanged:Connect(function(input)
		if dragging and isMove(input) then
			local d = input.Position - dragStart
			target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
end

----------------------------------------------------------------------
-- Icons & images
----------------------------------------------------------------------

function Library:RegisterIcon(name, icon)
	Library.Icons[name] = icon
end

function Library:RegisterIcons(map)
	for name, icon in pairs(map) do
		Library.Icons[name] = icon
	end
end

-- Normalizes any icon description into {Image, RectOffset, RectSize, Color, Tint}
local function resolveIcon(icon, depth)
	depth = depth or 0
	if icon == nil or icon == "" or depth > 3 then
		return nil
	end
	if type(icon) == "string" and Library.Icons[icon] ~= nil then
		return resolveIcon(Library.Icons[icon], depth + 1)
	end
	if type(icon) == "number" then
		return { Image = "rbxassetid://" .. tostring(icon) }
	end
	if type(icon) == "string" then
		if icon:match("^%d+$") then
			return { Image = "rbxassetid://" .. icon }
		end
		return { Image = icon }
	end
	if type(icon) == "table" then
		local base = resolveIcon(icon.Image or icon[1], depth + 1)
		if not base then
			return nil
		end
		base.RectOffset = icon.RectOffset or base.RectOffset
		base.RectSize = icon.RectSize or base.RectSize
		base.Color = icon.Color
		base.Tint = icon.Tint
		return base
	end
	return nil
end

-- defaultTint: theme key / function used when the icon is monochrome-tinted, or false for no tint.
-- Returns the ImageLabel and whether it is tinted by the theme.
local function makeIcon(parent, icon, size, defaultTint, props)
	local spec = resolveIcon(icon)
	if not spec then
		return nil, false
	end
	props = props or {}
	props.BackgroundTransparency = 1
	props.Size = UDim2.fromOffset(size, size)
	props.Image = spec.Image
	if spec.RectOffset then
		props.ImageRectOffset = spec.RectOffset
	end
	if spec.RectSize then
		props.ImageRectSize = spec.RectSize
	end

	local tinted = false
	if typeof(spec.Color) == "Color3" then
		props.ImageColor3 = spec.Color
	elseif spec.Tint == false or (spec.Tint == nil and not defaultTint) then
		props.ImageColor3 = Color3.new(1, 1, 1)
	else
		local t = spec.Tint
		if t == nil or t == true then
			t = defaultTint or "Text"
		end
		props.ImageColor3 = t
		tinted = true
	end
	return create("ImageLabel", props, parent), tinted
end

-- Avatar / headshot helper (yields). Use the result as `Image` in AddImage.
-- Returns (image, nil) on success or (nil, errorMessage) on failure so callers can branch.
function Library:GetAvatar(userId, thumbType, thumbSize)
	local ok, content = pcall(function()
		return Players:GetUserThumbnailAsync(
			userId,
			thumbType or Enum.ThumbnailType.HeadShot,
			thumbSize or Enum.ThumbnailSize.Size150x150
		)
	end)
	if ok and content then
		return content, nil
	end
	return nil, ok and "no thumbnail returned" or tostring(content)
end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------

-- Responsive scaling: shrink the window (never enlarge it) to fit the viewport and keep it on-screen.
-- Re-applied on every viewport change; it never fights the SetVisible / SetMinimized tweens
-- (while window._tweening is set, only window._fit is updated and _BeginTween re-applies afterwards).
local function hookViewport(window)
	local camConn = nil

	local function viewportSize()
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(0, 0)
		if vp.X < 100 or vp.Y < 100 then
			vp = window.Gui.AbsoluteSize -- camera not ready: fall back to the gui size
		end
		return vp
	end

	local function apply(recenter)
		if window._destroyed then
			return
		end
		local vp = viewportSize()
		if vp.X < 100 or vp.Y < 100 then
			return
		end
		local full = window.FullSize
		-- the 0.3 floor keeps the UIScale positive on absurdly small viewports
		local s = math.max(math.min(1, (vp.X - 40) / full.X, (vp.Y - 40) / full.Y), 0.3)
		window._fit = s
		if window._tweening then
			return
		end
		window.Scale.Scale = s * (window.Visible and 1 or 0.95)

		local w = full.X * s
		local h = (window.Minimized and 26 or full.Y) * s
		if recenter then
			window.Main.Position = UDim2.fromOffset((vp.X - w) / 2, (vp.Y - h) / 2)
		else
			local pos = window.Main.Position
			local x = pos.X.Scale * vp.X + pos.X.Offset
			local y = pos.Y.Scale * vp.Y + pos.Y.Offset
			window.Main.Position = UDim2.fromOffset(
				math.clamp(x, 0, math.max(vp.X - w, 0)),
				math.clamp(y, 0, math.max(vp.Y - h, 0))
			)
		end
	end

	local function bindCamera()
		if camConn then
			camConn:Disconnect()
			camConn = nil
		end
		local cam = workspace.CurrentCamera
		if cam then
			camConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				apply(false)
			end)
		end
		apply(false)
	end

	window._applyFit = apply
	window._viewportCleanup = function()
		if camConn then
			camConn:Disconnect()
			camConn = nil
		end
	end
	window:_Connect(workspace:GetPropertyChangedSignal("CurrentCamera"), bindCamera)
	bindCamera()
	apply(true)
end

local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

local function RandomString(length)
    length = length or 8
    local result = ""
    for i = 1, length do
        local index = math.random(1, #chars)
        result = result .. chars:sub(index, index)
    end
    return result
end

function Library:CreateWindow(config)
	config = config or {}
	if config.Theme then
		Library:SetTheme(config.Theme)
	end

	local self = setmetatable({}, Window)
	self.Name = config.Name or "Window"
	self.Tabs = {}
	self.ActiveTab = nil
	self.Connections = {}
	self.ToggleKey = config.ToggleKey or Enum.KeyCode.RightShift
	self.OnClose = config.OnClose
	self.Visible = false
	self.Minimized = false
	self._notifyOrder = 0
	self._notifications = {}
	self.MaxVisible = config.MaxVisible or 5
	self._fit = 1

	local size = config.Size or UDim2.fromOffset(600, 400)
	-- Pixel size (a Scale component is converted using the camera viewport)
	local viewport = Vector2.new(1280, 720)
	local camera = workspace.CurrentCamera
	if camera then
		viewport = camera.ViewportSize
	end
	local px = Vector2.new(
		math.max(size.X.Offset + size.X.Scale * viewport.X, 320),
		math.max(size.Y.Offset + size.Y.Scale * viewport.Y, 200)
	)
	self.FullSize = px
	local parent = config.Parent or Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = create("ScreenGui", {
		Name = RandomString(27),
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 2147483647, -- max int32 (DisplayOrder is an int property)
		-- Stays visible AND clickable above the Roblox escape menu (core blur layer)
		OnTopOfCoreBlur = config.AboveMenu ~= false,
	}, parent)
	self.Gui = gui

	-- CanvasGroup = the whole window can fade in/out
	local main = create("CanvasGroup", {
		Name = "Main",
		Size = UDim2.fromOffset(px.X, px.Y),
		Position = UDim2.new(0.5, -px.X / 2, 0.5, -px.Y / 2),
		BackgroundColor3 = "Background",
		GroupTransparency = 1,
		Active = true,
	}, gui)
	addStroke(main, "Border")
	self.Main = main

	self.Scale = Instance.new("UIScale")
	self.Scale.Scale = 0.95
	self.Scale.Parent = main

	-- Body = everything under the title bar (fixed pixel size, hidden when minimized)
	local body = create("Frame", {
		Name = "Body",
		Size = UDim2.fromOffset(px.X, px.Y),
		BackgroundTransparency = 1,
	}, main)
	self.Body = body

	-- Title bar (created after Body so it draws on top)
	local header = create("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundColor3 = "PanelHeader",
	}, main)

	local titleX = 10
	if config.Icon then
		local icon = makeIcon(header, config.Icon, 14, false, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 9, 0.5, 0),
		})
		if icon then
			titleX = 30
		end
	end

	create("TextLabel", {
		Text = self.Name,
		Position = UDim2.fromOffset(titleX, 0),
		Size = UDim2.new(0, 200, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = T.FontMedium,
	}, header)

	self.Breadcrumb = create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(0, 200, 1, 0),
		TextColor3 = "SubText",
		TextSize = 10,
	}, header)

	self.Stats = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -62, 0, 0),
		Size = UDim2.new(0, 160, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = "SubText",
		TextSize = 10,
	}, header)

	local function headerButton(text, offsetX, hoverKey)
		local btn = create("TextButton", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -offsetX, 0, 0),
			Size = UDim2.new(0, 28, 1, 0),
			Text = text,
			Font = T.FontMedium,
			TextSize = 13,
			TextColor3 = "SubText",
		}, header)
		btn.MouseEnter:Connect(function()
			tween(btn, { TextColor3 = T[hoverKey] })
		end)
		btn.MouseLeave:Connect(function()
			tween(btn, { TextColor3 = T.SubText })
		end)
		return btn
	end

	local closeBtn = headerButton("X", 0, "Danger")
	closeBtn.TextSize = 11
	closeBtn.MouseButton1Click:Connect(function()
		self:Close()
	end)

	self.MinBtn = headerButton("-", 28, "Accent")
	self.MinBtn.MouseButton1Click:Connect(function()
		self:SetMinimized(not self.Minimized)
	end)

	create("Frame", { Position = UDim2.new(0, 0, 0, 26), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = "Border" }, main)

	-- Double-click the title bar = minimize / restore
	local lastClick = 0
	header.InputBegan:Connect(function(input)
		-- ignore clicks on the "-" / "X" buttons (the right 62px of the title bar)
		local rightEdge = header.AbsolutePosition.X + header.AbsoluteSize.X
		if input.UserInputType == Enum.UserInputType.MouseButton1 and input.Position.X < rightEdge - 62 then
			local now = os.clock()
			if now - lastClick < 0.3 then
				lastClick = 0
				self:SetMinimized(not self.Minimized)
			else
				lastClick = now
			end
		end
	end)

	-- Horizontal tab bar
	create("Frame", { Position = UDim2.new(0, 0, 0, 55), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = "Border" }, body)
	self.TabHolder = create("ScrollingFrame", {
		Position = UDim2.new(0, 6, 0, 27),
		Size = UDim2.new(1, -12, 0, 28),
		BackgroundTransparency = 1,
		ScrollBarThickness = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
	}, body)
	addList(self.TabHolder, 0, true)

	-- Search
	self.SearchBox = create("TextBox", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 62),
		Size = UDim2.fromOffset(140, 20),
		BackgroundTransparency = 0,
		BackgroundColor3 = "Panel",
		PlaceholderText = "search...",
		PlaceholderColor3 = "SubText",
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 11,
	}, body)
	addStroke(self.SearchBox, "Border")
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
	}, body)

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

	table.insert(self.Connections, makeDraggable(header, main))

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

	hookViewport(self)
	table.insert(Library.Windows, self)
	self:SetVisible(true) -- fade-in
	return self
end

function Window:_Connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(self.Connections, c)
	return c
end

-- Marks the window as "mid-tween" so the responsive fit does not fight the animation;
-- the fit is re-applied (and the window re-clamped on-screen) when the tween ends.
function Window:_BeginTween(duration)
	self._tweenToken = (self._tweenToken or 0) + 1
	local token = self._tweenToken
	self._tweening = true
	task.delay(duration + 0.02, function()
		if self._tweenToken == token and not self._destroyed then
			self._tweening = false
			if self._applyFit then
				self._applyFit(false)
			end
		end
	end)
end

function Window:SetVisible(visible)
	if self.Visible == visible then
		return
	end
	self.Visible = visible
	if visible then
		self:_BeginTween(0.22)
		self.Main.Visible = true
		tween(self.Main, { GroupTransparency = 0 }, 0.22)
		tween(self.Scale, { Scale = self._fit }, 0.22, Enum.EasingStyle.Back)
	else
		self:_BeginTween(0.16)
		self:_CloseDropdown()
		tween(self.Main, { GroupTransparency = 1 }, 0.16)
		tween(self.Scale, { Scale = 0.95 * self._fit }, 0.16)
		task.delay(0.17, function()
			if not self.Visible and self.Main and self.Main.Parent then
				self.Main.Visible = false
			end
		end)
	end
end

-- Collapse to the title bar only (and back)
function Window:SetMinimized(minimized)
	if self.Minimized == minimized then
		return
	end
	self.Minimized = minimized
	self:_BeginTween(0.25)
	self:_CloseDropdown()
	self.MinBtn.Text = minimized and "+" or "-"
	if minimized then
		tween(self.Main, { Size = UDim2.fromOffset(self.FullSize.X, 26) }, 0.22, Enum.EasingStyle.Cubic)
		task.delay(0.23, function()
			if self.Minimized and self.Body and self.Body.Parent then
				self.Body.Visible = false
			end
		end)
	else
		self.Body.Visible = true
		tween(self.Main, { Size = UDim2.fromOffset(self.FullSize.X, self.FullSize.Y) }, 0.22, Enum.EasingStyle.Cubic)
	end
end

-- Toggle at runtime: keep the UI usable while the Roblox escape menu is open
function Window:SetAboveMenu(enabled)
	self.Gui.OnTopOfCoreBlur = not not enabled
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
	self._destroyed = true
	if self._viewportCleanup then
		self._viewportCleanup()
	end
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
		BackgroundColor3 = "Panel",
		GroupTransparency = 1,
		LayoutOrder = self._notifyOrder,
	}, self.NotifyHolder)
	addStroke(n, "Border")
	addList(n, 0)

	local body = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
	}, n)
	addList(body, 3)
	addPadding(body, 10, 8, 10, 8)

	local titleRow = create("Frame", {
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
	}, body)
	local tx = 0
	if o.Icon then
		local ic = makeIcon(titleRow, o.Icon, 12, "Accent", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
		})
		if ic then
			tx = 18
		end
	end
	create("TextLabel", {
		Position = UDim2.fromOffset(tx, 0),
		Size = UDim2.new(1, -tx, 1, 0),
		Text = o.Title or self.Name,
		Font = T.FontMedium,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, titleRow)

	create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = o.Text or "",
		TextColor3 = "SubText",
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = 2,
	}, body)

	local barBack = create("Frame", {
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = "Track",
		LayoutOrder = 2,
	}, n)
	local fill = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = "Accent" }, barBack)

	tween(n, { GroupTransparency = 0 }, 0.2)
	tween(fill, { Size = UDim2.fromScale(0, 1) }, duration, Enum.EasingStyle.Linear)

	local entry = { dismissed = false }
	function entry.dismiss()
		if entry.dismissed then
			return
		end
		entry.dismissed = true
		local i = table.find(self._notifications, entry)
		if i then
			table.remove(self._notifications, i)
		end
		if n.Parent then
			tween(n, { GroupTransparency = 1 }, 0.25)
			task.delay(0.26, function()
				n:Destroy()
			end)
		end
	end
	table.insert(self._notifications, entry)
	task.delay(duration, entry.dismiss)

	-- Over the limit: the oldest notification fades out early instead of waiting for its duration
	while #self._notifications > math.max(self.MaxVisible or 5, 1) do
		self._notifications[1].dismiss()
	end
end

function Window:_ApplySearch()
	local tab = self.ActiveTab
	local cat = tab and tab.ActiveCategory
	if not cat then
		return
	end
	local q = string.lower(self.SearchBox.Text)
	for _, gb in ipairs(cat.Groupboxes) do
		local titleMatch = q == "" or string.find(string.lower(gb.Name), q, 1, true) ~= nil
		local any = titleMatch
		for _, el in ipairs(gb.Elements) do
			local match = titleMatch or string.find(string.lower(el.Name), q, 1, true) ~= nil
			el.Match = match
			-- elements hidden through :SetVisible(false) stay hidden whatever the search says
			el.Frame.Visible = match and not el.Hidden
			any = any or (match and not el.Hidden)
		end
		gb.Frame.Visible = any
	end
end

-- Shows one category page of a tab (with fade + slide animation)
function Window:_ShowCategory(tab, cat)
	self:_CloseDropdown()
	tab.ActiveCategory = cat
	for _, c in ipairs(tab.Categories) do
		local active = c == cat
		local col = active and T.Accent or T.SubText
		tween(c.Label, { TextColor3 = col }, 0.15)
		if c.Icon and c.IconTinted then
			tween(c.Icon, { ImageColor3 = col }, 0.15)
		end
		tween(c.Button, { BackgroundTransparency = active and 0 or 1 }, 0.15)
		tween(c.Stroke, { Transparency = active and 0 or 1 }, 0.15)
		if not active then
			c.Page.Visible = false
		end
	end
	self.Breadcrumb.Text = string.upper(tab.Name) .. " / " .. string.upper(cat.Name)

	if not cat.Page.Visible then
		cat.Page.Position = UDim2.fromOffset(0, 14)
		cat.Page.GroupTransparency = 1
		cat.Page.Visible = true
		tween(cat.Page, { Position = UDim2.fromOffset(0, 0), GroupTransparency = 0 }, 0.24, Enum.EasingStyle.Cubic)
	end
	self:_ApplySearch()
end

function Window:SelectTab(tab)
	if self.ActiveTab == tab then
		return
	end
	self:_CloseDropdown()
	self.ActiveTab = tab

	for _, t in ipairs(self.Tabs) do
		local active = t == tab
		local col = active and T.Accent or T.SubText
		tween(t.Label, { TextColor3 = col }, 0.15)
		if t.Icon and t.IconTinted then
			tween(t.Icon, { ImageColor3 = col }, 0.15)
		end
		tween(t.Underline, { Size = active and UDim2.new(1, -8, 0, 1) or UDim2.new(0, 0, 0, 1) }, 0.22)
		t.CatBar.Visible = active and t.UsesCategories
		if not active then
			for _, c in ipairs(t.Categories) do
				c.Page.Visible = false
			end
		end
	end

	if tab.ActiveCategory then
		self:_ShowCategory(tab, tab.ActiveCategory)
	else
		self.Breadcrumb.Text = string.upper(tab.Name) .. " / MAIN"
	end
end

function Window:CreateTab(name, icon, opts)
	local tab = setmetatable({}, Tab)
	tab.Window = self
	tab.Name = name
	tab.Categories = {}
	tab.ActiveCategory = nil
	tab.UsesCategories = false
	-- categoriesOnly: no implicit "Main" page, the category bar is always the navigation
	tab.CategoriesOnly = type(opts) == "table" and opts.categoriesOnly == true
	if tab.CategoriesOnly then
		tab.UsesCategories = true
	end

	local iconSize = 14
	local hasIcon = resolveIcon(icon) ~= nil
	local textW = TextService:GetTextSize(name, T.TextSize, T.Font, Vector2.new(1000, 100)).X
	local width = textW + 20 + (hasIcon and (iconSize + 6) or 0)

	tab.Button = create("TextButton", {
		Size = UDim2.new(0, width, 1, 0),
		LayoutOrder = #self.Tabs + 1,
	}, self.TabHolder)

	-- Color follows the active / inactive state (and the theme)
	local function stateColor()
		return self.ActiveTab == tab and T.Accent or T.SubText
	end

	local startX = 10
	if hasIcon then
		tab.Icon, tab.IconTinted = makeIcon(tab.Button, icon, iconSize, stateColor, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, startX, 0.5, 0),
		})
		startX += iconSize + 6
	end
	tab.Label = create("TextLabel", {
		Position = UDim2.new(0, startX, 0, 0),
		Size = UDim2.new(0, textW + 2, 1, 0),
		Text = name,
		TextColor3 = stateColor,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, tab.Button)

	-- Underline grows from the center when the tab becomes active
	tab.Underline = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, -1),
		Size = UDim2.new(0, 0, 0, 1),
		BackgroundColor3 = "Accent",
	}, tab.Button)

	-- Category bar (sub-navigation), only shown when the tab has categories
	-- horizontal ScrollingFrame: with many categories / a narrow window the bar scrolls instead of clipping
	tab.CatBar = create("ScrollingFrame", {
		Position = UDim2.fromOffset(10, 60),
		Size = UDim2.new(1, -170, 0, 24),
		BackgroundTransparency = 1,
		ScrollBarThickness = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		Visible = false,
	}, self.Body)
	addPadding(tab.CatBar, 1, 0, 1, 0)
	local cl = addList(tab.CatBar, 4, true)
	cl.VerticalAlignment = Enum.VerticalAlignment.Center

	local function setHover(col)
		tween(tab.Label, { TextColor3 = col })
		if tab.Icon and tab.IconTinted then
			tween(tab.Icon, { ImageColor3 = col })
		end
	end
	tab.Button.MouseEnter:Connect(function()
		if self.ActiveTab ~= tab then
			setHover(T.Text)
		end
	end)
	tab.Button.MouseLeave:Connect(function()
		if self.ActiveTab ~= tab then
			setHover(T.SubText)
		end
	end)
	tab.Button.MouseButton1Click:Connect(function()
		self:SelectTab(tab)
	end)

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
		BackgroundColor3 = "Panel",
		Active = true, -- swallow clicks so the overlay does not close the popup
	}, self.Overlay)
	addStroke(frame, "Border")
	self._dropList = frame
	build(frame)
end

function Window:_OpenDropdown(anchor, options, current, onPick, onClose, multi, searchable)
	self:_CloseDropdown()
	local itemH = 20
	local searchH = searchable and 20 or 0 -- searchable popups are ~20px taller
	local height = math.min(#options, 6) * itemH + searchH
	local pos = anchor.AbsolutePosition
	local y = pos.Y + anchor.AbsoluteSize.Y + 2
	if y + height > self.Gui.AbsoluteSize.Y then
		y = pos.Y - height - 2
	end

	self.Overlay.Visible = true
	self._dropOnClose = onClose

	local list
	if searchable then
		local holder = create("Frame", {
			BackgroundColor3 = "Panel",
			Position = UDim2.fromOffset(pos.X, y),
			Size = UDim2.fromOffset(anchor.AbsoluteSize.X, height),
			Active = true, -- swallow clicks so the overlay does not close the popup
		}, self.Overlay)
		addStroke(holder, "Border")
		local search = create("TextBox", {
			Size = UDim2.new(1, 0, 0, searchH),
			PlaceholderText = "search...",
			PlaceholderColor3 = "SubText",
			ClearTextOnFocus = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 11,
		}, holder)
		addPadding(search, 6, 0, 6, 0)
		create("Frame", {
			Position = UDim2.fromOffset(0, searchH - 1),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = "Border",
		}, holder)
		list = create("ScrollingFrame", {
			Position = UDim2.fromOffset(0, searchH),
			Size = UDim2.new(1, 0, 1, -searchH),
			BackgroundTransparency = 1,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = "Border",
		}, holder)
		addList(list, 0)
		self._dropList = holder

		-- live filter (the option buttons carry the option text)
		search:GetPropertyChangedSignal("Text"):Connect(function()
			local q = string.lower(search.Text)
			for _, child in ipairs(list:GetChildren()) do
				if child:IsA("TextButton") then
					child.Visible = q == "" or string.find(string.lower(child.Text), q, 1, true) ~= nil
				end
			end
		end)
		if not UserInputService.TouchEnabled then
			search:CaptureFocus()
		end
	else
		list = create("ScrollingFrame", {
			BackgroundColor3 = "Panel",
			Position = UDim2.fromOffset(pos.X, y),
			Size = UDim2.fromOffset(anchor.AbsoluteSize.X, height),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = "Border",
		}, self.Overlay)
		addStroke(list, "Border")
		addList(list, 0)
		self._dropList = list
	end

	for i, opt in ipairs(options) do
		local hovered = false
		local function isSelected()
			if multi then
				return current[opt] == true
			end
			return opt == current
		end
		local function color()
			return (isSelected() or hovered) and T.Accent or T.SubText
		end

		local item = create("TextButton", {
			Size = UDim2.new(1, 0, 0, itemH),
			Text = tostring(opt),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = color,
			BackgroundColor3 = "ElementHover",
			LayoutOrder = i,
		}, list)
		addPadding(item, 6, 0, 6, 0)
		local mark = create("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.fromOffset(4, 4),
			BackgroundColor3 = "Accent",
			Visible = isSelected(),
		}, item)

		local function paint()
			item.TextColor3 = color()
			mark.Visible = isSelected()
		end

		item.MouseEnter:Connect(function()
			hovered = true
			item.BackgroundTransparency = 0
			paint()
		end)
		item.MouseLeave:Connect(function()
			hovered = false
			item.BackgroundTransparency = 1
			paint()
		end)
		item.MouseButton1Click:Connect(function()
			onPick(opt)
			if multi then
				paint()
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

	-- The swatch shows a user color, so it is NOT bound to the theme
	local swatch = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -offsetX, 0.5, 0),
		Size = UDim2.fromOffset(22, 12),
		BackgroundTransparency = 0,
		BackgroundColor3 = default,
	}, host)
	local swatchStroke = addStroke(swatch, "Border")
	swatch.MouseEnter:Connect(function()
		tween(swatchStroke, { Color = T.BorderHover })
	end)
	swatch.MouseLeave:Connect(function()
		tween(swatchStroke, { Color = T.Border })
	end)

	local picker = { Name = o.Name or "Color", Value = default, Kind = "color" }
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

	-- Default destroy = remove just the swatch (a picker living on a toggle row).
	-- Groupbox:AddColorPicker replaces this with a row-level destroy.
	function picker:Destroy()
		if refreshPopup then
			window:_CloseDropdown() -- its popup is open
		end
		clearFlag(self)
		swatch:Destroy()
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
				BackgroundColor3 = "Element",
				ClearTextOnFocus = false,
				TextSize = 11,
			}, frame)
			addStroke(hex, "Border")

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
-- Tab -> Categories -> Groupboxes
----------------------------------------------------------------------

-- Creates a sub-page. Used by CreateCategory and by the implicit "Main" page.
function Tab:_NewCategory(name, icon, order)
	local window = self.Window
	local cat = setmetatable({}, Category)
	cat.Tab = self
	cat.Window = window
	cat.Name = name
	cat.Groupboxes = {}

	-- Button in the category bar
	local iconSize = 12
	local hasIcon = resolveIcon(icon) ~= nil
	local textW = TextService:GetTextSize(name, 11, T.Font, Vector2.new(1000, 100)).X
	local width = textW + 18 + (hasIcon and (iconSize + 4) or 0)

	cat.Button = create("TextButton", {
		Size = UDim2.fromOffset(width, 20),
		BackgroundColor3 = "Element",
		LayoutOrder = order or (#self.Categories + 1),
	}, self.CatBar)
	cat.Stroke = addStroke(cat.Button, "Border")
	cat.Stroke.Transparency = 1

	local function stateColor()
		return self.ActiveCategory == cat and T.Accent or T.SubText
	end

	local startX = 9
	if hasIcon then
		cat.Icon, cat.IconTinted = makeIcon(cat.Button, icon, iconSize, stateColor, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, startX, 0.5, 0),
		})
		startX += iconSize + 4
	end
	cat.Label = create("TextLabel", {
		Position = UDim2.new(0, startX, 0, 0),
		Size = UDim2.new(0, textW + 2, 1, 0),
		Text = name,
		TextSize = 11,
		TextColor3 = stateColor,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, cat.Button)

	local function setHover(col)
		tween(cat.Label, { TextColor3 = col })
		if cat.Icon and cat.IconTinted then
			tween(cat.Icon, { ImageColor3 = col })
		end
	end
	cat.Button.MouseEnter:Connect(function()
		if self.ActiveCategory ~= cat then
			setHover(T.Text)
		end
	end)
	cat.Button.MouseLeave:Connect(function()
		if self.ActiveCategory ~= cat then
			setHover(T.SubText)
		end
	end)
	cat.Button.MouseButton1Click:Connect(function()
		if self.ActiveCategory ~= cat then
			window:_ShowCategory(self, cat)
		end
	end)

	-- Page (fade/slide animated) containing the two columns
	cat.Page = create("CanvasGroup", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		Visible = false,
	}, window.Content)

	cat.Scroll = create("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = "Border",
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, cat.Page)
	addPadding(cat.Scroll, 0, 0, 8, 0)

	local function column(xScale, xOffset)
		local col = create("Frame", {
			Position = UDim2.new(xScale, xOffset, 0, 0),
			Size = UDim2.new(0.5, -4, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, cat.Scroll)
		addList(col, 8)
		return col
	end
	cat.Columns = { Left = column(0, 0), Right = column(0.5, 4) }

	table.insert(self.Categories, cat)
	self.CatBar.Visible = self.UsesCategories and window.ActiveTab == self

	if #self.Categories == 1 then
		self.ActiveCategory = cat
		if window.ActiveTab == self then
			window:_ShowCategory(self, cat)
		end
	end
	return cat
end

function Tab:CreateCategory(name, icon, order)
	self.UsesCategories = true
	local cat = self:_NewCategory(name, icon, order)
	self.CatBar.Visible = self.Window.ActiveTab == self
	return cat
end

-- Sections created directly on the tab go in an implicit "Main" page
function Tab:CreateSection(name, side, icon, order)
	if self.CategoriesOnly then
		warn("[MalaphasUI] Tab '" .. tostring(self.Name) .. "' is categoriesOnly: use :CreateCategory(...):CreateSection(...)")
		return nil
	end
	if not self._default then
		self._default = self:_NewCategory("Main")
	end
	return self._default:CreateSection(name, side, icon, order)
end
Tab.CreateGroupbox = Tab.CreateSection

function Category:CreateSection(name, side, icon, order)
	local column = self.Columns[side or "Left"] or self.Columns.Left
	local gb = setmetatable({}, Groupbox)
	gb.Tab = self.Tab
	gb.Category = self
	gb.Window = self.Window
	gb.Name = name
	gb.Elements = {}
	gb._order = 0

	gb.Frame = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = "Panel",
		LayoutOrder = order or (#self.Groupboxes + 1),
	}, column)
	addStroke(gb.Frame, "Border")
	addList(gb.Frame, 0)

	local title = create("Frame", {
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundColor3 = "PanelHeader",
		LayoutOrder = 0,
	}, gb.Frame)
	local titleX = 8
	if icon then
		local ic = makeIcon(title, icon, 12, "Text", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 8, 0.5, 0),
		})
		if ic then
			titleX = 26
		end
	end
	create("TextLabel", {
		Position = UDim2.fromOffset(titleX, 0),
		Size = UDim2.new(1, -titleX, 1, 0),
		Text = name,
		Font = T.FontMedium,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, title)

	create("Frame", { Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = "Border", LayoutOrder = 1 }, gb.Frame)

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
Category.CreateGroupbox = Category.CreateSection

function Groupbox:_Row(height)
	self._order += 1
	return create("Frame", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
		LayoutOrder = self._order,
	}, self.Content)
end

function Groupbox:_Register(name, frame)
	-- Match = passes the current search filter; Hidden = hidden through :SetVisible(false)
	local entry = { Name = name, Frame = frame, Match = true, Hidden = false }
	table.insert(self.Elements, entry)
	return entry
end

-- Visibility that survives the search filter
local function setEntryVisible(entry, visible)
	entry.Hidden = not visible
	entry.Frame.Visible = visible and entry.Match
end

-- Adds an idempotent :Destroy() to an element object: removes the row from Groupbox.Elements,
-- clears the Library.Flags / Library.Options entry, runs `extra` (disconnect inputs, close popups)
-- and destroys the row frame.
local function attachDestroy(groupbox, obj, entry, extra)
	local destroyed = false
	function obj:Destroy()
		if destroyed then
			return
		end
		destroyed = true
		local i = table.find(groupbox.Elements, entry)
		if i then
			table.remove(groupbox.Elements, i)
		end
		clearFlag(obj)
		if extra then
			extra()
		end
		entry.Frame:Destroy()
	end
end

----------------------------------------------------------------------
-- Label / Divider / Image
----------------------------------------------------------------------

function Groupbox:AddLabel(text)
	local row = self:_Row(16)
	row.AutomaticSize = Enum.AutomaticSize.Y -- long labels wrap instead of overlapping the next row
	local colorSource = nil -- nil = default SubText; Color3 or theme key set through :SetColor
	local label = create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = text or "",
		-- function source: keeps following the theme unless a custom color was set
		TextColor3 = function()
			if typeof(colorSource) == "Color3" then
				return colorSource
			elseif type(colorSource) == "string" and typeof(T[colorSource]) == "Color3" then
				return T[colorSource]
			end
			return T.SubText
		end,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
	}, row)
	local entry = self:_Register(text or "", row)
	local obj = {}
	function obj:SetText(t)
		label.Text = t
	end
	-- color = Color3, theme key ("Accent", "Danger"...) or nil to go back to the default
	function obj:SetColor(color)
		colorSource = color
		if typeof(color) == "Color3" then
			label.TextColor3 = color
		elseif type(color) == "string" and typeof(T[color]) == "Color3" then
			label.TextColor3 = T[color]
		else
			colorSource = nil
			label.TextColor3 = T.SubText
		end
	end
	function obj:SetVisible(visible)
		setEntryVisible(entry, visible)
	end
	attachDestroy(self, obj, entry)
	return obj
end

function Groupbox:AddDivider(text)
	local row = self:_Row(text and 14 or 8)
	create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = "Border",
	}, row)
	if text then
		local w = TextService:GetTextSize(text, 10, T.Font, Vector2.new(1000, 100)).X + 12
		create("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(w, 14),
			BackgroundTransparency = 0,
			BackgroundColor3 = "Panel",
			Text = text,
			TextSize = 10,
			TextColor3 = "SubText",
		}, row)
	end
	local entry = self:_Register(text or "", row)
	-- object like the other elements (the raw frame stays reachable through .Frame)
	local obj = { Frame = row }
	function obj:SetVisible(visible)
		setEntryVisible(entry, visible)
	end
	attachDestroy(self, obj, entry)
	return obj
end

-- Full-width image (banner, avatar, logo...). Not tinted unless you pass Color / Tint.
function Groupbox:AddImage(o)
	o = o or {}
	local height = o.Height or 80
	local row = self:_Row(height)

	local frame = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = "Element",
	}, row)
	if o.Border ~= false then
		addStroke(frame, "Border")
	end
	if o.Rounded then
		addCorner(frame, o.Radius or 6)
	end

	local scaleTypes = {
		Fit = Enum.ScaleType.Fit,
		Crop = Enum.ScaleType.Crop,
		Stretch = Enum.ScaleType.Stretch,
	}
	local img = create("ImageLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScaleType = scaleTypes[o.ScaleType or "Fit"] or Enum.ScaleType.Fit,
		ImageColor3 = (typeof(o.Color) == "Color3" or type(o.Tint) == "string") and (o.Color or o.Tint) or Color3.new(1, 1, 1),
	}, frame)
	if o.Rounded then
		addCorner(img, o.Radius or 6)
	end

	local obj = { Name = o.Name or "", Value = o.Image }

	function obj:Set(image)
		local spec = resolveIcon(image)
		self.Value = image
		img.Image = spec and spec.Image or ""
		img.ImageRectOffset = spec and spec.RectOffset or Vector2.new(0, 0)
		img.ImageRectSize = spec and spec.RectSize or Vector2.new(0, 0)
	end

	function obj:Get()
		return self.Value
	end

	if o.Callback then
		local hit = create("TextButton", { Size = UDim2.fromScale(1, 1) }, frame)
		hit.MouseButton1Click:Connect(function()
			task.spawn(o.Callback)
		end)
	end

	obj:Set(o.Image)
	local entry = self:_Register(o.Name or "", row)
	function obj:SetVisible(visible)
		setEntryVisible(entry, visible)
	end
	-- opacity: 1 = fully visible, 0 = invisible
	function obj:SetOpacity(opacity)
		img.ImageTransparency = 1 - math.clamp(tonumber(opacity) or 1, 0, 1)
	end
	attachDestroy(self, obj, entry)
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

	local toggle = { Name = name, Value = false, Kind = "boolean", _pickers = 0, _children = {} }

	local function labelColor()
		return toggle.Value and T.Text or T.SubText
	end

	local box = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(12, 12),
		BackgroundColor3 = "Element",
	}, row)
	local boxStroke = addStroke(box, function()
		return toggle.Value and T.Accent or T.Border
	end)
	local mark = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = "Accent",
		BackgroundTransparency = 1,
	}, box)

	local labelX = 20
	local icon, iconTinted
	if o.Icon then
		icon, iconTinted = makeIcon(row, o.Icon, 14, labelColor, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 20, 0.5, 0),
		})
		if icon then
			labelX = 40
		end
	end
	local label = create("TextLabel", {
		Position = UDim2.fromOffset(labelX, 0),
		Size = UDim2.new(1, -labelX, 1, 0),
		Text = name,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = labelColor,
	}, row)
	local hit = create("TextButton", { Size = UDim2.fromScale(1, 1) }, row)

	function toggle:Set(value, silent)
		value = not not value
		local changed = value ~= self.Value
		self.Value = value
		tween(mark, { BackgroundTransparency = value and 0 or 1 })
		tween(boxStroke, { Color = value and T.Accent or T.Border })
		tween(label, { TextColor3 = labelColor() })
		if icon and iconTinted then
			tween(icon, { ImageColor3 = labelColor() })
		end
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
		opts = cloneOpts(opts) -- never mutate the caller's table
		opts.Name = opts.Name or name
		local picker = createPicker(window, row, opts, self._pickers * 28)
		self._pickers += 1
		register(opts.Flag, picker)
		table.insert(self._children, picker)
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
	local entry = self:_Register(name, row)
	attachDestroy(self, toggle, entry, function()
		for _, child in ipairs(toggle._children) do
			clearFlag(child) -- the swatches die with the row but their flags must go too
		end
		window:_CloseDropdown()
	end)
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
		TextColor3 = "SubText",
	}, row)
	-- TextButton (not a label) so a double-click on the value can open the text editor
	local valueLabel = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(70, 14),
		TextXAlignment = Enum.TextXAlignment.Right,
	}, row)

	local hit = create("TextButton", {
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.new(1, 0, 0, 12),
	}, row)
	local track = create("Frame", {
		Position = UDim2.new(0, 0, 0.5, -2),
		Size = UDim2.new(1, 0, 0, 4),
		BackgroundColor3 = "Track",
	}, hit)
	local fill = create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = "Accent",
	}, track)

	local slider = { Name = name, Value = min, Kind = "number" }

	local function snap(v)
		v = math.clamp(v, min, max)
		if inc > 0 then
			v = min + math.floor((v - min) / inc + 0.5) * inc
		end
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

	-- Change the range at runtime; the current value is re-snapped into the new range
	function slider:SetMin(n)
		if type(n) ~= "number" or n ~= n then
			return
		end
		min = n
		if max < min then
			max = min
		end
		self:Set(self.Value)
	end

	function slider:SetMax(n)
		if type(n) ~= "number" or n ~= n then
			return
		end
		max = n
		if min > max then
			min = max
		end
		self:Set(self.Value)
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
	local connMove = window:_Connect(UserInputService.InputChanged, function(input)
		if dragging and isMove(input) then
			updateFromX(input.Position.X)
		end
	end)
	local connEnd = window:_Connect(UserInputService.InputEnded, function(input)
		if isPointer(input) then
			dragging = false
		end
	end)

	-- Double-click the value to type a number (parsed, then snapped by slider:Set -> snap)
	local editBox = nil
	local lastClick = 0

	local function finishEdit()
		if editBox then
			editBox:Destroy()
			editBox = nil
		end
		valueLabel.Visible = true
	end

	local function startEdit()
		if editBox then
			return
		end
		valueLabel.Visible = false
		local box = create("TextBox", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.fromOffset(70, 14),
			BackgroundTransparency = 0,
			BackgroundColor3 = "Element",
			Text = string.format("%." .. decimals .. "f", slider.Value),
			TextXAlignment = Enum.TextXAlignment.Right,
			ClearTextOnFocus = false,
			TextSize = 11,
		}, row)
		local stroke = addStroke(box, "Accent")
		editBox = box
		box.FocusLost:Connect(function()
			local text = box.Text
			if suffix ~= "" then
				-- let the user keep the suffix ("50%")
				local s, e = string.find(text, suffix, 1, true)
				if s then
					text = string.sub(text, 1, s - 1) .. string.sub(text, e + 1)
				end
			end
			local n = tonumber(text)
			if n and n == n then
				slider:Set(n)
				if editBox == box then
					finishEdit()
				end
			else
				-- invalid input: flash the border red for ~0.4s, then revert to the label
				stroke.Color = T.Danger
				box.Text = string.format("%." .. decimals .. "f", slider.Value)
				task.delay(0.4, function()
					if editBox == box then
						finishEdit()
					end
				end)
			end
		end)
		box:CaptureFocus()
	end

	valueLabel.MouseButton1Click:Connect(function()
		local now = os.clock()
		if now - lastClick < 0.3 then
			lastClick = 0
			startEdit()
		else
			lastClick = now
		end
	end)

	slider:Set(o.Default ~= nil and o.Default or min, true)
	register(o.Flag, slider)
	local entry = self:_Register(name, row)
	attachDestroy(self, slider, entry, function()
		connMove:Disconnect()
		connEnd:Disconnect()
	end)
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
		TextColor3 = "SubText",
	}, row)

	local box = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(98, 18),
		BackgroundTransparency = 0,
		BackgroundColor3 = "Element",
	}, row)
	local boxStroke = addStroke(box, "Border")
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
		TextColor3 = "SubText",
	}, box)

	local dropdown = { Name = name, Value = nil, Options = options, Kind = "dropdown", Multi = multi }
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

	-- Returns the values of the previous selection that are not in newOptions
	-- ("dropped" is computed against the new list whatever keepValue says).
	function dropdown:Refresh(newOptions, keepValue)
		local dropped = {}
		local previous = multi and self.Value or { self.Value }
		for _, v in ipairs(previous) do
			if table.find(newOptions, v) == nil then
				table.insert(dropped, v)
			end
		end

		self.Options = newOptions
		if multi then
			if keepValue then
				for _, v in ipairs(dropped) do
					selected[v] = nil -- stale entries must not survive a refresh
				end
			else
				table.clear(selected)
			end
			commitMulti(true)
		elseif not keepValue or table.find(newOptions, self.Value) == nil then
			self:Set(newOptions[1], true)
		end
		return dropped
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
		end, multi, o.Searchable == true)
	end)

	if multi then
		dropdown:Set(o.Default or {}, true)
	else
		dropdown:Set(o.Default ~= nil and o.Default or options[1], true)
	end
	register(o.Flag, dropdown)
	local entry = self:_Register(name, row)
	attachDestroy(self, dropdown, entry, function()
		window:_CloseDropdown()
	end)
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
		BackgroundColor3 = "Element",
		Text = name,
		LayoutOrder = self._order,
	}, self.Content)
	local stroke = addStroke(button, "Border")

	local enabled = true
	local icon = nil

	local function buildIcon(spec)
		if icon then
			icon:Destroy()
			icon = nil
		end
		if spec then
			icon = makeIcon(button, spec, 14, "Text", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 8, 0.5, 0),
				ImageTransparency = enabled and 0 or 0.55,
			})
		end
	end
	buildIcon(o.Icon)

	button.MouseEnter:Connect(function()
		if not enabled then
			return
		end
		tween(button, { BackgroundColor3 = T.ElementHover })
		tween(stroke, { Color = T.BorderHover })
	end)
	button.MouseLeave:Connect(function()
		if not enabled then
			return
		end
		tween(button, { BackgroundColor3 = T.Element })
		tween(stroke, { Color = T.Border })
	end)
	button.MouseButton1Down:Connect(function()
		if not enabled then
			return
		end
		tween(button, { BackgroundColor3 = T.ElementPress }, 0.06)
	end)
	button.MouseButton1Up:Connect(function()
		if not enabled then
			return
		end
		tween(button, { BackgroundColor3 = T.ElementHover }, 0.15)
	end)
	button.MouseButton1Click:Connect(function()
		if enabled and o.Callback then
			task.spawn(o.Callback)
		end
	end)

	local entry = self:_Register(name, button)
	local obj = {}
	function obj:SetText(t)
		button.Text = t
	end
	function obj:SetIcon(spec)
		buildIcon(spec)
	end
	function obj:SetVisible(visible)
		setEntryVisible(entry, visible)
	end
	-- disabled = dimmed + clicks (and hover effects) are ignored
	function obj:SetEnabled(state)
		enabled = not not state
		button.TextTransparency = enabled and 0 or 0.55
		stroke.Transparency = enabled and 0 or 0.55
		if icon then
			icon.ImageTransparency = enabled and 0 or 0.55
		end
		if not enabled then
			tween(button, { BackgroundColor3 = T.Element })
			tween(stroke, { Color = T.Border })
		end
	end
	attachDestroy(self, obj, entry)
	return obj
end

----------------------------------------------------------------------
-- Color picker row
----------------------------------------------------------------------

function Groupbox:AddColorPicker(o)
	o = cloneOpts(o)
	local name = o.Name or "Color"
	local row = self:_Row(20)
	create("TextLabel", {
		Size = UDim2.new(1, -30, 1, 0),
		Text = name,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = "SubText",
	}, row)
	local picker = createPicker(self.Window, row, o, 0)
	register(o.Flag, picker)
	local entry = self:_Register(name, row)
	local window = self.Window
	-- replaces the swatch-only destroy: here the whole row goes away
	attachDestroy(self, picker, entry, function()
		window:_CloseDropdown()
	end)
	return picker
end

----------------------------------------------------------------------
-- Theme editor: preset dropdown + one color picker per theme color
----------------------------------------------------------------------

function Groupbox:AddThemeEditor(o)
	o = o or {}
	local keys = o.Keys or { "Accent", "Background", "Panel", "PanelHeader", "Element", "Border", "Text", "SubText" }
	local pickers = {}
	-- per-editor id: two editors (e.g. in two windows) never clobber each other's flags
	Library._themeEditorCount = (Library._themeEditorCount or 0) + 1
	local editorId = Library._themeEditorCount

	local presetDropdown = self:AddDropdown({
		Name = "Preset",
		Options = Library.PresetOrder,
		Default = "Default",
		Callback = function(presetName)
			Library:SetTheme(presetName)
			for key, picker in pairs(pickers) do
				picker:Set(T[key], true)
			end
		end,
	})

	for _, key in ipairs(keys) do
		pickers[key] = self:AddColorPicker({
			Name = key,
			Default = T[key],
			Flag = "theme_" .. editorId .. "_" .. key,
			Callback = function(color)
				Library:SetTheme({ [key] = color })
			end,
		})
	end

	self:AddButton({
		Name = "Reset to Default",
		Callback = function()
			Library:SetTheme("Default")
			presetDropdown:Set("Default", true)
			for key, picker in pairs(pickers) do
				picker:Set(T[key], true)
			end
		end,
	})
	return pickers
end

----------------------------------------------------------------------
-- Textbox
----------------------------------------------------------------------

function Groupbox:AddTextbox(o)
	o = o or {}
	local name = o.Name or "Textbox"
	local multiLine = o.MultiLine == true
	local row = self:_Row(multiLine and 48 or 22)
	create("TextLabel", {
		Size = UDim2.new(1, -124, 1, 0),
		Text = name,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = "SubText",
	}, row)

	local box = create("TextBox", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(116, multiLine and 44 or 18),
		BackgroundTransparency = 0,
		BackgroundColor3 = "Element",
		PlaceholderText = o.Placeholder or "...",
		PlaceholderColor3 = "SubText",
		ClearTextOnFocus = o.ClearTextOnFocus == true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = multiLine and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
		TextWrapped = multiLine,
		MultiLine = multiLine,
		TextSize = 11,
		ClipsDescendants = true,
	}, row)
	local stroke = addStroke(box, "Border")
	addPadding(box, 6, multiLine and 3 or 0, 6, multiLine and 3 or 0)

	local textbox = { Name = name, Value = o.Default or "", Kind = o.Numeric and "number" or "string" }

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
		if o.Numeric then
			local n = tonumber(box.Text)
			if n then
				tween(stroke, { Color = T.Border })
				textbox:Set(n)
			else
				-- invalid number: flash the border red for ~0.4s, then restore it
				stroke.Color = T.Danger
				box.Text = tostring(textbox.Value)
				task.delay(0.4, function()
					if stroke.Parent then
						tween(stroke, { Color = T.Border })
					end
				end)
			end
		else
			tween(stroke, { Color = T.Border })
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

	local initial = o.Default or ""
	if o.Numeric then
		initial = tonumber(initial) or 0
	end
	textbox:Set(initial, true)
	register(o.Flag, textbox)
	local entry = self:_Register(name, row)
	attachDestroy(self, textbox, entry)
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
		TextColor3 = "SubText",
	}, row)

	local kb = { Name = name, Value = o.Default, State = false, Kind = "keybind" }
	local binding = false

	local box = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(88, 18),
		BackgroundTransparency = 0,
		BackgroundColor3 = "Element",
		TextSize = 10,
	}, row)
	local stroke = addStroke(box, function()
		return binding and T.Accent or T.Border
	end)

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

	local connBegan = window:_Connect(UserInputService.InputBegan, function(input, processed)
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
	local connEnded = window:_Connect(UserInputService.InputEnded, function(input)
		if mode == "Hold" and kb.Value and input.KeyCode == kb.Value then
			kb.State = false
			if o.Callback then
				task.spawn(o.Callback, false)
			end
		end
	end)

	-- Right-click: tiny context menu (window:_OpenPopup) with a single "Unbind" entry
	box.MouseButton2Click:Connect(function()
		local pos = box.AbsolutePosition
		local viewport = window.Gui.AbsoluteSize
		local w, h = 88, 20
		local x = math.clamp(pos.X, 4, math.max(viewport.X - w - 4, 4))
		local y = pos.Y + box.AbsoluteSize.Y + 2
		if y + h > viewport.Y then
			y = pos.Y - h - 2
		end
		window:_OpenPopup(Vector2.new(x, y), Vector2.new(w, h), function(frame)
			local item = create("TextButton", {
				Size = UDim2.fromScale(1, 1),
				Text = "Unbind",
				TextSize = 11,
				TextColor3 = "SubText",
				BackgroundColor3 = "ElementHover",
			}, frame)
			item.MouseEnter:Connect(function()
				item.BackgroundTransparency = 0
				item.TextColor3 = T.Accent
			end)
			item.MouseLeave:Connect(function()
				item.BackgroundTransparency = 1
				item.TextColor3 = T.SubText
			end)
			item.MouseButton1Click:Connect(function()
				window:_CloseDropdown()
				kb:Set(nil)
			end)
		end)
	end)

	display()
	register(o.Flag, kb)
	local entry = self:_Register(name, row)
	attachDestroy(self, kb, entry, function()
		connBegan:Disconnect()
		connEnded:Disconnect()
		window:_CloseDropdown()
	end)
	return kb
end

----------------------------------------------------------------------
-- Watermark (small draggable bar: name | player | fps | ping)
----------------------------------------------------------------------

function Library:CreateWatermark(config)
	config = config or {}
	local wm = { Name = config.Name or "WATERMARK", Visible = true }

	local gui = create("ScreenGui", {
		Name = "UILibrary_Watermark",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 999,
		OnTopOfCoreBlur = config.AboveMenu ~= false,
	}, config.Parent or Players.LocalPlayer:WaitForChild("PlayerGui"))

	local frame = create("Frame", {
		Position = config.Position or UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = "Panel",
	}, gui)
	addStroke(frame, "Border")
	addPadding(frame, 8, 0, 8, 0)

	local label = create("TextLabel", {
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = 11,
	}, frame)

	local frames, acc = 0, 0
	local function update(fps)
		local ok, ping = pcall(function()
			return StatsService.Network.ServerStatsItem["Data Ping"]:GetValue()
		end)
		label.Text = string.format(
			"%s  |  %s  |  %s fps  |  %d ms",
			wm.Name,
			Players.LocalPlayer.Name,
			fps and tostring(fps) or "--",
			ok and math.floor(ping) or 0
		)
	end
	update(nil) -- no fake first value: "-- fps" until the first half-second bucket completes

	local renderConn = RunService.RenderStepped:Connect(function(dt)
		frames += 1
		acc += dt
		if acc >= 0.5 then
			update(math.floor(frames / acc + 0.5))
			frames, acc = 0, 0
		end
	end)
	local dragConn = makeDraggable(frame, frame)

	function wm:SetText(name)
		self.Name = name
	end

	function wm:SetVisible(visible)
		self.Visible = visible
		gui.Enabled = visible
	end

	function wm:Destroy()
		renderConn:Disconnect()
		dragConn:Disconnect()
		gui:Destroy()
	end

	return wm
end

----------------------------------------------------------------------
-- Config export / import (JSON string of all Flags)
----------------------------------------------------------------------

function Library:ExportConfig()
	local data = {}
	-- iterate the options (not Flags) so an unbound keybind (nil value) is still exported
	for flag, option in pairs(Library.Options) do
		local value = option.Value
		local t = typeof(value)
		if t == "Color3" then
			data[flag] = { _t = "Color3", v = value:ToHex() }
		elseif t == "EnumItem" then
			data[flag] = { _t = "KeyCode", v = value.Name }
		elseif option.Kind == "keybind" then
			data[flag] = { _t = "KeyCode" } -- unbound
		elseif t == "table" then
			data[flag] = { _t = "List", v = value }
		elseif t == "number" then
			if value == value and value > -1e308 and value < 1e308 then -- NaN / inf cannot be JSON-encoded
				data[flag] = value
			end
		elseif t == "string" or t == "boolean" then
			data[flag] = value
		end
	end
	return HttpService:JSONEncode(data)
end

local function isFiniteNumber(n)
	return type(n) == "number" and n == n and n > -1e308 and n < 1e308
end

-- Checks a decoded config value against the option's kind.
-- Returns (valid, parsedValue); invalid entries are skipped by ImportConfig.
local function parseConfigValue(option, value)
	local kind = option.Kind
	if kind == "boolean" then
		return type(value) == "boolean", value
	elseif kind == "number" then
		return isFiniteNumber(value), value
	elseif kind == "string" then
		return type(value) == "string", value
	elseif kind == "dropdown" then
		if option.Multi then
			if type(value) ~= "table" or value._t ~= "List" or type(value.v) ~= "table" then
				return false
			end
			local list = {}
			for _, item in ipairs(value.v) do
				if type(item) ~= "string" and not isFiniteNumber(item) then
					return false
				end
				table.insert(list, item)
			end
			return true, list
		end
		return type(value) == "string" or isFiniteNumber(value), value
	elseif kind == "color" then
		if type(value) ~= "table" or value._t ~= "Color3" or type(value.v) ~= "string" then
			return false
		end
		local ok, color = pcall(Color3.fromHex, value.v)
		return ok and typeof(color) == "Color3", color
	elseif kind == "keybind" then
		if type(value) ~= "table" or value._t ~= "KeyCode" then
			return false
		end
		if value.v == nil then
			return true, nil -- explicitly unbound
		end
		if type(value.v) ~= "string" then
			return false
		end
		local ok, key = pcall(function()
			return Enum.KeyCode[value.v]
		end)
		return ok and typeof(key) == "EnumItem", key
	end
	return false
end

-- Returns true when at least one entry was applied, otherwise (false, reason).
-- Entries whose type does not match their option (or whose flag is unknown) are skipped silently.
function Library:ImportConfig(json)
	if type(json) ~= "string" or json == "" then
		return false, "empty config"
	end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, json)
	if not ok then
		return false, "malformed JSON"
	end
	if type(data) ~= "table" then
		return false, "config is not a JSON object"
	end
	local applied = 0
	for flag, value in pairs(data) do
		local option = Library.Options[flag]
		if option and option.Kind then
			local valid, parsed = parseConfigValue(option, value)
			if valid then
				option:Set(parsed)
				applied += 1
			end
		end
	end
	if applied == 0 then
		return false, "nothing applied (no known flag with a valid value)"
	end
	return true
end

return Library
