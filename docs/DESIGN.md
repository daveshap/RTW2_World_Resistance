# Design

## Design contract

World Resistance treats human hegemony as a global threat, not a local war state.

Release 0.1.5 remains a standalone PFH4 Mod pack named `@wr2_world_resistance.pack`. The leading `@` is a launcher-recognition aid for manual installation, not a load-order mechanism or a second dependency.

Every active non-human faction receives the same world-pressure tier, including factions that are neutral, allied, clients, distant, unmet, or currently at peace with the human. A weak AI can also receive one catch-up package. Only a faction with neither a region nor a military force is treated as dormant or dead, because Rome II's current faction scripting interface does not expose `is_dead()`.

The human receives no World Resistance effect bundle, treasury grant, or pair-scoped diplomacy command. This invariant is checked at faction selection and again immediately before every diplomatic operation.

## World pressure

Territory is the primary signal. Let `s` be the number of human-controlled regions divided by the number of regions in the live campaign. Territory pressure `T(s)` is linearly interpolated between these points:

| Human share of map | Territory pressure |
|---:|---:|
| 0% | 0 |
| 10% | 20 |
| 20% | 40 |
| 32% | 65 |
| 50% | 85 |
| 70% | 100 |

Human army count and treasury can fill a small share of the pressure not already supplied by territory:

\[
P = T + (100-T)(0.10A + 0.05M)
\]

where `A = clamp(human armies / 16, 0, 1)` and `M = clamp(human treasury / 100000, 0, 1)`. The result is rounded and clamped to 0–100.

Final vanilla Imperium (script level 7) permanently establishes a minimum pressure of 65. It does **not** freeze scaling at that point: territory continues to drive the result toward 100. If the human later loses land, base-tier promotion happens immediately but demotion requires ten human-turn evaluations and drops only one tier at a time.

Pressure selects one exclusive base bundle:

| Pressure | Tier | Bundle |
|---:|---:|---|
| 0–19 | 0 | `wr2_wr_ai_tier_00` |
| 20–39 | 1 | `wr2_wr_ai_tier_20` |
| 40–64 | 2 | `wr2_wr_ai_tier_40` |
| 65–84 | 3 | `wr2_wr_ai_tier_65` |
| 85–99 | 4 | `wr2_wr_ai_tier_85` |
| 100 | 5 | `wr2_wr_ai_tier_100` |

Tier 0 is intentionally non-empty. The AI begins preparing before Rome arrives.

## Base package

Values are absolute per tier, not increments. Before applying a tier, the script removes all six World Resistance base keys so they cannot accumulate.

| Metric | T00 | T20 | T40 | T65 | T85 | T100 |
|---|---:|---:|---:|---:|---:|---:|
| Construction turns removed | -1 | -2 | -4 | -6 | -7 | -7 |
| Construction cost % | -10 | -20 | -40 | -60 | -78 | -90 |
| Building GDP % | +10 | +25 | +60 | +125 | +250 | +400 |
| Tax income % | +5 | +10 | +20 | +40 | +70 | +100 |
| Recruitment cost % | -10 | -20 | -40 | -60 | -78 | -90 |
| Unit upkeep % | -10 | -15 | -30 | -50 | -70 | -90 |
| Mercenary recruitment % | -10 | -20 | -40 | -60 | -78 | -90 |
| Mercenary upkeep % | -10 | -15 | -30 | -50 | -70 | -90 |
| Land recruitment slots | +1 | +2 | +3 | +4 | +6 | +8 |
| Naval recruitment slots | +1 | +1 | +2 | +3 | +4 | +6 |
| Replenishment | +3 | +5 | +8 | +12 | +20 | +30 |
| Recruit rank | 0 | +1 | +2 | +3 | +4 | +6 |
| Armour | 0 | 0 | +2 | +4 | +6 | +8 |
| Morale | 0 | +1 | +2 | +4 | +6 | +8 |
| Melee damage % | 0 | 0 | +1 | +2 | +4 | +6 |
| Experience gain % | +2 | +3 | +5 | +7 | +9 | +10 |
| Research rate % | +10 | +25 | +60 | +125 | +250 | +400 |
| Flat research points | +15 | +30 | +60 | +100 | +150 | +225 |
| Public order | +10 | +20 | +40 | +75 | +125 | +200 |
| Food | +20 | +50 | +125 | +300 | +800 | +2000 |
| Province growth | +2 | +3 | +5 | +8 | +12 | +20 |

Zero-value rows are omitted from the database. Construction time uses the largest negative value observed in real Rome II rows, `-7`; buildings with a base time of eight turns or less are expected to reach the engine's one-turn floor. That flooring behavior still needs a live test.

## Per-faction catch-up

Base pressure is global, but parity needs are local. For each AI, the director compares:

- its regions with human regions;
- its armies with human armies, or a target of at least 16 after final Imperium;
- its treasury with the human treasury, with a minimum comparison target of 5,000.

The worst of those three proportional shortfalls selects at most one exclusive catch-up bundle:

| Worst shortfall | Catch-up level |
|---:|---:|
| Below 25% | None |
| 25–49% | 1 |
| 50–74% | 2 |
| 75% or more | 3 |

| Metric | Catch-up 1 | Catch-up 2 | Catch-up 3 |
|---|---:|---:|---:|
| Building GDP % | +40 | +100 | +200 |
| Tax income % | +10 | +25 | +50 |
| Land recruitment slots | +1 | +2 | +4 |
| Naval recruitment slots | +1 | +2 | +3 |
| Replenishment | +4 | +10 | +20 |
| Recruit rank | +1 | +2 | +3 |
| Armour | 0 | +1 | +2 |
| Morale | 0 | +1 | +2 |
| Melee damage % | 0 | +1 | +4 |
| Experience gain % | +1 | +3 | +5 |
| Research rate % | +40 | +100 | +200 |
| Flat research points | +25 | +75 | +150 |
| Public order | +25 | +75 | +200 |
| Food | +150 | +600 | +3000 |
| Province growth | +3 | +7 | +15 |

Catch-up contains no cost, upkeep, or construction-time reducers. Therefore this mod's own base-plus-catch-up stack never exceeds `-90%` in those families. Other game or mod effects can still stack with it.

## Treasury parity

Once per human turn, and once at initial world creation, the director raises each AI treasury toward the greatest of:

- the current tier floor: 5,000 / 10,000 / 30,000 / 75,000 / 150,000 / 300,000;
- the human treasury;
- an 8,000-per-target-army replacement reserve.

Catch-up multiplies that target by 1.00, 1.25, 1.75, or 2.50. A single update can add at most 2,000,000, and the target is capped at 100,000,000. Funds are never removed. This is a liquidity floor, not a promise that CAI will spend optimally.

## Army-cap strategy

Recruitment slots do not raise the legal number of armies. The pack therefore includes a narrow Grand Campaign `fame_levels` override using Rome II's separate AI and player prestige thresholds:

- human `player_prestige` thresholds and the normal 3, 4, 6, 8, 10, 12, 14, 16 army progression remain unchanged;
- AI prestige thresholds become `-7` through `0`, making a non-negative AI prestige resolve to the final 16-army row;
- agent and navy caps remain the values in the selected stable-layout rows;
- no army is created or teleported by script.

The source uses `fame_levels_tables` **version 4 intentionally**. It is the exact Grand Campaign row shape—with separate champion, dignitary, and spy caps—decoded from stable Rome II packs and used by longstanding army-cap mods that the current engine continues to load. RPFM's schema also contains later v5/v6 layouts, but the schema commit containing them predates the PANTHEON announcement; they must not be described as PANTHEON formats. Without the paid current data depot, this build does not guess how those alternative layouts are distributed among vanilla files or campaigns. A future PANTHEON build must decode that branch's actual `main_rome` rows and revisit every cap assumption rather than relying on version-number inference.

This cap strategy is much safer than spawning stacks, but it is still an experimental engine-behavior assumption until verified in a live campaign. It also makes this pack incompatible with another Grand Campaign army-cap or `fame_levels` override.

After final human Imperium, catch-up calculations use `max(16, human army count)` as the target. An AI still has to recruit, fund, and command those legal armies itself.

This makes parity a mobilization process, not a force-spawn event. Rome II's diplomacy power bar is dominated by military strength already fielded, so it can remain near zero immediately after activation even while WR has accepted the faction's bundles and raised its treasury. Recruitment becomes dramatically faster, cheaper, higher-ranked, and easier to sustain, but the CAI must still recruit forces over subsequent turns. The `WORLD_STATE`, `STATE`, and `AI` records are the activation evidence; the power bar is a later gameplay outcome.

## AI-only anti-hegemonic diplomacy

Diplomacy follows the highest tier ever reached. This saved high-water mark never falls, because Rome II exposes no documented operation that cleanly restores every pair to vanilla diplomatic rules.

| Highest tier reached | AI-to-AI behavior |
|---:|---|
| 0 | Vanilla diplomacy |
| 1 | Friendly stance promotion; trade offers/acceptance enabled |
| 2 | Very Friendly stance; peace and non-aggression enabled |
| 3 | Best Friends stance; defensive/full alliances enabled; breaking trade, alliances, and non-aggression blocked |
| 4 | Ordinary war and join-war offers/acceptance blocked; existing AI-to-AI wars repeatedly forced to peace |
| 5 | Tier 4 plus direct legal AI-to-AI trade attempts |

Pair controls are applied in both directions only after both endpoints pass the non-human guard. They never alter AI diplomacy toward Rome or another human faction.

The design can guarantee repeated peace enforcement through the audited ordinary diplomacy path; it cannot honestly promise that every pair becomes formally allied. Rome II exposes an audited direct trade command, but no audited direct alliance constructor. A scripted campaign incident may also bypass ordinary war permissions until the declaration listener or next faction-turn enforcement closes it.

Pair work is processed in bounded batches—80 pairs at first tick and human turns, 20 on AI turns—to avoid a large full-map diplomacy burst on the loading screen.

## Observability

Release 0.1.5 exposes three progressively stronger lifecycle signals without modifying Rome II's UI component tree:

1. The root loader appends lifecycle milestones to installation-root `wr2_world_resistance_bootstrap.log`. `LOADER_START`, `MODULE_PATH_READY`, `DIRECTOR_ROUTE_TRY`, `DIRECTOR_ROUTE_OK`, and `DIRECTOR_REQUIRE_OK` prove the explicit pack-local module route. Matching loader-owned (`source=export_triggers`) and director-owned (`source=loader_argument`) `EVENT_REGISTRY_READY` identities, `DIRECTOR_SETUP_TRY`, six successful/reused listener outcomes, `LISTENERS_READY`, and `DIRECTOR_SETUP_OK` prove the root loader handed its exact `triggers.events` object to the director and all callbacks are present. Later `EVENT_HIT_*`, `ENGINE_READY`, `WORLD_ATTEMPT`, `WORLD_STATE`, and `WORLD_READY` milestones distinguish event dispatch, interface discovery, attempted reconciliation, successful command processing, and completed initialization. Failed attempts state `WORLD_PROBE_FAIL`, `WORLD_UNSUPPORTED`, or `WORLD_NO_HUMAN` before `WORLD_WAIT`; `EVENT_REGISTRY_INVALID` or `LISTENERS_PARTIAL` is not accepted attachment.
2. A supported custom message event appears after the first successful reconciliation and whenever the effective base tier reaches a new campaign high. The saved `highest_notified_tier` is monotonic, preventing reload or demotion spam and matching diplomacy's own high-water behavior.
3. The existing structured, local-only campaign diagnostics append to `data/wr2_world_resistance.log`. `DIAGNOSTIC_SINK_READY` proves this file opened and wrote; `DIAGNOSTIC_SINK_ERROR` identifies a real path/write failure without disabling mechanics. A `STATE` line records the human inputs, computed pressure, effective/desired tiers, active-AI and catch-up counts, command-acceptance counts, bundle-change count, treasury grant count/total, diplomacy backlog, and peace commands once per human turn.

A detailed `AI` block is written at session start, tier escalation, and every tenth turn. Each active non-human appears once with its regions, armies, navy count, treasury target/grant, catch-up level, selected bundle keys, and whether the corresponding protected engine commands completed without a Lua exception. The engine exposes no audited effect-bundle readback query, so `base_command_ok` and `catchup_command_ok` describe command acceptance and the director cache—not an independent query of native faction state.

No network API is used and no diagnostic data leaves the local machine. File access is nonessential and fail-closed; bootstrap milestones and compact session/state records also go to Rome II's native `out.ting` sink. `LISTENERS_READY` plus `DIRECTOR_SETUP_OK` proves accepted attachment, a later `EVENT_HIT_*` proves dispatch, `WORLD_STATE` proves a supported world was processed, and `SESSION_START` plus `STATE` is the detailed-file equivalent.

## Lifecycle and save behavior

- `all_scripted.lua` runs before the campaign interface is normally available. After the seven preserved vanilla imports and `events = triggers.events`, it temporarily prepends `script/campaign/wr2/?.lua`, protected-requires the simple module name `wr2_world_resistance`, and restores Rome II's original `package.path`.
- The imported module returns `WR` and exposes the dot-call API `WR.setup(event_registry)`. The root loader passes the exact local object with `director.setup(triggers.events)`; the director does not use `_G.events` as an implicit transport.
- Setup inserts six protected callbacks into the supplied table: `LoadingGame`, `SavingGame`, `UICreated`, `FirstTickAfterWorldCreated`, `FactionTurnStart`, and `FactionLeaderDeclaresWar`. Listener registration does not depend on `game_interface`, and repeated setup on the same registry reuses rather than duplicates callbacks.
- World Resistance never imports `EpisodicScripting`. At each event it lazily checks global `scripting`, global `EpisodicScripting`, and already-loaded uppercase/lowercase module variants for `game_interface`; a missing interface is logged and a later event retries.
- `LoadingGame` reads six primitive named values and does not mutate the world.
- `UICreated` only marks the message UI as available; it cannot show status before a successful reconciliation.
- `FirstTickAfterWorldCreated` is the normal first reconciliation after a new campaign, load, or return from battle.
- Supported-campaign detection uses Rome II's boolean predicate `model:campaign_name("main_rome")`; it is not a zero-argument campaign-key getter.
- If first tick arrived before the interface or campaign world was usable, the first delivered `FactionTurnStart` in each campaign turn retries while initialization is incomplete, regardless of whether its context faction is human or AI. The complete world scan identifies the human and enforces the human-exclusion invariant before mutation.
- After initialization, `FactionTurnStart` refreshes pressure, bundles, treasury, and diplomacy.
- `FactionLeaderDeclaresWar` reasserts hard AI peace for an AI declarer at high pressure.
- `SavingGame` stores pressure, permanent floor, current tier, demotion counter, diplomacy high-water mark, and highest notified tier.

Every bundle family is scrubbed before replacement, human bundles are scrubbed on every full update, and engine-facing calls are protected. Re-running converges on the same intended state.

Release 0.1.1 returned from its early import when the interface was `nil`, leaving no listeners. Release 0.1.2 added a `NewSession` handoff and kept the director under the special `lua_scripts` module route. The first native trace showed both assumptions were unsafe. Release 0.1.3 introduced the explicit pack-local route and lazy interface discovery; the next trace proved the route worked in two loads but also showed that neither registered listeners. Its test harness had shared `_G.events` between loader and director, an environment boundary the game did not reproduce. Release 0.1.4 passed `triggers.events` explicitly; the newest trace proves registry handoff, all six listeners, event dispatch, and interface discovery, but ends at `WORLD_WAIT`. It exposed a second mistake: calling Rome II's `campaign_name(key)` predicate with no key and treating the result as a string. Release 0.1.5 calls the predicate correctly, retries from the first faction turn per campaign turn, and makes every world failure reason observable. This correction does not relax the recommendation to begin a disposable new Grand Campaign, because successful live reconciliation, army-cap behavior, and existing-save balance remain uncertified.
