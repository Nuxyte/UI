--!nonstrict
--[[
	Gameplay.Inventory : inventaire à emplacements avec piles. Données pures (aucune Instance), sérialisable.

	Inventory.new(options?) -> inventory
		options : Slots (20)   MaxStack (99)   StackLimits { [id] = n }  ou  function(id) -> n

	inventory:Add(id, amount?) -> added, leftover       complète les piles existantes puis remplit les emplacements libres
	inventory:Remove(id, amount?) -> boolean            tout ou rien : false (sans rien retirer) si le total est insuffisant
	inventory:CanAdd(id, amount?) -> boolean
	inventory:Count(id) / Has(id, amount?) / GetSlot(index) -> { Id, Count }? / GetItems() -> { [id] = total }
	inventory:Swap(a, b)   inventory:Clear()   inventory:FreeSlots() -> number   inventory:Size()
	inventory:Serialize() -> { Slots, Items = { {Slot, Id, Count} } }       Inventory.Deserialize(data, options?) -> inventory
	Signaux : Changed(id, delta)   SlotChanged(index, slot?)

	Les `id` sont des chaînes (ou nombres). Les quantités sont des entiers > 0.

	Exemple
		local bag = Core.Gameplay.Inventory.new({ Slots = 10, StackLimits = { Potion = 5 } })
		bag:Add("Potion", 12)        --> 12, 0   (3 emplacements)
		bag:Remove("Potion", 4)
]]

local Signal = require(script.Parent.Parent.Utilities.Signal)

local Inventory = {}
Inventory.__index = Inventory

local function checkAmount(amount: any, fn: string): number
	if amount == nil then
		return 1
	end
	if type(amount) ~= "number" or amount <= 0 or amount % 1 ~= 0 then
		error(("Core.Gameplay.Inventory:%s : amount doit être un entier > 0"):format(fn), 3)
	end
	return amount
end

local function checkId(id: any, fn: string)
	if id == nil or (type(id) ~= "string" and type(id) ~= "number") then
		error(("Core.Gameplay.Inventory:%s : id (string ou number) requis"):format(fn), 3)
	end
end

function Inventory.new(options: any?)
	local opts = options or {}
	local slots = opts.Slots or 20
	if type(slots) ~= "number" or slots < 1 or slots % 1 ~= 0 then
		error("Core.Gameplay.Inventory.new : Slots doit être un entier >= 1", 2)
	end
	return setmetatable({
		Changed = Signal.new(),
		SlotChanged = Signal.new(),
		_size = slots,
		_slots = {},
		_maxStack = opts.MaxStack or 99,
		_limits = opts.StackLimits,
	}, Inventory)
end

function Inventory:_Limit(id: any): number
	local limits = self._limits
	local limit
	if type(limits) == "function" then
		limit = limits(id)
	elseif type(limits) == "table" then
		limit = limits[id]
	end
	return limit or self._maxStack
end

function Inventory:_Space(id: any): number
	local limit, space = self:_Limit(id), 0
	for i = 1, self._size do
		local slot = self._slots[i]
		if slot == nil then
			space += limit
		elseif slot.Id == id then
			space += limit - slot.Count
		end
	end
	return space
end

function Inventory:CanAdd(id: any, amount: number?): boolean
	checkId(id, "CanAdd")
	return self:_Space(id) >= checkAmount(amount, "CanAdd")
end

function Inventory:Add(id: any, amount: number?): (number, number)
	checkId(id, "Add")
	local remaining = checkAmount(amount, "Add")
	local requested = remaining
	local limit = self:_Limit(id)

	local touched = {}
	-- 1) compléter les piles existantes
	for i = 1, self._size do
		local slot = self._slots[i]
		if remaining > 0 and slot and slot.Id == id and slot.Count < limit then
			local moved = math.min(limit - slot.Count, remaining)
			slot.Count += moved
			remaining -= moved
			table.insert(touched, i)
		end
	end
	-- 2) ouvrir de nouveaux emplacements
	for i = 1, self._size do
		if remaining <= 0 then
			break
		end
		if self._slots[i] == nil then
			local moved = math.min(limit, remaining)
			self._slots[i] = { Id = id, Count = moved }
			remaining -= moved
			table.insert(touched, i)
		end
	end

	local added = requested - remaining
	for _, i in touched do
		self.SlotChanged:Fire(i, self._slots[i])
	end
	if added > 0 then
		self.Changed:Fire(id, added)
	end
	return added, remaining
end

function Inventory:Count(id: any): number
	local total = 0
	for i = 1, self._size do
		local slot = self._slots[i]
		if slot and slot.Id == id then
			total += slot.Count
		end
	end
	return total
end

function Inventory:Has(id: any, amount: number?): boolean
	return self:Count(id) >= (amount or 1)
end

function Inventory:Remove(id: any, amount: number?): boolean
	checkId(id, "Remove")
	local remaining = checkAmount(amount, "Remove")
	local requested = remaining
	if self:Count(id) < remaining then
		return false
	end

	local touched = {}
	-- on vide d'abord les piles les plus petites (garde les piles pleines intactes)
	local indices = {}
	for i = 1, self._size do
		local slot = self._slots[i]
		if slot and slot.Id == id then
			table.insert(indices, i)
		end
	end
	table.sort(indices, function(a, b)
		local ca, cb = self._slots[a].Count, self._slots[b].Count
		if ca ~= cb then
			return ca < cb
		end
		return a > b
	end)

	for _, i in indices do
		if remaining <= 0 then
			break
		end
		local slot = self._slots[i]
		local taken = math.min(slot.Count, remaining)
		slot.Count -= taken
		remaining -= taken
		if slot.Count == 0 then
			self._slots[i] = nil
		end
		table.insert(touched, i)
	end

	for _, i in touched do
		self.SlotChanged:Fire(i, self._slots[i])
	end
	self.Changed:Fire(id, -requested)
	return true
end

function Inventory:GetSlot(index: number)
	if type(index) ~= "number" or index < 1 or index > self._size or index % 1 ~= 0 then
		error(("Core.Gameplay.Inventory:GetSlot : index hors limites (1..%d)"):format(self._size), 2)
	end
	local slot = self._slots[index]
	return if slot then { Id = slot.Id, Count = slot.Count } else nil
end

function Inventory:GetItems(): { [any]: number }
	local items = {}
	for i = 1, self._size do
		local slot = self._slots[i]
		if slot then
			items[slot.Id] = (items[slot.Id] or 0) + slot.Count
		end
	end
	return items
end

function Inventory:Swap(a: number, b: number)
	if type(a) ~= "number" or type(b) ~= "number" or a < 1 or b < 1 or a > self._size or b > self._size then
		error(("Core.Gameplay.Inventory:Swap : indices hors limites (1..%d)"):format(self._size), 2)
	end
	if a == b then
		return
	end
	self._slots[a], self._slots[b] = self._slots[b], self._slots[a]
	self.SlotChanged:Fire(a, self._slots[a])
	self.SlotChanged:Fire(b, self._slots[b])
end

function Inventory:FreeSlots(): number
	local free = 0
	for i = 1, self._size do
		if self._slots[i] == nil then
			free += 1
		end
	end
	return free
end

function Inventory:Size(): number
	return self._size
end

function Inventory:Clear()
	for i = 1, self._size do
		if self._slots[i] ~= nil then
			self._slots[i] = nil
			self.SlotChanged:Fire(i, nil)
		end
	end
end

function Inventory:Serialize()
	local items = {}
	for i = 1, self._size do
		local slot = self._slots[i]
		if slot then
			table.insert(items, { Slot = i, Id = slot.Id, Count = slot.Count })
		end
	end
	return { Slots = self._size, Items = items }
end

function Inventory.Deserialize(data: any, options: any?)
	if type(data) ~= "table" or type(data.Items) ~= "table" then
		error("Core.Gameplay.Inventory.Deserialize : données invalides (table { Slots, Items } attendue)", 2)
	end
	local opts = table.clone(options or {})
	opts.Slots = opts.Slots or data.Slots
	local inventory = Inventory.new(opts)

	for _, entry in data.Items do
		local slot, id, count = entry.Slot, entry.Id, entry.Count
		if type(slot) ~= "number" or slot < 1 or slot > inventory._size or slot % 1 ~= 0 then
			error("Core.Gameplay.Inventory.Deserialize : emplacement invalide " .. tostring(slot), 2)
		end
		if inventory._slots[slot] ~= nil then
			error("Core.Gameplay.Inventory.Deserialize : emplacement dupliqué " .. tostring(slot), 2)
		end
		if (type(id) ~= "string" and type(id) ~= "number") or type(count) ~= "number" or count < 1 or count % 1 ~= 0 or count > inventory:_Limit(id) then
			error("Core.Gameplay.Inventory.Deserialize : entrée invalide à l'emplacement " .. tostring(slot), 2)
		end
		inventory._slots[slot] = { Id = id, Count = count }
	end
	return inventory
end

function Inventory:Destroy()
	self.Changed:Destroy()
	self.SlotChanged:Destroy()
end

return Inventory
