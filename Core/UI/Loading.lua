--!nonstrict
--[[
	UI.LoadingScreen
	Écran de chargement plein écran avec barre de progression.

	LoadingScreen.Show(options?)          options : Title ("Chargement...")  Tip (string | { string })
	                                                BackgroundColor  AccentColor  DisplayOrder (5000)
	LoadingScreen.SetProgress(value, text?)   value 0..1 ; text remplace le pourcentage
	LoadingScreen.SetTitle(text)
	LoadingScreen.Preload(assets)         précharge via ContentProvider:PreloadAsync et met la barre à jour (yield)
	LoadingScreen.Hide(duration?)         fondu (0.5 s) puis destruction ; retourne immédiatement
	LoadingScreen.IsVisible() -> boolean

	Exemple
		UI.LoadingScreen.Show({ Title = "Bienvenue", Tip = { "Astuce : sautez !", "Astuce : explorez !" } })
		UI.LoadingScreen.Preload(workspace.Map:GetDescendants())
		UI.LoadingScreen.Hide()
]]

local Create = require(script.Parent.Create)
local Animate = require(script.Parent.Animate)
local Widgets = require(script.Parent.Widgets)

local Loading = {}

local current = nil

function Loading.Show(options: any?)
	if current then
		return Loading
	end
	local opts = options or {}

	local screen = Create.ScreenGui("CoreLoading", {
		DisplayOrder = opts.DisplayOrder or 5000,
		IgnoreGuiInset = true,
	})
	local background = Create.Frame({
		Name = "Background",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = opts.BackgroundColor or Color3.fromRGB(16, 17, 22),
		Active = true, -- bloque les clics vers l'UI en dessous
		Parent = screen,
	})
	local title = Create.Label({
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(600, 48),
		Text = opts.Title or "Chargement...",
		TextSize = 36,
		Font = Enum.Font.GothamBold,
		Parent = background,
	})

	local tip = opts.Tip
	if type(tip) == "table" then
		tip = tip[math.random(1, #tip)]
	end
	if tip then
		Create.Label({
			Name = "Tip",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -32),
			Size = UDim2.fromOffset(600, 24),
			Text = tostring(tip),
			TextTransparency = 0.3,
			TextSize = 15,
			Parent = background,
		})
	end

	local bar = Widgets.ProgressBar({
		Parent = background,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromOffset(360, 14),
		FillColor = opts.AccentColor,
	})

	current = { screen = screen, background = background, title = title, bar = bar }
	return Loading
end

function Loading.SetProgress(value: number, text: string?)
	if not current then
		return
	end
	current.bar:Set(value)
	current.bar:SetText(text)
end

function Loading.SetTitle(text: string)
	if current then
		current.title.Text = text
	end
end

function Loading.Preload(assets: { any })
	local total = #assets
	if total == 0 then
		Loading.SetProgress(1)
		return
	end

	local done = 0
	game:GetService("ContentProvider"):PreloadAsync(assets, function()
		done += 1
		Loading.SetProgress(done / total, ("%d / %d"):format(done, total))
	end)
	Loading.SetProgress(1)
end

function Loading.Hide(duration: number?)
	local active = current
	if not active then
		return
	end
	current = nil

	local function destroy()
		active.screen:Destroy()
	end
	if Animate.Close(active.background, { Style = "Fade", Duration = duration or 0.5, OnComplete = destroy }) == nil then
		destroy()
	end
end

function Loading.IsVisible(): boolean
	return current ~= nil
end

return Loading
