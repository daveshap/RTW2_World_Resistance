# Validation report

Release candidate: `0.1.0-beta`  
Validation date: 2026-07-18  
Target: current public pre-PANTHEON Rome II Grand Campaign (`main_rome`)

## Final pack

- File: `dist/wr2_world_resistance.pack`
- SHA-256: `0fff2492ac82259d14d94eeda08a7768ec6c703f868dfdb92296b779959cf01b`
- Container: PFH4 Mod, type 3, zero flags, zero dependencies, zero timestamp
- Contents: exactly three DB files and two Lua files
- Size: 59,579 bytes

Two independent clean builds, using separate RPFM homes and output paths, produced byte-identical packs with the same SHA-256.

## RPFM database checks

RPFM 5.0.5 encoded the source TSVs. A fresh RPFM process then reopened the final normalized pack, exported all three tables, and compared their decoded rows with the validated source.

| Table | Version | Rows | Result |
|---|---:|---:|---|
| `effect_bundles_tables` | 1 | 9 | Exact round trip |
| `effect_bundles_to_effects_junctions_tables` | 2 | 162 | Exact round trip; no zero-value rows |
| `fame_levels_tables` | 4 | 8 | Exact round trip; eight unique `(campaign, level)` rows |

RPFM found no unexpected pack diagnostic. Its only report was `IncorrectGamePath`, because this environment has no installed Rome II game path or dependency cache. Consequently, current live-depot foreign-key resolution remains an in-game/dependency-cache gate.

The schema snapshot SHA-256 is `cbdb4f74265958ea77da2789e15093c7d12c441a7660cf95cba09e3cf5d6eecf`. Detailed machine-readable results are in `build_report.json`.

## Lua checks

- Both shipped scripts compile under stock Lua 5.1.
- Pure pressure/catch-up simulation: 32 assertions passed.
- Mock Rome II engine simulation: 329 assertions passed.
- Standalone vanilla-loader simulation: 13 assertions passed.
- Total Lua simulation assertions: 374.

The engine simulation covers universal ally/neutral/enemy scaling, dormant and human exclusion, read-only loading, first-tick idempotence, save values, treasury parity, bounded diplomacy, Tier 85 forced AI peace, Tier 100 forced AI trade, declaration-time peace enforcement, and the no-human-diplomacy invariant.

## Python checks

Nineteen tests passed. They cover:

- the exact 21-effect key/scope allowlist and JSON/CSV equality;
- absolute bundle tiers, catch-up exclusivity, and the `-90%` owned reducer ceiling;
- eight unique fame rows, preserved human thresholds, and the AI final-cap thresholds;
- deterministic PFH4 encoding, sorting, atomic output, path safety, duplicate rejection, and malformed-pack rejection.

Ten additional release-contract assertions against `build_report.json` passed.

## Limit of this report

This is structural and simulated validation, not a claim of live-game certification. Rome II itself was unavailable here, so the pack has not yet completed a real cold boot, first turn, end turn, save/load, battle return, or high-pressure soak. Follow the live smoke-test sequence in `docs/COMPATIBILITY_AND_TESTING.md` before using the beta with an important save.
