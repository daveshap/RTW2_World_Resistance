-- The root loader must survive and diagnose a director import failure before
-- any Rome II campaign interface exists.

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

local exported_events = {}
local imports = {
    "data.lua_scripts.export_triggers",
    "data.lua_scripts.export_ancillaries",
    "data.lua_scripts.export_historic_characters",
    "data.lua_scripts.export_missions",
    "data.lua_scripts.export_encyclopedia",
    "data.lua_scripts.export_experience",
    "data.lua_scripts.export_political_triggers"
}
local i
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

package.loaded["wr2_world_resistance"] = nil
package.preload["wr2_world_resistance"] = function()
    error("simulated|director\nimport failure")
end

local opened_paths = {}
local file_lines = {}
io = {
    open = function(path, mode)
        table.insert(opened_paths, path .. ":" .. mode)
        if mode == "r" then
            return nil
        end
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

local native_lines = {}
out = {
    ting = function(line)
        table.insert(native_lines, tostring(line))
    end
}

local original_path = package.path
local ok, failure = pcall(dofile, "lua_scripts/all_scripted.lua")
assert_true(ok, "director import failure must not abort the vanilla loader: " .. tostring(failure))
assert_true(events == exported_events, "vanilla event registry remains available")
assert_true(
    #opened_paths == 7,
    "loader scans once and writes start, registry, path, route, and failure records"
)
assert_true(
    opened_paths[1] == "wr2_world_resistance_bootstrap.log:r",
    "loader scans the root bootstrap path before its first append"
)
for i = 2, #opened_paths do
    assert_true(
        opened_paths[i] == "wr2_world_resistance_bootstrap.log:a",
        "every record uses the root bootstrap path"
    )
end
assert_true(package.path == original_path, "failed require still restores package.path")

local saw_start = false
local saw_registry = false
local saw_error = false
local saw_route_error = false
for i = 1, #file_lines do
    local line = file_lines[i]
    if string.find(line, "|stage=LOADER_START", 1, true) then
        saw_start = true
    end
    if string.find(line, "|stage=EVENT_REGISTRY_READY|", 1, true) then
        saw_registry = true
    end
    if string.find(line, "|stage=DIRECTOR_ROUTE_ERROR|", 1, true) then
        saw_route_error = true
    end
    if string.find(line, "|stage=DIRECTOR_REQUIRE_ERROR", 1, true) then
        saw_error = true
        assert_true(
            string.find(line, "simulated director import failure", 1, true) ~= nil,
            "structured bootstrap error sanitizes delimiters and newlines"
        )
        assert_true(
            string.find(line, "simulated|director", 1, true) == nil,
            "structured error cannot forge telemetry fields"
        )
    end
end
assert_true(saw_start, "bootstrap start record is retained")
assert_true(saw_registry, "exported event-registry readiness is retained")
assert_true(saw_route_error, "route-level director error is retained")
assert_true(saw_error, "director import error is retained")
assert_true(#native_lines >= 3, "native logging also receives boot and loader error records")
assert_true(WR2_WORLD_RESISTANCE == nil, "failed director does not publish partial state")

print("World Resistance loader failure simulation: " .. tostring(assertions) .. " assertions passed")
