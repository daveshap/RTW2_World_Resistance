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

## Compatibility matrix

World Resistance is self-contained in one pack and needs no framework or companion mod. It still edits shared Rome II resources.

| Other mod type | Expected compatibility | Reason |
|---|---|---|
| Reskins, models, textures, battle audio | Usually compatible | No shared campaign tables or loader expected |
| Unit roster or battle-stat mods | Often compatible | World Resistance applies faction effects, but armour modifiers will combine |
| Economy, research, public-order, upkeep, recruitment, or difficulty mods | Balance conflict likely | Additive modifiers can exceed intended ceilings |
| Grand Campaign army-cap / Imperium mods | Incompatible | Shared `fame_levels` rows |
| Mod replacing `lua_scripts/all_scripted.lua` | Incompatible without a manual merge | Rome II has one loader path; last loaded file wins |
| Diplomacy or CAI overhaul | High conflict risk | Both systems may constrain the same AI-to-AI deals and stances |
| Total campaign overhaul | Unsupported | Campaign key, region count, DB rows, and loader assumptions may differ |
| Startpos or force-spawning mod | Unsupported combination | Harder to isolate lifecycle and cap failures |

Rome II's `all_scripted.lua` does not have a safe automatic multi-mod append mechanism. A compatibility patch must preserve the seven vanilla imports, assign `events = triggers.events`, and protected-load both mods after that assignment.

## Why Normal campaign difficulty is the initial target

World Resistance caps its own construction, recruitment, upkeep, and mercenary reductions at `-90%`. Vanilla campaign difficulty, technologies, buildings, characters, and another mod can add to the same scalar. Patch-17 vanilla-derived evidence includes AI upkeep modifiers down to roughly `-30%` and unit-cost modifiers down to roughly `-25%`.

The database accepts a finite value below `-100`, but that does not establish safe economic behavior. Start on Normal. Harder campaign difficulties must be tested for zero/negative prices and unexpected payments before being recommended.

## Verification completed without the game

The source was designed and checked against:

- the current RPFM Rome II schema snapshot and exact table field types;
- real decoded PFH4 Rome II Workshop rows for all selected effect/scope pairs;
- a current Rome II scripting API and event dump;
- Lua 5.1 syntax and pure/mocked simulations, including all-faction eligibility and the no-human-diplomacy invariant;
- deterministic PFH4 structure tests and pack round-trip tooling.

These checks reduce guessed-key and malformed-pack risk. They cannot verify native engine behavior. This environment does not contain the paid Rome II data depot, Assembly Kit dependency cache, or a runnable Rome II executable, so this beta has **not** completed a real frontend cold boot, first turn, end turn, battle return, or soak test.

Treat any generated validation report as structural evidence, not an in-game certification.

## Required live smoke test

Use a disposable profile or backed-up saves. Test with no other mods before combining anything.

1. Ensure no stale copy of this pack or an older similarly named pack remains in `data` or the launcher list.
2. Enable only `wr2_world_resistance.pack`.
3. Cold-start to the main menu. A failure before the menu points first to pack/schema/loader conflicts.
4. Start a new Grand Campaign and reach the first human turn.
5. Confirm the human receives none of the nine `wr2_wr_` bundles and no treasury grant.
6. Inspect several neutral, allied, client, distant, and hostile AI factions. Every active AI should receive one base bundle; weak ones should receive one catch-up bundle as well.
7. Confirm an AI can legally raise armies toward the 16-army cap without any spawned or duplicate force.
8. End at least one full turn and watch for a freeze during the faction sequence.
9. Save, exit to menu, reload, and verify bundles did not duplicate and treasury was not granted repeatedly within one turn.
10. Enter a battle, return to campaign, and continue an AI turn.
11. Damage or sabotage a building under construction, then repair, capture, and convert it. Confirm the `-7` construction-turn effect respects a one-turn floor and does not break repair state.
12. At a disposable high-pressure state, verify AI-to-AI peace, inability to declare ordinary AI wars, protected agreements, and direct legal trade attempts. Also verify AI can still declare war on and negotiate with the human normally.
13. Test Normal first, then each intended campaign difficulty. Check construction and recruitment prices and upkeep for negative or nonsensical values.
14. Run at least 20 AI turns at high pressure and inspect logs after every save/load and battle return.

## Specific acceptance criteria

- The game reaches the campaign map from a cold process with only this pack enabled.
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
- exact pack filename and SHA-256 from the release report;
- the last successful step: menu, campaign load, first turn, end turn, save/load, or battle return;
- the relevant `script_error` or modified log excerpt;
- whether the failure reproduces with only World Resistance enabled from a clean process.
