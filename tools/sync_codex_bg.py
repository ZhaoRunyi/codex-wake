#!/usr/bin/env python3
"""Refresh the vendored codex-bg skill from a checked-out upstream repository."""

from __future__ import annotations

import argparse
import hashlib
import os
import pathlib
import shutil
import subprocess


REPO = pathlib.Path(__file__).resolve().parents[1]
DESTINATION = REPO / "skills" / "codex-bg"


def tree_digest(root: pathlib.Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        if "__pycache__" in path.parts or path.suffix == ".pyc":
            continue
        digest.update(path.relative_to(root).as_posix().encode() + b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def atomic_text(path: pathlib.Path, value: str) -> None:
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temporary.write_text(value + "\n")
    os.replace(temporary, path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=pathlib.Path)
    args = parser.parse_args()
    source_repo = args.source.resolve()
    source_skill = source_repo / "skills" / "codex-bg"
    if not (source_skill / "SKILL.md").is_file():
        raise SystemExit(f"not a codex-bg checkout: {source_repo}")
    commit = subprocess.check_output(
        [
            "git",
            "-c",
            f"safe.directory={source_repo}",
            "-C",
            str(source_repo),
            "rev-parse",
            "HEAD",
        ],
        text=True,
    ).strip()
    if len(commit) != 40 or any(character not in "0123456789abcdef" for character in commit):
        raise SystemExit(f"unexpected upstream commit: {commit}")

    temporary = REPO / f".codex-bg.sync.{os.getpid()}"
    backup = REPO / f".codex-bg.previous.{os.getpid()}"
    shutil.copytree(
        source_skill,
        temporary,
        ignore=shutil.ignore_patterns("__pycache__", "*.pyc"),
    )
    try:
        DESTINATION.rename(backup)
        temporary.rename(DESTINATION)
    except Exception:
        if backup.exists() and not DESTINATION.exists():
            backup.rename(DESTINATION)
        raise
    shutil.rmtree(backup)
    atomic_text(REPO / ".codex-bg-version", commit)
    atomic_text(REPO / ".codex-bg-tree-sha256", tree_digest(DESTINATION))


if __name__ == "__main__":
    main()
