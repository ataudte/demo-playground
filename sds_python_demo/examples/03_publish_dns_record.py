#!/usr/bin/env python3

# This script continues from 02_allocate_network_and_address.py by reading the configured subnet allocation JSON file.
# It lists forward DNS zones that belong to the selected SOLIDserver zone space and match the selected IPAM block domains.
# It uses --hostname or SDS_DEMO_HOSTNAME to build the DNS record name in the selected zone.
# It deliberately uses generic client.query() calls as a fallback for DNS list/info/create service methods.
# By default it runs in dry-run mode; with --apply it creates the DNS A record in SOLIDserver.

from __future__ import annotations

import argparse
import ipaddress
import json
import sys
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from SOLIDserverRest.Exception import SDSEmptyError

from lib.config import add_common_args, ensure_output_dir, get_config
from lib.display import dry_run, kv, read_json, section, warning
from lib.sds_client import connect_client, normalize_rows


def safe_list_rows(client, method: str, limit: int = 5, where: str = "") -> list[dict[str, Any]]:
    try:
        return client.list_rows(method, limit=limit, where=where)
    except SDSEmptyError:
        return []


def safe_query_rows(client, method: str, params: dict[str, Any]) -> list[dict[str, Any]]:
    try:
        # Generic query fallback: useful for direct DNS methods where no adv object is needed.
        return normalize_rows(client.query(method, params=params))
    except SDSEmptyError:
        return []


def write_output(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    section("Output")
    kv("path", path.parent)
    kv("file", path.name)


def zone_name(zone: dict[str, Any]) -> str:
    return str(zone.get("dnszone_name", "")).strip()


def server_name(zone: dict[str, Any]) -> str:
    return str(zone.get("dns_name", zone.get("dnsserver_name", ""))).strip()


def zone_space_name(zone: dict[str, Any]) -> str:
    for key in ("dnszone_site_name", "site_name", "zone_space_name", "dnszone_space_name"):
        value = str(zone.get(key, "")).strip()
        if value and value != "#":
            return value
    return ""


def zone_space_id(zone: dict[str, Any]) -> str:
    for key in ("dnszone_site_id", "site_id", "zone_space_id", "dnszone_space_id"):
        value = str(zone.get(key, "")).strip()
        if value and value != "0":
            return value
    return ""


def is_reverse_zone(zone: dict[str, Any]) -> bool:
    name = zone_name(zone).lower()
    zone_type = str(zone.get("dnszone_type", zone.get("zone_type", ""))).strip().lower()

    if not name:
        return True

    if name.endswith("in-addr.arpa") or name.endswith("ip6.arpa"):
        return True

    return "reverse" in zone_type


def domains_from_class_parameters(value: str) -> list[str]:
    if not value:
        return []

    parsed = parse_qs(value, keep_blank_values=True)
    domains = []

    for key in ("domain_list", "domain"):
        for raw_value in parsed.get(key, []):
            for domain in raw_value.split(";"):
                domain = domain.strip().strip(".")
                if domain and domain not in domains:
                    domains.append(domain)

    return domains


def domains_from_allocation(allocation: dict[str, Any]) -> list[str]:
    sources = [
        allocation.get("parent_block_source", {}),
        allocation.get("space", {}),
    ]

    domains = []

    for source in sources:
        for key in ("subnet_class_parameters", "site_class_parameters"):
            for domain in domains_from_class_parameters(str(source.get(key, ""))):
                if domain not in domains:
                    domains.append(domain)

    return domains


def zone_matches_domain(zone: dict[str, Any], allowed_domains: list[str]) -> bool:
    allowed = {domain.lower().strip(".") for domain in allowed_domains}
    return zone_name(zone).lower().strip(".") in allowed


def query_zones_for_space(client, space_name: str, space_id: str, limit: int) -> list[dict[str, Any]]:
    candidates: list[dict[str, Any]] = []

    # Generic query fallback: try common SOLIDserver DNS zone filters because returned field names can vary.
    where_clauses = [
        f"dnszone_site_id='{space_id}'",
        f"site_id='{space_id}'",
        f"dnszone_site_name='{space_name}'",
        f"site_name='{space_name}'",
    ]

    for where in where_clauses:
        rows = safe_list_rows(client, "dns_zone_list", limit=max(limit * 50, 250), where=where)
        for row in rows:
            if zone_name(row) and row not in candidates:
                candidates.append(row)

    return candidates


def list_forward_zones(client, space_name: str, space_id: str, allowed_domains: list[str], limit: int) -> list[dict[str, Any]]:
    space_zones = query_zones_for_space(client, space_name, space_id, limit)

    if not space_zones:
        rows = safe_list_rows(client, "dns_zone_list", limit=max(limit * 50, 250))
        space_zones = [
            row
            for row in rows
            if zone_name(row)
            and (
                zone_space_id(row) == space_id
                or zone_space_name(row) == space_name
                or str(row.get("tree_path", "")).startswith(f"{space_name}#")
            )
        ]

    return [
        zone
        for zone in space_zones
        if zone_name(zone)
        and not is_reverse_zone(zone)
        and zone_matches_domain(zone, allowed_domains)
    ]


def zone_label(index: int, zone: dict[str, Any]) -> str:
    name = zone_name(zone) or "<unknown>"
    view = zone.get("dnsview_name", "")
    server = server_name(zone)

    details = []
    if view:
        details.append(f"view={view}")
    if server:
        details.append(f"server={server}")

    suffix = f" ({', '.join(details)})" if details else ""
    return f"{index}. {name}{suffix}"


def choose_zone(zones: list[dict[str, Any]]) -> dict[str, Any]:
    section("Available DNS Zones")

    for index, zone in enumerate(zones, start=1):
        print(zone_label(index, zone))

    while True:
        answer = input("\nChoose DNS zone [1]: ").strip() or "1"

        try:
            selected_index = int(answer)
        except ValueError:
            print("Please enter a number from the list.")
            continue

        if 1 <= selected_index <= len(zones):
            return zones[selected_index - 1]

        print(f"Please enter a number between 1 and {len(zones)}.")


def enrich_zone(client, zone: dict[str, Any]) -> dict[str, Any]:
    zone_id = zone.get("dnszone_id")

    if not zone_id:
        return zone

    details = safe_query_rows(client, "dns_zone_info", {"dnszone_id": zone_id})

    if not details:
        return zone

    enriched = dict(zone)
    enriched.update(details[0])
    return enriched


def first_usable_address(cidr: str) -> str:
    if not cidr:
        return ""

    network = ipaddress.ip_network(cidr, strict=False)

    try:
        return str(next(network.hosts()))
    except StopIteration:
        return ""


def record_fqdn(hostname: str, selected_zone_name: str) -> str:
    hostname = hostname.strip().rstrip(".")
    selected_zone_name = selected_zone_name.strip().rstrip(".")

    if hostname.endswith(selected_zone_name):
        return hostname

    return f"{hostname}.{selected_zone_name}"


def dns_id_from_zone_or_server(client, zone: dict[str, Any]) -> str:
    for key in ("dns_id", "dnsserver_id"):
        value = str(zone.get(key, "")).strip()
        if value and value != "0":
            return value

    name = server_name(zone)
    if not name:
        return ""

    rows = safe_list_rows(client, "dns_server_list", limit=1, where=f"dns_name='{name}'")
    if rows:
        return str(rows[0].get("dns_id", rows[0].get("dnsserver_id", ""))).strip()

    return ""


def record_create_params(client, fqdn: str, address: str, zone: dict[str, Any]) -> dict[str, Any]:
    params = {
        "rr_name": fqdn.strip().rstrip("."),
        "rr_type": "A",
        "value1": address,
        "rr_ttl": "3600",
        "add_flag": "new_edit",
    }

    dns_id = dns_id_from_zone_or_server(client, zone)

    if dns_id:
        params["dns_id"] = dns_id
    else:
        dns_name = server_name(zone)
        if dns_name:
            params["dns_name"] = dns_name

    return params


def main() -> int:
    parser = argparse.ArgumentParser(description="Prepare or publish a DNS A record for the demo allocation.")
    add_common_args(parser)
    parser.add_argument("--hostname", help="hostname to create in the selected zone")
    parser.add_argument("--address", help="IPv4 address for the A record")
    args = parser.parse_args()

    config = get_config()
    output_dir = ensure_output_dir()
    allocation_path = output_dir / config.output_02_subnet_allocation

    section("Input")
    kv("context file", allocation_path)

    allocation = read_json(allocation_path, {})

    if not allocation:
        warning(f"{allocation_path} was not found or is empty. Run 02_allocate_network_and_address.py first.")
        return 1

    client = connect_client(config)

    space_info = allocation.get("space", {})
    space_name = space_info.get("name") or config.default_space
    space_id = str(space_info.get("id", ""))

    hostname = args.hostname or config.demo_hostname
    address = (
        args.address
        or next(iter(allocation.get("free_addresses", [])), "")
        or first_usable_address(allocation.get("proposed_subnet", ""))
    )

    section("DNS Context")
    kv("space", f"{space_name} ({space_id})")
    kv("hostname", hostname)
    kv("address", address or "<missing>")

    if not address:
        warning("no address is available; pass --address or rerun step 02 with a proposed subnet")
        return 1

    allowed_domains = domains_from_allocation(allocation)

    section("DNS Zone Filter")
    kv("zone space", space_name)
    kv("domains", ", ".join(allowed_domains) or "<none from selected block>")

    zones = list_forward_zones(client, space_name, space_id, allowed_domains, args.limit)

    if not zones:
        warning("no forward DNS zones matched the selected zone space and IPAM block domain list")
        return 1

    selected_zone = enrich_zone(client, choose_zone(zones))
    selected_zone_name = zone_name(selected_zone)
    view_name = selected_zone.get("dnsview_name", "")
    fqdn = record_fqdn(hostname, selected_zone_name)

    section("DNS Record")
    kv("zone", selected_zone_name)
    kv("server", server_name(selected_zone) or "<not specified>")
    kv("view", view_name or "<not specified>")
    kv("fqdn", fqdn)
    kv("address", address)

    params = record_create_params(client, fqdn, address, selected_zone)

    if args.apply:
        # Generic query fallback: create the DNS A record with the SOLIDserver DNS service method.
        result = client.query("dns_rr_create", params=params)
        kv("status", "record created or updated")
    else:
        dry_run("would create DNS A record")
        result = params

    payload = {
        "space": {
            "name": space_name,
            "id": space_id,
        },
        "zone": selected_zone,
        "hostname": hostname,
        "fqdn": fqdn,
        "address": address,
        "record": result,
        "applied": args.apply,
    }

    write_output(output_dir / config.output_03_dns_record, payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
