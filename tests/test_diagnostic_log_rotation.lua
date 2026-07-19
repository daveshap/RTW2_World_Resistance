-- The detailed campaign log must never exceed 1,000 records. This simulation
-- begins with an oversized file, drives enough human turns to roll repeatedly,
-- and proves that a denied rewrite skips file output without stopping the mod.

WR2_WORLD_RESISTANCE = nil
scripting = nil

local assertions = 0
local function assert_true(value, message)
    assertions = assertions + 1
    if not value then
        error(message or "assertion failed", 2)
    end
end

local function list(items)
    return {
        num_items = function(_self)
            return #items
        end,
        item_at = function(_self, index)
            return items[index + 1]
        end
    }
end

local function field_army()
    local units = {}
    local i
    for i = 1, 20 do
        units[i] = {}
    end
    return {
        is_army = function(_self) return true end,
        is_navy = function(_self) return false end,
        has_general = function(_self) return true end,
        unit_list = function(_self) return list(units) end
    }
end

local function faction(key, human, region_count, army_count, treasury, imperium)
    local regions = {}
    local forces = {}
    local i
    for i = 1, region_count do
        regions[i] = {}
    end
    for i = 1, army_count do
        forces[i] = field_army()
    end
    local result = {}
    function result:name() return key end
    function result:is_human() return human end
    function result:region_list() return list(regions) end
    function result:military_force_list() return list(forces) end
    function result:treasury() return treasury end
    function result:imperium_level() return imperium end
    function result:at_war() return false end
    function result:faction_attitudes() return {} end
    return result
end

local human = faction("rom_rome", true, 70, 16, 250000, 7)
local ai = faction("rom_carthage", false, 4, 4, 5000, 7)
local factions = { human, ai }
local world_regions = {}
local i
for i = 1, 100 do
    world_regions[i] = {}
end

local turn = 1
local world = {}
function world:faction_list() return list(factions) end
function world:region_manager()
    return { region_list = function(_self) return list(world_regions) end }
end
local model = {}
function model:world() return world end
function model:campaign_name(key) return key == "main_rome" end
function model:turn_number() return turn end

local game = {}
function game:model() return model end
function game:remove_effect_bundle(_bundle, _key) end
function game:apply_effect_bundle(_bundle, _key, _duration) end
function game:treasury_mod(_key, _amount) end
function game:show_message_event(_key, _x, _y) end
scripting = { game_interface = game }

local parts = {}
for i = 1, 1005 do
    parts[i] = "old-" .. tostring(i) .. "\n"
end
local content = table.concat(parts)
local deny_rewrite = false
local maximum_after_first_rewrite = 0

local function line_count(value)
    local _, count = string.gsub(value, "\n", "")
    if value ~= "" and string.sub(value, -1) ~= "\n" then
        count = count + 1
    end
    return count
end

local function memory_open(path, mode)
    assert_true(path == "data/wr2_world_resistance.log", "director uses the detailed log path")
    if mode == "r" then
        return {
            read = function(_self, format)
                assert_true(format == "*a", "rotation reads the complete bounded log")
                return content
            end,
            close = function(_self) end
        }
    end
    if mode == "w" then
        if deny_rewrite then
            return nil, "simulated rewrite denial"
        end
        content = ""
    else
        assert_true(mode == "a", "director only reads, rewrites, or appends")
    end
    return {
        write = function(_self, value) content = content .. tostring(value) end,
        flush = function(_self)
            local count = line_count(content)
            if count > maximum_after_first_rewrite then
                maximum_after_first_rewrite = count
            end
        end,
        close = function(_self) end
    }
end

io = { open = memory_open }
out = { ting = function(_line) end }

local events = {
    LoadingGame = {},
    SavingGame = {},
    UICreated = {},
    FirstTickAfterWorldCreated = {},
    FactionTurnStart = {},
    FactionLeaderDeclaresWar = {}
}
local WR = dofile("../pack_root/script/campaign/wr2/wr2_world_resistance.lua")
local ready = WR.setup(events)
assert_true(ready == true, "director setup succeeds")
events.FirstTickAfterWorldCreated[1]({})
assert_true(line_count(content) <= 1000, "oversized detailed log is compacted before append")
assert_true(string.find(content, "old-206", 1, true) == 1, "newest 800 old records are retained")

WR.config.detailed_audit_turn_interval = 0
for i = 1, 450 do
    turn = turn + 1
    events.FactionTurnStart[1]({ faction = function(_self) return human end })
    assert_true(line_count(content) <= 1000, "live detailed log stays within its hard cap")
end

while line_count(content) < 1000 do
    turn = turn + 1
    events.FactionTurnStart[1]({ faction = function(_self) return human end })
end
deny_rewrite = true
local before_denial = content
turn = turn + 1
local denied_ok = pcall(events.FactionTurnStart[1], {
    faction = function(_self) return human end
})
assert_true(denied_ok, "rewrite denial never escapes the protected event listener")
assert_true(content == before_denial, "rewrite denial cannot append past 1,000 lines")

deny_rewrite = false
turn = turn + 1
events.FactionTurnStart[1]({ faction = function(_self) return human end })
assert_true(line_count(content) == 801, "rotation recovers to an 800-line tail plus the new record")
assert_true(maximum_after_first_rewrite <= 1000, "no completed detailed-log write exceeds the cap")

print("World Resistance detailed log rotation simulation: "
    .. tostring(assertions) .. " assertions passed")
