--!nonstrict
--[[
	Gameplay.Zone : zone d'entrée / sortie (checkpoints, zones de capture, de soin, de danger...).
	Détection par requête spatiale à intervalle fixe (pas de Touched : pas de faux positifs ni de ratés), via la boucle
	partagée de Core.Engine.Scheduler ; aucune connexion tant que la zone est arrêtée.

	Zone.new(options) -> zone
		Forme (une seule) : Part (BasePart : suit ses déplacements)  |  CFrame + Size  |  Center + Radius
		Interval (0.2 s)    Filter "Players" (défaut : personnages de joueurs) | "Characters" (tout Model avec Humanoid)
		Ignore { Instance }    AutoStart (true)
	zone.Entered (Signal : character, player?)     zone.Left (Signal : character, player?)
	zone:Start()  zone:Stop()  zone:Pulse()   zone:Contains(character) -> boolean   zone:GetOccupants() -> { Model }
	zone:Destroy()    (un personnage détruit / retiré de la zone déclenche Left au passage suivant)

	Exemple
		local zone = Core.Gameplay.Zone.new({ Part = lavaPart })
		zone.Entered:Connect(function(character, player) damage(character) end)
]]

local Players = game:GetService("Players")

local Cast = require(script.Parent.Parent.Physics.Cast)
local Driver = require(script.Parent.Parent.Engine.Scheduler)
local Signal = require(script.Parent.Parent.Utilities.Signal)

local Zone = {}
Zone.__index = Zone

function Zone.new(options: any)
	local opts = options
	if type(opts) ~= "table" then
		error("Core.Gameplay.Zone.new : options requises", 2)
	end

	local shape
	if opts.Part ~= nil then
		if typeof(opts.Part) ~= "Instance" or not opts.Part:IsA("BasePart") then
			error("Core.Gameplay.Zone.new : Part doit être une BasePart", 2)
		end
		shape = "Part"
	elseif opts.CFrame ~= nil and opts.Size ~= nil then
		if typeof(opts.CFrame) ~= "CFrame" or typeof(opts.Size) ~= "Vector3" then
			error("Core.Gameplay.Zone.new : CFrame et Size (Vector3) attendus", 2)
		end
		shape = "Box"
	elseif opts.Center ~= nil and opts.Radius ~= nil then
		if typeof(opts.Center) ~= "Vector3" or type(opts.Radius) ~= "number" or opts.Radius <= 0 then
			error("Core.Gameplay.Zone.new : Center (Vector3) et Radius (> 0) attendus", 2)
		end
		shape = "Sphere"
	else
		error("Core.Gameplay.Zone.new : forme requise (Part, CFrame + Size ou Center + Radius)", 2)
	end

	local filter = opts.Filter or "Players"
	if filter ~= "Players" and filter ~= "Characters" then
		error("Core.Gameplay.Zone.new : Filter doit valoir 'Players' ou 'Characters'", 2)
	end

	local self = setmetatable({
		Entered = Signal.new(),
		Left = Signal.new(),
		_opts = opts,
		_shape = shape,
		_filter = filter,
		_interval = opts.Interval or 0.2,
		_inside = {},
		_handle = nil,
		_destroyed = false,
	}, Zone)

	if opts.AutoStart ~= false then
		self:Start()
	end
	return self
end

function Zone:_Query(): { Model }
	local castOptions = { Ignore = self._opts.Ignore }
	local parts
	if self._shape == "Part" then
		parts = Cast.GetPartsInBox(self._opts.Part.CFrame, self._opts.Part.Size, castOptions)
	elseif self._shape == "Box" then
		parts = Cast.GetPartsInBox(self._opts.CFrame, self._opts.Size, castOptions)
	else
		parts = Cast.GetPartsInRadius(self._opts.Center, self._opts.Radius, castOptions)
	end
	return Cast.CharactersFromParts(parts, Vector3.zero)
end

function Zone:Pulse()
	local present = {}
	for _, character in self:_Query() do
		local player = Players:GetPlayerFromCharacter(character)
		if self._filter == "Characters" or player ~= nil then
			present[character] = player or false
		end
	end

	for character, player in present do
		if self._inside[character] == nil then
			self._inside[character] = player
			self.Entered:Fire(character, player or nil)
		end
	end
	for character, player in self._inside do
		if present[character] == nil then
			self._inside[character] = nil
			self.Left:Fire(character, player or nil)
		end
	end
end

function Zone:Start()
	if self._handle or self._destroyed then
		return
	end
	local elapsed = self._interval -- première détection immédiate
	self._handle = Driver.Run(nil, function(dt)
		elapsed += dt
		if elapsed >= self._interval then
			elapsed = 0
			self:Pulse()
		end
	end, function()
		self._handle = nil
	end)
end

function Zone:Stop()
	if self._handle then
		self._handle:Cancel()
		self._handle = nil
	end
end

function Zone:Contains(character: Model): boolean
	return self._inside[character] ~= nil
end

function Zone:GetOccupants(): { Model }
	local list = {}
	for character in self._inside do
		table.insert(list, character)
	end
	return list
end

function Zone:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	self:Stop()
	self.Entered:Destroy()
	self.Left:Destroy()
	table.clear(self._inside)
end

return Zone
