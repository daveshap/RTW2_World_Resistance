-- Regression simulation for Rome II's real campaign bootstrap order.
--
-- all_scripted.lua is evaluated before the campaign script publishes its game
-- interface. World Resistance must register all ordinary listeners at once,
-- must not import EpisodicScripting early, and must lazily bind from state the
-- campaign later publishes. This test also proves that a too-early FirstTick
-- does not poison initialization: the first human turn retries safely.

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

local native_logs = {}
out = {
    ting = function(line)
        table.insert(native_logs, tostring(line))
    end
}

local calls = {}
local function record(kind, ...)
    table.insert(calls, { kind = kind, args = { ... } })
end

local function count_calls(kind)
    local count = 0
    local i
    for i = 1, #calls do
        if calls[i].kind == kind then
            count = count + 1
        end
    end
    return count
end

local function list(items)
    return {
        num_items = function(self)
            return #items
        end,
        item_at = function(self, index)
            return items[index + 1]
        end
    }
end

local function make_force()
    return {
        is_army = function(self)
            return true
        end,
        is_navy = function(self)
            return false
        end,
        has_general = function(self)
            return true
        end,
        unit_list = function(self)
            return list({})
        end
    }
end

local function make_faction(key, human, region_count, army_count, treasury, imperium)
    local regions = {}
    local forces = {}
    local i
    for i = 1, region_count do
        regions[i] = { key = key .. "_region_" .. tostring(i) }
    end
    for i = 1, army_count do
        forces[i] = make_force()
    end

    local faction = {}
    function faction:name()
        return key
    end
    function faction:is_human()
        return human
    end
    function faction:region_list()
        return list(regions)
    end
    function faction:military_force_list()
        return list(forces)
    end
    function faction:treasury()
        return treasury
    end
    function faction:imperium_level()
        return imperium
    end
    function faction:at_war()
        return false
    end
    return faction
end

local human = make_faction("rom_rome", true, 7, 16, 120000, 7)
local ai = make_faction("rom_carthage", false, 3, 1, 1000, 2)
local factions = { human, ai }
local regions = {}
local i
for i = 1, 10 do
    regions[i] = { key = "region_" .. tostring(i) }
end

local world = {}
function world:faction_list()
    return list(factions)
end
function world:region_manager()
    return {
        region_list = function(self)
            return list(regions)
        end
    }
end

local model = {}
function model:world()
    return world
end
function model:campaign_name(campaign_key)
    if campaign_key ~= "main_rome" then
        error("campaign_name must be called as the main_rome predicate")
    end
    return true
end
function model:turn_number()
    return 42
end

-- These values represent an existing save, not the defaults used for a new
-- campaign.  LoadingGame must read them before FirstTick mutates the world.
local loaded_values = {
    wr2_wr_pressure_v1 = 40,
    wr2_wr_permanent_floor_v1 = 20,
    wr2_wr_tier_v1 = 2,
    wr2_wr_demotion_turns_v1 = 3,
    wr2_wr_diplomacy_peak_v1 = 2,
    wr2_wr_highest_notified_tier_v1 = 2
}

local game = {}
function game:model()
    return model
end
function game:load_named_value(key, default, context)
    record("load_named_value", key)
    if loaded_values[key] == nil then
        return default
    end
    return loaded_values[key]
end
function game:save_named_value(key, value, context)
    record("save_named_value", key, value)
end
function game:remove_effect_bundle(bundle, faction_key)
    record("remove_effect_bundle", bundle, faction_key)
end
function game:apply_effect_bundle(bundle, faction_key, duration)
    record("apply_effect_bundle", bundle, faction_key, duration)
end
function game:treasury_mod(faction_key, amount)
    record("treasury_mod", faction_key, amount)
end
function game:show_message_event(event_key, x, y)
    record("show_message_event", event_key, x, y)
end

local imports = {
    "data.lua_scripts.export_triggers",
    "data.lua_scripts.export_ancillaries",
    "data.lua_scripts.export_historic_characters",
    "data.lua_scripts.export_missions",
    "data.lua_scripts.export_encyclopedia",
    "data.lua_scripts.export_experience",
    "data.lua_scripts.export_political_triggers"
}

for i = 1, #imports do
    local module_name = imports[i]
    package.loaded[module_name] = nil
    package.preload[module_name] = function()
        if module_name == "data.lua_scripts.export_triggers" then
            return { events = exported_events }
        end
        return {}
    end
end

-- Any early EpisodicScripting require is a regression. Rome II's campaign
-- script owns that module and publishes it only after all_scripted has run.
local episodic_loads = 0
local episodic_names = {
    "lua_scripts.EpisodicScripting",
    "lua_scripts.episodicscripting",
    "data.lua_scripts.EpisodicScripting",
    "data.lua_scripts.episodicscripting"
}
for i = 1, #episodic_names do
    local module_name = episodic_names[i]
    package.loaded[module_name] = nil
    package.preload[module_name] = function()
        episodic_loads = episodic_loads + 1
        error("WR imported EpisodicScripting too early: " .. module_name)
    end
end

package.loaded["wr2_world_resistance"] = nil
local ambient_path = "./unrelated/?.lua"
package.path = ambient_path

-- Simulate a read-only/blocked data directory from the very beginning.  Any
-- bootstrap or telemetry file attempt must fail closed; native logging and
-- campaign behavior must remain alive.
local real_io = io
io = {
    open = function()
        error("simulated permission denial")
    end
}

local loader_ok, loader_error = pcall(dofile, "lua_scripts/all_scripted.lua")
assert_true(loader_ok, "all_scripted must survive denied bootstrap logging: " .. tostring(loader_error))
assert_true(events == exported_events, "all_scripted exposes the exported event registry")
assert_true(episodic_loads == 0, "WR never imports EpisodicScripting from all_scripted")
assert_true(package.path == ambient_path, "loader restores the hostile ambient package path")
assert_true(WR2_WORLD_RESISTANCE.runtime.game == nil, "interface is allowed to be absent at import")
assert_true(#events.LoadingGame == 1, "WR registers LoadingGame immediately")
assert_true(#events.SavingGame == 1, "WR registers SavingGame immediately")
assert_true(#events.UICreated == 1, "WR registers UICreated immediately")
assert_true(#events.FirstTickAfterWorldCreated == 1, "WR registers FirstTick immediately")
assert_true(#events.FactionTurnStart == 1, "WR registers faction-turn listener immediately")
assert_true(#events.FactionLeaderDeclaresWar == 1, "WR registers war listener immediately")

-- UI and FirstTick may arrive before an interface in a pathological state.
-- Neither event may mutate the world or permanently mark WR initialized.
events.UICreated[1]({})
events.FirstTickAfterWorldCreated[1]({ existing_save = true })
assert_true(not WR2_WORLD_RESISTANCE.runtime.initialized, "too-early FirstTick remains retryable")
assert_true(count_calls("apply_effect_bundle") == 0, "too-early FirstTick performs no mutation")
assert_true(count_calls("treasury_mod") == 0, "too-early FirstTick grants no treasury")

-- Simulate main_rome/scripting.lua publishing the already-loaded interface.
-- WR discovers it but never invokes require itself.
local episodic = { game_interface = game }
package.loaded["lua_scripts.EpisodicScripting"] = episodic

events.LoadingGame[1]({ existing_save = true })
assert_true(count_calls("load_named_value") == 6, "existing-save state is loaded through all six named values")
assert_true(count_calls("apply_effect_bundle") == 0, "LoadingGame performs no world mutation")
assert_true(count_calls("treasury_mod") == 0, "LoadingGame performs no treasury mutation")

events.FactionTurnStart[1]({
    faction = function(self)
        return human
    end
})
assert_true(WR2_WORLD_RESISTANCE.runtime.initialized, "first human turn retries initialization")
assert_true(count_calls("apply_effect_bundle") >= 1, "retry applies scaling to the active AI")
assert_true(count_calls("treasury_mod") == 1, "retry grants the active AI its parity treasury")
assert_true(
    WR2_WORLD_RESISTANCE.runtime.game_interface_source
        == "package:lua_scripts.EpisodicScripting",
    "lazy lookup records the exact interface source"
)

local saw_session = false
local saw_state = false
local saw_denied_sink = false
local saw_boot_start = false
local saw_boot_success = false
local saw_listeners = false
local saw_engine_wait = false
local saw_engine_ready = false
local saw_first_tick_hit = false
local saw_world_ready = false
for i = 1, #native_logs do
    local line = native_logs[i]
    if string.find(line, "WR2|schema=1|event=BOOT", 1, true)
        and string.find(line, "|stage=LOADER_START", 1, true) then
        saw_boot_start = true
    end
    if string.find(line, "WR2|schema=1|event=BOOT", 1, true)
        and string.find(line, "|stage=DIRECTOR_REQUIRE_OK", 1, true) then
        saw_boot_success = true
    end
    if string.find(line, "|stage=LISTENERS_READY", 1, true) then
        saw_listeners = true
    end
    if string.find(line, "|stage=ENGINE_WAIT", 1, true) then
        saw_engine_wait = true
    end
    if string.find(line, "|stage=ENGINE_READY", 1, true) then
        saw_engine_ready = true
    end
    if string.find(line, "|stage=EVENT_HIT_FirstTickAfterWorldCreated", 1, true) then
        saw_first_tick_hit = true
    end
    if string.find(line, "|stage=WORLD_READY", 1, true) then
        saw_world_ready = true
    end
    if string.find(line, "WR2|schema=1|event=SESSION_START", 1, true) then
        saw_session = true
    end
    if string.find(line, "WR2|schema=1|event=STATE", 1, true)
        and string.find(line, "|turn=42|", 1, true)
        and string.find(line, "|active_ai=1|", 1, true) then
        saw_state = true
    end
    if string.find(line, "local diagnostic file batch skipped safely", 1, true) then
        saw_denied_sink = true
    end
end
assert_true(saw_boot_start, "native bootstrap trace survives denied file IO")
assert_true(saw_boot_success, "native bootstrap trace confirms the director import")
assert_true(saw_listeners, "listeners are ready before the interface")
assert_true(saw_engine_wait, "bootstrap records the initial missing interface")
assert_true(saw_engine_ready, "a later event records lazy interface acquisition")
assert_true(saw_first_tick_hit, "event-hit trace proves FirstTick dispatch")
assert_true(saw_world_ready, "human-turn retry records successful world activation")
assert_true(saw_session, "existing-save retry emits the native session trace")
assert_true(saw_state, "existing-save retry emits the native state trace")
assert_true(saw_denied_sink, "denied local logging is reported without stopping the director")

io = real_io

print("World Resistance lifecycle bootstrap simulation: " .. tostring(assertions) .. " assertions passed")
