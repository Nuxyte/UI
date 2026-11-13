--!nonstrict
--[[
	Instance.Metadata
	Attributes et Tags (CollectionService).

	Attributes
		GetAttribute(instance, name, default?)  -> any
		SetAttributes(instance, { Nom = valeur })
		GetAttributes(instance)                 -> { [string]: any }
		IncrementAttribute(instance, name, amount?, default?) -> nouveau nombre
		ObserveAttribute(instance, name, callback(value), fireInitial?) -> { Disconnect }
	Tags
		AddTag(instance, ...tags)   RemoveTag(instance, ...tags)   HasTag(instance, tag)
		GetTags(instance)           GetTagged(tag)
		ObserveTag(tag, onAdded(instance), onRemoved?(instance)) -> { Disconnect }
			(appelle onAdded pour les Instances déjà taguées)

	Exemple
		Core.Instance.ObserveTag("Coin", function(coin) setupCoin(coin) end)
]]

local CollectionService = game:GetService("CollectionService")

local Metadata = {}

function Metadata.GetAttribute(instance: Instance, name: string, default: any?): any
	local value = instance:GetAttribute(name)
	if value == nil then
		return default
	end
	return value
end

function Metadata.SetAttributes(instance: Instance, attributes: { [string]: any })
	for name, value in attributes do
		instance:SetAttribute(name, value)
	end
end

function Metadata.GetAttributes(instance: Instance): { [string]: any }
	return instance:GetAttributes()
end

function Metadata.IncrementAttribute(instance: Instance, name: string, amount: number?, default: number?): number
	local current = instance:GetAttribute(name)
	if current ~= nil and type(current) ~= "number" then
		error(("Core.Instance.IncrementAttribute : l'attribut '%s' n'est pas un nombre"):format(name), 2)
	end
	local newValue = (current or default or 0) + (amount or 1)
	instance:SetAttribute(name, newValue)
	return newValue
end

function Metadata.ObserveAttribute(instance: Instance, name: string, callback: (any) -> (), fireInitial: boolean?)
	local connection = instance:GetAttributeChangedSignal(name):Connect(function()
		callback(instance:GetAttribute(name))
	end)
	if fireInitial ~= false then
		task.spawn(callback, instance:GetAttribute(name))
	end
	return connection
end

function Metadata.AddTag(instance: Instance, ...: string)
	for i = 1, select("#", ...) do
		CollectionService:AddTag(instance, (select(i, ...)))
	end
end

function Metadata.RemoveTag(instance: Instance, ...: string)
	for i = 1, select("#", ...) do
		CollectionService:RemoveTag(instance, (select(i, ...)))
	end
end

function Metadata.HasTag(instance: Instance, tag: string): boolean
	return CollectionService:HasTag(instance, tag)
end

function Metadata.GetTags(instance: Instance): { string }
	return CollectionService:GetTags(instance)
end

function Metadata.GetTagged(tag: string): { Instance }
	return CollectionService:GetTagged(tag)
end

function Metadata.ObserveTag(tag: string, onAdded: (Instance) -> (), onRemoved: ((Instance) -> ())?)
	local connections: { RBXScriptConnection } = {}

	table.insert(connections, CollectionService:GetInstanceAddedSignal(tag):Connect(onAdded))
	if onRemoved then
		table.insert(connections, CollectionService:GetInstanceRemovedSignal(tag):Connect(onRemoved))
	end
	for _, instance in CollectionService:GetTagged(tag) do
		task.spawn(onAdded, instance)
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

return Metadata
