--!nonstrict
--[[
	Pathfinding.Grid
	Grille 2D (plan XZ) pour la recherche de chemin : cases praticables/bloquées, coûts par case, hauteurs,
	scan automatique du monde (sol + obstacles), voisins à 4 ou 8 directions.

	Grid.new(options) -> grid
		Origin        Vector3   coin minimal (X, Z) de la grille ; Y = hauteur de base (défaut 0,0,0)
		CellSize      studs par case (défaut 4)
		Width, Depth  nombre de cases en X et en Z (requis)
		Diagonal      true (défaut) : 8 directions
		CornerCutting false (défaut) : une diagonale exige que les 2 cases orthogonales voisines soient libres
		Heuristic     "Octile" (défaut si Diagonal) | "Manhattan" (défaut sinon) | "Euclidean" | "Chebyshev"
	Cases (x, z) : entiers de 0 à Width-1 / Depth-1.
	grid:WorldToCell(position) -> x, z | nil (hors grille)     grid:CellToWorld(x, z) -> Vector3 (centre, Y = hauteur de la case)
	grid:InBounds(x, z)   grid:IsWalkable(x, z)   grid:IsBlocked(x, z)   grid:SetBlocked(x, z, blocked)
	grid:SetWeight(x, z, w)   multiplicateur de coût (> 0 ; 1 = normal, 3 = marais, 0.5 = route) ; nil = normal
	grid:GetWeight(x, z)   grid:SetHeight(x, z, y)   grid:GetHeight(x, z)
	grid:BlockRegion(minPos, maxPos, blocked?)   grid:BlockCircle(center, radius, blocked?)   grid:Clear()
	grid:NearestWalkable(x, z, maxRadius?) -> x, z | nil
	grid:HasLineOfSight(x0, z0, x1, z1) -> boolean       (cases libres et de poids <= 1 sur tout le segment)
	grid:Scan(options?) -> nombre de cases bloquées      grid:ScanAsync(options?) -> handle
		Ground (true)         lance un rayon vers le bas : hauteur du sol ; pas de sol => case bloquée (RequireGround)
		RayHeight (100) / RayDepth (400)   départ du rayon au-dessus de Origin.Y / longueur
		GroundWhitelist / GroundIgnore   parts considérées comme sol (ex. { workspace.Map.Floor }). IMPORTANT : sans filtre,
		                      le dessus d'un bâtiment ou d'un mur est vu comme du « sol » (le rayon le touche en premier) ;
		                      filtrez le sol, ou réglez RayHeight juste au-dessus du sol praticable
		Clearance (5)         hauteur libre nécessaire pour l'agent ; StepHeight (1.5) : obstacles plus bas ignorés (marches)
		Shrink (0.9)          fraction de la case testée pour les obstacles
		Ignore / Whitelist / CollisionGroup ; seules les parts avec CanCollide ~= false bloquent
		CellsPerFrame (200)   ScanAsync uniquement ;  OnDone(blockedCount)
	grid.Version   incrémenté à chaque modification (utilisé pour la replanification)

	Les coûts sont exprimés en cases (déplacement orthogonal = 1, diagonale = √2, multipliés par le poids).
]]

local Cast = require(script.Parent.Parent.Physics.Cast)
local Scheduler = require(script.Parent.Parent.Engine.Scheduler)

local Grid = {}
Grid.__index = Grid

local SQRT2 = math.sqrt(2)

local HEURISTICS = {
	Manhattan = function(dx, dz) return dx + dz end,
	Euclidean = function(dx, dz) return math.sqrt(dx * dx + dz * dz) end,
	Chebyshev = function(dx, dz) return math.max(dx, dz) end,
	Octile = function(dx, dz) return (dx + dz) + (SQRT2 - 2) * math.min(dx, dz) end,
}

function Grid.new(options: any)
	local opts = options
	if type(opts) ~= "table" then
		error("Core.Pathfinding.Grid.new : options { Width, Depth, ... } requis", 2)
	end
	local width, depth = opts.Width, opts.Depth
	if type(width) ~= "number" or type(depth) ~= "number" or width < 1 or depth < 1 or width % 1 ~= 0 or depth % 1 ~= 0 then
		error("Core.Pathfinding.Grid.new : Width et Depth doivent être des entiers >= 1", 2)
	end
	local cellSize = opts.CellSize or 4
	if type(cellSize) ~= "number" or cellSize <= 0 then
		error("Core.Pathfinding.Grid.new : CellSize doit être > 0", 2)
	end
	local origin = opts.Origin or Vector3.zero
	if typeof(origin) ~= "Vector3" then
		error("Core.Pathfinding.Grid.new : Origin doit être un Vector3", 2)
	end
	local diagonal = opts.Diagonal ~= false
	local heuristicName = opts.Heuristic or (if diagonal then "Octile" else "Manhattan")
	if not HEURISTICS[heuristicName] then
		error(("Core.Pathfinding.Grid.new : Heuristic inconnue '%s'"):format(tostring(heuristicName)), 2)
	end

	return setmetatable({
		Width = width,
		Depth = depth,
		CellSize = cellSize,
		Origin = origin,
		Diagonal = diagonal,
		CornerCutting = opts.CornerCutting == true,
		Version = 0,
		_heuristic = HEURISTICS[heuristicName],
		_blocked = {},
		_weights = {},
		_heights = {},
		_minWeight = 1,
	}, Grid)
end

local function touch(self)
	self.Version += 1
end

function Grid:InBounds(x: number, z: number): boolean
	return x >= 0 and z >= 0 and x < self.Width and z < self.Depth and x % 1 == 0 and z % 1 == 0
end

function Grid:_index(x: number, z: number): number
	return z * self.Width + x + 1
end

function Grid:_cell(index: number): (number, number)
	local i = index - 1
	return i % self.Width, i // self.Width
end

function Grid:WorldToCell(position: Vector3): (number?, number?)
	local x = math.floor((position.X - self.Origin.X) / self.CellSize)
	local z = math.floor((position.Z - self.Origin.Z) / self.CellSize)
	if not self:InBounds(x, z) then
		return nil, nil
	end
	return x, z
end

function Grid:CellToWorld(x: number, z: number): Vector3
	local y = self._heights[self:_index(x, z)] or self.Origin.Y
	return Vector3.new(
		self.Origin.X + (x + 0.5) * self.CellSize,
		y,
		self.Origin.Z + (z + 0.5) * self.CellSize
	)
end

function Grid:IsBlocked(x: number, z: number): boolean
	return not self:InBounds(x, z) or self._blocked[self:_index(x, z)] == true
end

function Grid:IsWalkable(x: number, z: number): boolean
	return self:InBounds(x, z) and self._blocked[self:_index(x, z)] ~= true
end

function Grid:SetBlocked(x: number, z: number, blocked: boolean?)
	if not self:InBounds(x, z) then
		error(("Core.Pathfinding.Grid:SetBlocked : case (%s, %s) hors grille"):format(tostring(x), tostring(z)), 2)
	end
	local index = self:_index(x, z)
	local value = if blocked == false then nil else true
	if self._blocked[index] ~= value then
		self._blocked[index] = value
		touch(self)
	end
end

function Grid:SetWeight(x: number, z: number, weight: number?)
	if not self:InBounds(x, z) then
		error("Core.Pathfinding.Grid:SetWeight : case hors grille", 2)
	end
	if weight ~= nil and (type(weight) ~= "number" or weight <= 0 or weight ~= weight or weight == math.huge) then
		error("Core.Pathfinding.Grid:SetWeight : poids > 0 (fini) ou nil requis", 2)
	end
	local index = self:_index(x, z)
	if weight == 1 then
		weight = nil
	end
	self._weights[index] = weight
	if weight ~= nil and weight < self._minWeight then
		self._minWeight = weight -- l'heuristique est mise à l'échelle pour rester admissible
	end
	touch(self)
end

function Grid:GetWeight(x: number, z: number): number
	return self._weights[self:_index(x, z)] or 1
end

function Grid:SetHeight(x: number, z: number, y: number)
	if not self:InBounds(x, z) then
		error("Core.Pathfinding.Grid:SetHeight : case hors grille", 2)
	end
	self._heights[self:_index(x, z)] = y
end

function Grid:GetHeight(x: number, z: number): number
	return self._heights[self:_index(x, z)] or self.Origin.Y
end

function Grid:BlockRegion(minPos: Vector3, maxPos: Vector3, blocked: boolean?)
	local x0 = math.floor((math.min(minPos.X, maxPos.X) - self.Origin.X) / self.CellSize)
	local x1 = math.floor((math.max(minPos.X, maxPos.X) - self.Origin.X) / self.CellSize)
	local z0 = math.floor((math.min(minPos.Z, maxPos.Z) - self.Origin.Z) / self.CellSize)
	local z1 = math.floor((math.max(minPos.Z, maxPos.Z) - self.Origin.Z) / self.CellSize)
	local count = 0
	for x = math.max(x0, 0), math.min(x1, self.Width - 1) do
		for z = math.max(z0, 0), math.min(z1, self.Depth - 1) do
			self:SetBlocked(x, z, blocked ~= false)
			count += 1
		end
	end
	return count
end

function Grid:BlockCircle(center: Vector3, radius: number, blocked: boolean?)
	local count = 0
	local r2 = radius * radius
	local x0 = math.max(math.floor((center.X - radius - self.Origin.X) / self.CellSize), 0)
	local x1 = math.min(math.floor((center.X + radius - self.Origin.X) / self.CellSize), self.Width - 1)
	local z0 = math.max(math.floor((center.Z - radius - self.Origin.Z) / self.CellSize), 0)
	local z1 = math.min(math.floor((center.Z + radius - self.Origin.Z) / self.CellSize), self.Depth - 1)
	for x = x0, x1 do
		for z = z0, z1 do
			local world = self:CellToWorld(x, z)
			local dx, dz = world.X - center.X, world.Z - center.Z
			if dx * dx + dz * dz <= r2 then
				self:SetBlocked(x, z, blocked ~= false)
				count += 1
			end
		end
	end
	return count
end

function Grid:Clear()
	table.clear(self._blocked)
	table.clear(self._weights)
	table.clear(self._heights)
	self._minWeight = 1
	touch(self)
end

function Grid:NearestWalkable(x: number, z: number, maxRadius: number?): (number?, number?)
	if self:IsWalkable(x, z) then
		return x, z
	end
	local bestX, bestZ, bestDistance
	for radius = 1, maxRadius or 3 do
		for dx = -radius, radius do
			for dz = -radius, radius do
				if math.max(math.abs(dx), math.abs(dz)) == radius and self:IsWalkable(x + dx, z + dz) then
					local d = dx * dx + dz * dz
					if not bestDistance or d < bestDistance then
						bestX, bestZ, bestDistance = x + dx, z + dz, d
					end
				end
			end
		end
		if bestX then
			return bestX, bestZ
		end
	end
	return nil, nil
end

-- Interface de graphe -------------------------------------------------------------

local ORTHOGONAL = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local DIAGONAL = { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

function Grid:Neighbors(index: number, emit: (number, number) -> ())
	local x, z = self:_cell(index)
	local blocked, weights = self._blocked, self._weights
	local width = self.Width

	for _, step in ORTHOGONAL do
		local nx, nz = x + step[1], z + step[2]
		if nx >= 0 and nz >= 0 and nx < width and nz < self.Depth then
			local ni = nz * width + nx + 1
			if not blocked[ni] then
				emit(ni, weights[ni] or 1)
			end
		end
	end

	if self.Diagonal then
		local cutting = self.CornerCutting
		for _, step in DIAGONAL do
			local nx, nz = x + step[1], z + step[2]
			if nx >= 0 and nz >= 0 and nx < width and nz < self.Depth then
				local ni = nz * width + nx + 1
				if not blocked[ni] then
					local free = true
					if not cutting then
						free = not blocked[z * width + nx + 1] and not blocked[nz * width + x + 1]
					end
					if free then
						emit(ni, SQRT2 * (weights[ni] or 1))
					end
				end
			end
		end
	end
end

function Grid:Heuristic(a: number, b: number): number
	local ax, az = self:_cell(a)
	local bx, bz = self:_cell(b)
	return self._heuristic(math.abs(ax - bx), math.abs(az - bz)) * self._minWeight
end

function Grid:HasLineOfSight(x0: number, z0: number, x1: number, z1: number): boolean
	local dx, dz = math.abs(x1 - x0), math.abs(z1 - z0)
	local sx, sz = if x0 < x1 then 1 else -1, if z0 < z1 then 1 else -1
	local err = dx - dz
	local x, z = x0, z0
	local blocked, weights = self._blocked, self._weights
	local width = self.Width

	while true do
		local index = self:_index(x, z)
		if not self:InBounds(x, z) or blocked[index] or (weights[index] or 1) > 1 then
			return false
		end
		if x == x1 and z == z1 then
			return true
		end
		local e2 = 2 * err
		local stepX, stepZ = false, false
		if e2 > -dz then
			err -= dz
			x += sx
			stepX = true
		end
		if e2 < dx then
			err += dx
			z += sz
			stepZ = true
		end
		if stepX and stepZ and not self.CornerCutting then
			-- pas diagonal : les deux cases orthogonales traversées doivent être libres
			if blocked[(z - sz) * width + x + 1] or blocked[z * width + (x - sx) + 1] then
				return false
			end
		end
	end
end

-- Scan du monde ---------------------------------------------------------------------

local function scanSettings(self, options: any?)
	local opts = options or {}
	return {
		ground = opts.Ground ~= false,
		requireGround = opts.RequireGround ~= false,
		rayHeight = opts.RayHeight or 100,
		rayDepth = opts.RayDepth or 400,
		clearance = opts.Clearance or 5,
		step = opts.StepHeight or 1.5,
		shrink = opts.Shrink or 0.9,
		cast = { Ignore = opts.Ignore, Whitelist = opts.Whitelist, CollisionGroup = opts.CollisionGroup },
		groundCast = {
			Ignore = opts.GroundIgnore or opts.Ignore,
			Whitelist = opts.GroundWhitelist or opts.Whitelist,
			CollisionGroup = opts.CollisionGroup,
		},
	}
end

-- Retourne true si la case est bloquée.
local function scanCell(self, x: number, z: number, cfg: any): boolean
	local center = self:CellToWorld(x, z)
	local y = self.Origin.Y

	if cfg.ground then
		local hit = Cast.Raycast(
			Vector3.new(center.X, self.Origin.Y + cfg.rayHeight, center.Z),
			Vector3.new(0, -cfg.rayDepth, 0),
			cfg.groundCast
		)
		if hit then
			y = hit.Position.Y
			self._heights[self:_index(x, z)] = y
		elseif cfg.requireGround then
			return true
		end
	end

	local height = cfg.clearance - cfg.step
	if height <= 0 then
		return false
	end
	local size = self.CellSize * cfg.shrink
	local parts = Cast.GetPartsInBox(
		CFrame.new(Vector3.new(center.X, y + cfg.step + height / 2, center.Z)),
		Vector3.new(size, height, size),
		cfg.cast
	)
	for _, part in parts do
		if part.CanCollide ~= false then
			return true
		end
	end
	return false
end

function Grid:Scan(options: any?): number
	local cfg = scanSettings(self, options)
	local count = 0
	for z = 0, self.Depth - 1 do
		for x = 0, self.Width - 1 do
			local blocked = scanCell(self, x, z, cfg)
			self._blocked[self:_index(x, z)] = if blocked then true else nil
			if blocked then
				count += 1
			end
		end
	end
	touch(self)
	return count
end

function Grid:ScanAsync(options: any?)
	local cfg = scanSettings(self, options)
	local perFrame = (options and options.CellsPerFrame) or 200
	local total = self.Width * self.Depth
	local nextCell, count = 0, 0
	local onDone = options and options.OnDone

	local handle
	handle = Scheduler.Run(nil, function()
		for _ = 1, perFrame do
			if nextCell >= total then
				break
			end
			local x, z = nextCell % self.Width, nextCell // self.Width
			local blocked = scanCell(self, x, z, cfg)
			self._blocked[self:_index(x, z)] = if blocked then true else nil
			if blocked then
				count += 1
			end
			nextCell += 1
		end
		return nextCell >= total
	end, function(status)
		touch(self)
		if status == "Completed" then
			handle.Blocked = count
			if onDone then
				task.spawn(onDone, count)
			end
		end
	end, { Label = "GridScan" })
	handle.Progress = function() return nextCell / total end
	return handle
end

return Grid
