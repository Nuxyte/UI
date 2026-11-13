--!nonstrict
--[[
	Cache : cache clé/valeur avec expiration (TTL) et éviction LRU.
	Aucune boucle en arrière-plan : l'expiration est évaluée à l'accès.

	API
		Cache.new(options?) -> Cache
			options.MaxSize  nombre max d'entrées (défaut illimité)
			options.TTL      durée de vie par défaut en secondes (défaut illimité)
		cache:Set(key, value, ttl?)
		cache:Get(key)           -> value | nil
		cache:Has(key)           -> boolean
		cache:GetOrCompute(key, compute, ttl?) -> value
		cache:Remove(key)
		cache:Clear()
		cache:Size()             -> number
		cache:Purge()            -- supprime les entrées expirées

	Exemple
		local cache = Cache.new({ MaxSize = 100, TTL = 60 })
		local name = cache:GetOrCompute(userId, function() return fetchName(userId) end)
]]

local Cache = {}
Cache.__index = Cache

function Cache.new(options: { MaxSize: number?, TTL: number? }?)
	local opts = options or {}
	return setmetatable({
		_entries = {}, -- key -> { value, expires, used }
		_size = 0,
		_tick = 0,
		_maxSize = opts.MaxSize,
		_ttl = opts.TTL,
	}, Cache)
end

local function isExpired(entry): boolean
	return entry.expires ~= nil and os.clock() >= entry.expires
end

function Cache:_evictOne()
	-- LRU : on retire l'entrée la moins récemment utilisée (O(n), uniquement en cas de dépassement).
	local oldestKey, oldestUsed = nil, math.huge
	for key, entry in self._entries do
		if isExpired(entry) then
			oldestKey = key
			break
		end
		if entry.used < oldestUsed then
			oldestKey, oldestUsed = key, entry.used
		end
	end
	if oldestKey ~= nil then
		self:Remove(oldestKey)
	end
end

function Cache:Set(key: any, value: any, ttl: number?)
	assert(key ~= nil, "Cache:Set : la clé ne peut pas être nil")
	if value == nil then
		self:Remove(key)
		return
	end

	local lifetime = ttl or self._ttl
	self._tick += 1

	if self._entries[key] == nil then
		if self._maxSize and self._size >= self._maxSize then
			self:_evictOne()
		end
		self._size += 1
	end

	self._entries[key] = {
		value = value,
		expires = if lifetime then os.clock() + lifetime else nil,
		used = self._tick,
	}
end

function Cache:Get(key: any): any
	local entry = self._entries[key]
	if entry == nil then
		return nil
	end
	if isExpired(entry) then
		self:Remove(key)
		return nil
	end
	self._tick += 1
	entry.used = self._tick
	return entry.value
end

function Cache:Has(key: any): boolean
	return self:Get(key) ~= nil
end

function Cache:GetOrCompute(key: any, compute: () -> any, ttl: number?): any
	local value = self:Get(key)
	if value == nil then
		value = compute()
		if value ~= nil then
			self:Set(key, value, ttl)
		end
	end
	return value
end

function Cache:Remove(key: any)
	if self._entries[key] ~= nil then
		self._entries[key] = nil
		self._size -= 1
	end
end

function Cache:Clear()
	table.clear(self._entries)
	self._size = 0
end

function Cache:Purge()
	for key, entry in self._entries do
		if isExpired(entry) then
			self:Remove(key)
		end
	end
end

function Cache:Size(): number
	return self._size
end

return Cache
