#!/usr/bin/env python3

# This script continues from 01_find_space_and_networks.py by reading the configured IPAM context JSON file.
# It shows the IPv4 blocks collected by step 01 and asks which parent block to use.
# It uses SOLIDserverRest.adv.Network to search the chosen block for a free IPv4 subnet.
# With --apply, it also creates the terminal subnet through the advanced object-oriented API.
# By default it runs in dry-run mode and writes the proposal to the configured subnet allocation JSON file.

from __future__ import annotations

import argparse
import ipaddress
import json
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from SOLIDserverRest import adv as sdsadv

from lib.config import add_common_args, ensure_output_dir, get_config
from lib.display import dry_run, kv, read_json, section, warning
from lib.sds_client import connect_client


def split_cidr(value: str) -> tuple[str, int]:
    network = ipaddress.ip_network(value, strict=False)
    return str(network.network_address), int(network.prefixlen)


def block_to_cidr(block: dict[str, Any]) -> str:
    address = block.get("start_hostaddr", "")
    prefix = block.get("subnet_prefix", "")

    if address and prefix:
        return f"{address}/{prefix}"

    name = block.get("subnet_name", "")
    for part in str(name).replace("(", " ").replace(")", " ").split():
        if "/" in part:
            try:
                return str(ipaddress.ip_network(part, strict=False))
            except ValueError:
                continue

    return ""


def block_label(index: int, block: dict[str, Any]) -> str:
    cidr = block_to_cidr(block) or "<unknown>"
    name = block.get("subnet_name", "")
    used = block.get("subnet_used_percent", block.get("subnet_ip_used_percent", ""))
    free = block.get("subnet_ip_free_size", "")

    details = []
    if name:
        details.append(str(name))
    if used != "":
        details.append(f"used={used}%")
    if free != "":
        details.append(f"free_ips={free}")

    suffix = f" ({', '.join(details)})" if details else ""
    return f"{index}. {cidr}{suffix}"


def choose_block(blocks: list[dict[str, Any]]) -> dict[str, Any]:
    section("Available IPv4 Blocks")

    for index, block in enumerate(blocks, start=1):
        print(block_label(index, block))

    while True:
        answer = input("\nChoose parent block [1]: ").strip() or "1"

        try:
            selected_index = int(answer)
        except ValueError:
            print("Please enter a number from the list.")
            continue

        if 1 <= selected_index <= len(blocks):
            return blocks[selected_index - 1]

        print(f"Please enter a number between 1 and {len(blocks)}.")


def find_free_ipv4_subnets(client, space, block_cidr: str, prefix: int, limit: int) -> list[str]:
    block_addr, block_prefix = split_cidr(block_cidr)

    # Advanced object model: bind a Network object to the selected space and parent CIDR.
    parent = sdsadv.Network(sds=client.sds, space=space)
    parent.set_address_prefix(block_addr, block_prefix)
    parent.refresh()

    # Advanced object model: ask SOLIDserver to calculate free child subnets.
    candidates = parent.find_free(prefix=prefix, max_find=limit) or []
    return [f"{candidate}/{prefix}" for candidate in candidates]


def write_output(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    section("Output")
    kv("path", path.parent)
    kv("file", path.name)


def main() -> int:
    parser = argparse.ArgumentParser(description="Find demo IPv4 capacity from a block selected in step 01.")
    add_common_args(parser)
    parser.add_argument("--prefix", type=int, help="free subnet prefix to request")
    parser.add_argument("--block", help="parent block CIDR; skips the interactive block picker")
    parser.add_argument("--subnet-name", help="name for a created demo subnet")
    args = parser.parse_args()

    config = get_config()
    output_dir = ensure_output_dir()
    context_path = output_dir / config.output_01_ipam_context

    section("Input")
    kv("context file", context_path)

    context = read_json(context_path, {})

    if not context:
        warning(f"{context_path} was not found or is empty. Run 01_find_space_and_networks.py first.")
        return 1

    space_info = context.get("space", {})
    space_name = space_info.get("name") or config.default_space
    prefix = args.prefix or config.demo_prefix
    subnet_name = args.subnet_name or config.demo_subnet_name

    client = connect_client(config)
    space = client.get_space(space_name)

    section("IPAM Context")
    kv("space", f"{space.name} ({space.myid})")
    kv("requested prefix", f"/{prefix}")

    if args.block:
        block_cidr = args.block
        selected_block = {"manual": True, "cidr": block_cidr}
    else:
        blocks = context.get("ipv4_blocks", [])

        if not blocks:
            warning(f"no IPv4 blocks were found in {context_path}")
            warning("run 01_find_space_and_networks.py again and make sure it lists IPv4 blocks")
            return 1

        selected_block = choose_block(blocks)
        block_cidr = block_to_cidr(selected_block)

    if not block_cidr:
        warning("could not determine CIDR for the selected block")
        return 1

    section("Free Subnet Search")
    kv("parent block", block_cidr)

    candidates = find_free_ipv4_subnets(client, space, block_cidr, prefix, args.limit)
    proposed_subnet = candidates[0] if candidates else None
    free_addresses: list[str] = []

    if proposed_subnet:
        kv("selected candidate", proposed_subnet)
    else:
        warning("no free subnet candidates returned")

    if args.apply and proposed_subnet:
        subnet_addr, subnet_prefix = split_cidr(proposed_subnet)
        parent_addr, parent_prefix = split_cidr(block_cidr)

        # Advanced object model: recreate the parent object so the new subnet can be attached to it.
        parent = sdsadv.Network(sds=client.sds, space=space)
        parent.set_address_prefix(parent_addr, parent_prefix)
        parent.refresh()

        # Advanced object model: create the demo subnet as a terminal network under the selected parent.
        demo_net = sdsadv.Network(sds=client.sds, space=space, name=subnet_name)
        demo_net.set_address_prefix(subnet_addr, subnet_prefix)
        demo_net.set_parent(parent)
        demo_net.set_is_terminal(True)
        demo_net.create()
        demo_net.refresh()

        # Advanced object model: find candidate host addresses inside the created subnet.
        free_addresses = demo_net.find_free_ip(max_find=args.limit) or []

        kv("created subnet id", demo_net.myid)
        kv("free addresses found", len(free_addresses))
    elif proposed_subnet:
        dry_run(f"would create terminal IPv4 subnet {subnet_name} at {proposed_subnet}")

    payload = {
        "space": {
            "name": space.name,
            "id": space.myid,
        },
        "address_family": "ipv4",
        "requested_prefix": prefix,
        "parent_block": block_cidr,
        "parent_block_source": selected_block,
        "proposed_subnet": proposed_subnet,
        "subnet_name": subnet_name,
        "free_addresses": free_addresses,
        "applied": args.apply,
    }

    write_output(output_dir / config.output_02_subnet_allocation, payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
