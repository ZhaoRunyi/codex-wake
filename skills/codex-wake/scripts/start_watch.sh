#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
codex_home="${CODEX_WAKE_CODEX_HOME:-${CODEX_HOME:-$HOME/.codex}}"
python_binary="${CODEX_WAKE_PYTHON:-$codex_home/skill-runtimes/codex-wake/bin/python}"
[[ -x "$python_binary" ]] || python_binary="$(command -v python3 || true)"
state_root="${CODEX_WAKE_STATE_ROOT:-$codex_home/wakes}"
marker_script="$script_dir/thread_marker.py"
wake_script="$script_dir/wake_thread.py"
calibration_script="$script_dir/calibrate_poll.py"
codex_bg_root="${CODEX_BG_SKILL_ROOT:-$codex_home/skills/codex-bg}"
frontend_scope_script="$codex_bg_root/scripts/frontend_scope.py"
config_guard_script="$codex_bg_root/scripts/daemon_config_guard.py"
daemon_socket="${CODEX_APP_SERVER_SOCKET:-$codex_home/app-server-control/app-server-control.sock}"
bridge_marker="${CODEX_FRONTEND_BRIDGE_MARKER:-$codex_home/app-server-control/frontend-bridge.inode}"

usage() {
    cat <<'EOF'
Usage:
  start_watch.sh start [options]
  start_watch.sh status NAME
  start_watch.sh cancel NAME

Start options:
  --name NAME
  --session-id ID
  --probe-key KEY
  --probe-command SHELL_COMMAND
  --match REGEX
  --workdir PATH
  --prompt TEXT
  --probe-timeout N
  --calibration-samples N
  --min-seconds N
  --max-seconds N
  --dry-run
EOF
}

write_status() {
    printf '%s %s\n' "$(date --iso-8601=seconds)" "$1" \
        >"$watch_dir/status.$$"
    mv "$watch_dir/status.$$" "$watch_dir/status"
}

shared_frontend_ready() {
    [[ -n "${session_id:-}" ]] || return 1
    daemon_config_current || return 1
    "$python_binary" "$frontend_scope_script" \
        --session-id "$session_id" \
        --socket "$daemon_socket" \
        --bridge-marker "$bridge_marker" >/dev/null || detached_claim_ready
}

daemon_config_current() {
    "$python_binary" "$config_guard_script" check \
        --codex-home "$codex_home" \
        --socket "$daemon_socket" >/dev/null 2>&1
}

detached_claim_ready() {
    "$python_binary" -c '
import json, os, sys
claim = json.load(open(sys.argv[1]))
valid = claim.get("session_id") == sys.argv[2] and claim.get("socket_inode") == os.stat(sys.argv[3]).st_ino
raise SystemExit(0 if valid else 1)
' "$codex_home/app-server-control/thread-claims/$session_id.json" \
        "$session_id" "$daemon_socket" 2>/dev/null
}

frontend_wait_reason() {
    if ! daemon_config_current; then
        "$python_binary" "$config_guard_script" check \
            --codex-home "$codex_home" \
            --socket "$daemon_socket" 2>/dev/null \
            | "$python_binary" -c 'import json,sys; print(json.load(sys.stdin).get("reason", "daemon-config-stale"))' \
            || true
        return
    fi
    "$python_binary" "$frontend_scope_script" \
        --session-id "$session_id" \
        --socket "$daemon_socket" \
        --bridge-marker "$bridge_marker" 2>/dev/null || true
}

resume_ready() {
    local wake_status=0
    while [[ ! -S "$daemon_socket" ]]; do
        write_status "ready-waiting-shared-daemon"
        sleep 1
    done
    while ! shared_frontend_ready; do
        write_status "ready-waiting-$(frontend_wait_reason)"
        sleep 1
    done
    write_status "waking"
    "$python_binary" "$wake_script" \
        --session-id "$(<"$watch_dir/session_id")" \
        --prompt "$(<"$watch_dir/prompt")" \
        --marker "$watch_dir/thread_marker.json" \
        --codex-home "$codex_home" \
        --socket "$daemon_socket" \
        >>"$watch_dir/wake.log" 2>&1 || wake_status=$?
    if ((wake_status == 0)); then
        write_status "completed"
    else
        write_status "wake-failed exit=$wake_status"
    fi
    return "$wake_status"
}

command_name="${1:-}"
case "$command_name" in
    status)
        [[ $# == 2 ]] || { usage >&2; exit 2; }
        watch_dir="$state_root/$2"
        [[ -f "$watch_dir/status" ]] || { echo "Unknown watcher: $2" >&2; exit 2; }
        cat "$watch_dir/status"
        if [[ -r "$watch_dir/worker_pid" ]] && [[ -d "/proc/$(<"$watch_dir/worker_pid")" ]]; then
            echo "worker_alive=true pid=$(<"$watch_dir/worker_pid")"
        else
            echo "worker_alive=false"
        fi
        [[ -f "$watch_dir/calibration.json" ]] && cat "$watch_dir/calibration.json"
        [[ -f "$watch_dir/latest_probe.log" ]] && tail -n 20 "$watch_dir/latest_probe.log"
        [[ -f "$watch_dir/wake.log" ]] && tail -n 20 "$watch_dir/wake.log"
        exit 0
        ;;
    cancel)
        [[ $# == 2 ]] || { usage >&2; exit 2; }
        watch_dir="$state_root/$2"
        screen -S "codex_wake_$2" -X quit 2>/dev/null || true
        if [[ -r "$watch_dir/worker_pid" ]]; then
            kill "$(<"$watch_dir/worker_pid")" 2>/dev/null || true
        fi
        mkdir -p "$watch_dir"
        write_status "canceled"
        exit 0
        ;;
    start)
        shift
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

watch_name=""
session_id="${CODEX_THREAD_ID:-}"
probe_key=""
probe_command=""
match_regex=""
workdir="$PWD"
prompt=""
probe_timeout=30
calibration_samples=3
min_seconds=15
max_seconds=86400
dry_run=false
run_child=false

while (($#)); do
    case "$1" in
        --name) watch_name="$2"; shift 2 ;;
        --session-id) session_id="$2"; shift 2 ;;
        --probe-key) probe_key="$2"; shift 2 ;;
        --probe-command) probe_command="$2"; shift 2 ;;
        --match) match_regex="$2"; shift 2 ;;
        --workdir) workdir="$2"; shift 2 ;;
        --prompt) prompt="$2"; shift 2 ;;
        --probe-timeout) probe_timeout="$2"; shift 2 ;;
        --calibration-samples) calibration_samples="$2"; shift 2 ;;
        --min-seconds) min_seconds="$2"; shift 2 ;;
        --max-seconds) max_seconds="$2"; shift 2 ;;
        --dry-run) dry_run=true; shift ;;
        --run-child) run_child=true; shift ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ -z "$prompt" ]]; then
    echo "start requires --prompt with the condition-specific task for the resumed agent" >&2
    exit 2
fi

[[ "$watch_name" =~ ^[a-z0-9][a-z0-9-]{0,47}$ ]] || {
    echo "Watcher name must match [a-z0-9][a-z0-9-]{0,47}." >&2
    exit 2
}
[[ "$session_id" =~ ^[0-9a-fA-F-]{36}$ ]] || {
    echo "A UUID-shaped Codex session ID is required." >&2
    exit 2
}
[[ "$probe_key" =~ ^[a-z0-9][a-z0-9._-]{0,63}$ ]] || {
    echo "A stable lowercase --probe-key is required." >&2
    exit 2
}
[[ -n "$probe_command" ]] || { echo "--probe-command is required." >&2; exit 2; }
for numeric_value in \
    "$probe_timeout" "$calibration_samples" "$min_seconds" "$max_seconds"; do
    [[ "$numeric_value" =~ ^[1-9][0-9]*$ ]] || {
        echo "Probe timing options must be positive integers." >&2
        exit 2
    }
done
((min_seconds <= max_seconds)) || {
    echo "--min-seconds cannot exceed --max-seconds." >&2
    exit 2
}
[[ -d "$workdir" ]] || { echo "Workdir not found: $workdir" >&2; exit 2; }
[[ -x "$python_binary" ]] || { echo "Shared Codex Python is missing: $python_binary" >&2; exit 2; }
[[ -f "$frontend_scope_script" && -f "$config_guard_script" ]] || {
    echo "codex-bg is required; install it or set CODEX_BG_SKILL_ROOT." >&2
    exit 2
}

watch_dir="$state_root/$watch_name"
watch_screen="codex_wake_$watch_name"

run_probe() {
    local probe_status=0
    timeout "$probe_timeout" bash -lc "$probe_command" \
        </dev/null >"$watch_dir/latest_probe.tmp" 2>&1 || probe_status=$?
    mv "$watch_dir/latest_probe.tmp" "$watch_dir/latest_probe.log"
    ((probe_status == 0)) || return 2
    [[ -z "$match_regex" ]] || grep -Eq "$match_regex" "$watch_dir/latest_probe.log"
}

mkdir -p "$watch_dir"
calibration_args=(
    --probe-key "$probe_key"
    --command "$probe_command"
    --match "$match_regex"
    --samples "$calibration_samples"
    --timeout "$probe_timeout"
    --min-seconds "$min_seconds"
    --max-seconds "$max_seconds"
    --latest-output "$watch_dir/latest_probe.log"
    --reference-dir "$state_root/calibration"
)

if ! $run_child; then
    if $dry_run; then
        "$python_binary" "$calibration_script" "${calibration_args[@]}" \
            >"$watch_dir/calibration.json"
        condition_ready="$(
            "$python_binary" -c 'import json,sys; print(str(json.load(sys.stdin)["ready"]).lower())' \
                <"$watch_dir/calibration.json"
        )"
        cat "$watch_dir/calibration.json"
        printf 'condition=%s\n' "$($condition_ready && echo ready || echo waiting)"
        $condition_ready
        exit $?
    fi
    nspid_count="$(awk '/^NSpid:/ {print NF - 1}' /proc/self/status)"
    ((nspid_count == 1)) || {
        echo "Launch the real watcher in the host process namespace." >&2
        exit 2
    }
    exec 8>"$watch_dir/setup.lock"
    flock -n 8 || {
        echo "Another setup owns watcher $watch_name." >&2
        exit 2
    }
    screen -ls | grep -Fq ".$watch_screen" && {
        echo "Watcher screen already exists: $watch_screen" >&2
        exit 2
    }
    printf '%s' "$session_id" >"$watch_dir/session_id"
    printf '%s' "$prompt" >"$watch_dir/prompt"
    printf '%s' "$probe_command" >"$watch_dir/probe_command"
    printf '%s' "$match_regex" >"$watch_dir/match"
    chmod 600 "$watch_dir/session_id" "$watch_dir/prompt" \
        "$watch_dir/probe_command" "$watch_dir/match"
    write_status "launched calibration=pending"
    child_args=(
        start
        --run-child
        --name "$watch_name"
        --session-id "$session_id"
        --probe-key "$probe_key"
        --probe-command "$probe_command"
        --match "$match_regex"
        --workdir "$workdir"
        --prompt "$prompt"
        --probe-timeout "$probe_timeout"
        --calibration-samples "$calibration_samples"
        --min-seconds "$min_seconds"
        --max-seconds "$max_seconds"
    )
    screen -dmS "$watch_screen" "$0" "${child_args[@]}"
    screen -ls | grep -Fq ".$watch_screen" || {
        write_status "launch-failed"
        echo "Watcher did not enter detached screen: $watch_screen" >&2
        exit 2
    }
    for _ in {1..20}; do
        [[ -r "$watch_dir/worker_pid" ]] && break
        sleep 0.1
    done
    if shared_frontend_ready; then
        printf 'Started adaptive watcher %s; wake_rpc_ready=true; status=%s\n' \
            "$watch_name" "$watch_dir/status"
    else
        printf 'Started condition watcher %s; wake_rpc_ready=false reason=%s; status=%s\n' \
            "$watch_name" "$(frontend_wait_reason)" "$watch_dir/status"
    fi
    exit 0
fi

{
    worker_exit() {
        local worker_status=$?
        if ((worker_status != 0)); then
            write_status "worker-failed exit=$worker_status"
        fi
    }
    trap worker_exit EXIT
    printf '%s' "$$" >"$watch_dir/worker_pid"
    exec 9>"$watch_dir/lock"
    flock -n 9 || { echo "Another watcher owns $watch_name"; exit 2; }
    "$python_binary" "$marker_script" --session-id "$session_id" \
        --codex-home "$codex_home" >"$watch_dir/thread_marker.json"
    chmod 600 "$watch_dir/thread_marker.json"
    write_status "calibrating"
    "$python_binary" "$calibration_script" "${calibration_args[@]}" \
        >"$watch_dir/calibration.json"
    interval_seconds="$(
        "$python_binary" -c 'import json,sys; print(json.load(sys.stdin)["interval_seconds"])' \
            <"$watch_dir/calibration.json"
    )"
    printf '%s' "$interval_seconds" >"$watch_dir/interval_seconds"
    condition_ready="$(
        "$python_binary" -c 'import json,sys; print(str(json.load(sys.stdin)["ready"]).lower())' \
            <"$watch_dir/calibration.json"
    )"
    write_status "calibrated interval=${interval_seconds}s ready=$condition_ready"
    attempt=0
    poll_seconds="$interval_seconds"
    while true; do
        while ! $condition_ready; do
            write_status "waiting interval=${poll_seconds}s attempt=$attempt"
            sleep "$poll_seconds"
            attempt=$((attempt + 1))
            if run_probe; then
                condition_ready=true
            else
                probe_status=$?
                if ((probe_status == 2)); then
                    poll_seconds=$((poll_seconds * 2))
                    ((poll_seconds > max_seconds)) && poll_seconds="$max_seconds"
                else
                    poll_seconds="$interval_seconds"
                fi
            fi
        done
        write_status "ready attempt=$attempt"
        while [[ ! -S "$daemon_socket" ]]; do
            write_status "ready-waiting-shared-daemon"
            sleep 1
        done
        while ! shared_frontend_ready; do
            write_status "ready-waiting-$(frontend_wait_reason)"
            sleep 1
        done
        if run_probe; then
            if resume_ready; then
                trap - EXIT
                exit 0
            fi
            condition_ready=false
            poll_seconds="$interval_seconds"
            write_status "wake-failed rearming"
            continue
        fi
        condition_ready=false
        poll_seconds="$interval_seconds"
        write_status "condition-changed rearming"
    done
} >>"$watch_dir/watch.log" 2>&1
