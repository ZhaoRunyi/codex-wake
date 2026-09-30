# Troubleshooting

- **`codex-bg is required`:** install it at the standard skill path or set
  `CODEX_BG_SKILL_ROOT`.
- **`wake_rpc_ready=false`:** polling is alive, but the shared sidebar bridge or thread claim is not
  ready. Reload the target VS Code window through `codex-bg`, then inspect status again.
- **Daemon configuration stale:** reload through the `codex-bg` wrapper. Do not fork the thread to
  pick up a configuration change.
- **Probe errors:** inspect `latest_probe.log`; fix authentication, timeout, or state lookup, then
  cancel and replace the watcher. Repeated errors deliberately back off.
- **Condition changed before delivery:** this is expected; the worker re-arms rather than waking on
  stale evidence.
- **New user message after arming:** the resumed agent must reread the thread, absorb compatible new
  constraints, and cancel obsolete watchers. It must not blindly continue a superseded task.
- **Host restart:** detached processes and sockets do not survive. Runtime evidence remains, but the
  watcher must be verified and armed again.
