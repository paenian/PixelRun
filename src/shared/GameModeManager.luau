--!strict
--[[
    GameModeManager.luau - Stub module for game mode management
    
    This is a stub to be replaced in a later epoch.
    Provides type interface and no-op implementations so other modules
    can require() this without error.
]]

local GameModeManager = {}

export type GameModeManager = {
	init: () -> (),
}

function GameModeManager.init(): ()
end

return GameModeManager
