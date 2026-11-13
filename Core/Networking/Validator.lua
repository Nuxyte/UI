--!nonstrict
--[[
	Networking.Validator
	Validation stricte des arguments reçus d'un client (jamais de confiance côté serveur).

	Schéma = liste de specs, une par argument (dans l'ordre). Une spec est :
		"number" | "string" | "boolean" | "table" | "any" | "Vector3" | "CFrame" | "Instance" | ... (nom `typeof`)
		ou une table :
			Type        (comme ci-dessus)
			Optional    true => nil accepté
			OneOf       { valeurs autorisées }
			Check       function(value) -> true | false | "message"      (validation sur mesure)
		  number  : Min, Max, Integer (NaN et ±inf toujours refusés)
		  string  : MinLength, MaxLength (défaut 256), Pattern
		  Instance: Class (IsA), AllowDetached (par défaut l'instance doit être dans la DataModel)
		  table   : Schema = { clé = spec }  (clés inattendues refusées sauf AllowExtra)
		            Array = spec (éléments), MaxLength (défaut 100)
		            sinon table libre limitée à MaxKeys (défaut 200) ; MaxDepth (défaut 4)
	Le schéma lui-même peut avoir AllowExtra = true pour accepter des arguments en plus.

	API
		Validator.Validate(schema, packedArgs) -> ok: boolean, err: string?
		Validator.Check(spec, value)           -> ok, err

	Exemple
		Validator.Validate({ "string", { Type = "number", Min = 1, Max = 5, Integer = true } }, table.pack("Sword", 3))
]]

local Validator = {}

local DEFAULT_MAX_DEPTH = 4

local function finite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

local check

local function checkTable(spec, value, path, depth)
	if depth > (spec.MaxDepth or DEFAULT_MAX_DEPTH) then
		return false, path .. " : table trop profonde"
	end

	if spec.Schema then
		for key, sub in spec.Schema do
			local ok, err = check(sub, value[key], path .. "." .. tostring(key), depth + 1)
			if not ok then
				return false, err
			end
		end
		if not spec.AllowExtra then
			for key in value do
				if spec.Schema[key] == nil then
					return false, ("%s : clé inattendue '%s'"):format(path, tostring(key))
				end
			end
		end
		return true
	end

	if spec.Array then
		local count = 0
		for key in value do
			count += 1
			if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
				return false, path .. " : tableau attendu"
			end
		end
		if count ~= #value then
			return false, path .. " : tableau non contigu"
		end
		if count > (spec.MaxLength or 100) then
			return false, path .. " : tableau trop long"
		end
		for i = 1, count do
			local ok, err = check(spec.Array, value[i], ("%s[%d]"):format(path, i), depth + 1)
			if not ok then
				return false, err
			end
		end
		return true
	end

	local count = 0
	for _ in value do
		count += 1
		if count > (spec.MaxKeys or 200) then
			return false, path .. " : trop de clés"
		end
	end
	return true
end

check = function(spec: any, value: any, path: string, depth: number): (boolean, string?)
	if type(spec) == "string" then
		spec = { Type = spec }
	end
	local expected = spec.Type

	if value == nil then
		if spec.Optional then
			return true
		end
		return false, ("%s : valeur manquante (%s attendu)"):format(path, tostring(expected))
	end

	if expected ~= "any" then
		local actual = typeof(value)
		if actual ~= expected then
			return false, ("%s : %s attendu, %s reçu"):format(path, tostring(expected), actual)
		end

		if expected == "number" then
			if not finite(value) then
				return false, path .. " : nombre invalide (NaN/inf)"
			end
			if spec.Integer and value ~= math.floor(value) then
				return false, path .. " : entier attendu"
			end
			if spec.Min and value < spec.Min then
				return false, ("%s : %s < min %s"):format(path, tostring(value), tostring(spec.Min))
			end
			if spec.Max and value > spec.Max then
				return false, ("%s : %s > max %s"):format(path, tostring(value), tostring(spec.Max))
			end
		elseif expected == "string" then
			if #value > (spec.MaxLength or 256) then
				return false, path .. " : chaîne trop longue"
			end
			if spec.MinLength and #value < spec.MinLength then
				return false, path .. " : chaîne trop courte"
			end
			if spec.Pattern and not string.match(value, spec.Pattern) then
				return false, path .. " : format invalide"
			end
		elseif expected == "Instance" then
			if spec.Class and not value:IsA(spec.Class) then
				return false, ("%s : doit être un %s"):format(path, spec.Class)
			end
			if not spec.AllowDetached and not value:IsDescendantOf(game) then
				return false, path .. " : instance hors de la DataModel"
			end
		elseif expected == "Vector3" then
			if not (finite(value.X) and finite(value.Y) and finite(value.Z)) then
				return false, path .. " : Vector3 invalide"
			end
		elseif expected == "Vector2" then
			if not (finite(value.X) and finite(value.Y)) then
				return false, path .. " : Vector2 invalide"
			end
		elseif expected == "CFrame" then
			local p = value.Position
			if not (finite(p.X) and finite(p.Y) and finite(p.Z)) then
				return false, path .. " : CFrame invalide"
			end
		elseif expected == "table" then
			local ok, err = checkTable(spec, value, path, depth)
			if not ok then
				return false, err
			end
		end
	end

	if spec.OneOf and not table.find(spec.OneOf, value) then
		return false, path .. " : valeur non autorisée"
	end

	if spec.Check then
		local result = spec.Check(value)
		if result ~= true then
			return false, type(result) == "string" and (path .. " : " .. result) or (path .. " : refusé par Check")
		end
	end

	return true
end

function Validator.Check(spec: any, value: any): (boolean, string?)
	return check(spec, value, "valeur", 1)
end

function Validator.Validate(schema: any, args: any): (boolean, string?)
	local given = args.n or #args
	local expected = #schema

	if given > expected and not schema.AllowExtra then
		return false, ("trop d'arguments (%d reçus, %d max)"):format(given, expected)
	end

	for i = 1, expected do
		local ok, err = check(schema[i], args[i], "argument " .. i, 1)
		if not ok then
			return false, err
		end
	end
	return true
end

return Validator
