-- Bounded bootstrap-log simulation. A pre-existing oversized log is compacted
-- to its newest 800 records before append, and repeated writes never let the
-- live file exceed 1,000 records.

WR2_WORLD_RESISTANCE = nil
WR2_BOOT_EMIT = nil
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
    return {
        setup = function(registry)
            assert_true(registry == exported_events, "loader passes the exported registry")
            return true, "simulated setup"
        end
    }
end

local content_parts = {}
for i = 1, 1005 do
    content_parts[#content_parts + 1] = "old-" .. tostring(i) .. "\n"
end
local content = table.concat(content_parts)
local has_compacted = false
local post_compaction_maximum = 0

local function line_count(value)
    local count = 0
    local position = 1
    while true do
        local newline = string.find(value, "\n", position, true)
        if newline == nil then
            if position <= string.len(value) then
                count = count + 1
            end
            return count
        end
        count = count + 1
        position = newline + 1
    end
end

local function working_open(path, mode)
        assert_true(path == "wr2_world_resistance_bootstrap.log", "rotation uses the bootstrap path")
        if mode == "r" then
            local position = 1
            return {
                read = function(self, format)
                    assert_true(format == "*l", "rotation scans one line at a time")
                    if position > string.len(content) then
                        return nil
                    end
                    local newline = string.find(content, "\n", position, true)
                    local value
                    if newline == nil then
                        value = string.sub(content, position)
                        position = string.len(content) + 1
                    else
                        value = string.sub(content, position, newline - 1)
                        position = newline + 1
                    end
                    return value
                end,
                close = function(self) end
            }
        end
        if mode == "w" then
            content = ""
            has_compacted = true
        else
            assert_true(mode == "a", "rotation only reads, rewrites, or appends")
        end
        return {
            write = function(self, value)
                content = content .. tostring(value)
            end,
            flush = function(self)
                local count = line_count(content)
                if has_compacted and count > post_compaction_maximum then
                    post_compaction_maximum = count
                end
            end,
            close = function(self) end
        }
end
io = {
    open = working_open
}
out = { ting = function(line) end }

local pack_root = os.getenv("WR2_PACK_ROOT") or "../pack_root"
dofile(pack_root .. "/lua_scripts/all_scripted.lua")

local lines = {}
for value in string.gmatch(content, "([^\n]+)") do
    lines[#lines + 1] = value
end
assert_true(#lines == 808, "oversized log retains 800 old records plus eight boot records")
assert_true(lines[1] == "old-206", "compaction retains the newest 800 old records")
assert_true(lines[800] == "old-1005", "compaction retains the newest old record")
assert_true(
    string.find(lines[801], "|release=0.1.8-beta|", 1, true) ~= nil,
    "new bootstrap records carry the 0.1.8 release"
)

for i = 1, 450 do
    WR2_BOOT_EMIT("ROTATION_STRESS", tostring(i))
end

assert_true(line_count(content) <= 1000, "repeated appends leave at most 1,000 records")
assert_true(post_compaction_maximum <= 1000, "no post-compaction write exceeds 1,000 records")

while line_count(content) < 1000 do
    WR2_BOOT_EMIT("ROTATION_FILL")
end
io.open = function(path, mode)
    if mode == "w" then
        error("simulated rewrite denial")
    end
    return working_open(path, mode)
end
local rewrite_ok = pcall(WR2_BOOT_EMIT, "ROTATION_REWRITE_DENIED")
assert_true(rewrite_ok, "rewrite denial cannot escape the protected bootstrap bridge")
assert_true(line_count(content) == 1000, "rewrite denial does not append past the cap")

io.open = working_open
WR2_BOOT_EMIT("ROTATION_RECOVERY")
local before_append_denial = content
io.open = function(path, mode)
    if mode == "a" then
        error("simulated append denial")
    end
    return working_open(path, mode)
end
local append_ok = pcall(WR2_BOOT_EMIT, "ROTATION_APPEND_DENIED")
assert_true(append_ok, "append denial cannot escape the protected bootstrap bridge")
assert_true(content == before_append_denial, "append denial leaves the retained log unchanged")

print("World Resistance bootstrap log rotation simulation: "
    .. tostring(assertions) .. " assertions passed")
