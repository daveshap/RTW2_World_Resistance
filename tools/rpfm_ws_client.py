#!/usr/bin/env python3
"""Reliable client for RPFM 5's local WebSocket IPC endpoint.

RPFM 5.0.5 exposes both MCP-over-HTTP and the native WebSocket IPC protocol.
The 5.0.5 MCP session manager can terminate the server between otherwise valid
requests.  The WebSocket endpoint drives the same serial background worker but
keeps one connection/session for the complete build, so the pack build uses it
instead.

This module intentionally exposes the native JSON command format.  Examples::

    session.call({"SetGameSelected": ["rome_2", False]})
    result = session.call("NewPack")

Tuple enum variants are encoded as a one-key object; unit variants are strings.
RPFM errors are promoted to :class:`RpfmWsError`.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
from typing import Any
from urllib.error import URLError
from urllib.request import urlopen

try:
    from websockets.exceptions import ConnectionClosed
    from websockets.sync.client import connect
except ImportError as error:  # pragma: no cover - environment-specific message
    raise ImportError(
        "rpfm_ws_client requires the 'websockets' Python package (version 12+)"
    ) from error


class RpfmWsError(RuntimeError):
    """Raised when RPFM exits, rejects a command, or violates its IPC protocol."""


class RpfmWsSession:
    """Own one RPFM process and one native WebSocket IPC session.

    RPFM 5.0.5 always binds to ``127.0.0.1:45127``.  To avoid accidentally
    controlling an unrelated GUI/server process, startup verifies that the PID
    reported by ``/version`` matches the child process this object started.
    """

    def __init__(
        self,
        server: os.PathLike[str] | str,
        *,
        home: os.PathLike[str] | str,
        library_path: str | None = None,
        startup_timeout: float = 15.0,
        command_timeout: float = 120.0,
    ) -> None:
        self.server = Path(server).resolve()
        self.home = Path(home).resolve()
        self.library_path = library_path
        self.startup_timeout = startup_timeout
        self.command_timeout = command_timeout
        self.process: subprocess.Popen[bytes] | None = None
        self.socket: Any = None
        self.request_id = 0
        self.session_id: int | None = None
        self._stderr_file: Any = None
        self._stderr_path: Path | None = None

    def __enter__(self) -> "RpfmWsSession":
        if not self.server.is_file():
            raise RpfmWsError(f"RPFM server not found: {self.server}")
        self.home.mkdir(parents=True, exist_ok=True)
        (self.home / ".config").mkdir(parents=True, exist_ok=True)
        (self.home / ".local" / "share").mkdir(parents=True, exist_ok=True)

        # RPFM uses a fixed port.  A pre-existing listener would make it
        # ambiguous which process receives build commands, so fail closed.
        try:
            with urlopen("http://127.0.0.1:45127/version", timeout=0.25):
                raise RpfmWsError(
                    "RPFM port 45127 is already in use; close the other RPFM "
                    "server before building"
                )
        except URLError:
            pass

        environment = os.environ.copy()
        environment.update(
            {
                "HOME": str(self.home),
                "XDG_CONFIG_HOME": str(self.home / ".config"),
                "XDG_DATA_HOME": str(self.home / ".local" / "share"),
            }
        )
        if self.library_path:
            environment["LD_LIBRARY_PATH"] = self.library_path

        descriptor, stderr_name = tempfile.mkstemp(prefix="rpfm-server-", suffix=".log")
        os.close(descriptor)
        self._stderr_path = Path(stderr_name)
        self._stderr_file = self._stderr_path.open("wb")
        self.process = subprocess.Popen(
            [str(self.server)],
            env=environment,
            stdout=subprocess.DEVNULL,
            stderr=self._stderr_file,
        )

        try:
            self._wait_for_own_endpoint()
            self.socket = connect(
                "ws://127.0.0.1:45127/ws",
                max_size=None,
                open_timeout=min(self.startup_timeout, 15.0),
                close_timeout=1.0,
            )
            hello = self._receive(timeout=min(self.command_timeout, 15.0))
            payload = hello.get("data") if isinstance(hello, dict) else None
            if not (
                hello.get("id") == 0
                and isinstance(payload, dict)
                and isinstance(payload.get("SessionConnected"), int)
            ):
                raise RpfmWsError(f"invalid RPFM WebSocket greeting: {hello!r}")
            self.session_id = payload["SessionConnected"]
            return self
        except BaseException:
            self.__exit__()
            raise

    def __exit__(self, *_: object) -> None:
        # Do not send ClientDisconnecting: RPFM 5.0.5 exits before flushing that
        # response and waits up to five seconds on network telemetry.  Closing
        # the socket and terminating our owned child is deterministic.
        if self.socket is not None:
            try:
                self.socket.close()
            except Exception:
                pass
            self.socket = None
        if self.process is not None and self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
        if self._stderr_file is not None:
            self._stderr_file.close()
            self._stderr_file = None

    def _wait_for_own_endpoint(self) -> None:
        assert self.process is not None
        deadline = time.monotonic() + self.startup_timeout
        last_version: object = None
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                raise RpfmWsError(
                    "RPFM exited during startup: " + self.stderr_tail()
                )
            try:
                with urlopen("http://127.0.0.1:45127/version", timeout=0.5) as response:
                    last_version = json.loads(response.read().decode("utf-8"))
                pid = _find_pid(last_version)
                if pid is not None and pid != self.process.pid:
                    raise RpfmWsError(
                        f"RPFM endpoint belongs to PID {pid}, expected child PID "
                        f"{self.process.pid}"
                    )
                if pid == self.process.pid:
                    return
            except (OSError, ValueError, json.JSONDecodeError):
                time.sleep(0.1)
        raise RpfmWsError(
            f"RPFM did not expose its own endpoint within {self.startup_timeout:g}s; "
            f"last version response was {last_version!r}; stderr: {self.stderr_tail()}"
        )

    def _receive(self, *, timeout: float) -> dict[str, Any]:
        if self.socket is None:
            raise RpfmWsError("RPFM WebSocket is not connected")
        try:
            raw = self.socket.recv(timeout=timeout)
        except (ConnectionClosed, TimeoutError, OSError) as error:
            status = None if self.process is None else self.process.poll()
            raise RpfmWsError(
                f"RPFM connection failed (process status {status}): {self.stderr_tail()}"
            ) from error
        try:
            response = json.loads(raw)
        except (TypeError, json.JSONDecodeError) as error:
            raise RpfmWsError(f"RPFM returned invalid JSON: {raw!r}") from error
        if not isinstance(response, dict):
            raise RpfmWsError(f"RPFM returned a non-object response: {response!r}")
        return response

    def call(self, command: str | dict[str, Any]) -> Any:
        """Send one native RPFM ``Command`` and return its decoded ``Response``."""

        if self.socket is None:
            raise RpfmWsError("RPFM WebSocket is not connected")
        self.request_id += 1
        request_id = self.request_id
        request = {"id": request_id, "data": command}
        try:
            self.socket.send(json.dumps(request, separators=(",", ":")))
        except (ConnectionClosed, OSError) as error:
            raise RpfmWsError(
                f"failed to send RPFM command {command!r}: {self.stderr_tail()}"
            ) from error

        while True:
            response = self._receive(timeout=self.command_timeout)
            if response.get("id") != request_id:
                raise RpfmWsError(
                    f"RPFM response ID mismatch: expected {request_id}, got "
                    f"{response.get('id')!r}"
                )
            payload = response.get("data")
            if isinstance(payload, dict) and "Error" in payload:
                raise RpfmWsError(
                    f"RPFM rejected {command!r}: {payload['Error']}"
                )
            return payload

    def stderr_tail(self, limit: int = 4000) -> str:
        """Return recent RPFM stderr without risking a blocked pipe read."""

        if self._stderr_file is not None:
            self._stderr_file.flush()
        if self._stderr_path is None or not self._stderr_path.exists():
            return ""
        data = self._stderr_path.read_bytes()
        return data[-limit:].decode("utf-8", errors="replace")


def _find_pid(value: object) -> int | None:
    """Find the PID in RPFM's version payload without coupling to key casing."""

    if isinstance(value, dict):
        for key, item in value.items():
            if key.lower() == "pid" and isinstance(item, int):
                return item
            found = _find_pid(item)
            if found is not None:
                return found
    elif isinstance(value, list):
        for item in value:
            found = _find_pid(item)
            if found is not None:
                return found
    return None
