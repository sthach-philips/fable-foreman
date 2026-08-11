#!/usr/bin/env python3
"""Append validated Foreman events and render ledger projections."""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import socket
import sys
import time
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterator

from jsonschema import Draft202012Validator, FormatChecker

SCHEMA = Path(__file__).resolve().parent.parent / "assets/schemas/ledger-line.schema.json"


def fail(message: str) -> "NoReturn":
    raise RuntimeError(message)


def read_json(path: Path) -> dict[str, object]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"{path}: {error}")
    if not isinstance(value, dict):
        fail(f"{path}: expected a JSON object")
    return value


def validator() -> Draft202012Validator:
    return Draft202012Validator(read_json(SCHEMA), format_checker=FormatChecker())


def validate_record(record: dict[str, object], source: str) -> None:
    errors = sorted(validator().iter_errors(record), key=lambda item: list(item.path))
    if errors:
        details = "; ".join(
            f"{'.'.join(str(part) for part in error.absolute_path) or '<root>'}: {error.message}"
            for error in errors
        )
        fail(f"{source}: {details}")


def load_records(path: Path) -> list[dict[str, object]]:
    if not path.exists():
        return []
    records: list[dict[str, object]] = []
    event_ids: dict[str, str] = {}
    with path.open(encoding="utf-8") as ledger:
        for line_number, raw_line in enumerate(ledger, 1):
            if not raw_line.endswith("\n"):
                fail(f"{path}:{line_number}: truncated JSONL line")
            if not raw_line.strip():
                continue
            try:
                record = json.loads(raw_line)
            except json.JSONDecodeError as error:
                fail(f"{path}:{line_number}: {error}")
            if not isinstance(record, dict):
                fail(f"{path}:{line_number}: expected a JSON object")
            validate_record(record, f"{path}:{line_number}")
            event_id = str(record["event_id"])
            canonical = json.dumps(record, sort_keys=True, separators=(",", ":"))
            if event_id in event_ids and event_ids[event_id] != canonical:
                fail(f"{path}:{line_number}: conflicting duplicate event_id {event_id}")
            if event_id in event_ids:
                continue
            event_ids[event_id] = canonical
            records.append(record)
    return records


@contextmanager
def exclusive_lock(path: Path) -> Iterator[None]:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a+", encoding="utf-8") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(lock.fileno(), fcntl.LOCK_UN)


def lease_path(ledger: Path) -> Path:
    return ledger.parent / ".coordinator.lock"


def assert_lease(ledger: Path, owner: str) -> None:
    lease = read_json(lease_path(ledger))
    if lease.get("owner") != owner:
        fail(f"coordinator lease belongs to {lease.get('owner')!r}, not {owner!r}")


def acquire(ledger: Path, owner: str, stale_after: int, force_stale: bool) -> None:
    target = lease_path(ledger)
    target.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "owner": owner,
        "pid": os.getpid(),
        "host": socket.gethostname(),
        "acquired_at": datetime.now(timezone.utc).isoformat(),
    }
    encoded = json.dumps(payload, sort_keys=True) + "\n"
    try:
        descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        current = read_json(target)
        if current.get("owner") == owner:
            target.touch()
            return
        age = time.time() - target.stat().st_mtime
        if age <= stale_after:
            fail(f"active coordinator lease held by {current.get('owner')!r}")
        if not force_stale:
            fail("stale coordinator lease; inspect it, then retry with --force-stale")
        target.unlink()
        return acquire(ledger, owner, stale_after, False)
    with os.fdopen(descriptor, "w", encoding="utf-8") as lease:
        lease.write(encoded)
        lease.flush()
        os.fsync(lease.fileno())


def release(ledger: Path, owner: str) -> None:
    target = lease_path(ledger)
    assert_lease(ledger, owner)
    target.unlink()


def append(ledger: Path, record_path: Path, owner: str) -> None:
    record = read_json(record_path)
    validate_record(record, str(record_path))
    assert_lease(ledger, owner)
    with exclusive_lock(ledger.parent / ".append.lock"):
        records = load_records(ledger)
        canonical = json.dumps(record, sort_keys=True, separators=(",", ":"))
        for existing in records:
            if existing["event_id"] != record["event_id"]:
                continue
            if json.dumps(existing, sort_keys=True, separators=(",", ":")) == canonical:
                return
            fail(f"conflicting duplicate event_id {record['event_id']}")
        if record["type"] == "attempt":
            attempts = [
                item
                for item in records
                if item["type"] == "attempt" and item["task_id"] == record["task_id"]
            ]
            max_generation = max((int(item["generation"]) for item in attempts), default=1)
            generation = int(record["generation"])
            if generation not in {max_generation, max_generation + 1}:
                fail(f"attempt generation must be {max_generation} or {max_generation + 1}")
            generation_attempts = [item for item in attempts if int(item["generation"]) == generation]
            expected_attempt = len(generation_attempts) + 1
            if generation > max_generation:
                expected_attempt = 1
            if int(record["attempt"]) != expected_attempt:
                fail(f"attempt must be {expected_attempt} in generation {generation}")
        ledger.parent.mkdir(parents=True, exist_ok=True)
        line = (json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n").encode()
        descriptor = os.open(ledger, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        try:
            os.write(descriptor, line)
            os.fsync(descriptor)
        finally:
            os.close(descriptor)


def apply_attempt(task: dict[str, object], record: dict[str, object]) -> None:
    generation = int(record["generation"])
    if generation > int(task["generation"]):
        task["generation"] = generation
        task["attempts"] = 0
    if generation == task["generation"]:
        task["attempts"] = int(task["attempts"]) + 1
    disposition = str(record["disposition"])
    task["state"] = {
        "complete": "VERIFIED" if record.get("status_or_verdict") == "PASS" else "REPORTED",
        "complete_with_concerns": "REPORTED",
        "needs_context": "PENDING",
        "needs_redispatch": "PENDING",
        "blocked": "FAILED",
        "failed": "FAILED",
    }[disposition]


def task_projection(records: list[dict[str, object]]) -> list[dict[str, object]]:
    tasks: dict[str, dict[str, object]] = {}
    for record in records:
        task_id = record.get("task_id")
        if not isinstance(task_id, str):
            continue
        if record["type"] == "task":
            tasks[task_id] = {
                "task_id": task_id,
                "title": record["title"],
                "task_class": record["task_class"],
                "state": record["state"],
                "generation": 0,
                "attempts": 0,
            }
            continue
        if task_id not in tasks:
            continue
        if record["type"] == "attempt":
            apply_attempt(tasks[task_id], record)
        elif record["type"] == "escalation":
            tasks[task_id]["state"] = "ESCALATED"
    return list(tasks.values())


def project(records: list[dict[str, object]], view: str) -> list[dict[str, object]]:
    if view == "tasks":
        return task_projection(records)
    if view == "attempts":
        return [record for record in records if record["type"] == "attempt"]
    if view == "failures":
        return [
            record
            for record in records
            if record["type"] == "attempt" and record["disposition"] in {"blocked", "failed"}
        ]
    if view == "escalations":
        return [record for record in records if record["type"] == "escalation"]
    fail(f"unknown view {view}")


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    acquire_parser = subparsers.add_parser("acquire")
    acquire_parser.add_argument("--ledger", type=Path, required=True)
    acquire_parser.add_argument("--owner", required=True)
    acquire_parser.add_argument("--stale-after", type=int, default=86400)
    acquire_parser.add_argument("--force-stale", action="store_true")

    release_parser = subparsers.add_parser("release")
    release_parser.add_argument("--ledger", type=Path, required=True)
    release_parser.add_argument("--owner", required=True)

    append_parser = subparsers.add_parser("append")
    append_parser.add_argument("--ledger", type=Path, required=True)
    append_parser.add_argument("--owner", required=True)
    append_parser.add_argument("record", type=Path)

    validate_parser = subparsers.add_parser("validate")
    validate_parser.add_argument("--ledger", type=Path, required=True)

    view_parser = subparsers.add_parser("view")
    view_parser.add_argument("--ledger", type=Path, required=True)
    view_parser.add_argument("--view", choices=("tasks", "attempts", "failures", "escalations"), required=True)
    view_parser.add_argument("--status")

    args = parser.parse_args()
    try:
        if args.command == "acquire":
            acquire(args.ledger, args.owner, args.stale_after, args.force_stale)
        elif args.command == "release":
            release(args.ledger, args.owner)
        elif args.command == "append":
            append(args.ledger, args.record, args.owner)
        elif args.command == "validate":
            load_records(args.ledger)
        elif args.command == "view":
            output = project(load_records(args.ledger), args.view)
            if args.status:
                output = [
                    item
                    for item in output
                    if args.status in {item.get("state"), item.get("disposition"), item.get("status_or_verdict")}
                ]
            print(json.dumps(output, indent=2, sort_keys=True))
    except RuntimeError as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())