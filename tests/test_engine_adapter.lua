-- Integration-style simulation of the Rome II adapter. No real engine calls
-- are made; this verifies eligibility, lifecycle, idempotence, and AI-only
-- command targeting against interfaces shaped like the dumped Rome II API.

WR2_WORLD_RESISTANCE = nil

events = {
    LoadingGame = {},
    SavingGame = {},
    UICreated = {},
    FirstTickAfterWorldCreated = {},
    FactionTurnStart = {},
    FactionLeaderDeclaresWar = {}
}

local calls = {}
local native_logs = {}
out = {
    ting = function(line)
        table.insert(native_logs, line)
    end
}
local saved = {}
local loaded = {
    wr2_wr_pressure_v1 = 0,
    wr2_wr_permanent_floor_v1 = 0,
    wr2_wr_tier_v1 = 0,
    wr2_wr_demotion_turns_v1 = 0,
    wr2_wr_diplomacy_peak_v1 = 0,
    wr2_wr_highest_notified_tier_v1 = -1,
    wr2_wr_last_development_turn_v1 = -1
}

local function record(kind, ...)
    table.insert(calls, { kind = kind, args = { ... } })
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

local function force(kind)
    return {
        is_army = function(self)
            return kind == "army" or kind == "garrison"
        end,
        is_navy = function(self)
            return kind == "navy"
        end,
        has_general = function(self)
            -- Live Rome II returned true for settlement garrison forces too.
            -- The director must not depend on this value for army parity.
            return kind == "army" or kind == "garrison"
        end,
        unit_list = function(self)
            local units = {}
            local count = kind == "army" and 20 or 0
            local i
            for i = 1, count do
                units[i] = {}
            end
            return list(units)
        end
    }
end

local function region(owner, index)
    local result = {
        _key = owner._key .. "_region_" .. tostring(index),
        _province = owner._key .. "_province_" .. tostring(math.floor((index + 1) / 2)),
        _owner = owner
    }
    function result:name()
        return self._key
    end
    function result:province_name()
        return self._province
    end
    function result:owning_faction()
        return self._owner
    end
    function result:num_buildings()
        return 2
    end
    return result
end

local function faction(key, human, region_count, army_count, treasury, imperium)
    local forces = {}
    local result = {
        _key = key,
        _human = human,
        _regions = {},
        _forces = forces,
        _treasury = treasury,
        _imperium = imperium,
        _attitudes = {},
        _wars = {}
    }
    local i
    for i = 1, region_count do
        result._regions[i] = region(result, i)
    end
    for i = 1, army_count do
        forces[i] = force("army")
    end
    for i = 1, region_count do
        forces[army_count + i] = force("garrison")
    end
    function result:name()
        return self._key
    end
    function result:is_human()
        return self._human
    end
    function result:region_list()
        return list(self._regions)
    end
    function result:military_force_list()
        return list(self._forces)
    end
    function result:treasury()
        return self._treasury
    end
    function result:imperium_level()
        return self._imperium
    end
    function result:faction_attitudes()
        return self._attitudes
    end
    function result:at_war(...)
        if select("#", ...) ~= 0 then
            error("Rome II at_war() takes no arguments")
        end
        local _, active
        for _, active in pairs(self._wars) do
            if active then
                return true
            end
        end
        return false
    end
    return result
end

local rome = faction("rom_rome", true, 90, 16, 100000, 7)
local ally = faction("rom_athens", false, 4, 2, 5000, 2)
local neutral = faction("rom_arverni", false, 3, 1, 1000, 2)
local enemy = faction("rom_carthage", false, 6, 3, 9000, 3)
local dormant = faction("rom_dormant", false, 0, 0, 0, 0)

ally._attitudes = { rom_arverni = -40, rom_carthage = 20, rom_rome = -90 }
neutral._attitudes = { rom_athens = -20, rom_carthage = 30, rom_rome = -80 }
enemy._attitudes = { rom_athens = 10, rom_arverni = 40, rom_rome = -70 }

ally._wars[neutral._key] = true
neutral._wars[ally._key] = true

local factions = { rome, ally, neutral, enemy, dormant }
local all_regions = {}
local i
for i = 1, 173 do
    all_regions[i] = { key = "region_" .. tostring(i) }
end

local model = { _turn = 77 }
local world = {}
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
    return self._turn
end
function world:faction_list()
    return list(factions)
end
function world:region_manager()
    return {
        region_list = function(self)
            return list(all_regions)
        end
    }
end

local game = {}
function game:model()
    return model
end
function game:apply_effect_bundle(bundle, faction_key, duration)
    record("apply_effect_bundle", bundle, faction_key, duration)
end
function game:remove_effect_bundle(bundle, faction_key)
    record("remove_effect_bundle", bundle, faction_key)
end
function game:treasury_mod(faction_key, amount)
    record("treasury_mod", faction_key, amount)
end
function game:add_development_points_to_region(region_key, amount)
    if self._development_error then
        error("simulated development binding failure")
    end
    record("add_development_points_to_region", region_key, amount)
end
function game:force_diplomacy(a, b, deal, offer, accept)
    record("force_diplomacy", a, b, deal, offer, accept)
end
function game:cai_strategic_stance_manager_promote_specified_stance_towards_target_faction(a, b, stance)
    record("promote_stance", a, b, stance)
end
function game:force_make_peace(a, b)
    record("force_make_peace", a, b)
    local left, right
    for _, item in ipairs(factions) do
        if item._key == a then left = item end
        if item._key == b then right = item end
    end
    if left and right then
        left._wars[b] = false
        right._wars[a] = false
    end
end
function game:force_make_trade_agreement(a, b)
    record("force_make_trade_agreement", a, b)
end
function game:show_message_event(event_key, x, y)
    record("show_message_event", event_key, x, y)
end
function game:save_named_value(key, value, context)
    saved[key] = value
    record("save_named_value", key, value)
end
function game:load_named_value(key, default, context)
    record("load_named_value", key)
    if loaded[key] == nil then
        return default
    end
    return loaded[key]
end

scripting = { game_interface = game }

local WR = dofile("../pack_root/script/campaign/wr2/wr2_world_resistance.lua")
local setup_ready, setup_detail = WR.setup(events)
WR.config.diplomacy_pair_budget_first_tick = 2
WR.config.diplomacy_pair_budget_ai_turn = 1

local assertions = 0
local function assert_true(value, message)
    assertions = assertions + 1
    if not value then
        error(message or "assertion failed", 2)
    end
end
local function count_calls(kind)
    local count = 0
    for _, call in ipairs(calls) do
        if call.kind == kind then
            count = count + 1
        end
    end
    return count
end

assert_true(setup_ready == true, "explicit event-registry setup succeeds: " .. tostring(setup_detail))
assert_true(#events.FirstTickAfterWorldCreated == 1, "one FirstTick listener")
assert_true(#events.LoadingGame == 1, "one LoadingGame listener")
assert_true(#events.SavingGame == 1, "one SavingGame listener")
assert_true(#events.UICreated == 1, "one UICreated listener")

-- Loading reads primitives and performs no mutation.
events.LoadingGame[1]({})
local mutation_before_first_tick = count_calls("apply_effect_bundle")
    + count_calls("remove_effect_bundle")
    + count_calls("treasury_mod")
    + count_calls("force_diplomacy")
    + count_calls("promote_stance")
    + count_calls("force_make_peace")
    + count_calls("add_development_points_to_region")
assert_true(mutation_before_first_tick == 0, "LoadingGame is read-only")
assert_true(count_calls("show_message_event") == 0, "LoadingGame never invokes UI")

-- UI may be created before the campaign world is ready; no status message is
-- legal until the first successful reconciliation completes.
events.UICreated[1]({})
assert_true(count_calls("show_message_event") == 0, "UICreated alone does not show status")

-- A denied diagnostic-file write must fail closed while native out.ting and
-- every campaign mutation continue normally.
local real_io = io
io = {
    open = function()
        return nil, "simulated read-only game directory"
    end
}

events.FirstTickAfterWorldCreated[1]({})
io = real_io
local after_first_tick = #calls
local cached_pairs_after_first_tick = 0
for _, _ in pairs(WR.runtime.diplomacy_mode_by_pair) do
    cached_pairs_after_first_tick = cached_pairs_after_first_tick + 1
end
assert_true(cached_pairs_after_first_tick == 2, "first callback obeys the diplomacy pair budget")
assert_true(count_calls("show_message_event") == 1, "successful first reconciliation shows status")
assert_true(
    calls[#calls].kind == "show_message_event"
        and calls[#calls].args[1] == "custom_event_23182004",
    "initial status matches the active Tier 85 band"
)
local saw_session = false
local saw_state = false
local saw_diplomacy_audit = false
local saw_file_failure = false
for _, line in ipairs(native_logs) do
    if string.find(line, "WR2|schema=1|event=SESSION_START", 1, true) then
        saw_session = true
    end
    if string.find(line, "WR2|schema=1|event=STATE", 1, true)
        and string.find(line, "|active_ai=3|", 1, true) then
        saw_state = true
    end
    if string.find(line, "WR2|schema=1|event=DIPLOMACY_AUDIT", 1, true)
        and string.find(line, "|ai_ai_count=6|", 1, true)
        and string.find(line, "|ai_human_count=3|", 1, true)
        and string.find(line, "|cooperation_mode=promotion_only|", 1, true)
        and string.find(line, "|best_friend_promotions_ok=2|", 1, true) then
        saw_diplomacy_audit = true
    end
    if string.find(line, "local diagnostic file batch skipped safely", 1, true) then
        saw_file_failure = true
    end
end
assert_true(saw_session, "native out.ting receives the session trace")
assert_true(saw_state, "native out.ting receives the structured state trace")
assert_true(saw_diplomacy_audit, "periodic audit separates AI-AI from AI-human attitudes")
assert_true(saw_file_failure, "file failure is reported natively and remains nonfatal")
assert_true(
    count_calls("add_development_points_to_region") == 7,
    "Tier 85 grants once per unique AI-owned province"
)
for _, call in ipairs(calls) do
    if call.kind == "add_development_points_to_region" then
        assert_true(call.args[2] == 2, "Tier 85 grants two development points")
        assert_true(
            string.find(call.args[1], "rom_rome", 1, true) == nil,
            "human regions receive no development points"
        )
    end
end

-- A second callback in the same Lua campaign session must be a no-op.
events.FirstTickAfterWorldCreated[1]({})
assert_true(#calls == after_first_tick, "FirstTick initialization is idempotent")

-- A later AI turn resumes the bounded all-pairs reconciliation.
events.FactionTurnStart[1]({
    faction = function(self)
        return enemy
    end
})
local cached_pairs_after_ai_turn = 0
for _, _ in pairs(WR.runtime.diplomacy_mode_by_pair) do
    cached_pairs_after_ai_turn = cached_pairs_after_ai_turn + 1
end
assert_true(cached_pairs_after_ai_turn == 3, "AI turn resumes and completes queued diplomacy")

local applied_by_faction = {}
local treasury_by_faction = {}
for _, call in ipairs(calls) do
    if call.kind == "apply_effect_bundle" then
        local faction_key = call.args[2]
        applied_by_faction[faction_key] = (applied_by_faction[faction_key] or 0) + 1
    elseif call.kind == "treasury_mod" then
        treasury_by_faction[call.args[1]] = true
    elseif call.kind == "force_diplomacy"
        or call.kind == "force_make_peace"
        or call.kind == "force_make_trade_agreement"
        or call.kind == "promote_stance" then
        local a = call.args[1]
        local b = call.args[2]
        assert_true(a ~= "rom_rome" and b ~= "rom_rome", "diplomacy call must be AI-to-AI")
        assert_true(a ~= "rom_dormant" and b ~= "rom_dormant", "dormant faction must not be targeted")
    end
end

assert_true(applied_by_faction.rom_athens == 2, "ally receives full base and catch-up scaling")
assert_true(applied_by_faction.rom_arverni == 2, "neutral receives full base and catch-up scaling")
assert_true(applied_by_faction.rom_carthage == 2, "enemy receives full base and catch-up scaling")
assert_true(applied_by_faction.rom_rome == nil, "human receives no applied bundle")
assert_true(applied_by_faction.rom_dormant == nil, "dormant faction receives no bundle")
assert_true(treasury_by_faction.rom_athens, "ally receives treasury parity")
assert_true(treasury_by_faction.rom_arverni, "neutral receives treasury parity")
assert_true(treasury_by_faction.rom_carthage, "enemy receives treasury parity")
assert_true(treasury_by_faction.rom_rome == nil, "human receives no treasury grant")
assert_true(count_calls("force_make_peace") == 1, "existing AI-AI war is ended at tier 85")
assert_true(ally._wars[neutral._key] ~= true, "mock AI-AI war state is peaceful")
assert_true(count_calls("promote_stance") == 6, "all three AI pairs receive bidirectional stance promotion")
assert_true(count_calls("force_make_trade_agreement") == 0, "forced trade waits for tier 100")

local snapshot = WR.debug_snapshot()
assert_true(snapshot.ai_count == 3, "all and only active AIs counted")
assert_true(snapshot.tier == 4, "ninety regions reaches tier 85")
assert_true(snapshot.target_armies == 16, "final Imperium army parity target")
assert_true(snapshot.ai_commanded_armies == 6, "regional garrisons are subtracted from AI field-army estimates")
assert_true(snapshot.ai_full_armies == 6, "largest estimated field stacks are reported as full")
assert_true(snapshot.ai_army_goal == 16 + 12 + 16, "AI goals use four armies per region capped at sixteen")
assert_true(snapshot.best_friend_promotions_ok == 3, "all AI pairs report accepted best-friends promotions")
assert_true(snapshot.development_status == "accepted", "development batch is accepted")
assert_true(snapshot.development_points_per_province == 2, "Tier 85 development scale is reported")
assert_true(snapshot.development_provinces == 7, "unique AI provinces are reported")
assert_true(snapshot.development_commands_ok == 7, "accepted development commands are reported")
assert_true(snapshot.development_commands_failed == 0, "successful development batch reports no failures")
assert_true(snapshot.development_owner_skips == 0, "stable ownership reports no development skips")
assert_true(snapshot.development_points_granted == 14, "requested development points are reported")
assert_true(snapshot.last_development_turn == 77, "development turn high-water mark is reported")

events.SavingGame[1]({})
assert_true(saved.wr2_wr_pressure_v1 ~= nil, "pressure saved")
assert_true(saved.wr2_wr_permanent_floor_v1 == 65, "permanent floor saved")
assert_true(saved.wr2_wr_tier_v1 == 4, "tier saved")
assert_true(saved.wr2_wr_diplomacy_peak_v1 == 4, "diplomacy high-water mark saved")
assert_true(saved.wr2_wr_highest_notified_tier_v1 == 4, "highest UI tier saved")
assert_true(saved.wr2_wr_last_development_turn_v1 == 77, "development turn high-water mark saved")

-- Restoring the saved high-water mark and recreating the UI must not repeat an
-- already acknowledged tier notification.
for key, value in pairs(saved) do
    loaded[key] = value
end
local notices_before_reload = count_calls("show_message_event")
events.LoadingGame[1]({})
events.UICreated[1]({})
assert_true(
    count_calls("show_message_event") == notices_before_reload,
    "saved UI high-water mark prevents reload duplicates"
)
assert_true(
    count_calls("add_development_points_to_region") == 7,
    "same-turn reload does not duplicate development grants"
)

-- Seventy percent of the live map reaches tier 100. Every AI pair is then
-- trade-forced while war remains blocked; no command may include the human.
for i = #rome._regions + 1, 122 do
    rome._regions[i] = region(rome, i)
end
model._turn = 78
events.FactionTurnStart[1]({
    faction = function(self)
        return rome
    end
})
local maximum = WR.debug_snapshot()
assert_true(maximum.pressure == 100, "seventy percent map reaches pressure 100")
assert_true(maximum.tier == 5, "pressure 100 applies the maximum tier")
assert_true(maximum.diplomacy_peak == 5, "maximum diplomacy mode is permanent")
assert_true(maximum.diplomatic_calls == 75, "tier 100 remains at the stable 25-call profile per AI pair")
assert_true(maximum.development_points_per_province == 3, "Tier 100 grants three points per AI province")
assert_true(maximum.development_commands_ok == 7, "new turn grants each AI province once")
assert_true(maximum.development_commands_failed == 0, "Tier 100 development reports no failures")
assert_true(maximum.development_points_granted == 21, "Tier 100 requested development total is reported")
assert_true(maximum.last_development_turn == 78, "new campaign turn advances development high-water mark")
assert_true(
    count_calls("add_development_points_to_region") == 14,
    "development grants repeat only on a new campaign turn"
)
assert_true(count_calls("force_make_trade_agreement") == 3, "all AI pairs receive forced trade at maximum")
assert_true(count_calls("show_message_event") == 2, "maximum tier creates one additional notice")
local last_status_key = nil
for _, call in ipairs(calls) do
    if call.kind == "show_message_event" then
        last_status_key = call.args[1]
    end
end
assert_true(last_status_key == "custom_event_23182005", "maximum notice uses the Tier 100 event")

-- A native development failure is contained per target, reported honestly,
-- and never retried in the same turn. Other world reconciliation continues.
model._turn = 79
game._development_error = true
events.FactionTurnStart[1]({
    faction = function(self)
        return rome
    end
})
local failed_development = WR.debug_snapshot()
assert_true(failed_development.development_status == "disabled_on_error", "all-target failure is explicit")
assert_true(failed_development.development_commands_ok == 0, "failed native commands are not accepted")
assert_true(failed_development.development_commands_failed == 7, "every failed province command is counted")
assert_true(failed_development.last_development_turn == 79, "failed batch still advances dedupe turn")
assert_true(count_calls("add_development_points_to_region") == 14, "failed calls do not forge accepted records")

events.FactionTurnStart[1]({
    faction = function(self)
        return rome
    end
})
assert_true(
    count_calls("add_development_points_to_region") == 14,
    "failed batch is not repeated in the same campaign turn"
)

game._development_error = false
model._turn = 80
events.FactionTurnStart[1]({
    faction = function(self)
        return rome
    end
})
assert_true(count_calls("add_development_points_to_region") == 21, "development resumes on the next turn")

-- If ownership changes between collection and mutation, the human-protection
-- guard skips that representative rather than trusting stale faction state.
ally._regions[1]._owner = rome
model._turn = 81
events.FactionTurnStart[1]({
    faction = function(self)
        return rome
    end
})
local ownership_changed = WR.debug_snapshot()
assert_true(ownership_changed.development_status == "owner_changed", "owner change is explicit")
assert_true(ownership_changed.development_owner_skips == 1, "changed owner is counted once")
assert_true(ownership_changed.development_commands_ok == 6, "other AI provinces still receive support")
assert_true(count_calls("add_development_points_to_region") == 27, "human-owned representative is skipped")
ally._regions[1]._owner = ally

-- If an AI declaration slips through the campaign AI, the audited event
-- exposes the declarer's character. The callback must end only AI-AI wars.
enemy._wars[neutral._key] = true
neutral._wars[enemy._key] = true
events.FactionLeaderDeclaresWar[1]({
    character = function(self)
        return {
            faction = function(self)
                return enemy
            end
        }
    end
})
assert_true(enemy._wars[neutral._key] ~= true, "AI-AI declaration is immediately neutralised")

-- A human declaration never invokes the peace routine, preserving every
-- player-facing diplomatic choice.
rome._wars[enemy._key] = true
enemy._wars[rome._key] = true
events.FactionLeaderDeclaresWar[1]({
    character = function(self)
        return {
            faction = function(self)
                return rome
            end
        }
    end
})
assert_true(rome._wars[enemy._key] == true, "human wars are never rewritten")

for _, call in ipairs(calls) do
    if call.kind == "force_diplomacy"
        or call.kind == "force_make_peace"
        or call.kind == "force_make_trade_agreement"
        or call.kind == "promote_stance" then
        assert_true(call.args[1] ~= "rom_rome" and call.args[2] ~= "rom_rome", "maximum-tier diplomacy remains AI-only")
    end
end

print("World Resistance engine simulation: " .. tostring(assertions) .. " assertions passed")
