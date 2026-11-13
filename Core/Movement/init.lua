--!nonstrict
--[[
	Core.Movement
	Déplacements prêts à l'emploi. Toutes les fonctions sont à plat (`Core.Movement.Follow`).

	Path.lua      MoveTo, FollowPath, Patrol           déplacement vers un point / le long d'un chemin
	Follow.lua    Follow, Orbit, Hover                 suivi de cible, orbite, flottement
	Physical.lua  Dash, Knockback                      mouvements physiques (LinearVelocity / ApplyImpulse)
	Driver.lua    Run, GetStats, GetActive, CancelAll  alias de Core/Engine/Scheduler (connexion Heartbeat unique, arbitrage, statistiques)
	Util.lua      GetCFrame, SetPosition, Resolve...   accès uniforme BasePart / Model

	Tous les mouvements retournent un handle : :Pause() :Resume() :Cancel() :Wait() .Completed .State
	et s'annulent seuls si l'objet est détruit.

	ARBITRAGE (0.2.0) — options communes à tous les mouvements : Channel (string), Priority (number, 0), OnConflict ("Replace" | "Reject").
	Deux mouvements sur le même objet et le même Channel : le nouveau remplace l'ancien s'il a une Priority >= ; sinon il est rejeté
	(handle déjà "Cancelled", .Rejected = true). Sans Channel : pas d'arbitrage (comportement 0.1.0).
	Movement.GetStats() / GetActive(target?) / CancelAll(target?, channel?) / ResetStats() : suivi des mouvements actifs.

	Exemple
		local Movement = Core.Movement
		Movement.MoveTo(door, door.Position + Vector3.new(0, 8, 0), { Duration = 1.5, Easing = "BackOut" })
		Movement.Follow(pet, character.HumanoidRootPart, { Offset = Vector3.new(3, 2, 0), Face = true })
		Movement.Orbit(satellite, planet, { Radius = 20, Speed = 0.5 })
		Movement.FollowPath(npc, waypoints, { Speed = 12, Face = "Yaw", Loop = "PingPong" })
]]

local MovementModule = {}

local CATEGORIES = {
	Path = require(script.Path),
	Follow = require(script.Follow),
	Physical = require(script.Physical),
	Driver = require(script.Driver),
	Util = require(script.Util),
}

for categoryName, category in CATEGORIES do
	for name, value in category do
		if MovementModule[name] ~= nil then
			error(("Core.Movement : conflit de nom '%s' (%s)"):format(name, categoryName))
		end
		MovementModule[name] = value
	end
end

-- Alias de compatibilité 0.1.0 : Core.Movement.Driver == Core.Engine.Scheduler
MovementModule.Driver = CATEGORIES.Driver

return table.freeze(MovementModule)
