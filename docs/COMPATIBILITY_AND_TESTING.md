# Compatibility and testing

## Supported target

| Environment | Status |
|---|---|
| Current public pre-PANTHEON Rome II | Targeted |
| Grand Campaign (`main_rome`) | Targeted |
| New single-player campaign | Strongly recommended |
| Existing save | Not certified |
| Multiplayer / co-op | Defensive handling exists, but balance and lifecycle are unsupported |
| DLC and mini-campaigns | Unsupported; the director becomes inert outside `main_rome` |
| PANTHEON/JUPITER branch | Unsupported; requires a separate build |

Creative Assembly has announced that PANTHEON will change Rome II over a series of updates, and JUPITER specifically revisits buildings and army/navy/agent-cap sources. This release intentionally targets the public pre-PANTHEON rules rather than guessing at an unreleased final cap model. Its `fame_levels` table uses the backward-compatible v4 Grand Campaign row shape verified in decoded stable packs. RPFM also knows later table layouts, but those definitions predate the PANTHEON announcement and are not labelled here as future formats.

The installable filename is `@wr2_world_resistance.pack`. The leading `@` is intentional: it improves recognition of a manually installed local pack by the current Rome II launcher. Remove or disable the old unprefixed `wr2_world_resistance.pack`; keeping both copies makes it impossible to know which release the launcher selected.

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

Rome II's `all_scripted.lua` does not have a safe automatic multi-mod append mechanism. A compatibility patch must preserve the seven vanilla imports, assign `events = triggers.events`, and protected-load both mods after that assignment. World Resistance 0.1.4 must also receive the exact shared registry through `director.setup(triggers.events)`; merely assigning an `events` global is not a verified cross-module handoff.

The inspected Stable Politics presets do not replace `all_scripted.lua` and do not share a primary key with World Resistance. Their relative launcher order should therefore be immaterial. Complete the World Resistance-only smoke test first, then enable exactly one Stable Politics preset and repeat the first-turn/end-turn check; this remains a compatibility expectation until both packs have been exercised together in a live Rome II installation.

## 0.1.1–0.1.3 startup defects and 0.1.4 repair

Release 0.1.1 imported the director before Rome II had exposed `scripting.game_interface`. When the interface was absent, the adapter returned without registering its campaign listeners and had no retry path. That made the mod silent and mechanically inert on both a new campaign and a loaded campaign. Starting a new campaign could not repair that defect.

Release 0.1.2 kept the root loader alive but assumed that appending a function to `events.NewSession` would run after Rome II published `game_interface`. The first native bootstrap trace reached `ENGINE_WAIT` without completing that hand-off. A subsequent fresh campaign Lua state also failed to resolve the custom `lua_scripts.wr2_world_resistance` module. Starting a new campaign could not make either loader assumption reliable.

Release 0.1.3 fixed the module route: its loader temporarily prepended `script/campaign/wr2/?.lua`, required the simple module name, and restored the prior path. The second native trace confirms that route succeeded in two separate 0.1.3 load IDs. Both blocks nevertheless stopped after `DIRECTOR_REQUIRE_OK`, with no `LISTENERS_READY` or event hit. The director had attempted to find `events` through its own `_G`; the live runtime did not demonstrate that the root loader's global assignment was visible in that imported environment.

Release 0.1.4 preserves the proven route but adds an explicit API boundary. The imported module returns `WR`, the loader checks its `setup` function, and calls `director.setup(triggers.events)` with dot-call semantics. Listener registration uses only that argument and records the registry identity; it does not rediscover `_G.events`. Setup remains independent of `game_interface`. Every registered callback lazily checks the campaign-owned global and already-loaded module variants for the interface. `FirstTickAfterWorldCreated` remains the normal activation edge; if the interface or world is still unavailable, the first human `FactionTurnStart` retries initialization. `LoadingGame` remains read-only, and no bundle, treasury, or diplomacy mutation occurs before successful world initialization.

The 0.1.4 regression simulation isolates the director from a global `events` value, verifies that the exact `triggers.events` argument receives all six callbacks, and covers repeated setup, partial registration, retry without duplicates, delayed-interface recovery, the existing-save path, and rejection of an AI-turn fallback. This is still simulated evidence. The build environment has no runnable Rome II executable.

## Why Normal campaign difficulty is the initial target

World Resistance caps its own construction, recruitment, upkeep, and mercenary reductions at `-90%`. Vanilla campaign difficulty, technologies, buildings, characters, and another mod can add to the same scalar. Patch-17 vanilla-derived evidence includes AI upkeep modifiers down to roughly `-30%` and unit-cost modifiers down to roughly `-25%`.

The database accepts a finite value below `-100`, but that does not establish safe economic behavior. Start on Normal. Harder campaign difficulties must be tested for zero/negative prices and unexpected payments before being recommended.

## Verification completed without the game

The source was designed and checked against:

- the current RPFM Rome II schema snapshot and exact table field types;
- real decoded PFH4 Rome II Workshop rows for all selected effect/scope pairs;
- a current Rome II scripting API and event dump;
- Rome II's evidenced `all_scripted.lua` → campaign `scripting.lua` load order, an explicit pack-local module path, an explicit `triggers.events` argument handoff, and lazy interface discovery;
- Rome II's documented three-argument custom message-event path and a working Workshop implementation exported through RPFM;
- Lua 5.1 syntax and pure/mocked simulations, including no-interface import, delayed interface publication, first-human-turn recovery, all-faction eligibility, and the no-human-diplomacy invariant;
- deterministic PFH4 structure tests and pack round-trip tooling.

These checks reduce guessed-key and malformed-pack risk. They cannot verify native engine behavior. This environment does not contain the paid Rome II data depot, Assembly Kit dependency cache, or a runnable Rome II executable, so this beta has **not** completed a real frontend cold boot, first turn, end turn, battle return, or soak test.

Treat any generated validation report as structural evidence, not an in-game certification.

## Required live smoke test

Use a disposable profile or backed-up saves. Test with no other mods before combining anything.

1. Close Rome II. Remove or disable every older World Resistance copy, especially unprefixed `wr2_world_resistance.pack`, and archive the two old log files so this run starts with unambiguous evidence.
2. Put `@wr2_world_resistance.pack` in `data` and enable only that pack.
3. Cold-start to the main menu. A failure before the menu points first to pack/schema/loader conflicts.
4. Start a new original Grand Campaign and reach the first human turn.
5. Open `wr2_world_resistance_bootstrap.log` in the Rome II installation root, one directory above `data`. For release 0.1.4, one load ID must contain `LOADER_START`, loader-owned `EVENT_REGISTRY_READY` with detail `source=export_triggers`, `MODULE_PATH_READY`, `DIRECTOR_ROUTE_TRY`, `DIRECTOR_ROUTE_OK`, `DIRECTOR_REQUIRE_OK`, `DIRECTOR_SETUP_TRY`, director-owned `EVENT_REGISTRY_READY` with detail `source=loader_argument`, all six `LISTENER_OK_*` stages, `LISTENERS_READY`, and `DIRECTOR_SETUP_OK`. The opaque `registry=` identity in the two ready lines must match. After campaign dispatch begins it must also reach an `EVENT_HIT_*`, `ENGINE_READY`, and `WORLD_READY`. An early `ENGINE_WAIT|detail=director_setup` is expected when `all_scripted.lua` precedes the campaign interface; it is only a failure if no later event reaches `ENGINE_READY`.
6. Confirm a **WORLD RESISTANCE ACTIVE** message appears only after the campaign map finishes reconciling.
7. Open `data/wr2_world_resistance.log`. Confirm it contains one `SESSION_START`, one `STATE`, and an `AI_AUDIT_BEGIN`/`AI`/`AI_AUDIT_END` block for the current turn. This detailed file is deliberately not created until a supported world has reconciled successfully.
8. Confirm the human receives none of the nine `wr2_wr_` bundles and no treasury grant.
9. In the audit block, inspect several neutral, allied, client, distant, and hostile AI factions. Every active AI should have a base selection; weak ones should have a catch-up selection as well.
10. Confirm an AI can legally raise armies toward the 16-army cap without any spawned or duplicate force.
11. End at least one full turn and watch for a freeze during the faction sequence. Confirm exactly one new `STATE` line appears for the next human turn.
12. Save, exit to menu, reload, and verify the acknowledged tier popup does not repeat, bundles do not duplicate, and treasury is not granted repeatedly within one turn.
13. Enter a battle, return to campaign, and continue an AI turn.
14. Damage or sabotage a building under construction, then repair, capture, and convert it. Confirm the `-7` construction-turn effect respects a one-turn floor and does not break repair state.
15. At a disposable high-pressure state, verify a new tier popup, AI-to-AI peace, inability to declare ordinary AI wars, protected agreements, and direct legal trade attempts. Also verify AI can still declare war on and negotiate with the human normally.
16. Test Normal first, then each intended campaign difficulty. Check construction and recruitment prices and upkeep for negative or nonsensical values.
17. Run at least 20 AI turns at high pressure and inspect the local diagnostics after every save/load and battle return.
18. Only after the single-pack test passes, enable one Stable Politics preset and repeat cold load, first turn, and a complete end turn.

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
- `WORLD_WAIT` means first-tick reconciliation could not yet see a supported world; only the first human faction turn may retry one-time initialization. `WORLD_READY` proves that reconciliation completed.
- `DIRECTOR_SETUP_OK` with no `EVENT_HIT_*` means attachment was accepted but no registered callback was observed. `LISTENERS_READY` and an event hit with no `WORLD_READY` or detailed `SESSION_START` after first tick and the first human turn means supported-world reconciliation did not complete, or the detailed file could not be written. Check native `out.ting` output for the reason.
- A `SESSION_START` plus `STATE` proves the director completed a `main_rome` reconciliation and its protected calls returned; it does not independently read back native effect-bundle state.
- A detailed `STATE` with no status message isolates the problem to UI readiness/message display rather than the scaling reconciliation.

## Specific acceptance criteria

- The game reaches the campaign map from a cold process with only this pack enabled.
- For one load ID, the bootstrap trace reaches `DIRECTOR_ROUTE_OK`, `DIRECTOR_REQUIRE_OK`, matching loader/director `EVENT_REGISTRY_READY` identities, six successful/reused listener outcomes, `LISTENERS_READY`, `DIRECTOR_SETUP_OK`, an `EVENT_HIT_*`, `ENGINE_READY`, and `WORLD_READY`; the detailed trace then reaches `SESSION_START` and `STATE` after first tick or the guarded first-human-turn retry.
- The activation/tier message appears after successful reconciliation, never during `LoadingGame`, and an acknowledged tier does not repeat after reload.
- Each human turn produces at most one structured `STATE`; detailed audits include every active non-human faction exactly once and exclude the human and dormant factions.
- Exactly one base bundle and zero or one catch-up bundle exist on every active AI.
- No World Resistance bundle, treasury grant, stance promotion, forced treaty, or forced peace touches a human endpoint.
- Repeated loading and battle return do not accumulate base or catch-up tiers.
- Every AI with non-negative prestige resolves to the 16-army final row while the human retains its normal cap progression.
- At Tier 85 or above, ordinary AI-to-AI war/join-war is blocked and existing AI-to-AI wars converge to peace.
- The player remains a legal war target; AI-to-human hostility is not disabled.
- No turn-time freeze occurs while diplomacy pairs are processed in batches.
- No negative price, money-on-purchase, broken construction, or unrecoverable sabotage state appears.

## Save and removal guidance

A new campaign is the only supported starting point for this beta. The Lua director is written to reconcile an existing save, but DB cap behavior and already-created AI forces make mid-campaign installation/removal a separate risk.

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
- all 0.1.4 `BOOT` lines for the same `load=` identifier from installation-root `wr2_world_resistance_bootstrap.log`;
- the `SESSION_START`, latest `STATE`, and surrounding `AI_AUDIT` lines from `data/wr2_world_resistance.log`;
- whether the failure reproduces with only World Resistance enabled from a clean process.
