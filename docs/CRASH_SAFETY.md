# Crash-safety notes

## What “safe” means here

No Rome II mod can be proven crash-safe by static analysis alone. Database decoding, Lua simulation, and protected calls catch many errors, but only the game can exercise native campaign code and CAI edge cases.

This beta is deliberately engineered to minimize the most common startup and campaign risks. Release 0.1.5 completed a successful native world reconciliation in the user's game, but 0.1.6 is not described as fully certified because the build environment has no Rome II executable/current `data.pack` dependency cache and the new field-army, stance-lock, and log-rotation paths still require a live soak.

## Structural safeguards

- One PFH4 mod pack; no movie pack, DLL, executable patch, startpos, or external runtime dependency.
- Unique `wr2_wr_` bundle and table namespaces.
- A small DB surface: custom effect-bundle rows, a narrow Grand Campaign fame-level override, and additive status-message rows/localization.
- Existing Rome II effect and scope keys only; no invented effect, bonus-value ID, or campaign scope.
- No copied `effects`, building, technology, difficulty, CAI personality, or startpos tables.
- RPFM-schema encoding and round-trip/static pack validation rather than guessed binary DB output.
- Six exclusive base bundles and three exclusive catch-up bundles. Old family members are removed before a new one is applied.
- Zero-value DB rows are omitted, finite values are bounded, and this mod's own cost-reduction contribution stops at `-90%`.

## Loader and lifecycle safeguards

Rome II loads `lua_scripts/all_scripted.lua` before campaign scripting. The included loader preserves all seven vanilla imports and assigns the vanilla event table before making one protected import of the World Resistance director.

The director no longer resides beside CA's engine scripts. It is packaged at the unique path `script/campaign/wr2/wr2_world_resistance.lua`. For the duration of one protected `require("wr2_world_resistance")`, the root loader prepends `script/campaign/wr2/?.lua` to `package.path`; it then restores Rome II's original path on both success and failure. This makes custom-module discovery explicit in each fresh Lua state without changing resolution for scripts or mods loaded afterward.

Before path setup, the root loader emits `LOADER_START` to `wr2_world_resistance_bootstrap.log` and Rome II's native output when available. Every 0.1.6 line carries an opaque per-loader `load` token. `MODULE_PATH_READY`, `DIRECTOR_ROUTE_TRY`, and `DIRECTOR_ROUTE_OK` identify the selected route; route and require errors preserve a longer sanitized diagnostic. The root logger is independent of director initialization, and all of its read/track/rewrite/open/write/flush/close and native-output operations are protected. If search, compilation, director execution, or bootstrap-file rotation raises a normal Lua error, the protected path leaves the vanilla loader alive. This cannot recover from a malformed DB file or a crash inside native engine code.

Import and listener setup are separate protected boundaries. After `DIRECTOR_REQUIRE_OK`, the loader verifies the returned `WR.setup` API and calls `director.setup(triggers.events)` using dot syntax and its exact local registry. The director immediately appends protected callbacks to the six required event arrays: `LoadingGame`, `SavingGame`, `UICreated`, `FirstTickAfterWorldCreated`, `FactionTurnStart`, and `FactionLeaderDeclaresWar`. It does not look up `_G.events`. Registration does not require `game_interface`, import `EpisodicScripting`, or wait for `NewSession`. Registry-scoped per-event guards keep repeated setup idempotent; a partial attempt can retry only the missing/failed insertions, while each callback retains its own `pcall` boundary and first-hit/error milestone.

The setup boundary is independently observable. The loader emits `EVENT_REGISTRY_READY` with detail `source=export_triggers` before import and the director emits a second record with detail `source=loader_argument` when it accepts the setup argument; their opaque registry identities must match. Those records, one `LISTENER_OK_*` or `LISTENER_REUSED_*` outcome per event, `LISTENERS_READY`, and `DIRECTOR_SETUP_OK` are required for accepted attachment. An invalid registry emits `EVENT_REGISTRY_INVALID`; missing arrays or protected insertion failures end in `LISTENERS_PARTIAL` plus `DIRECTOR_SETUP_PARTIAL`. An unexpected setup exception produces `DIRECTOR_SETUP_ERROR`, and a missing setup API produces `DIRECTOR_API_ERROR`. All fail closed so the vanilla loader can continue.

Interface attachment is lazy. At explicit setup and on each relevant event, WR reads the published `scripting` and `EpisodicScripting` globals and their known `package.loaded` aliases; it never forces CA's campaign module to load early. `ENGINE_WAIT|detail=director_setup` is therefore an expected early state, not a gate. A later event can record `ENGINE_READY` and continue even if the setup lookup failed.

World mutation remains deferred until a world-facing initialization edge. `LoadingGame` only restores six primitive named values and never changes bundles, treasuries, or diplomacy. `FirstTickAfterWorldCreated` is the normal first reconciliation. Supported-campaign detection uses the documented boolean predicate `model:campaign_name("main_rome")`. If initialization is incomplete, the first delivered `FactionTurnStart` in each campaign turn may retry regardless of whether its context is human or AI; the full scan identifies the human and rechecks every human-isolation guard before mutation. `WORLD_ATTEMPT`, `WORLD_PROBE_FAIL`/`WORLD_UNSUPPORTED`/`WORLD_NO_HUMAN`, `WORLD_WAIT`, `WORLD_STATE`, and `WORLD_READY` distinguish those outcomes. A same-session guard ignores duplicate first-tick initialization after new-game creation, load, or return from battle.

This architecture supersedes four observed defects. Release 0.1.1 could return permanently when the early interface was absent. Release 0.1.2 added a `NewSession` handoff, but kept the director under `lua_scripts` and relied on an ambient module route. Its first trace reached `LOADER_START` and then failed with `module 'lua_scripts.wr2_world_resistance' not found`, proving that this pack's root loader ran while the custom director did not. Release 0.1.3 fixed that route: two load IDs in the next live file reached `DIRECTOR_ROUTE_OK` and `DIRECTOR_REQUIRE_OK`. Neither reached `LISTENERS_READY`, because the imported director still tried to rediscover the loader's event registry through its own global environment. Release 0.1.4 removed that implicit boundary, and the latest live trace proves matching registry handoff, all six listeners, event dispatch, and interface acquisition. It also revealed that 0.1.4 treated `campaign_name` as a zero-argument string getter instead of Rome II's `campaign_name(key)` predicate, preventing reconciliation. All four failures occurred before supported-world mutation and cannot be attributed to an existing save or the DB-only No Civil War preset.

The 0.1.6 regression suite models an initially hostile ambient `package.path`, temporary explicit routing/restoration, a director environment without a shared `events` global, exact registry identity, partial setup/retry, lazy interface discovery, `campaign_name("main_rome")`, first-tick initialization, first-faction-turn recovery, garrison-safe field-army counting, regional mobilization goals, pair-scoped best-friend locks/readback, and bounded-log failures. The user's later 0.1.5 trace independently proves the route through successful native world reconciliation and detailed telemetry; the 0.1.6 deltas remain simulated until replayed in the game.

Every interface read and engine call is protected and fails closed for that target. Invalid faction keys and dormant zero-region/zero-force records are ignored. Diplomacy has an independent AI-only guard immediately before each pair call.

The status UI uses Rome II's documented `show_message_event(event_key, x, y)` path and proven vanilla message assets. It does not construct, search, divorce, replace, or patch UI components. The call waits for both `UICreated` and a successful world reconciliation, is protected, and is never made from `LoadingGame`.

The root bootstrap file and detailed campaign file are separate. Installation-root `wr2_world_resistance_bootstrap.log` can record route, event, interface, and world progress before detailed telemetry exists. The detailed stream, `data/wr2_world_resistance.log`, begins only while processing a successful supported-world reconciliation. `DIAGNOSTIC_SINK_READY` confirms that it opened and wrote; `DIAGNOSTIC_SINK_ERROR` explicitly reports a sink/tracking failure. Both files are hard-bounded at 1,000 lines and rotate to the newest 800-line tail (or a smaller detailed tail needed to fit the incoming batch). A tracking or rewrite failure skips that file record/batch rather than appending blindly; native `out.ting` output and mechanics continue. A direct detailed append/write/flush/close failure disables only that file sink for the Lua session.

## Performance safeguards

Pairwise diplomacy is potentially quadratic when many factions survive. The director processes at most 80 previously unreconciled pairs on the first tick or a human turn and 20 on an AI turn. Work resumes on later callbacks instead of issuing thousands of commands on one loading frame.

War-declaration handling resolves only the declaring AI and compares it with the active AI list. It does not run a full all-pairs audit inside the event.

Structured `STATE` output is limited to once per human turn. Detailed per-AI and aggregate diplomacy audits run only at session start, at a new tier high, and every tenth turn; pair-by-pair diplomacy is never written to the local file.

The script does not create forces. Force spawning, especially in invalid or occupied locations, is a known source of campaign instability and turn-sequence freezes. AI army parity is pursued through legal cap access, money, recruitment slots, rank, replenishment, and low costs. Release 0.1.6 counts only general-led land forces for parity; settlement garrisons remain separately observable. The comparison/reserve goal is `min(4 × regions, human parity target, 16)`, not a spawning order or dynamic cap rewrite. Consequently, Rome II's fielded-military power bar can remain low immediately after activation; accelerated recruitment is not instant parity.

## Why global building rewrites were rejected

Editing every `building_levels` row to force `create_time=1` would affect the human, overwrite DLC/current rows, enlarge the conflict surface, and couple the mod to building sabotage/repair state. Workshop users have reported one-turn building edits failing to apply consistently and, in one case, a sabotaged construction becoming unrepairable.

World Resistance instead applies the proven faction effect `rom_tech_module_engineering_construction` with observed values no lower than `-7`, leaving building records intact. The expected one-turn floor still requires live sabotage, repair, capture, and conversion tests.

## Why global CAI personality rewrites were rejected

Personality and treaty-value tables are not pair-specific to AI relationships and can also alter behavior toward the human. A Workshop report describes a diplomacy mod where a friendly neighbor declared war and then accepted cheap peace, illustrating that several CAI decision layers can disagree.

World Resistance uses pair-scoped script controls after checking that both endpoints are AI. At Tier 85+ it hard-blocks each AI-to-AI direction to `BEST_FRIENDS`, force-refreshes the pair, protects agreements, disables ordinary war/join-war offers, and repeatedly forces peace. The audited interface exposes current numeric attitudes for reading but no safe pair-specific numeric setter, so WR does not add a guessed `+300` or rewrite global personality/reputation tables. `best_friend_pair_commands_ok` records protected command acceptance; separate stance-block counters provide native readback when available. This is narrower and auditable, although a hard-coded incident could still bypass normal diplomacy temporarily.

## Relevant community failure reports

These reports are warnings, not controlled proof of root cause:

- [Getae – Total Cheat Mod 2.2](https://steamcommunity.com/sharedfiles/filedetails/?id=265516523): a user reported that most intended one-turn construction changes did not work even with no other mods.
- [Baktria – Total Cheat Mod 2.2](https://steamcommunity.com/sharedfiles/filedetails/?id=201497202): a user reported that a sabotaged building under construction could no longer be repaired.
- [Better Economic & Military Management AI](https://steamcommunity.com/sharedfiles/filedetails/?id=2742800090): a comment describes apparently contradictory war and peace behavior despite good relations.
- [Para Bellum clean-install troubleshooting](https://steamcommunity.com/workshop/filedetails/discussion/2010751524/4747300038104744049/): warns that Workshop and Rome II cache state can survive an apparent unsubscribe.
- [Rome II outdated-mod discussion](https://steamcommunity.com/app/214950/discussions/0/38596747932133585/): reports recovery after removing stale packs and resubscribing.

These findings shaped the clean-test requirement, minimal DB surface, protected loader, pair-scoped diplomacy, and construction repair test. They do not establish that every reported problem had the same cause.

The separately inspected [Stable Politics: No Civil War](https://github.com/daveshap/RTW2_No_Civil_War) preset is a single DB-table fragment and contains no Lua loader, army-cap rows, or overlapping World Resistance key. It is therefore expected to coexist with 0.1.6 and cannot explain the 0.1.1 missing-interface retry, 0.1.2 module-route, 0.1.3 registry-handoff, or 0.1.4 campaign-predicate defects. The combination still needs the same live first-turn/end-turn smoke test as any two-pack setup.

## Residual risks that need the game

1. **Fame-level resolution.** The AI-only negative prestige-threshold strategy is structurally valid and avoids spawning, but must be observed in a current Grand Campaign. The game must give AI factions the final 16-army row while leaving human progression unchanged. The pack intentionally uses the decoded, backward-compatible v4 Grand Campaign row shape. Converting it to another schema version without first extracting the matching live `main_rome` rows would replace verified fields with assumptions.
2. **Current foreign keys.** The selected effect/scope pairs decode from real Rome II packs and match the current RPFM schema, but a live dependency-cache check against the installed current `data.pack` remains the strongest gate.
3. **External stacking.** `-90%` may combine with campaign-difficulty or other modifiers below `-100%`.
4. **Construction floor.** A negative seven-turn effect is evidenced; exact one-turn clamping and repair behavior are empirical.
5. **Native diplomacy behavior.** `pcall` can catch a bad Lua binding call, not a crash inside native code. The best-friend block/refresh methods are present in the current Rome II dump and official sibling-engine interface, but odd/emergent factions and alliance formation need soak testing. Numeric historical attitudes may remain negative because no pair-specific attitude setter exists.
6. **Scripted wars.** Campaign incidents can potentially bypass ordinary treaty permissions; repeated peace enforcement should close them but needs observation.
7. **Loader ownership.** Another enabled mod that replaces `all_scripted.lua` can silently prevent one director from loading or can remove vanilla imports. A missing 0.1.6 `LOADER_START` in a writable installation is the first indicator of that condition; the `load` token, route milestones, and explicit setup outcome distinguish separate loader evaluations once this loader is selected.
8. **PANTHEON/JUPITER.** New official rules may invalidate campaign, schema, Imperium, and army-cap assumptions.
9. **Message localization.** The additive Loc file is English and covers the four proven Rome II culture keys. Other client languages need a live display test; missing text should be cosmetic, but has not been observed here.
10. **Local file permissions and rotation.** A protected game install may reject reads, rewrites, or appends for either local log. Tracking/rotation failures skip file output rather than exceeding the hard ceiling, and both streams also attempt native `out.ting`, but the 1,000/800 behavior still needs live observation.

## Recovery if a test fails

1. Do not overwrite the only copy of the affected save.
2. Close Rome II completely.
3. Disable World Resistance in the launcher and move only `@wr2_world_resistance.pack` out of the game's `data` directory.
4. Check for stale copies with similar names and for subscribed Workshop versions that the launcher may still activate.
5. Launch a clean vanilla Grand Campaign from a fresh process. If vanilla also fails, the problem is not isolated to this pack.
6. Restore the pre-mod save rather than continuing a save that may contain AI forces above the vanilla cap.
7. Report the exact lifecycle point and logs using the template in [Compatibility and testing](COMPATIBILITY_AND_TESTING.md#useful-bug-report).

Do not delete broad Steam, game, or user-data directories while troubleshooting. Isolate the exact pack first.
