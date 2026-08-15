#!/usr/bin/env python3
"""Estimate API-equivalent cost for the latest Codex model request."""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
import sys
from dataclasses import asdict, dataclass
from decimal import Decimal
from pathlib import Path
from typing import Any


MILLION = Decimal(1_000_000)


@dataclass(frozen=True)
class ModelPricing:
    uncached_input: Decimal
    cached_input: Decimal
    output: Decimal
    cache_write_multiplier: Decimal = Decimal("1")
    long_context_threshold: int | None = None
    long_context_input_multiplier: Decimal = Decimal("1")
    long_context_output_multiplier: Decimal = Decimal("1")

    @property
    def cache_write(self) -> Decimal:
        return self.uncached_input * self.cache_write_multiplier


# USD per one million tokens. Keep aliases explicit so unsupported models fail
# visibly instead of silently receiving a potentially incorrect price.
GPT_5_6_SOL = ModelPricing(
    uncached_input=Decimal("5.00"),
    cached_input=Decimal("0.50"),
    output=Decimal("30.00"),
    cache_write_multiplier=Decimal("1.25"),
    long_context_threshold=272_000,
    long_context_input_multiplier=Decimal("2"),
    long_context_output_multiplier=Decimal("1.5"),
)
GPT_5_6_TERRA = ModelPricing(
    uncached_input=Decimal("2.50"),
    cached_input=Decimal("0.25"),
    output=Decimal("15.00"),
    cache_write_multiplier=Decimal("1.25"),
    long_context_threshold=272_000,
    long_context_input_multiplier=Decimal("2"),
    long_context_output_multiplier=Decimal("1.5"),
)
GPT_5_6_LUNA = ModelPricing(
    uncached_input=Decimal("1.00"),
    cached_input=Decimal("0.10"),
    output=Decimal("6.00"),
    cache_write_multiplier=Decimal("1.25"),
    long_context_threshold=272_000,
    long_context_input_multiplier=Decimal("2"),
    long_context_output_multiplier=Decimal("1.5"),
)

MODEL_PRICING: dict[str, ModelPricing] = {
    "gpt-5.6": GPT_5_6_SOL,
    "gpt-5.6-sol": GPT_5_6_SOL,
    "gpt-5.6-terra": GPT_5_6_TERRA,
    "gpt-5.6-luna": GPT_5_6_LUNA,
}


@dataclass(frozen=True)
class Thread:
    id: str
    title: str
    rollout_path: Path
    model: str | None


@dataclass(frozen=True)
class RequestUsage:
    timestamp: str
    model: str
    input_tokens: int
    cached_input_tokens: int
    cache_write_input_tokens: int
    uncached_input_tokens: int
    output_tokens: int
    reasoning_output_tokens: int


@dataclass(frozen=True)
class TurnState:
    raw_status: str
    label: str
    detail: str
    estimate_is_partial: bool


def codex_home() -> Path:
    configured = os.environ.get("CODEX_HOME")
    return Path(configured).expanduser() if configured else Path.home() / ".codex"


def latest_thread(database: Path, requested_id: str | None) -> Thread:
    if not database.is_file():
        raise RuntimeError(f"Codex thread database not found: {database}")

    connection = sqlite3.connect(f"file:{database}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    try:
        if requested_id:
            row = connection.execute(
                """
                SELECT id, COALESCE(NULLIF(name, ''), NULLIF(title, ''),
                                    '(untitled)') AS display_title,
                       rollout_path, model
                  FROM threads
                 WHERE id = ?
                """,
                (requested_id,),
            ).fetchone()
        else:
            row = connection.execute(
                """
                SELECT id, COALESCE(NULLIF(name, ''), NULLIF(title, ''),
                                    '(untitled)') AS display_title,
                       rollout_path, model
                 FROM threads
                 WHERE archived = 0
                   AND rollout_path <> ''
                   AND model IS NOT NULL
                   AND model <> ''
                 ORDER BY recency_at_ms DESC, updated_at_ms DESC, id DESC
                 LIMIT 1
                """
            ).fetchone()
    finally:
        connection.close()

    if row is None:
        qualifier = f" with ID {requested_id}" if requested_id else ""
        raise RuntimeError(f"No Codex thread found{qualifier}")

    return Thread(
        id=row["id"],
        title=row["display_title"],
        rollout_path=Path(row["rollout_path"]),
        model=row["model"],
    )


def last_request(thread: Thread) -> RequestUsage:
    if not thread.rollout_path.is_file():
        raise RuntimeError(f"Codex rollout not found: {thread.rollout_path}")

    active_model = thread.model
    latest: RequestUsage | None = None

    with thread.rollout_path.open(encoding="utf-8") as rollout:
        for line_number, line in enumerate(rollout, start=1):
            try:
                event = json.loads(line)
            except json.JSONDecodeError as error:
                raise RuntimeError(
                    f"Invalid JSON in {thread.rollout_path}:{line_number}: {error}"
                ) from error

            if event.get("type") == "turn_context":
                active_model = event.get("payload", {}).get("model") or active_model
                continue

            payload = event.get("payload", {})
            if event.get("type") != "event_msg" or payload.get("type") != "token_count":
                continue

            usage = payload.get("info", {}).get("last_token_usage")
            if not usage:
                continue
            if not active_model:
                raise RuntimeError("The last request does not identify its model")

            input_tokens = int(usage.get("input_tokens", 0))
            cached_tokens = int(usage.get("cached_input_tokens", 0))
            cache_write_tokens = int(usage.get("cache_write_input_tokens", 0))
            uncached_tokens = input_tokens - cached_tokens - cache_write_tokens
            if uncached_tokens < 0:
                raise RuntimeError(
                    "Token accounting is inconsistent: cached and cache-write input "
                    "exceed total input"
                )

            latest = RequestUsage(
                timestamp=event.get("timestamp", "unknown"),
                model=active_model,
                input_tokens=input_tokens,
                cached_input_tokens=cached_tokens,
                cache_write_input_tokens=cache_write_tokens,
                uncached_input_tokens=uncached_tokens,
                output_tokens=int(usage.get("output_tokens", 0)),
                reasoning_output_tokens=int(usage.get("reasoning_output_tokens", 0)),
            )

    if latest is None:
        raise RuntimeError(f"No completed token-count event found in {thread.rollout_path}")
    return latest


def latest_turn_state(database: Path, thread_id: str) -> TurnState:
    if not database.is_file():
        return TurnState(
            raw_status="unknown",
            label="UNKNOWN",
            detail="Codex turn history is unavailable",
            estimate_is_partial=False,
        )

    connection = sqlite3.connect(f"file:{database}?mode=ro", uri=True)
    try:
        row = connection.execute(
            """
            SELECT status
              FROM thread_turns
             WHERE thread_id = ?
             ORDER BY rollout_ordinal DESC
             LIMIT 1
            """,
            (thread_id,),
        ).fetchone()
    finally:
        connection.close()

    raw_status = str(row[0]) if row else "unknown"
    states = {
        "inProgress": TurnState(
            raw_status=raw_status,
            label="WORKING",
            detail="latest turn is still running; this estimate may increase",
            estimate_is_partial=True,
        ),
        "completed": TurnState(
            raw_status=raw_status,
            label="FINISHED",
            detail="latest turn completed",
            estimate_is_partial=False,
        ),
        "interrupted": TurnState(
            raw_status=raw_status,
            label="INTERRUPTED",
            detail="latest turn stopped before normal completion",
            estimate_is_partial=False,
        ),
        "failed": TurnState(
            raw_status=raw_status,
            label="FAILED",
            detail="latest turn ended with an error",
            estimate_is_partial=False,
        ),
    }
    return states.get(
        raw_status,
        TurnState(
            raw_status=raw_status,
            label="UNKNOWN",
            detail=f"unrecognized Codex turn status: {raw_status}",
            estimate_is_partial=False,
        ),
    )


def token_cost(tokens: int, rate: Decimal, multiplier: Decimal) -> Decimal:
    return Decimal(tokens) * rate * multiplier / MILLION


def calculate_costs(usage: RequestUsage, pricing: ModelPricing) -> dict[str, Any]:
    is_long_context = (
        pricing.long_context_threshold is not None
        and usage.input_tokens > pricing.long_context_threshold
    )
    input_multiplier = (
        pricing.long_context_input_multiplier if is_long_context else Decimal("1")
    )
    output_multiplier = (
        pricing.long_context_output_multiplier if is_long_context else Decimal("1")
    )

    cached_cost = token_cost(
        usage.cached_input_tokens, pricing.cached_input, input_multiplier
    )
    uncached_cost = token_cost(
        usage.uncached_input_tokens, pricing.uncached_input, input_multiplier
    )
    cache_write_cost = token_cost(
        usage.cache_write_input_tokens, pricing.cache_write, input_multiplier
    )
    output_cost = token_cost(usage.output_tokens, pricing.output, output_multiplier)
    input_cost = cached_cost + uncached_cost + cache_write_cost

    return {
        "long_context_pricing": is_long_context,
        "input_multiplier": input_multiplier,
        "output_multiplier": output_multiplier,
        "cached_input": cached_cost,
        "uncached_input": uncached_cost,
        "cache_write_input": cache_write_cost,
        "input_total": input_cost,
        "output": output_cost,
        "request_total": input_cost + output_cost,
    }


def money(value: Decimal) -> str:
    return f"${value:.8f}"


def compact_title(title: str, width: int = 120) -> str:
    single_line = " ".join(title.split())
    if len(single_line) <= width:
        return single_line
    return f"{single_line[: width - 3]}..."


def pricing_as_json(pricing: ModelPricing) -> dict[str, Any]:
    result = asdict(pricing)
    result["cache_write"] = pricing.cache_write
    return {key: str(value) if isinstance(value, Decimal) else value for key, value in result.items()}


def print_report(
    thread: Thread,
    turn_state: TurnState,
    usage: RequestUsage,
    pricing: ModelPricing,
) -> None:
    costs = calculate_costs(usage, pricing)
    print(f"Thread: {compact_title(thread.title)}")
    print(f"Thread ID: {thread.id}")
    print(f"Thread state: {turn_state.label} - {turn_state.detail}")
    print(f"Last model request: {usage.timestamp}")
    print(f"Model: {usage.model}")
    print()
    print("Rates (USD per 1M tokens)")
    print(f"  Cached input:   ${pricing.cached_input}")
    print(f"  Uncached input: ${pricing.uncached_input}")
    print(f"  Cache write:    ${pricing.cache_write}")
    print(f"  Output:         ${pricing.output}")
    if costs["long_context_pricing"]:
        print(
            "  Long context:   "
            f"{costs['input_multiplier']}x input, "
            f"{costs['output_multiplier']}x output"
        )
    print()
    print("Last-request usage and API-equivalent cost")
    print(
        f"  Cached input:   {usage.cached_input_tokens:>10,}  "
        f"{money(costs['cached_input'])}"
    )
    print(
        f"  Uncached input: {usage.uncached_input_tokens:>10,}  "
        f"{money(costs['uncached_input'])}"
    )
    print(
        f"  Cache write:    {usage.cache_write_input_tokens:>10,}  "
        f"{money(costs['cache_write_input'])}"
    )
    print(
        f"  Input total:    {usage.input_tokens:>10,}  "
        f"{money(costs['input_total'])}"
    )
    print(
        f"  Output:         {usage.output_tokens:>10,}  "
        f"{money(costs['output'])}"
    )
    print(
        f"    Reasoning:    {usage.reasoning_output_tokens:>10,}  "
        "(included in output)"
    )
    print(f"  Request total:              {money(costs['request_total'])}")


def print_json(
    thread: Thread,
    turn_state: TurnState,
    usage: RequestUsage,
    pricing: ModelPricing,
) -> None:
    costs = calculate_costs(usage, pricing)
    document = {
        "thread": {
            "id": thread.id,
            "title": thread.title,
            "rollout_path": str(thread.rollout_path),
            "turn_status": turn_state.raw_status,
            "state": turn_state.label.lower(),
            "state_detail": turn_state.detail,
            "estimate_is_partial": turn_state.estimate_is_partial,
        },
        "request": asdict(usage),
        "rates_usd_per_million_tokens": pricing_as_json(pricing),
        "costs_usd": {
            key: str(value) if isinstance(value, Decimal) else value
            for key, value in costs.items()
        },
    }
    print(json.dumps(document, indent=2))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Estimate API-equivalent token cost for the final model request in "
            "the most recently active Codex thread."
        )
    )
    parser.add_argument("--thread-id", help="inspect a specific Codex thread")
    parser.add_argument("--json", action="store_true", help="emit machine-readable JSON")
    parser.add_argument(
        "--list-models", action="store_true", help="list models in the pricing map"
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if args.list_models:
        for model, pricing in MODEL_PRICING.items():
            print(
                f"{model}: uncached=${pricing.uncached_input}, "
                f"cached=${pricing.cached_input}, output=${pricing.output}, "
                f"cache-write=${pricing.cache_write} per 1M tokens"
            )
        return 0

    try:
        home = codex_home()
        thread = latest_thread(home / "state_5.sqlite", args.thread_id)
        turn_state = latest_turn_state(home / "thread_history_1.sqlite", thread.id)
        usage = last_request(thread)
        pricing = MODEL_PRICING.get(usage.model)
        if pricing is None:
            supported = ", ".join(sorted(MODEL_PRICING))
            raise RuntimeError(
                f"No pricing configured for model {usage.model!r}. "
                f"Supported models: {supported}"
            )

        if args.json:
            print_json(thread, turn_state, usage, pricing)
        else:
            print_report(thread, turn_state, usage, pricing)
        return 0
    except (OSError, RuntimeError, sqlite3.Error) as error:
        print(f"last-cost-co: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
