"""Use the prepared Ruff version, including the native executable on NixOS."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from importlib.metadata import version


def main() -> int:
    executable = os.environ.get("HAVEAPI_RUFF") or shutil.which("ruff")
    if executable is None:
        raise SystemExit("Ruff is unavailable; enter the Nix shell or run uv sync")
    expected = f"ruff {version('ruff')}"
    actual = subprocess.check_output([executable, "--version"], text=True).strip()
    if actual != expected:
        raise SystemExit(
            "Ruff version differs from the prepared environment: "
            f"expected {expected}, got {actual}"
        )
    return subprocess.call([executable, *sys.argv[1:]])


if __name__ == "__main__":
    raise SystemExit(main())
