--!nonstrict
--[[
	Pathfinding.Search
	Algorithmes de recherche de chemin génériques, exécutables par tranches (voir FindAsync).

	Un "graphe" est n'importe quelle table avec des méthodes :
		graph:Neighbors(node, emit)      appelle emit(neighbor, cost) pour chaque voisin (cost > 0)
		graph:Heuristic(node, goal)      estimation du coût restant (optionnel ; 0 par défaut) — doit être
		                                 ADMISSIBLE (jamais supérieure au coût réel) pour garantir le chemin optimal
	Les noeuds sont des valeurs hachables quelconques (nombres, chaînes, tables).

	Search.new(graph, start, goal, options?) -> searcher
		Algorithm   "AStar" (défaut) | "Dijkstra" | "BFS" | "Greedy"
		              AStar     optimal si l'heuristique est admissible
		              Dijkstra  optimal, sans heuristique (explore dans toutes les directions)
		              BFS       moins d'arêtes possible, coûts ignorés pour le choix (graphes non pondérés)
		              Greedy    très rapide, chemin NON optimal
		Weight      poids de l'heuristique pour AStar (1 = optimal ; > 1 plus rapide mais jusqu'à Weight × le coût optimal)
		MaxIterations   noeuds développés au maximum (défaut 100000)
		MaxCost         abandonne les chemins plus coûteux que cette valeur
		Partial         true : si le but est inatteignable, retourne le chemin vers le noeud exploré le plus proche
		IsGoal(node)    but multiple / zone d'arrivée (remplace `node == goal`)
	searcher:Step(maxExpansions) -> "Running" | "Found" | "NoPath" | "MaxIterations"
	searcher:Run() -> result                          exécute jusqu'au bout
	searcher:GetResult() -> { Success, Reason, Nodes, Cost, Iterations, Visited, Partial }
]]

local Heap = require(script.Parent.Heap)

local Search = {}
Search.__index = Search

local ALGORITHMS = { AStar = true, Dijkstra = true, BFS = true, Greedy = true }

function Search.new(graph: any, start: any, goal: any, options: any?)
	if type(graph) ~= "table" or type(graph.Neighbors) ~= "function" then
		error("Core.Pathfinding.Search.new : graphe avec méthode Neighbors requis", 2)
	end
	if start == nil or (goal == nil and not (options and options.IsGoal)) then
		error("Core.Pathfinding.Search.new : start et goal requis", 2)
	end
	local opts = options or {}
	local algorithm = opts.Algorithm or "AStar"
	if not ALGORITHMS[algorithm] then
		error(("Core.Pathfinding : Algorithm inconnu '%s' (AStar, Dijkstra, BFS, Greedy)"):format(tostring(algorithm)), 2)
	end
	local weight = opts.Weight or 1
	if type(weight) ~= "number" or weight < 1 then
		error("Core.Pathfinding : Weight doit être un nombre >= 1", 2)
	end

	local self = setmetatable({
		_graph = graph,
		_goal = goal,
		_isGoal = opts.IsGoal or function(node) return node == goal end,
		_algorithm = algorithm,
		_weight = weight,
		_maxIterations = opts.MaxIterations or 100000,
		_maxCost = opts.MaxCost or math.huge,
		_partial = opts.Partial == true,
		_g = { [start] = 0 },
		_came = {},
		_closed = {},
		_open = Heap.new(),
		_queue = { start },
		_head = 1,
		_tail = 1,
		_seq = 0,
		_iterations = 0,
		_visited = 0,
		_status = "Running",
		_result = nil,
		_best = start,
		_bestH = math.huge,
		_foundNode = nil,
	}, Search)

	local hasHeuristic = type(graph.Heuristic) == "function" and algorithm ~= "Dijkstra" and algorithm ~= "BFS"
	self._useHeuristic = hasHeuristic
	if hasHeuristic or self._partial then
		self._bestH = self:_h(start)
	end
	if algorithm ~= "BFS" then
		self._open:Push(start, 0, 0)
	end
	if self._isGoal(start) then
		self._foundNode = start
		self._status = "Found"
		self:_finish()
	end
	return self
end

function Search:_h(node: any): number
	local graph = self._graph
	if type(graph.Heuristic) ~= "function" or self._goal == nil then
		return 0
	end
	return graph:Heuristic(node, self._goal)
end

function Search:_discover(current: any, neighbor: any, cost: number)
	if type(cost) ~= "number" or cost <= 0 or cost ~= cost then
		error(("Core.Pathfinding : coût invalide (%s) vers un voisin ; il doit être un nombre > 0"):format(tostring(cost)), 0)
	end
	local g = self._g
	local tentative = g[current] + cost
	if tentative > self._maxCost then
		return
	end
	local known = g[neighbor]

	if self._algorithm == "BFS" then
		if known == nil then
			g[neighbor] = tentative
			self._came[neighbor] = current
			self._tail += 1
			self._queue[self._tail] = neighbor
			if self._foundNode == nil and self._isGoal(neighbor) then
				self._foundNode = neighbor
			end
		end
		return
	end

	if known == nil or tentative < known then
		g[neighbor] = tentative
		self._came[neighbor] = current
		self._closed[neighbor] = nil -- ré-ouverture si l'heuristique est incohérente
		local h = 0
		if self._useHeuristic then
			h = self:_h(neighbor)
		end
		local priority
		if self._algorithm == "Greedy" then
			priority = h
		else
			priority = tentative + self._weight * h
		end
		self._seq += 1
		self._open:Push(neighbor, priority, h * 1e-6 + self._seq * 1e-12)
		if self._partial and (h < self._bestH) and self._goal ~= nil then
			self._bestH, self._best = h, neighbor
		end
	end
end

function Search:Step(maxExpansions: number?): string
	if self._status ~= "Running" then
		return self._status
	end
	local budget = maxExpansions or math.huge
	local graph = self._graph
	local expansions = 0
	local emitCurrent
	local function emit(neighbor, cost)
		self:_discover(emitCurrent, neighbor, cost)
	end

	while expansions < budget do
		local current
		if self._algorithm == "BFS" then
			current = self._queue[self._head]
			if current == nil then
				self._status = "NoPath"
				break
			end
			self._queue[self._head] = nil
			self._head += 1
			if self._foundNode ~= nil then
				self._status = "Found"
				break
			end
		else
			current = self._open:Pop()
			if current == nil then
				self._status = "NoPath"
				break
			end
			if self._closed[current] then
				continue
			end
			self._closed[current] = true
			if self._isGoal(current) then
				self._foundNode = current
				self._status = "Found"
				break
			end
		end

		if self._iterations >= self._maxIterations then
			self._status = "MaxIterations"
			break
		end
		self._iterations += 1
		self._visited += 1
		expansions += 1
		emitCurrent = current
		graph:Neighbors(current, emit)

		if self._algorithm == "BFS" and self._foundNode ~= nil then
			self._status = "Found"
			break
		end
	end

	if self._status ~= "Running" then
		self:_finish()
	end
	return self._status
end

function Search:_finish()
	local status = self._status
	local target = self._foundNode
	local partial = false
	if target == nil and self._partial and self._best ~= nil and (status == "NoPath" or status == "MaxIterations") then
		target, partial = self._best, true
	end

	local nodes, cost = nil, 0
	if target ~= nil then
		nodes = {}
		local node = target
		while node ~= nil do
			table.insert(nodes, 1, node)
			node = self._came[node]
		end
		cost = self._g[target] or 0
	end

	local reason = status
	if status == "Found" then
		reason = "Found"
	end
	self._result = {
		Success = status == "Found",
		Reason = reason,
		Nodes = nodes or {},
		Cost = cost,
		Iterations = self._iterations,
		Visited = self._visited,
		Partial = partial,
	}
end

function Search:GetResult(): any
	return self._result
end

function Search:Run(): any
	self:Step(math.huge)
	return self._result
end

return Search
