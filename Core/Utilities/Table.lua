--!nonstrict
--[[
	Table : utilitaires de tables (tableaux ET dictionnaires).
	Aucune fonction ne modifie son entrée sauf mention explicite.

	Copie / fusion
		DeepCopy(t)  Merge(a, b, ...)  DeepMerge(a, b)  Freeze(t) (profond)
	Lecture
		Keys(t)  Values(t)  Count(t)  IsEmpty(t)  IsArray(t)  Contains(array, value)  Find(array, predicate)
		Get(t, "a.b.c", default?)
	Transformation
		Map(t, fn)  Filter(t, predicate)  Reduce(t, fn, initial)  Flatten(array, depth?)  Reverse(array)
		Slice(array, from, to?)  Unique(array)  Chunk(array, size)  GroupBy(array, keyFn)  Zip(a, b)
	Mutation (indiquée par le nom)
		RemoveValue(array, value) -> boolean   (modifie `array`)

	Exemple
		local copy = Table.DeepCopy(config)
		local names = Table.Map(players, function(p) return p.Name end)
]]

local Table = {}

function Table.DeepCopy(value: any, _seen: { [any]: any }?): any
	if type(value) ~= "table" then
		return value
	end
	local seen = _seen or {}
	if seen[value] then
		return seen[value]
	end
	local copy = {}
	seen[value] = copy
	for k, v in value do
		copy[Table.DeepCopy(k, seen)] = Table.DeepCopy(v, seen)
	end
	return setmetatable(copy, getmetatable(value))
end

--- Fusion superficielle : les tables suivantes écrasent les précédentes. Retourne une nouvelle table.
function Table.Merge(...: { [any]: any }): { [any]: any }
	local result = {}
	for i = 1, select("#", ...) do
		local source = select(i, ...)
		if source then
			for k, v in source do
				result[k] = v
			end
		end
	end
	return result
end

--- Fusion récursive des sous-tables (dictionnaires). Retourne une nouvelle table.
function Table.DeepMerge(base: { [any]: any }, override: { [any]: any }): { [any]: any }
	local result = Table.DeepCopy(base)
	for k, v in override do
		if type(v) == "table" and type(result[k]) == "table" and not Table.IsArray(v) then
			result[k] = Table.DeepMerge(result[k], v)
		else
			result[k] = Table.DeepCopy(v)
		end
	end
	return result
end

function Table.Freeze(t: { [any]: any }): { [any]: any }
	for _, v in t do
		if type(v) == "table" and not table.isfrozen(v) then
			Table.Freeze(v)
		end
	end
	return table.freeze(t)
end

function Table.Keys(t: { [any]: any }): { any }
	local keys = {}
	for k in t do
		table.insert(keys, k)
	end
	return keys
end

function Table.Values(t: { [any]: any }): { any }
	local values = {}
	for _, v in t do
		table.insert(values, v)
	end
	return values
end

function Table.Count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

function Table.IsEmpty(t: { [any]: any }): boolean
	return next(t) == nil
end

function Table.IsArray(t: { [any]: any }): boolean
	if type(t) ~= "table" then
		return false
	end
	local n = 0
	for _ in t do
		n += 1
	end
	return n == #t
end

function Table.Contains(array: { any }, value: any): boolean
	return table.find(array, value) ~= nil
end

--- Retourne (valeur, index) du premier élément validant `predicate`, ou nil.
function Table.Find(array: { any }, predicate: (any, number) -> boolean): (any, number?)
	for i, v in array do
		if predicate(v, i) then
			return v, i
		end
	end
	return nil, nil
end

--- Accès par chemin : Table.Get(t, "a.b.c", default)
function Table.Get(t: { [any]: any }, path: string, default: any?): any
	local current: any = t
	for key in string.gmatch(path, "[^%.]+") do
		if type(current) ~= "table" then
			return default
		end
		current = current[key]
		if current == nil then
			return default
		end
	end
	return current
end

function Table.Map(t: { [any]: any }, fn: (any, any) -> any): { [any]: any }
	local result = {}
	for k, v in t do
		result[k] = fn(v, k)
	end
	return result
end

--- Pour un tableau, le résultat est un tableau compact ; pour un dictionnaire, les clés sont conservées.
function Table.Filter(t: { [any]: any }, predicate: (any, any) -> boolean): { [any]: any }
	local result = {}
	if Table.IsArray(t) then
		for i, v in t do
			if predicate(v, i) then
				table.insert(result, v)
			end
		end
	else
		for k, v in t do
			if predicate(v, k) then
				result[k] = v
			end
		end
	end
	return result
end

function Table.Reduce(t: { [any]: any }, fn: (any, any, any) -> any, initial: any): any
	local accumulator = initial
	for k, v in t do
		accumulator = fn(accumulator, v, k)
	end
	return accumulator
end

function Table.Flatten(array: { any }, depth: number?): { any }
	local maxDepth = depth or math.huge
	local result = {}
	local function walk(source: { any }, level: number)
		for _, v in source do
			if type(v) == "table" and level < maxDepth then
				walk(v, level + 1)
			else
				table.insert(result, v)
			end
		end
	end
	walk(array, 0)
	return result
end

function Table.Reverse(array: { any }): { any }
	local n = #array
	local result = table.create(n)
	for i = 1, n do
		result[i] = array[n - i + 1]
	end
	return result
end

function Table.Slice(array: { any }, from: number, to: number?): { any }
	return table.move(array, from, to or #array, 1, {})
end

function Table.Unique(array: { any }): { any }
	local seen, result = {}, {}
	for _, v in array do
		if not seen[v] then
			seen[v] = true
			table.insert(result, v)
		end
	end
	return result
end

function Table.Chunk(array: { any }, size: number): { { any } }
	assert(size >= 1, "Table.Chunk : `size` doit être >= 1")
	local chunks = {}
	for i = 1, #array, size do
		table.insert(chunks, table.move(array, i, math.min(i + size - 1, #array), 1, {}))
	end
	return chunks
end

function Table.GroupBy(array: { any }, keyFn: (any) -> any): { [any]: { any } }
	local groups = {}
	for _, v in array do
		local key = keyFn(v)
		local group = groups[key]
		if not group then
			group = {}
			groups[key] = group
		end
		table.insert(group, v)
	end
	return groups
end

function Table.Zip(a: { any }, b: { any }): { { any } }
	local result = {}
	for i = 1, math.min(#a, #b) do
		result[i] = { a[i], b[i] }
	end
	return result
end

--- Retire la première occurrence de `value` (MODIFIE `array`).
function Table.RemoveValue(array: { any }, value: any): boolean
	local index = table.find(array, value)
	if index then
		table.remove(array, index)
		return true
	end
	return false
end

return Table
