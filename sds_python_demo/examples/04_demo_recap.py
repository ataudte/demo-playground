#!/usr/bin/env python3

# This script recaps the demo by reading the JSON files created by steps 02 and 03.
# It deliberately uses generic client.query() calls through the shared adv-backed client wrapper as a fallback style.
# It focuses on the demo subnet, the demo IP address, and the DNS A record that points to that IP.
# It is read-only and safe to run because it only queries SOLIDserver and local demo output files.

from __future__ import annotations

import datetime
import argparse
import ipaddress
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from SOLIDserverRest.Exception import SDSEmptyError

from lib.config import add_common_args, ensure_output_dir, get_config
from lib.display import read_json, section, warning
from lib.sds_client import connect_client, normalize_rows


TRACE_FIELDS = [
    "trace_creation_date",
    "trace_last_update_date",
    "trace_creation_usr_login",
    "trace_creation_origin_usr_login",
    "trace_creation_origin",
    "trace_creation_exec_stack",
]

LABEL_WIDTH = 34

def format_timestamp(value: Any) -> Any:
    text = str(value).strip()

    if not text or not text.isdigit():
        return value

    try:
        return datetime.datetime.fromtimestamp(int(text)).strftime("%Y-%m-%d %H:%M:%S")
    except (OSError, OverflowError, ValueError):
        return value

def kv(label: str, value: Any) -> None:
    print(f"{label:<{LABEL_WIDTH}} {value}")


def query_rows(client, service: str, params: dict[str, Any]) -> list[dict[str, Any]]:
    try:
        # Generic query fallback: recap/reporting only needs direct service methods and normalized rows.
        return normalize_rows(client.query(service, params=params))
    except SDSEmptyError:
        return []


def first_row(rows: list[dict[str, Any]]) -> dict[str, Any]:
    return rows[0] if rows else {}


def split_cidr(value: str) -> tuple[str, int] | tuple[str, None]:
    if not value:
        return "", None

    network = ipaddress.ip_network(value, strict=False)
    return str(network.network_address), int(network.prefixlen)


def enrich_dns_record(client, row: dict[str, Any]) -> dict[str, Any]:
    rr_id = row.get("rr_id")

    if not rr_id:
        return row

    details = query_rows(
        client,
        "dns_rr_info",
        {
            "rr_id": rr_id,
            "SELECT": (
                "rr_id,rr_full_name,rr_type,value1,dnszone_name,dns_name,dnsview_name,"
                "rr_last_update_time,rr_last_update_days,delayed_create_time,delayed_delete_time"
            ),
        },
    )

    if not details:
        return row

    enriched = dict(row)
    enriched.update(details[0])
    return enriched


def print_object(title: str, row: dict[str, Any], fields: list[tuple[str, str]]) -> None:
    section(title)

    if not row:
        print("No object found.")
        return

    for label, field in fields:
        kv(label, row.get(field, ""))

def print_trace(row: dict[str, Any]) -> None:
    printed = False

    for field in TRACE_FIELDS:
        value = row.get(field, "")
        if value not in ("", None):
            kv(field, format_timestamp(value))
            printed = True

    if not printed:
        print("No trace fields returned for this object.")

def find_subnet(client, space_id: str, cidr: str, limit: int) -> dict[str, Any]:
    subnet_addr, subnet_prefix = split_cidr(cidr)

    if not subnet_addr or subnet_prefix is None:
        return {}

    rows = query_rows(
        client,
        "ip_subnet_list",
        {
            "WHERE": f"site_id='{space_id}' and start_hostaddr='{subnet_addr}' and subnet_prefix='{subnet_prefix}'",
            "limit": limit,
        },
    )

    return first_row(rows)


def find_ip_address(client, address: str, limit: int) -> dict[str, Any]:
    if not address:
        return {}

    try:
        hex_address = f"{int(ipaddress.IPv4Address(address)):08x}"
    except ipaddress.AddressValueError:
        hex_address = ""

    queries = [
        f"hostaddr='{address}'",
        f"ip_addr='{address}'",
    ]

    if hex_address:
        queries.append(f"ip_addr='{hex_address}'")

    for where in queries:
        rows = query_rows(
            client,
            "ip_address_list",
            {
                "WHERE": where,
                "limit": limit,
            },
        )

        if rows:
            return first_row(rows)

    return {}


def find_dns_records_for_ip(client, fqdn: str, address: str, limit: int) -> list[dict[str, Any]]:
    if fqdn and address:
        rows = query_rows(
            client,
            "dns_rr_list",
            {
                "WHERE": f"rr_full_name='{fqdn}' and rr_type='A' and value1='{address}'",
                "limit": limit,
            },
        )
        if rows:
            return rows

    if address:
        rows = query_rows(
            client,
            "dns_rr_list",
            {
                "WHERE": f"rr_type='A' and value1='{address}'",
                "limit": limit,
            },
        )
        if rows:
            return rows

    return []


def print_dns_records(records: list[dict[str, Any]]) -> None:
    section("DNS Records For Demo IP")

    if not records:
        print("No DNS A records found for this IP.")
        return

    for index, record in enumerate(records, start=1):
        print()
        print(f"Record {index}")
        print("-" * 8)
        kv("record id", record.get("rr_id", ""))
        kv("fqdn", record.get("rr_full_name", ""))
        kv("type", record.get("rr_type", ""))
        kv("value", record.get("value1", ""))
        kv("zone", record.get("dnszone_name", ""))
        kv("server", record.get("dns_name", ""))
        kv("view", record.get("dnsview_name", ""))


def main() -> int:
    parser = argparse.ArgumentParser(description="Recap demo subnet, IP address, and DNS record using generic SOLIDserver API queries.")
    add_common_args(parser)
    args = parser.parse_args()

    config = get_config()
    output_dir = ensure_output_dir()

    allocation_path = output_dir / config.output_02_subnet_allocation
    dns_record_path = output_dir / config.output_03_dns_record

    section("Input")
    kv("subnet allocation", allocation_path)
    kv("DNS record", dns_record_path)

    allocation = read_json(allocation_path, {})
    dns_record = read_json(dns_record_path, {})

    if not allocation:
        warning(f"{allocation_path} was not found or is empty")
    if not dns_record:
        warning(f"{dns_record_path} was not found or is empty")

    client = connect_client(config)

    section("Basic API Fallback")
    print("Using generic client.query(service, params) calls on the same advanced SOLIDserver session.")

    space = allocation.get("space", {})
    space_id = str(space.get("id", "")).strip()
    space_name = str(space.get("name", config.default_space)).strip()

    proposed_subnet = allocation.get("proposed_subnet", "")
    fqdn = dns_record.get("fqdn", "")
    address = (
        dns_record.get("address", "")
        or dns_record.get("record", {}).get("value1", "")
        or next(iter(allocation.get("free_addresses", [])), "")
    )

    subnet_row = find_subnet(client, space_id, proposed_subnet, args.limit)

    print_object(
        "Demo Subnet",
        subnet_row,
        [
            ("subnet id", "subnet_id"),
            ("subnet name", "subnet_name"),
            ("network address", "start_hostaddr"),
            ("prefix", "subnet_prefix"),
            ("terminal", "is_terminal"),
        ],
    )

    section("Demo Subnet Trace")
    if subnet_row:
        print_trace(subnet_row)
    else:
        print("Subnet was not found. If step 02 was run without --apply, this is expected.")

    ip_row = find_ip_address(client, address, args.limit)

    print_object(
        "Demo IP Address",
        ip_row,
        [
            ("ip id", "ip_id"),
            ("address", "hostaddr"),
            ("name", "name"),
            ("subnet", "subnet_name"),
            ("class", "ip_class_name"),
        ],
    )

    section("Demo IP Address Trace")
    if ip_row:
        print_trace(ip_row)
    else:
        print("IP address was not found. If the IP was only proposed and not reserved, this is expected.")

    dns_records = [enrich_dns_record(client, row) for row in find_dns_records_for_ip(client, fqdn, address, args.limit)]
    print_dns_records(dns_records)

    section("Demo Summary")
    kv("space", f"{space_name} ({space_id})")
    kv("subnet", proposed_subnet or "<missing>")
    kv("ip address", address or "<missing>")
    kv("dns record", fqdn or "<missing>")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
