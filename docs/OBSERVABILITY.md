# Observability and local diagnostics

World Resistance 0.1.6 exposes module resolution, explicit event-registry handoff, listener registration, lazy engine discovery, event delivery, campaign probing, command processing, field-army mobilization, directional diplomatic attitudes, and diagnostic-file health as separate signals. This is deliberately not remote telemetry: the pack contains no network code and uploads nothing.

## Bootstrap file

The root `all_scripted.lua` loader owns a small rolling bootstrap stream. In a normal Steam installation its relative path resolves in the Rome II installation root, one directory above the installed pack:

```text
...\Total War Rome II\wr2_world_resistance_bootstrap.log
```

The root logger starts before the director import, so it can report a module-route or setup failure even when the detailed campaign logger never starts. A 0.1.6 line has this shape:

```text
WR2|schema=1|event=BOOT|release=0.1.6-beta|load=table: 01234567|stage=LOADER_START
```

`load` is an opaque token created for one evaluation of `all_scripted.lua`. Use it only to group lines from the same loader evaluation; it is not a campaign ID and is not persisted. This removes the ambiguity in older traces, where adjacent blocks could have come from different Lua states or game launches.

The bootstrap file has a hard ceiling of 1,000 lines. At the next append after it reaches that size, the logger rewrites the newest 800 lines and then appends the new record. It scans and tracks the file under protected calls; if safe tracking or rewrite is unavailable, that file record is skipped while native output and the vanilla loader continue.

### Loader and route milestones

| Stage | What it establishes | What it does not establish |
|---|---|---|
| `LOADER_START` | The seven preserved vanilla imports completed and this pack's loader section ran | The custom director was found |
| `EVENT_REGISTRY_READY` with `source=export_triggers` | The root loader holds the registry returned by its local vanilla import | The director received that object |
| `MODULE_PATH_READY` | The unique `script/campaign/wr2/?.lua` template was temporarily prepended | The module exists or compiles |
| `DIRECTOR_ROUTE_TRY` | The loader attempted the simple module key `wr2_world_resistance` | The attempt succeeded |
| `DIRECTOR_ROUTE_OK` | The protected `require` returned without a Lua error through that explicit route | A supported campaign world was ready |
| `DIRECTOR_ROUTE_ERROR` | Module search, compilation, or director execution failed safely | Which native game state would otherwise have followed |
| `DIRECTOR_REQUIRE_OK` | The protected import returned the director table | Any event registry was handed off or any listener attached |
| `DIRECTOR_REQUIRE_ERROR` | The root loader retained the final sanitized import error and continued fail-closed | That the error came from another mod |
| `DIRECTOR_API_ERROR` | The imported value did not expose the required `setup` function | That the module route itself failed |
| `DIRECTOR_SETUP_TRY` | The loader called `director.setup(triggers.events)` with the exact locally imported registry | That all six event arrays accepted callbacks |
| `DIRECTOR_SETUP_OK` | Setup returned ready after confirming all six listeners on that registry | That Rome II has dispatched a callback |
| `DIRECTOR_SETUP_PARTIAL` | Setup returned not ready because at least one event was missing or rejected insertion | That a later retry cannot recover |
| `DIRECTOR_SETUP_ERROR` | The protected setup call raised unexpectedly | That vanilla campaign loading was unwound |

The loader restores Rome II's original `package.path` immediately after the protected import, on both success and failure. The custom path therefore cannot change resolution for campaign scripts loaded afterward.

### Registry, listener, event, interface, and world milestones

| Stage | Meaning |
|---|---|
| `EVENT_REGISTRY_READY` with `source=loader_argument` | The director accepted the explicit registry argument; its opaque `registry` value should match the loader-owned record |
| `EVENT_REGISTRY_INVALID` | Setup received a non-table registry and cannot attach all listeners |
| `LISTENER_OK_<name>` | This setup attempt inserted the protected callback for that event |
| `LISTENER_REUSED_<name>` | That exact registry already held WR's callback for the event; no duplicate was inserted |
| `LISTENER_MISSING_<name>` | The named event array was unavailable in the supplied registry |
| `LISTENER_INSERT_ERROR_<name>` | Protected insertion into the named event array failed |
| `LISTENERS_READY` | All six required listeners are confirmed on the supplied registry |
| `LISTENERS_PARTIAL` | Fewer than six listeners are confirmed; the detail reports the count and a later setup may retry |
| `EVENT_HIT_<name>` | That event reached WR at least once in this director load |
| `EVENT_ERROR_<name>` | The protected callback raised a Lua error; the detail contains the sanitized error |
| `ENGINE_WAIT` | No live game interface was discoverable during the first lazy lookup; this is normally emitted at `director_setup` |
| `ENGINE_UNAVAILABLE_<name>` | A later event still could not find the interface; another event remains eligible to retry |
| `ENGINE_READY` | WR found `game_interface`; detail identifies the global or `package.loaded` source and the event that found it |
| `WORLD_ATTEMPT` | One initialization attempt began; detail includes an incrementing attempt number and its event source |
| `WORLD_PROBE_FAIL` | The game/model/world/faction-list probe failed; detail gives the exact source and reason |
| `WORLD_UNSUPPORTED` | The world was readable, but `model:campaign_name("main_rome")` returned false |
| `WORLD_NO_HUMAN` | The supported world was readable, but its faction scan found no human; detail includes faction and active-AI counts |
| `WORLD_WAIT` | This attempt did not initialize; detail repeats the source and exact failure reason |
| `WORLD_STATE` | Reconciliation succeeded; detail summarizes campaign, turn, human, active AI, pressure/tier, accepted bundle commands, treasury grants, and target armies |
| `DIAGNOSTIC_SINK_READY` | The detailed `data/wr2_world_resistance.log` sink opened and wrote successfully |
| `DIAGNOSTIC_SINK_ERROR` | The detailed sink failed to open/write/flush/close; mechanics remain enabled and native/bootstrap diagnostics continue |
| `WORLD_READY` | A supported `main_rome` world completed its first reconciliation |

Event-hit and final-ready milestones are emitted once per stage in a director load, so `EVENT_HIT_FactionTurnStart` proves at least one delivery rather than counting every turn. `WORLD_ATTEMPT`, its reasoned result, `WORLD_WAIT`, and `WORLD_STATE` are not once-only: retries remain visible. Each callback is independently protected, so `EVENT_ERROR_*` records a contained Lua failure instead of allowing it to unwind through Rome II's dispatcher.

Listener registration does not wait for `game_interface`, import `EpisodicScripting`, or depend on `NewSession`. After importing the director, the root loader explicitly passes its local `triggers.events` object to `WR.setup(event_registry)`. The director appends callbacks for `LoadingGame`, `SavingGame`, `UICreated`, `FirstTickAfterWorldCreated`, `FactionTurnStart`, and `FactionLeaderDeclaresWar` to that argument. It does not rediscover the registry through `_G.events`. Each callback lazily checks the published `scripting` and `EpisodicScripting` globals and their known `package.loaded` aliases.

A normal first setup should progress through `LOADER_START`, loader-owned `EVENT_REGISTRY_READY` with detail `source=export_triggers`, route success, `DIRECTOR_REQUIRE_OK`, `DIRECTOR_SETUP_TRY`, director-owned `EVENT_REGISTRY_READY` with detail `source=loader_argument`, six `LISTENER_OK_*` stages, `LISTENERS_READY`, and `DIRECTOR_SETUP_OK`. The opaque registry identity in the two ready records should match. An early `ENGINE_WAIT|detail=director_setup` is expected before the final setup result when the interface is not yet published. The decisive runtime sequence is a later event hit, `ENGINE_READY`, `WORLD_ATTEMPT`, `WORLD_STATE`, and finally `WORLD_READY`. A normal writable install also emits `DIAGNOSTIC_SINK_READY` before `WORLD_STATE`.

On a repeated setup against the same registry, `LISTENER_REUSED_*` replaces `LISTENER_OK_*`; this is successful idempotence, not a warning. `LISTENERS_PARTIAL` plus `DIRECTOR_SETUP_PARTIAL` is not accepted as attachment. A later retry must visibly succeed for each previously missing/failed event and end at `LISTENERS_READY` plus `DIRECTOR_SETUP_OK`.

The loader also sends every bootstrap line through Rome II's `out.ting` sink when available, with a protected `print` fallback. A missing file alone cannot distinguish "pack did not load" from "installation directory was not writable."

## Detailed campaign file

The structured campaign stream remains at:

```text
data/wr2_world_resistance.log
```

It is deliberately opened only after `FirstTickAfterWorldCreated`, or a later per-campaign-turn faction-turn fallback, has collected and processed a supported `main_rome` world. Each line retains the stable pipe-delimited schema:

```text
WR2|schema=1|event=STATE|release=0.1.6-beta|director=8|key=value|...
```

Carriage returns, newlines, tabs, and pipe characters are removed from values. String fields are length-limited. The file is opened, appended, flushed, and closed for each batch so it can be inspected while Rome II is running.

The detailed file also has a hard ceiling of 1,000 lines. Before a batch would exceed it, WR rewrites up to the newest 800 existing lines, reducing that tail when necessary to leave room for the complete incoming batch. If it cannot read/count the existing lines or safely finish the rewrite, it skips that file batch rather than appending beyond the ceiling. Native `out.ting` telemetry and every campaign mutation continue, and a later callback may retry.

| Event | Frequency | Purpose |
|---|---|---|
| `SESSION_START` | First successful reconciliation in a Lua session | Release, campaign, human faction, turn, path, and local-only declaration |
| `STATE` | At most once per human turn, plus the initial session state | Inputs, corrected human field-army metrics, pressure/tier, aggregate AI mobilization/goals, catch-up distribution, accepted bundle commands, treasury grants, pair backlog, accepted best-friend pair commands, and peace work |
| `AI_AUDIT_BEGIN` / `AI_AUDIT_END` | Session start, tier escalation, and every tenth turn | Bounds and aggregate checks for a detailed audit block |
| `DIPLOMACY_AUDIT` | Once inside every detailed audit block | Directional AI-to-AI and AI-to-human attitude count/minimum/average/maximum, native stance-block readback, accepted best-friend pair-command count, and total pairs |
| `AI` | Once per active AI inside an audit block | Regions, general-led field armies, garrisons, army units, 20-unit full stacks, mobilization goal/shortfall, treasury target/grant, catch-up, selected bundles, and command status |
| `UI_NOTICE` | When a tier message command succeeds | Event key, tier, turn, and pressure |
| `AI_WAR_SUPPRESSED` | At most once per declaring AI per turn | Number of protected peace commands issued after a declaration |

The four catch-up counts in `STATE` and `AI_AUDIT_END` must sum to `active_ai`. `base_commands_ok` and `catchup_commands_ok` should also equal `active_ai` after a clean reconciliation. `ai_commanded_armies` is the sum of general-led AI land forces, `ai_army_goal` is the sum of each faction's `min(4 × regions, human parity target, 16)` goal, `ai_full_armies` counts those field armies with at least 20 units, and `ai_factions_at_army_goal` counts factions with no goal shortfall.

The bootstrap `WORLD_STATE` carries the most important activation totals even if the detailed file cannot be used: `active_ai`, `base_ok`, `catchup_ok`, `grant_count`, `grant_total`, pressure/tier, and `target_armies`. It does not replace the per-faction `AI` records, but it makes “the world reconciled and commands were attempted” observable at the bootstrap layer.

`base_command_ok=true` means the protected Rome II call returned without a Lua exception and the director cached the requested selection. It does **not** mean the value was read back from the engine: the audited Rome II faction interface provides no effect-bundle query.

`peace_commands` similarly counts accepted peace commands, not independently proven treaty transitions. `best_friend_pair_commands_ok` counts AI pairs for which the protected block-and-refresh commands were accepted; it is not native readback of the resulting stance. `stance_block_checks` and `stance_blocked_directions` in `DIPLOMACY_AUDIT` are the separate native readback counters. Verify important outcomes in the campaign UI during the live smoke test.

`ai_ai_*` and `ai_human_*` are read from directional `faction_attitudes()` maps. They let a playtest compare whether AI-to-AI attitudes improve relative to AI-to-human attitudes, but WR does not write these numbers. The audited interface has no safe pair-specific numeric attitude setter, so the log must not be interpreted as proof of a hidden `+300` relation modifier.

## In-game status

The first successful Grand Campaign reconciliation queues a standard Rome II message for the current resistance tier. Another message appears only when a higher tier is reached. The highest acknowledged tier is saved as an integer, so loading, returning from battle, or temporarily losing territory does not repeat old messages.

The six status messages correspond to pressure bands 0, 20, 40, 65, 85, and 100. They use the official three-argument Rome II `show_message_event(event_key, 0, 0)` interface, additive DB rows, and existing vanilla image/icon/audio assets. The mod never edits the UI component tree.

The status message is attempted only after both `UICreated` and successful world reconciliation. It is never invoked during `LoadingGame`. A missing message API or localization failure cannot authorize any additional campaign mutation.

## Reading a 0.1.6 smoke test

- No bootstrap file: the pack's loader may not have run, another `all_scripted.lua` may have won, an old pack may be selected, or file access may be blocked. Check the launcher and native script output.
- `LOADER_START` without `MODULE_PATH_READY`: the preserved loader ran, but its path setup failed before the director route was attempted.
- `DIRECTOR_ROUTE_ERROR` / `DIRECTOR_REQUIRE_ERROR`: the pack's loader ran, but module search, compilation, or director execution failed safely. The shared `load` token identifies the relevant block.
- `DIRECTOR_REQUIRE_OK` without `DIRECTOR_SETUP_TRY`: the module imported, but the loader did not begin the required API handoff.
- `DIRECTOR_API_ERROR`: the module route worked, but the returned value does not implement the setup contract.
- `DIRECTOR_SETUP_TRY` without a second `EVENT_REGISTRY_READY` whose detail begins `source=loader_argument`: setup did not accept the registry argument; inspect `EVENT_REGISTRY_INVALID`, `DIRECTOR_SETUP_ERROR`, and native output.
- `LISTENER_MISSING_*` or `LISTENER_INSERT_ERROR_*`: at least one event failed registration. `LISTENERS_PARTIAL` and `DIRECTOR_SETUP_PARTIAL` are the expected aggregate results and are not acceptance.
- `LISTENERS_READY` plus `ENGINE_WAIT`: expected during early setup. Continue until a campaign event is delivered.
- `EVENT_HIT_<name>` plus `ENGINE_UNAVAILABLE_<name>` and no later `ENGINE_READY`: WR receives events, but Rome II has not published the interface through any known global/cache route.
- `ENGINE_READY` with no `WORLD_ATTEMPT`: no world-facing activation callback reached initialization. Inspect event sequence and any `EVENT_ERROR_*`.
- `WORLD_ATTEMPT` followed by `WORLD_PROBE_FAIL`: inspect the named `game_unavailable`, `model_unavailable`, `world_unavailable`, or `faction_list_unavailable` reason. The next campaign turn can retry.
- `WORLD_UNSUPPORTED`: `model:campaign_name("main_rome")` returned false. Confirm this is the original Grand Campaign, not Augustus, Empire Divided, Rise of the Republic, or another DLC campaign.
- `WORLD_NO_HUMAN`: the scan was readable but did not find a human faction; preserve the trace for API/lifecycle diagnosis.
- `WORLD_WAIT`: initialization failed for the reason on the same line. Until success, the first delivered `FactionTurnStart` in each campaign turn retries whether its context faction is human or AI.
- `WORLD_STATE` and `WORLD_READY`: supported-world reconciliation and protected command processing completed. Read the counts rather than inferring activation from the diplomacy power bar.
- `DIAGNOSTIC_SINK_ERROR`: the detailed file really did fail. `WORLD_STATE` still exposes compact activation totals and mechanics continue.
- `WORLD_READY` with no detailed `SESSION_START`: check `DIAGNOSTIC_SINK_READY`/`DIAGNOSTIC_SINK_ERROR`; do not infer path failure merely from file absence.
- `SESSION_START` plus `STATE`: the director reconciled the supported world and its protected commands returned. This is strong proof that the script is active, but not native-state readback.
- `AI` records with high `garrison_armies` but low `commanded_armies`: expected for small factions. Only the latter consumes the field-army comparison target. Use `army_goal`, `army_shortfall`, `army_units`, and `full_armies` to watch mobilization over multiple turns.
- `DIPLOMACY_AUDIT`: compare AI-to-AI and AI-to-human aggregates over successive scheduled audits. At Tier 85+, `stance_blocked_directions` should approach the number of successfully readable AI-to-AI directions after the pair backlog reaches zero. `best_friend_pair_commands_ok` remains command acceptance, not that readback.
- `STATE` with no campaign message: campaign reconciliation worked; investigate `UICreated`, the custom event rows/localization, or message display.

On a loaded save, the callbacks already exist before campaign lifecycle events begin. `LoadingGame` restores the six primitive named values when the interface is discoverable and remains read-only. `FirstTickAfterWorldCreated` is the normal first reconciliation edge. If the interface or world was not ready then, the first faction-turn callback in each campaign turn retries until success; it need not be the human's turn because the world scan independently locates and protects the human. A new campaign is therefore not required merely for the script to register, although it remains the only supported balance/army-cap starting point.

## What the attached live traces proved

The first live bootstrap trace contained an earlier 0.1.2 `DIRECTOR_REQUIRE_OK` block and a later block ending with:

```text
WR2|schema=1|event=BOOT|release=0.1.2-beta|stage=LOADER_START
WR2|schema=1|event=BOOT|release=0.1.2-beta|stage=DIRECTOR_REQUIRE_ERROR|detail=module 'lua_scripts.wr2_world_resistance' not found
```

Because the file was append-only and 0.1.2 had no load token or timestamp, those blocks cannot safely be treated as one continuous session. The later `LOADER_START` nevertheless proves that WR's `all_scripted.lua` was selected and all seven preceding vanilla imports completed. Its next operation failed while resolving the unqualified custom `lua_scripts` module, before the director could register listeners or inspect a save. The trace therefore did **not** implicate the existing campaign, `NewSession`, or the DB-only No Civil War mod.

Release 0.1.3 addressed that module-route boundary: the director moved to the unique `script/campaign/wr2/` path, the loader temporarily supplied that exact search template, and route/load milestones gained an opaque load token.

The second attached file retains those historical 0.1.2 lines and then contains two independent 0.1.3 blocks. Both reach:

```text
LOADER_START
MODULE_PATH_READY
DIRECTOR_ROUTE_TRY
ENGINE_WAIT
DIRECTOR_ROUTE_OK
DIRECTOR_REQUIRE_OK
```

Neither reaches `LISTENERS_READY` or an `EVENT_HIT_*`. Read by load ID, this proves that the explicit route found and executed the director in two Lua states while attachment still failed. `ENGINE_WAIT` is expected before campaign-interface publication and is not the failure. Source inspection shows that 0.1.3 assigned `events` in the root loader but then made the imported director rediscover it with `rawget(_G, "events")`; the live environment did not validate that cross-module global-visibility assumption. Release 0.1.4 makes the boundary explicit by calling `director.setup(triggers.events)`.

The third attached file extends that evidence with two 0.1.4 load IDs. The decisive loaded-campaign block reaches matching loader/director registry identities, six `LISTENER_OK_*` stages, `LISTENERS_READY`, `DIRECTOR_SETUP_OK`, `EVENT_HIT_LoadingGame`, `ENGINE_READY`, `EVENT_HIT_UICreated`, and `EVENT_HIT_FirstTickAfterWorldCreated`. It later records saving, faction-turn, and declaration-of-war event hits as well. Routing, exact registry transport, listener insertion, dispatch, and interface discovery therefore all work in the native game.

That same block ends without `WORLD_READY` after emitting `WORLD_WAIT` at first tick. The detailed file is also absent. This is one failure, not two: detailed telemetry starts only inside a successful supported-world reconciliation. Source comparison against Creative Assembly's model-interface contract identifies the boundary: `MODEL_SCRIPT_INTERFACE.campaign_name(key)` returns whether the current campaign matches the supplied key. Release 0.1.4 called it with no argument and expected a string, so it rejected the valid Grand Campaign before bundle application or detailed logging. Release 0.1.5 corrected the predicate.

The later 0.1.5 live files close that activation gap. A loaded maximum-pressure `main_rome` save reaches `DIAGNOSTIC_SINK_READY`, `WORLD_STATE`, `WORLD_READY`, `SESSION_START`, `STATE`, and a complete AI audit. Every active AI reports the Tier 100 base and Catch-up 3 package, treasury grants recur as needed, and all 91 surviving AI pairs are eventually processed; the trace also records the forced end of the AI-to-AI wars. The context popup appears once and remains deduplicated after a full game exit, reload, and turn advance. These observations validate activation and reconciliation, not every long-run CAI roster or alliance outcome.

## Historical activation defects

Release 0.1.1 attempted to acquire the interface only during the early director import. If `game_interface` was still `nil`, it returned without normal listeners and never retried. The detailed logger also began only after successful reconciliation, so the same defect removed both mechanics and their evidence.

Release 0.1.2 added an independent bootstrap stream and a deferred `NewSession` handoff, but its custom director remained under `lua_scripts` and was required through an ambient, context-sensitive route. Release 0.1.3 removed that route ambiguity and the single-event gate, but its regression harness shared a global `events` table between loader and director; the native 0.1.3 trace exposed that unmodeled boundary. Release 0.1.4 passed the exact registry as an argument, and the native trace confirms that repair through event delivery and interface discovery. It then exposed the incorrect zero-argument campaign-name assumption. Release 0.1.5 corrected the predicate and completed native world reconciliation. Release 0.1.6 keeps that activation path and adds bounded files plus richer mobilization/diplomacy audit records.

## Failure behavior

All operations for both files are protected. A bootstrap-file tracking, compaction, or append failure skips that record and cannot abort the root loader. A detailed tracking or rewrite failure skips the current file batch so the 1,000-line ceiling is never knowingly exceeded; native output and mechanics continue and a later callback can retry. A direct detailed append/write/flush/close failure disables that file sink for the Lua session while scaling, treasury, and diplomacy processing continue.

Compact session/state/audit-boundary records are also sent through Rome II's `out.ting` sink. A detailed-file failure produces one native warning rather than repeating every turn.
