--!nonstrict
--[[
	Core.Gameplay
	Briques de gameplay réutilisables, indépendantes les unes des autres (aucune boucle permanente) :

	Health.new(options)          vie, dégâts, soins, régénération, mort / réanimation        (serveur)
	Cooldown.new(d) / .Keyed(d)  temps de recharge simple ou par clé (joueur, compétence...)
	Inventory.new(options)       inventaire à emplacements et piles, sérialisable
	Stats.new(base, limits)      statistiques avec modificateurs temporaires / permanents
	StateMachine.new(def)        machine à états (Allow, Enter, Exit)
	Interact.Create(target, o)   ProximityPrompt validé côté serveur (distance, recharge, règle)
	Zone.new(options)            détection d'entrée / sortie de zone

	Exemple
		local Gameplay = Core.Gameplay
		local hp = Gameplay.Health.new({ Max = 100, Regen = 2 })
		local dash = Gameplay.Cooldown.new(1.5)
		if dash:Use() then hp:Damage(10, "Fatigue") end
]]

return table.freeze({
	Health = require(script.Health),
	Cooldown = require(script.Cooldown),
	Inventory = require(script.Inventory),
	Stats = require(script.Stats),
	StateMachine = require(script.StateMachine),
	Interact = require(script.Interact),
	Zone = require(script.Zone),
})
