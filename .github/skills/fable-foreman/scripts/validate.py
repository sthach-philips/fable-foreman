#!/usr/bin/env python3
"""Validate a JSON document against a JSON Schema."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker


def load_json(path: Path) -> object:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"{path}: {error}") from error


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("schema", type=Path)
    parser.add_argument("payload", type=Path)
    args = parser.parse_args()

    try:
        schema = load_json(args.schema)
        payload = load_json(args.payload)
        validator = Draft202012Validator(schema, format_checker=FormatChecker())
        errors = sorted(validator.iter_errors(payload), key=lambda item: list(item.path))
    except (ValueError, TypeError) as error:
        print(error, file=sys.stderr)
        return 2

    if not errors:
        return 0

    for error in errors:
        location = ".".join(str(part) for part in error.absolute_path) or "<root>"
        print(f"{args.payload}:{location}: {error.message}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())