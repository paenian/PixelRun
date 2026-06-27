--!strict
--[[
    TestHarness.luau - Property-based test harness for Pixel Run Obby
    
    Provides a property testing framework with seeded random generators
    for reproducible test runs. Minimum 100 iterations per property.
    
    On failure, captures the failing seed and input for easy reproduction.
    
    Usage:
        local TestHarness = require("../tests/TestHarness")
        
        TestHarness.property("XP is non-negative", 100, function(rng)
            local blocks = TestHarness.randomInt(rng, 0, 10000)
            local pack = TestHarness.randomInt(rng, 1, 20)
            local result = LevelUtils.calculateXP(blocks, pack)
            return result >= 0, string.format("Got %d for blocks=%d, pack=%d", result, blocks, pack)
        end)
        
        TestHarness.report()
]]

local TestHarness = {}

--============================================================================
-- Types
--============================================================================

type PropertyResult = {
    name: string,
    passed: boolean,
    iterations: number,
    failingSeed: number?,
    failingIteration: number?,
    failureMessage: string?,
}

--============================================================================
-- State
--============================================================================

local results: {PropertyResult} = {}
local baseSeed: number = os.time()

--============================================================================
-- Seeded Random Number Generator
--============================================================================

--- Simple LCG (Linear Congruential Generator) for reproducible randomness.
--- State is a single integer that advances deterministically.
type RNG = {
    state: number,
    seed: number,
}

--- Create a new seeded RNG instance.
function TestHarness.createRNG(seed: number): RNG
    return {
        state = seed,
        seed = seed,
    }
end

--- Advance the RNG state and return the next pseudo-random integer.
--- Uses a standard LCG with parameters that work well for 32-bit integers.
local function nextState(rng: RNG): number
    -- LCG parameters (Numerical Recipes)
    rng.state = (rng.state * 1664525 + 1013904223) % 4294967296
    return rng.state
end

--- Generate a random integer in [min, max] inclusive using the seeded RNG.
function TestHarness.randomInt(rng: RNG, min: number, max: number): number
    local raw = nextState(rng)
    return min + (raw % (max - min + 1))
end

--- Generate a random float in [min, max) using the seeded RNG.
function TestHarness.randomFloat(rng: RNG, min: number, max: number): number
    local raw = nextState(rng)
    local t = raw / 4294967296
    return min + t * (max - min)
end

--- Generate a random boolean using the seeded RNG.
function TestHarness.randomBool(rng: RNG): boolean
    return nextState(rng) % 2 == 0
end

--- Generate a random string of given length using the seeded RNG.
--- Characters are lowercase alphanumeric.
function TestHarness.randomString(rng: RNG, minLen: number, maxLen: number): string
    local len = TestHarness.randomInt(rng, minLen, maxLen)
    local chars = {}
    local charset = "abcdefghijklmnopqrstuvwxyz0123456789"
    for _ = 1, len do
        local idx = TestHarness.randomInt(rng, 1, #charset)
        table.insert(chars, string.sub(charset, idx, idx))
    end
    return table.concat(chars)
end

--- Pick a random element from an array using the seeded RNG.
function TestHarness.randomChoice(rng: RNG, arr: {any}): any
    if #arr == 0 then
        return nil
    end
    local idx = TestHarness.randomInt(rng, 1, #arr)
    return arr[idx]
end

--============================================================================
-- Property Test Runner
--============================================================================

--- Set the base seed for all property tests in this run.
--- Useful for reproducing a specific test failure.
function TestHarness.setSeed(seed: number)
    baseSeed = seed
end

--- Get the current base seed (for reporting in output).
function TestHarness.getSeed(): number
    return baseSeed
end

--- Define and run a property test.
--- @param name string -- Descriptive name for this property
--- @param iterations number -- Number of test iterations (minimum 100 enforced)
--- @param testFn function -- Function taking (rng: RNG) -> (boolean, string?)
---   The test function should:
---   - Use the provided RNG for all random values (for reproducibility)
---   - Return true if the property holds, false if it fails
---   - Optionally return a failure message as the second value
function TestHarness.property(name: string, iterations: number, testFn: (RNG) -> (boolean, string?))
    -- Enforce minimum 100 iterations
    local actualIterations = math.max(iterations, 100)
    
    local result: PropertyResult = {
        name = name,
        passed = true,
        iterations = actualIterations,
        failingSeed = nil,
        failingIteration = nil,
        failureMessage = nil,
    }
    
    for i = 1, actualIterations do
        -- Each iteration gets a unique, deterministic seed derived from base + iteration
        local iterSeed = (baseSeed * 31 + i * 9973) % 4294967296
        local rng = TestHarness.createRNG(iterSeed)
        
        local success, err = pcall(function()
            local passed, message = testFn(rng)
            if not passed then
                error(message or "Property violated")
            end
        end)
        
        if not success then
            result.passed = false
            result.failingSeed = iterSeed
            result.failingIteration = i
            result.failureMessage = tostring(err)
            break
        end
    end
    
    table.insert(results, result)
    
    -- Print result immediately
    if result.passed then
        print(string.format("  ✓ PASS [%d iterations]: %s", actualIterations, name))
    else
        print(string.format("  ✗ FAIL [iteration %d/%d]: %s", 
            result.failingIteration :: number, actualIterations, name))
        print(string.format("    Seed: %d", result.failingSeed :: number))
        print(string.format("    Error: %s", result.failureMessage :: string))
        print(string.format("    Reproduce: TestHarness.setSeed(%d)", baseSeed))
    end
end

--============================================================================
-- Reporting
--============================================================================

--- Print a summary of all property test results and return overall pass/fail.
--- @return boolean -- true if all properties passed, false if any failed
function TestHarness.report(): boolean
    local passCount = 0
    local failCount = 0
    
    for _, result in results do
        if result.passed then
            passCount += 1
        else
            failCount += 1
        end
    end
    
    print(string.format("\n=== Property Test Results: %d passed, %d failed (seed: %d) ===",
        passCount, failCount, baseSeed))
    
    if failCount > 0 then
        print("\nFailing properties:")
        for _, result in results do
            if not result.passed then
                print(string.format("  - %s (iteration %d, seed %d)",
                    result.name, result.failingIteration :: number, result.failingSeed :: number))
                print(string.format("    %s", result.failureMessage :: string))
            end
        end
    end
    
    return failCount == 0
end

--- Reset all results (useful between test files).
function TestHarness.reset()
    results = {}
end

--- Get all results for programmatic access.
function TestHarness.getResults(): {PropertyResult}
    return results
end

return TestHarness
