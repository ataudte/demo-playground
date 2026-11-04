#!/usr/bin/env python3

# This script connects to SOLIDserver with the advanced SOLIDserverRest client and prints a compact inventory.
# It validates authentication, TLS behavior, API reachability, and the SOLIDserver version.
# It prints grouped object counts across core SOLIDserver services.
# It is the first demo step and is safe to run because it only reads from SOLIDserver.

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lib.config import add_common_args, get_config
from lib.display import kv, section
from lib.sds_client import COUNT_METHODS, connect_client


def main() -> int:
    parser = argparse.ArgumentParser(description="Connect to SOLIDserver and print object counts.")
    add_common_args(parser)
    args = parser.parse_args()

    config = get_config()

    section("Connection")
    kv("SDS Host", config.host)
    kv("SDS User", config.user)
    kv("SDS Space", config.default_space)
    client = connect_client(config)
    kv("SDS Version", client.version)
    kv("Auth Method", config.auth_method)
    kv("TLS verified", config.verify_tls)

    section("Object Counts")
    current_group = ""

    for group, label, method in COUNT_METHODS:
        if group != current_group:
            current_group = group
            print()
            print(f"{group}:")

        try:
            print(f"  {label:<24} {client.count(method)}")
        except Exception as exc:
            print(f"  {label:<24} ERROR: {exc}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())