--!nonstrict
--[[
	Core.Debug
	Outils de diagnostic. Aucun coût tant qu'ils ne sont pas appelés (tracés désactivés hors mode debug).

	Logger.lua    Verbose, Info, Warn, Error, Logger(tag), Assert, SetLevel, GetLevel, GetHistory, ClearHistory, OnLog, GetLogCounts
	Inspect.lua   Inspect(value), Print(...)
	Profile.lua   Measure, Time, Benchmark, GetProfile, ResetProfile, ProfileReport
	Draw.lua      Line, Point, Sphere, Box, Arrow, Path, Text, Clear, DrawCount, SetEnabled, IsEnabled, ShowCasts
	Overlay.lua   ShowOverlay, HideOverlay, ToggleOverlay, IsOverlayVisible, Watch, Unwatch, GetFPS, Report

	Exemple
		Core.Debug.SetEnabled(true)
		Core.Debug.ShowCasts(true)                       -- visualise tous les Core.Physics.Raycast
		Core.Debug.Time("spawn", spawnWave)
		Core.Debug.Watch("Santé", function() return health:Get() end)
		Core.Debug.ShowOverlay()
]]

local Debug = {}

local FLAT = {
	Logger = require(script.Logger),
	Inspect = require(script.Inspect),
	Profile = require(script.Profile),
	Draw = require(script.Draw),
	Overlay = require(script.Overlay),
}

for fileName, module in FLAT do
	for name, value in module do
		if Debug[name] ~= nil then
			error(("Core.Debug : conflit de nom '%s' (%s)"):format(name, fileName))
		end
		Debug[name] = value
	end
end

return table.freeze(Debug)
