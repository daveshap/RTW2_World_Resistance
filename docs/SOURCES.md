# Research sources

Research snapshot: 2026-07-18.

## Evidence standard

The project distinguishes three kinds of evidence:

1. **Current schema evidence** establishes field order, data types, table versions, primary keys, and references.
2. **Decoded Rome II pack evidence** establishes that an effect/scope/sign combination has existed in a real PFH4 pack. Much of the broad effect inventory comes from Patch-17 vanilla-derived rows, so it is not a substitute for the current installed `data.pack`.
3. **Current scripting evidence** establishes that the required methods and events appear in a current Rome II executable dump. Official Attila sibling-engine documentation supplies several argument signatures where Rome II's own public documentation is incomplete.

No paid Rome II depot, current Assembly Kit dependency cache, or runnable game executable was available. Claims that require native behavior remain labeled as live-test gates.

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
| [ConsulScriptum](https://github.com/bukowa/ConsulScriptum/tree/95085275d9ad20167e72231a7c3304ab04d97777) | `95085275d9ad20167e72231a7c3304ab04d97777`, 2026-05-28 | Current Rome II API/event dump, lifecycle guidance, diplomacy strings, vanilla-preserving loader pattern |
| [Total War Rome II docs](https://github.com/bukowa/twr2docs/tree/aeaece2b77f5ae7f197cf14184a367ce58a6e4e9) | `aeaece2b77f5ae7f197cf14184a367ce58a6e4e9`, 2026-04-25 | Rome II Lua loading order |
| [Rome II Lua Profiler](https://github.com/bukowa/rome2_luaprofiler/tree/00a5cda98a3c12fe06ea7fca2ac627f5dac3d859) | `00a5cda98a3c12fe06ea7fca2ac627f5dac3d859` | Working `all_scripted.lua` pack pattern |
| [Official Rome II Seasons and Wonders update](https://wiki.totalwar.com/w/Total_War_ROME_II%3A_Season_and_Wonders_Update.html) | Published CA wiki | Rome II's three-argument `show_message_event` signature and numeric `custom_event_` key rule |
| [Official Attila campaign interface](https://wiki.totalwar.com/w/Total_War%3A_ATTILA_KIT_-_Campaign_Script_Interface) | Published CA wiki | Sibling-engine signatures for effect bundles, treasury, peace, trade, diplomacy, and stance calls |

The audited event set is `LoadingGame`, `SavingGame`, `UICreated`, `FirstTickAfterWorldCreated`, `FactionTurnStart`, and `FactionLeaderDeclaresWar`. The current Rome II faction dump includes `imperium_level`, `is_human`, `region_list`, `military_force_list`, `treasury`, and no `is_dead` method. The current registry and vanilla EpisodicScripting expose the native logger as the table method `out.ting`, not callable `out()`.

## Decoded Workshop evidence

| Pack | Workshop page | SHA-256 | Use |
|---|---|---|---|
| Guaranteed Major Faction Empires | [233589292](https://steamcommunity.com/sharedfiles/filedetails/?id=233589292) | `c20f2273d86b0dde6f92097fc0eecad742a042e2d9a569ad207b2603dd6b342a` | Working Rome II three-argument status message, four-culture title/body Loc pattern, local campaign log, and historical loader/event patterns |
| Radious AI Mod – Patch 17 Only | [186967731](https://steamcommunity.com/sharedfiles/filedetails/?id=186967731) | `4778192e6c810d6b42290610d22c9180c06047e91034c08239aee8cba62bba55` | Vanilla-derived difficulty effect rows |
| Radious Campaign Features Mod – Patch 17 Only | [186967968](https://steamcommunity.com/sharedfiles/filedetails/?id=186967968) | `2c6b13e54699e5b3a523dc59c8d9536ef519c168d2b387594b736f6899df0fe8` | Effect/scope pairs and historical fame data |
| Increase army cap | [1082051626](https://steamcommunity.com/sharedfiles/filedetails/?id=1082051626) | `7cb69cb281192b6643cd9e3be5a911952587958da6d607bb5cf9f9b683bec996` | Public Grand Campaign fame-table layout and unchanged non-army columns; not copied as a balance mod |

The selected 21 effects and scopes are recorded exactly in the project balance matrix. Representative real values include construction turns `-3/-5/-7`, AI research points, public order, food, recruitment capacity, upkeep, replenishment, recruit rank, armour, faction-wide morale, melee damage, and experience gain. Proposed extreme values are World Resistance balance decisions, not claims that vanilla uses those values. Recruit-rank and melee-damage rows retain their evidenced `start_turn_initiated` advancement stage; other rows use an evidenced or common `start_turn_completed` stage.

## Community failure-mode research

- [Getae – Total Cheat Mod 2.2](https://steamcommunity.com/sharedfiles/filedetails/?id=265516523)
- [Baktria – Total Cheat Mod 2.2](https://steamcommunity.com/sharedfiles/filedetails/?id=201497202)
- [Better Economic & Military Management AI](https://steamcommunity.com/sharedfiles/filedetails/?id=2742800090)
- [Para Bellum clean-install troubleshooting](https://steamcommunity.com/workshop/filedetails/discussion/2010751524/4747300038104744049/)
- [Rome II outdated-mod discussion](https://steamcommunity.com/app/214950/discussions/0/38596747932133585/)

These are user reports rather than controlled reproductions. They define test cases—clean startup, construction sabotage/repair, contradictory diplomacy, stale files—not proven root causes.

## Preserved local evidence

The research workspace preserves:

- the RPFM schema snapshot and a generated full schema-column manifest;
- exact decoded candidate effect rows and compact verified difficulty rows;
- original acquired reference packs and SHA-256 manifests;
- current Rome II loader, API, event, and runtime registry extracts;
- historical script examples retained as evidence only, never shipped as overrides.

The release pack contains only the records needed to run World Resistance. Research packs and third-party scripts are not redistributed in the installable mod.
