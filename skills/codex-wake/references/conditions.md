# Designing a condition

The probe must be read-only, bounded, and non-interactive:

- exit zero and emit text matching `--match` only when the condition is satisfied;
- otherwise exit nonzero or omit the match;
- include terminal failure states when they should wake Codex for diagnosis;
- attach stdin to `/dev/null` and enforce a timeout;
- read authoritative state rather than relying on an incidental log line;
- avoid placing the complete match token inside an echoed command.

Use a stable semantic `--probe-key` for comparable calls. Calibration measures wall time, child CPU,
host load, and failures, then chooses an interval that limits polling duty. Repeated probe failures
back off up to `--max-seconds`.

For a remote workload, separate lifecycle from workload health when either can disappear
independently. A platform state such as `RUNNING` proves allocation, not application health. Use the
platform/domain skill to build those probes, then give their read-only commands to `codex-wake`.
