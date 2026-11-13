--!nonstrict
--[[
	Core.Math
	Bibliothèque mathématique orientée jeu. Toutes les fonctions sont à plat sur
	`Core.Math` (ex. `Core.Math.Lerp`) ET accessibles par catégorie :
		Core.Math.Interpolation / .Trajectory / .Geometry / .Motion

	Voir l'en-tête de chaque fichier pour la liste complète et les exemples :
		Interpolation.lua  Lerp, SmoothLerp, Damp, InverseLerp, Remap, Clamp, Normalize, SmoothStep...
		Trajectory.lua     CalculateLaunchVelocity (+ ByTime / BySpeed), PositionAt, FlightTime, gravité...
		Geometry.lua       Distance, angles, projection, intersections, cercles, Bézier, splines...
		Motion.lua         Oscillate, Wave, Orbit, Spring, SmoothDamp, Inertia

	Le générateur aléatoire est séparé : Core.Random.
]]

local Math = {}

local CATEGORIES = {
	Interpolation = require(script.Interpolation),
	Trajectory = require(script.Trajectory),
	Geometry = require(script.Geometry),
	Motion = require(script.Motion),
}

for categoryName, category in CATEGORIES do
	Math[categoryName] = category
	for name, value in category do
		if Math[name] ~= nil then
			error(("Core.Math : conflit de nom '%s' (catégorie %s)"):format(name, categoryName))
		end
		Math[name] = value
	end
end

return table.freeze(Math)
