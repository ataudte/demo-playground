#!/usr/bin/env python3

# Shared terminal output helper for the SOLIDserver advanced Python demo scripts.
# Keeps every example readable during video recording and blog screenshots.
# Provides simple section headers, compact key/value rows, table output, and JSON artifact helpers.

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


def section(title: str) -> None:
    print()
    print(title)
    print("=" * len(title))


def kv(label: str, value: Any) -> None:
    print(f"{label:<24} {value}")


def warning(message: str) -> None:
    print(f"WARNING: {message}")


def dry_run(message: str) -> None:
    print(f"DRY-RUN: {message}")


def success(message: str) -> None:
    print(f"OK: {message}")


def print_rows(rows: list[dict[str, Any]], fields: list[str], limit: int = 5) -> None:
    if not rows:
        print("No rows returned.")
        return

    for row in rows[:limit]:
        values = []
        for field in fields:
            values.append(f"{field}={row.get(field, '')}")
        print("  " + " | ".join(values))


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    success(f"wrote {path}")


def read_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8"))
