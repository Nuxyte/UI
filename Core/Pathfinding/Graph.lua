--!nonstrict
--[[
	Pathfinding.Graph
	Graphe de waypoints (points de passage / navmesh simplifié) : noeuds positionnés + arêtes pondérées.

	Graph.new() -> graph
	graph:AddNode(id, position)      id : valeur hachable (chaîne, nombre, Instance...)      graph:RemoveNode(id)
	graph:AddEdge(a, b, options?)    options : Cost (défaut = distance), OneWay (défaut false)
	graph:RemoveEdge(a, b)           graph:SetBlocked(id, blocked)    graph:HasNode(id)    graph:GetPosition(id)
	graph:Nearest(position, maxDistance?) -> id | nil     graph:GetNodeCount()    graph.Version
	graph:ConnectNearby(radius, filter?)    relie tous les noeuds distants de <= radius ; filter(a, b) -> boolean
	                                         (ex. Core.Physics.HasLineOfSight) pour ignorer une paire

	L'heuristique (distance euclidienne) est mise à l'échelle par le plus petit rapport coût/distance
	pour rester admissible même avec des coûts d'arête personnalisés.
]]

local Graph = {}
Graph.__index = Graph

function Graph.new()
	return setmetatable({
		Version = 0,
		_positions = {},
		_edges = {}, -- _edges[a][b] = cost
		_blocked = {},
		_scale = 1,
		_count = 0,
	}, Graph)
end

function Graph:AddNode(id: any, position: Vector3)
	if id == nil then
		error("Core.Pathfinding.Graph:AddNode : id requis", 2)
	end
	if typeof(position) ~= "Vector3" then
		error("Core.Pathfinding.Graph:AddNode : position (Vector3) requise", 2)
	end
	if self._positions[id] == nil then
		self._count += 1
		self._edges[id] = {}
	end
	self._positions[id] = position
	self.Version += 1
end

function Graph:HasNode(id: any): boolean
	return self._positions[id] ~= nil
end

function Graph:GetPosition(id: any): Vector3?
	return self._positions[id]
end

function Graph:GetNodeCount(): number
	return self._count
end

function Graph:RemoveNode(id: any)
	if self._positions[id] == nil then
		return
	end
	self._positions[id] = nil
	self._edges[id] = nil
	self._blocked[id] = nil
	for _, edges in self._edges do
		edges[id] = nil
	end
	self._count -= 1
	self.Version += 1
end

function Graph:AddEdge(a: any, b: any, options: any?)
	if self._positions[a] == nil or self._positions[b] == nil then
		error("Core.Pathfinding.Graph:AddEdge : les deux noeuds doivent exister (AddNode d'abord)", 2)
	end
	local opts = options or {}
	local distance = (self._positions[a] - self._positions[b]).Magnitude
	local cost = opts.Cost or distance
	if type(cost) ~= "number" or cost <= 0 or cost ~= cost then
		error("Core.Pathfinding.Graph:AddEdge : Cost doit être un nombre > 0 (noeuds confondus ?)", 2)
	end
	if distance > 1e-9 and cost / distance < self._scale then
		self._scale = cost / distance
	end
	self._edges[a][b] = cost
	if not opts.OneWay then
		self._edges[b][a] = cost
	end
	self.Version += 1
end

function Graph:RemoveEdge(a: any, b: any)
	if self._edges[a] then
		self._edges[a][b] = nil
	end
	if self._edges[b] then
		self._edges[b][a] = nil
	end
	self.Version += 1
end

function Graph:SetBlocked(id: any, blocked: boolean?)
	if self._positions[id] == nil then
		error("Core.Pathfinding.Graph:SetBlocked : noeud inconnu", 2)
	end
	local value = if blocked == false then nil else true
	if self._blocked[id] ~= value then
		self._blocked[id] = value
		self.Version += 1
	end
end

function Graph:IsBlocked(id: any): boolean
	return self._blocked[id] == true
end

function Graph:Nearest(position: Vector3, maxDistance: number?): any
	local best, bestDistance = nil, maxDistance or math.huge
	for id, p in self._positions do
		if not self._blocked[id] then
			local d = (p - position).Magnitude
			if d <= bestDistance then
				best, bestDistance = id, d
			end
		end
	end
	return best
end

function Graph:ConnectNearby(radius: number, filter: ((any, any) -> boolean)?)
	local ids = {}
	for id in self._positions do
		table.insert(ids, id)
	end
	local created = 0
	for i = 1, #ids do
		for j = i + 1, #ids do
			local a, b = ids[i], ids[j]
			if (self._positions[a] - self._positions[b]).Magnitude <= radius and self._edges[a][b] == nil then
				if not filter or filter(a, b) then
					self:AddEdge(a, b)
					created += 1
				end
			end
		end
	end
	return created
end

function Graph:Neighbors(id: any, emit: (any, number) -> ())
	local edges = self._edges[id]
	if not edges then
		return
	end
	for neighbor, cost in edges do
		if not self._blocked[neighbor] then
			emit(neighbor, cost)
		end
	end
end

function Graph:Heuristic(a: any, b: any): number
	return (self._positions[a] - self._positions[b]).Magnitude * self._scale
end

return Graph
