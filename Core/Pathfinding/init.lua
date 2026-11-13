--!nonstrict
--[[
	Core.Pathfinding
	Recherche de chemin : A*, Dijkstra, BFS et Greedy sur grille ou graphe de waypoints, recherche étalée sur
	plusieurs frames, et navigation avec replanification. Indépendant du pathfinding natif de Roblox
	(PathfindingService) : fonctionne sur vos propres données (grille scannée, waypoints, graphe quelconque).

	Heap.lua      tas binaire                                    Search.lua   algorithmes génériques (voir ce fichier)
	Grid.lua      grille XZ, scan du monde, coûts, hauteurs      Graph.lua    graphe de waypoints

	Pathfinding.Grid.new(options)   Pathfinding.Graph.new()   Pathfinding.Heap.new()   Pathfinding.Search.new(graph, a, b, opts)

	Pathfinding.Find(map, from, to, options?) -> result
		map   Grid | Graph | graphe personnalisé (méthodes Neighbors / Heuristic, voir Search.lua)
		from, to   Grille : Vector3 | BasePart | Model | Attachment | function() -> Vector3 | { X = x, Z = z } (case)
		           Graphe : id de noeud existant, ou Vector3 (noeud le plus proche)
		options  Algorithm "AStar" | "Dijkstra" | "BFS" | "Greedy"   Weight   MaxIterations   MaxCost   Partial
		         Smooth (grille, défaut true)   raccourcit le chemin par lignes de vue (le chemin reste hors des cases bloquées)
		         SnapRadius (grille, défaut 3)  si départ/arrivée est sur une case bloquée : case libre la plus proche (0 = refuser)
		         SnapDistance (graphe)          distance maximale pour rattacher un Vector3 à un noeud
		result { Success, Reason, Path = { Vector3 }, Nodes, Cost, Length (studs), Iterations, Visited, TimeMs, Partial }
		Reason : "Found" | "NoPath" | "MaxIterations" | "StartBlocked" | "GoalBlocked" | "StartOutside" | "GoalOutside"
		         | "StartUnknown" | "GoalUnknown"
		Cost est exprimé en cases pour une grille (diagonale = √2, × poids), Length en studs.

	Pathfinding.FindAsync(map, from, to, options?) -> handle     même recherche, étalée sur les frames (Engine.Scheduler)
		options en plus : BudgetMs (défaut 2) temps maximal par frame   OnDone(result)
		                  StepsPerFrame  nombre fixe de noeuds développés par frame (remplace BudgetMs ; déterministe)
		handle:Wait() -> "Completed" | "Cancelled"      handle.Result (nil avant la fin)      handle:Cancel()

	Pathfinding.Navigate(target, map, goal, options?) -> handle
		Déplace `target` (BasePart ou Model) le long d'un chemin calculé, à vitesse constante, et REPLANIFIE :
		quand la grille/le graphe change (map.Version), quand le but (Instance ou fonction) s'éloigne, ou quand
		il n'y a plus de chemin (attente puis nouvel essai).
		options : Speed (16)  Offset (Vector3 ajouté aux positions, ex. hauteur du centre)  Face (false | true | "Yaw")
		          RepathInterval (0.5 s)  RepathDistance (but mobile ; défaut 2 cases)  MaxFailures (3 essais sans chemin)
		          StopDistance (0)  Partial (false)  + options de Find (Algorithm, Weight, ...)
		          OnWaypoint(i)  OnComplete()  OnFail(reason)  OnRepath(result)
		          Channel / Priority / OnConflict  (arbitrage, voir Engine.Scheduler)
		handle.Path (chemin courant)  handle.Result (dernier calcul)  handle.Success (true à l'arrivée)  handle.Replans
		handle.Reason : "NoPath" | "StartBlocked" | ... en cas d'échec ; l'état final est "Cancelled" si échec ou annulation.

	Exemple
		local grid = Core.Pathfinding.Grid.new({ Origin = Vector3.new(-100, 0, -100), CellSize = 4, Width = 50, Depth = 50 })
		grid:Scan({ Clearance = 6, Ignore = { npc } })
		local result = Core.Pathfinding.Find(grid, npc.PrimaryPart.Position, goalPart)
		if result.Success then print(#result.Path, result.Length) end
		Core.Pathfinding.Navigate(npc, grid, player.Character, { Speed = 14, Face = "Yaw", Offset = Vector3.new(0, 3, 0) })
]]

local Config = require(script.Parent.Config)
local Scheduler = require(script.Parent.Engine.Scheduler)
local MovementUtil = require(script.Parent.Movement.Util)
local Heap = require(script.Heap)
local Search = require(script.Search)
local Grid = require(script.Grid)
local Graph = require(script.Graph)

local Pathfinding = {}

Pathfinding.Heap = Heap
Pathfinding.Search = Search
Pathfinding.Grid = Grid
Pathfinding.Graph = Graph

local DEFAULTS = { MaxIterations = 100000, BudgetMs = 2, RepathInterval = 0.5 }

local function setting(name: string): any
	local section = Config.Pathfinding
	local value = section and section[name]
	if value == nil then
		return DEFAULTS[name]
	end
	return value
end

-- Résolution des extrémités ----------------------------------------------------------

local function resolvePosition(spec: any): Vector3?
	local kind = typeof(spec)
	if kind == "Vector3" or kind == "function" or kind == "Instance" then
		return MovementUtil.Resolve(spec)
	end
	return nil
end

-- Retourne node, exactPosition?, failureReason?
local function resolveGridEndpoint(grid: any, spec: any, role: string, snapRadius: number)
	local x, z, exact
	if typeof(spec) == "table" and spec.X ~= nil and spec.Z ~= nil then
		x, z = spec.X, spec.Z
		if not grid:InBounds(x, z) then
			return nil, nil, role .. "Outside"
		end
	else
		local position = resolvePosition(spec)
		if not position then
			error(("Core.Pathfinding.Find : %s invalide (Vector3, BasePart, Model, Attachment, fonction ou {X, Z} attendu)"):format(role), 4)
		end
		x, z = grid:WorldToCell(position)
		if not x then
			return nil, nil, role .. "Outside"
		end
		exact = position
	end
	if not grid:IsWalkable(x, z) then
		local nx, nz
		if snapRadius > 0 then
			nx, nz = grid:NearestWalkable(x, z, snapRadius)
		end
		if not nx then
			return nil, nil, role .. "Blocked"
		end
		x, z, exact = nx, nz, nil
	end
	return grid:_index(x, z), exact, nil
end

local function resolveGraphEndpoint(graph: any, spec: any, role: string, maxDistance: number?)
	if graph.HasNode and graph:HasNode(spec) then
		return spec, nil, nil
	end
	local position = resolvePosition(spec)
	if position and graph.Nearest then
		local id = graph:Nearest(position, maxDistance)
		if id ~= nil then
			return id, nil, nil
		end
	end
	return nil, nil, role .. "Unknown"
end

local function failure(reason: string)
	return { Success = false, Reason = reason, Path = {}, Nodes = {}, Cost = 0, Length = 0, Iterations = 0, Visited = 0, TimeMs = 0, Partial = false }
end

local function pathLength(points: { Vector3 }): number
	local length = 0
	for i = 2, #points do
		length += (points[i] - points[i - 1]).Magnitude
	end
	return length
end

-- Raccourcit un chemin de cases par lignes de vue (« string pulling »).
local function smoothCells(grid: any, cells: { { number } }): { { number } }
	if #cells <= 2 then
		return cells
	end
	local result = { cells[1] }
	local anchor = 1
	while anchor < #cells do
		local far = anchor + 1
		for j = #cells, anchor + 2, -1 do
			if grid:HasLineOfSight(cells[anchor][1], cells[anchor][2], cells[j][1], cells[j][2]) then
				far = j
				break
			end
		end
		table.insert(result, cells[far])
		anchor = far
	end
	return result
end

-- Préparation / finalisation partagées par Find et FindAsync --------------------------

local function prepare(map: any, from: any, to: any, options: any?)
	local opts = options or {}
	local isGrid = getmetatable(map) == Grid
	local startNode, goalNode, startExact, goalExact, reason

	if type(map) ~= "table" or type(map.Neighbors) ~= "function" then
		error("Core.Pathfinding.Find : map (Grid, Graph ou graphe avec Neighbors) requis", 3)
	end

	if isGrid then
		local snap = if opts.SnapRadius ~= nil then opts.SnapRadius else 3
		startNode, startExact, reason = resolveGridEndpoint(map, from, "Start", snap)
		if reason then
			return nil, failure(reason)
		end
		goalNode, goalExact, reason = resolveGridEndpoint(map, to, "Goal", snap)
		if reason then
			return nil, failure(reason)
		end
	elseif getmetatable(map) == Graph then
		startNode, startExact, reason = resolveGraphEndpoint(map, from, "Start", opts.SnapDistance)
		if reason then
			return nil, failure(reason)
		end
		goalNode, goalExact, reason = resolveGraphEndpoint(map, to, "Goal", opts.SnapDistance)
		if reason then
			return nil, failure(reason)
		end
	else
		startNode, goalNode = from, to
	end

	local searcher = Search.new(map, startNode, goalNode, {
		Algorithm = opts.Algorithm,
		Weight = opts.Weight,
		MaxIterations = opts.MaxIterations or setting("MaxIterations"),
		MaxCost = opts.MaxCost,
		Partial = opts.Partial,
	})
	return {
		map = map,
		isGrid = isGrid,
		isGraph = getmetatable(map) == Graph,
		searcher = searcher,
		smooth = opts.Smooth ~= false,
		startExact = startExact,
		goalExact = goalExact,
		startedAt = os.clock(),
	}, nil
end

local function finalize(ctx: any): any
	local raw = ctx.searcher:GetResult()
	local map = ctx.map
	local points = {}

	if ctx.isGrid then
		local cells = {}
		for i, index in raw.Nodes do
			local x, z = map:_cell(index)
			cells[i] = { x, z }
		end
		if ctx.smooth then
			cells = smoothCells(map, cells)
		end
		for i, cell in cells do
			points[i] = map:CellToWorld(cell[1], cell[2])
		end
		-- extrémités exactes (la position réelle plutôt que le centre de la case)
		if #points > 0 and not raw.Partial then
			if ctx.startExact then
				points[1] = Vector3.new(ctx.startExact.X, points[1].Y, ctx.startExact.Z)
			end
			if ctx.goalExact then
				local last = points[#points]
				points[#points] = Vector3.new(ctx.goalExact.X, last.Y, ctx.goalExact.Z)
			end
		end
	elseif ctx.isGraph or type(map.GetPosition) == "function" then
		for i, node in raw.Nodes do
			points[i] = map:GetPosition(node)
		end
	end

	return {
		Success = raw.Success,
		Reason = raw.Reason,
		Path = points,
		Nodes = raw.Nodes,
		Cost = raw.Cost,
		Length = pathLength(points),
		Iterations = raw.Iterations,
		Visited = raw.Visited,
		TimeMs = (os.clock() - ctx.startedAt) * 1000,
		Partial = raw.Partial,
	}
end

function Pathfinding.Find(map: any, from: any, to: any, options: any?): any
	local ctx, failed = prepare(map, from, to, options)
	if not ctx then
		return failed
	end
	ctx.searcher:Run()
	return finalize(ctx)
end

function Pathfinding.FindAsync(map: any, from: any, to: any, options: any?)
	local opts = options or {}
	local ctx, failed = prepare(map, from, to, opts)
	local budget = (opts.BudgetMs or setting("BudgetMs")) / 1000
	if opts.BudgetMs ~= nil and (type(opts.BudgetMs) ~= "number" or opts.BudgetMs <= 0) then
		error("Core.Pathfinding.FindAsync : BudgetMs doit être > 0", 2)
	end
	local stepsPerFrame = opts.StepsPerFrame
	if stepsPerFrame ~= nil and (type(stepsPerFrame) ~= "number" or stepsPerFrame < 1) then
		error("Core.Pathfinding.FindAsync : StepsPerFrame doit être >= 1", 2)
	end

	local handle
	handle = Scheduler.Run(nil, function()
		if not ctx then
			handle.Result = failed
			return true
		end
		if stepsPerFrame then
			if ctx.searcher:Step(stepsPerFrame) ~= "Running" then
				handle.Result = finalize(ctx)
				return true
			end
			return false
		end
		local startedAt = os.clock()
		repeat
			local status = ctx.searcher:Step(64)
			if status ~= "Running" then
				handle.Result = finalize(ctx)
				return true
			end
		until os.clock() - startedAt >= budget
		return false
	end, function(status)
		if handle.Result == nil then
			handle.Result = failure("Cancelled")
		end
		if status == "Completed" and opts.OnDone then
			task.spawn(opts.OnDone, handle.Result)
		end
	end, { Label = "FindAsync" })
	return handle
end

-- Navigation ---------------------------------------------------------------------------

function Pathfinding.Navigate(target: Instance, map: any, goal: any, options: any?)
	if not MovementUtil.IsMovable(target) then
		error("Core.Pathfinding.Navigate : la cible doit être une BasePart ou un Model", 2)
	end
	local opts = options or {}
	local speed = opts.Speed or 16
	if type(speed) ~= "number" or speed <= 0 then
		error("Core.Pathfinding.Navigate : Speed doit être > 0", 2)
	end
	local face = opts.Face or false
	if face ~= false and face ~= true and face ~= "Yaw" then
		error("Core.Pathfinding.Navigate : Face doit valoir false, true ou 'Yaw'", 2)
	end
	local meta = Scheduler.MetaFrom(opts, "Navigate")
	local offset = opts.Offset or Vector3.zero
	local interval = opts.RepathInterval or setting("RepathInterval")
	local maxFailures = opts.MaxFailures or 3
	local stopDistance = opts.StopDistance or 0
	local repathDistance = opts.RepathDistance or ((map.CellSize or 4) * 2)
	local dynamicGoal = (typeof(goal) == "function" or typeof(goal) == "Instance") and not (type(map.HasNode) == "function" and map:HasNode(goal))

	local handle
	local path, index = nil, 1
	local plannedVersion, plannedGoal = nil, nil
	local failures, sinceCheck = 0, 0
	local lastDirection = Vector3.new(0, 0, 1)

	local function currentPosition(): Vector3
		return MovementUtil.GetPosition(target) - offset
	end

	local goalIsNode = type(map.HasNode) == "function" and map:HasNode(goal)

	local function goalPosition(): any
		local kind = typeof(goal)
		if goalIsNode or (kind ~= "Vector3" and kind ~= "function" and kind ~= "Instance") then
			return goal -- id de noeud ou case { X, Z } : Find sait la résoudre
		end
		return MovementUtil.Resolve(goal)
	end

	local function plan(): (boolean, string?)
		local destination = goalPosition()
		local result = Pathfinding.Find(map, currentPosition(), destination, opts)
		handle.Result = result
		plannedVersion = map.Version
		plannedGoal = if typeof(destination) == "Vector3" then destination else nil
		if result.Success or (opts.Partial and #result.Path > 0) then
			path, index = result.Path, 1
			handle.Path = path
			if opts.OnRepath and handle.Replans > 0 then
				task.spawn(opts.OnRepath, result)
			end
			return true, nil
		end
		path = nil
		handle.Path = nil
		return false, result.Reason
	end

	local function fail(reason: string)
		handle.Success = false
		handle.Reason = reason
		if opts.OnFail then
			task.spawn(opts.OnFail, reason)
		end
		handle:Cancel()
	end

	local function step(dt: number): boolean?
		sinceCheck += dt
		if sinceCheck >= interval then
			sinceCheck = 0
			local needPlan = path == nil
			if not needPlan and map.Version ~= nil and map.Version ~= plannedVersion then
				needPlan = true
			end
			if not needPlan and dynamicGoal and plannedGoal then
				local ok, now = pcall(goalPosition)
				if ok and (now - plannedGoal).Magnitude > repathDistance then
					needPlan = true
				end
			end
			if needPlan then
				handle.Replans += 1
				local ok, reason = plan()
				if ok then
					failures = 0
				else
					failures += 1
					if failures >= maxFailures then
						fail(reason)
						return false
					end
				end
			end
		end

		if not path then
			return false -- pas de chemin pour l'instant : on attend le prochain essai
		end

		local position = currentPosition()
		local remaining = speed * dt
		local last = path[#path]
		while remaining > 0 and index <= #path do
			local to = path[index]
			local delta = to - position
			local distance = delta.Magnitude
			if distance <= remaining then
				position = to
				remaining -= distance
				if opts.OnWaypoint then
					task.spawn(opts.OnWaypoint, index)
				end
				index += 1
			else
				position += delta.Unit * remaining
				lastDirection = delta
				remaining = 0
			end
		end

		local world = position + offset
		if face then
			local look = if face == "Yaw" then Vector3.new(lastDirection.X, 0, lastDirection.Z) else lastDirection
			if look.Magnitude > 1e-4 then
				MovementUtil.SetCFrame(target, CFrame.lookAt(world, world + look))
			else
				MovementUtil.SetPosition(target, world)
			end
		else
			MovementUtil.SetPosition(target, world)
		end

		if index > #path or (last - position).Magnitude <= stopDistance then
			if handle.Result and handle.Result.Partial then
				-- chemin partiel : on se replanifiera depuis ici
				path = nil
				return false
			end
			handle.Success = true
			if opts.OnComplete then
				task.spawn(opts.OnComplete)
			end
			return true
		end
		return false
	end

	handle = Scheduler.Run(target, step, nil, meta)
	handle.Replans = 0
	handle.Success = false
	if handle.Rejected then
		return handle
	end

	local ok, reason = plan()
	if not ok then
		failures = 1
		if maxFailures <= 1 then
			fail(reason)
		end
	end
	return handle
end

return table.freeze(Pathfinding)
