# sds_python_demo

## Description
Demo repository for the advanced `SOLIDserverRest` Python library, especially the object-oriented [`SOLIDserverRest.adv` API](https://gitlab.com/efficientip/solidserverrest/-/tree/master/SOLIDserverRest/adv).

The flow shows how SOLIDserver can act as the DDI source of truth for a small ecosystem integration: connect to SOLIDserver, select IPAM context, find IPv4 capacity, prepare or create a DNS A record, and recap the created objects.

The examples intentionally separate SOLIDserver-specific calls from general demo plumbing. Configuration loading, JSON artifacts, terminal display, CIDR parsing, and interactive selection are ordinary Python helper code. The SOLIDserver-specific parts are concentrated in the shared client wrapper and the places where the scripts use the advanced object model or the generic API-query fallback.

---

## Usage
Create a Python virtual environment and install the requirements:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Create local configuration:

```bash
cp .env.example .env
```

Fill in `.env`, then run the demo flow:

```bash
python examples/00_connect_and_inventory.py
python examples/01_find_space_and_networks.py
python examples/02_allocate_network_and_address.py
python examples/03_publish_dns_record.py
python examples/04_demo_recap.py
```

Steps `02` and `03` are dry-run by default. Add `--apply` only in a safe demo environment:

```bash
python examples/02_allocate_network_and_address.py --apply
python examples/03_publish_dns_record.py --apply
```

---

## Requirements
- Python 3.9+
- External modules:
  - `SOLIDserverRest`, including the advanced object-oriented library under `SOLIDserverRest.adv`
- SOLIDserver access:
  - reachable SOLIDserver management endpoint
  - API user with rights to list IPAM/DNS objects
  - additional rights to create subnets or DNS records when using `--apply`

---

## Input / Output
- **Input:** SOLIDserver connection and demo settings from `.env`, exported environment variables, or command-line arguments.
- **Output:** JSON artifacts in `output/`, with filenames configured in `.env`:
  - `SDS_OUTPUT_01_IPAM_CONTEXT`
  - `SDS_OUTPUT_02_SUBNET_ALLOCATION`
  - `SDS_OUTPUT_03_DNS_RECORD`

---

## Example Flow
1. `00_connect_and_inventory.py` verifies SOLIDserver API access and prints grouped object counts.
2. `01_find_space_and_networks.py` selects the configured IPAM space and writes candidate IPv4 blocks.
3. `02_allocate_network_and_address.py` reads the IPAM context JSON, prompts for a parent block, and uses `SOLIDserverRest.adv.Network` to find a free IPv4 subnet. With `--apply`, it creates a terminal subnet and finds available host addresses through the advanced object model.
4. `03_publish_dns_record.py` reads the subnet allocation JSON, filters DNS zones using the selected block metadata, and prepares or creates an A record. DNS zone lookup and record creation use the generic `client.query(...)` fallback because those calls are simple service-method operations.
5. `04_demo_recap.py` reads the generated JSON files and uses generic `client.query(...)` calls as a fallback-style review of the demo subnet, IP address, and DNS record.

---

## Library Usage Notes
- Advanced object-oriented library: the demo uses `SOLIDserverRest.adv.SDS` for the session, `SOLIDserverRest.adv.Space` to select the IPAM space, and `SOLIDserverRest.adv.Network` for subnet discovery and subnet creation.
- Generic query fallback: when a workflow only needs a direct SOLIDserver service method, the shared wrapper exposes `client.query(method, params)` and `client.list_rows(...)`. This keeps DNS and recap examples concise while still using the same authenticated advanced client session.
- Non-SOLIDserver code: helpers such as `.env` parsing, output formatting, JSON reads/writes, CIDR conversion, and menu prompts are included only to make the demo repeatable and readable.

---

## Notes
- Keep `.env` private. It is ignored by Git.
- Generated JSON files in `output/` are ignored by Git.
- IPv6, DHCP, Network Object Manager, and final integration payload examples are intentionally left for future demos.
- The examples are designed for video recording and blog posts, so terminal output is compact and predictable.

---

## License
This demo repository is covered under the [MIT License](LICENSE).
