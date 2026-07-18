![World Resistance Banner](banner.jpg)


# World Resistance for Total War: ROME II

World Resistance is a standalone anti-steamroll campaign mod. As the human empire grows, **every active AI faction** receives stronger economic, military, research, stability, and diplomatic support. War status, alliance status, client status, diplomatic contact, culture, and distance do not affect eligibility.

The intended end state is deliberately unfair: once the human is a hegemon, the rest of the world can build, recruit, replenish, research, and finance near-peer armies at extreme speed, while AI factions increasingly cooperate with one another.

> **Release status: pre-PANTHEON beta.** This build targets the current public Grand Campaign (`main_rome`) as researched on 2026-07-18. It has not been cold-booted in a live Rome II installation in this environment. Read [Compatibility and testing](docs/COMPATIBILITY_AND_TESTING.md) before using it in a campaign you care about.

## What it does

- Scales all living, active non-human factions from turn one. There is no frontline, enemy, ally, client, contact, or distance exception.
- Uses the human share of world territory as the primary pressure signal. Human army count and treasury are smaller secondary signals.
- Establishes a permanent endgame pressure floor when the human reaches final vanilla Imperium, then keeps scaling with territory until maximum pressure at roughly 70% of the map.
- Gives each AI exactly one global pressure bundle and, when it is behind, one additional catch-up bundle based on its worst shortfall in regions, armies, or treasury.
- Raises AI treasuries toward human-relative and replacement-reserve floors. The script only adds funds; it never removes them.
- Gives Grand Campaign AI access to the final 16-army cap from the start while retaining the human's normal Imperium thresholds and normal 3-to-16 army progression. It does not spawn armies.
- Makes strategic behavior progressively more cooperative **only between AI factions**. At high pressure it protects trade and alliances, blocks ordinary AI-to-AI war/join-war offers, and repeatedly forces AI-to-AI wars back to peace.
- Never makes the AI friendlier to the human and never applies a World Resistance bundle or diplomatic command to a human faction.

At maximum pressure, a severely behind AI receives the Tier 100 package plus Catch-up 3:

| System | Maximum contribution from this mod |
|---|---:|
| Construction time | -7 turns |
| Construction, recruitment, normal upkeep, and mercenary costs | -90% each |
| Building GDP / tax | +600% / +150% |
| Land / naval recruitment capacity | +12 / +9 |
| Replenishment | +50 percentage points |
| Recruit rank / armour / morale | +9 / +10 / +10 |
| Melee damage / experience gain | +10% / +15% |
| Research | +600% and +375 flat points |
| Public order / food / growth | +400 / +5000 / +35 |

This does not guarantee that the campaign AI will make perfect decisions. It gives every AI the legal capacity, money, throughput, resilience, and diplomatic protection needed to remain dangerous.

## Installation

1. Close Rome II.
2. Copy `wr2_world_resistance.pack` from `dist` into the game's `data` directory, normally:

   ```text
   ...\Steam\steamapps\common\Total War Rome II\data
   ```

3. Open the Rome II launcher, enable **only** `wr2_world_resistance.pack` for the first test, and start a new Grand Campaign.
4. Keep the original release archive so you can restore the exact build used by a save.

No other gameplay or framework mod is required. “Standalone” means all World Resistance mechanics are in this one pack; it does not mean the pack can safely coexist with every overhaul. In particular, do not enable another pack that replaces `lua_scripts/all_scripted.lua`, and avoid army-cap or `fame_levels` mods. See the [compatibility matrix](docs/COMPATIBILITY_AND_TESTING.md#compatibility-matrix).

## Recommended first run

Use a disposable new Grand Campaign on Normal campaign difficulty with no other mods. Confirm that the campaign reaches the first turn, survives an end turn, saves and loads, and returns from a battle. Then run several AI turns before adding any other mods.

Do not add or remove this beta in the middle of an important campaign. Removing an army-cap override while an AI owns more forces than its restored cap has not been validated.

## Design summary

The pressure curve has six bands: 0, 20, 40, 65, 85, and 100. Territory is continuously interpolated between those points rather than waiting for a single Imperium threshold. Tier promotion is immediate; economic tier demotion is slow. Anti-hegemonic diplomacy is a saved high-water mark and never becomes less cooperative later in the campaign.

Full mechanics and numbers are in [Design](docs/DESIGN.md).

## Important limits

- This build is only for the pre-PANTHEON Grand Campaign (`main_rome`). It deliberately becomes inert in other campaigns.
- The forthcoming PANTHEON/JUPITER branch changes Imperium and army-cap assumptions and needs a separate adapter. This pack intentionally encodes the backward-compatible `fame_levels` v4 Grand Campaign row shape found in decoded stable Rome II packs. The RPFM schema also contains later table layouts, but their presence predates PANTHEON and is not evidence that they describe the forthcoming update.
- The ordinary AI-to-AI war path is disabled at high pressure, but a hard-coded campaign incident could bypass normal diplomacy. The script listens for declarations and forces AI peace again; only live soak testing can prove complete coverage.
- The API can enable and protect alliances, but there is no audited Rome II command that instantly creates an alliance. Universal alliance formation is encouraged, not guaranteed.
- `-90%` reducers can stack with campaign difficulty, technologies, traits, or other mods. Normal campaign difficulty is the initial balance target; higher difficulties require a live economy test.
- A protected Lua call can contain a Lua error, but it cannot catch a native engine crash.

## Project layout

| Path | Purpose |
|---|---|
| `dist/` | Installable PFH4 mod pack |
| `pack_root/lua_scripts/` | Vanilla-preserving loader and campaign director |
| `config/bundle_matrix.json` | Machine-readable balance contract |
| `db_src/` | Source TSVs used to construct the pack |
| `tests/` | Pure calculation, mocked engine, and PFH4 tests |
| `tools/` | Deterministic pack/build validation utilities |
| `validation/` | Machine-readable build report, RPFM round trips, and test summary |
| `docs/` | Design, compatibility, safety, and source notes |

## Documentation

- [Design](docs/DESIGN.md)
- [Compatibility and testing](docs/COMPATIBILITY_AND_TESTING.md)
- [Crash-safety notes](docs/CRASH_SAFETY.md)
- [Research sources](docs/SOURCES.md)
- [Validation report](validation/TEST_REPORT.md)
- [Changelog](CHANGELOG.md)
