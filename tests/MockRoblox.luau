--!strict
--[[
    MockRoblox.luau - Minimal Roblox API mocks for Lune test environment
    
    Provides mock implementations of Roblox-specific globals that shared modules
    depend on (Vector3, Color3). This allows SharedModules to be require()'d
    in Lune without access to the actual Roblox engine.
    
    Usage:
        require("../tests/MockRoblox")  -- Injects globals before requiring shared modules
]]

local MockRoblox = {}

--============================================================================
-- Vector3 Mock
--============================================================================

local Vector3Methods = {}
Vector3Methods.__index = Vector3Methods

function Vector3Methods.__add(a: any, b: any): any
    return MockRoblox.Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end

function Vector3Methods.__sub(a: any, b: any): any
    return MockRoblox.Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end

function Vector3Methods.__mul(a: any, b: any): any
    if type(a) == "number" then
        return MockRoblox.Vector3.new(a * b.X, a * b.Y, a * b.Z)
    elseif type(b) == "number" then
        return MockRoblox.Vector3.new(a.X * b, a.Y * b, a.Z * b)
    else
        return MockRoblox.Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
    end
end

function Vector3Methods.__eq(a: any, b: any): boolean
    return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end

function Vector3Methods.__tostring(self: any): string
    return string.format("Vector3(%g, %g, %g)", self.X, self.Y, self.Z)
end

function Vector3Methods.Dot(self: any, other: any): number
    return self.X * other.X + self.Y * other.Y + self.Z * other.Z
end

function Vector3Methods.Cross(self: any, other: any): any
    return MockRoblox.Vector3.new(
        self.Y * other.Z - self.Z * other.Y,
        self.Z * other.X - self.X * other.Z,
        self.X * other.Y - self.Y * other.X
    )
end

MockRoblox.Vector3 = {}
MockRoblox.Vector3.zero = nil :: any -- Set after .new is defined

function MockRoblox.Vector3.new(x: number?, y: number?, z: number?): any
    local v = setmetatable({
        X = x or 0,
        Y = y or 0,
        Z = z or 0,
    }, Vector3Methods)
    return v
end

MockRoblox.Vector3.zero = MockRoblox.Vector3.new(0, 0, 0)
MockRoblox.Vector3.one = MockRoblox.Vector3.new(1, 1, 1)
MockRoblox.Vector3.yAxis = MockRoblox.Vector3.new(0, 1, 0)
MockRoblox.Vector3.xAxis = MockRoblox.Vector3.new(1, 0, 0)
MockRoblox.Vector3.zAxis = MockRoblox.Vector3.new(0, 0, 1)

--============================================================================
-- Color3 Mock
--============================================================================

local Color3Methods = {}
Color3Methods.__index = Color3Methods

function Color3Methods.__eq(a: any, b: any): boolean
    return a.R == b.R and a.G == b.G and a.B == b.B
end

function Color3Methods.__tostring(self: any): string
    return string.format("Color3(%g, %g, %g)", self.R, self.G, self.B)
end

MockRoblox.Color3 = {}

function MockRoblox.Color3.new(r: number?, g: number?, b: number?): any
    local c = setmetatable({
        R = r or 0,
        G = g or 0,
        B = b or 0,
    }, Color3Methods)
    return c
end

function MockRoblox.Color3.fromRGB(r: number, g: number, b: number): any
    return MockRoblox.Color3.new(r / 255, g / 255, b / 255)
end

function MockRoblox.Color3.fromHSV(h: number, s: number, v: number): any
    -- Simplified HSV to RGB conversion
    local c = v * s
    local x = c * (1 - math.abs((h * 6) % 2 - 1))
    local m = v - c
    local r, g, b
    local hp = h * 6
    if hp < 1 then r, g, b = c, x, 0
    elseif hp < 2 then r, g, b = x, c, 0
    elseif hp < 3 then r, g, b = 0, c, x
    elseif hp < 4 then r, g, b = 0, x, c
    elseif hp < 5 then r, g, b = x, 0, c
    else r, g, b = c, 0, x end
    return MockRoblox.Color3.new(r + m, g + m, b + m)
end

--============================================================================
-- Usage Notes
--============================================================================

--[[
    In Lune, Roblox globals like Vector3 and Color3 are not available.
    Shared modules that reference these types in their type definitions
    (e.g., Types.luau's ObstacleDefinition.color field) need mocked values
    when constructing test data.
    
    Test files should use MockRoblox directly:
    
        local MockRoblox = require("../MockRoblox")
        local Vector3 = MockRoblox.Vector3
        local Color3 = MockRoblox.Color3
        
        -- Now create test data using mocked constructors
        local pos = Vector3.new(1, 2, 3)
        local color = Color3.fromRGB(255, 0, 128)
    
    For shared modules that only use Vector3/Color3 in type annotations
    (like Types.luau) but not at runtime, they can be require()'d directly
    in Lune without needing mocks — the types are erased at runtime.
    
    For modules that use Vector3/Color3 as runtime values (like level generation),
    pass mock values through function parameters or use this module to construct them.
]]

return MockRoblox
