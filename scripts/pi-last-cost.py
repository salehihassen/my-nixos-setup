#!/usr/bin/env python3
"""Report token usage and recorded cost for the latest Pi agent turn."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import asdict, dataclass
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class Session:
    id: str
    cwd: str
    path: Path
    entries: list[dict[str, Any]]
    updated_at: str


@dataclass(frozen=True)
class Usage:
    input_tokens: int
    cached_input_tokens: int
    cache_write_input_tokens: int
    output_tokens: int
    reasoning_output_tokens: int
    total_tokens: int
    input_cost: Decimal
    cached_input_cost: Decimal
    cache_write_input_cost: Decimal
    output_cost: Decimal
    total_cost: Decimal

    @classmethod
    def zero(cls) -> Usage:
        return cls(0, 0, 0, 0, 0, 0, *(Decimal(0) for _ in range(5)))

    def __add__(self, other: Usage) -> Usage:
        values = (
            self.input_tokens + other.input_tokens,
            self.cached_input_tokens + other.cached_input_tokens,
            self.cache_write_input_tokens + other.cache_write_input_tokens,
            self.output_tokens + other.output_tokens,
            self.reasoning_output_tokens + other.reasoning_output_tokens,
            self.total_tokens + other.total_tokens,
            self.input_cost + other.input_cost,
            self.cached_input_cost + other.cached_input_cost,
            self.cache_write_input_cost + other.cache_write_input_cost,
            self.output_cost + other.output_cost,
            self.total_cost + other.total_cost,
        )
        return Usage(*values)


@dataclass(frozen=True)
class ModelCall:
    timestamp: str
    provider: str
    model: str
    stop_reason: str
    error: str | None
    usage: Usage


@dataclass(frozen=True)
class Turn:
    prompt: str
    state: str
    state_detail: str
    estimate_is_partial: bool
    calls: list[ModelCall]


def decimal(value: Any) -> Decimal:
    try:
        return Decimal(str(value or 0))
    except (InvalidOperation, ValueError) as error:
        raise RuntimeError(f"Invalid recorded cost value: {value!r}") from error


def pi_agent_dir() -> Path:
    configured = os.environ.get("PI_CODING_AGENT_DIR")
    return (
        Path(configured).expanduser() if configured else Path.home() / ".pi" / "agent"
    )


def sessions_dir() -> Path:
    configured = os.environ.get("PI_CODING_AGENT_SESSION_DIR")
    return Path(configured).expanduser() if configured else pi_agent_dir() / "sessions"


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    try:
        with path.open(encoding="utf-8") as stream:
            for line_number, line in enumerate(stream, start=1):
                if not line.strip():
                    continue
                try:
                    value = json.loads(line)
                except json.JSONDecodeError as error:
                    raise RuntimeError(
                        f"Invalid JSON in {path}:{line_number}: {error}"
                    ) from error
                if isinstance(value, dict):
                    entries.append(value)
    except OSError as error:
        raise RuntimeError(f"Unable to read Pi session {path}: {error}") from error
    return entries


def load_session(path: Path) -> Session:
    entries = read_jsonl(path)
    if not entries or entries[0].get("type") != "session":
        raise RuntimeError(f"Not a Pi session file: {path}")
    header = entries[0]
    timestamps = [
        str(entry["timestamp"]) for entry in entries if entry.get("timestamp")
    ]
    return Session(
        id=str(header.get("id") or path.stem),
        cwd=str(header.get("cwd") or "unknown"),
        path=path,
        entries=entries[1:],
        updated_at=max(timestamps, default=str(header.get("timestamp") or "")),
    )


def find_session(requested_id: str | None, requested_file: str | None) -> Session:
    if requested_file:
        return load_session(Path(requested_file).expanduser())

    root = sessions_dir()
    if not root.is_dir():
        raise RuntimeError(f"Pi session directory not found: {root}")

    paths = list(root.rglob("*.jsonl"))
    if requested_id:
        matches = [path for path in paths if requested_id in path.name]
        if not matches:
            raise RuntimeError(f"No Pi session found with ID {requested_id}")
        sessions = [load_session(path) for path in matches]
        exact = [session for session in sessions if session.id == requested_id]
        if len(exact) == 1:
            return exact[0]
        if len(sessions) != 1:
            raise RuntimeError(f"Pi session ID {requested_id!r} is ambiguous")
        return sessions[0]

    sessions: list[Session] = []
    for path in paths:
        try:
            sessions.append(load_session(path))
        except RuntimeError:
            continue
    if not sessions:
        raise RuntimeError(f"No readable Pi sessions found in {root}")
    return max(sessions, key=lambda session: (session.updated_at, session.id))


def active_branch(session: Session) -> list[dict[str, Any]]:
    """Follow parent IDs from the current leaf to exclude abandoned branches."""
    identified = [entry for entry in session.entries if entry.get("id")]
    if not identified:
        return session.entries
    by_id = {str(entry["id"]): entry for entry in identified}
    branch: list[dict[str, Any]] = []
    current: dict[str, Any] | None = identified[-1]
    seen: set[str] = set()
    while current is not None:
        entry_id = str(current["id"])
        if entry_id in seen:
            raise RuntimeError(f"Parent cycle found in Pi session {session.path}")
        seen.add(entry_id)
        branch.append(current)
        parent_id = current.get("parentId")
        current = by_id.get(str(parent_id)) if parent_id is not None else None
    branch.reverse()
    return branch


def text_content(message: dict[str, Any]) -> str:
    content = message.get("content", [])
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return ""
    return " ".join(
        str(item.get("text", ""))
        for item in content
        if isinstance(item, dict) and item.get("type") == "text"
    ).strip()


def usage_from_message(message: dict[str, Any]) -> Usage:
    usage = message.get("usage") or {}
    costs = usage.get("cost") or {}
    return Usage(
        input_tokens=int(usage.get("input", 0) or 0),
        cached_input_tokens=int(usage.get("cacheRead", 0) or 0),
        cache_write_input_tokens=int(usage.get("cacheWrite", 0) or 0),
        output_tokens=int(usage.get("output", 0) or 0),
        reasoning_output_tokens=int(usage.get("reasoning", 0) or 0),
        total_tokens=int(usage.get("totalTokens", 0) or 0),
        input_cost=decimal(costs.get("input")),
        cached_input_cost=decimal(costs.get("cacheRead")),
        cache_write_input_cost=decimal(costs.get("cacheWrite")),
        output_cost=decimal(costs.get("output")),
        total_cost=decimal(costs.get("total")),
    )


def latest_turn(session: Session) -> Turn:
    branch = active_branch(session)
    user_indexes = [
        index
        for index, entry in enumerate(branch)
        if entry.get("type") == "message"
        and (entry.get("message") or {}).get("role") == "user"
    ]
    if not user_indexes:
        raise RuntimeError(f"No user request found in Pi session {session.path}")

    start = user_indexes[-1]
    prompt = text_content(branch[start].get("message") or {}) or "(non-text request)"
    calls: list[ModelCall] = []
    for entry in branch[start + 1 :]:
        message = entry.get("message") or {}
        if entry.get("type") != "message" or message.get("role") != "assistant":
            continue
        calls.append(
            ModelCall(
                timestamp=str(entry.get("timestamp") or "unknown"),
                provider=str(message.get("provider") or "unknown"),
                model=str(message.get("model") or "unknown"),
                stop_reason=str(message.get("stopReason") or "unknown"),
                error=str(message["errorMessage"])
                if message.get("errorMessage")
                else None,
                usage=usage_from_message(message),
            )
        )

    if not calls:
        return Turn(
            prompt, "WORKING", "no model response has been recorded yet", True, []
        )

    last = calls[-1]
    states = {
        "stop": ("FINISHED", "latest turn completed", False),
        "length": ("FINISHED", "latest turn stopped at the model output limit", False),
        "error": ("FAILED", "latest model call ended with an error", False),
        "aborted": ("INTERRUPTED", "latest turn was aborted", False),
        "toolUse": (
            "INCOMPLETE",
            "latest model call requested tools but no later model response was recorded",
            True,
        ),
    }
    state, detail, partial = states.get(
        last.stop_reason,
        ("UNKNOWN", f"unrecognized Pi stop reason: {last.stop_reason}", False),
    )
    return Turn(prompt, state, detail, partial, calls)


def total_usage(turn: Turn) -> Usage:
    total = Usage.zero()
    for call in turn.calls:
        total += call.usage
    return total


def money(value: Decimal) -> str:
    return f"${value:.8f}"


def compact(text: str, width: int = 120) -> str:
    redacted = re.sub(
        r"(?i)(\b(?:[A-Z][A-Z0-9_]*_)?(?:KEY|TOKEN|SECRET|PASSWORD)\b\s*[:=]\s*)\S+",
        r"\1[REDACTED]",
        text,
    )
    redacted = re.sub(
        r"\b(?:sk|ghp|github_pat|xox[baprs]|AIza)[-_][A-Za-z0-9_-]{8,}",
        "[REDACTED]",
        redacted,
    )
    single_line = " ".join(redacted.split())
    return (
        single_line if len(single_line) <= width else f"{single_line[: width - 3]}..."
    )


def print_usage(label: str, usage: Usage) -> None:
    print(label)
    print(f"  Uncached input: {usage.input_tokens:>10,}  {money(usage.input_cost)}")
    print(
        f"  Cached input:   {usage.cached_input_tokens:>10,}  {money(usage.cached_input_cost)}"
    )
    print(
        f"  Cache write:    {usage.cache_write_input_tokens:>10,}  {money(usage.cache_write_input_cost)}"
    )
    print(f"  Output:         {usage.output_tokens:>10,}  {money(usage.output_cost)}")
    print(
        f"    Reasoning:    {usage.reasoning_output_tokens:>10,}  (included in output)"
    )
    print(f"  Tokens total:   {usage.total_tokens:>10,}")
    print(f"  Cost total:                 {money(usage.total_cost)}")


def print_report(session: Session, turn: Turn) -> None:
    total = total_usage(turn)
    print(f"Request: {compact(turn.prompt)}")
    print(f"Session ID: {session.id}")
    print(f"Working directory: {session.cwd}")
    print(f"Turn state: {turn.state} - {turn.state_detail}")
    print(f"Model calls in turn: {len(turn.calls)}")
    if turn.calls:
        last = turn.calls[-1]
        print(f"Last model request: {last.timestamp}")
        print(f"Provider/model: {last.provider}/{last.model}")
        print(f"Stop reason: {last.stop_reason}")
        if last.error:
            print(f"Error: {compact(last.error)}")
    print()
    print_usage("Latest user-turn usage and recorded cost", total)
    if len(turn.calls) > 1:
        print()
        print_usage("Final model-call usage and recorded cost", turn.calls[-1].usage)


def usage_json(usage: Usage) -> dict[str, Any]:
    result = asdict(usage)
    return {
        key: str(value) if isinstance(value, Decimal) else value
        for key, value in result.items()
    }


def print_json(session: Session, turn: Turn) -> None:
    print(
        json.dumps(
            {
                "session": {
                    "id": session.id,
                    "cwd": session.cwd,
                    "path": str(session.path),
                    "updated_at": session.updated_at,
                },
                "turn": {
                    "prompt": compact(turn.prompt, width=10_000),
                    "state": turn.state.lower(),
                    "state_detail": turn.state_detail,
                    "estimate_is_partial": turn.estimate_is_partial,
                    "model_call_count": len(turn.calls),
                    "usage": usage_json(total_usage(turn)),
                    "calls": [
                        {
                            **{
                                key: value
                                for key, value in asdict(call).items()
                                if key != "usage"
                            },
                            "usage": usage_json(call.usage),
                        }
                        for call in turn.calls
                    ],
                },
            },
            indent=2,
        )
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Report recorded token cost for the latest user turn in the most recently active Pi session."
    )
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument(
        "--session-id", help="inspect a specific Pi session ID or unique ID prefix"
    )
    selection.add_argument(
        "--session-file", help="inspect a specific Pi session JSONL file"
    )
    parser.add_argument(
        "--json", action="store_true", help="emit machine-readable JSON"
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        session = find_session(args.session_id, args.session_file)
        turn = latest_turn(session)
        if args.json:
            print_json(session, turn)
        else:
            print_report(session, turn)
        return 0
    except RuntimeError as error:
        print(f"last-cost-pi: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
