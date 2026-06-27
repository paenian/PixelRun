--!strict
--[[
    run_tests.luau - Main test runner for Pixel Run Obby
    
    Discovers and executes all test files in tests/unit/ and tests/properties/.
    Run with: lune run tests/run_tests.luau
    
    Exit code:
        0 = all tests passed
        1 = one or more tests failed
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

--============================================================================
-- Configuration
--============================================================================

local TEST_DIRS = {
    { path = "tests/unit", pattern = "%.spec%.luau$", label = "Unit Tests" },
    { path = "tests/properties", pattern = "%.prop%.luau$", label = "Property Tests" },
}

--============================================================================
-- File Discovery
--============================================================================

--- Discover test files in a directory matching the given pattern.
--- @param dir string -- Directory path to search
--- @param pattern string -- Lua pattern to match filenames against
--- @return {string} -- List of file paths relative to workspace root
local function discoverTests(dir: string, pattern: string): {string}
    local files: {string} = {}
    
    local success, entries = pcall(function()
        return fs.readDir(dir)
    end)
    
    if not success or not entries then
        return files
    end
    
    for _, entry in entries do
        if string.match(entry, pattern) then
            table.insert(files, dir .. "/" .. entry)
        end
    end
    
    -- Sort for deterministic execution order
    table.sort(files)
    
    return files
end

--============================================================================
-- Test Execution
--============================================================================

type TestResult = {
    file: string,
    passed: boolean,
    output: string,
    error: string?,
}

--- Execute a single test file by requiring it.
--- @param filePath string -- Path to the test file
--- @return TestResult -- Result of running the test
local function executeTest(filePath: string): TestResult
    local result: TestResult = {
        file = filePath,
        passed = true,
        output = "",
        error = nil,
    }
    
    -- Run the test file as a subprocess using Lune
    local spawnResult = process.exec("lune", {"run", filePath})
    
    result.output = spawnResult.stdout or ""
    
    if not spawnResult.ok then
        result.passed = false
        result.error = spawnResult.stderr or ""
        if result.error == "" then
            result.error = spawnResult.stdout or ""
        end
    end
    
    return result
end

--============================================================================
-- Main Runner
--============================================================================

print("╔══════════════════════════════════════════════════════╗")
print("║         Pixel Run Obby - Test Runner                ║")
print("╚══════════════════════════════════════════════════════╝")
print("")

local totalPassed = 0
local totalFailed = 0
local allResults: {TestResult} = {}

for _, testDir in TEST_DIRS do
    local files = discoverTests(testDir.path, testDir.pattern)
    
    if #files == 0 then
        print(string.format("── %s ── (no test files found in %s)", testDir.label, testDir.path))
        print("")
        continue
    end
    
    print(string.format("── %s ── (%d files)", testDir.label, #files))
    print("")
    
    for _, file in files do
        print(string.format("  Running: %s", file))
        
        local result = executeTest(file)
        table.insert(allResults, result)
        
        -- Print output from the test
        if result.output ~= "" then
            -- Indent test output
            for line in string.gmatch(result.output, "[^\n]+") do
                print(string.format("    %s", line))
            end
        end
        
        if result.passed then
            totalPassed += 1
            print(string.format("  ✓ PASSED: %s", file))
        else
            totalFailed += 1
            print(string.format("  ✗ FAILED: %s", file))
            if result.error and result.error ~= "" then
                for line in string.gmatch(result.error, "[^\n]+") do
                    print(string.format("    ERROR: %s", line))
                end
            end
        end
        
        print("")
    end
end

--============================================================================
-- Summary
--============================================================================

print("══════════════════════════════════════════════════════")
print(string.format("  Total: %d files | ✓ %d passed | ✗ %d failed",
    totalPassed + totalFailed, totalPassed, totalFailed))
print("══════════════════════════════════════════════════════")

if totalFailed > 0 then
    print("\nFailed tests:")
    for _, result in allResults do
        if not result.passed then
            print(string.format("  - %s", result.file))
        end
    end
    process.exit(1)
else
    if totalPassed == 0 then
        print("\n  (No test files found)")
    end
    process.exit(0)
end
