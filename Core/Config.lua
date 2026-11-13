--!strict
--[[
	Core/Config.lua
	Configuration centralisée du framework.

	Modifiable à chaud via `Core.Configure({ ... })` (fusion profonde),
	ou directement en éditant ce fichier.

	Activer / désactiver un module :
		Core.Configure({ Modules = { VFX = false } })
	Un module désactivé lève une erreur claire s'il est demandé (`Core.VFX`),
	et n'est jamais chargé en mémoire.
]]

local Config = {
	-- Mode debug global (utilisé par les modules qui exposent des logs / visualisations).
	Debug = false,

	-- "Debug" | "Info" | "Warn" | "Error" | "Off"
	LogLevel = "Info",

	-- Interrupteurs de modules. `false` = module indisponible.
	Modules = {
		Tween = true,
		Animation = true,
		Math = true,
		Random = true,
		Physics = true,
		Movement = true,
		Pathfinding = true,
		Instance = true,
		UI = true,
		VFX = true,
		Audio = true,
		Gameplay = true,
		Networking = true,
		Utilities = true,
		Debug = true,
	},

	Tween = {
		DefaultDuration = 0.5,
		DefaultEasing = "QuadOut",
	},

	Math = {
		-- nil => utilise workspace.Gravity
		Gravity = nil :: number?,
	},

	Networking = {
		RemotesFolder = "CoreRemotes", -- dossier créé dans ReplicatedStorage
		DefaultRate = 30, -- requêtes/seconde/joueur/canal acceptées
		DefaultBurst = 60, -- rafale maximale
		MaxViolations = 0, -- > 0 : kick du joueur après N violations (0 = jamais)
		InvokeTimeout = 10, -- secondes avant abandon d'un Invoke
		WaitTimeout = 10, -- attente max (client) d'un remote créé par le serveur
		GlobalRate = 120, -- requêtes/seconde/joueur toutes chaînes confondues (false ou 0 = désactivé)
		GlobalBurst = 240,
	},

	VFX = {
		DefaultDuration = 3, -- durée d'un effet continu (émetteurs Enabled) lancé par VFX.Play sans Duration
		PoolSize = 16, -- effets au repos conservés par modèle d'effet
		ShakeFrequency = 18, -- Hz du bruit de la secousse de caméra
	},

	Pathfinding = {
		MaxIterations = 100000, -- noeuds développés au maximum par recherche
		BudgetMs = 2, -- FindAsync : temps maximal par frame
		RepathInterval = 0.5, -- Navigate : intervalle de vérification (s)
	},

	Animation = {
		DefaultFade = 0.15, -- fondu d'entrée / sortie (s) des AnimationTracks lancés par Core.Animation
	},

	Audio = {
		MasterVolume = 1,
		DefaultRollOff = { Min = 10, Max = 120 }, -- Sound 3D (RollOffMinDistance / MaxDistance)
		PoolSize = 16, -- Sound au repos conservés (Play / PlayAt)
		Groups = { "Music", "SFX", "UI", "Voice", "Ambient" }, -- SoundGroups créés à la demande
	},

	Gameplay = {
		RespawnDelay = 3,
		DefaultMaxHealth = 100,
		CooldownTolerance = 0.05, -- tolérance (s) de validation d'un cooldown côté serveur
	},

	DebugTools = {
		Folder = "CoreDebug", -- dossier workspace des visualisations
		DrawLifetime = 1, -- durée d'affichage par défaut d'un tracé (s)
		MaxDrawings = 200, -- plafond de tracés simultanés
		HistorySize = 200, -- entrées conservées par le logger
	},
}

return Config
