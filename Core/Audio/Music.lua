--!nonstrict
--[[
	Audio.Music : musique de fond avec fondu enchaîné et playlists. Un seul morceau actif à la fois.

	Audio.Music.Play(source, options?) -> handle       remplace le morceau actuel par un fondu enchaîné
		options : Fade (1.5 s)   Volume (1)   Loop (true)   Group ("Music")   Restart (false : même morceau => rien ne change)
	Audio.Music.Stop(fade?)        Audio.Music.Pause()      Audio.Music.Resume()
	Audio.Music.Current() -> handle?     Audio.Music.IsPlaying() -> boolean
	Audio.Music.SetVolume(volume, fade?)    volume du morceau actif (le volume du groupe "Music" reste indépendant)

	Audio.Music.Playlist(sources, options?) -> playlist
		options : Shuffle (false)   Loop (true : recommence)   Fade (1.5)   Volume   Group
		playlist:Skip()   playlist:Stop(fade?)   playlist:GetIndex()   playlist.Changed (Signal : index, source)

	Exemple
		Core.Audio.Music.Play(12345678, { Fade = 2 })
		Core.Audio.Music.Playlist({ 111, 222, 333 }, { Shuffle = true })
]]

local Play = require(script.Parent.Play)
local Signal = require(script.Parent.Parent.Utilities.Signal)

local Music = {}

local current = nil -- { handle, key }
local activePlaylist = nil

local function key(source: any): string
	return if typeof(source) == "Instance" then source:GetFullName() else Play.Normalize(source)
end

function Music.Play(source: any, options: any?)
	local opts = options or {}
	local fade = if opts.Fade ~= nil then opts.Fade else 1.5
	local id = key(source)

	if current and not current.handle._finished and current.key == id and not opts.Restart then
		return current.handle
	end

	local previous = current
	if previous then
		previous.handle:Stop(fade)
	end

	local handle = Play.Play(source, {
		Group = opts.Group or "Music",
		Volume = opts.Volume,
		Loop = if opts.Loop == nil then true else opts.Loop,
		FadeIn = fade,
		Parent = opts.Parent,
	})
	local entry = { handle = handle, key = id }
	current = entry
	handle.Ended:Connect(function()
		if current == entry then
			current = nil
		end
	end)
	return handle
end

function Music.Stop(fade: number?)
	if activePlaylist then
		activePlaylist:Stop(fade)
		return
	end
	if current then
		current.handle:Stop(if fade ~= nil then fade else 1.5)
		current = nil
	end
end

function Music.Pause()
	if current then
		current.handle:Pause()
	end
end

function Music.Resume()
	if current then
		current.handle:Resume()
	end
end

function Music.Current()
	return if current then current.handle else nil
end

function Music.IsPlaying(): boolean
	return current ~= nil and current.handle:IsPlaying()
end

function Music.SetVolume(volume: number, fade: number?)
	if current then
		current.handle:SetVolume(volume, fade)
	end
end

function Music.Playlist(sources: { any }, options: any?)
	if type(sources) ~= "table" or #sources == 0 then
		error("Core.Audio.Music.Playlist : liste de morceaux non vide requise", 2)
	end
	local opts = options or {}
	if activePlaylist then
		activePlaylist:Stop(0)
	end

	local order = table.clone(sources)
	local function shuffle()
		for i = #order, 2, -1 do
			local j = math.random(i)
			order[i], order[j] = order[j], order[i]
		end
	end
	if opts.Shuffle then
		shuffle()
	end

	local playlist = { Changed = Signal.new(), _index = 0, _stopped = false }

	local function advance()
		if playlist._stopped then
			return
		end
		playlist._index += 1
		if playlist._index > #order then
			if opts.Loop == false then
				playlist:Stop(0)
				return
			end
			playlist._index = 1
			if opts.Shuffle then
				shuffle()
			end
		end
		local source = order[playlist._index]
		local handle = Music.Play(source, {
			Fade = opts.Fade,
			Volume = opts.Volume,
			Group = opts.Group,
			Loop = false,
			Restart = true,
		})
		playlist.Changed:Fire(playlist._index, source)
		handle.Ended:Connect(function()
			-- fin naturelle du morceau (pas un remplacement par Skip) : on passe au suivant
			if not playlist._stopped and current and current.handle == handle then
				advance()
			elseif not playlist._stopped and current == nil then
				advance()
			end
		end)
	end

	function playlist:Skip()
		if not self._stopped then
			advance()
		end
	end

	function playlist:GetIndex(): number
		return self._index
	end

	function playlist:Stop(fade: number?)
		if self._stopped then
			return
		end
		self._stopped = true
		if activePlaylist == self then
			activePlaylist = nil
		end
		if current then
			current.handle:Stop(if fade ~= nil then fade else 1.5)
			current = nil
		end
		self.Changed:Destroy()
	end

	activePlaylist = playlist
	advance()
	return playlist
end

return Music
