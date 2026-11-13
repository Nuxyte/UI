--!nonstrict
--[[
	Maid : nettoyage centralisé de connexions, Instances, fonctions, threads
	et objets exposant Destroy / Disconnect / Cancel / Clean.

	API
		Maid.new()
		maid:Give(task, key?)   -> task     (remplacer une clé nettoie l'ancienne tâche)
		maid:Remove(key)                    -- nettoie et retire une tâche par clé
		maid:Clean()                        -- nettoie tout (le Maid reste utilisable)
		maid:Destroy()                      -- alias de Clean
		Maid.IsMaid(value)

	Exemple
		local maid = Maid.new()
		maid:Give(part.Touched:Connect(onTouch))
		maid:Give(function() print("nettoyé") end)
		maid:Give(Instance.new("Part"), "Preview")
		maid:Clean()
]]

local Maid = {}
Maid.__index = Maid

local function cleanTask(item: any)
	local kind = typeof(item)

	if kind == "function" then
		item()
	elseif kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "Instance" then
		item:Destroy()
	elseif kind == "thread" then
		if coroutine.running() ~= item then
			pcall(task.cancel, item)
		end
	elseif kind == "table" then
		if type(item.Destroy) == "function" then
			item:Destroy()
		elseif type(item.Disconnect) == "function" then
			item:Disconnect()
		elseif type(item.Cancel) == "function" then
			item:Cancel()
		elseif type(item.Clean) == "function" then
			item:Clean()
		else
			error("Maid : table sans méthode Destroy/Disconnect/Cancel/Clean", 0)
		end
	else
		error(("Maid : type de tâche non supporté (%s)"):format(kind), 0)
	end
end

function Maid.new()
	return setmetatable({ _tasks = {}, _nextId = 0 }, Maid)
end

function Maid.IsMaid(value: any): boolean
	return type(value) == "table" and getmetatable(value) == Maid
end

function Maid:Give(item: any, key: any?): any
	local kind = typeof(item)
	if
		kind ~= "function"
		and kind ~= "RBXScriptConnection"
		and kind ~= "Instance"
		and kind ~= "thread"
		and kind ~= "table"
	then
		error(("Maid:Give : type non supporté (%s)"):format(kind), 2)
	end

	if key == nil then
		self._nextId += 1
		key = self._nextId
	else
		self:Remove(key)
	end

	self._tasks[key] = item
	return item
end

function Maid:Remove(key: any)
	local item = self._tasks[key]
	if item == nil then
		return
	end
	self._tasks[key] = nil
	local ok, err = pcall(cleanTask, item)
	if not ok then
		warn(("[Maid] erreur de nettoyage : %s"):format(tostring(err)))
	end
end

function Maid:Clean()
	-- Boucle `next` : une tâche peut en ajouter/retirer d'autres pendant le nettoyage.
	while true do
		local key, item = next(self._tasks)
		if key == nil then
			break
		end
		self._tasks[key] = nil
		local ok, err = pcall(cleanTask, item)
		if not ok then
			warn(("[Maid] erreur de nettoyage : %s"):format(tostring(err)))
		end
	end
end

Maid.Destroy = Maid.Clean

return Maid
