"""Check standalone wheel and sdist installation outside the source checkout."""

from __future__ import annotations

import os
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path


def run(*args: str, cwd: Path) -> None:
    subprocess.run(args, cwd=cwd, check=True)


def main() -> None:
    project = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="haveapi-python-package-") as directory:
        root = Path(directory)
        artifacts = root / "artifacts"
        run("uv", "build", "--out-dir", str(artifacts), cwd=project)
        source = next(artifacts.glob("*.tar.gz"))
        with tarfile.open(source) as archive:
            # Python 3.11 supports the extraction filter since 3.11.4.
            archive.extractall(root / "source", filter="data")
        extracted = next((root / "source").iterdir())
        run("uv", "build", "--wheel", "--out-dir", str(root / "rebuilt"), cwd=extracted)
        wheels = [next(artifacts.glob("*.whl")), next((root / "rebuilt").glob("*.whl"))]
        for index, wheel in enumerate(wheels):
            environment = root / f"venv-{index}"
            run("uv", "venv", "--python", sys.executable, str(environment), cwd=root)
            python = environment / (
                "Scripts/python.exe" if os.name == "nt" else "bin/python"
            )
            run("uv", "pip", "install", "--python", str(python), str(wheel), cwd=root)
            run(
                str(python),
                "-I",
                "-c",
                "import importlib.metadata as m; import importlib.resources as r; "
                "import haveapi_client as c; "
                "assert c.__version__ == m.version('haveapi-client'); "
                "assert r.files(c).joinpath('py.typed').is_file()",
                cwd=root,
            )
    print("Wheel and standalone sdist installation passed")


if __name__ == "__main__":
    main()
