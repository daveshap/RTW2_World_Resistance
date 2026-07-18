# Crash-safety notes

## What “safe” means here

No Rome II mod can be proven crash-safe by static analysis alone. Database decoding, Lua simulation, and protected calls catch many errors, but only the game can exercise native campaign code and CAI edge cases.

This beta is deliberately engineered to minimize the most common startup and campaign risks. It is not described as live-game certified because a Rome II executable and current `data.pack` dependency cache were unavailable in the build environment.

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

If the child Lua module raises a normal Lua error, the protected import logs it and leaves the vanilla loader alive. That protects against a campaign-load abort caused by a Lua exception; it cannot recover from a malformed DB file or native engine fault.

World mutation is deferred until `FirstTickAfterWorldCreated`. `LoadingGame` only restores primitive named values. The director is idempotent across new-game creation, load, and return from battle, and a same-session guard ignores a duplicate first-tick callback.

Every interface read and engine call is protected and fails closed for that target. Invalid faction keys and dormant zero-region/zero-force records are ignored. Diplomacy has an independent AI-only guard immediately before each pair call.

The status UI uses Rome II's documented `show_message_event(event_key, x, y)` path and proven vanilla message assets. It does not construct, search, divorce, replace, or patch UI components. The call waits for both `UICreated` and a successful world reconciliation, is protected, and is never made from `LoadingGame`.

Local diagnostics use append-only `io.open` access to `data/wr2_world_resistance.log`. Open, write, flush, and close are all protected. The first failure permanently disables that file sink for the Lua session while the campaign director and native `out.ting` logging continue.

## Performance safeguards

Pairwise diplomacy is potentially quadratic when many factions survive. The director processes at most 80 previously unreconciled pairs on the first tick or a human turn and 20 on an AI turn. Work resumes on later callbacks instead of issuing thousands of commands on one loading frame.

War-declaration handling resolves only the declaring AI and compares it with the active AI list. It does not run a full all-pairs audit inside the event.

Structured `STATE` output is limited to once per human turn. Detailed per-AI audits run only at session start, at a new tier high, and every tenth turn; pair-by-pair diplomacy is never written to the local file.

The script does not create forces. Force spawning, especially in invalid or occupied locations, is a known source of campaign instability and turn-sequence freezes. AI army parity is pursued through legal cap access, money, recruitment slots, rank, replenishment, and low costs.

## Why global building rewrites were rejected

Editing every `building_levels` row to force `create_time=1` would affect the human, overwrite DLC/current rows, enlarge the conflict surface, and couple the mod to building sabotage/repair state. Workshop users have reported one-turn building edits failing to apply consistently and, in one case, a sabotaged construction becoming unrepairable.

World Resistance instead applies the proven faction effect `rom_tech_module_engineering_construction` with observed values no lower than `-7`, leaving building records intact. The expected one-turn floor still requires live sabotage, repair, capture, and conversion tests.

## Why global CAI personality rewrites were rejected

Personality and treaty-value tables are not pair-specific to AI relationships and can also alter behavior toward the human. A Workshop report describes a diplomacy mod where a friendly neighbor declared war and then accepted cheap peace, illustrating that several CAI decision layers can disagree.

World Resistance uses pair-scoped script controls after checking that both endpoints are AI. At high pressure it combines cooperative stance promotion, protected agreements, disabled ordinary war/join-war offers, and repeated forced peace. This is narrower and auditable, although a hard-coded incident could still bypass normal diplomacy temporarily.

## Relevant community failure reports

These reports are warnings, not controlled proof of root cause:

- [Getae – Total Cheat Mod 2.2](https://steamcommunity.com/sharedfiles/filedetails/?id=265516523): a user reported that most intended one-turn construction changes did not work even with no other mods.
- [Baktria – Total Cheat Mod 2.2](https://steamcommunity.com/sharedfiles/filedetails/?id=201497202): a user reported that a sabotaged building under construction could no longer be repaired.
- [Better Economic & Military Management AI](https://steamcommunity.com/sharedfiles/filedetails/?id=2742800090): a comment describes apparently contradictory war and peace behavior despite good relations.
- [Para Bellum clean-install troubleshooting](https://steamcommunity.com/workshop/filedetails/discussion/2010751524/4747300038104744049/): warns that Workshop and Rome II cache state can survive an apparent unsubscribe.
- [Rome II outdated-mod discussion](https://steamcommunity.com/app/214950/discussions/0/38596747932133585/): reports recovery after removing stale packs and resubscribing.

These findings shaped the clean-test requirement, minimal DB surface, protected loader, pair-scoped diplomacy, and construction repair test. They do not establish that every reported problem had the same cause.

## Residual risks that need the game

1. **Fame-level resolution.** The AI-only negative prestige-threshold strategy is structurally valid and avoids spawning, but must be observed in a current Grand Campaign. The game must give AI factions the final 16-army row while leaving human progression unchanged. The pack intentionally uses the decoded, backward-compatible v4 Grand Campaign row shape. Converting it to another schema version without first extracting the matching live `main_rome` rows would replace verified fields with assumptions.
2. **Current foreign keys.** The selected effect/scope pairs decode from real Rome II packs and match the current RPFM schema, but a live dependency-cache check against the installed current `data.pack` remains the strongest gate.
3. **External stacking.** `-90%` may combine with campaign-difficulty or other modifiers below `-100%`.
4. **Construction floor.** A negative seven-turn effect is evidenced; exact one-turn clamping and repair behavior are empirical.
5. **Native diplomacy behavior.** `pcall` can catch a bad Lua binding call, not a crash inside native code. Odd or emergent factions need soak testing.
6. **Scripted wars.** Campaign incidents can potentially bypass ordinary treaty permissions; repeated peace enforcement should close them but needs observation.
7. **Loader ownership.** Another enabled mod that replaces `all_scripted.lua` can silently prevent one director from loading or can remove vanilla imports.
8. **PANTHEON/JUPITER.** New official rules may invalidate campaign, schema, Imperium, and army-cap assumptions.
9. **Message localization.** The additive Loc file is English and covers the four proven Rome II culture keys. Other client languages need a live display test; missing text should be cosmetic, but has not been observed here.
10. **Local file permissions.** A protected game install may reject `data/wr2_world_resistance.log`. This is designed to disable diagnostics rather than gameplay, but the live fallback behavior still needs observation.

## Recovery if a test fails

1. Do not overwrite the only copy of the affected save.
2. Close Rome II completely.
3. Disable World Resistance in the launcher and move only `wr2_world_resistance.pack` out of the game's `data` directory.
4. Check for stale copies with similar names and for subscribed Workshop versions that the launcher may still activate.
5. Launch a clean vanilla Grand Campaign from a fresh process. If vanilla also fails, the problem is not isolated to this pack.
6. Restore the pre-mod save rather than continuing a save that may contain AI forces above the vanilla cap.
7. Report the exact lifecycle point and logs using the template in [Compatibility and testing](COMPATIBILITY_AND_TESTING.md#useful-bug-report).

Do not delete broad Steam, game, or user-data directories while troubleshooting. Isolate the exact pack first.
