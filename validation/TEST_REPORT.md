# Validation report

Release candidate: `0.1.1-beta`  
Validation date: 2026-07-18  
Target: current public pre-PANTHEON Rome II Grand Campaign (`main_rome`)

## Final pack

- File: `dist/wr2_world_resistance.pack`
- SHA-256: `9ca3cf59de7d1851110994917b43a777b46f5adf05c7b61e274439669fbada4e`
- Container: PFH4 Mod, type 3, zero flags, zero dependencies, zero timestamp
- Contents: exactly five DB files, two Lua files, and one additive Loc file
- Size: 85,539 bytes

Two independent clean builds, using separate RPFM homes and output paths, produced byte-identical packs with the same SHA-256.

## RPFM database checks

RPFM 5.0.5 encoded the source TSVs. A fresh RPFM process then reopened the final normalized pack, exported all three tables, and compared their decoded rows with the validated source.

| Table | Version | Rows | Result |
|---|---:|---:|---|
| `effect_bundles_tables` | 1 | 9 | Exact round trip |
| `effect_bundles_to_effects_junctions_tables` | 2 | 162 | Exact round trip; no zero-value rows |
| `fame_levels_tables` | 4 | 8 | Exact round trip; eight unique `(campaign, level)` rows |
| `message_events_tables` | 1 | 6 | Exact round trip; numeric `custom_event_` keys only |
| `message_event_strings_tables` | 3 | 24 | Exact round trip; six events × four proven culture keys |
| `text/db/wr2_world_resistance.loc` | Loc 1 | 30 | Exact round trip; all title/body references closed |

RPFM found no unexpected pack diagnostic. Its only report was `IncorrectGamePath`, because this environment has no installed Rome II game path or dependency cache. Consequently, current live-depot foreign-key resolution remains an in-game/dependency-cache gate.

The schema snapshot SHA-256 is `cbdb4f74265958ea77da2789e15093c7d12c441a7660cf95cba09e3cf5d6eecf`. Detailed machine-readable results are in `build_report.json`.

## Lua checks

- Both shipped scripts compile under stock Lua 5.1.
- Pure pressure/catch-up/telemetry simulation: 34 assertions passed.
- Mock Rome II engine simulation: 341 assertions passed.
- Standalone vanilla-loader simulation: 14 assertions passed.
- Total Lua simulation assertions: 389.

The engine simulation covers universal ally/neutral/enemy scaling, dormant and human exclusion, read-only loading, UI-before-world ordering, first-tick idempotence, saved popup deduplication, tier escalation notices, denied-file-write safety, native `out.ting` traces, treasury parity, bounded diplomacy, Tier 85 forced AI peace, Tier 100 forced AI trade, declaration-time peace enforcement, and the no-human-diplomacy invariant.

## Python checks

Twenty-eight tests passed. They cover:

- the exact 21-effect key/scope allowlist and JSON/CSV equality;
- absolute bundle tiers, catch-up exclusivity, and the `-90%` owned reducer ceiling;
- eight unique fame rows, preserved human thresholds, and the AI final-cap thresholds;
- six unique numeric custom events, 24 culture-specific message rows, 30 unique localization rows, and exact title/body reference closure;
- deterministic PFH4 encoding, sorting, atomic output, path safety, duplicate rejection, and malformed-pack rejection.
- final release/version, eight-file path/hash/size, unchanged balance, observability, and RPFM reopen contracts.

## Limit of this report

This is structural and simulated validation, not a claim of live-game certification. Rome II itself was unavailable here, so the pack has not yet completed a real cold boot, first turn, end turn, save/load, battle return, or high-pressure soak. Follow the live smoke-test sequence in `docs/COMPATIBILITY_AND_TESTING.md` before using the beta with an important save.
