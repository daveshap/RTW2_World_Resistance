# Validation report

Release candidate: `0.1.8-beta`  
Validation date: 2026-07-20  
Target: current public pre-PANTHEON Rome II Grand Campaign (`main_rome`)

## Final pack

- File: `dist/@wr2_world_resistance.pack`
- SHA-256: `4f01060d9ace7d948f7948f4de76220c6c51ef1c5a40de218bd82197114ef1d6`
- Container: PFH4 Mod, type 3, zero flags, zero dependencies, zero timestamp
- Size: 135,934 bytes
- Paths, exactly:

  - `db/effect_bundles_tables/wr2_world_resistance`
  - `db/effect_bundles_to_effects_junctions_tables/wr2_world_resistance`
  - `db/fame_levels_tables/wr2_world_resistance`
  - `db/message_event_strings_tables/wr2_world_resistance`
  - `db/message_events_tables/wr2_world_resistance`
  - `lua_scripts/all_scripted.lua`
  - `script/campaign/wr2/wr2_world_resistance.lua`
  - `text/db/wr2_world_resistance.loc`

The final PFH4 was reopened and verified for its header, file index, exact eight-path set, payload bounds, and SHA-256. The release tests also verify that this is the only `.pack` in `dist`.

## Database and Loc provenance

This is a Lua-only hotfix built from the RPFM-verified `0.1.1-beta` pack. The loader changed, the old `lua_scripts/wr2_world_resistance.lua` entry was removed, and the corrected director was added at `script/campaign/wr2/wr2_world_resistance.lua`. The following five DB payloads and one Loc payload were copied without decoding or re-encoding and are byte-identical to that base; their per-payload SHA-256 values are recorded in `build_report.json`.

RPFM 5.0.5 was not rerun for this hotfix because its temporary executable was no longer available. The retained `0.1.1-beta` evidence is an exact RPFM encode, reopen, export, and source comparison of all five DB tables plus the Loc file:

| Table | Version | Rows | Result |
|---|---:|---:|---|
| `effect_bundles_tables` | 1 | 9 | Exact round trip |
| `effect_bundles_to_effects_junctions_tables` | 2 | 162 | Exact round trip; no zero-value rows |
| `fame_levels_tables` | 4 | 8 | Exact round trip; eight unique `(campaign, level)` rows |
| `message_events_tables` | 1 | 6 | Exact round trip; numeric `custom_event_` keys only |
| `message_event_strings_tables` | 3 | 24 | Exact round trip; six events × four proven culture keys |
| `text/db/wr2_world_resistance.loc` | Loc 1 | 30 | Exact round trip; all title/body references closed |

That prior RPFM run found no unexpected pack diagnostic. Its only report was `IncorrectGamePath`, because this environment has no installed Rome II game path or dependency cache. The hotfix PFH4 itself was independently reopened and verified by `tools/pfh4.py`; current live-depot foreign-key resolution remains an in-game/dependency-cache gate.

The unchanged schema snapshot SHA-256 is `cbdb4f74265958ea77da2789e15093c7d12c441a7660cf95cba09e3cf5d6eecf`. Detailed machine-readable provenance, retained RPFM results, payload hashes, and final-container results are in `build_report.json`; the original machine-readable RPFM report is retained as `build_report_v0.1.1.json`.

## Lua checks

- Both shipped scripts remain Lua 5.1-syntax-only and parse/execute in the available Lua-compatible test runtime.
- Pure pressure/catch-up/field-army/development/telemetry simulation: 45 assertions passed.
- Mock Rome II engine simulation: 390 assertions passed.
- Explicit-path vanilla-loader simulation: 21 assertions passed.
- Immediate-listener/lazy-interface lifecycle simulation: 31 assertions passed.
- Protected loader-failure simulation: 19 assertions passed.
- Isolated loader/director environment and exact-registry handoff: 59 assertions passed.
- Partial listener registration, retry, replacement-registry, and insertion-failure recovery: 68 assertions passed.
- Missing/throwing/partial setup API failure boundaries: 27 assertions passed.
- Grand Campaign predicate, reasoned world-retry, and diagnostic-sink activation contract: 71 assertions passed.
- Bootstrap rolling-log simulation: 2,224 assertions passed.
- Detailed rolling-log simulation: 1,664 assertions passed.
- Total: 11 Lua simulations and 4,619 assertions passed.

The engine simulation covers universal ally/neutral/enemy scaling, dormant and human exclusion, read-only loading, UI-before-world ordering, first-tick idempotence, saved popup deduplication, tier escalation notices, denied-file-write safety, native `out.ting` traces, treasury parity, region-adjusted field-army estimation even when `has_general()` misidentifies garrisons, separate garrison/unit/full-stack telemetry, regional mobilization goals, bounded diplomacy, Tier 85 pair-scoped `BEST_FRIENDS` promotion, Tier 100 forced AI trade, declaration-time peace enforcement, and the no-human-diplomacy invariant. It also covers one representative per unique AI province, the exact `0/0/1/1/2/3` direct-development scale, current-owner human isolation, same-turn save/load deduplication, protected native failures, continued processing after individual failures, and owner-change skips. The maximum-tier fixture requires the stable 25-call diplomacy profile per pair.

The lifecycle regression reproduces the corrected ordering: `all_scripted.lua` loads with a hostile ambient module path and no campaign interface; the loader temporarily supplies its unique director path; all six listeners register through the explicit setup call; and WR never imports `EpisodicScripting`. A too-early first tick remains uninitialized and mutation-free. After the simulated campaign publishes its existing interface, `LoadingGame` restores all seven values and the next faction turn completes the bounded retry, AI scaling, and treasury activation. Denied file writes remain nonfatal throughout.

The activation regression gives `campaign_name` the exact Rome II predicate contract: it rejects zero arguments, requires the `main_rome` key, and returns a boolean. An unsupported predicate produces no mutations and emits `WORLD_UNSUPPORTED` plus a reasoned `WORLD_WAIT`; the first faction turn in a later campaign turn can recover regardless of whether that event context is AI or human. A successful run must emit `WORLD_STATE`, `WORLD_READY`, and `DIAGNOSTIC_SINK_READY`, write to exactly `data/wr2_world_resistance.log`, and process every active non-human faction. Separate cases prove that unavailable-world, no-human, and denied-sink outcomes are explicit, while a denied detailed log remains nonfatal.

The new environment-boundary regression evaluates the root loader in an isolated global environment while the required director runs against a different `_G` containing a deliberate decoy `events` table. It proves that the loader passes its exact local `triggers.events` object into `WR.setup`, all six WR callbacks append beside pre-existing native callbacks, the decoy remains untouched, and a cached second loader evaluation reuses callback identities without duplication. Recovery coverage proves that missing or insertion-rejecting slots remain partial and later become ready without duplicating the listeners that already succeeded.

Observability coverage distinguishes both local logs. `wr2_world_resistance_bootstrap.log` records loader/director milestones before the game interface exists, while `data/wr2_world_resistance.log` remains the structured campaign telemetry sink after successful world reconciliation. Both rotation simulations preload and append through the 1,000-line boundary, verify retention of the newest 800-line history, and prove that read/tracking/rewrite failure skips file output while native traces and gameplay continue. Detailed audits cover corrected mobilization fields, read-only building counts, direct-development eligibility/accepted/failed/skipped counters, directional `DIPLOMACY_AUDIT` attitude aggregates, and accepted best-friend promotions. They do not claim native building or stance readback.

The loader-failure regression forces the explicitly routed director import to throw before any campaign interface exists. It verifies that the vanilla loader and exported event registry survive, `package.path` is restored, the root bootstrap log receives route-level and final sanitized errors, native logging receives the failure, and no partial WR director is published.

## Python checks

Thirty-two tests passed. They cover:

- the exact 21-effect key/scope allowlist and JSON/CSV equality;
- absolute bundle tiers, catch-up exclusivity, and the `-90%` owned reducer ceiling;
- eight unique fame rows, preserved human thresholds, and the AI final-cap thresholds;
- six unique numeric custom events, 24 culture-specific message rows, 30 unique localization rows, and exact title/body reference closure;
- deterministic PFH4 encoding, sorting, atomic output, path safety, duplicate rejection, and malformed-pack rejection;
- the manual-load-order filename, exact eight-file path/hash/size contract, two bounded-log paths, explicit module route, exact-registry setup contract, retry edge, field-army/AI-cooperation/development runtime contract, and per-listener bootstrap milestones;
- a source-level prohibition on all three 0.1.6 native stance-lock, forced-refresh, and malformed blocker-readback methods;
- byte-for-byte equality between both tested Lua source files and the Lua payloads extracted from the final `.pack`, followed by rerunning all four registry/setup/activation integration fixtures against those extracted payloads;
- the Lua-only payload provenance, byte-identical five-DB-plus-Loc base payloads, unchanged balance, and retained RPFM reopen contract.

## Limit of this report

This is structural and simulated validation of the 0.1.8 delta, not a claim of complete live-game certification. The user's 0.1.4 trace supplies native evidence for loading, exact registry handoff, all six listeners, event dispatch, and interface discovery. The 0.1.5 traces add successful maximum-pressure reconciliation; the 0.1.6 traces isolate the later Diplomacy-panel crash; and the user's 0.1.7 playtest now supplies native evidence that the crash-hotfix loads, survives Diplomacy entry, remains stable across multiple turns, produces more/full AI armies, and materially raises campaign difficulty. Its detailed log spans only turns 207–211 while Rome expands from 138 to 148 of 173 regions and active AIs fall from 14 to 12. Every survivor has accepted Tier 100 plus Catch-up 3 and roughly 4.8–5.9 million treasury targets, so those late-save low-level settlements are not evidence of an affordability failure and received only four development cycles. Rome II was unavailable in this build environment, so 0.1.8's direct-development call, resulting building choices, capture/repair/conversion behavior, and fresh-campaign buildout still require the live sequence in `docs/COMPATIBILITY_AND_TESTING.md`.
