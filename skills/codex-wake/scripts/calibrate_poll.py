#!/usr/bin/env python3
"""Measure a read-only probe, choose a low-impact cadence, and persist evidence."""

import argparse
import datetime
import fcntl
import json
import math
import os
import pathlib
import re
import resource
import statistics
import subprocess
import tempfile
import time


parser = argparse.ArgumentParser()
parser.add_argument("--probe-key", required=True)
parser.add_argument("--command", required=True)
parser.add_argument("--match", default="")
parser.add_argument("--samples", type=int, default=3)
parser.add_argument("--timeout", type=int, default=30)
parser.add_argument("--min-seconds", type=int, default=15)
parser.add_argument("--max-seconds", type=int, default=86400)
parser.add_argument("--latest-output", required=True)
parser.add_argument(
    "--reference-dir",
    default=os.environ.get("CODEX_WAKE_REFERENCE_DIR", ""),
)
args = parser.parse_args()

reference_dir = (
    pathlib.Path(args.reference_dir)
    if args.reference_dir
    else pathlib.Path(os.environ.get("CODEX_HOME", pathlib.Path.home() / ".codex"))
    / "wakes/calibration"
)
observations_path = reference_dir / "polling_observations.jsonl"
profiles_path = reference_dir / "polling_profiles.json"
playbook_path = reference_dir / "polling-playbook.md"


def cpu_snapshot():
    fields = pathlib.Path("/proc/stat").read_text().splitlines()[0].split()[1:]
    values = [int(field) for field in fields]
    idle = values[3] + (values[4] if len(values) > 4 else 0)
    return sum(values), idle


def run_probe():
    usage_before = resource.getrusage(resource.RUSAGE_CHILDREN)
    total_before, idle_before = cpu_snapshot()
    started = time.monotonic()
    try:
        result = subprocess.run(
            ["bash", "-lc", args.command],
            capture_output=True,
            stdin=subprocess.DEVNULL,
            text=True,
            timeout=args.timeout,
            check=False,
        )
        status = result.returncode
        output = result.stdout + result.stderr
    except subprocess.TimeoutExpired as error:
        status = 124
        stdout = error.stdout.decode(errors="replace") if isinstance(error.stdout, bytes) else error.stdout or ""
        stderr = error.stderr.decode(errors="replace") if isinstance(error.stderr, bytes) else error.stderr or ""
        output = stdout + stderr
    wall_seconds = time.monotonic() - started
    total_after, idle_after = cpu_snapshot()
    usage_after = resource.getrusage(resource.RUSAGE_CHILDREN)
    total_delta = max(total_after - total_before, 1)
    busy_fraction = 1.0 - (idle_after - idle_before) / total_delta
    child_cpu_seconds = (
        usage_after.ru_utime
        + usage_after.ru_stime
        - usage_before.ru_utime
        - usage_before.ru_stime
    )
    ready = status == 0 and (
        not args.match or re.search(args.match, output, re.MULTILINE) is not None
    )
    pathlib.Path(args.latest_output).write_text(output)
    return {
        "wall_seconds": wall_seconds,
        "child_cpu_seconds": max(child_cpu_seconds, 0.0),
        "system_busy_fraction": min(max(busy_fraction, 0.0), 1.0),
        "status": status,
        "ready": ready,
    }


measurements = []
for _ in range(max(args.samples, 1)):
    measurement = run_probe()
    measurements.append(measurement)
    if measurement["ready"]:
        break
    if len(measurements) < args.samples:
        time.sleep(1)

successful = [item for item in measurements if item["status"] == 0]
timing_measurements = successful or measurements
wall_p95 = max(item["wall_seconds"] for item in timing_measurements)
child_cpu_p95 = max(item["child_cpu_seconds"] for item in timing_measurements)
system_busy = statistics.mean(item["system_busy_fraction"] for item in measurements)
cpu_count = max(os.cpu_count() or 1, 1)
normalized_load = os.getloadavg()[0] / cpu_count
interval = max(
    args.min_seconds,
    math.ceil(wall_p95 / 0.02),
    math.ceil(child_cpu_p95 / 0.01),
)
if system_busy > 0.95 or normalized_load > 2.0:
    interval *= 4
elif system_busy > 0.8 or normalized_load > 1.0:
    interval *= 2
interval = min(interval, args.max_seconds)

observation = {
    "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "probe_key": args.probe_key,
    "samples": len(measurements),
    "probe_failures": len(measurements) - len(successful),
    "wall_p95_seconds": round(wall_p95, 6),
    "child_cpu_p95_seconds": round(child_cpu_p95, 6),
    "system_busy_fraction": round(system_busy, 6),
    "normalized_load": round(normalized_load, 6),
    "interval_seconds": interval,
    "ready": any(item["ready"] for item in measurements),
}

reference_dir.mkdir(parents=True, exist_ok=True)
lock_stream = (reference_dir / ".calibration.lock").open("a")
fcntl.flock(lock_stream, fcntl.LOCK_EX)
with observations_path.open("a") as stream:
    stream.write(json.dumps(observation, sort_keys=True) + "\n")

observations = [
    json.loads(line)
    for line in observations_path.read_text().splitlines()
    if line.strip()
]
profiles = json.loads(profiles_path.read_text()) if profiles_path.exists() else {}
profile = profiles.get(args.probe_key)
if profile:
    interval = min(
        max(interval, int(profile["interval_seconds"])),
        args.max_seconds,
    )
similar = [
    item
    for item in observations
    if item["probe_key"] == args.probe_key
    and item.get("probe_failures") == 0
][-5:]
promoted = False
if len(similar) == 5:
    wall_values = [item["wall_p95_seconds"] for item in similar]
    cpu_values = [item["child_cpu_p95_seconds"] for item in similar]
    busy_buckets = [
        0 if item["system_busy_fraction"] < 0.5
        else 1 if item["system_busy_fraction"] < 0.8
        else 2
        for item in similar
    ]
    wall_stable = max(wall_values) <= max(min(wall_values) * 1.5, min(wall_values) + 0.05)
    cpu_stable = max(cpu_values) <= max(min(cpu_values) * 1.5, min(cpu_values) + 0.02)
    if wall_stable and cpu_stable and len(set(busy_buckets)) == 1:
        profile_interval = math.ceil(
            statistics.median(item["interval_seconds"] for item in similar)
        )
        profiles[args.probe_key] = {
            "interval_seconds": profile_interval,
            "observations": 5,
            "updated_at": observation["timestamp"],
        }
        interval = min(max(interval, profile_interval), args.max_seconds)
        promoted = True

descriptor, temporary_name = tempfile.mkstemp(dir=reference_dir)
with os.fdopen(descriptor, "w") as stream:
    json.dump(profiles, stream, indent=2, sort_keys=True)
    stream.write("\n")
os.replace(temporary_name, profiles_path)

recent_rows = []
for item in observations[-20:]:
    recent_rows.append(
        f"| {item['timestamp'][:19]} | `{item['probe_key']}` | "
        f"{item['wall_p95_seconds']:.3f} | {item['child_cpu_p95_seconds']:.3f} | "
        f"{item['system_busy_fraction']:.2f} | {item['normalized_load']:.2f} | "
        f"{item.get('probe_failures', '?')} | {item['interval_seconds']} |"
    )
start_marker = "<!-- OBSERVATIONS_START -->"
end_marker = "<!-- OBSERVATIONS_END -->"
playbook = (
    playbook_path.read_text()
    if playbook_path.exists()
    else (
        "# Polling Calibration Playbook\n\n"
        "Generated observations from read-only condition probes.\n\n"
        f"{start_marker}\n{end_marker}\n"
    )
)
generated = (
    start_marker
    + "\n| UTC | probe key | wall p95 (s) | child CPU p95 (s) | system busy | normalized load | failures | interval (s) |\n"
    + "|---|---|---:|---:|---:|---:|---:|---:|\n"
    + "\n".join(recent_rows)
    + "\n"
    + end_marker
)
playbook = (
    playbook.split(start_marker, 1)[0]
    + generated
    + playbook.split(end_marker, 1)[1]
)
playbook_path.write_text(playbook)

observation["interval_seconds"] = interval
observation["promoted"] = promoted
print(json.dumps(observation, sort_keys=True))
