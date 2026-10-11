#!/usr/bin/env bash
set -euo pipefail

codex_home="${CODEX_HOME:-$HOME/.codex}"
codex_bg_root="${CODEX_BG_SKILL_ROOT:-$codex_home/skills/codex-bg}"
bootstrap="$codex_bg_root/scripts/bootstrap_runtime.sh"
[[ -x "$bootstrap" ]] || {
    echo "codex-bg is required; install the bundled skill or set CODEX_BG_SKILL_ROOT." >&2
    exit 2
}
CODEX_HOME="$codex_home" "$bootstrap"
printf 'Codex Wake uses the shared codex-bg runtime: %s\n' \
    "${CODEX_BG_PYTHON:-$codex_home/skill-runtimes/codex-bg/bin/python}"
