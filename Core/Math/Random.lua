--!nonstrict
--[[
	Random : utilitaires aléatoires (non seedé par défaut, seedable via Random.Seeded).
	Les mêmes méthodes existent sur le module (générateur par défaut) et sur un générateur seedé.

	Nombres
		Number(min?, max?)            flottant dans [min, max]  (défaut 0..1)
		Integer(min, max)             entier dans [min, max]
		Boolean(chance?)              true avec probabilité `chance` (défaut 0.5)
		Chance(percent)               true avec `percent` % de chances (0..100)
	Vecteurs / positions
		Vector3(min?, max?)           chaque axe tiré entre min et max (Vector3). Défaut (0,0,0)..(1,1,1)
		Vector2(min?, max?)
		Direction()                   vecteur unitaire uniforme sur la sphère
		Direction2D()                 vecteur unitaire du plan XZ
		PointInBox(cframe, size)      point uniforme dans une boîte orientée
		PointInPart(part)             point uniforme dans le volume d'un BasePart
		PointInCircle(center, radius, normal?)   disque (uniforme)
		PointOnCircle(center, radius, normal?)   bord du cercle
		PointInSphere(center, radius)            boule (uniforme)
		PointOnSphere(center, radius)            surface (uniforme)
		Color()                       Color3 aléatoire
	Listes
		Choice(list)                  élément aléatoire
		Sample(list, count)           `count` éléments distincts
		Shuffle(list, inPlace?)       Fisher-Yates ; nouvelle table sauf si inPlace
		Weighted(items)               items = { {Value=x, Weight=n}, ... } ou { [valeur] = poids }
		String(length, charset?)
	Seed
		Random.Seeded(seed) -> générateur indépendant et reproductible
		Random.SetSeed(seed)          re-seed le générateur par défaut

	Exemple
		local n = Core.Random.Number(1, 100)
		local loot = Core.Random.Weighted({ Common = 70, Rare = 25, Epic = 5 })
		local gen = Core.Random.Seeded(1234); gen:Integer(1, 6)
]]

local Generator = {}
Generator.__index = Generator

function Generator.new(seed: number?)
	return setmetatable({
		Seed = seed,
		_rng = if seed then Random.new(seed) else Random.new(),
	}, Generator)
end

local function sortedKeys(map: { [any]: any }): { any }
	local keys = {}
	for key in map do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	return keys
end

-- Base orthonormée du plan de normale `normal` (défaut Y).
local function planeBasis(normal: Vector3?): (Vector3, Vector3)
	if normal == nil then
		return Vector3.xAxis, Vector3.zAxis
	end
	local n = normal.Unit
	local reference = if math.abs(n.Y) < 0.99 then Vector3.yAxis else Vector3.xAxis
	local right = n:Cross(reference).Unit
	return right, n:Cross(right)
end

function Generator:Number(min: number?, max: number?): number
	local lo, hi = min or 0, max or 1
	if lo > hi then
		lo, hi = hi, lo
	end
	if lo == hi then
		return lo
	end
	return self._rng:NextNumber(lo, hi)
end

function Generator:Integer(min: number, max: number): number
	assert(min ~= nil and max ~= nil, "Random.Integer : min et max requis")
	local lo, hi = math.floor(min), math.floor(max)
	if lo > hi then
		lo, hi = hi, lo
	end
	return self._rng:NextInteger(lo, hi)
end

function Generator:Boolean(chance: number?): boolean
	return self._rng:NextNumber() < (chance or 0.5)
end

function Generator:Chance(percent: number): boolean
	return self._rng:NextNumber() * 100 < percent
end

function Generator:Vector3(min: Vector3?, max: Vector3?): Vector3
	local lo, hi = min or Vector3.zero, max or Vector3.one
	return Vector3.new(self:Number(lo.X, hi.X), self:Number(lo.Y, hi.Y), self:Number(lo.Z, hi.Z))
end

function Generator:Vector2(min: Vector2?, max: Vector2?): Vector2
	local lo, hi = min or Vector2.zero, max or Vector2.one
	return Vector2.new(self:Number(lo.X, hi.X), self:Number(lo.Y, hi.Y))
end

function Generator:Direction(): Vector3
	local z = self:Number(-1, 1)
	local angle = self:Number(0, 2 * math.pi)
	local radius = math.sqrt(1 - z * z)
	return Vector3.new(radius * math.cos(angle), z, radius * math.sin(angle))
end

function Generator:Direction2D(): Vector3
	local angle = self:Number(0, 2 * math.pi)
	return Vector3.new(math.cos(angle), 0, math.sin(angle))
end

function Generator:PointInBox(cframe: CFrame, size: Vector3): Vector3
	local half = size / 2
	return cframe * self:Vector3(-half, half)
end

function Generator:PointInPart(part: BasePart): Vector3
	return self:PointInBox(part.CFrame, part.Size)
end

function Generator:PointOnCircle(center: Vector3, radius: number, normal: Vector3?): Vector3
	local right, forward = planeBasis(normal)
	local angle = self:Number(0, 2 * math.pi)
	return center + right * (math.cos(angle) * radius) + forward * (math.sin(angle) * radius)
end

function Generator:PointInCircle(center: Vector3, radius: number, normal: Vector3?): Vector3
	local right, forward = planeBasis(normal)
	local angle = self:Number(0, 2 * math.pi)
	local r = radius * math.sqrt(self._rng:NextNumber()) -- sqrt => densité uniforme
	return center + right * (math.cos(angle) * r) + forward * (math.sin(angle) * r)
end

function Generator:PointOnSphere(center: Vector3, radius: number): Vector3
	return center + self:Direction() * radius
end

function Generator:PointInSphere(center: Vector3, radius: number): Vector3
	local r = radius * (self._rng:NextNumber() ^ (1 / 3)) -- racine cubique => densité uniforme
	return center + self:Direction() * r
end

function Generator:Color(): Color3
	return Color3.new(self._rng:NextNumber(), self._rng:NextNumber(), self._rng:NextNumber())
end

function Generator:Choice(list: { any }): any
	local n = #list
	if n == 0 then
		return nil
	end
	return list[self._rng:NextInteger(1, n)]
end

function Generator:Shuffle(list: { any }, inPlace: boolean?): { any }
	local result = if inPlace then list else table.clone(list)
	for i = #result, 2, -1 do
		local j = self._rng:NextInteger(1, i)
		result[i], result[j] = result[j], result[i]
	end
	return result
end

function Generator:Sample(list: { any }, count: number): { any }
	local pool = self:Shuffle(list)
	local n = math.clamp(math.floor(count), 0, #pool)
	return table.move(pool, 1, n, 1, {})
end

--- items : { {Value = x, Weight = n}, ... }  ou  { [valeur] = poids }.
--- Les poids <= 0 ne sont jamais tirés. Retourne nil si aucun poids positif.
function Generator:Weighted(items: { [any]: any }): any
	local entries: { { Value: any, Weight: number } } = {}

	local first = items[1]
	if type(first) == "table" and first.Weight ~= nil then
		for _, entry in items do
			table.insert(entries, entry)
		end
	else
		-- Dictionnaire : clés triées pour que les tirages seedés restent reproductibles.
		for _, key in sortedKeys(items) do
			table.insert(entries, { Value = key, Weight = items[key] })
		end
	end

	local total = 0
	for _, entry in entries do
		if type(entry.Weight) ~= "number" then
			error("Random.Weighted : poids non numérique", 2)
		end
		if entry.Weight > 0 then
			total += entry.Weight
		end
	end
	if total <= 0 then
		return nil
	end

	local roll = self._rng:NextNumber() * total
	for _, entry in entries do
		if entry.Weight > 0 then
			roll -= entry.Weight
			if roll < 0 then
				return entry.Value
			end
		end
	end
	-- Sécurité flottante : dernier élément à poids positif.
	for i = #entries, 1, -1 do
		if entries[i].Weight > 0 then
			return entries[i].Value
		end
	end
	return nil
end

function Generator:String(length: number, charset: string?): string
	local chars = charset or "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	assert(#chars > 0, "Random.String : charset vide")
	local out = table.create(length)
	for i = 1, length do
		local index = self._rng:NextInteger(1, #chars)
		out[i] = string.sub(chars, index, index)
	end
	return table.concat(out)
end

-- Module : générateur par défaut ----------------------------------------

local RandomModule = {}

local default = Generator.new()

for name, fn in Generator do
	if type(fn) == "function" and name ~= "new" then
		RandomModule[name] = function(...)
			return fn(default, ...)
		end
	end
end

--- Crée un générateur indépendant et reproductible.
function RandomModule.Seeded(seed: number)
	assert(type(seed) == "number", "Random.Seeded : seed numérique requis")
	return Generator.new(seed)
end

--- Re-seed le générateur par défaut (reproductibilité globale).
function RandomModule.SetSeed(seed: number?)
	default = Generator.new(seed)
end

return RandomModule
