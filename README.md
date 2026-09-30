# codex-wake

A Codex skill for calibrating a low-impact persistent watcher and resuming or steering the exact
same VS Code Codex sidebar thread when a read-only condition becomes true.

This repository contains one skill at `skills/codex-wake`. It is **not** a Codex plugin.

## Required companion skill

`codex-wake` deliberately depends on [`codex-bg`](https://github.com/ZhaoRunyi/codex-bg) for the
shared app-server, sidebar bridge, and thread ownership checks. They remain separate skills and
separate repositories so each can be versioned and installed independently.

Install in this order:

```text
Use $skill-installer to install ZhaoRunyi/codex-bg from path skills/codex-bg.
Use $skill-installer to install ZhaoRunyi/codex-wake from path skills/codex-wake.
```

Restart Codex, configure and verify `codex-bg`, then run:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/codex-wake/scripts/bootstrap_runtime.sh"
```

The generic watcher accepts any bounded, read-only probe. Platform-specific lifecycle and health
checks belong in the corresponding domain skill.

## Security and state

Watcher state and calibration evidence live under `${CODEX_HOME:-$HOME/.codex}/wakes` and are not
stored in the skill. Never commit credentials, probe commands, job IDs, raw output, thread IDs, or
wake logs.
