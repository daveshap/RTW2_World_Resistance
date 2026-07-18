-- World Resistance: universal anti-hegemon campaign director for Total War: ROME II.
--
-- Pack path (loaded by lua_scripts/all_scripted.lua):
--   lua_scripts/wr2_world_resistance.lua
--
-- Design constraints:
--   * Every active non-human faction scales. Diplomacy/war/ally status is irrelevant.
--   * Every diplomatic command is strictly AI-to-AI.
--   * No force creation or emergency spawning occurs in this script.
--   * World mutation begins at FirstTickAfterWorldCreated, never LoadingGame.
--   * Save data consists only of primitive values supported by Rome II.

local VERSION = 2
local GLOBAL_KEY = "WR2_WORLD_RESISTANCE"

local existing = rawget(_G, GLOBAL_KEY)
if existing ~= nil and existing.__version == VERSION then
    return existing
end

local WR = {
    __version = VERSION
}
rawset(_G, GLOBAL_KEY, WR)

WR.config = {
    namespace = "wr2_wr_",
    supported_campaign = "main_rome",

    -- Grand Campaign thresholds expressed as a share of the live campaign's
    -- region count. Interpolation between points makes territory the main,
    -- continuous pressure driver.
    territory_curve = {
        { share = 0.00, pressure = 0 },
        { share = 0.10, pressure = 20 },
        { share = 0.20, pressure = 40 },
        { share = 0.32, pressure = 65 },
        { share = 0.50, pressure = 85 },
        { share = 0.70, pressure = 100 }
    },

    -- Rome II's vanilla Grand Campaign has Imperium levels 1..7. Reaching
    -- the final level permanently establishes the requested endgame floor.
    final_imperium_level = 7,
    final_imperium_pressure_floor = 65,
    final_imperium_min_armies = 16,

    army_signal_reference = 16,
    treasury_signal_reference = 100000,
    army_signal_weight_of_remainder = 0.10,
    treasury_signal_weight_of_remainder = 0.05,

    demotion_turns_required = 10,

    -- Tier zero is intentionally a real bundle: every living AI scales from
    -- the beginning instead of waiting for contact or war with the human.
    tiers = {
        { threshold = 0,   bundle = "wr2_wr_ai_tier_00", treasury_floor = 5000 },
        { threshold = 20,  bundle = "wr2_wr_ai_tier_20", treasury_floor = 10000 },
        { threshold = 40,  bundle = "wr2_wr_ai_tier_40", treasury_floor = 30000 },
        { threshold = 65,  bundle = "wr2_wr_ai_tier_65", treasury_floor = 75000 },
        { threshold = 85,  bundle = "wr2_wr_ai_tier_85", treasury_floor = 150000 },
        { threshold = 100, bundle = "wr2_wr_ai_tier_100", treasury_floor = 300000 }
    },

    catchup_bundles = {
        [0] = nil,
        [1] = "wr2_wr_ai_catchup_1",
        [2] = "wr2_wr_ai_catchup_2",
        [3] = "wr2_wr_ai_catchup_3"
    },
    catchup_treasury_multipliers = {
        [0] = 1.00,
        [1] = 1.25,
        [2] = 1.75,
        [3] = 2.50
    },
    replacement_reserve_per_target_army = 8000,
    max_treasury_grant_per_update = 2000000,
    max_treasury_target = 100000000,

    -- At tiers 0..3, cooperation is increasingly favoured. At tier 4 the
    -- anti-AI-war lock begins; tier 5 additionally attempts universal legal
    -- AI-to-AI trade. Diplomacy is a high-water mark to prevent toggling and
    -- because force_diplomacy has no documented "restore vanilla" operation.
    hard_ai_peace_tier = 4,
    force_trade_tier = 5,

    -- Strategic stance promotion is directional, so it is always applied in
    -- both directions and only after the pair has passed the AI-only guard.
    strategic_stances = {
        [1] = "CAI_STRATEGIC_STANCE_FRIENDLY",
        [2] = "CAI_STRATEGIC_STANCE_VERY_FRIENDLY",
        [3] = "CAI_STRATEGIC_STANCE_BEST_FRIENDS",
        [4] = "CAI_STRATEGIC_STANCE_BEST_FRIENDS",
        [5] = "CAI_STRATEGIC_STANCE_BEST_FRIENDS"
    },

    -- Pair-scoped diplomacy can require thousands of engine calls in a fresh
    -- full-map campaign. Bound each callback and resume from the cache on later
    -- faction turns instead of freezing the load screen.
    diplomacy_pair_budget_first_tick = 80,
    diplomacy_pair_budget_human_turn = 80,
    diplomacy_pair_budget_ai_turn = 20,

    log_each_human_turn = true
}

local function clamp(value, low, high)
    if value < low then
        return low
    end
    if value > high then
        return high
    end
    return value
end

local function round(value)
    return math.floor(value + 0.5)
end

local function shallow_copy(source)
    local result = {}
    local key, value
    for key, value in pairs(source) do
        result[key] = value
    end
    return result
end

local function faction_key_is_safe(key)
    return type(key) == "string" and string.match(key, "^[%w_]+$") ~= nil
end

local function pair_key(a, b)
    if a < b then
        return a .. "|" .. b
    end
    return b .. "|" .. a
end

local logged_once = {}
local function write_log(message)
    local line = "[WR2 World Resistance] " .. tostring(message)
    if type(rawget(_G, "output")) == "function" then
        output(line)
    elseif type(rawget(_G, "out")) == "function" then
        out(line)
    elseif type(rawget(_G, "print")) == "function" then
        print(line)
    end
end

local function write_log_once(key, message)
    if not logged_once[key] then
        logged_once[key] = true
        write_log(message)
    end
end

WR.log = write_log

-- -------------------------------------------------------------------------
-- Pure calculations (kept engine-independent for simulation tests)
-- -------------------------------------------------------------------------

function WR.territory_pressure(share, curve)
    local points = curve or WR.config.territory_curve
    local bounded_share = clamp(tonumber(share) or 0, 0, 1)
    local i

    if bounded_share <= points[1].share then
        return points[1].pressure
    end

    for i = 2, #points do
        local left = points[i - 1]
        local right = points[i]
        if bounded_share <= right.share then
            local width = right.share - left.share
            if width <= 0 then
                return right.pressure
            end
            local fraction = (bounded_share - left.share) / width
            return left.pressure + ((right.pressure - left.pressure) * fraction)
        end
    end

    return points[#points].pressure
end

function WR.raw_pressure(inputs, permanent_floor, config)
    local cfg = config or WR.config
    local total_regions = math.max(tonumber(inputs.total_regions) or 0, 1)
    local human_regions = math.max(tonumber(inputs.human_regions) or 0, 0)
    local human_armies = math.max(tonumber(inputs.human_armies) or 0, 0)
    local human_treasury = math.max(tonumber(inputs.human_treasury) or 0, 0)
    local imperium = math.max(tonumber(inputs.human_imperium) or 0, 0)

    local share = clamp(human_regions / total_regions, 0, 1)
    local territory = WR.territory_pressure(share, cfg.territory_curve)
    local remainder = 100 - territory
    local army_signal = clamp(human_armies / cfg.army_signal_reference, 0, 1)
    local treasury_signal = clamp(human_treasury / cfg.treasury_signal_reference, 0, 1)

    local pressure = territory
        + (remainder * cfg.army_signal_weight_of_remainder * army_signal)
        + (remainder * cfg.treasury_signal_weight_of_remainder * treasury_signal)

    local floor = math.max(tonumber(permanent_floor) or 0, 0)
    if imperium >= cfg.final_imperium_level then
        floor = math.max(floor, cfg.final_imperium_pressure_floor)
    end

    pressure = math.max(pressure, floor)
    return clamp(round(pressure), 0, 100), floor, share
end

function WR.tier_for_pressure(pressure, config)
    local cfg = config or WR.config
    local result = 0
    local i
    for i = 1, #cfg.tiers do
        if pressure >= cfg.tiers[i].threshold then
            result = i - 1
        else
            break
        end
    end
    return result
end

function WR.advance_tier_state(state, desired_tier, config)
    local cfg = config or WR.config
    local next_state = shallow_copy(state)
    local maximum_tier = #cfg.tiers - 1
    local desired = clamp(tonumber(desired_tier) or 0, 0, maximum_tier)
    local current = clamp(tonumber(next_state.tier) or 0, 0, maximum_tier)

    if desired > current then
        next_state.tier = desired
        next_state.demotion_turns = 0
    elseif desired < current then
        next_state.demotion_turns = (tonumber(next_state.demotion_turns) or 0) + 1
        if next_state.demotion_turns >= cfg.demotion_turns_required then
            -- Drop only one band per hysteresis window. Existing AI assets
            -- also persist, preventing a sell/abandon exploit.
            next_state.tier = current - 1
            next_state.demotion_turns = 0
        else
            next_state.tier = current
        end
    else
        next_state.tier = current
        next_state.demotion_turns = 0
    end

    return next_state
end

function WR.target_armies(human, permanent_floor, config)
    local cfg = config or WR.config
    local human_armies = math.max(tonumber(human.armies) or 0, 0)
    if (tonumber(permanent_floor) or 0) >= cfg.final_imperium_pressure_floor then
        return math.max(cfg.final_imperium_min_armies, human_armies)
    end
    return human_armies
end

function WR.catchup_level(ai, human, permanent_floor, config)
    local cfg = config or WR.config
    local target_regions = math.max(tonumber(human.regions) or 0, 1)
    local target_armies = math.max(WR.target_armies(human, permanent_floor, cfg), 1)
    local target_treasury = math.max(tonumber(human.treasury) or 0, 5000)

    local region_fraction = clamp((tonumber(ai.regions) or 0) / target_regions, 0, 1)
    local army_fraction = clamp((tonumber(ai.armies) or 0) / target_armies, 0, 1)
    local treasury_fraction = clamp(math.max(tonumber(ai.treasury) or 0, 0) / target_treasury, 0, 1)
    local worst_shortfall = math.max(
        1 - region_fraction,
        1 - army_fraction,
        1 - treasury_fraction
    )

    if worst_shortfall >= 0.75 then
        return 3
    elseif worst_shortfall >= 0.50 then
        return 2
    elseif worst_shortfall >= 0.25 then
        return 1
    end
    return 0
end

function WR.treasury_target(ai, human, tier, catchup, permanent_floor, config)
    local cfg = config or WR.config
    local tier_index = clamp(tonumber(tier) or 0, 0, #cfg.tiers - 1)
    local catchup_index = clamp(tonumber(catchup) or 0, 0, 3)
    local multiplier = cfg.catchup_treasury_multipliers[catchup_index]
    local target_armies = WR.target_armies(human, permanent_floor, cfg)

    local tier_floor = cfg.tiers[tier_index + 1].treasury_floor * multiplier
    local human_parity = math.max(tonumber(human.treasury) or 0, 0) * multiplier
    local replacement_reserve = target_armies * cfg.replacement_reserve_per_target_army * multiplier

    return round(math.min(
        math.max(tier_floor, human_parity, replacement_reserve),
        cfg.max_treasury_target
    ))
end

function WR.build_ai_pairs(factions)
    local eligible = {}
    local seen = {}
    local result = {}
    local i, j

    for i = 1, #factions do
        local faction = factions[i]
        if faction.active and not faction.human and faction_key_is_safe(faction.key) and not seen[faction.key] then
            seen[faction.key] = true
            table.insert(eligible, faction)
        end
    end

    for i = 1, #eligible - 1 do
        for j = i + 1, #eligible do
            table.insert(result, {
                a = eligible[i],
                b = eligible[j],
                key = pair_key(eligible[i].key, eligible[j].key)
            })
        end
    end

    return result
end

-- -------------------------------------------------------------------------
-- Rome II adapter
-- -------------------------------------------------------------------------

local runtime = {
    initialized = false,
    listeners_registered = false,
    game = nil,
    state = {
        pressure = 0,
        permanent_floor = 0,
        tier = 0,
        demotion_turns = 0,
        diplomacy_peak = 0
    },
    base_bundle_by_faction = {},
    catchup_bundle_by_faction = {},
    diplomacy_mode_by_pair = {},
    last_treasury_turn = nil,
    last_stats = nil,
    last_summary = nil
}
WR.runtime = runtime

local SAVE_KEYS = {
    pressure = "wr2_wr_pressure_v1",
    permanent_floor = "wr2_wr_permanent_floor_v1",
    tier = "wr2_wr_tier_v1",
    demotion_turns = "wr2_wr_demotion_turns_v1",
    diplomacy_peak = "wr2_wr_diplomacy_peak_v1"
}

local function safe_read(label, callback, default)
    local ok, value = pcall(callback)
    if not ok then
        write_log_once("read:" .. label, "Read failed (skipping safely): " .. label .. " :: " .. tostring(value))
        return default
    end
    if value == nil then
        return default
    end
    return value
end

local function safe_engine_call(label, callback)
    local ok, result = pcall(callback)
    if not ok then
        write_log_once("call:" .. label, "Engine call failed (operation disabled for this target): " .. label .. " :: " .. tostring(result))
        return false
    end
    return true
end

local function count_forces(faction)
    local forces = safe_read("military_force_list", function()
        return faction:military_force_list()
    end, nil)
    if forces == nil then
        return 0, 0, 0
    end

    local total = safe_read("military_force_list:num_items", function()
        return forces:num_items()
    end, 0)
    local armies = 0
    local navies = 0
    local i
    for i = 0, total - 1 do
        local force = safe_read("military_force_list:item_at", function()
            return forces:item_at(i)
        end, nil)
        if force ~= nil then
            if safe_read("military_force:is_army", function()
                return force:is_army()
            end, false) then
                armies = armies + 1
            elseif safe_read("military_force:is_navy", function()
                return force:is_navy()
            end, false) then
                navies = navies + 1
            end
        end
    end
    return total, armies, navies
end

local function inspect_faction(faction)
    local key = safe_read("faction:name", function()
        return faction:name()
    end, "")
    if not faction_key_is_safe(key) then
        write_log_once("bad-faction-key:" .. tostring(key), "Ignoring faction with invalid/empty key")
        return nil
    end

    local human = safe_read("faction:is_human:" .. key, function()
        return faction:is_human()
    end, false)
    local region_list = safe_read("faction:region_list:" .. key, function()
        return faction:region_list()
    end, nil)
    local regions = 0
    if region_list ~= nil then
        regions = safe_read("faction:region_count:" .. key, function()
            return region_list:num_items()
        end, 0)
    end
    local forces, armies, navies = count_forces(faction)

    return {
        interface = faction,
        key = key,
        human = human,
        regions = math.max(tonumber(regions) or 0, 0),
        forces = math.max(tonumber(forces) or 0, 0),
        armies = math.max(tonumber(armies) or 0, 0),
        navies = math.max(tonumber(navies) or 0, 0),
        treasury = safe_read("faction:treasury:" .. key, function()
            return faction:treasury()
        end, 0),
        imperium = safe_read("faction:imperium_level:" .. key, function()
            return faction:imperium_level()
        end, 0),

        -- Rome II exposes no is_dead() on FACTION_SCRIPT_INTERFACE. A faction
        -- with a settlement or military force is operational; zero/zero
        -- entries are dormant/dead database factions and are not mutated.
        active = regions > 0 or forces > 0
    }
end

local function collect_world_stats()
    if runtime.game == nil then
        return nil
    end
    local model = safe_read("game:model", function()
        return runtime.game:model()
    end, nil)
    if model == nil then
        return nil
    end
    local world = safe_read("model:world", function()
        return model:world()
    end, nil)
    if world == nil then
        return nil
    end
    local faction_list = safe_read("world:faction_list", function()
        return world:faction_list()
    end, nil)
    if faction_list == nil then
        return nil
    end

    local stats = {
        model = model,
        world = world,
        campaign = safe_read("model:campaign_name", function()
            return model:campaign_name()
        end, ""),
        factions = {},
        humans = {},
        ais = {},
        human = {
            regions = 0,
            armies = 0,
            treasury = 0,
            imperium = 0
        },
        total_regions = 1,
        turn = safe_read("model:turn_number", function()
            return model:turn_number()
        end, -1)
    }

    local region_manager = safe_read("world:region_manager", function()
        return world:region_manager()
    end, nil)
    if region_manager ~= nil then
        local region_list = safe_read("world:region_list", function()
            return region_manager:region_list()
        end, nil)
        if region_list ~= nil then
            stats.total_regions = math.max(safe_read("world:region_count", function()
                return region_list:num_items()
            end, 1), 1)
        end
    end

    local count = safe_read("faction_list:num_items", function()
        return faction_list:num_items()
    end, 0)
    local i
    for i = 0, count - 1 do
        local faction = safe_read("faction_list:item_at", function()
            return faction_list:item_at(i)
        end, nil)
        if faction ~= nil then
            local metric = inspect_faction(faction)
            if metric ~= nil then
                table.insert(stats.factions, metric)
                if metric.human then
                    table.insert(stats.humans, metric)
                    if metric.active then
                        stats.human.regions = stats.human.regions + metric.regions
                        -- Multi-human is unsupported, but max individual
                        -- military/treasury power is safer than summing it.
                        stats.human.armies = math.max(stats.human.armies, metric.armies)
                        stats.human.treasury = math.max(stats.human.treasury, metric.treasury)
                        stats.human.imperium = math.max(stats.human.imperium, metric.imperium)
                    end
                elseif metric.active then
                    table.insert(stats.ais, metric)
                end
            end
        end
    end

    if #stats.humans > 1 then
        write_log_once("multiplayer", "Multiple human factions detected. Scaling is safe, but multiplayer balance is unsupported; territory is combined and parity uses the strongest human.")
    end

    return stats
end


local function all_base_bundles()
    local result = {}
    local i
    for i = 1, #WR.config.tiers do
        table.insert(result, WR.config.tiers[i].bundle)
    end
    return result
end


local function all_catchup_bundles()
    local result = {}
    local i
    for i = 1, 3 do
        table.insert(result, WR.config.catchup_bundles[i])
    end
    return result
end


local BASE_BUNDLES = all_base_bundles()
local CATCHUP_BUNDLES = all_catchup_bundles()

local function remove_bundle_family(faction_key, bundles)
    local all_removed = true
    local i
    for i = 1, #bundles do
        local bundle = bundles[i]
        local removed = safe_engine_call("remove_bundle:" .. faction_key .. ":" .. bundle, function()
            runtime.game:remove_effect_bundle(bundle, faction_key)
        end)
        if not removed then
            all_removed = false
        end
    end
    return all_removed
end


local function apply_bundle_exclusive(faction_key, bundle, family, cache)
    -- false is an intentional "known to have no bundle" sentinel. nil means
    -- this Lua session has not scrubbed the family yet (common after reload).
    local desired = bundle
    if desired == nil then
        desired = false
    end
    if cache[faction_key] ~= nil and cache[faction_key] == desired then
        return false
    end

    local family_removed = remove_bundle_family(faction_key, family)
    if not family_removed then
        -- Do not stack a new tier on top of an old one when cleanup failed.
        cache[faction_key] = nil
        return false
    end
    if bundle ~= nil then
        local applied = safe_engine_call("apply_bundle:" .. faction_key .. ":" .. bundle, function()
            runtime.game:apply_effect_bundle(bundle, faction_key, -1)
        end)
        if applied then
            cache[faction_key] = bundle
        else
            cache[faction_key] = nil
        end
    else
        cache[faction_key] = false
    end
    return true
end


local function scrub_human_bundles(stats)
    local i
    for i = 1, #stats.humans do
        local key = stats.humans[i].key
        remove_bundle_family(key, BASE_BUNDLES)
        remove_bundle_family(key, CATCHUP_BUNDLES)
        runtime.base_bundle_by_faction[key] = nil
        runtime.catchup_bundle_by_faction[key] = nil
    end
end


local function cleanup_inactive_cached_factions(active_keys)
    local cached_keys = {}
    local key
    for key, _ in pairs(runtime.base_bundle_by_faction) do
        cached_keys[key] = true
    end
    for key, _ in pairs(runtime.catchup_bundle_by_faction) do
        cached_keys[key] = true
    end
    for key, _ in pairs(cached_keys) do
        if not active_keys[key] then
            remove_bundle_family(key, BASE_BUNDLES)
            remove_bundle_family(key, CATCHUP_BUNDLES)
            runtime.base_bundle_by_faction[key] = nil
            runtime.catchup_bundle_by_faction[key] = nil
        end
    end
end


local function grant_treasury_to_floor(ai, human, tier, catchup, permanent_floor)
    local current = math.max(tonumber(ai.treasury) or 0, 0)
    local target = WR.treasury_target(ai, human, tier, catchup, permanent_floor)
    if current >= target then
        return 0
    end

    local amount = math.min(target - current, WR.config.max_treasury_grant_per_update)
    amount = math.max(math.floor(amount), 0)
    if amount == 0 then
        return 0
    end
    local granted = safe_engine_call("treasury_mod:" .. ai.key, function()
        runtime.game:treasury_mod(ai.key, amount)
    end)
    if granted then
        return amount
    end
    return 0
end


local function reconcile_faction(ai, stats, grant_treasury)
    if ai.human or not ai.active then
        return 0, 0
    end

    local tier = runtime.state.tier
    local catchup = WR.catchup_level(ai, stats.human, runtime.state.permanent_floor)
    local desired_base = WR.config.tiers[tier + 1].bundle
    local desired_catchup = WR.config.catchup_bundles[catchup]
    local changes = 0

    if apply_bundle_exclusive(ai.key, desired_base, BASE_BUNDLES, runtime.base_bundle_by_faction) then
        changes = changes + 1
    end
    if apply_bundle_exclusive(ai.key, desired_catchup, CATCHUP_BUNDLES, runtime.catchup_bundle_by_faction) then
        changes = changes + 1
    end

    local grant = 0
    if grant_treasury then
        grant = grant_treasury_to_floor(ai, stats.human, tier, catchup, runtime.state.permanent_floor)
    end
    return changes, grant
end


local function assert_ai_pair(a, b)
    if a == nil or b == nil then
        return false
    end
    if a.human or b.human then
        write_log_once("human-diplomacy-block", "INVARIANT: blocked an attempted World Resistance diplomatic command involving a human faction")
        return false
    end
    if not a.active or not b.active or a.key == b.key then
        return false
    end
    return faction_key_is_safe(a.key) and faction_key_is_safe(b.key)
end


local function force_diplomacy_both(a, b, deal_type, can_offer, can_accept)
    if not assert_ai_pair(a, b) then
        return false
    end
    local first = safe_engine_call("force_diplomacy:" .. a.key .. ":" .. b.key .. ":" .. deal_type, function()
        runtime.game:force_diplomacy(a.key, b.key, deal_type, can_offer, can_accept)
    end)
    local second = safe_engine_call("force_diplomacy:" .. b.key .. ":" .. a.key .. ":" .. deal_type, function()
        runtime.game:force_diplomacy(b.key, a.key, deal_type, can_offer, can_accept)
    end)
    return first and second
end


local function promote_strategic_stance_both(a, b, mode)
    if not assert_ai_pair(a, b) then
        return false
    end
    local stance = WR.config.strategic_stances[mode]
    if stance == nil then
        return false
    end
    local first = safe_engine_call("promote_stance:" .. a.key .. ":" .. b.key, function()
        runtime.game:cai_strategic_stance_manager_promote_specified_stance_towards_target_faction(
            a.key,
            b.key,
            stance
        )
    end)
    local second = safe_engine_call("promote_stance:" .. b.key .. ":" .. a.key, function()
        runtime.game:cai_strategic_stance_manager_promote_specified_stance_towards_target_faction(
            b.key,
            a.key,
            stance
        )
    end)
    return first and second
end


local function faction_has_any_war(metric)
    return safe_read("faction:at_war:" .. metric.key, function()
        -- Rome II exposes only this no-argument, any-war query.
        return metric.interface:at_war()
    end, false)
end


local function force_ai_peace(a, b)
    if not assert_ai_pair(a, b) then
        return false
    end
    -- There is no audited pair-specific war query in Rome II. Use the broad
    -- query only as a cheap prefilter; force_make_peace safely no-ops when
    -- this particular pair is already at peace.
    if not faction_has_any_war(a) and not faction_has_any_war(b) then
        return false
    end
    return safe_engine_call("force_make_peace:" .. a.key .. ":" .. b.key, function()
        runtime.game:force_make_peace(a.key, b.key)
    end)
end


local function apply_diplomacy_mode(pair, mode)
    local a = pair.a
    local b = pair.b
    if not assert_ai_pair(a, b) then
        return 0, 0
    end

    local calls = 0
    local wars_ended = 0

    if mode >= 1 then
        promote_strategic_stance_both(a, b, mode)
        force_diplomacy_both(a, b, "trade agreement", true, true)
        calls = calls + 4
    end
    if mode >= 2 then
        force_diplomacy_both(a, b, "peace", true, true)
        force_diplomacy_both(a, b, "non aggression pact", true, true)
        calls = calls + 4
    end
    if mode >= 3 then
        force_diplomacy_both(a, b, "defensive alliance", true, true)
        force_diplomacy_both(a, b, "alliance", true, true)
        force_diplomacy_both(a, b, "break trade", false, false)
        force_diplomacy_both(a, b, "break alliance", false, false)
        force_diplomacy_both(a, b, "break non aggression pact", false, false)
        force_diplomacy_both(a, b, "break defensive alliance", false, false)
        calls = calls + 12
    end
    if mode >= WR.config.hard_ai_peace_tier then
        force_diplomacy_both(a, b, "war", false, false)
        force_diplomacy_both(a, b, "join war", false, false)
        calls = calls + 4
        if force_ai_peace(a, b) then
            wars_ended = wars_ended + 1
        end
    end
    if mode >= WR.config.force_trade_tier then
        safe_engine_call("force_make_trade_agreement:" .. a.key .. ":" .. b.key, function()
            runtime.game:force_make_trade_agreement(a.key, b.key)
        end)
        calls = calls + 1
    end

    runtime.diplomacy_mode_by_pair[pair.key] = mode
    return calls, wars_ended
end


local function reconcile_diplomacy(stats, pair_budget)
    local mode = runtime.state.diplomacy_peak
    if mode <= 0 then
        return 0, 0, 0
    end

    local budget = math.max(tonumber(pair_budget) or WR.config.diplomacy_pair_budget_ai_turn, 0)
    local pairs = WR.build_ai_pairs(stats.factions)
    local changed_pairs = 0
    local calls = 0
    local wars_ended = 0
    local i
    for i = 1, #pairs do
        local pair = pairs[i]
        if runtime.diplomacy_mode_by_pair[pair.key] ~= mode then
            if changed_pairs >= budget then
                break
            end
            local pair_calls, pair_wars = apply_diplomacy_mode(pair, mode)
            changed_pairs = changed_pairs + 1
            calls = calls + pair_calls
            wars_ended = wars_ended + pair_wars
        end
    end
    return changed_pairs, calls, wars_ended
end


local function enforce_peace_for_faction(metric, stats)
    if runtime.state.diplomacy_peak < WR.config.hard_ai_peace_tier or metric == nil or metric.human then
        return 0
    end

    local ended = 0
    local i
    for i = 1, #stats.ais do
        local other = stats.ais[i]
        if other.key ~= metric.key and force_ai_peace(metric, other) then
            ended = ended + 1
        end
    end
    return ended
end


local function update_pressure_state(stats)
    local raw, floor, share = WR.raw_pressure({
        total_regions = stats.total_regions,
        human_regions = stats.human.regions,
        human_armies = stats.human.armies,
        human_treasury = stats.human.treasury,
        human_imperium = stats.human.imperium
    }, runtime.state.permanent_floor)

    runtime.state.pressure = raw
    runtime.state.permanent_floor = floor
    local desired_tier = WR.tier_for_pressure(raw)
    runtime.state = WR.advance_tier_state(runtime.state, desired_tier)
    runtime.state.pressure = raw
    runtime.state.permanent_floor = floor
    runtime.state.diplomacy_peak = math.max(
        tonumber(runtime.state.diplomacy_peak) or 0,
        runtime.state.tier
    )
    return share, desired_tier
end


local function reconcile_world(options)
    local opts = options or {}
    local stats = collect_world_stats()
    if stats == nil then
        write_log_once("no-world", "World interface unavailable; director remains inert")
        return false
    end
    if stats.campaign ~= WR.config.supported_campaign then
        write_log_once(
            "unsupported-campaign:" .. tostring(stats.campaign),
            "Unsupported campaign " .. tostring(stats.campaign)
                .. "; this release is intentionally limited to main_rome"
        )
        return false
    end
    if #stats.humans == 0 then
        write_log_once("no-human", "No human faction detected; director remains inert")
        return false
    end

    local share, desired_tier = update_pressure_state(stats)
    local active_keys = {}
    local bundle_changes = 0
    local treasury_granted = 0
    local i

    -- Human isolation is reasserted at every full update. This is a small,
    -- deliberate cost that also repairs saves previously touched by a buggy
    -- build of this mod.
    scrub_human_bundles(stats)

    for i = 1, #stats.ais do
        local ai = stats.ais[i]
        active_keys[ai.key] = true
        local changed, grant = reconcile_faction(ai, stats, opts.grant_treasury == true)
        bundle_changes = bundle_changes + changed
        treasury_granted = treasury_granted + grant
    end
    cleanup_inactive_cached_factions(active_keys)

    local diplomatic_pairs, diplomatic_calls, wars_ended = reconcile_diplomacy(
        stats,
        opts.diplomacy_pair_budget
    )

    runtime.last_stats = stats
    runtime.last_summary = {
        turn = stats.turn,
        pressure = runtime.state.pressure,
        tier = runtime.state.tier,
        desired_tier = desired_tier,
        diplomacy_peak = runtime.state.diplomacy_peak,
        territory_share = share,
        ai_count = #stats.ais,
        bundle_changes = bundle_changes,
        treasury_granted = treasury_granted,
        diplomatic_pairs = diplomatic_pairs,
        diplomatic_calls = diplomatic_calls,
        wars_ended = wars_ended,
        target_armies = WR.target_armies(stats.human, runtime.state.permanent_floor)
    }

    if opts.log_summary or WR.config.log_each_human_turn then
        write_log(
            "turn=" .. tostring(stats.turn)
            .. " pressure=" .. tostring(runtime.state.pressure)
            .. " tier=" .. tostring(runtime.state.tier)
            .. " map=" .. tostring(round(share * 100)) .. "%"
            .. " AI=" .. tostring(#stats.ais)
            .. " target_armies=" .. tostring(runtime.last_summary.target_armies)
            .. " bundle_changes=" .. tostring(bundle_changes)
            .. " treasury_granted=" .. tostring(treasury_granted)
            .. " diplomacy_pairs=" .. tostring(diplomatic_pairs)
            .. " wars_ended=" .. tostring(wars_ended)
        )
    end
    return true
end


local function metric_for_key(stats, key)
    if stats == nil then
        return nil
    end
    local i
    for i = 1, #stats.factions do
        if stats.factions[i].key == key then
            return stats.factions[i]
        end
    end
    return nil
end


local function on_loading_game(context)
    if runtime.game == nil then
        return
    end
    -- LoadingGame is read-only by design. No bundle, treasury, diplomacy, or
    -- other world mutation belongs here.
    runtime.state.pressure = safe_read("load:pressure", function()
        return runtime.game:load_named_value(SAVE_KEYS.pressure, 0, context)
    end, 0)
    runtime.state.permanent_floor = safe_read("load:permanent_floor", function()
        return runtime.game:load_named_value(SAVE_KEYS.permanent_floor, 0, context)
    end, 0)
    runtime.state.tier = safe_read("load:tier", function()
        return runtime.game:load_named_value(SAVE_KEYS.tier, 0, context)
    end, 0)
    runtime.state.demotion_turns = safe_read("load:demotion_turns", function()
        return runtime.game:load_named_value(SAVE_KEYS.demotion_turns, 0, context)
    end, 0)
    runtime.state.diplomacy_peak = safe_read("load:diplomacy_peak", function()
        return runtime.game:load_named_value(SAVE_KEYS.diplomacy_peak, 0, context)
    end, 0)
end


local function on_saving_game(context)
    if runtime.game == nil then
        return
    end
    safe_engine_call("save:pressure", function()
        runtime.game:save_named_value(SAVE_KEYS.pressure, runtime.state.pressure, context)
    end)
    safe_engine_call("save:permanent_floor", function()
        runtime.game:save_named_value(SAVE_KEYS.permanent_floor, runtime.state.permanent_floor, context)
    end)
    safe_engine_call("save:tier", function()
        runtime.game:save_named_value(SAVE_KEYS.tier, runtime.state.tier, context)
    end)
    safe_engine_call("save:demotion_turns", function()
        runtime.game:save_named_value(SAVE_KEYS.demotion_turns, runtime.state.demotion_turns, context)
    end)
    safe_engine_call("save:diplomacy_peak", function()
        runtime.game:save_named_value(SAVE_KEYS.diplomacy_peak, runtime.state.diplomacy_peak, context)
    end)
end


local function on_first_tick_after_world_created(_context)
    if runtime.initialized then
        write_log_once("duplicate-first-tick", "Duplicate FirstTickAfterWorldCreated ignored in the same campaign Lua session")
        return
    end
    runtime.initialized = true
    write_log("initializing version " .. tostring(VERSION))
    reconcile_world({
        grant_treasury = true,
        diplomacy_pair_budget = WR.config.diplomacy_pair_budget_first_tick,
        log_summary = true
    })
end


local function on_faction_turn_start(context)
    if not runtime.initialized then
        return
    end
    local faction = safe_read("event:FactionTurnStart:faction", function()
        return context:faction()
    end, nil)
    if faction == nil then
        return
    end
    local metric = inspect_faction(faction)
    if metric == nil then
        return
    end

    if metric.human then
        local turn = safe_read("event:FactionTurnStart:turn", function()
            return runtime.game:model():turn_number()
        end, -1)
        local grant = runtime.last_treasury_turn ~= turn
        if grant then
            runtime.last_treasury_turn = turn
        end
        reconcile_world({
            grant_treasury = grant,
            diplomacy_pair_budget = WR.config.diplomacy_pair_budget_human_turn,
            log_summary = true
        })
        return
    end

    if metric.active then
        local stats = collect_world_stats()
        if stats ~= nil
            and stats.campaign == WR.config.supported_campaign
            and #stats.humans > 0 then
            reconcile_faction(metric, stats, false)
            enforce_peace_for_faction(metric, stats)
            reconcile_diplomacy(stats, WR.config.diplomacy_pair_budget_ai_turn)
            runtime.last_stats = stats
        end
    end
end


local function on_faction_declares_war(context)
    if not runtime.initialized or runtime.state.diplomacy_peak < WR.config.hard_ai_peace_tier then
        return
    end
    -- Rome II exposes the declaring Character but not the target faction.
    -- Restrict enforcement to that AI instead of doing O(n^2) work inside the
    -- declaration callback. The human guard remains explicit.
    local character = safe_read("event:FactionLeaderDeclaresWar:character", function()
        return context:character()
    end, nil)
    if character == nil then
        return
    end
    local faction = safe_read("event:FactionLeaderDeclaresWar:faction", function()
        return character:faction()
    end, nil)
    if faction == nil then
        return
    end
    local metric = inspect_faction(faction)
    if metric == nil or metric.human or not metric.active then
        return
    end
    local stats = collect_world_stats()
    if stats ~= nil
        and stats.campaign == WR.config.supported_campaign
        and #stats.humans > 0 then
        enforce_peace_for_faction(metric, stats)
    end
end


function WR.debug_snapshot()
    if runtime.last_summary == nil then
        return {
            initialized = runtime.initialized,
            pressure = runtime.state.pressure,
            tier = runtime.state.tier,
            diplomacy_peak = runtime.state.diplomacy_peak
        }
    end
    local snapshot = shallow_copy(runtime.last_summary)
    snapshot.initialized = runtime.initialized
    return snapshot
end


local function register_listener(event_name, callback)
    local event_table = rawget(_G, "events")
    if type(event_table) ~= "table" or type(event_table[event_name]) ~= "table" then
        write_log_once("missing-event:" .. event_name, "Event unavailable: " .. event_name)
        return false
    end
    table.insert(event_table[event_name], callback)
    return true
end


local function game_interface_from(candidate)
    local candidate_type = type(candidate)
    if candidate_type ~= "table" and candidate_type ~= "userdata" then
        return nil
    end
    return safe_read("scripting.game_interface", function()
        return candidate.game_interface
    end, nil)
end


local function initialize_engine_adapter()
    local scripting_api = rawget(_G, "scripting")
    local game_interface = game_interface_from(scripting_api)

    if game_interface == nil and type(package.loaded) == "table" then
        scripting_api = package.loaded["lua_scripts.EpisodicScripting"]
            or package.loaded["lua_scripts.episodicscripting"]
        game_interface = game_interface_from(scripting_api)
    end

    if game_interface == nil then
        local ok, loaded = pcall(require, "lua_scripts.EpisodicScripting")
        if ok then
            scripting_api = rawget(_G, "scripting") or loaded
            game_interface = game_interface_from(scripting_api)
        end
    end

    if game_interface == nil then
        write_log_once("no-engine", "Rome II scripting interface not detected; pure calculation API loaded only")
        return false
    end
    runtime.game = game_interface

    if runtime.listeners_registered then
        return true
    end
    runtime.listeners_registered = true

    register_listener("LoadingGame", on_loading_game)
    register_listener("SavingGame", on_saving_game)
    register_listener("FirstTickAfterWorldCreated", on_first_tick_after_world_created)
    register_listener("FactionTurnStart", on_faction_turn_start)
    register_listener("FactionLeaderDeclaresWar", on_faction_declares_war)
    return true
end


WR.reconcile_world = reconcile_world
WR.initialize_engine_adapter = initialize_engine_adapter

initialize_engine_adapter()

return WR
