--!strict
--[[
    MascotManager.luau - Stub module for mascot management
    
    This is a stub to be replaced in a later epoch.
    Provides type interface and no-op implementations so other modules
    can require() this without error.
]]

local MascotManager = {}

export type MascotManager = {
	init: () -> (),
}

function MascotManager.init(): ()
end

return MascotManager
