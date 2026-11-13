"""Exercise pin synchronization and updater Git boundaries without remote writes."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

UTILS = Path(__file__).resolve().parent
OLD_REV = "a" * 40
NEW_REV = "b" * 40
PROJECT = b'[dependency-groups]\ndev = ["ruff==1.2.3", "pytest>=9"]\n'
NIX = """#!/usr/bin/env python3
import json
import os
import pathlib
import sys
import tomllib

args = sys.argv[1:]
with open('nix-calls', 'a') as log:
    log.write(' '.join(args) + '\\n')
lock = pathlib.Path('flake.lock')
if args[:1] == ['shell'] and args[-1:] == ['nixpkgs']:
    if 'ls' in args:
        rev = json.loads(lock.read_text())['rev']
        print(json.dumps([{'input': 'nixpkgs', 'rev': rev}]))
    else:
        assert '--forward-only' in args
        if os.environ.get('UPDATE_EXIT'):
            sys.exit(int(os.environ['UPDATE_EXIT']))
        lock.write_text(json.dumps({'rev': os.environ['NEW_REV']}))
elif args[:1] == ['eval']:
    assert 'builtins.currentSystem' in args[-1]
    assert 'inputs.nixpkgs.legacyPackages' in args[-1]
    print(os.environ.get('RUFF_VERSION', '1.2.4'))
elif args == ['flake', 'check']:
    project = pathlib.Path('clients/python/pyproject.toml')
    requirements = tomllib.loads(project.read_text())['dependency-groups']['dev']
    assert 'ruff==' + os.environ.get('RUFF_VERSION', '1.2.4') in requirements
    sys.exit(int(os.environ.get('CHECK_EXIT', '0')))
elif args[:3] == ['develop', '.#client-python', '-c']:
    os.execvp(args[3], args[3:])
else:
    sys.exit('unexpected Nix invocation: ' + repr(args))
"""
UV = """#!/usr/bin/env python3
import os
import pathlib
import sys

args = sys.argv[1:]
with open('../../uv-calls', 'a') as log:
    log.write(' '.join(args) + '\\n')
if args == ['sync']:
    pathlib.Path('uv.lock').write_text('fixture local lock')
    sys.exit(int(os.environ.get('UV_SYNC_EXIT', '0')))
assert args[:4] == ['run', '--locked', 'python', 'utils/run_ruff.py']
if args[4:] == ['format', '--check', '.']:
    sys.exit(int(os.environ.get('RUFF_FORMAT_EXIT', '0')))
if args[4:] == ['check', '.']:
    sys.exit(int(os.environ.get('RUFF_CHECK_EXIT', '0')))
sys.exit('unexpected uv invocation: ' + repr(args))
"""


class UpdateNixpkgsTest(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="haveapi-update-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.project = self.root / "clients/python/pyproject.toml"
        self.project.parent.mkdir(parents=True)
        self.project.write_bytes(PROJECT)
        (self.root / "flake.lock").write_text(json.dumps({"rev": OLD_REV}))
        (self.root / "utils").mkdir()
        for name in ("update-nixpkgs.sh", "sync-ruff.py"):
            (self.root / "utils" / name).write_bytes((UTILS / name).read_bytes())
        (self.root / "utils/update-nixpkgs.sh").chmod(0o755)
        (self.root / "bin").mkdir()
        nix = self.root / "bin/nix"
        nix.write_text(NIX)
        nix.chmod(0o755)
        uv = self.root / "bin/uv"
        uv.write_text(UV)
        uv.chmod(0o755)
        self.env = dict(
            os.environ,
            PATH=str(nix.parent) + os.pathsep + os.environ["PATH"],
            CONFCTL_FLAKE="fixture-pinned-confctl",
            NEW_REV=NEW_REV,
        )
        self.git("init", "--initial-branch=fixture")
        self.git("config", "user.name", "Updater Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("add", "flake.lock", "clients", "utils")
        message = self.root / "message"
        message.write_text("Initialize updater fixture\n")
        self.git("commit", "-F", str(message))
        self.head = self.git("rev-parse", "HEAD").stdout

    def git(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["git", *args],
            cwd=self.root,
            env=self.env,
            check=True,
            capture_output=True,
            text=True,
        )

    def update(self, **env: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["./utils/update-nixpkgs.sh"],
            cwd=self.root,
            env=dict(self.env, **env),
            capture_output=True,
            text=True,
        )

    def sync(self, version: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, "utils/sync-ruff.py", version],
            cwd=self.root,
            capture_output=True,
            text=True,
        )

    def assert_no_commit(self) -> None:
        self.assertEqual(self.git("rev-parse", "HEAD").stdout, self.head)

    def test_replacement_preserves_unrelated_toml_bytes(self) -> None:
        source = (
            b"# ruff==1.2.3\r\n[dependency-groups]\r\n"
            b"dev = [\"pytest>=9\", 'RuFf == 1.2.3'] # comment\r\n"
            b'other = ["RuFf == 1.2.3"]\r\n'
        )
        self.project.write_bytes(source)
        result = self.sync("1.2.4")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.project.read_bytes(), source.replace(b"1.2.3'", b"1.2.4'", 1)
        )

    def test_same_pin_does_not_write(self) -> None:
        before = self.project.stat().st_mtime_ns
        self.assertEqual(self.sync("1.2.3").returncode, 0)
        self.assertEqual(self.project.read_bytes(), PROJECT)
        self.assertEqual(self.project.stat().st_mtime_ns, before)

    def test_invalid_requirements_fail_without_writing(self) -> None:
        for requirements in (
            "[]",
            '["pytest>=9"]',
            '["ruff==1.2.3", "Ruff==1.2.3"]',
            '["ruff>=1.2.3"]',
            '["ruff[extra]==1.2.3"]',
            '["ruff==1.2"]',
        ):
            with self.subTest(requirements=requirements):
                source = f"[dependency-groups]\ndev = {requirements}\n".encode()
                self.project.write_bytes(source)
                self.assertNotEqual(self.sync("1.2.4").returncode, 0)
                self.assertEqual(self.project.read_bytes(), source)

    def test_invalid_versions_fail_without_writing(self) -> None:
        for version in ("", "1.2", "1.2.4rc1", "1.2.4\n", "unexpected"):
            with self.subTest(version=version):
                self.assertNotEqual(self.sync(version).returncode, 0)
                self.assertEqual(self.project.read_bytes(), PROJECT)

    def test_update_commits_only_checked_lock_and_pin(self) -> None:
        (self.root / "unrelated").write_text("untracked local content")
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.git("diff-tree", "--no-commit-id", "--name-only", "-r", "HEAD").stdout,
            "clients/python/pyproject.toml\nflake.lock\n",
        )
        self.assertEqual(
            self.git("log", "-1", "--format=%s").stdout.strip(),
            f"flake: nixpkgs {OLD_REV[:11]} -> {NEW_REV[:11]}",
        )
        self.assertEqual(self.project.read_bytes(), PROJECT.replace(b"1.2.3", b"1.2.4"))
        self.assertEqual(
            (self.root / "uv-calls").read_text().splitlines(),
            [
                "sync",
                "run --locked python utils/run_ruff.py format --check .",
                "run --locked python utils/run_ruff.py check .",
            ],
        )

    def test_unchanged_ruff_commits_only_lock(self) -> None:
        result = self.update(RUFF_VERSION="1.2.3")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.project.read_bytes(), PROJECT)
        self.assertEqual(
            self.git("diff-tree", "--no-commit-id", "--name-only", "-r", "HEAD").stdout,
            "flake.lock\n",
        )

    def test_no_input_update_skips_version_and_checks(self) -> None:
        result = self.update(NEW_REV=OLD_REV)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_no_commit()
        self.assertNotIn("eval", (self.root / "nix-calls").read_text())
        self.assertNotIn("flake check", (self.root / "nix-calls").read_text())
        self.assertEqual(self.project.read_bytes(), PROJECT)
        self.assertFalse((self.root / "uv-calls").exists())

    def test_dirty_inputs_and_unrelated_index_reject_before_nix(self) -> None:
        for name in ("flake.lock", "clients/python/pyproject.toml", "unrelated"):
            path = self.root / name
            original = path.read_bytes() if path.exists() else None
            path.write_text("pre-existing content")
            if name != "unrelated":
                self.assertNotEqual(self.update().returncode, 0)
            self.git("add", name)
            self.assertNotEqual(self.update().returncode, 0)
            self.assert_no_commit()
            self.assertFalse((self.root / "nix-calls").exists())
            self.git("restore", "--staged", name)
            if original is None:
                path.unlink()
            else:
                path.write_bytes(original)

    def test_failed_check_leaves_no_commit_or_staging(self) -> None:
        result = self.update(CHECK_EXIT="1")
        self.assertNotEqual(result.returncode, 0)
        self.assert_no_commit()
        self.assertEqual(self.git("diff", "--cached", "--name-only").stdout, "")
        self.assertEqual(self.project.read_bytes(), PROJECT.replace(b"1.2.3", b"1.2.4"))

    def test_failed_guard_does_not_reach_sync_or_check(self) -> None:
        self.assertNotEqual(self.update(UPDATE_EXIT="1").returncode, 0)
        self.assert_no_commit()
        self.assertEqual(self.project.read_bytes(), PROJECT)
        self.assertNotIn("eval", (self.root / "nix-calls").read_text())
        self.assertNotIn("flake check", (self.root / "nix-calls").read_text())

    def assert_python_failure(self, calls: int, **env: str) -> None:
        self.assertNotEqual(self.update(**env).returncode, 0)
        self.assert_no_commit()
        self.assertEqual(self.git("diff", "--cached", "--name-only").stdout, "")
        self.assertEqual(len((self.root / "uv-calls").read_text().splitlines()), calls)

    def test_failed_uv_sync_leaves_no_commit_or_staging(self) -> None:
        self.assert_python_failure(1, UV_SYNC_EXIT="1")

    def test_failed_format_leaves_no_commit_or_staging(self) -> None:
        self.assert_python_failure(2, RUFF_FORMAT_EXIT="1")

    def test_failed_lint_leaves_no_commit_or_staging(self) -> None:
        self.assert_python_failure(3, RUFF_CHECK_EXIT="1")


if __name__ == "__main__":
    unittest.main()
