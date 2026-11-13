--!nonstrict
--[[
	Tween.Easing
	Courbes d'easing. Deux usages :
	  - noms de style pour le tween natif ("QuadOut", "BackInOut", "Linear"...)
	  - fonctions pures (t ∈ [0,1] -> [0,1]) pour le moteur logiciel et vos propres calculs.

	Noms : <Famille><Direction>
		Familles : Linear Sine Quad Cubic Quart Quint Expo (ou Exponential) Circ (ou Circular)
		           Back Elastic Bounce, + SmoothStep SmootherStep (moteur logiciel uniquement)
		Directions : In, Out, InOut. Sans direction (ex. "Quad") => Out.

	API
		Easing.Parse(spec, direction?) -> { Name, Fn, Style?, Direction? }
			spec : "BackOut" | Enum.EasingStyle.X | function(t) -> number
		Easing.Get(spec, direction?)   -> function(t) -> number
		Easing.Apply(spec, t)          -> number
		Easing.Functions.QuadOut(t)    -- accès direct
		Easing.Names                   -- liste triée de tous les noms

	Exemple
		local f = Easing.Get("BackOut")
		print(f(0.5))
]]

local Easing = {}

local pi = math.pi

local function makeSet(inFn: (number) -> number)
	return {
		In = inFn,
		Out = function(t: number): number
			return 1 - inFn(1 - t)
		end,
		InOut = function(t: number): number
			if t < 0.5 then
				return inFn(2 * t) / 2
			end
			return 1 - inFn(2 - 2 * t) / 2
		end,
	}
end

local function identity(t: number): number
	return t
end

local c1 = 1.70158
local c3 = c1 + 1
local c4 = 2 * pi / 3

local function bounceOut(t: number): number
	local n1, d1 = 7.5625, 2.75
	if t < 1 / d1 then
		return n1 * t * t
	elseif t < 2 / d1 then
		t -= 1.5 / d1
		return n1 * t * t + 0.75
	elseif t < 2.5 / d1 then
		t -= 2.25 / d1
		return n1 * t * t + 0.9375
	end
	t -= 2.625 / d1
	return n1 * t * t + 0.984375
end

local function smoothStep(t: number): number
	return t * t * (3 - 2 * t)
end

local function smootherStep(t: number): number
	return t * t * t * (t * (t * 6 - 15) + 10)
end

local FAMILIES = {
	Linear = { In = identity, Out = identity, InOut = identity },
	Sine = makeSet(function(t)
		return 1 - math.cos(t * pi / 2)
	end),
	Quad = makeSet(function(t)
		return t * t
	end),
	Cubic = makeSet(function(t)
		return t * t * t
	end),
	Quart = makeSet(function(t)
		return t * t * t * t
	end),
	Quint = makeSet(function(t)
		return t * t * t * t * t
	end),
	Exponential = makeSet(function(t)
		return if t <= 0 then 0 else 2 ^ (10 * t - 10)
	end),
	Circular = makeSet(function(t)
		return 1 - math.sqrt(math.max(1 - t * t, 0))
	end),
	Back = makeSet(function(t)
		return c3 * t * t * t - c1 * t * t
	end),
	Elastic = makeSet(function(t)
		if t <= 0 then
			return 0
		elseif t >= 1 then
			return 1
		end
		return -(2 ^ (10 * t - 10)) * math.sin((t * 10 - 10.75) * c4)
	end),
	Bounce = makeSet(function(t)
		return 1 - bounceOut(1 - t)
	end),
	-- Moteur logiciel uniquement (pas d'équivalent Enum.EasingStyle).
	SmoothStep = { In = smoothStep, Out = smoothStep, InOut = smoothStep },
	SmootherStep = { In = smootherStep, Out = smootherStep, InOut = smootherStep },
}

local SOFTWARE_ONLY = { SmoothStep = true, SmootherStep = true }
local ALIASES = { Expo = "Exponential", Circ = "Circular" }

-- Table plate de toutes les fonctions : Easing.Functions.QuadOut
local Functions: { [string]: (number) -> number } = {}
local names = {}
for family, set in FAMILIES do
	Functions[family] = set.Out
	table.insert(names, family)
	for _, direction in { "In", "Out", "InOut" } do
		local name = family .. direction
		Functions[name] = set[direction]
		table.insert(names, name)
	end
end
for alias, family in ALIASES do
	Functions[alias] = FAMILIES[family].Out
	for _, direction in { "In", "Out", "InOut" } do
		Functions[alias .. direction] = FAMILIES[family][direction]
	end
end
table.sort(names)

Easing.Functions = table.freeze(Functions)
Easing.Names = table.freeze(names)

local function splitName(name: string): (string, string?)
	local family, direction
	if string.sub(name, -5) == "InOut" then
		family, direction = string.sub(name, 1, -6), "InOut"
	elseif string.sub(name, -3) == "Out" then
		family, direction = string.sub(name, 1, -4), "Out"
	elseif string.sub(name, -2) == "In" then
		family, direction = string.sub(name, 1, -3), "In"
	else
		family, direction = name, nil
	end
	return ALIASES[family] or family, direction
end

local function directionName(direction: any): string?
	if direction == nil then
		return nil
	end
	local name = if typeof(direction) == "EnumItem" then direction.Name else tostring(direction)
	if name ~= "In" and name ~= "Out" and name ~= "InOut" then
		error(("Easing : direction invalide '%s' (In, Out ou InOut)"):format(name), 3)
	end
	return name
end

--- Analyse une spécification d'easing.
function Easing.Parse(spec: any, direction: any?): { Name: string, Fn: (number) -> number, Style: any?, Direction: any? }
	if type(spec) == "function" then
		return { Name = "Custom", Fn = spec, Style = nil, Direction = nil }
	end

	local family: string
	local dir: string?

	if typeof(spec) == "EnumItem" then
		family, dir = spec.Name, nil
	elseif type(spec) == "string" then
		family, dir = splitName(spec)
	else
		error(("Easing : spécification invalide (%s)"):format(typeof(spec)), 3)
	end

	local set = FAMILIES[family]
	if not set then
		error(("Easing : style inconnu '%s'. Exemples valides : QuadOut, BackInOut, Linear, ElasticOut"):format(tostring(spec)), 3)
	end

	local resolved = dir or directionName(direction) or "Out"
	local fn = set[resolved]

	local style, enumDirection = nil, nil
	if not SOFTWARE_ONLY[family] then
		style = Enum.EasingStyle[family]
		enumDirection = Enum.EasingDirection[resolved]
	end

	return { Name = family .. resolved, Fn = fn, Style = style, Direction = enumDirection }
end

function Easing.Get(spec: any, direction: any?): (number) -> number
	return Easing.Parse(spec, direction).Fn
end

function Easing.Apply(spec: any, t: number): number
	return Easing.Parse(spec).Fn(t)
end

return Easing
