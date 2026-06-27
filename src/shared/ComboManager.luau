--!strict
--[[
    ComboManager.luau - Stub module for combo system management
    
    This is a stub to be replaced in a later epoch.
    Provides type interface and no-op implementations so other modules
    can require() this without error.
]]

local ComboManager = {}

export type ComboManager = {
	init: () -> (),
}

function ComboManager.init(): ()
end

return ComboManager
