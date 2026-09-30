# Operations

## Dry-run

```bash
skill_root="${CODEX_HOME:-$HOME/.codex}/skills/codex-wake"
"$skill_root/scripts/start_watch.sh" start \
  --name example-ready \
  --session-id "$CODEX_THREAD_ID" \
  --probe-key example-status \
  --probe-command 'READ_ONLY_BOUNDED_COMMAND' \
  --match 'READY|FAILED' \
  --prompt 'Overall task: incomplete; the external condition is still pending and work must continue. This watcher: reread the authoritative status; on READY continue the task, and on FAILED diagnose it.' \
  --dry-run
```

Dry-run calibrates and evaluates once without creating a detached process.

## Arm

Remove `--dry-run` from the same command. A real launch returns immediately after creating a
detached `screen`. Trust `wake_rpc_ready=true`, not merely the existence of that screen.

The prompt must remain actionable after a long delay:

- `Overall task:` explicitly state whether the whole task is complete, the current evidence or
  blocker, and whether work must continue.
- `This watcher:` name the condition, evidence to reread, next action for every matched state, and
  any stop or approval boundary.

## Inspect and cancel

```bash
"$skill_root/scripts/start_watch.sh" status example-ready
"$skill_root/scripts/start_watch.sh" cancel example-ready
```

`status` includes worker PID liveness and is more authoritative than a stale `screen -ls` entry.
Cancel obsolete or superseded sibling watchers explicitly.
