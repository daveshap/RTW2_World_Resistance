# Observability and local diagnostics

World Resistance 0.1.4 exposes module resolution, explicit event-registry handoff, listener registration, lazy engine discovery, event delivery, and campaign reconciliation as separate signals. This is deliberately not remote telemetry: the pack contains no network code and uploads nothing.

## Bootstrap file

The root `all_scripted.lua` loader owns a small append-only bootstrap stream. In a normal Steam installation its relative path resolves in the Rome II installation root, one directory above the installed pack:

```text
...\Total War Rome II\wr2_world_resistance_bootstrap.log
```

The root logger starts before the director import, so it can report a module-route or setup failure even when the detailed campaign logger never starts. A 0.1.4 line has this shape:

```text
WR2|schema=1|event=BOOT|release=0.1.4-beta|load=table: 01234567|stage=LOADER_START
```

`load` is an opaque token created for one evaluation of `all_scripted.lua`. Use it only to group lines from the same loader evaluation; it is not a campaign ID and is not persisted. This removes the ambiguity in older append-only traces, where adjacent blocks could have come from different Lua states or game launches.

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
| `ENGINE_WAIT` | No live game interface was discoverable during the first lazy lookup; in 0.1.4 this is normally emitted at `director_setup` |
| `ENGINE_UNAVAILABLE_<name>` | A later event still could not find the interface; another event remains eligible to retry |
| `ENGINE_READY` | WR found `game_interface`; detail identifies the global or `package.loaded` source and the event that found it |
| `WORLD_WAIT` | The interface existed, but supported-world collection/reconciliation was not yet possible; the first human turn will retry |
| `WORLD_READY` | A supported `main_rome` world completed its first reconciliation |

Event and world milestones are emitted once per stage in a director load, so `EVENT_HIT_FactionTurnStart` proves at least one delivery rather than counting every turn. Each callback is independently protected: `EVENT_ERROR_*` records a contained Lua failure instead of allowing it to unwind through Rome II's dispatcher.

Listener registration does not wait for `game_interface`, import `EpisodicScripting`, or depend on `NewSession`. After importing the director, the root loader explicitly passes its local `triggers.events` object to `WR.setup(event_registry)`. The director appends callbacks for `LoadingGame`, `SavingGame`, `UICreated`, `FirstTickAfterWorldCreated`, `FactionTurnStart`, and `FactionLeaderDeclaresWar` to that argument. It does not rediscover the registry through `_G.events`. Each callback lazily checks the published `scripting` and `EpisodicScripting` globals and their known `package.loaded` aliases.

A normal first setup should progress through `LOADER_START`, loader-owned `EVENT_REGISTRY_READY` with detail `source=export_triggers`, route success, `DIRECTOR_REQUIRE_OK`, `DIRECTOR_SETUP_TRY`, director-owned `EVENT_REGISTRY_READY` with detail `source=loader_argument`, six `LISTENER_OK_*` stages, `LISTENERS_READY`, and `DIRECTOR_SETUP_OK`. The opaque registry identity in the two ready records should match. An early `ENGINE_WAIT|detail=director_setup` is expected before the final setup result when the interface is not yet published. The decisive runtime sequence is a later event hit, `ENGINE_READY`, and finally `WORLD_READY`.

On a repeated setup against the same registry, `LISTENER_REUSED_*` replaces `LISTENER_OK_*`; this is successful idempotence, not a warning. `LISTENERS_PARTIAL` plus `DIRECTOR_SETUP_PARTIAL` is not accepted as attachment. A later retry must visibly succeed for each previously missing/failed event and end at `LISTENERS_READY` plus `DIRECTOR_SETUP_OK`.

The loader also sends every bootstrap line through Rome II's `out.ting` sink when available, with a protected `print` fallback. A missing file alone cannot distinguish "pack did not load" from "installation directory was not writable."

## Detailed campaign file

The structured campaign stream remains at:

```text
data/wr2_world_resistance.log
```

It is deliberately opened only after `FirstTickAfterWorldCreated`, or its first-human-turn fallback, has collected and successfully reconciled a supported `main_rome` world. Each line retains the stable pipe-delimited schema:

```text
WR2|schema=1|event=STATE|release=0.1.4-beta|director=6|key=value|...
```

Carriage returns, newlines, tabs, and pipe characters are removed from values. String fields are length-limited. The file is opened, appended, flushed, and closed for each batch so it can be inspected while Rome II is running.

| Event | Frequency | Purpose |
|---|---|---|
| `SESSION_START` | First successful reconciliation in a Lua session | Release, campaign, human faction, turn, path, and local-only declaration |
| `STATE` | At most once per human turn, plus the initial session state | Inputs, pressure/tier, active-AI counts, catch-up distribution, treasury grants, and diplomacy work |
| `AI_AUDIT_BEGIN` / `AI_AUDIT_END` | Session start, tier escalation, and every tenth turn | Bounds and aggregate checks for a detailed audit block |
| `AI` | Once per active AI inside an audit block | Regions, forces, treasury target/grant, catch-up, selected bundles, and command status |
| `UI_NOTICE` | When a tier message command succeeds | Event key, tier, turn, and pressure |
| `AI_WAR_SUPPRESSED` | At most once per declaring AI per turn | Number of protected peace commands issued after a declaration |

The four catch-up counts in `STATE` and `AI_AUDIT_END` must sum to `active_ai`. `base_commands_ok` and `catchup_commands_ok` should also equal `active_ai` after a clean reconciliation.

`base_command_ok=true` means the protected Rome II call returned without a Lua exception and the director cached the requested selection. It does **not** mean the value was read back from the engine: the audited Rome II faction interface provides no effect-bundle query.

`peace_commands` similarly counts accepted peace commands, not independently proven treaty transitions. Verify important native outcomes in the campaign UI during the live smoke test.

## In-game status

The first successful Grand Campaign reconciliation queues a standard Rome II message for the current resistance tier. Another message appears only when a higher tier is reached. The highest acknowledged tier is saved as an integer, so loading, returning from battle, or temporarily losing territory does not repeat old messages.

The six status messages correspond to pressure bands 0, 20, 40, 65, 85, and 100. They use the official three-argument Rome II `show_message_event(event_key, 0, 0)` interface, additive DB rows, and existing vanilla image/icon/audio assets. The mod never edits the UI component tree.

The status message is attempted only after both `UICreated` and successful world reconciliation. It is never invoked during `LoadingGame`. A missing message API or localization failure cannot authorize any additional campaign mutation.

## Reading a 0.1.4 smoke test

- No bootstrap file: the pack's loader may not have run, another `all_scripted.lua` may have won, an old pack may be selected, or file access may be blocked. Check the launcher and native script output.
- `LOADER_START` without `MODULE_PATH_READY`: the preserved loader ran, but its path setup failed before the director route was attempted.
- `DIRECTOR_ROUTE_ERROR` / `DIRECTOR_REQUIRE_ERROR`: the pack's loader ran, but module search, compilation, or director execution failed safely. The shared `load` token identifies the relevant block.
- `DIRECTOR_REQUIRE_OK` without `DIRECTOR_SETUP_TRY`: the module imported, but the loader did not begin the required API handoff.
- `DIRECTOR_API_ERROR`: the module route worked, but the returned value does not implement the 0.1.4 setup contract.
- `DIRECTOR_SETUP_TRY` without a second `EVENT_REGISTRY_READY` whose detail begins `source=loader_argument`: setup did not accept the registry argument; inspect `EVENT_REGISTRY_INVALID`, `DIRECTOR_SETUP_ERROR`, and native output.
- `LISTENER_MISSING_*` or `LISTENER_INSERT_ERROR_*`: at least one event failed registration. `LISTENERS_PARTIAL` and `DIRECTOR_SETUP_PARTIAL` are the expected aggregate results and are not acceptance.
- `LISTENERS_READY` plus `ENGINE_WAIT`: expected during early setup. Continue until a campaign event is delivered.
- `EVENT_HIT_<name>` plus `ENGINE_UNAVAILABLE_<name>` and no later `ENGINE_READY`: WR receives events, but Rome II has not published the interface through any known global/cache route.
- `ENGINE_READY` with no `WORLD_READY`: inspect `WORLD_WAIT`, campaign support, and native diagnostics. Only the original Grand Campaign key `main_rome` is active.
- `WORLD_WAIT`: collection was too early or incomplete. The first human `FactionTurnStart` is the bounded fallback initialization edge.
- `WORLD_READY` with no detailed `SESSION_START`: reconciliation succeeded, but the detailed file may not be writable. Check native output for the one-time sink warning.
- `SESSION_START` plus `STATE`: the director reconciled the supported world and its protected commands returned. This is strong proof that the script is active, but not native-state readback.
- `STATE` with no campaign message: campaign reconciliation worked; investigate `UICreated`, the custom event rows/localization, or message display.

On a loaded save, the callbacks already exist before campaign lifecycle events begin. `LoadingGame` restores the six primitive named values when the interface is discoverable and remains read-only. `FirstTickAfterWorldCreated` is the normal first reconciliation edge. If the interface or world was not ready then, the first human `FactionTurnStart` retries; AI turns cannot perform fallback initialization. A new campaign is therefore not required merely for the script to register, although it remains the only supported balance/army-cap starting point.

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

## Historical startup defects

Release 0.1.1 attempted to acquire the interface only during the early director import. If `game_interface` was still `nil`, it returned without normal listeners and never retried. The detailed logger also began only after successful reconciliation, so the same defect removed both mechanics and their evidence.

Release 0.1.2 added an independent bootstrap stream and a deferred `NewSession` handoff, but its custom director remained under `lua_scripts` and was required through an ambient, context-sensitive route. Release 0.1.3 removed that route ambiguity and the single-event gate, but its regression harness shared a global `events` table between loader and director; the native 0.1.3 trace exposed that unmodeled boundary. Release 0.1.4 passes the exact registry as an argument and tests an isolated director environment, partial registration, retry, and duplicate prevention. The build environment still lacks a runnable Rome II executable, so a successful 0.1.4 native smoke test remains required.

## Failure behavior

All operations for both files are protected. A bootstrap-file failure cannot abort the root loader. If the detailed sink cannot open, write, flush, or close, the director disables that sink for the Lua session while scaling, treasury, and diplomacy processing continue.

Compact session/state/audit-boundary records are also sent through Rome II's `out.ting` sink. A detailed-file failure produces one native warning rather than repeating every turn.
