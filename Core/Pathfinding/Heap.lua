--!nonstrict
--[[
	Pathfinding.Heap
	Tas binaire min (file de priorité) : push/pop en O(log n), sans allocation par élément.

	Heap.new() -> heap
	heap:Push(value, priority, tie?)    tie : départage les priorités égales (plus petit d'abord)
	heap:Pop() -> value, priority       nil si vide
	heap:Peek() -> value, priority      heap:Size()   heap:IsEmpty()   heap:Clear()
]]

local Heap = {}
Heap.__index = Heap

function Heap.new()
	return setmetatable({ _values = {}, _priorities = {}, _ties = {}, _size = 0 }, Heap)
end

local function less(self, i, j): boolean
	local pi, pj = self._priorities[i], self._priorities[j]
	if pi ~= pj then
		return pi < pj
	end
	return self._ties[i] < self._ties[j]
end

local function swap(self, i, j)
	local v, p, t = self._values, self._priorities, self._ties
	v[i], v[j] = v[j], v[i]
	p[i], p[j] = p[j], p[i]
	t[i], t[j] = t[j], t[i]
end

function Heap:Push(value: any, priority: number, tie: number?)
	if type(priority) ~= "number" or priority ~= priority then
		error("Core.Pathfinding.Heap:Push : priorité numérique (non NaN) requise", 2)
	end
	local index = self._size + 1
	self._size = index
	self._values[index], self._priorities[index], self._ties[index] = value, priority, tie or 0
	while index > 1 do
		local parent = index // 2
		if less(self, index, parent) then
			swap(self, index, parent)
			index = parent
		else
			break
		end
	end
end

function Heap:Pop(): (any, number?)
	local size = self._size
	if size == 0 then
		return nil, nil
	end
	local v, p, t = self._values, self._priorities, self._ties
	local value, priority = v[1], p[1]
	v[1], p[1], t[1] = v[size], p[size], t[size]
	v[size], p[size], t[size] = nil, nil, nil
	size -= 1
	self._size = size

	local index = 1
	while true do
		local left, right, smallest = index * 2, index * 2 + 1, index
		if left <= size and less(self, left, smallest) then
			smallest = left
		end
		if right <= size and less(self, right, smallest) then
			smallest = right
		end
		if smallest == index then
			break
		end
		swap(self, index, smallest)
		index = smallest
	end
	return value, priority
end

function Heap:Peek(): (any, number?)
	return self._values[1], self._priorities[1]
end

function Heap:Size(): number
	return self._size
end

function Heap:IsEmpty(): boolean
	return self._size == 0
end

function Heap:Clear()
	table.clear(self._values)
	table.clear(self._priorities)
	table.clear(self._ties)
	self._size = 0
end

return Heap
