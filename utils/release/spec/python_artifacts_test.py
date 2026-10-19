"""Exercise Python artifact identity and archive checks without registries."""

from __future__ import annotations

import importlib.util
import io
import tarfile
import tempfile
import unittest
import zipfile
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "python_artifacts.py"
SPEC = importlib.util.spec_from_file_location("python_artifacts", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class PythonArtifactsTest(unittest.TestCase):
    version = "1.2.3"
    prefix = "haveapi_client-1.2.3"

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="haveapi-artifact-test-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        metadata = b"Metadata-Version: 2.4\nName: haveapi-client\nVersion: 1.2.3\n"
        self.wheel_files = {
            f"{self.prefix}.dist-info/METADATA": metadata,
            f"{self.prefix}.dist-info/licenses/LICENSE.txt": b"MIT",
            "haveapi_client/__init__.py": b"",
            "haveapi_client/py.typed": b"",
        }
        self.source_files = {
            f"{self.prefix}/PKG-INFO": metadata,
            f"{self.prefix}/LICENSE.txt": b"MIT",
            f"{self.prefix}/pyproject.toml": (
                b'[project]\nname = "haveapi-client"\nversion = "1.2.3"\n'
            ),
            f"{self.prefix}/src/haveapi_client/__init__.py": b"",
            f"{self.prefix}/src/haveapi_client/py.typed": b"",
        }

    def write(self) -> None:
        with zipfile.ZipFile(
            self.directory / f"{self.prefix}-py3-none-any.whl", "w"
        ) as archive:
            for name, content in self.wheel_files.items():
                archive.writestr(name, content)
        with tarfile.open(self.directory / f"{self.prefix}.tar.gz", "w:gz") as archive:
            for name, content in self.source_files.items():
                entry = tarfile.TarInfo(name)
                entry.size = len(content)
                archive.addfile(entry, io.BytesIO(content))

    def inspect(self) -> None:
        self.write()
        MODULE.inspect(self.directory, self.version)

    def test_valid_pair(self) -> None:
        self.inspect()

    def test_wrong_wheel_identity(self) -> None:
        self.wheel_files[f"{self.prefix}.dist-info/METADATA"] = (
            b"Name: another-package\nVersion: 1.2.3\n"
        )
        with self.assertRaisesRegex(ValueError, "identity"):
            self.inspect()

    def test_missing_typing_marker(self) -> None:
        del self.wheel_files["haveapi_client/py.typed"]
        with self.assertRaisesRegex(ValueError, "missing"):
            self.inspect()

    def test_unsafe_wheel_path(self) -> None:
        self.wheel_files["../outside"] = b""
        with self.assertRaisesRegex(ValueError, "Unsafe"):
            self.inspect()

    def test_sdist_project_identity(self) -> None:
        self.source_files[f"{self.prefix}/pyproject.toml"] = (
            b'[project]\nname = "haveapi-client"\nversion = "9.9.9"\n'
        )
        with self.assertRaisesRegex(ValueError, "identity"):
            self.inspect()

    def test_unsafe_sdist_path(self) -> None:
        self.source_files["../outside"] = b""
        with self.assertRaisesRegex(ValueError, "Unsafe"):
            self.inspect()


if __name__ == "__main__":
    unittest.main()
