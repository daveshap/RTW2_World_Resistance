# Compatibility and testing

## Supported target

| Environment | Status |
|---|---|
| Current public pre-PANTHEON Rome II | Targeted |
| Grand Campaign (`main_rome`) | Targeted |
| New single-player campaign | Strongly recommended |
| Existing original Grand Campaign save | 0.1.7 activation, Diplomacy-panel stability, and turns 207–211 confirmed in one live save; balance and retroactive AI development are not certified |
| Multiplayer / co-op | Defensive handling exists, but balance and lifecycle are unsupported |
| DLC and mini-campaigns | Unsupported; the director becomes inert outside `main_rome` |
| PANTHEON/JUPITER branch | Unsupported; requires a separate build |

Creative Assembly has announced that PANTHEON will change Rome II over a series of updates, and JUPITER specifically revisits buildings and army/navy/agent-cap sources. This release intentionally targets the public pre-PANTHEON rules rather than guessing at an unreleased final cap model. Its `fame_levels` table uses the backward-compatible v4 Grand Campaign row shape verified in decoded stable packs. RPFM also knows later table layouts, but those definitions predate the PANTHEON announcement and are not labelled here as future formats.

The installable filename is `@wr2_world_resistance.pack`. The leading `@` is intentional: it improves recognition of a manually installed local pack by the current Rome II launcher. Remove or disable the old unprefixed `wr2_world_resistance.pack`; keeping both copies makes it impossible to know which release the launcher selected.

The standalone `.pack` beside the release archive and the copy under the archive's `dist/` directory are the same installable artifact and must have the same SHA-256 recorded in the final validation report. No companion pack is required. If those hashes differ, do not guess which one is newer; preserve the files and report the mismatch.

## Compatibility matrix

World Resistance is self-contained in one pack and needs no framework or companion mod. It still edits shared Rome II resources.

| Other mod type | Expected compatibility | Reason |
|---|---|---|
| Reskins, models, textures, battle audio | Usually compatible | No shared campaign tables or loader expected |
| Unit roster or battle-stat mods | Often compatible | World Resistance applies faction effects, but armour modifiers will combine |
| Economy, research, public-order, upkeep, recruitment, or difficulty mods | Balance conflict likely | Additive modifiers can exceed intended ceilings |
| [Stable Politics: No Civil War](https://github.com/daveshap/RTW2_No_Civil_War) | Compatible | Its selected preset is a DB-only political-loyalty fragment; it has no Lua loader, `fame_levels` rows, or World Resistance keys |
| Grand Campaign army-cap / Imperium mods | Incompatible | Shared `fame_levels` rows |
| Mod replacing `lua_scripts/all_scripted.lua` | Incompatible without a manual merge | Rome II has one loader path; last loaded file wins |
| Diplomacy or CAI overhaul | High conflict risk | Both systems may constrain the same AI-to-AI deals and stances |
| Total campaign overhaul | Unsupported | Campaign key, region count, DB rows, and loader assumptions may differ |
| Startpos or force-spawning mod | Unsupported combination | Harder to isolate lifecycle and cap failures |

Rome II's `all_scripted.lua` does not have a safe automatic multi-mod append mechanism. A compatibility patch must preserve the seven vanilla imports, assign `events = triggers.events`, and protected-load both mods after that assignment. World Resistance 0.1.8 must also receive the exact shared registry through `director.setup(triggers.events)`; merely assigning an `events` global is not a verified cross-module handoff.

The inspected Stable Politics presets do not replace `all_scripted.lua` and do not share a primary key with World Resistance. Their relative launcher order should therefore be immaterial. Complete the World Resistance-only smoke test first, then enable exactly one Stable Politics preset and repeat the first-turn/end-turn check; this remains a compatibility expectation until both packs have been exercised together in a live Rome II installation.

## Activation history and 0.1.8 settlement-hotfix baseline

Release 0.1.1 imported the director before Rome II had exposed `scripting.game_interface`. When the interface was absent, the adapter returned without registering its campaign listeners and had no retry path. That made the mod silent and mechanically inert on both a new campaign and a loaded campaign. Starting a new campaign could not repair that defect.

Release 0.1.2 kept the root loader alive but assumed that appending a function to `events.NewSession` would run after Rome II published `game_interface`. The first native bootstrap trace reached `ENGINE_WAIT` without completing that hand-off. A subsequent fresh campaign Lua state also failed to resolve the custom `lua_scripts.wr2_world_resistance` module. Starting a new campaign could not make either loader assumption reliable.

Release 0.1.3 fixed the module route: its loader temporarily prepended `script/campaign/wr2/?.lua`, required the simple module name, and restored the prior path. The second native trace confirms that route succeeded in two separate 0.1.3 load IDs. Both blocks nevertheless stopped after `DIRECTOR_REQUIRE_OK`, with no `LISTENERS_READY` or event hit. The director had attempted to find `events` through its own `_G`; the live runtime did not demonstrate that the root loader's global assignment was visible in that imported environment.

Release 0.1.4 preserved the proven route and added an explicit API boundary. The imported module returns `WR`, the loader checks its `setup` function, and calls `director.setup(triggers.events)` with dot-call semantics. Listener registration uses only that argument and records the registry identity; it does not rediscover `_G.events`. The latest live trace proves that this boundary works: it contains matching registry identities, all six listener successes, multiple event hits, and `ENGINE_READY`.

The 0.1.4 director nevertheless stopped at `WORLD_WAIT`. Rome II's model API exposes `campaign_name(key)` as a boolean predicate. The director incorrectly called `campaign_name()` as if it were a zero-argument string getter, then rejected the valid Grand Campaign before any bundle, treasury, or diplomacy mutation.

Release 0.1.5 calls `model:campaign_name("main_rome")`, keeps `LoadingGame` read-only, and retains `FirstTickAfterWorldCreated` as the normal activation edge. If initialization is still incomplete, the first delivered `FactionTurnStart` in each campaign turn retries regardless of that context faction's human/AI status; the complete world scan performs supported-campaign detection, finds the human, and enforces human isolation. This avoids requiring the first retry context to be recognized as human before the world has initialized.

The later 0.1.5 live run closes the activation gap: a loaded maximum-pressure original Grand Campaign reaches `WORLD_STATE`, `WORLD_READY`, `DIAGNOSTIC_SINK_READY`, `SESSION_START`, `STATE`, and complete AI/pair audits. Every active AI receives Tier 100 plus Catch-up 3 in that save, all 91 surviving AI pairs are processed, treasury support repeats as needed, and the activation popup stays deduplicated after a full exit/reload/turn advance.

Release 0.1.6 preserved that live-proven activation path, added a `min(4 × regions, human parity target, 16)` mobilization goal, richer audits, and bounded logs. It also attempted to classify field armies with `has_general()` and added a hard block plus forced stance refresh in each direction of every high-tier AI pair. Live Rome II then exposed two regressions: the force predicate still counted settlement garrisons, and opening the Diplomacy panel after reconciliation caused a repeatable native hard crash.

Release 0.1.7 removes all hard-block, forced-refresh, and invalid blocker-readback calls while retaining bidirectional tier-appropriate stance promotion, AI-only treaty permissions/protections, ordinary war/join-war blocking, repeated peace enforcement, and top-tier legal trade attempts. It estimates `main_rome` field armies as broad land-army forces minus one presumed settlement-garrison force per owned region, clamped at zero. That estimate drives the existing mobilization goal and is not native force-type readback. The DB effects, cap strategy, roster policy, force-spawning policy, and CAI budget/personality policy are unchanged.

The subsequent 0.1.7 native run passed the Diplomacy-panel crash boundary and continued through turns 207–211. Rome expanded from 138 to 148 of 173 regions while active AI factions fell from 14 to 12. Every surviving AI received Tier 100 plus Catch-up 3 and treasury targets around 4.8–5.9 million. The AI fielded more and fuller armies and substantial agent pressure, but many conquered settlements still had low-level buildings. With only four new development cycles before another ten regions changed hands, this late save proves activation and pressure—not a full-campaign buildout.

Release 0.1.8 preserves the 0.1.7 activation, diplomacy, DB, and localization payloads. Its only gameplay delta is a protected once-per-campaign-turn development-point batch: one representative region per unique AI-owned province receives 0 / 0 / 1 / 1 / 2 / 3 points at Tiers 0 / 20 / 40 / 65 / 85 / 100. A saved global last-development-turn prevents same-turn duplication. Human provinces are excluded. The points supply surplus but do not force CAI building choices or bypass building-chain prerequisites.

## Why Normal campaign difficulty is the initial target

World Resistance caps its own construction, recruitment, upkeep, and mercenary reductions at `-90%`. Vanilla campaign difficulty, technologies, buildings, characters, and another mod can add to the same scalar. Patch-17 vanilla-derived evidence includes AI upkeep modifiers down to roughly `-30%` and unit-cost modifiers down to roughly `-25%`.

The database accepts a finite value below `-100`, but that does not establish safe economic behavior. Start on Normal. Harder campaign difficulties must be tested for zero/negative prices and unexpected payments before being recommended.

## Build-environment checks and supplied live evidence

The source was designed and checked against:

- the current RPFM Rome II schema snapshot and exact table field types;
- real decoded PFH4 Rome II Workshop rows for all selected effect/scope pairs;
- a current Rome II scripting API and event dump;
- Rome II's evidenced `all_scripted.lua` → campaign `scripting.lua` load order, an explicit pack-local module path, an explicit `triggers.events` argument handoff, and lazy interface discovery;
- Rome II's documented three-argument custom message-event path and a working Workshop implementation exported through RPFM;
- Lua 5.1 syntax and pure/mocked simulations, including no-interface import, delayed interface publication, first-faction-turn-per-campaign-turn recovery, all-faction eligibility, and the no-human-diplomacy invariant;
- deterministic PFH4 structure tests and pack round-trip tooling.

These checks reduce guessed-key and malformed-pack risk. The user's 0.1.4 trace supplies native proof of loader selection, listener attachment, event dispatch, and interface acquisition. The later 0.1.5 bootstrap and detailed traces supply native proof of a successful maximum-pressure world reconciliation, protected bundle/treasury command processing, complete pair traversal, one-time popup behavior, a full exit/reload, and a later turn. The 0.1.6 run supplies native proof of the Diplomacy-panel crash boundary and disproves `has_general()` as a garrison discriminator. The turns 207–211 0.1.7 run supplies native proof that the crash repair holds in that save and shows stronger mobilization, extreme treasury support, heavy agent use, and uneven inherited settlement development. The build environment still lacks the paid Rome II data depot, Assembly Kit dependency cache, and runnable executable, and the live runs do not certify 0.1.8's development-point calls, full-campaign city development, ideal elite roster choices, universal alliance formation, or every long-soak edge case.

Treat any generated validation report as structural evidence, not an in-game certification.

## Required live smoke test

Use a disposable profile or backed-up saves. Test with no other mods before combining anything.

1. Close Rome II. Remove or disable every older World Resistance copy, especially unprefixed `wr2_world_resistance.pack`, and archive the two old log files so this run starts with unambiguous evidence.
2. Put `@wr2_world_resistance.pack` in `data` and enable only that pack.
3. Cold-start to the main menu. A failure before the menu points first to pack/schema/loader conflicts.
4. Start a new original Grand Campaign and reach the first human turn.
5. Open `wr2_world_resistance_bootstrap.log` in the Rome II installation root, one directory above `data`. For release 0.1.8, one load ID must contain `LOADER_START`, loader-owned `EVENT_REGISTRY_READY` with detail `source=export_triggers`, `MODULE_PATH_READY`, `DIRECTOR_ROUTE_TRY`, `DIRECTOR_ROUTE_OK`, `DIRECTOR_REQUIRE_OK`, `DIRECTOR_SETUP_TRY`, director-owned `EVENT_REGISTRY_READY` with detail `source=loader_argument`, all six `LISTENER_OK_*` stages, `LISTENERS_READY`, and `DIRECTOR_SETUP_OK`. The opaque `registry=` identity in the two ready lines must match. After campaign dispatch begins it must also reach an `EVENT_HIT_*`, `ENGINE_READY`, `WORLD_ATTEMPT`, `WORLD_STATE`, and `WORLD_READY`. An early `ENGINE_WAIT|detail=director_setup` is expected when `all_scripted.lua` precedes the campaign interface; it is only a failure if no later event reaches `ENGINE_READY`.
6. Confirm a **WORLD RESISTANCE ACTIVE** message appears only after the campaign map finishes reconciling.
7. Confirm the same bootstrap block contains `DIAGNOSTIC_SINK_READY`, then open `data/wr2_world_resistance.log`. Confirm it contains one `SESSION_START`, one `STATE`, and an `AI_AUDIT_BEGIN`/`DIPLOMACY_AUDIT`/`AI`/`AI_AUDIT_END` block for the current turn. This detailed file is deliberately not created until a supported world has reconciled successfully. `DIAGNOSTIC_SINK_ERROR` is explicit evidence of a file tracking/path/write problem; absence of the detailed file before `WORLD_STATE` is not.
8. Confirm the human receives none of the nine `wr2_wr_` bundles and no treasury grant.
9. In the audit block, inspect several neutral, allied, client, distant, and hostile AI factions. Every active AI should have a base selection; weak ones should have a catch-up selection as well.
10. Treat `commanded_armies` as the retained `main_rome` estimate, not engine readback. Verify that it equals broad land-army forces minus one presumed garrison force per owned region, clamped at zero, and that `garrison_armies` reports the subtracted estimate. For each AI, verify `army_goal = min(4 × regions, target_armies, 16)`, `army_shortfall` is nonnegative, and the estimated `army_units` and `full_armies` remain plausible. Then observe whether the AI recruits toward that goal over several turns. The legal fame ceiling remains 16; WR does not dynamically cap or spawn armies.
11. End at least one full turn and watch for a freeze during the faction sequence. Confirm exactly one new `STATE` line appears for the next human turn.
12. Save, exit to menu, reload, and verify the acknowledged tier popup does not repeat, bundles do not duplicate, treasury is not granted repeatedly within one turn, and the saved `last_development_turn` prevents a second province-development batch in that turn.
13. Enter a battle, return to campaign, and continue an AI turn.
14. At Tier 40+, compare `development_points_per_province`, `development_provinces`, `development_commands_ok`, `development_commands_failed`, `development_owner_skips`, `development_points_granted`, `development_status`, and `last_development_turn`. The eligible province total must deduplicate multi-settlement provinces, exclude every human province, and be processed at most once in the campaign turn. `_commands_ok` is protected call acceptance, not building-upgrade readback. Preserve any `partial_error` or `disabled_on_error` record; the saved turn high-water mark should still prevent an uncertain same-turn retry.
15. Damage or sabotage a building under construction, then repair, capture, and convert it. Confirm the `-7` construction-turn effect respects a one-turn floor and the new development surplus does not break repair or conversion state.
16. At a disposable Tier 85+ state, let the pair backlog reach zero, then open and close the Diplomacy panel repeatedly before ending the turn. Verify AI-to-AI peace, inability to declare ordinary AI wars, protected agreements, and accepted bidirectional `BEST_FRIENDS` promotions. `best_friend_promotions_ok` is protected command acceptance, not native stance readback or a numeric attitude write. At Tier 100, also check direct legal trade attempts and compare `ai_ai_avg` with `ai_human_avg` over scheduled audits. Historical AI attitudes may remain negative; do not expect or report a numeric `+300`. Confirm AI-to-human war and negotiation remain legal.
17. Test Normal first, then each intended campaign difficulty. Check construction and recruitment prices and upkeep for negative or nonsensical values.
18. Run at least 20 AI turns at high pressure and inspect the local diagnostics after every save/load and battle return. For the actual settlement-development balance test, start a new campaign and periodically inspect AI cities; development points do not instantly upgrade old structures. For a rotation test, use copied logs or a disposable run and confirm neither local file exceeds 1,000 lines and the newest history survives the 800-line compaction.
19. Only after the single-pack test passes, enable one Stable Politics preset and repeat cold load, first turn, and a complete end turn.

### Exact log interpretation

- No bootstrap file means either the pack's root loader did not run or the game could not write the file. Check launcher selection, stale `all_scripted.lua` owners, and Rome II's native script output before drawing a conclusion.
- `LOADER_START` proves this pack's root loader ran. `MODULE_PATH_READY` and `DIRECTOR_ROUTE_TRY` prove it selected the explicit `script/campaign/wr2/?.lua` route.
- `DIRECTOR_ROUTE_OK` and `DIRECTOR_REQUIRE_OK` prove the protected director import returned without a Lua error. They do **not** prove listener attachment. `DIRECTOR_ROUTE_ERROR` or `DIRECTOR_REQUIRE_ERROR` is a module-resolution or director-load failure.
- `DIRECTOR_API_ERROR` means the imported value did not expose the required `setup` function. `DIRECTOR_SETUP_ERROR` means its protected call raised unexpectedly.
- The loader's `EVENT_REGISTRY_READY` with detail `source=export_triggers` and the director's later record with detail `source=loader_argument` must report the same opaque registry identity. With `DIRECTOR_SETUP_TRY`, they prove the exact handoff began and was accepted. `EVENT_REGISTRY_INVALID` is a failed handoff.
- Six `LISTENER_OK_*` results, `LISTENERS_READY`, and `DIRECTOR_SETUP_OK` prove first attachment. On an idempotent repeated setup, six `LISTENER_REUSED_*` results are equally valid.
- `LISTENER_MISSING_*` or `LISTENER_INSERT_ERROR_*`, followed by `LISTENERS_PARTIAL` and `DIRECTOR_SETUP_PARTIAL`, is a failed attachment attempt. A later attempt must visibly recover the missing listener and reach the ready/OK outcomes.
- `EVENT_HIT_<name>` proves Rome II dispatched that event-table callback. `EVENT_ERROR_<name>` means its protected body failed and supplies the failure boundary.
- `ENGINE_WAIT` or `ENGINE_UNAVAILABLE_<name>` means no published interface was found at that attempt; a later lifecycle event retries. `ENGINE_READY` proves the interface was acquired and records which global/module source and event supplied it.
- `WORLD_ATTEMPT` is emitted for every initialization attempt. `WORLD_PROBE_FAIL` names an unavailable game/model/world/faction-list probe, `WORLD_UNSUPPORTED` means `campaign_name("main_rome")` returned false, and `WORLD_NO_HUMAN` means the world was readable but no human faction was detected. `WORLD_WAIT` repeats the reason. Until ready, the first delivered faction turn in each campaign turn retries regardless of the context faction's humanity. `WORLD_READY` proves that reconciliation completed.
- `WORLD_STATE` is the compact successful-reconciliation proof. It includes active AI, accepted base/catch-up bundle-command counts, treasury grant count/total, province-development totals/status, pressure/tier, and target armies.
- `DIAGNOSTIC_SINK_READY` proves the detailed file opened and wrote. `DIAGNOSTIC_SINK_ERROR` is a real path/permission/write failure and does not disable mechanics.
- `DIRECTOR_SETUP_OK` with no `EVENT_HIT_*` means attachment was accepted but no registered callback was observed. `LISTENERS_READY` and an event hit with no `WORLD_READY`, `WORLD_STATE`, or detailed `SESSION_START` means supported-world reconciliation did not complete; the reasoned world stages now identify why. If `WORLD_STATE` and `WORLD_READY` exist but the detailed file does not, inspect the diagnostic-sink milestone.
- A `SESSION_START` plus `STATE` proves the director completed a `main_rome` reconciliation and its protected calls returned; it does not independently read back native effect-bundle state.
- A detailed `STATE` with no status message isolates the problem to UI readiness/message display rather than the scaling reconciliation.

## Specific acceptance criteria

- The game reaches the campaign map from a cold process with only this pack enabled.
- For one load ID, the bootstrap trace reaches `DIRECTOR_ROUTE_OK`, `DIRECTOR_REQUIRE_OK`, matching loader/director `EVENT_REGISTRY_READY` identities, six successful/reused listener outcomes, `LISTENERS_READY`, `DIRECTOR_SETUP_OK`, an `EVENT_HIT_*`, `ENGINE_READY`, `WORLD_ATTEMPT`, `WORLD_STATE`, and `WORLD_READY`; the detailed trace then reaches `SESSION_START` and `STATE` after first tick or the guarded first-faction-turn-per-campaign-turn retry.
- The activation/tier message appears after successful reconciliation, never during `LoadingGame`, and an acknowledged tier does not repeat after reload.
- Each human turn produces at most one structured `STATE`; detailed audits include every active non-human faction exactly once and exclude the human and dormant factions.
- Both local logs remain at or below 1,000 lines; rotation retains the newest history, and a read/rewrite failure suppresses that file batch without suppressing native telemetry or gameplay.
- Exactly one base bundle and zero or one catch-up bundle exist on every active AI.
- No World Resistance bundle, treasury grant, stance promotion, forced treaty, or forced peace touches a human endpoint.
- Repeated loading and battle return do not accumulate base or catch-up tiers.
- Each eligible unique AI-owned province receives at most one tier-scaled development-point call per campaign turn; human provinces receive none, and a same-turn reload does not duplicate the batch.
- Every AI with non-negative prestige resolves to the 16-army final row while the human retains its normal cap progression; telemetry uses the clearly labeled region-subtracted `main_rome` army estimate and computes the per-AI regional goal without force spawning.
- At Tier 85 or above, ordinary AI-to-AI war/join-war is blocked, existing wars converge to peace, and both strategic directions receive `BEST_FRIENDS` promotion without a hard block, forced refresh, or blocker readback.
- The player remains a legal war target; AI-to-human hostility is not disabled.
- No turn-time freeze occurs while diplomacy pairs are processed in batches.
- No negative price, money-on-purchase, broken construction, or unrecoverable sabotage state appears.
- Over a new-campaign soak, AI settlements use the added development surplus without any claim that every building is automatically maxed or that CAI choices are prescribed.

## Save and removal guidance

A copied existing original Grand Campaign is supported for activation testing: 0.1.7 successfully reconciled and advanced one maximum-pressure save without the 0.1.6 Diplomacy-panel crash. A new campaign remains the supported **balance** starting point because an existing save cannot retroactively receive earlier research, construction, recruitment, province-development points, or diplomatic development. Mid-campaign installation/removal also remains a separate DB-cap risk.

When migrating directly from 0.1.6, prefer the last save made before 0.1.6 performed its pair reconciliation. Neither 0.1.7 nor 0.1.8 issues a speculative clear-all-blockers command.

Do not remove the pack and then overwrite your only save if an AI may own more armies than the restored cap. Keep a pre-mod save and the exact pack version together. If a test fails, disable the pack, restore the clean save, and report the last safe lifecycle point.

## Useful bug report

Include:

- Rome II branch/build shown by Steam;
- campaign name, faction, turn, and campaign difficulty;
- whether the campaign was new or existing;
- every enabled mod and launcher load order;
- exact `@wr2_world_resistance.pack` filename and SHA-256 from the release report;
- the last successful step: menu, campaign load, first turn, end turn, save/load, or battle return;
- the relevant `script_error` or modified log excerpt;
- all 0.1.8 `BOOT` lines for the same `load=` identifier from installation-root `wr2_world_resistance_bootstrap.log`;
- the `SESSION_START`, latest `STATE`, and surrounding `AI_AUDIT` lines from `data/wr2_world_resistance.log`;
- whether the failure reproduces with only World Resistance enabled from a clean process.
