-- Live world-activation contract for Rome II's campaign model interface.
--
-- Rome II exposes model:campaign_name(key) as a boolean predicate.  A
-- zero-argument call is not a campaign-name getter.  This test drives the
-- protected lifecycle listeners so a false predicate, a temporarily missing
-- world, and a temporarily missing human all remain inert and retryable.

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

local function make_force()
    return {
        is_army = function(_self)
            return true
        end,
        is_navy = function(_self)
            return false
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

local function new_scenario(options)
    local opts = options or {}
    local state = {
        supported = opts.supported == true,
        probe_fails = opts.probe_fails == true,
        include_human = opts.include_human ~= false,
        turn = opts.turn or 1,
        sink = opts.sink or "ready",
        stages = {},
        campaign_arguments = {},
        mutations = {},
        diagnostic_opens = {}
    }

    local human = make_faction("rom_rome", true, 1, 1, 10000, 1)
    local ai = make_faction("rom_carthage", false, 1, 1, 100, 1)
    state.human = human
    state.ai = ai

    local faction_items = { ai }
    if state.include_human then
        faction_items = { human, ai }
    end

    local all_regions = {}
    local i
    for i = 1, 100 do
        all_regions[i] = { key = "region_" .. tostring(i) }
    end

    local world = {}
    function world:faction_list()
        return list(faction_items)
    end
    function world:region_manager()
        return {
            region_list = function(_self)
                return list(all_regions)
            end
        }
    end

    local model = {}
    function model:campaign_name(...)
        local argument_count = select("#", ...)
        local campaign_key = select(1, ...)
        state.campaign_arguments[#state.campaign_arguments + 1] = {
            count = argument_count,
            value = campaign_key
        }
        if argument_count ~= 1 then
            error("campaign_name must receive exactly one campaign key")
        end
        if campaign_key ~= "main_rome" then
            error("unexpected campaign predicate key: " .. tostring(campaign_key))
        end
        return state.supported
    end
    function model:world()
        if state.probe_fails then
            return nil
        end
        return world
    end
    function model:turn_number()
        return state.turn
    end

    local function record_mutation(kind, ...)
        state.mutations[#state.mutations + 1] = {
            kind = kind,
            args = { ... }
        }
    end

    local game = {}
    function game:model()
        return model
    end
    function game:remove_effect_bundle(...)
        record_mutation("remove_effect_bundle", ...)
    end
    function game:apply_effect_bundle(...)
        record_mutation("apply_effect_bundle", ...)
    end
    function game:treasury_mod(...)
        record_mutation("treasury_mod", ...)
    end
    function game:show_message_event(...)
        record_mutation("show_message_event", ...)
    end

    local event_registry = {
        LoadingGame = {},
        SavingGame = {},
        UICreated = {},
        FirstTickAfterWorldCreated = {},
        FactionTurnStart = {},
        FactionLeaderDeclaresWar = {}
    }

    WR2_BOOT_EMIT = function(stage, detail)
        state.stages[#state.stages + 1] = {
            stage = tostring(stage),
            detail = tostring(detail or "")
        }
    end
    out = { ting = function(_line) end }
    scripting = { game_interface = game }
    EpisodicScripting = nil
    WR2_WORLD_RESISTANCE = nil

    local WR = dofile(director_path)
    local setup_ready, setup_detail = WR.setup(event_registry)
    assert_true(setup_ready == true, "scenario listener setup succeeds: " .. tostring(setup_detail))
    state.WR = WR
    state.events = event_registry

    function state:stage_count(expected)
        local count = 0
        local j
        for j = 1, #self.stages do
            if self.stages[j].stage == expected then
                count = count + 1
            end
        end
        return count
    end

    function state:stage_detail_contains(expected, fragment)
        local j
        for j = 1, #self.stages do
            local entry = self.stages[j]
            if entry.stage == expected
                and string.find(string.lower(entry.detail), string.lower(fragment), 1, true) then
                return true
            end
        end
        return false
    end

    function state:assert_campaign_predicate_calls()
        assert_true(#self.campaign_arguments > 0, "campaign support is probed")
        local j
        for j = 1, #self.campaign_arguments do
            local call = self.campaign_arguments[j]
            assert_true(call.count == 1, "campaign_name is never called as a zero-argument getter")
            assert_true(call.value == "main_rome", "campaign_name probes only main_rome")
        end
    end

    function state:with_sink(callback)
        local real_io = io
        io = {
            open = function(path, mode)
                self.diagnostic_opens[#self.diagnostic_opens + 1] = {
                    path = tostring(path),
                    mode = tostring(mode)
                }
                if self.sink == "error" then
                    return nil, "simulated diagnostic permission denial"
                end
                return {
                    write = function(_file, _value) end,
                    flush = function(_file) end,
                    close = function(_file) end
                }
            end
        }
        local ok, error_message = pcall(callback)
        io = real_io
        assert_true(ok, "event survives diagnostic sink behavior: " .. tostring(error_message))
    end

    function state:first_tick()
        self:with_sink(function()
            self.events.FirstTickAfterWorldCreated[1]({})
        end)
    end

    function state:faction_turn(faction)
        self:with_sink(function()
            self.events.FactionTurnStart[1]({
                faction = function(_context)
                    return faction
                end
            })
        end)
    end

    return state
end

-- A false main_rome predicate is conclusively unsupported.  It must perform
-- no mutation, remain retryable, and emit a reason every time it is retried.
local recovery = new_scenario({ supported = false, turn = 31, sink = "ready" })
recovery:first_tick()
assert_true(not recovery.WR.runtime.initialized, "false campaign predicate stays inert")
assert_true(#recovery.mutations == 0, "unsupported campaign performs no world mutation")
assert_true(recovery:stage_count("WORLD_ATTEMPT") == 1, "FirstTick reports its world attempt")
assert_true(recovery:stage_count("WORLD_UNSUPPORTED") == 1, "false predicate reports unsupported")
assert_true(recovery:stage_count("WORLD_WAIT") == 1, "unsupported world reports a retryable wait")
assert_true(
    recovery:stage_detail_contains("WORLD_WAIT", "unsupported"),
    "WORLD_WAIT identifies the unsupported reason"
)

-- The first FactionTurnStart in a turn retries before faction-humanity can
-- suppress it.  A second faction callback in that same turn cannot thrash the
-- world probe.
recovery:faction_turn(recovery.ai)
assert_true(recovery:stage_count("WORLD_ATTEMPT") == 2, "an AI turn retries uninitialized world activation")
assert_true(recovery:stage_count("WORLD_UNSUPPORTED") == 2, "unsupported telemetry is non-once")
assert_true(recovery:stage_count("WORLD_WAIT") == 2, "wait telemetry is non-once")
recovery:faction_turn(recovery.human)
assert_true(
    recovery:stage_count("WORLD_ATTEMPT") == 2,
    "only the first uninitialized FactionTurnStart retries in a turn"
)

-- Once the next turn exposes a supported main_rome world, even an AI callback
-- completes initialization and produces a compact bootstrap state record.
recovery.turn = 32
recovery.supported = true
recovery:faction_turn(recovery.ai)
assert_true(recovery.WR.runtime.initialized, "next-turn AI callback activates the supported world")
assert_true(#recovery.mutations > 0, "successful activation scales the active AI")
assert_true(recovery:stage_count("WORLD_ATTEMPT") == 3, "successful retry remains observable")
assert_true(recovery:stage_count("WORLD_STATE") == 1, "successful reconcile emits bootstrap world state")
assert_true(
    recovery:stage_detail_contains("WORLD_STATE", "turn=32"),
    "WORLD_STATE identifies the reconciled turn"
)
assert_true(
    recovery:stage_detail_contains("WORLD_STATE", "active_ai=1"),
    "WORLD_STATE identifies the active AI count"
)
assert_true(
    recovery:stage_count("DIAGNOSTIC_SINK_READY") >= 1,
    "opening the detailed telemetry log is visible in bootstrap telemetry"
)
assert_true(
    recovery:stage_detail_contains("DIAGNOSTIC_SINK_READY", "data/wr2_world_resistance.log"),
    "sink-ready telemetry names the detailed log path"
)
assert_true(#recovery.diagnostic_opens >= 1, "successful reconcile attempts the detailed log")
assert_true(
    recovery.diagnostic_opens[1].path == "data/wr2_world_resistance.log",
    "detailed telemetry opens the configured relative path"
)
assert_true(recovery.diagnostic_opens[1].mode == "a", "detailed telemetry opens in append mode")
recovery:assert_campaign_predicate_calls()

-- A present model with no campaign world is a probe failure, not an
-- unsupported campaign.  It remains inert and carries a distinct reason.
local probe_failure = new_scenario({ supported = true, probe_fails = true, turn = 7 })
probe_failure:first_tick()
assert_true(not probe_failure.WR.runtime.initialized, "missing world stays inert")
assert_true(#probe_failure.mutations == 0, "missing world cannot mutate campaign state")
assert_true(probe_failure:stage_count("WORLD_PROBE_FAIL") == 1, "missing world reports probe failure")
assert_true(probe_failure:stage_count("WORLD_WAIT") == 1, "probe failure remains retryable")
assert_true(
    probe_failure:stage_detail_contains("WORLD_WAIT", "world_unavailable"),
    "WORLD_WAIT identifies the exact failed world probe"
)
probe_failure:faction_turn(probe_failure.ai)
assert_true(probe_failure:stage_count("WORLD_PROBE_FAIL") == 2, "probe-failure telemetry is non-once")
assert_true(probe_failure:stage_count("WORLD_WAIT") == 2, "probe-failure wait telemetry is non-once")
assert_true(
    #probe_failure.campaign_arguments == 0,
    "campaign predicate is not guessed when the campaign world cannot be probed"
)

-- A supported world without a human faction is a third explicit wait state.
local no_human = new_scenario({ supported = true, include_human = false, turn = 8 })
no_human:first_tick()
assert_true(not no_human.WR.runtime.initialized, "human-less world stays inert")
assert_true(#no_human.mutations == 0, "human-less world performs no scaling mutation")
assert_true(no_human:stage_count("WORLD_NO_HUMAN") == 1, "missing human is reported distinctly")
assert_true(no_human:stage_count("WORLD_WAIT") == 1, "missing human remains retryable")
assert_true(
    no_human:stage_detail_contains("WORLD_WAIT", "human"),
    "WORLD_WAIT identifies the missing-human reason"
)
no_human:faction_turn(no_human.ai)
assert_true(no_human:stage_count("WORLD_NO_HUMAN") == 2, "missing-human telemetry is non-once")
assert_true(no_human:stage_count("WORLD_WAIT") == 2, "missing-human wait telemetry is non-once")
no_human:assert_campaign_predicate_calls()

-- Detailed-file failure must be diagnosed through the already-proven
-- bootstrap sink and must never undo successful world activation.
local denied_sink = new_scenario({ supported = true, turn = 9, sink = "error" })
denied_sink:first_tick()
assert_true(denied_sink.WR.runtime.initialized, "diagnostic denial cannot block world activation")
assert_true(#denied_sink.mutations > 0, "campaign work survives diagnostic denial")
assert_true(
    denied_sink:stage_count("DIAGNOSTIC_SINK_ERROR") >= 1,
    "detailed log failure is reported through bootstrap telemetry"
)
assert_true(
    denied_sink:stage_detail_contains("DIAGNOSTIC_SINK_ERROR", "permission denial"),
    "sink-error telemetry retains the actionable open failure"
)
assert_true(
    denied_sink:stage_detail_contains("DIAGNOSTIC_SINK_ERROR", "data/wr2_world_resistance.log"),
    "sink-error telemetry names the failed detailed log path"
)
denied_sink:assert_campaign_predicate_calls()

print("World Resistance live activation contract: " .. tostring(assertions) .. " assertions passed")
