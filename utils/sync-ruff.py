"""Keep the exact Python Ruff dev pin aligned with the selected Nix package."""

from __future__ import annotations

import re
import sys
import tomllib
from pathlib import Path


def sync_ruff(path: Path, version: str) -> None:
    if re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version) is None:
        raise ValueError(f"invalid Nix Ruff version: {version!r}")

    text = path.read_bytes().decode("utf-8")
    document = tomllib.loads(text)
    groups = document.get("dependency-groups", {})
    if not isinstance(groups, dict) or not isinstance(groups.get("dev"), list):
        raise ValueError("expected a dev dependency group")
    requirements = groups["dev"]
    ruff = [
        (index, requirement)
        for index, requirement in enumerate(requirements)
        if isinstance(requirement, str)
        and re.match(r"\s*ruff(?:[^A-Za-z0-9._-]|$)", requirement, re.IGNORECASE)
    ]
    if len(ruff) != 1:
        raise ValueError("expected exactly one Ruff dev requirement")
    index, requirement = ruff[0]
    pin = re.fullmatch(
        r"\s*ruff\s*==\s*([0-9]+\.[0-9]+\.[0-9]+)\s*", requirement, re.IGNORECASE
    )
    if pin is None:
        raise ValueError("expected an exact Ruff dev pin (ruff==X.Y.Z)")
    if pin[1] == version:
        return

    requirements[index] = (
        requirement[: pin.start(1)] + version + requirement[pin.end(1) :]
    )
    candidates = []
    for match in re.finditer(r"(['\"])" + re.escape(requirement) + r"\1", text):
        start = match.start() + 1 + pin.start(1)
        end = match.start() + 1 + pin.end(1)
        updated = text[:start] + version + text[end:]
        if tomllib.loads(updated) == document:
            candidates.append(updated)
    if len(candidates) != 1:
        raise ValueError(
            "could not identify one Ruff dev pin without changing other TOML"
        )
    path.write_bytes(candidates[0].encode("utf-8"))
    print(f"Python Ruff: {pin[1]} -> {version}")


if __name__ == "__main__":
    try:
        sync_ruff(Path("clients/python/pyproject.toml"), sys.argv[1])
    except (IndexError, OSError, UnicodeError, ValueError) as error:
        sys.exit(f"error: {error}")
