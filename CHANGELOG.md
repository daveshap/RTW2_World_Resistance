# Changelog

## 0.1.1-beta — 2026-07-18

### Added

- Native Rome II activation/status messages after the first successful reconciliation and at each new resistance-tier high.
- Saved `highest_notified_tier` state to prevent reload and demotion popup spam.
- Append-only, local-only `data/wr2_world_resistance.log` diagnostics with versioned `SESSION_START`, `STATE`, `AI_AUDIT`, `AI`, `UI_NOTICE`, and `AI_WAR_SUPPRESSED` records.
- Per-AI audit fields for selected bundles, catch-up level, treasury target/grant, force/region counts, and protected command-acceptance status.
- RPFM-encoded and round-tripped `message_events`, `message_event_strings`, and English Loc sources using proven vanilla UI assets.

### Fixed

- Director and protected-loader logging now call Rome II's actual `out.ting()` table method instead of treating `out` as a function or relying only on `print`.
- Structured `STATE` output is deduplicated to once per human turn.
- File logging fails closed if `io` or game-directory write access is unavailable and cannot interrupt campaign mutation.

### Validation

- Expanded lifecycle simulations cover UI-before-world ordering, read-only loading, saved popup deduplication, tier escalation, native traces, and denied file writes.
- Pack contract expanded deterministically from five to eight files; all new DB and Loc rows are reopened, exported, and compared through RPFM.

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
