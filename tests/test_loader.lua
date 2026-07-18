-- Standalone all_scripted.lua simulation. This verifies that the pack keeps
-- every vanilla import, exposes the exported event table, loads the director,
-- and registers listeners without relying on a campaign/mod autoloader.

WR2_WORLD_RESISTANCE = nil
events = nil
scripting = nil

local exported_events = {
    LoadingGame = {},
    SavingGame = {},
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

package.path = "../pack_root/?.lua;" .. package.path
dofile("../pack_root/lua_scripts/all_scripted.lua")

assert(events == exported_events, "loader must expose triggers.events")
for i = 1, #imports do
    assert(loaded[imports[i]], "missing vanilla import " .. imports[i])
end
assert(#events.LoadingGame == 1, "LoadingGame listener missing")
assert(#events.SavingGame == 1, "SavingGame listener missing")
assert(#events.FirstTickAfterWorldCreated == 1, "FirstTick listener missing")
assert(#events.FactionTurnStart == 1, "FactionTurnStart listener missing")
assert(#events.FactionLeaderDeclaresWar == 1, "war listener missing")

print("World Resistance loader simulation: 13 assertions passed")
