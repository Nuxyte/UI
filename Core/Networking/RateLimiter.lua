--!nonstrict
--[[
	Networking.RateLimiter
	Token bucket par clé (ex. joueur). Aucune boucle de fond : le remplissage est calculé à l'appel.

	RateLimiter.new(rate, burst?) -> limiter     rate = jetons/seconde, burst = capacité (défaut rate*2)
	limiter:Allow(key, cost?)     -> boolean     consomme `cost` jetons (défaut 1) si disponibles
	limiter:Remove(key)                          libère la mémoire (à appeler quand le joueur part)
	limiter:Clear()
]]

local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(rate: number, burst: number?)
	assert(type(rate) == "number" and rate > 0, "RateLimiter.new : rate doit être > 0")
	return setmetatable({
		_rate = rate,
		_burst = burst or rate * 2,
		_buckets = {},
	}, RateLimiter)
end

function RateLimiter:Allow(key: any, cost: number?): boolean
	local amount = cost or 1
	local now = os.clock()
	local bucket = self._buckets[key]

	if bucket == nil then
		bucket = { tokens = self._burst, last = now }
		self._buckets[key] = bucket
	else
		bucket.tokens = math.min(self._burst, bucket.tokens + (now - bucket.last) * self._rate)
		bucket.last = now
	end

	if bucket.tokens >= amount then
		bucket.tokens -= amount
		return true
	end
	return false
end

function RateLimiter:Remove(key: any)
	self._buckets[key] = nil
end

function RateLimiter:Clear()
	table.clear(self._buckets)
end

return RateLimiter
