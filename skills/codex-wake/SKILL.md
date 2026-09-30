---
name: codex-wake
description: Calibrate and run a low-impact persistent watcher for a bounded read-only condition, then resume or steer the exact same VS Code Codex sidebar thread through codex-bg. Use for queued jobs, builds, downloads, approvals, files, or remote state that may outlive VS Code or SSH; not for ordinary synchronous waits.
---

# Codex Wake

Watch a condition outside the active Codex turn, then deliver a continuation to the same thread.
The watcher uses adaptive polling because many services expose snapshots rather than callbacks.

## Dependency

Install and verify `codex-bg` first. `codex-wake` uses its shared daemon, ownership guard, and
sidebar bridge; it must not create a second app-server. If the dependency is installed outside
`${CODEX_HOME:-$HOME/.codex}/skills/codex-bg`, set `CODEX_BG_SKILL_ROOT`.

## Route

1. Read [setup.md](references/setup.md) for first-time installation and dependency checks.
2. Read [conditions.md](references/conditions.md) to design a bounded, read-only, authoritative
   probe. Domain-specific lifecycle logic belongs in the domain skill, not in this generic skill.
3. Read [operations.md](references/operations.md) to dry-run, arm, inspect, cancel, and replace a
   watcher.
4. Read [troubleshooting.md](references/troubleshooting.md) when polling is alive but delivery is
   not ready, configuration changes, or the probe becomes invalid.

## Contract

- The root agent arms the real watcher with its own `CODEX_THREAD_ID`. A subagent may review or
  dry-run it but cannot wake the parent's thread.
- A launch is end-to-end ready only when it reports `wake_rpc_ready=true`. A live polling process
  with `wake_rpc_ready=false` is not successful delivery.
- Revalidate the condition immediately before wake. If it changed, resume calibrated polling.
- The continuation prompt must state the overall task status, this watcher's exact condition,
  authoritative evidence to reread, and the next action for each matched outcome.
- A matched condition is a handoff point, not proof that the overall task succeeded.
- Persist runtime state under `${CODEX_HOME:-$HOME/.codex}/wakes`; never commit probe commands,
  credentials, job IDs, outputs, calibration observations, thread IDs, or wake logs.
