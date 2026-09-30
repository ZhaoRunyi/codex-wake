# Setup

Prerequisites are Linux/POSIX, `bash`, `screen`, Python 3.10+, and a working `codex-bg` shared
sidebar daemon.

Install `codex-bg` before `codex-wake`, then run:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/codex-wake/scripts/bootstrap_runtime.sh"
```

The runtime is stored at `${CODEX_HOME:-$HOME/.codex}/skill-runtimes/codex-wake`. Set
`CODEX_WAKE_PYTHON` only when another Python environment already provides `websockets`.

Check the dependencies without arming a watcher:

```bash
test -x "${CODEX_HOME:-$HOME/.codex}/skills/codex-wake/scripts/start_watch.sh"
test -f "${CODEX_HOME:-$HOME/.codex}/skills/codex-bg/scripts/frontend_scope.py"
```

Runtime state defaults to `${CODEX_HOME:-$HOME/.codex}/wakes`. Override it with
`CODEX_WAKE_STATE_ROOT` only for isolation tests or an intentionally separate installation.
