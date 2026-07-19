-- Standalone all_scripted.lua simulation. This verifies that the pack keeps
-- every vanilla import, exposes the exported event table, loads the director,
-- and registers listeners without relying on a campaign/mod autoloader.

WR2_WORLD_RESISTANCE = nil
events = nil
scripting = nil

local assertions = 0
local function assert_true(value, message)
    assertions = assertions + 1
    if not value then
        error(message or "assertion failed", 2)
    end
end

local exported_events = {
    LoadingGame = {},
    SavingGame = {},
    UICreated = {},
    FirstTickAfterWorldCreated = {},
    FactionTurnStart = {},
    FactionLeaderDeclaresWar = {}
}

local imports = {
    "data.lua_scripts.export_triggers",
    "data.lua_scripts.export_ancillaries",
    "data.lua_scripts.export_historic_characters",
    "data.lua_scripts.export_missions",
    "data.lua_scripts.export_encyclopedia",
    "data.lua_scripts.export_experience",
    "data.lua_scripts.export_political_triggers"
}

local loaded = {}
local i
for i = 1, #imports do
    local module_name = imports[i]
    package.preload[module_name] = function()
        loaded[module_name] = true
        if module_name == "data.lua_scripts.export_triggers" then
            return { events = exported_events }
        end
        return {}
    end
end

local mock_game = {}
scripting = { game_interface = mock_game }

-- A hostile ambient path cannot resolve the director. The loader must prepend
-- its own unique pack path for the require and restore this value afterward.
package.loaded["wr2_world_resistance"] = nil
local original_path = "./unrelated/?.lua"
package.path = original_path

local file_lines = {}
io = {
    open = function(_path, _mode)
        return {
            write = function(self, value)
                if value ~= "\n" then
                    table.insert(file_lines, tostring(value))
                end
            end,
            flush = function(self) end,
            close = function(self) end
        }
    end
}

dofile("lua_scripts/all_scripted.lua")

assert_true(events == exported_events, "loader must expose triggers.events")
assert_true(WR2_WORLD_RESISTANCE ~= nil, "loader must expose the WR director")
assert_true(
    WR2_WORLD_RESISTANCE.runtime.game == mock_game,
    "a game interface available at import must register immediately"
)
for i = 1, #imports do
    assert_true(loaded[imports[i]], "missing vanilla import " .. imports[i])
end
assert_true(#events.LoadingGame == 1, "LoadingGame listener missing")
assert_true(#events.SavingGame == 1, "SavingGame listener missing")
assert_true(#events.UICreated == 1, "UICreated listener missing")
assert_true(#events.FirstTickAfterWorldCreated == 1, "FirstTick listener missing")
assert_true(#events.FactionTurnStart == 1, "FactionTurnStart listener missing")
assert_true(#events.FactionLeaderDeclaresWar == 1, "war listener missing")
assert_true(package.path == original_path, "loader restores the ambient package.path")
assert_true(
    package.loaded["wr2_world_resistance"] == WR2_WORLD_RESISTANCE,
    "explicit simple-name require is cached"
)

local saw_path = false
local saw_route = false
local saw_ready = false
for i = 1, #file_lines do
    local line = file_lines[i]
    if string.find(line, "|stage=MODULE_PATH_READY|", 1, true) then
        saw_path = true
    end
    if string.find(line, "|stage=DIRECTOR_ROUTE_OK|", 1, true) then
        saw_route = true
    end
    if string.find(line, "|stage=LISTENERS_READY", 1, true) then
        saw_ready = true
    end
end
assert_true(saw_path, "bootstrap trace records the explicit module path")
assert_true(saw_route, "bootstrap trace records the successful director route")
assert_true(saw_ready, "bootstrap trace records immediate listeners")

print("World Resistance loader simulation: " .. tostring(assertions) .. " assertions passed")
