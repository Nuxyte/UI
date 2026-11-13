--!nonstrict
--[[
	Debug.ShowOverlay / HideOverlay / Watch : panneau de diagnostic à l'écran (CLIENT).

	Debug.ShowOverlay(options?)      options : Interval (0.25 s : rafraîchissement)   Position (UDim2)   Modules (true : liste Core)
	Debug.HideOverlay()   Debug.ToggleOverlay()   Debug.IsOverlayVisible()
	Debug.Watch(name, source)        suit une valeur : source = fonction() -> any (relue à chaque rafraîchissement) ou valeur fixe
	Debug.Unwatch(name)
	Debug.GetFPS() -> number         FPS moyen mesuré sur la dernière fenêtre (0 si l'overlay n'a jamais tourné)
	Debug.Report() -> string         rapport texte (modules chargés + temps de chargement, journal, profils, tracés) : fonctionne partout

	Le panneau affiche : FPS, durée de frame (moyenne / max), mémoire, modules Core chargés, valeurs surveillées.
	Il n'utilise la boucle partagée de Core.Engine.Scheduler que tant qu'il est visible.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Driver = require(script.Parent.Parent.Engine.Scheduler)
local Draw = require(script.Parent.Draw)
local Inspect = require(script.Parent.Inspect)
local Logger = require(script.Parent.Logger)
local Profile = require(script.Parent.Profile)

local Overlay = {}

local watches = {}
local watchOrder = {}
local lastFps = 0
local gui, label, handle = nil, nil, nil

local function coreRoot()
	return require(script.Parent.Parent)
end

local function memoryMb(): number?
	local ok, value = pcall(function()
		return game:GetService("Stats"):GetTotalMemoryUsageMb()
	end)
	return if ok and type(value) == "number" then value else nil
end

local function moduleLines(): { string }
	local ok, stats = pcall(function()
		return coreRoot().GetModuleStats()
	end)
	local lines = {}
	if ok and type(stats) == "table" then
		local names = {}
		for name in stats do
			table.insert(names, name)
		end
		table.sort(names)
		for _, name in names do
			table.insert(lines, ("  %s (%.2f ms)"):format(name, (stats[name].LoadTime or 0) * 1000))
		end
	end
	return lines
end

function Overlay.Watch(name: string, source: any)
	if type(name) ~= "string" or name == "" then
		error("Core.Debug.Watch : nom (string) requis", 2)
	end
	if watches[name] == nil then
		table.insert(watchOrder, name)
	end
	watches[name] = source
end

function Overlay.Unwatch(name: string)
	if watches[name] ~= nil then
		watches[name] = nil
		table.remove(watchOrder, table.find(watchOrder, name))
	end
end

function Overlay.GetFPS(): number
	return lastFps
end

function Overlay.Report(): string
	local lines = { "=== Core : rapport de diagnostic ===" }

	table.insert(lines, "Modules chargés :")
	local loaded = moduleLines()
	if #loaded == 0 then
		table.insert(lines, "  (aucun)")
	end
	for _, line in loaded do
		table.insert(lines, line)
	end

	local counts = Logger.GetLogCounts()
	table.insert(lines, ("Journal : %d debug, %d info, %d warn, %d error"):format(counts.Debug, counts.Info, counts.Warn, counts.Error))
	table.insert(lines, ("Mode debug : %s, tracés actifs : %d"):format(tostring(Draw.IsEnabled()), Draw.DrawCount()))

	local profile = Profile.GetProfile()
	if next(profile) ~= nil then
		table.insert(lines, "Profils :")
		table.insert(lines, Profile.ProfileReport(8))
	end
	return table.concat(lines, "\n")
end

local function buildText(frames: number, window: number, worst: number, showModules: boolean): string
	local fps = frames / window
	lastFps = fps
	local lines = { ("FPS %.0f   frame %.1f ms (max %.1f)"):format(fps, window / math.max(frames, 1) * 1000, worst * 1000) }

	local memory = memoryMb()
	if memory then
		table.insert(lines, ("Mémoire %.0f MB"):format(memory))
	end
	table.insert(lines, ("Tracés %d"):format(Draw.DrawCount()))

	for _, name in watchOrder do
		local source = watches[name]
		local ok, value = pcall(function()
			return if type(source) == "function" then source() else source
		end)
		table.insert(lines, ("%s = %s"):format(name, if ok then Inspect.Inspect(value, { Depth = 1 }) else "<erreur>"))
	end

	if showModules then
		local modules = moduleLines()
		if #modules > 0 then
			table.insert(lines, "Modules :")
			for _, line in modules do
				table.insert(lines, line)
			end
		end
	end
	return table.concat(lines, "\n")
end

function Overlay.IsOverlayVisible(): boolean
	return handle ~= nil
end

function Overlay.HideOverlay()
	if handle then
		handle:Cancel()
		handle = nil
	end
	if gui then
		gui:Destroy()
		gui, label = nil, nil
	end
end

function Overlay.ShowOverlay(options: any?)
	if not RunService:IsClient() then
		error("Core.Debug.ShowOverlay : disponible côté client uniquement", 2)
	end
	if handle then
		return
	end
	local opts = options or {}
	local interval = opts.Interval or 0.25

	gui = Instance.new("ScreenGui")
	gui.Name = "CoreDebugOverlay"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10000
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Position = opts.Position or UDim2.fromOffset(8, 8)
	label.Size = UDim2.fromOffset(320, 200)
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.BackgroundTransparency = 0.45
	label.TextColor3 = Color3.new(0.8, 1, 0.8)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Font = Enum.Font.Code
	label.TextSize = 14
	label.Text = "…"
	label.Parent = gui

	local frames, elapsed, worst = 0, 0, 0
	handle = Driver.Run(gui, function(dt)
		frames += 1
		elapsed += dt
		worst = math.max(worst, dt)
		if elapsed >= interval then
			label.Text = buildText(frames, elapsed, worst, opts.Modules ~= false)
			frames, elapsed, worst = 0, 0, 0
		end
	end, function()
		handle = nil
	end)
end

function Overlay.ToggleOverlay(options: any?)
	if handle then
		Overlay.HideOverlay()
	else
		Overlay.ShowOverlay(options)
	end
end

return Overlay
