"""Validate Python distribution identities without importing packaged code."""

from __future__ import annotations

import email.parser
import stat
import sys
import tarfile
import tomllib
import zipfile
from pathlib import Path, PurePosixPath


def metadata_matches(content: bytes, version: str) -> None:
    metadata = email.parser.BytesParser().parsebytes(content)
    if metadata.get_all("Name") != ["haveapi-client"] or metadata.get_all(
        "Version"
    ) != [version]:
        raise ValueError("Wrong Python package identity")


def safe_name(name: str) -> None:
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts:
        raise ValueError(f"Unsafe Python archive entry: {name}")


def inspect(directory: Path, version: str) -> None:
    prefix = f"haveapi_client-{version}"
    wheel = directory / f"{prefix}-py3-none-any.whl"
    with zipfile.ZipFile(wheel) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError("Duplicate Python wheel entries")
        for entry in archive.infolist():
            safe_name(entry.filename)
            if stat.S_ISLNK(entry.external_attr >> 16):
                raise ValueError("Python wheel contains a symlink")
        metadata_matches(archive.read(f"{prefix}.dist-info/METADATA"), version)
        for name in (
            "haveapi_client/__init__.py",
            "haveapi_client/py.typed",
            f"{prefix}.dist-info/licenses/LICENSE.txt",
        ):
            if name not in names:
                raise ValueError(f"Python wheel is missing {name}")
    with tarfile.open(directory / f"{prefix}.tar.gz") as archive:
        seen = set()
        files = {}
        for entry in archive:
            safe_name(entry.name)
            if entry.name in seen:
                raise ValueError("Duplicate Python sdist entries")
            seen.add(entry.name)
            if entry.isdir():
                continue
            if not entry.isfile():
                raise ValueError("Python sdist contains a nonregular entry")
            stream = archive.extractfile(entry)
            assert stream is not None
            files[entry.name] = stream.read()
        metadata_matches(files[f"{prefix}/PKG-INFO"], version)
        project = tomllib.loads(files[f"{prefix}/pyproject.toml"].decode())["project"]
        if project["name"] != "haveapi-client" or project["version"] != version:
            raise ValueError("Wrong Python sdist project identity")
        for name in (
            "LICENSE.txt",
            "src/haveapi_client/__init__.py",
            "src/haveapi_client/py.typed",
        ):
            if f"{prefix}/{name}" not in files:
                raise ValueError(f"Python sdist is missing {name}")


if __name__ == "__main__":
    inspect(Path(sys.argv[1]), sys.argv[2])
