-- Registration recovery and idempotence regression for WR.setup(registry).
-- No Rome II engine calls are required: this test isolates attachment state.

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

local director_path = find_file("script/campaign/wr2/wr2_world_resistance.lua")
local required_events = {
    "LoadingGame",
    "SavingGame",
    "UICreated",
    "FirstTickAfterWorldCreated",
    "FactionTurnStart",
    "FactionLeaderDeclaresWar"
}

local stages = {}
WR2_BOOT_EMIT = function(stage, detail)
    stages[#stages + 1] = { stage = tostring(stage), detail = tostring(detail or "") }
end
out = { ting = function(_line) end }

local decoy_registry = {}
local i
for i = 1, #required_events do
    decoy_registry[required_events[i]] = {}
end
events = decoy_registry
scripting = nil
EpisodicScripting = nil
WR2_WORLD_RESISTANCE = nil

local WR = dofile(director_path)
assert_true(type(WR.setup) == "function", "director exports WR.setup")
assert_true(WR.runtime.event_registry == nil, "module import has no implicit registry attachment")
for i = 1, #required_events do
    assert_true(#decoy_registry[required_events[i]] == 0, "module import leaves decoy registry untouched")
end

local partial_registry = {
    FactionTurnStart = {}
}
local ready, detail = WR.setup(partial_registry)
assert_true(ready == false, "partial registry cannot report ready")
assert_true(type(detail) == "string" and detail ~= "", "partial setup returns diagnostic detail")
assert_true(WR.runtime.event_registry == partial_registry, "partial setup retains registry identity for retry")
assert_true(#partial_registry.FactionTurnStart == 1, "available listener attaches during partial setup")
assert_true(WR.runtime.listeners_registered == false, "partial setup leaves aggregate readiness false")

local function stage_count(expected)
    local count = 0
    local j
    for j = 1, #stages do
        if stages[j].stage == expected then
            count = count + 1
        end
    end
    return count
end

assert_true(stage_count("EVENT_REGISTRY_READY") >= 1, "registry acceptance is observable")
assert_true(stage_count("LISTENER_OK_FactionTurnStart") == 1, "available event reports successful insertion")
assert_true(stage_count("LISTENERS_PARTIAL") >= 1, "partial aggregate state is observable")
for i = 1, #required_events do
    local event_name = required_events[i]
    if event_name ~= "FactionTurnStart" then
        assert_true(
            stage_count("LISTENER_MISSING_" .. event_name) == 1,
            "missing event is identified exactly: " .. event_name
        )
    end
end

-- Simulate export_triggers populating the remaining arrays after the first
-- setup. Dispatch through the one listener that was already attached. Its
-- protected wrapper must retry the incomplete setup before invoking gameplay.
for i = 1, #required_events do
    local event_name = required_events[i]
    if partial_registry[event_name] == nil then
        partial_registry[event_name] = {}
    end
end
partial_registry.FactionTurnStart[1]({})

assert_true(WR.runtime.listeners_registered == true, "an attached callback repairs later registry population")
for i = 1, #required_events do
    assert_true(
        #partial_registry[required_events[i]] == 1,
        "recovery attaches exactly once to " .. required_events[i]
    )
end
assert_true(stage_count("LISTENER_REUSED_FactionTurnStart") >= 1, "retry recognizes the existing wrapper")
assert_true(stage_count("LISTENERS_READY") >= 1, "successful retry reports aggregate readiness")

-- Repeating setup with the same object must be a strict no-duplicate success.
local counts_before_repeat = {}
for i = 1, #required_events do
    counts_before_repeat[required_events[i]] = #partial_registry[required_events[i]]
end
local repeated_ready, repeated_detail = WR.setup(partial_registry)
assert_true(repeated_ready == true, "repeated setup remains ready")
assert_true(type(repeated_detail) == "string", "repeated setup returns stable detail")
for i = 1, #required_events do
    local event_name = required_events[i]
    assert_true(
        #partial_registry[event_name] == counts_before_repeat[event_name],
        "same-registry setup does not duplicate " .. event_name
    )
end

-- A replacement registry in the same Lua state needs its own attachments;
-- name-only registration flags must not suppress them.
local replacement_registry = {}
for i = 1, #required_events do
    replacement_registry[required_events[i]] = {}
end
local replacement_ready, replacement_detail = WR.setup(replacement_registry)
assert_true(replacement_ready == true, "replacement registry reaches ready")
assert_true(type(replacement_detail) == "string", "replacement setup returns diagnostic detail")
assert_true(WR.runtime.event_registry == replacement_registry, "runtime tracks replacement registry identity")
for i = 1, #required_events do
    local event_name = required_events[i]
    assert_true(#replacement_registry[event_name] == 1, "replacement registry receives " .. event_name)
    assert_true(#partial_registry[event_name] == 1, "old registry is not modified during replacement setup")
end

-- A table-shaped event slot may still reject insertion. Lua 5.1's native
-- table.insert uses a raw indexed write, so a __newindex metatable is not a
-- valid way to inject this failure. Override table.insert only for the target
-- slot to exercise the protected insertion boundary in the shipped runtime.
local rejecting_slot = {}
local insert_failure_registry = {}
for i = 1, #required_events do
    insert_failure_registry[required_events[i]] = {}
end
insert_failure_registry.UICreated = rejecting_slot
local original_table_insert = table.insert
table.insert = function(target, value)
    if target == rejecting_slot then
        error("simulated insert failure")
    end
    return original_table_insert(target, value)
end
local setup_ok, insert_ready, insert_detail = pcall(WR.setup, insert_failure_registry)
table.insert = original_table_insert
if not setup_ok then
    error("protected insert failure escaped setup: " .. tostring(insert_ready), 2)
end
assert_true(insert_ready == false, "one rejecting slot makes setup partial")
assert_true(type(insert_detail) == "string", "insert failure returns aggregate detail")
assert_true(
    stage_count("LISTENER_INSERT_ERROR_UICreated") >= 1,
    "insert failure telemetry names the exact event"
)
for i = 1, #required_events do
    local event_name = required_events[i]
    if event_name ~= "UICreated" then
        assert_true(#insert_failure_registry[event_name] == 1, "valid peer still attaches: " .. event_name)
    end
end

insert_failure_registry.UICreated = {}
insert_failure_registry.FactionTurnStart[1]({})
assert_true(WR.runtime.listeners_registered == true, "peer callback repairs a replaced rejecting slot")
for i = 1, #required_events do
    assert_true(
        #insert_failure_registry[required_events[i]] == 1,
        "insert-error recovery remains duplicate-free: " .. required_events[i]
    )
end

print("World Resistance listener setup recovery: " .. tostring(assertions) .. " assertions passed")
