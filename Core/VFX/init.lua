--!nonstrict
--[[
	Core.VFX
	Effets visuels. Aucune connexion permanente : le rendu n'est lié que pendant une secousse de caméra.

	Emit.lua     Emit, SetEnabled, GetDuration, Play         (modèles de particules préfabriqués, poolés)
	Lines.lua    Beam, Trail
	Screen.lua   Shake, StopShake, Flash (client), Highlight

	Exemple
		Core.VFX.Play(ReplicatedStorage.Effects.Explosion, { Position = hit.Position })
		Core.VFX.Shake(0.6, 0.5)
		Core.VFX.Beam(muzzle.Position, hit.Position, { Color = Color3.new(1, 0.4, 0), Duration = 0.15 })
]]

local VFX = {}

local FLAT = {
	Emit = require(script.Emit),
	Lines = require(script.Lines),
	Screen = require(script.Screen),
}

for fileName, module in FLAT do
	for name, value in module do
		if VFX[name] ~= nil then
			error(("Core.VFX : conflit de nom '%s' (%s)"):format(name, fileName))
		end
		VFX[name] = value
	end
end

return table.freeze(VFX)
