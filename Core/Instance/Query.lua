--!nonstrict
--[[
	Instance.Query
	Recherche et parcours d'Instances.

	IsValid(instance)                               -> boolean  (Instance existante et dans l'arbre de jeu)
	Find(parent, name, recursive?)                  -> Instance?
	FindByClass(parent, className, recursive?)      -> Instance?   (IsA)
	FindAll(parent, predicate, recursive?)          -> { Instance }   (récursif par défaut)
	FindAncestor(instance, predicate)               -> Instance?
	GetByPath(root, "A.B.C")                        -> Instance?
	GetDescendantsOfClass(parent, className)        -> { Instance }
	ForEachDescendant(parent, fn)
	WaitFor(parent, name, timeout?)                 -> Instance?   (nil si timeout, 5 s par défaut)
	WaitForPath(root, { "A", "B" }, timeout?)       -> Instance?
	ObserveChildren(parent, onAdded, onRemoved?)    -> { Disconnect } (appelle onAdded pour l'existant aussi)

	Exemple
		local hitboxes = Core.Instance.FindAll(workspace.Enemies, function(i) return i.Name == "Hitbox" end)
]]

local Query = {}

function Query.IsValid(instance: any): boolean
	return typeof(instance) == "Instance" and instance:IsDescendantOf(game)
end

function Query.Find(parent: Instance, name: string, recursive: boolean?): Instance?
	return parent:FindFirstChild(name, recursive == true)
end

function Query.FindByClass(parent: Instance, className: string, recursive: boolean?): Instance?
	return parent:FindFirstChildWhichIsA(className, recursive == true)
end

function Query.FindAll(parent: Instance, predicate: (Instance) -> boolean, recursive: boolean?): { Instance }
	local source = if recursive == false then parent:GetChildren() else parent:GetDescendants()
	local results = {}
	for _, instance in source do
		if predicate(instance) then
			table.insert(results, instance)
		end
	end
	return results
end

function Query.FindAncestor(instance: Instance, predicate: (Instance) -> boolean): Instance?
	local current = instance.Parent
	while current do
		if predicate(current) then
			return current
		end
		current = current.Parent
	end
	return nil
end

function Query.GetByPath(root: Instance, path: string): Instance?
	local current: Instance? = root
	for name in string.gmatch(path, "[^%.]+") do
		current = current and current:FindFirstChild(name)
		if current == nil then
			return nil
		end
	end
	return current
end

function Query.GetDescendantsOfClass(parent: Instance, className: string): { Instance }
	local results = {}
	for _, instance in parent:GetDescendants() do
		if instance:IsA(className) then
			table.insert(results, instance)
		end
	end
	return results
end

function Query.ForEachDescendant(parent: Instance, fn: (Instance) -> ())
	for _, instance in parent:GetDescendants() do
		fn(instance)
	end
end

function Query.WaitFor(parent: Instance, name: string, timeout: number?): Instance?
	return parent:WaitForChild(name, timeout or 5)
end

function Query.WaitForPath(root: Instance, path: { string }, timeout: number?): Instance?
	local current: Instance? = root
	for _, name in path do
		current = current and current:WaitForChild(name, timeout or 5)
		if current == nil then
			return nil
		end
	end
	return current
end

function Query.ObserveChildren(parent: Instance, onAdded: (Instance) -> (), onRemoved: ((Instance) -> ())?)
	local connections: { RBXScriptConnection } = {}

	table.insert(connections, parent.ChildAdded:Connect(onAdded))
	if onRemoved then
		table.insert(connections, parent.ChildRemoved:Connect(onRemoved))
	end
	for _, child in parent:GetChildren() do
		task.spawn(onAdded, child)
	end

	return {
		Disconnect = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
		end,
	}
end

return Query
