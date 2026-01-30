# dns_straying.sh

## Description
Interactive demo script that simulates **DNS straying queries** by sending random, non-existent hostnames for a given zone to its authoritative name servers.

The script:
- discovers the zone’s NS records
- resolves those name servers to A and AAAA addresses
- generates random hostnames under the zone
- sends queries with randomized timing to randomly selected authoritative servers

This is intended for **education, testing, and demonstrations** of stray DNS traffic, logging, and server-side visibility — not for load testing or abuse.

---

## Usage
```bash
chmod +x dns_straying.sh
./dns_straying.sh <zone>
```

Example:
```bash
./dns_straying.sh example.com
```

The script will display the discovered name servers, generated FQDNs, and ask for confirmation before sending any queries.

---

## Requirements
- Bash
- DNS utilities:
  - `dig`
- Standard Unix tools:
  - `tr`, `head`, `sort`, `sleep`
  - `/dev/urandom`

No external libraries required.

---

## Input / Output
- **Input:**  
  - One DNS zone name passed as `$1` (with or without trailing dot)

- **Output:**  
  - Informational output to STDOUT:
    - NS names and IP addresses
    - Generated random FQDNs
    - Per-query destination and delay
  - DNS queries are sent directly to the authoritative servers of the zone

No files are written.

---

## Notes
- Trailing dots in zone names are stripped automatically.
- The number of generated FQDNs defaults to `16` and can be overridden:
  ```bash
  MAX_FQDNS=32 ./dns_straying.sh example.com
  ```
- Queries are spread across all discovered NS IPs (IPv4 and IPv6).
- Random inter-query delays (0.5s–2.0s) are used to avoid burst traffic.
- All queries are expected to result in **NXDOMAIN**.
- Always run this only for zones you control or have permission to test.

---

## License
This script is covered under the repository’s main [MIT License](../LICENSE).
