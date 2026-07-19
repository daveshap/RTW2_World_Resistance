# World Resistance for Total War: ROME II

World Resistance is a standalone anti-steamroll campaign mod. As the human empire grows, **every active AI faction** receives stronger economic, military, research, stability, and diplomatic support. War status, alliance status, client status, diplomatic contact, culture, and distance do not affect eligibility.

The intended end state is deliberately unfair: once the human is a hegemon, the rest of the world can build, recruit, replenish, research, and finance near-peer armies at extreme speed, while AI factions increasingly cooperate with one another.

> **Release status: 0.1.6 pre-PANTHEON beta.** Release 0.1.5 completed the first successful native Grand Campaign reconciliation: both logs reached their ready/state records, the activation popup appeared once, all active AI factions received their maximum-pressure packages, and all 91 surviving AI pairs were processed. Release 0.1.6 keeps that proven activation path and adds stricter AI-only coalition stances, accurate field-army telemetry and mobilization goals, and bounded logs. It targets only the current public original Grand Campaign (`main_rome`) as researched through 2026-07-19; read [Compatibility and testing](docs/COMPATIBILITY_AND_TESTING.md) before using it in a campaign you care about.

## What it does

- Scales all living, active non-human factions from turn one. There is no frontline, enemy, ally, client, contact, or distance exception.
- Uses the human share of world territory as the primary pressure signal. Human general-led field-army count and treasury are smaller secondary signals; settlement garrisons no longer inflate the army signal.
- Establishes a permanent endgame pressure floor when the human reaches final vanilla Imperium, then keeps scaling with territory until maximum pressure at roughly 70% of the map.
- Gives each AI exactly one global pressure bundle and, when it is behind, one additional catch-up bundle based on its worst shortfall in regions, armies, or treasury.
- Raises AI treasuries toward human-relative and replacement-reserve floors. The script only adds funds; it never removes them.
- Gives Grand Campaign AI access to the final legal 16-army cap from the start while retaining the human's normal Imperium thresholds and 3-to-16 progression. Each AI's mobilization comparison target is `min(4 × regions, human parity target, 16)`, so one city does not imply a demand for 16 stacks. It does not spawn armies.
- Makes strategic behavior progressively more cooperative **only between AI factions**. At Tier 85 and above, every AI-to-AI direction is locked to `BEST_FRIENDS` and force-refreshed; protected agreements, blocked ordinary war/join-war offers, and repeated peace enforcement remain in place.
- Never makes the AI friendlier to the human and never applies a World Resistance bundle or diplomatic command to a human faction.
- Shows a native Rome II campaign message after the first successful reconciliation and at each new resistance-tier high.
- Writes structured, local-only diagnostics to `data/wr2_world_resistance.log`; both local logs rotate at 1,000 lines and nothing is transmitted or uploaded.

At maximum pressure, a severely behind AI receives the Tier 100 package plus Catch-up 3:

| System | Maximum contribution from this mod |
|---|---:|
| Construction time | -7 turns |
| Construction, recruitment, normal upkeep, and mercenary costs | -90% each |
| Building GDP / tax | +600% / +150% |
| Land / naval recruitment capacity | +12 / +9 |
| Replenishment | +50 percentage points |
| Recruit rank / armour / morale | +9 / +10 / +10 |
| Melee damage / experience gain | +10% / +15% |
| Research | +600% and +375 flat points |
| Public order / food / growth | +400 / +5000 / +35 |

This does not guarantee that the campaign AI will make perfect decisions or choose an ideal elite roster. It gives every AI the legal capacity, money, throughput, resilience, and diplomatic protection needed to remain dangerous. It does not unlock faction-ineligible units, spawn forces, prescribe rosters, or replace CAI budget/personality tables.

Rome II's diplomacy power bar primarily reflects military forces already fielded. World Resistance does **not** create armies or instantly fill existing armies with units, so that bar is not an immediate activation indicator. Once reconciliation succeeds, recruitment capacity, cost, rank, replenishment, treasury, and the legal army cap let every AI build toward parity through normal campaign recruitment. A weak faction—especially in a save that began without WR—can therefore remain visibly weak for several turns while mobilizing.

## Installation

1. Close Rome II.
2. Remove or move **every older World Resistance pack** from the game's `data` directory. In particular, remove the 0.1.1 file named `wr2_world_resistance.pack`; do not leave both releases installed.
3. Copy `@wr2_world_resistance.pack` from `dist` into the game's `data` directory, normally:

   ```text
   ...\Steam\steamapps\common\Total War Rome II\data
   ```

   The leading `@` is intentional and is part of the exact filename.
4. Open the Rome II launcher and enable **only** `@wr2_world_resistance.pack` for the clean first test.
5. Keep the original release archive so you can restore the exact build used by a save.

No other gameplay or framework mod is required. “Standalone” means all World Resistance mechanics are in this one pack; it does not mean the pack can safely coexist with every overhaul. In particular, do not enable another pack that replaces `lua_scripts/all_scripted.lua`, and avoid army-cap or `fame_levels` mods. See the [compatibility matrix](docs/COMPATIBILITY_AND_TESTING.md#compatibility-matrix).

The **No Civil War** and **Stable Politics** mods are DB-only and do not replace World Resistance's Lua loader, so they are compatible with WR's activation path. Leave them disabled for the clean smoke test, then re-enable them after WR has passed it.

## Recommended first run

With the game closed, first move or delete any old WR logs so the new session is unambiguous. Enable only `@wr2_world_resistance.pack`, then launch a disposable Grand Campaign or a **copy** of an existing `main_rome` save. Confirm that the activation message appears, inspect both logs described below, end one turn, save and load, and return from a battle. Then run several AI turns before adding any other mods.

A copied, mid-flight original Grand Campaign is valid for proving that 0.1.6 attaches and activates: 0.1.5 successfully reconciled the user's existing maximum-pressure save. It cannot retroactively give the AI the development time it would have received on earlier turns, however. A new Grand Campaign on Normal campaign difficulty remains the supported balance path for the intended full-campaign experience.

Do not add or remove this beta in the middle of an important campaign. Removing an army-cap override while an AI owns more forces than its restored cap has not been validated.

## How to verify it is running

Release 0.1.6 has two separate, local-only logs. The first starts in the root loader, before the campaign interface exists:

```text
...\Total War Rome II\wr2_world_resistance_bootstrap.log
```

Every bootstrap line includes a `load=<id>` field. That ID groups lines from one evaluation of `all_scripted.lua`, so a rolling file containing several game or campaign loads can be read without guessing where one attempt ends and another begins. The file never exceeds 1,000 lines; when full, it keeps the newest 800 before appending again.

On a normal first setup, one load ID should show the loader route, the explicit event-registry handoff, and six successful listener insertions:

```text
LOADER_START
EVENT_REGISTRY_READY (source=export_triggers)
MODULE_PATH_READY
DIRECTOR_ROUTE_TRY
DIRECTOR_ROUTE_OK
DIRECTOR_REQUIRE_OK
DIRECTOR_SETUP_TRY
EVENT_REGISTRY_READY (source=loader_argument)
LISTENER_OK_LoadingGame
LISTENER_OK_SavingGame
LISTENER_OK_UICreated
LISTENER_OK_FirstTickAfterWorldCreated
LISTENER_OK_FactionTurnStart
LISTENER_OK_FactionLeaderDeclaresWar
LISTENERS_READY
ENGINE_WAIT
DIRECTOR_SETUP_OK
```

`ENGINE_WAIT` at `director_setup` is expected when Rome II has not published its campaign interface yet. A normal block contains two `EVENT_REGISTRY_READY` lines: `source=export_triggers` proves the root loader has the vanilla registry, and `source=loader_argument` proves the director accepted the argument. Their opaque `registry=` values must match. The decisive attachment result is that the **same** load ID reaches `DIRECTOR_REQUIRE_OK`, both matching registry stages, all six `LISTENER_OK_*` stages, `LISTENERS_READY`, and `DIRECTOR_SETUP_OK`. `DIRECTOR_REQUIRE_OK` by itself proves only that the module imported.

World Resistance does not import `EpisodicScripting` early or wait for a special `NewSession` handoff. The root loader temporarily prepends the pack-owned route `script/campaign/wr2/?.lua`, imports `wr2_world_resistance`, and restores Rome II's original `package.path`. It then calls the returned module's `setup` function with the exact local `triggers.events` table. The director registers its six callbacks on that argument; it no longer assumes that a loader-assigned `events` global is visible from the imported module's environment. On later events it reads the `game_interface` already published by Rome II's own campaign script.

As the campaign continues, that same load ID should add event and world milestones such as:

```text
EVENT_HIT_LoadingGame
ENGINE_READY
EVENT_HIT_UICreated
EVENT_HIT_FirstTickAfterWorldCreated
WORLD_ATTEMPT
DIAGNOSTIC_SINK_READY
WORLD_STATE
WORLD_READY
```

A new campaign need not emit `EVENT_HIT_LoadingGame`, and the first event that can see the interface may vary. `FirstTickAfterWorldCreated` is the normal activation point. Every attempt now emits `WORLD_ATTEMPT`; a failed probe is followed by the specific `WORLD_PROBE_FAIL`, `WORLD_UNSUPPORTED`, or `WORLD_NO_HUMAN` reason and then `WORLD_WAIT`. Until initialization succeeds, the first delivered `FactionTurnStart` in each campaign turn retries regardless of whether that event's context faction is human or AI; the world scan itself finds and protects the human. `DIRECTOR_ROUTE_ERROR` or `DIRECTOR_REQUIRE_ERROR` means the protected director import failed. `DIRECTOR_API_ERROR`, `DIRECTOR_SETUP_ERROR`, or `DIRECTOR_SETUP_PARTIAL` means the module imported but listener attachment was not accepted.

The 0.1.4 trace established the loader, exact event-registry handoff, all six listeners, event dispatch, and interface discovery, then exposed its incorrect zero-argument `campaign_name()` call. Release 0.1.5 corrected that predicate and the subsequent live files reached `DIAGNOSTIC_SINK_READY`, `WORLD_STATE`, `WORLD_READY`, `SESSION_START`, `STATE`, and complete faction/pair audits. The activation popup appeared once and did not repeat after a full exit, reload, and another turn. Release 0.1.6 preserves that live-proven route.

For the clean retest, close Rome II, move or archive the old logs, verify that only the new WR pack is installed and enabled, and start or load a copied original Grand Campaign. New records should identify `0.1.6-beta`. For one load ID, require a successful route, `DIRECTOR_SETUP_TRY`, both matching `EVENT_REGISTRY_READY` stages, six `LISTENER_OK_*` stages, `LISTENERS_READY`, and `DIRECTOR_SETUP_OK`; then require at least one later `EVENT_HIT_...`, `ENGINE_READY`, `WORLD_ATTEMPT`, `WORLD_STATE`, and finally `WORLD_READY`. `DIAGNOSTIC_SINK_READY` confirms the detailed file opened; `DIAGNOSTIC_SINK_ERROR` identifies a real file-sink failure without disabling gameplay. If several load IDs appear, evaluate each ID separately rather than combining milestones from different blocks.

The second log begins only after the director completes a supported Grand Campaign reconciliation:

```text
...\Total War Rome II\data\wr2_world_resistance.log
```

It writes one `STATE` record per human turn, plus a faction-by-faction audit at session start, tier escalation, and every tenth turn. Each audit now includes a `DIPLOMACY_AUDIT` line between its begin marker and faction rows. A new `SESSION_START` followed by `STATE` and `AI_AUDIT_BEGIN`/`DIPLOMACY_AUDIT`/`AI`/`AI_AUDIT_END` proves that WR reached and processed the campaign world. After that first successful reconciliation, Rome II should also show a **WORLD RESISTANCE ACTIVE** message identifying the current tier. Later messages appear only when the campaign reaches a new tier high, so reloads and temporary tier demotions do not spam the UI.

For example:

```text
WR2|schema=1|event=STATE|release=0.1.6-beta|director=8|campaign=main_rome|turn=42|human=rom_rome|human_regions=61|world_regions=173|map_pct=35|commanded_armies=16|garrison_armies=61|army_units=320|full_armies=16|treasury=245000|imperium=7|pressure=70|floor=65|tier=65|tier_index=3|desired_tier=65|diplomacy_peak=65|active_ai=34|target_armies=16|ai_commanded_armies=90|ai_army_goal=500|ai_full_armies=24|ai_factions_at_army_goal=3|catchup_0=4|catchup_1=8|catchup_2=11|catchup_3=11|base_commands_ok=34|catchup_commands_ok=34|bundle_changes=68|grant_count=31|grant_total=2450000
```

An `AI` record identifies the selected bundles, treasury target/grant, general-led field armies, garrisons, field-army unit total, 20-unit full stacks, mobilization goal, and shortfall for each active AI. `DIPLOMACY_AUDIT` reports directional AI-to-AI and AI-to-human attitude count/minimum/average/maximum values plus stance-lock readback counts. These are observations, not a claimed numeric attitude write: the audited interface has a read method but no safe pair-specific numeric attitude setter. `base_command_ok=true` likewise means the protected engine call returned and the director cached that selection; Rome II exposes no audited effect-bundle readback API. The bootstrap `WORLD_STATE` summary independently makes the activation boundary visible.

If the bootstrap file is absent, first confirm that the exact `@wr2_world_resistance.pack` is enabled and the old pack is absent; a protected installation root can also prevent that file from opening. If the bootstrap exists but the detailed `data/wr2_world_resistance.log` does not, read the world stages before blaming the path. `DIAGNOSTIC_SINK_READY` or `DIAGNOSTIC_SINK_ERROR` explicitly settles the detailed-file question after reconciliation. Both files have a hard 1,000-line ceiling and retain the newest 800 lines when rotating. If safe line tracking or rewrite fails, that file batch is skipped rather than written blindly; compact traces still go to Rome II's native `out.ting` sink when available, and gameplay continues.

## Design summary

The pressure curve has six bands: 0, 20, 40, 65, 85, and 100. Territory is continuously interpolated between those points rather than waiting for a single Imperium threshold. Tier promotion is immediate; economic tier demotion is slow. Anti-hegemonic diplomacy is a saved high-water mark and never becomes less cooperative later in the campaign.

Full mechanics and numbers are in [Design](docs/DESIGN.md).

## Important limits

- This build is only for the pre-PANTHEON Grand Campaign (`main_rome`). It deliberately becomes inert in other campaigns.
- The forthcoming PANTHEON/JUPITER branch changes Imperium and army-cap assumptions and needs a separate adapter. This pack intentionally encodes the backward-compatible `fame_levels` v4 Grand Campaign row shape found in decoded stable Rome II packs. The RPFM schema also contains later table layouts, but their presence predates PANTHEON and is not evidence that they describe the forthcoming update.
- The ordinary AI-to-AI war path is disabled at high pressure, but a hard-coded campaign incident could bypass normal diplomacy. The script listens for declarations and forces AI peace again; only live soak testing can prove complete coverage.
- The API can enable and protect alliances, but there is no audited Rome II command that instantly creates an alliance. Universal alliance formation is encouraged, not guaranteed.
- At Tier 85 and above, WR hard-locks every processed AI-to-AI direction to `BEST_FRIENDS` and force-refreshes it. This controls CAI strategic stance, not the diplomacy screen's historical relation score. Rome II exposes `faction_attitudes()` for audit reads, but no safe pair-specific numeric setter; WR therefore does not claim or fake a visible `+300` modifier.
- The diplomacy power bar measures already-fielded military strength, not WR's treasury, construction, research, or future recruitment capacity. Because WR deliberately does not spawn units or armies, parity develops through accelerated legal recruitment rather than appearing instantly after activation.
- `-90%` reducers can stack with campaign difficulty, technologies, traits, or other mods. Normal campaign difficulty is the initial balance target; higher difficulties require a live economy test.
- A protected Lua call can contain a Lua error, but it cannot catch a native engine crash.
- The status message uses a custom English localization file. A non-English installation may display missing/fallback text; that should be cosmetic, but still needs a live locale test.

## Project layout

| Path | Purpose |
|---|---|
| `dist/` | Installable PFH4 mod pack |
| `pack_root/lua_scripts/` | Vanilla-preserving root loader |
| `pack_root/script/campaign/wr2/` | Pack-routed campaign director |
| `config/bundle_matrix.json` | Machine-readable balance contract |
| `db_src/` | Source TSVs used to construct the pack |
| `tests/` | Pure calculation, mocked engine, and PFH4 tests |
| `tools/` | Deterministic pack/build validation utilities |
| `validation/` | Machine-readable build report, RPFM round trips, and test summary |
| `docs/` | Design, compatibility, safety, and source notes |

## Documentation

- [Design](docs/DESIGN.md)
- [Compatibility and testing](docs/COMPATIBILITY_AND_TESTING.md)
- [Observability and local diagnostics](docs/OBSERVABILITY.md)
- [Crash-safety notes](docs/CRASH_SAFETY.md)
- [Research sources](docs/SOURCES.md)
- [Validation report](validation/TEST_REPORT.md)
- [Changelog](CHANGELOG.md)
