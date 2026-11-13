--!nonstrict
--[[
	Core.Engine : briques de base partagées par tous les systèmes (pas de module activable : toujours présent).
	Scheduler   boucle Heartbeat partagée, arbitrage des mouvements, statistiques  (voir Scheduler.lua)

	Exemple
		local stats = Core.Engine.Scheduler.GetStats()
		print(stats.Active, stats.Connected, stats.ByLabel.Follow)
]]

return table.freeze({
	Scheduler = require(script.Scheduler),
})
