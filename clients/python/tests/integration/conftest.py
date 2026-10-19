"""Own a disposable Ruby server, including startup failures and teardown."""

from __future__ import annotations

import os
import queue
import subprocess
import threading
import time
from collections import deque
from collections.abc import Iterator
from pathlib import Path

import httpx
import pytest


@pytest.fixture(scope="session")
def ruby_server() -> Iterator[str]:
    root = Path(__file__).resolve().parents[4]
    env = dict(os.environ, BUNDLE_GEMFILE=str(root / "servers/ruby/Gemfile"))
    process = subprocess.Popen(
        [
            "bundle",
            "exec",
            "ruby",
            "-r",
            str(root / "clients/python/tests/fixtures/token_challenge.rb"),
            "servers/ruby/test_support/client_test_server.rb",
        ],
        cwd=root,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    lines: queue.Queue[str | None] = queue.Queue()
    output: deque[str] = deque(maxlen=100)

    def read_output() -> None:
        assert process.stdout is not None
        for line in process.stdout:
            output.append(line)
            lines.put(line)
        lines.put(None)

    reader = threading.Thread(target=read_output, daemon=True)
    reader.start()
    try:
        deadline = time.monotonic() + 30
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                pytest.fail("Ruby server readiness timed out:\n" + "".join(output))
            try:
                line = lines.get(timeout=remaining)
            except queue.Empty:
                pytest.fail("Ruby server readiness timed out:\n" + "".join(output))
            if line is None:
                pytest.fail("Ruby server exited before readiness:\n" + "".join(output))
            if line.startswith("HAVEAPI_TEST_SERVER_READY "):
                url = line.split()[1]
                break
        with httpx.Client(trust_env=False, timeout=5) as client:
            client.get(url + "/__health").raise_for_status()
        yield url
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        reader.join(timeout=5)
        if process.stdout is not None:
            process.stdout.close()


@pytest.fixture
def server_url(ruby_server: str) -> str:
    with httpx.Client(trust_env=False, timeout=5) as client:
        client.post(ruby_server + "/__reset", json={}).raise_for_status()
    return ruby_server
