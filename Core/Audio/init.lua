--!nonstrict
--[[
	Core.Audio
	Audio.Play / PlayAt / Preload / StopAll   (Play.lua)       sons poolés, variations, 3D, fondus
	Audio.GetGroup / SetVolume / GetVolume / Mute / IsMuted / Duck / FadeTo   (Groups.lua)
	Audio.Music.Play / Stop / Pause / Resume / Playlist ...    (Music.lua)

	Hiérarchie : SoundService.Master > Music / SFX / UI / Voice / Ambient (Config.Audio.Groups).
	Aucune boucle Heartbeat : tout repose sur TweenService et les événements Sound.Ended.

	Exemple
		Core.Audio.Play(1843463175, { PitchVariation = 0.1 })
		Core.Audio.PlayAt(explosionSound, hit.Position, { RollOff = { Min = 20, Max = 200 } })
		Core.Audio.Music.Play(musicId)
]]

local Audio = {}

local Groups = require(script.Groups)
local Play = require(script.Play)

local FLAT = { Groups = Groups, Play = Play }
for fileName, module in FLAT do
	for name, value in module do
		if string.sub(name, 1, 1) ~= "_" then
			if Audio[name] ~= nil then
				error(("Core.Audio : conflit de nom '%s' (%s)"):format(name, fileName))
			end
			Audio[name] = value
		end
	end
end

Audio.Music = require(script.Music)

Groups._Init()

return table.freeze(Audio)
