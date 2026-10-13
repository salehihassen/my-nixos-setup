#!/usr/bin/env python3
"""Connect co terminals to one persistent CLIProxyAPI app-server.

Uses the normal Codex home and loads cliproxy.config.toml into the server.
The CLI's automatic daemon selection cannot do this for named profiles.
"""

from __future__ import annotations

import datetime
import fcntl
import json
import os
from pathlib import Path
import signal
import socket
import stat
import subprocess
import sys
import time
import tomllib


def toml_value(value):
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, (datetime.date, datetime.time)):
        return value.isoformat()
    if isinstance(value, list):
        return "[" + ", ".join(map(toml_value, value)) + "]"
    if isinstance(value, dict):
        return "{" + ", ".join(
            f"{json.dumps(key)} = {toml_value(item)}"
            for key, item in value.items()
        ) + "}"
    raise ValueError(f"Unsupported TOML value type: {type(value).__name__}")


def socket_ready(path):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(0.2)
        try:
            connection.connect(str(path))
            return True
        except OSError:
            return False


def process_identity(pid):
    try:
        # Fields following the closing parenthesis begin with stat field 3.
        return Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[19]
    except (FileNotFoundError, ProcessLookupError):
        return None


def stop_server(state_dir, socket_path):
    pid_file = state_dir / "server.json"
    if pid_file.exists():
        record = json.loads(pid_file.read_text())
        pid = record["pid"]
        identity = process_identity(pid)
        if identity is not None and identity == record["start_ticks"]:
            os.killpg(pid, signal.SIGTERM)
            deadline = time.monotonic() + 5
            while socket_ready(socket_path) and time.monotonic() < deadline:
                time.sleep(0.1)
            if socket_ready(socket_path):
                raise RuntimeError("Proxy daemon did not stop; no replacement was started")
        pid_file.unlink()


def main():
    codex_home = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex")).resolve()
    args = sys.argv[1:]
    embedded = ["codex", "--dangerously-bypass-approvals-and-sandbox",
                "--no-daemon", "--profile", "cliproxy"]
    if "--no-daemon" in args:
        os.execvp("codex", embedded + [arg for arg in args if arg != "--no-daemon"])
    if args and args[0] in {"exec", "e", "review", "mcp", "sandbox", "debug"}:
        os.execvp("codex", embedded + args)

    state_dir = codex_home / "cliproxy-daemon"
    state_dir.mkdir(mode=0o700, exist_ok=True)
    socket_path = state_dir / "server.sock"
    endpoint = f"unix://{socket_path}"
    lock_fd = os.open(state_dir / "launcher.lock", os.O_CREAT | os.O_RDWR, 0o600)
    with os.fdopen(lock_fd, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if args == ["--daemon-status"]:
            print(f"Proxy daemon: {'running' if socket_ready(socket_path) else 'stopped'}")
            print(f"Socket: {socket_path}")
            return
        if args in (["--daemon-stop"], ["--daemon-restart"]):
            stop_server(state_dir, socket_path)
            if args == ["--daemon-stop"]:
                print("Proxy daemon stopped")
                return

        if not socket_ready(socket_path):
            profile = tomllib.loads((codex_home / "cliproxy.config.toml").read_text())
            overrides = []
            for key, value in profile.items():
                overrides += ["-c", f"{key}={toml_value(value)}"]
            if socket_path.exists():
                if not stat.S_ISSOCK(socket_path.stat().st_mode):
                    raise RuntimeError(f"Expected a socket at {socket_path}")
                socket_path.unlink()
            log_path = state_dir / "server.log"
            log_fd = os.open(log_path, os.O_CREAT | os.O_WRONLY | os.O_APPEND, 0o600)
            with os.fdopen(log_fd, "ab") as log:
                server = subprocess.Popen(
                    ["codex", *overrides, "app-server", "--listen", endpoint],
                    stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                    start_new_session=True,
                )
            record = {"pid": server.pid, "start_ticks": process_identity(server.pid)}
            pid_path = state_dir / "server.json"
            pid_fd = os.open(pid_path, os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o600)
            with os.fdopen(pid_fd, "w") as output:
                json.dump(record, output)
            deadline = time.monotonic() + 15
            while not socket_ready(socket_path):
                if server.poll() is not None or time.monotonic() >= deadline:
                    if server.poll() is None:
                        stop_server(state_dir, socket_path)
                    raise RuntimeError(f"Proxy daemon failed to start; see {log_path}")
                time.sleep(0.1)

    if args == ["--daemon-restart"]:
        print("Proxy daemon started with the current cliproxy profile")
        return
    if args and args[0] == "agents":
        # `agents` rejects --profile, so load its client defaults explicitly.
        profile = tomllib.loads((codex_home / "cliproxy.config.toml").read_text())
        client_overrides = []
        for key, value in profile.items():
            client_overrides += ["-c", f"{key}={toml_value(value)}"]
        os.execvp("codex", ["codex", *client_overrides, "--remote", endpoint, *args])
    os.execvp("codex", ["codex", "--dangerously-bypass-approvals-and-sandbox",
                       "--remote", endpoint, "--profile", "cliproxy", *args])


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError) as error:
        print(f"co: {error}", file=sys.stderr)
        sys.exit(1)
