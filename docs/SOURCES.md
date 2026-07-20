# Research sources

Research snapshot: 2026-07-20.

## Evidence standard

The project distinguishes three kinds of evidence:

1. **Current schema evidence** establishes field order, data types, table versions, primary keys, and references.
2. **Decoded Rome II pack evidence** establishes that an effect/scope/sign combination has existed in a real PFH4 pack. Much of the broad effect inventory comes from Patch-17 vanilla-derived rows, so it is not a substitute for the current installed `data.pack`.
3. **Current scripting evidence** establishes that the required methods and events appear in a current Rome II executable dump. Official Attila sibling-engine documentation supplies several argument signatures where Rome II's own public documentation is incomplete.

No paid Rome II depot, current Assembly Kit dependency cache, or runnable game executable was available in the build environment. Native claims are therefore separated between source/API evidence and the user's supplied live traces. The 0.1.5 trace establishes successful world reconciliation, protected command processing, both diagnostic sinks, popup deduplication, and full AI-pair traversal. The 0.1.6 trace plus two user reproductions establish a later native crash when the Diplomacy panel opens and show that `has_general()` does not distinguish settlement garrison forces in this interface. The turns 207–211 0.1.7 trace establishes that the promotion-only crash repair works in that save and records stronger mobilization, extreme treasuries, and uneven inherited settlement development. It does not certify the new 0.1.8 development-point calls or a full-campaign buildout.

## Official current-branch context

- Creative Assembly, [The PANTHEON Updates](https://community.creative-assembly.com/total-war/total-war/forums/109-total-war/threads/13996-the-pantheon-updates), 2026-04-24. The announced work is future-facing and supports retaining a pre-PANTHEON branch.
- Creative Assembly, [JUPITER – Building Changes](https://community.creative-assembly.com/total-war/total-war/forums/112-total-war/threads/14002-jupiter-building-changes), including planned Imperium/cap and building-system changes.

Those announcements are why this release explicitly targets the current public pre-PANTHEON Grand Campaign and does not claim future compatibility.

## Schema and toolchain

| Source | Revision | Use |
|---|---|---|
| [RPFM Rome II schema](https://github.com/Frodo45127/rpfm-schemas/blob/04ae66b53835b0b922e3eeed8ab5ffddd94a6b0e/schema_rom2.ron) | `04ae66b53835b0b922e3eeed8ab5ffddd94a6b0e` | DB layout, versions, types, and references |
| [RPFM](https://github.com/Frodo45127/rpfm/tree/cd255a4405f5cc052df3a5809b3aced5717496f5) | 5.0.5 / `cd255a4405f5cc052df3a5809b3aced5717496f5` | Decoding reference packs and constructing/inspecting PFH4 |

The preserved schema snapshot has SHA-256 `cbdb4f74265958ea77da2789e15093c7d12c441a7660cf95cba09e3cf5d6eecf`.

Selected release bundles use `effect_bundles_tables` and `effect_bundles_to_effects_junctions_tables`; values in the junction are 32-bit floats. Effect and scope keys remain references to datacored Rome II records and are never invented.

The schema repository contains multiple `fame_levels` versions, including v4 and a later v6 layout. Its cited Rome II schema commit dates to 2025-08-28, before PANTHEON was announced, so the later version cannot responsibly be labelled a PANTHEON format. World Resistance intentionally builds the v4 Grand Campaign row shape because exact v4 `main_rome` rows were decoded from stable packs and current Rome II continues to support versioned Workshop tables. A post-PANTHEON build must be based on rows decoded from that released branch, not on schema-version inference.

## Scripting and loader sources

| Source | Revision | Use |
|---|---|---|
| [ConsulScriptum](https://github.com/bukowa/ConsulScriptum/tree/95085275d9ad20167e72231a7c3304ab04d97777) | `95085275d9ad20167e72231a7c3304ab04d97777`, 2026-05-28 | Current Rome II API/event dump, immediate event-table listeners, explicit custom module path, and lazy interface lookup |
| [Total War Rome II docs](https://github.com/bukowa/twr2docs/tree/aeaece2b77f5ae7f197cf14184a367ce58a6e4e9) | `aeaece2b77f5ae7f197cf14184a367ce58a6e4e9`, 2026-04-25 | Rome II Lua loading order |
| [Rome II Lua Profiler Steam fix](https://github.com/bukowa/rome2_luaprofiler/commit/00a5cda98a3c12fe06ea7fca2ac627f5dac3d859) | `00a5cda98a3c12fe06ea7fca2ac627f5dac3d859`, 2025-02-21 | Working `all_scripted.lua` correction: explicit `script/profi/?.lua` path, simple module name, direct `events` insertion, and removal of the early `EpisodicScripting` import |
| [Current Divide et Impera UI `main_rome` scripting reference](https://github.com/bukowa/tw_rome2_dei_ui_mod/blob/4fa458784362b2a8b9e2bd7ca1821036c7b0a781/mod/campaigns/main_rome/scripting.lua) | `4fa458784362b2a8b9e2bd7ca1821036c7b0a781`, 2025-02-18 | Inspected live-community source for working Grand Campaign setup order: campaign-owned `EpisodicScripting` import, `SetCampaign`, and `initialise_let` from `UICreated`; no DEI balance rows are copied |
| [DEI-derived AI population setup](https://github.com/Destroyer13579/DEI-AI-USES-POP-DEV-GITHUB/blob/main/current_PORT_version/Pre_release/lua_scripts/gc_first_turn_setup.lua) | Main branch inspected 2026-07-20 | Functional community comparison for strategic-stance blocking: a small named-pair setup at new-campaign initialization, not a whole-map recurring lock; no forced stance refresh or blocker-readback loop |
| [Official Rome II Seasons and Wonders update](https://wiki.totalwar.com/w/Total_War_ROME_II%3A_Season_and_Wonders_Update.html) | Published CA wiki | Rome II's three-argument `show_message_event` signature and numeric `custom_event_` key rule |
| [Official Attila campaign interface](https://wiki.totalwar.com/w/Total_War%3A_ATTILA_KIT_-_Campaign_Script_Interface) | Published CA wiki | Sibling-engine signatures for effect bundles, treasury, province development points, peace, trade, diplomacy, and stance calls |
| [Official Attila extra scripting guides](https://wiki.totalwar.com/w/Total_War%3A_ATTILA_KIT_-_Extra_Scripting_Guides) | Published CA wiki | `MODEL_SCRIPT_INTERFACE.campaign_name(key)` contract: compares the current campaign with the supplied campaigns-table key and returns a boolean |

The loading-order evidence places `all_scripted.lua` before `campaigns/<campaign_name>/scripting.lua`. The working Grand Campaign script then imports `lua_scripts.EpisodicScripting`, calls `SetCampaign("main_rome")`, and initializes the export-trigger layer from its `UICreated` callback. The Lua Profiler's Steam correction is especially relevant: it removed an early `EpisodicScripting` import and direct `AddEventCallBack`, added an explicit pack-local search path, and inserted its callback directly into `events.FactionTurnStart`. Current ConsulScriptum follows the same structure, registering ordinary event-table listeners immediately and deliberately resolving `game_interface` later from global or already-loaded module state. Its [cross-campaign fix](https://github.com/bukowa/ConsulScriptum/commit/521a1677877d5d117d44f434bf308d0c003c8847) records why importing `EpisodicScripting` from the early loader is avoided.

That evidence does **not** establish a callable ordering between a function appended to `events.NewSession` and Rome II's native `EpisodicScripting` initialization. Release 0.1.2 treated the two registration layers as if CA's callback would necessarily run first; the user's native trace disproved that operational assumption. Release 0.1.3 therefore removed `NewSession`, temporarily prepended `script/campaign/wr2/?.lua`, required the simple module name `wr2_world_resistance`, and restored the ambient path. A later native trace proved that route worked in two independent load IDs but that neither load reached listener readiness.

Source inspection localized the remaining 0.1.3 assumption: `all_scripted.lua` held the exact `triggers.events` table, while the imported director attempted to rediscover `events` through its own `_G`. The existing Lua harness ran both in a shared global environment, but the native evidence did not validate that model. Release 0.1.4 replaces the implicit global boundary with the public dot-call API `WR.setup(event_registry)` and calls it as `director.setup(triggers.events)`. Registration is scoped to that object and inserts the six protected listeners for `LoadingGame`, `SavingGame`, `UICreated`, `FirstTickAfterWorldCreated`, `FactionTurnStart`, and `FactionLeaderDeclaresWar`.

The latest native 0.1.4 trace validates that repair: its registry identities match, all six listeners attach, campaign events arrive, and the director acquires `game_interface`. It then stops at `WORLD_WAIT`. The current Rome II dump and Creative Assembly's official sibling-engine guide agree that `MODEL_SCRIPT_INTERFACE.campaign_name` accepts a campaign key and returns whether it matches. Release 0.1.4 instead called `campaign_name()` and treated the result as a returned key, which rejected the valid original Grand Campaign before any WR command ran.

Release 0.1.5 uses the documented predicate `model:campaign_name("main_rome")`. Each callback independently attempts lazy interface discovery from global `scripting`, global `EpisodicScripting`, and the already-loaded uppercase/lowercase module variants; the director never imports `EpisodicScripting` itself. `FirstTickAfterWorldCreated` is the normal world-reconciliation edge. While initialization is incomplete, the first delivered `FactionTurnStart` in each campaign turn retries regardless of the event-context faction's humanity; the world scan itself finds and excludes the human. The lifecycle harness isolates the director from global `events`, passes the exact registry argument, and covers partial/repeated setup, a loaded-save path, a delayed interface, the campaign predicate, per-turn faction-turn recovery, an unwritable installation, and repeated bootstrap entry. The later user-supplied 0.1.5 trace reaches successful `WORLD_STATE`/`WORLD_READY` and detailed telemetry in Rome II, closing the activation boundary that simulation alone could not certify.

The current Rome II faction dump includes `imperium_level`, `is_human`, `region_list`, `military_force_list`, `treasury`, `faction_attitudes`, and no `is_dead` method. The military-force interface includes `is_army`, `is_navy`, `has_general`, `has_garrison_residence`, and `unit_list`, but method presence does not establish semantics: live 0.1.6 output proved that `has_general()` did not separate field armies from settlement garrison forces. Release 0.1.8 retains 0.1.7's clearly labeled `main_rome` estimate—broad land-army forces minus one presumed garrison per owned region, clamped—rather than claiming native force-type readback. `has_garrison_residence()` is also unsuitable as a classifier because a field army stationed in a settlement can have a garrison residence.

The current Rome II game-interface dump exposes `add_development_points_to_region`, while Creative Assembly's official sibling-engine campaign interface documents the argument shape `add_development_points_to_region(region_key, num_points)` and states that it adds development points to the province containing the specified region. A current [ConsulScriptum implementation](https://github.com/bukowa/ConsulScriptum/blob/95085275d9ad20167e72231a7c3304ab04d97777/src/consul/consul.lua) invokes that exact Rome II method with one point, and its [generated-action guide](https://consulscriptum.com/guide/parts/generated-consul-scripts) describes the result as a permanent growth point used to open building slots. Creative Assembly's [Rome II province overview](https://academy.totalwar.com/rome-2-province-overview/) independently identifies population surplus as the input for settlement expansion. Release 0.1.8 therefore groups owned regions by province and calls the method through one representative region per unique AI province. This is materially stronger than method-name speculation, but it is not native proof that WR's current-branch batch or CAI spending works as intended; those remain live-test gates.

`faction_attitudes()` is a read operation that returns a directional map of faction keys to numeric attitudes. Neither the current Rome II dump nor Creative Assembly's published sibling-engine campaign interface exposes a safe pair-specific numeric attitude setter. The official interface does expose pair-scoped stance promotion, block-all-stances-but-one, forced stance refresh, deal permissions, peace, and trade operations. Method availability is not proof that an all-map combination is safe. Release 0.1.6 added a block and refresh in each direction for every processed pair—320 new native calls in an 80-pair batch—and the Diplomacy panel then crashed reproducibly. Its blocker-readback call was also invalid because the binding requires a stance argument that was omitted. Release 0.1.7 removes all block, refresh, and blocker-readback calls, retains bidirectional `BEST_FRIENDS` promotion and deal controls, and logs attitude aggregates without claiming a visible `+300` relation write. The current registry and vanilla EpisodicScripting expose the native logger as the table method `out.ting`, not callable `out()`.

The functional DEI-derived comparison uses block-all-but-one only for a handful of named campaign pairs during new-campaign setup; it does not demonstrate that 160 directional whole-map locks plus 160 forced updates are safe on every reconciliation. ConsulScriptum examples use `promote_specified_stance` and ordinary `force_diplomacy` controls without the 0.1.6 all-map lock/refresh profile. This stare-and-compare supports returning 0.1.7 to the live-stable promotion-only mutation set rather than attempting another native stance-state repair.

## Decoded Workshop evidence

| Pack | Workshop page | SHA-256 | Use |
|---|---|---|---|
| Guaranteed Major Faction Empires | [233589292](https://steamcommunity.com/sharedfiles/filedetails/?id=233589292) | `c20f2273d86b0dde6f92097fc0eecad742a042e2d9a569ad207b2603dd6b342a` | Working Rome II three-argument status message, four-culture title/body Loc pattern, local campaign log, and historical loader/event patterns |
| Radious AI Mod – Patch 17 Only | [186967731](https://steamcommunity.com/sharedfiles/filedetails/?id=186967731) | `4778192e6c810d6b42290610d22c9180c06047e91034c08239aee8cba62bba55` | Vanilla-derived difficulty effect rows |
| Radious Campaign Features Mod – Patch 17 Only | [186967968](https://steamcommunity.com/sharedfiles/filedetails/?id=186967968) | `2c6b13e54699e5b3a523dc59c8d9536ef519c168d2b387594b736f6899df0fe8` | Effect/scope pairs and historical fame data |
| Increase army cap | [1082051626](https://steamcommunity.com/sharedfiles/filedetails/?id=1082051626) | `7cb69cb281192b6643cd9e3be5a911952587958da6d607bb5cf9f9b683bec996` | Public Grand Campaign fame-table layout and unchanged non-army columns; not copied as a balance mod |

The selected 21 effects and scopes are recorded exactly in the project balance matrix. Representative real values include construction turns `-3/-5/-7`, AI research points, public order, food, recruitment capacity, upkeep, replenishment, recruit rank, armour, faction-wide morale, melee damage, and experience gain. Proposed extreme values are World Resistance balance decisions, not claims that vanilla uses those values. Recruit-rank and melee-damage rows retain their evidenced `start_turn_initiated` advancement stage; other rows use an evidenced or common `start_turn_completed` stage. The inspected Radious tables establish historical effect/scope and fame-row forms; the inspected DEI UI source establishes a contemporary community loader/campaign setup pattern. Neither is redistributed or treated as proof that global personality, roster, or diplomacy-relation rewrites are safe.

Construction stare-and-compare reached the same boundary from several directions. The Rome II Assembly Kit schema separates legal building chains and technology gates from CAI building values, construction templates, and personality budget allocations. The decoded historical Radious AI pack changes construction budgets and strategic-state allocation rather than relying on cheap build costs alone; at peace it assigns much more of the CAI budget to construction than under total-war/last-stand states. [Better Campaign AI](https://steamcommunity.com/sharedfiles/filedetails/?id=1219494379) likewise advertises building-priority, dismantling, budget, food, growth, and economic changes; [Wars of the Gods 10.7](https://www.moddb.com/mods/wars-of-the-gods-ancient-wars/news/wars-of-the-gods-ancient-wars-107) describes construction and research priority work together; and [Divide et Impera 0.7.1](https://www.moddb.com/mods/divide-et-impera/news/release-divide-et-impera-v071) treats building chains, tiers, conditions, and resources as a coupled system. These comparisons explain why money and `-7` construction time do not force upgrades. They also explain why WR does not copy a global CAI/building overhaul into a near-final standalone pack: doing so would greatly widen conflicts, affect AI behavior toward the human, and require current full-table data plus a fresh-campaign balance pass. The direct development grant removes the narrower, evidenced surplus bottleneck while preserving Rome II's own legal building choice.

The decoded Radious-derived rows also show that Rome II has global diplomatic-reputation effects. They do not establish a pair-matrix effect that can target AI-to-AI relationships while excluding both directions involving the human. World Resistance therefore does not repurpose a global reputation effect as a guessed `+300` solution; it uses the documented pair-scoped CAI stance controls and audits the read-only attitude map instead.

## Community failure-mode research

- [Getae – Total Cheat Mod 2.2](https://steamcommunity.com/sharedfiles/filedetails/?id=265516523)
- [Baktria – Total Cheat Mod 2.2](https://steamcommunity.com/sharedfiles/filedetails/?id=201497202)
- [Better Economic & Military Management AI](https://steamcommunity.com/sharedfiles/filedetails/?id=2742800090)
- [Para Bellum clean-install troubleshooting](https://steamcommunity.com/workshop/filedetails/discussion/2010751524/4747300038104744049/)
- [Rome II outdated-mod discussion](https://steamcommunity.com/app/214950/discussions/0/38596747932133585/)

These are user reports rather than controlled reproductions. They define test cases—clean startup, construction sabotage/repair, contradictory diplomacy, stale files—not proven root causes.

## Inspected compatibility reference

- [RTW2 Stable Politics / No Civil War](https://github.com/daveshap/RTW2_No_Civil_War), main branch inspected 2026-07-19. Its published presets contain one `effect_bundles_to_effects_junctions_tables` fragment for government loyalty. The repository documents no Lua campaign script, startpos change, or `fame_levels` override. Its keys do not overlap the World Resistance bundle rows, so the two packs are expected to coexist; this is source-level compatibility evidence, not a completed live two-mod test.

## Preserved local evidence

The research workspace preserves:

- the RPFM schema snapshot and a generated full schema-column manifest;
- exact decoded candidate effect rows and compact verified difficulty rows;
- original acquired reference packs and SHA-256 manifests;
- current Rome II loader, API, event, and runtime registry extracts;
- the 0.1.8 explicit-registry, partial/repeated-setup, delayed-interface, campaign-predicate, per-turn faction-retry, army-estimate, promotion-only diplomacy, unsafe-method-ban, bounded-log, unique-province, human-exclusion, and same-turn development-deduplication harnesses;
- the user-supplied 0.1.5 bootstrap/detailed logs proving successful live reconciliation, one-time popup behavior, universal maximum-tier/catch-up application in that save, treasury maintenance, and complete 91-pair processing;
- the user-supplied 0.1.6 bootstrap/detailed logs plus repeatable Diplomacy-panel crash report, proving the native regression boundary and failed `has_general()` distinction;
- the user-supplied 0.1.7 bootstrap/detailed logs covering turns 207–211, proving the Diplomacy-panel hotfix in that save and documenting Tier 100 plus Catch-up 3, approximately 4.8–5.9 million treasury targets, stronger/full armies, heavy agent use, and uneven late-save settlement development;
- historical script examples retained as evidence only, never shipped as overrides.

The release pack contains only the records needed to run World Resistance. Research packs and third-party scripts are not redistributed in the installable mod.
