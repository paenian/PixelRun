--!strict
--[[
    RewardsManager.luau - Stub module for rewards management
    
    This is a stub to be replaced in a later epoch.
    Provides type interface and no-op implementations so other modules
    can require() this without error.
]]

local RewardsManager = {}

export type RewardsManager = {
	init: () -> (),
}

function RewardsManager.init(): ()
end

return RewardsManager
