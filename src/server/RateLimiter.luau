--!strict
--[[
    RateLimiter.luau - Enforces per-player remote call rate limits

    Limits each player to a maximum of 30 RemoteEvent calls per second.
    Excess calls are dropped and a warning is logged on the server.

    Validates: Requirements 13.6
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Types"))

--============================================================================
-- Types
--============================================================================

type RateLimitState = {
	count: number,     -- Calls this second
	lastReset: number, -- tick() of last reset
}

--============================================================================
-- Module
--============================================================================

local RateLimiter = {}

--- Maximum remote calls allowed per second per player.
RateLimiter.MAX_CALLS_PER_SECOND = Types.MAX_REMOTE_CALLS_PER_SECOND

--- Per-player rate limit state, keyed by userId.
local state: { [number]: RateLimitState } = {}

--- Checks whether a player is under the rate limit.
--- Returns true if the call is allowed, false if it should be dropped.
function RateLimiter.check(userId: number): boolean
	local now = tick()
	local playerState = state[userId]

	if not playerState then
		-- First call from this player; initialize state
		state[userId] = {
			count = 1,
			lastReset = now,
		}
		return true
	end

	-- If more than 1 second has elapsed since last reset, reset the counter
	if now - playerState.lastReset > 1 then
		playerState.count = 1
		playerState.lastReset = now
		return true
	end

	-- Increment call count
	playerState.count += 1

	-- Check if over the limit
	if playerState.count > RateLimiter.MAX_CALLS_PER_SECOND then
		warn(string.format(
			"[RateLimiter] Rate limit exceeded for userId %d (%d calls in current window)",
			userId,
			playerState.count
		))
		return false
	end

	return true
end

--- Clears the rate limit state for a player (called on player leave).
function RateLimiter.reset(userId: number): ()
	state[userId] = nil
end

return RateLimiter
