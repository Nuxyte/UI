--!nonstrict
--[[
	Core.Physics
	Physique simplifiée. Fonctions à plat (`Core.Physics.Launch`) + sous-modules.

	Forces.lua      Launch, LaunchTo, Impulse, Push, AngularImpulse, Force, SetGravity, Pull, Field, Explode
	Cast.lua        Raycast, Spherecast, Blockcast, RaycastBetween, HasLineOfSight, GetPartsInRadius, GetPartsInBox,
	                GetCharactersInRadius, SetHook
	Projectile.lua  Core.Physics.Projectile.Fire(options)      projectiles cinématiques balayés
	Hitbox.lua      Core.Physics.Hitbox.new(options)           zones de détection répétées
	Util.lua        GetRoot, GetPosition, GetMass

	Dépend de Core.Math (trajectoires) et de Core.Engine.Scheduler (boucle partagée).

	Exemple (voir la demande initiale)
		local Velocity = Core.Math.CalculateLaunchVelocity(StartPosition, TargetPosition, 15)
		Core.Physics.Launch(Object, Velocity)
]]

local PhysicsModule = {}

local FLAT = {
	Forces = require(script.Forces),
	Cast = require(script.Cast),
	Util = require(script.Util),
}

for fileName, module in FLAT do
	for name, value in module do
		if PhysicsModule[name] ~= nil then
			error(("Core.Physics : conflit de nom '%s' (%s)"):format(name, fileName))
		end
		PhysicsModule[name] = value
	end
end

PhysicsModule.Projectile = require(script.Projectile)
PhysicsModule.Hitbox = require(script.Hitbox)

return table.freeze(PhysicsModule)
