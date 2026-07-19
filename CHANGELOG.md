# Changelog

## 0.1.6-beta — 2026-07-19

This is an observability and anti-hegemonic-coordination update built on the first successful native 0.1.5 campaign reconciliation. The live 0.1.5 traces reached `WORLD_STATE`, `WORLD_READY`, `DIAGNOSTIC_SINK_READY`, `SESSION_START`, `STATE`, and complete AI/pair audits; the activation popup appeared once and remained suppressed after a full exit, reload, and subsequent turn. The same run showed every active AI receiving the maximum pressure and catch-up packages, all surviving AI wars being reconciled, and all 91 AI pairs eventually processed.

### Changed

- Corrected army telemetry and parity calculations to count only general-led land forces as deployable field armies. Rome II exposes settlement garrisons through the same broad army list; those garrisons previously inflated the human and AI army signals.
- Added separate `commanded_armies`, `garrison_armies`, `army_units`, and `full_armies` telemetry. A full army is a general-led field army with at least 20 units.
- Added a per-faction mobilization goal of `min(4 × regions, human parity target, 16)`. A one-region faction therefore aims for at most four field armies, while a four-region faction can aim for the full 16. This is a comparison and reserve target, not a force-spawn command or a dynamic legal-cap rewrite.
- Retained the existing Grand Campaign fame override: active AI can legally reach the final 16-army row, while the human keeps the vanilla 3-to-16 progression. The CAI still decides when and where to recruit.
- At Tier 85 and above, every AI-to-AI direction is now hard-blocked to `CAI_STRATEGIC_STANCE_BEST_FRIENDS` and immediately force-refreshed. Existing protected trade/peace/non-aggression/alliance permissions, break prohibitions, war/join-war blocks, repeated peace enforcement, and Tier 100 legal trade attempts remain in place.
- Did **not** add a claimed `+300` visible relations modifier. The audited Rome II interface exposes numeric faction attitudes for reading, but no safe pair-specific numeric setter. A global DB diplomacy modifier would also affect relationships with the human and therefore violates the AI-only contract.
- Added `DIPLOMACY_AUDIT` records with directional AI-to-AI and AI-to-human attitude count/minimum/average/maximum values, stance-block readback counts, accepted best-friend pair-command counts, and total pair counts.
- Added AI mobilization totals to `STATE` and per-faction goal/shortfall fields to `AI` audit records.
- Bounded both local log files to 1,000 lines. Rotation keeps the newest 800 lines (or the largest smaller tail that leaves room for the incoming detailed batch). If line tracking or rewrite fails, that file write is skipped; native output and all campaign mechanics continue.
- Bumped the release/director identifiers to `0.1.6-beta` / `8`.

### Deliberately unchanged

- The Tier 100 and Catch-up 3 economy, research, public-order, food, growth, construction, recruitment, rank, armour, morale, damage, replenishment, and upkeep effects are unchanged.
- The script does not unlock faction-ineligible units, prescribe elite roster composition, create forces, fill armies, override CAI budgets/personality tables, or rewrite building/technology records. Elite development remains the result of extreme research, construction, recruitment, rank, replenishment, and treasury support acting through normal CAI recruitment.
- Compatibility remains limited to the current public pre-PANTHEON original Grand Campaign (`main_rome`). The pack is standalone but still conflicts with another `all_scripted.lua` owner, another `fame_levels` override, or a diplomacy/CAI overhaul that controls the same pairs.

## 0.1.5-beta — 2026-07-19

This is a mandatory world-reconciliation replacement for 0.1.4. The latest native trace proves that 0.1.4 successfully loaded, attached all six callbacks to the exact exported registry, received campaign events, and acquired Rome II's campaign interface. It then stopped at `WORLD_WAIT` before applying a single AI bundle or treasury grant.

### Fixed

- Corrected Grand Campaign detection to use Rome II's documented boolean predicate, `model:campaign_name("main_rome")`. Release 0.1.4 incorrectly called `campaign_name()` as though it were a zero-argument string getter, so even a valid original Grand Campaign was rejected before reconciliation.
- Changed initialization recovery from “first event context already recognized as human” to the first delivered `FactionTurnStart` in each campaign turn while initialization remains incomplete. The full world scan—not the event-context faction—identifies and protects the human, so an AI turn can now recover a first-tick probe that arrived too early.
- Preserved `LoadingGame` as read-only, `FirstTickAfterWorldCreated` as the primary activation edge, the exact `triggers.events` setup handoff, and all human-isolation guards.

### Diagnostics

- Added non-deduplicated `WORLD_ATTEMPT` records with attempt number and event source.
- Split failed reconciliation into reasoned `WORLD_PROBE_FAIL`, `WORLD_UNSUPPORTED`, and `WORLD_NO_HUMAN` records, followed by `WORLD_WAIT` carrying the exact reason. This distinguishes an unavailable model/world/list from a supported-campaign predicate failure or absent human.
- Added `DIAGNOSTIC_SINK_READY` and `DIAGNOSTIC_SINK_ERROR` bootstrap milestones. The former confirms that `data/wr2_world_resistance.log` opened and wrote; the latter reports an actual sink failure without stopping gameplay.
- Added a compact `WORLD_STATE` bootstrap summary after every successful reconciliation. It reports campaign, turn, human faction, active-AI count, pressure/tier, accepted base and catch-up bundle commands, treasury grant count/total, and target-army signal even when the detailed file is inaccessible.
- Bumped the release/director identifiers to `0.1.5-beta` / `7`.

### Live-trace finding

- The 0.1.4 registry identities match exactly, all six listeners report success, and later `EVENT_HIT_LoadingGame`, `EVENT_HIT_UICreated`, `EVENT_HIT_FirstTickAfterWorldCreated`, `EVENT_HIT_SavingGame`, `EVENT_HIT_FactionTurnStart`, and `EVENT_HIT_FactionLeaderDeclaresWar` records prove dispatch. `ENGINE_READY` proves interface acquisition. This closes the loader, registry, listener, and interface hypotheses.
- The same block reaches `WORLD_WAIT` after first tick but never `WORLD_READY`. Source/API comparison localizes the defect to the incorrect zero-argument `campaign_name()` call.
- The missing `data/wr2_world_resistance.log` in that run is expected: the detailed sink is first used only after supported-world reconciliation. Because reconciliation never succeeded, its absence is not evidence of a bad path or denied file permissions.

### Behavior clarification

- Rome II's diplomacy power bar reflects military strength already on the map. World Resistance intentionally does not spawn forces or units, so activation does not instantly raise that bar. It supplies money, legal army capacity, recruitment slots, low costs, ranks, replenishment, and other advantages; the AI still mobilizes through normal recruitment over subsequent turns.

## 0.1.4-beta — 2026-07-19

This is a mandatory event-registry handoff replacement for 0.1.3. The second live bootstrap trace proved that 0.1.3 reliably found and executed its director in two fresh Lua states, but neither state registered the six campaign listeners.

### Fixed

- Added the explicit public setup boundary `WR.setup(event_registry)`. After the protected director import, the root loader now calls `director.setup(triggers.events)` with dot-call semantics and the exact registry returned by the preserved vanilla `export_triggers` import.
- Removed listener registration's dependency on `rawget(_G, "events")`. Rome II can expose different global views across the root loader and an imported module, so a global assigned by `all_scripted.lua` is no longer treated as a cross-module transport.
- Scoped listener idempotence to the supplied registry object. Repeating setup on that registry reuses callbacks; a partial attempt remains retryable without duplicating listeners that were already inserted.
- Kept event registration independent of `game_interface`. Setup can finish while the normal early `ENGINE_WAIT` state is active, and later events still perform lazy interface discovery.

### Diagnostics

- Separated successful import from successful setup. `DIRECTOR_REQUIRE_OK` is now followed by `DIRECTOR_SETUP_TRY` and exactly one loader outcome: `DIRECTOR_SETUP_OK`, `DIRECTOR_SETUP_PARTIAL`, `DIRECTOR_SETUP_ERROR`, or `DIRECTOR_API_ERROR`.
- Added a loader-owned `EVENT_REGISTRY_READY` with detail `source=export_triggers` before import and a director-owned record with detail `source=loader_argument` during setup. Their opaque registry identities make the object handoff auditable. Added `EVENT_REGISTRY_INVALID` for a rejected argument and per-event `LISTENER_OK_*`, `LISTENER_REUSED_*`, `LISTENER_MISSING_*`, and `LISTENER_INSERT_ERROR_*` outcomes.
- Added aggregate `LISTENERS_READY` and `LISTENERS_PARTIAL` results. Setup-attempt diagnostics are not suppressed by once-only event/runtime milestone caching, so a partial attempt and later recovery remain visible.
- Defined the minimum attachment proof as one load ID reaching both matching `EVENT_REGISTRY_READY` records, `LISTENERS_READY`, and `DIRECTOR_SETUP_OK`. A later `EVENT_HIT_*`, `ENGINE_READY`, and `WORLD_READY` remain the runtime and world-activation gates.

### Live-trace finding

- Read the appended bootstrap file by `load` ID rather than as one chronological session. Both 0.1.3 blocks reached `MODULE_PATH_READY`, `DIRECTOR_ROUTE_OK`, and `DIRECTOR_REQUIRE_OK`; both stopped without `LISTENERS_READY` or an event hit.
- Treated the early `ENGINE_WAIT|detail=director_import` in those blocks as expected. The failure boundary is missing listener attachment, not early interface availability.
- Combined that native evidence with source inspection: 0.1.3's root loader held `triggers.events`, while the imported director independently looked for `_G.events`. The 0.1.4 argument handoff removes that unproven environment-sharing assumption.
- Confirmed that the failure occurred before a campaign event, save inspection, supported-world reconciliation, or any scaling command. A new campaign and the DB-only No Civil War mod could not repair or cause this boundary.

### Validation

- Added isolated-module regression coverage in which the director cannot see a global `events` value but receives the exact registry argument from the loader.
- Added API-shape, dot-call, registry-identity, six-event outcome, repeated-setup, partial-registration, retry-without-duplicates, and protected loader-failure coverage.
- Retained delayed-interface, existing-save, first-human-turn recovery, path restoration, and fail-closed logging tests. These remain simulated Lua evidence; 0.1.4 still requires the native acceptance sequence documented in the smoke test.

## 0.1.3-beta — 2026-07-19

This is a mandatory loader and lifecycle replacement for 0.1.2. Live bootstrap evidence showed that 0.1.2 could load its director without ever attaching listeners and, in a separate fresh Lua state, could fail to resolve that director at all.

### Fixed

- Moved the director from Rome II's engine-owned `lua_scripts` namespace to the pack-owned path `script/campaign/wr2/wr2_world_resistance.lua`.
- Added a protected, explicit module route. `all_scripted.lua` temporarily prepends `script/campaign/wr2/?.lua`, imports the simple `wr2_world_resistance` module name, and restores the original `package.path` before Rome II continues loading.
- Removed WR's early `EpisodicScripting` import and its dependency on a second `NewSession` callback. Rome II's campaign script remains the sole owner of initializing that module.
- Registered the six loading, saving, UI, first-tick, faction-turn, and declaration-of-war listeners immediately in the exported Rome II event table, independently of whether `game_interface` is available yet.
- Changed every engine-dependent callback to resolve the already-loaded `game_interface` lazily from Rome II's globals or `package.loaded`, without calling `require`.
- Kept `FirstTickAfterWorldCreated` as the normal world-activation edge and added a human-turn retry if the interface or supported campaign world was not ready on first tick. A failed attempt no longer permanently marks the director initialized.

### Diagnostics

- Added a per-loader `load` ID to every bootstrap line so multiple append-only startup blocks cannot be accidentally combined.
- Added explicit `MODULE_PATH_READY`, `DIRECTOR_ROUTE_TRY`, `DIRECTOR_ROUTE_OK`, and `DIRECTOR_ROUTE_ERROR` milestones around custom-module discovery.
- Added protected `EVENT_HIT_<event>` and `EVENT_ERROR_<event>` milestones for all six registered callbacks.
- Added `WORLD_READY` and `WORLD_WAIT` milestones to distinguish a loaded director from successful campaign reconciliation, plus event-specific `ENGINE_UNAVAILABLE_<event>` traces when lazy interface discovery must retry.
- Increased protected bootstrap-detail capacity so a module-resolution failure preserves substantially more of Lua's search report.

### Live-trace finding

- Interpreted the reported 0.1.2 bootstrap file as two separate attempts. The first ended at `ENGINE_WAIT` plus `DIRECTOR_REQUIRE_OK` without `ENGINE_READY` or `LISTENERS_READY`; the second ended in `DIRECTOR_REQUIRE_ERROR` because `lua_scripts.wr2_world_resistance` was not discoverable in that state.
- Confirmed that this trace occurs before save-specific WR behavior and does not implicate the DB-only No Civil War mod. Starting a new campaign could not repair either loader defect.
- Updated the clean retest contract: begin with an empty bootstrap file, group all lines by `load`, require a successful director route and `LISTENERS_READY`, then require a later event hit, `ENGINE_READY`, `WORLD_READY`, and detailed `SESSION_START`/`STATE` output.

### Validation

- Replaced the simulated CA-first `NewSession` publisher with the actual load-order contract: listeners exist before the campaign publishes its interface, and later events acquire it without an early import.
- Added fresh-Lua-state module-route coverage so tests no longer inject a broad path that makes the broken 0.1.2 route appear valid.
- Added retry, event-boundary, path-restoration, duplicate-registration, and expanded bootstrap-trace coverage.

## 0.1.2-beta — 2026-07-19

This is a mandatory lifecycle hotfix for 0.1.1. Remove the old `wr2_world_resistance.pack` and install only `@wr2_world_resistance.pack`; the leading `@` is intentional.

### Fixed

- Deferred engine-adapter initialization until Rome II's `NewSession` lifecycle event. The stock campaign loader creates `game_interface` after `all_scripted.lua` imports WR, so 0.1.1 could return early without ever registering its campaign listeners.
- Appended WR's guarded `NewSession` callback after CA's callback, then attached the normal loading, saving, UI, first-tick, faction-turn, and declaration-of-war listeners once the interface became available.
- Made deferred attachment idempotent and fail-closed so repeated lifecycle callbacks cannot duplicate listeners and a Lua or logging failure cannot abort the vanilla campaign loader.
- Preserved immediate attachment for test or engine contexts where `game_interface` is already available.

### Added

- A root-level `wr2_world_resistance_bootstrap.log` that starts before the director import and records `LOADER_START`, import success/failure, `ENGINE_WAIT`, `ENGINE_READY`, and `LISTENERS_READY` milestones.
- A protected bridge from the deferred director back to the root bootstrap logger, allowing startup diagnosis even before `data/wr2_world_resistance.log` can begin.
- Clean-smoke-test guidance for interpreting the bootstrap log separately from the detailed campaign `SESSION_START`, `STATE`, and AI-audit telemetry.

### Packaging and compatibility

- Renamed the installable pack to the exact filename `@wr2_world_resistance.pack`. Older WR packs must be removed rather than left beside it.
- Confirmed that a copied existing original Grand Campaign (`main_rome`) save is suitable for activation testing. A new campaign remains the supported balance path because WR cannot retroactively reproduce earlier AI development.
- Confirmed that the DB-only No Civil War and Stable Politics mods do not replace WR's Lua loader and are compatible with its activation path. They should remain disabled during the initial clean smoke test.
- The balance DB and localization payloads are unchanged from 0.1.1; this hotfix changes the two Lua entries and release packaging.

### Validation

- Added a regression simulation for Rome II's real pre-`NewSession` initialization order, including CA-first interface publication, one-time listener registration, and first-tick reconciliation of an existing save.
- Added denied-file-write coverage proving that both logs fail safely while native traces and the campaign director continue.
- Rebuilt and reopened the PFH4 pack deterministically with the expected eight-entry tree and exact leading-`@` filename.

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
