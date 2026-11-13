--!strict
--[[
	Core/Types
	Types Luau partagés. Aucun code à l'exécution : `require` est facultatif,
	utilisez-le uniquement pour importer des types :

		local Types = require(Core.Types)
		local function f(options: Types.TweenOptions) end
]]

export type Cleanable =
	Instance
	| RBXScriptConnection
	| thread
	| () -> ()
	| { Destroy: (any) -> () }
	| { Disconnect: (any) -> () }

export type EasingSpec = string | Enum.EasingStyle | (number) -> number

export type TweenOptions = {
	Duration: number?,
	Easing: EasingSpec?,
	Delay: number?,
	-- Nombre de répétitions supplémentaires (0 = une seule lecture, -1 = infini).
	Repeat: number?,
	-- Aller puis retour à chaque cycle.
	Yoyo: boolean?,
	-- Joue de la valeur cible vers la valeur actuelle.
	Reverse: boolean?,
	OnStart: (() -> ())?,
	OnUpdate: ((...any) -> ())?,
	OnComplete: (() -> ())?,
	-- false = force le moteur logiciel (au lieu de TweenService).
	Native: boolean?,
}

export type TweenSpec = {
	Target: any,
	Props: { [string]: any },
	Options: (TweenOptions | number)?,
}

return {}
