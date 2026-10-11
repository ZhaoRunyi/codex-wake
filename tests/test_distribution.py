from __future__ import annotations

import hashlib
import pathlib
import unittest


REPO = pathlib.Path(__file__).resolve().parents[1]
BG = REPO / "skills" / "codex-bg"
WAKE = REPO / "skills" / "codex-wake"


def tree_digest(root: pathlib.Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        relative = path.relative_to(root).as_posix()
        if "__pycache__" in path.parts or path.suffix == ".pyc":
            continue
        digest.update(relative.encode() + b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


class DistributionTests(unittest.TestCase):
    def test_bundled_dependency_matches_manifest(self):
        expected = (REPO / ".codex-bg-tree-sha256").read_text().strip()
        self.assertEqual(tree_digest(BG), expected)

    def test_core_delivery_scripts_have_one_owner(self):
        self.assertTrue((BG / "scripts" / "wake_thread.py").is_file())
        self.assertTrue((BG / "scripts" / "thread_marker.py").is_file())
        self.assertFalse((WAKE / "scripts" / "wake_thread.py").exists())
        self.assertFalse((WAKE / "scripts" / "thread_marker.py").exists())
        launcher = (WAKE / "scripts" / "start_watch.sh").read_text()
        self.assertIn('wake_script="$codex_bg_root/scripts/wake_thread.py"', launcher)
        self.assertIn('marker_script="$codex_bg_root/scripts/thread_marker.py"', launcher)

    def test_upstream_commit_is_pinned(self):
        commit = (REPO / ".codex-bg-version").read_text().strip()
        self.assertRegex(commit, r"^[0-9a-f]{40}$")


if __name__ == "__main__":
    unittest.main()
