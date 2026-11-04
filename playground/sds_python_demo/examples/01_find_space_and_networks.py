#!/usr/bin/env python3

# This script selects the SOLIDserver IPAM space used by the demo workflow.
# It uses --space when provided, otherwise it uses SDS_DEFAULT_SPACE from the environment.
# It resolves the space through the advanced SOLIDserverRest object model, then lists blocks with the query fallback.
# It lists non-terminal IPv4 network blocks in that selected space and writes them to the configured JSON output file.
# IPv6 is intentionally left for a future demo so this walkthrough can stay focused on the advanced IPv4 workflow.

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lib.config import add_common_args, ensure_output_dir, get_config
from lib.display import kv, print_rows, section, warning
from lib.sds_client import connect_client


def is_block(row: dict[str, Any]) -> bool:
    terminal_value = row.get("is_terminal", row.get("subnet_is_terminal", ""))
    return str(terminal_value).strip().lower() in {"0", "false", "no", ""}


def list_ipv4_blocks(client, space_id: str, fetch_limit: int) -> list[dict[str, Any]]:
    rows = client.list_rows("ip_subnet_list", limit=fetch_limit, where=f"site_id='{space_id}'")
    return [row for row in rows if is_block(row)]


def write_output(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    section("Output")
    kv("path", path.parent)
    kv("file", path.name)


def main() -> int:
    parser = argparse.ArgumentParser(description="Find the SOLIDserver IPAM space and candidate IPv4 network blocks.")
    add_common_args(parser)
    parser.add_argument("--space", help="space name to inspect")
    args = parser.parse_args()

    config = get_config()
    space_name = args.space or config.default_space
    client = connect_client(config)

    section("Selected Space")
    space = client.get_space(space_name)
    kv("space", f"{space.name} ({space.myid})")

    fetch_limit = max(args.limit * 5, 50)

    section("Candidate IPv4 Blocks")
    try:
        ipv4_blocks = list_ipv4_blocks(client, str(space.myid), fetch_limit)
        print_rows(
            ipv4_blocks,
            [
                "subnet_id",
                "subnet_name",
                "start_hostaddr",
                "subnet_prefix",
                "subnet_size",
                "is_terminal",
                "subnet_ip_used_percent",
            ],
            limit=args.limit,
        )
    except Exception as exc:
        ipv4_blocks = []
        warning(f"could not list IPv4 blocks: {exc}")

    payload = {
        "space": {
            "name": space.name,
            "id": space.myid,
        },
        "ipv4_blocks": ipv4_blocks,
    }

    write_output(ensure_output_dir() / config.output_01_ipam_context, payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
