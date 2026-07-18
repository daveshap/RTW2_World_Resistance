# Changelog

## 0.1.0-beta — 2026-07-18

First pre-PANTHEON Grand Campaign build.

### Added

- Universal scaling for every active non-human faction from turn one, without war, alliance, client, contact, culture, or distance filters.
- Six territory-led global pressure tiers with army/treasury secondary signals.
- Permanent Tier 65 floor after final vanilla Imperium and continued territory scaling to Tier 100.
- Ten-turn, one-band economic demotion hysteresis and a permanent diplomatic high-water mark.
- Three per-faction catch-up levels based on the worst region, army, or treasury shortfall.
- Extreme AI construction, economy, recruitment, upkeep, replenishment, rank, armour, morale, melee damage, experience gain, research, public order, food, and growth effects.
- Human-relative treasury floors, replacement reserves, per-update bounds, and no subtraction behavior.
- AI-only cooperative stances and treaty permissions, protected agreements, hard peace, war/join-war lock, and top-tier direct legal trade attempts.
- Grand Campaign AI prestige-threshold override intended to provide the final 16-army cap from the start while retaining the human's normal cap progression.
- Vanilla-preserving `all_scripted.lua` loader with a protected director import.
- Save/load persistence using primitive named values and idempotent world reconciliation.
- Bounded diplomacy batches and declaration-time AI peace enforcement.
- Lua 5.1 calculation/adapter simulations, PFH4 validation tooling, reproducible balance data, and research documentation.

### Deliberate exclusions

- No force spawning, teleporting, startpos edit, DLL, executable patch, or movie pack.
- No universal CAI personality-table rewrite.
- No global building or technology table rewrite.
- No direct friendliness bonus toward the human.
- No support for DLC campaigns, multiplayer balance, or PANTHEON/JUPITER.

### Known beta gates

- No live Rome II cold boot, new-campaign first turn, end turn, save/load, battle return, or long soak was possible in the build environment.
- AI fame-threshold resolution and human cap isolation require in-game verification.
- One-turn construction flooring, sabotage/repair behavior, high-difficulty reducer stacking, and scripted-war bypasses require in-game verification.
- Another mod replacing `lua_scripts/all_scripted.lua` or Grand Campaign `fame_levels` requires a manual compatibility patch.
