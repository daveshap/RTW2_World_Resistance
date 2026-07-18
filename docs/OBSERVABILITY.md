# Observability and local diagnostics

World Resistance exposes its campaign director through a native Rome II message and an append-only local diagnostic stream. This is deliberately not remote telemetry: the mod contains no network code and uploads nothing.

## In-game status

The first successful Grand Campaign reconciliation queues a standard Rome II message for the current resistance tier. Another message appears only when a higher tier is reached. The highest acknowledged tier is saved as an integer, so loading, returning from battle, or temporarily losing territory does not repeat old messages.

The six status messages correspond to pressure bands 0, 20, 40, 65, 85, and 100. They use the official three-argument Rome II `show_message_event(event_key, 0, 0)` interface, additive DB rows, and existing vanilla image/icon/audio assets. The mod never edits the UI component tree.

## Diagnostic file

The target path is relative to the Rome II installation:

```text
data/wr2_world_resistance.log
```

Each line uses a stable pipe-delimited format:

```text
WR2|schema=1|event=STATE|release=0.1.1-beta|director=3|key=value|...
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

## Failure behavior

All file operations are protected. If the installation is read-only, `io` is unavailable, or a write/flush/close fails, the director disables the file sink for that Lua session. Scaling, treasury, and diplomacy processing continue.

Compact session/state/audit-boundary records are also sent through Rome II's `out.ting` sink. A file failure produces one native warning rather than repeating every turn.

The status message is attempted only after both `UICreated` and successful world reconciliation. It is never invoked during `LoadingGame`. A missing message API or localization failure cannot authorize any additional campaign mutation.
