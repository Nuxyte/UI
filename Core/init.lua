--!nonstrict
--[[
	Ultimate Roblox Core Framework
	==============================

	Point d'entrée. Les modules sont chargés PARESSEUSEMENT : un module n'est
	`require`d qu'au premier accès (`Core.Tween`, `Core.Math`, ...), donc on
	ne paie que ce qu'on utilise.

		local Core = require(ReplicatedStorage.Core)

		Core.Tween(Part, { Position = Vector3.new(0, 10, 0) }, 1)
		local part = Core.Instance.Create("Part", { Parent = workspace })
		local n = Core.Random.Number(1, 100)
		Core.Wait(2)

	Raccourcis utiles :
		Core.Signal, Core.Maid           -> Utilities.Signal / Utilities.Maid
		Core.Utilities.<Nom>             -> tous les utilitaires
		Core.Require("Nom")              -> chargement explicite
		Core.IsEnabled("Nom")            -> module activé dans Config ET utilisable ? (= Core.IsAvailable)
		Core.GetModuleState("Nom")       -> "Loaded" | "Available" | "Disabled" | "Planned" | "Missing" | "Unknown"
		Core.GetFeatures()               -> { [nom] = état } pour tous les modules connus
		Core.Validate()                  -> { Ok, Problems } : cohérence registre / fichiers / Config.Modules
		Core.Configure({...})            -> fusion profonde dans Config

	Modules réellement disponibles : voir REGISTRY ci-dessous.
]]

local RunService = game:GetService("RunService")

local Config = require(script.Config)

local Core = {}

Core.Version = "0.2.0"
Core.Config = Config
Core.IsServer = RunService:IsServer()
Core.IsClient = RunService:IsClient()

-- Nom public -> chemin sous Core/
local REGISTRY = {
	Tween = { "Tween" },
	Math = { "Math" },
	Random = { "Math", "Random" },
	Instance = { "Instance" },
	Utilities = { "Utilities" },
	Signal = { "Utilities", "Signal" },
	Maid = { "Utilities", "Maid" },
	Networking = { "Networking" },
	Net = { "Networking" },
	UI = { "UI" },
	Movement = { "Movement" },
	Physics = { "Physics" },
	VFX = { "VFX" },
	Audio = { "Audio" },
	Gameplay = { "Gameplay" },
	Debug = { "Debug" },
	Animation = { "Animation" },
	Engine = { "Engine" },
	Pathfinding = { "Pathfinding" },
}

-- Nom public -> clé de Config.Modules qui l'active (par défaut : le nom lui-même).
local SWITCH = {
	Signal = "Utilities",
	Maid = "Utilities",
	Net = "Networking",
}

-- Modules prévus mais pas encore implémentés : erreur explicite plutôt qu'un `nil` obscur.
local PLANNED: { [string]: boolean } = {}

local loadStats = {}

local function load(name: string): any
	local path = REGISTRY[name]
	if not path then
		error(("Core: module inconnu '%s'"):format(name), 3)
	end

	local switch = SWITCH[name] or name
	if Config.Modules[switch] == false then
		error(("Core: le module '%s' est désactivé (Config.Modules.%s = false)"):format(name, switch), 3)
	end

	local instance: Instance = script
	for _, segment in path do
		local child = instance:FindFirstChild(segment)
		if not child then
			error(("Core: fichier introuvable pour '%s' (segment '%s' manquant)"):format(name, segment), 3)
		end
		instance = child
	end

	local startedAt = os.clock()
	local ok, result = pcall(require, instance)
	if ok then
		loadStats[name] = { LoadTime = os.clock() - startedAt, LoadedAt = os.clock() }
	end
	if not ok then
		error(("Core: échec du chargement de '%s' : %s"):format(name, tostring(result)), 3)
	end

	rawset(Core, name, result)
	return result
end

--- Statistiques des modules chargés : { [nom] = { LoadTime = secondes, LoadedAt = os.clock() } }.
function Core.GetModuleStats(): { [string]: { LoadTime: number, LoadedAt: number } }
	return table.clone(loadStats)
end

--- Liste des modules disponibles (nom -> chargé ?).
function Core.GetModules(): { [string]: boolean }
	local result = {}
	for name in REGISTRY do
		result[name] = rawget(Core, name) ~= nil
	end
	return result
end

--- Charge explicitement un module par son nom.
function Core.Require(name: string): any
	local cached = rawget(Core, name)
	if cached ~= nil then
		return cached
	end
	return load(name)
end

local function findNode(name: string): Instance?
	local path = REGISTRY[name]
	if not path then
		return nil
	end
	local instance: Instance? = script
	for _, segment in path do
		instance = instance and instance:FindFirstChild(segment)
	end
	return instance
end

--- État d'un module : "Loaded" (chargé), "Available" (utilisable, pas encore chargé), "Disabled" (Config.Modules = false),
--- "Planned" (annoncé, non implémenté), "Missing" (déclaré mais fichier absent), "Unknown".
function Core.GetModuleState(name: string): string
	if not REGISTRY[name] then
		return if PLANNED[name] then "Planned" else "Unknown"
	end
	if Config.Modules[SWITCH[name] or name] == false then
		return "Disabled"
	end
	if rawget(Core, name) ~= nil then
		return "Loaded"
	end
	return if findNode(name) then "Available" else "Missing"
end

--- Le module peut-il être utilisé maintenant (existe, fichier présent, non désactivé) ?
function Core.IsAvailable(name: string): boolean
	local state = Core.GetModuleState(name)
	return state == "Loaded" or state == "Available"
end

--- Un module est-il activé ET utilisable ? (0.2.0 : faux pour un module inconnu, prévu ou absent ; en 0.1.0 seule la config
--- était lue, ce qui retournait true pour un nom inexistant.)
function Core.IsEnabled(name: string): boolean
	return Core.IsAvailable(name)
end

--- État de tous les modules connus (registre + prévus).
function Core.GetFeatures(): { [string]: string }
	local features = {}
	for name in REGISTRY do
		features[name] = Core.GetModuleState(name)
	end
	for name in PLANNED do
		features[name] = "Planned"
	end
	return features
end

local function knownSwitches(): { [string]: boolean }
	local known = {}
	for name in REGISTRY do
		known[SWITCH[name] or name] = true
	end
	for name in PLANNED do
		known[name] = true
	end
	return known
end

--- Vérifie la cohérence : fichiers du registre présents, clés de Config.Modules connues.
function Core.Validate(): { Ok: boolean, Problems: { string } }
	local problems = {}
	for name in REGISTRY do
		if not findNode(name) then
			table.insert(problems, ("module '%s' déclaré dans le registre mais fichier introuvable"):format(name))
		end
	end
	local known = knownSwitches()
	for key in Config.Modules do
		if not known[key] then
			table.insert(problems, ("Config.Modules.%s : aucun module de ce nom"):format(tostring(key)))
		end
	end
	table.sort(problems)
	return { Ok = #problems == 0, Problems = problems }
end

local function deepMerge(target: { [any]: any }, source: { [any]: any })
	for key, value in source do
		if type(value) == "table" and type(target[key]) == "table" then
			deepMerge(target[key], value)
		else
			target[key] = value
		end
	end
end

--- Fusionne `overrides` dans la configuration centrale.
function Core.Configure(overrides: { [any]: any })
	assert(type(overrides) == "table", "Core.Configure attend une table")
	if type(overrides.Modules) == "table" then
		-- une faute de frappe dans un nom de module ne doit pas être ignorée silencieusement
		local known = knownSwitches()
		for key in overrides.Modules do
			if not known[key] then
				error(("Core.Configure : Modules.%s ne correspond à aucun module connu"):format(tostring(key)), 2)
			end
		end
	end
	deepMerge(Config, overrides)
end

--- Attend `seconds` (task.wait). Retourne le temps réellement écoulé.
function Core.Wait(seconds: number?): number
	return task.wait(seconds)
end

--- Exécute `callback` après `seconds`. Retourne le thread (annulable avec task.cancel).
function Core.Delay(seconds: number, callback: (...any) -> (), ...: any): thread
	return task.delay(seconds, callback, ...)
end

--- Exécute `callback` immédiatement dans un nouveau thread.
function Core.Spawn(callback: (...any) -> (), ...: any): thread
	return task.spawn(callback, ...)
end

--- Exécute `callback` à la prochaine reprise du scheduler.
function Core.Defer(callback: (...any) -> (), ...: any): thread
	return task.defer(callback, ...)
end

setmetatable(Core, {
	__index = function(_, key)
		if type(key) == "string" then
			if REGISTRY[key] then
				return load(key)
			end
			if PLANNED[key] then
				error(("Core.%s n'est pas encore implémenté"):format(key), 2)
			end
		end
		error(("Core.%s n'existe pas"):format(tostring(key)), 2)
	end,
})

return Core
