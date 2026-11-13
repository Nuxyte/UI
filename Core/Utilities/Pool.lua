--!nonstrict
--[[
	Pool : réutilise des objets coûteux à créer (Parts, Sounds, effets...) au lieu de les détruire.

	Pool.new(options) -> Pool
		options : Create    function(...) -> objet          (requis)
		          Reset     function(objet)                 appelé à la remise dans le pool
		          Destroy   function(objet)                 appelé quand le pool est plein / vidé (défaut : :Destroy() si présent)
		          MaxIdle   nombre max d'objets au repos (défaut 64)
		          Prewarm   nombre d'objets créés d'avance (défaut 0)
	pool:Get(...)              -> objet (réutilisé ou créé ; les arguments vont à Create seulement)
	pool:Release(objet)        -> boolean (false si l'objet n'appartient pas au pool ou est déjà rendu)
	pool:ReleaseAfter(objet, secondes) -> thread
	pool:Stats()               -> { Idle, Active, Created, Destroyed, Reused }
	pool:Clear()               détruit les objets au repos

	Exemple
		local pool = Pool.new({ Create = function() return Instance.new("Part") end, Reset = function(p) p.Parent = nil end })
		local part = pool:Get(); pool:ReleaseAfter(part, 2)
]]

local Pool = {}
Pool.__index = Pool

local function defaultDestroy(object: any)
	if typeof(object) == "Instance" then
		object:Destroy()
	elseif type(object) == "table" and type(object.Destroy) == "function" then
		object:Destroy()
	end
end

function Pool.new(options: any)
	assert(type(options) == "table" and type(options.Create) == "function", "Pool.new : options.Create (function) requis")

	local self = setmetatable({
		_create = options.Create,
		_reset = options.Reset,
		_destroy = options.Destroy or defaultDestroy,
		_maxIdle = options.MaxIdle or 64,
		_idle = {},
		_active = {},
		_created = 0,
		_destroyed = 0,
		_reused = 0,
	}, Pool)

	for _ = 1, options.Prewarm or 0 do
		local object = self._create()
		self._created += 1
		table.insert(self._idle, object)
	end
	return self
end

function Pool:Get(...: any): any
	local object = table.remove(self._idle)
	if object ~= nil then
		self._reused += 1
	else
		object = self._create(...)
		self._created += 1
	end
	self._active[object] = true
	return object
end

function Pool:Release(object: any): boolean
	if not self._active[object] then
		return false
	end
	self._active[object] = nil

	if self._reset then
		local ok, err = pcall(self._reset, object)
		if not ok then
			warn(("[Pool] erreur de Reset : %s"):format(tostring(err)))
		end
	end

	if #self._idle < self._maxIdle then
		table.insert(self._idle, object)
	else
		self._destroyed += 1
		pcall(self._destroy, object)
	end
	return true
end

function Pool:ReleaseAfter(object: any, seconds: number): thread
	return task.delay(seconds, function()
		self:Release(object)
	end)
end

function Pool:Stats()
	local active = 0
	for _ in self._active do
		active += 1
	end
	return { Idle = #self._idle, Active = active, Created = self._created, Destroyed = self._destroyed, Reused = self._reused }
end

function Pool:Clear()
	for _, object in self._idle do
		self._destroyed += 1
		pcall(self._destroy, object)
	end
	table.clear(self._idle)
end

return Pool
