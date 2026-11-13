--!strict
--[[
	Retry : ré-essaie une fonction qui peut échouer (DataStore, HTTP, ...).
	Appel BLOQUANT (yield) : à lancer dans un thread (task.spawn) si besoin.

	API
		Retry(fn, options?) -> (success: boolean, result: any, attempts: number)
			options.Attempts    nombre max d'essais            (défaut 3)
			options.Delay       délai avant le 2e essai, en s  (défaut 0.5)
			options.Backoff     multiplicateur du délai        (défaut 2)
			options.MaxDelay    plafond du délai               (défaut 30)
			options.ShouldRetry (err, attempt) -> boolean      (défaut : toujours)
			options.OnRetry     (err, attempt, nextDelay)      (facultatif)

	Exemple
		local ok, data = Retry(function()
			return store:GetAsync("key")
		end, { Attempts = 5, Delay = 1 })
]]

export type Options = {
	Attempts: number?,
	Delay: number?,
	Backoff: number?,
	MaxDelay: number?,
	ShouldRetry: ((err: any, attempt: number) -> boolean)?,
	OnRetry: ((err: any, attempt: number, nextDelay: number) -> ())?,
}

local function Retry(fn: (attempt: number) -> any, options: Options?): (boolean, any, number)
	assert(type(fn) == "function", "Retry : `fn` doit être une fonction")

	local opts: Options = options or {}
	local attempts = math.max(math.floor(opts.Attempts or 3), 1)
	local delay = opts.Delay or 0.5
	local backoff = opts.Backoff or 2
	local maxDelay = opts.MaxDelay or 30

	local lastError: any = nil
	for attempt = 1, attempts do
		local ok, result = pcall(fn, attempt)
		if ok then
			return true, result, attempt
		end

		lastError = result
		if attempt == attempts then
			break
		end
		if opts.ShouldRetry and not opts.ShouldRetry(result, attempt) then
			return false, lastError, attempt
		end

		local nextDelay = math.min(delay, maxDelay)
		if opts.OnRetry then
			opts.OnRetry(result, attempt, nextDelay)
		end
		if nextDelay > 0 then
			task.wait(nextDelay)
		end
		delay *= backoff
	end

	return false, lastError, attempts
end

return Retry
