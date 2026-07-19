-- Rome II-faithful loader/director boundary regression.
--
-- The game is allowed to evaluate all_scripted.lua in an environment whose
-- bare globals are not raw _G.  The loader must therefore pass the exact
-- export_triggers registry to the required director's explicit setup method;
-- the director must never rediscover a decoy _G.events table.

local assertions = 0

local function assert_true(value, message)
    assertions = assertions + 1
    if not value then
        error(message or "assertion failed", 2)
    end
end

local function find_file(relative)
    local override = os.getenv("WR2_PACK_ROOT")
    local candidates = {}
    if override ~= nil and override ~= "" then
        candidates[#candidates + 1] = override .. "/" .. relative
    end
    candidates[#candidates + 1] = "../pack_root/" .. relative
    candidates[#candidates + 1] = "pack_root/" .. relative
    candidates[#candidates + 1] = relative

    local i
    for i = 1, #candidates do
        local handle = io.open(candidates[i], "rb")
        if handle ~= nil then
            handle:close()
            return candidates[i]
        end
    end
    error("cannot locate pack file " .. relative, 2)
end

local function load_with_environment(path, environment)
    local chunk, load_error
    if type(setfenv) == "function" then
        chunk, load_error = loadfile(path)
        if chunk ~= nil then
            setfenv(chunk, environment)
        end
    else
        chunk, load_error = loadfile(path, "t", environment)
    end
    assert_true(chunk ~= nil, "failed to load isolated loader: " .. tostring(load_error))
    return chunk
end

local loader_path = find_file("lua_scripts/all_scripted.lua")
local director_path = find_file("script/campaign/wr2/wr2_world_resistance.lua")

local required_events = {
    "LoadingGame",
    "SavingGame",
    "UICreated",
    "FirstTickAfterWorldCreated",
    "FactionTurnStart",
    "FactionLeaderDeclaresWar"
}

local engine_registry = {}
local decoy_registry = {}
local native_hits = {}
local function make_native_callback(event_name)
    return function()
        native_hits[event_name] = (native_hits[event_name] or 0) + 1
    end
end
local i
for i = 1, #required_events do
    local event_name = required_events[i]
    engine_registry[event_name] = { make_native_callback(event_name) }
    decoy_registry[event_name] = {}
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

local imported = {}
local function install_import(module_name)
    package.loaded[module_name] = nil
    package.preload[module_name] = function()
        imported[module_name] = true
        if module_name == "data.lua_scripts.export_triggers" then
            return { events = engine_registry }
        end
        return {}
    end
end
for i = 1, #imports do
    install_import(imports[i])
end

WR2_WORLD_RESISTANCE = nil
WR2_BOOT_EMIT = nil
scripting = nil
EpisodicScripting = nil
events = decoy_registry

package.loaded["wr2_world_resistance"] = nil
package.preload["wr2_world_resistance"] = function()
    return dofile(director_path)
end

local bootstrap_lines = {}
local native_lines = {}
local real_io = io
io = {
    open = function(_path, _mode)
        return {
            write = function(self, value)
                if value ~= "\n" then
                    bootstrap_lines[#bootstrap_lines + 1] = tostring(value)
                end
            end,
            flush = function(self) end,
            close = function(self) end
        }
    end
}
out = {
    ting = function(line)
        native_lines[#native_lines + 1] = tostring(line)
    end
}

-- Bare assignments made by this chunk land in loader_environment. Required
-- modules still execute through host require/_G, reproducing the boundary that
-- ordinary dofile-based tests erase.
local loader_environment = setmetatable({ _G = _G }, { __index = _G })
local ambient_path = package.path
local loader_ok, loader_error = pcall(load_with_environment(loader_path, loader_environment))

assert_true(loader_ok, "isolated all_scripted must remain alive: " .. tostring(loader_error))
assert_true(loader_environment.events == engine_registry, "loader preserves its vanilla registry assignment")
assert_true(rawget(_G, "events") == decoy_registry, "host _G.events remains the deliberate decoy")
assert_true(package.path == ambient_path, "loader restores package.path after explicit require")
assert_true(WR2_WORLD_RESISTANCE ~= nil, "director publishes its module state")
assert_true(type(WR2_WORLD_RESISTANCE.setup) == "function", "director exposes explicit setup")
assert_true(
    WR2_WORLD_RESISTANCE.runtime.event_registry == engine_registry,
    "setup retains the exact export_triggers registry identity"
)

for i = 1, #imports do
    assert_true(imported[imports[i]], "missing vanilla import " .. imports[i])
end
for i = 1, #required_events do
    local event_name = required_events[i]
    assert_true(#engine_registry[event_name] == 2, "WR appends to engine registry event " .. event_name)
    assert_true(#decoy_registry[event_name] == 0, "WR never touches decoy event " .. event_name)
end

local function saw_stage(stage)
    local j
    for j = 1, #bootstrap_lines do
        if string.find(bootstrap_lines[j], "|stage=" .. stage, 1, true) ~= nil then
            return true
        end
    end
    return false
end

local function first_stage_index(stage)
    local j
    for j = 1, #bootstrap_lines do
        if string.find(bootstrap_lines[j], "|stage=" .. stage, 1, true) ~= nil then
            return j
        end
    end
    return nil
end

assert_true(saw_stage("DIRECTOR_REQUIRE_OK"), "bootstrap distinguishes successful module import")
assert_true(saw_stage("DIRECTOR_SETUP_TRY"), "bootstrap records explicit setup attempt")
assert_true(saw_stage("DIRECTOR_SETUP_OK"), "bootstrap records explicit setup success")
assert_true(saw_stage("EVENT_REGISTRY_READY"), "director records exact registry acceptance")
assert_true(saw_stage("LISTENERS_READY"), "bootstrap records six-listener readiness")
for i = 1, #required_events do
    assert_true(
        saw_stage("LISTENER_OK_" .. required_events[i]),
        "bootstrap records registration for " .. required_events[i]
    )
end
assert_true(
    first_stage_index("DIRECTOR_REQUIRE_OK") < first_stage_index("DIRECTOR_SETUP_TRY"),
    "module import is distinguished before setup"
)
assert_true(
    first_stage_index("DIRECTOR_SETUP_TRY") < first_stage_index("LISTENER_OK_LoadingGame"),
    "listener insertion occurs inside explicit setup"
)
assert_true(
    first_stage_index("LISTENER_OK_FactionLeaderDeclaresWar")
        < first_stage_index("LISTENERS_READY"),
    "aggregate readiness follows all six listener results"
)
assert_true(
    first_stage_index("LISTENERS_READY") < first_stage_index("DIRECTOR_SETUP_OK"),
    "loader reports setup success only after director readiness"
)

-- Re-evaluate the loader in another isolated chunk environment while require
-- returns the already-cached director. Explicit setup must still run, verify
-- the existing wrappers, and avoid duplicating any event callback.
local second_environment = setmetatable({ _G = _G }, { __index = _G })
local second_chunk = load_with_environment(loader_path, second_environment)
local second_ok, second_error = pcall(second_chunk)
assert_true(second_ok, "cached-director loader evaluation remains alive: " .. tostring(second_error))
assert_true(second_environment.events == engine_registry, "second loader receives the same engine registry")
for i = 1, #required_events do
    local event_name = required_events[i]
    assert_true(#engine_registry[event_name] == 2, "cached setup does not duplicate " .. event_name)
    assert_true(
        saw_stage("LISTENER_REUSED_" .. event_name),
        "cached setup verifies existing wrapper " .. event_name
    )
end

-- Dispatch only the engine-owned registry. The pre-existing native callback
-- and WR callback must both run; the decoy registry remains inert.
engine_registry.UICreated[1]({})
engine_registry.UICreated[2]({})
assert_true(native_hits.UICreated == 1, "pre-existing engine callback is not overwritten")
assert_true(saw_stage("EVENT_HIT_UICreated"), "engine-registry dispatch reaches WR")

io = real_io

print("World Resistance isolated registry handoff: " .. tostring(assertions) .. " assertions passed")
