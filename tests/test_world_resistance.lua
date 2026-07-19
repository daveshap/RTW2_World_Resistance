local script_path = "../pack_root/script/campaign/wr2/wr2_world_resistance.lua"
local WR = dofile(script_path)

local tests_run = 0

local function fail(message)
    error(message, 2)
end

local function assert_equal(actual, expected, label)
    tests_run = tests_run + 1
    if actual ~= expected then
        fail((label or "assert_equal") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function assert_near(actual, expected, tolerance, label)
    tests_run = tests_run + 1
    if math.abs(actual - expected) > tolerance then
        fail((label or "assert_near") .. ": expected " .. tostring(expected) .. " +/- " .. tostring(tolerance) .. ", got " .. tostring(actual))
    end
end

local function assert_true(value, label)
    tests_run = tests_run + 1
    if not value then
        fail(label or "assert_true failed")
    end
end

-- Territory curve is the primary, continuous driver.
assert_near(WR.territory_pressure(0.00), 0, 0.001, "zero share")
assert_near(WR.territory_pressure(0.10), 20, 0.001, "ten percent")
assert_near(WR.territory_pressure(0.20), 40, 0.001, "twenty percent")
assert_near(WR.territory_pressure(0.32), 65, 0.001, "final-imperium pivot")
assert_near(WR.territory_pressure(0.50), 85, 0.001, "half map")
assert_near(WR.territory_pressure(0.70), 100, 0.001, "maximum resistance")
assert_near(WR.territory_pressure(0.15), 30, 0.001, "interpolation")

local pressure_before, floor_before = WR.raw_pressure({
    total_regions = 173,
    human_regions = 10,
    human_armies = 2,
    human_treasury = 5000,
    human_imperium = 3
}, 0)
assert_true(pressure_before < 20, "small empire remains below the first main threshold")
assert_equal(floor_before, 0, "no permanent floor before final Imperium")

local pressure_pivot, floor_pivot = WR.raw_pressure({
    total_regions = 173,
    human_regions = 55,
    human_armies = 16,
    human_treasury = 100000,
    human_imperium = 7
}, 0)
assert_true(pressure_pivot >= 65, "final Imperium activates the endgame floor")
assert_equal(floor_pivot, 65, "final Imperium floor persists")

local pressure_after = WR.raw_pressure({
    total_regions = 173,
    human_regions = 100,
    human_armies = 16,
    human_treasury = 100000,
    human_imperium = 7
}, floor_pivot)
assert_true(pressure_after > pressure_pivot, "territory continues scaling after final Imperium")

local pressure_max = WR.raw_pressure({
    total_regions = 173,
    human_regions = 122,
    human_armies = 20,
    human_treasury = 200000,
    human_imperium = 7
}, floor_pivot)
assert_equal(pressure_max, 100, "seventy percent map reaches maximum")

-- Tier promotion is immediate; demotion is delayed and one band at a time.
local state = { tier = 0, demotion_turns = 0 }
state = WR.advance_tier_state(state, 4)
assert_equal(state.tier, 4, "immediate promotion")
local i
for i = 1, 9 do
    state = WR.advance_tier_state(state, 0)
end
assert_equal(state.tier, 4, "nine-turn demotion delay")
state = WR.advance_tier_state(state, 0)
assert_equal(state.tier, 3, "one tier demotion on tenth turn")

-- Final Imperium target is at least 16 and continues following the human.
assert_equal(WR.target_armies({ armies = 8 }, 0), 8, "pre-pivot army target")
assert_equal(WR.target_armies({ armies = 8 }, 65), 16, "pivot minimum army target")
assert_equal(WR.target_armies({ armies = 21 }, 65), 21, "post-pivot army target continues")

-- Each AI's mobilization goal remains proportional to its settlement base,
-- while the global fame table still permits a legal ceiling of sixteen.
local mobilized_human = { armies = 16 }
assert_equal(WR.ai_army_goal({ regions = 1 }, mobilized_human, 65), 4, "one region supports four-army goal")
assert_equal(WR.ai_army_goal({ regions = 3 }, mobilized_human, 65), 12, "three regions support twelve-army goal")
assert_equal(WR.ai_army_goal({ regions = 9 }, mobilized_human, 65), 16, "regional goal is capped at sixteen")
assert_equal(WR.ai_army_goal({ regions = 0 }, mobilized_human, 65), 0, "landless faction has no recruitment goal")

-- Weak factions receive the strongest catch-up regardless of relationship.
local human = { regions = 55, armies = 16, treasury = 100000 }
assert_equal(WR.catchup_level({ regions = 1, armies = 1, treasury = 1000 }, human, 65), 3, "one-region faction catch-up")
assert_equal(WR.catchup_level({ regions = 55, armies = 16, treasury = 100000 }, human, 65), 0, "parity faction catch-up")
local treasury_target = WR.treasury_target({ regions = 1 }, human, 3, 3, 65)
assert_true(treasury_target >= 250000, "weak AI keeps catch-up treasury parity")
assert_true(treasury_target < 320000, "one-region reserve is not priced as sixteen field armies")

-- Pair planner excludes humans, dormant factions, duplicates, and self-pairs.
-- Relationship fields are deliberately present but ignored.
local pairs = WR.build_ai_pairs({
    { key = "rom_rome", human = true, active = true, relation = "enemy" },
    { key = "rom_carthage", human = false, active = true, relation = "ally" },
    { key = "rom_athens", human = false, active = true, relation = "neutral" },
    { key = "rom_sparta", human = false, active = true, relation = "enemy" },
    { key = "rom_dead", human = false, active = false, relation = "neutral" },
    { key = "rom_sparta", human = false, active = true, relation = "duplicate" }
})
assert_equal(#pairs, 3, "three choose two AI-only pairs")
for i = 1, #pairs do
    assert_true(not pairs[i].a.human and not pairs[i].b.human, "pair is AI-only")
    assert_true(pairs[i].a.key ~= "rom_rome" and pairs[i].b.key ~= "rom_rome", "human key never targeted")
    assert_true(pairs[i].a.active and pairs[i].b.active, "pair contains only active factions")
end

-- Structured telemetry has a fixed prefix/order and sanitizes delimiters so a
-- faction or engine error cannot forge an extra field or log line.
local telemetry = WR.telemetry_line("STATE", {
    { "unsafe", "alpha|beta\ngamma\tdelta" },
    { "number", 42 }
})
assert_true(
    string.find(telemetry, "WR2|schema=1|event=STATE|release=0.1.6-beta|director=8", 1, true) == 1,
    "telemetry prefix is versioned and deterministic"
)
assert_true(
    string.find(telemetry, "|unsafe=alpha beta gamma delta|number=42", 1, true) ~= nil,
    "telemetry values are delimiter-safe"
)

print("World Resistance simulation: " .. tostring(tests_run) .. " assertions passed")
