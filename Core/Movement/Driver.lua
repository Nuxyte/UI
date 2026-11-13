--!nonstrict
--[[
	Movement.Driver — ALIAS de compatibilité (0.2.0)
	Le moteur partagé vit désormais dans Core/Engine/Scheduler.lua ; ce fichier retourne la même table, donc
	`Core.Movement.Driver.Run(...)`, `Core.Movement.Run(...)` et `Core.Engine.Scheduler` sont identiques.
	Nouveautés : arbitrage (Channel / Priority), GetStats, GetActive, CancelAll — voir Engine/Scheduler.lua.
]]

return require(script.Parent.Parent.Engine.Scheduler)
