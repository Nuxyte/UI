--!nonstrict
--[[
	Physics.Hitbox
	Zone de détection répétée (attaques de mêlée, auras, pièges).

	Hitbox.new(options) -> hitbox
		Shape      "Box" (défaut) | "Sphere"
		Size       Vector3 (Box)        Radius   nombre (Sphere)
		Source     BasePart | Model | function() -> CFrame      repère suivi à chaque frame
		Offset     CFrame (défaut identité)                      décalage local par rapport à Source
		Mode       "Characters" (défaut : Models avec Humanoid, une fois par cible) | "Parts"
		Once       true (défaut) : chaque cible n'est signalée qu'UNE fois par Start()
		Ignore / Whitelist / CollisionGroup
	hitbox:Start()     détection continue (une seule connexion Heartbeat partagée)
	hitbox:Stop()      hitbox:Pulse() -> { cibles }   (un seul test immédiat, sans signaler deux fois si Once)
	hitbox:Reset()     oublie les cibles déjà touchées
	hitbox.Hit (Signal : target, hitbox)       target = Model (Characters) ou BasePart (Parts)
	hitbox:Destroy()   hitbox:IsActive()

	Exemple
		local box = Core.Physics.Hitbox.new({ Size = Vector3.new(4, 4, 6), Source = root, Offset = CFrame.new(0, 0, -4), Ignore = { character } })
		box.Hit:Connect(function(enemyModel) damage(enemyModel) end)
		box:Start(); task.wait(0.3); box:Stop()
]]

local Driver = require(script.Parent.Parent.Engine.Scheduler)
local Signal = require(script.Parent.Parent.Utilities.Signal)
local Cast = require(script.Parent.Cast)

local Hitbox = {}
Hitbox.__index = Hitbox

function Hitbox.new(options: any)
	local opts = options or {}
	local shape = opts.Shape or "Box"
	if shape ~= "Box" and shape ~= "Sphere" then
		error("Core.Physics.Hitbox : Shape doit valoir 'Box' ou 'Sphere'", 2)
	end
	if shape == "Box" and typeof(opts.Size) ~= "Vector3" then
		error("Core.Physics.Hitbox : Size (Vector3) requis pour une Box", 2)
	end
	if shape == "Sphere" and (type(opts.Radius) ~= "number" or opts.Radius <= 0) then
		error("Core.Physics.Hitbox : Radius (> 0) requis pour une Sphere", 2)
	end
	if opts.Source == nil then
		error("Core.Physics.Hitbox : Source (BasePart, Model ou fonction) requis", 2)
	end
	local mode = opts.Mode or "Characters"
	if mode ~= "Characters" and mode ~= "Parts" then
		error("Core.Physics.Hitbox : Mode doit valoir 'Characters' ou 'Parts'", 2)
	end

	return setmetatable({
		Hit = Signal.new(),
		_shape = shape,
		_size = opts.Size,
		_radius = opts.Radius,
		_source = opts.Source,
		_offset = opts.Offset or CFrame.new(),
		_mode = mode,
		_once = opts.Once ~= false,
		_castOptions = { Ignore = opts.Ignore, Whitelist = opts.Whitelist, CollisionGroup = opts.CollisionGroup },
		_seen = {},
		_handle = nil,
	}, Hitbox)
end

function Hitbox:_GetCFrame(): CFrame
	local source = self._source
	local base
	if type(source) == "function" then
		base = source()
	elseif source:IsA("Model") then
		base = source:GetPivot()
	else
		base = source.CFrame
	end
	return base * self._offset
end

function Hitbox:_Query(): { Instance }
	local cframe = self:_GetCFrame()
	local parts
	if self._shape == "Box" then
		parts = Cast.GetPartsInBox(cframe, self._size, self._castOptions)
	else
		parts = Cast.GetPartsInRadius(cframe.Position, self._radius, self._castOptions)
	end

	if self._mode == "Parts" then
		return parts
	end
	return Cast.CharactersFromParts(parts, cframe.Position)
end

function Hitbox:Pulse(): { Instance }
	local reported = {}
	for _, target in self:_Query() do
		if not (self._once and self._seen[target]) then
			self._seen[target] = true
			table.insert(reported, target)
			self.Hit:Fire(target, self)
		end
	end
	return reported
end

function Hitbox:Start()
	if self._handle then
		return
	end
	self._handle = Driver.Run(nil, function()
		self:Pulse()
	end, function()
		self._handle = nil
	end)
end

function Hitbox:Stop()
	if self._handle then
		self._handle:Cancel()
		self._handle = nil
	end
end

function Hitbox:IsActive(): boolean
	return self._handle ~= nil
end

function Hitbox:Reset()
	table.clear(self._seen)
end

function Hitbox:Destroy()
	self:Stop()
	self.Hit:Destroy()
end

return Hitbox
