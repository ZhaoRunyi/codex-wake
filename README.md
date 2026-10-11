# codex-wake

A Codex skill for calibrating a low-impact persistent watcher and resuming or steering the exact
same VS Code Codex sidebar thread when a read-only condition becomes true.

This repository is a self-contained distribution with `skills/codex-wake` plus a pinned copy of its
runtime dependency at `skills/codex-bg`. It is **not** a Codex plugin.

## Required companion skill

`codex-wake` deliberately depends on [`codex-bg`](https://github.com/ZhaoRunyi/codex-bg) for the
shared app-server, sidebar bridge, and thread ownership checks. The pinned copy in this repository
makes a fresh `codex-wake` installation independent of the other repository; the top-level
`.codex-bg-version` records the upstream commit.

After a `codex-bg` release, maintainers can run `python tools/sync_codex_bg.py <codex-bg-checkout>`
to refresh the vendored tree and both provenance files. The ordinary CI then validates the pinned
tree; publishing the resulting change remains an explicit reviewed action.

Install in this order:

```text
Use $skill-installer to install ZhaoRunyi/codex-wake from path skills/codex-bg.
Use $skill-installer to install ZhaoRunyi/codex-wake from path skills/codex-wake.
```

Restart Codex, configure and verify `codex-bg`, then run:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/codex-wake/scripts/bootstrap_runtime.sh"
```

The generic watcher accepts any bounded, read-only probe. Platform-specific lifecycle and health
checks belong in the corresponding domain skill.

The current implementation was synchronized from a working Remote SSH deployment on 2026-10-11
against Codex CLI `0.162.0-alpha.17.2` and the OpenAI VS Code extension
`26.1007.21434-linux-x64`. Same-thread delivery inherits `codex-bg`'s version-sensitive verification
requirement and its client-lease/idle daemon update policy.

## Security and state

Watcher state and calibration evidence live under `${CODEX_HOME:-$HOME/.codex}/wakes` and are not
stored in the skill. Never commit credentials, probe commands, job IDs, raw output, thread IDs, or
wake logs.
