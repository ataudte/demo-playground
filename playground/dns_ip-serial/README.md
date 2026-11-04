# dns_ip-serial.sh

## Description
Small utility script to convert between an IPv4 address in dotted-quad notation (e.g. `192.168.1.1`) and its **32-bit integer representation** (often called “serial”, “decimal IP”, or “IPv4 as integer”)

This is useful for quick sanity checks in DNS/IPAM workflows, log analysis, or when systems store IPv4 addresses as integers.

---

## Usage
```bash
chmod +x dns_ip-serial.sh
./dns_ip-serial.sh <ip|serial>
```

Examples:
```bash
./dns_ip-serial.sh 192.168.1.1
# -> 3232235777

./dns_ip-serial.sh 3232235777
# -> 192.168.1.1
```

---

## Requirements
- Bash
- No external modules or vendor dependencies

---

## Input / Output
- **Input:** One argument (`$1`)
  - IPv4 dotted-quad: `a.b.c.d`
  - or an integer: `0` to `4294967295`

- **Output:** Printed to STDOUT
  - If input is an IPv4 dotted-quad: prints the integer representation
  - If input is an integer: prints the corresponding IPv4 dotted-quad

Errors and usage help are printed to STDERR.

---

## Notes
- Validates IPv4 octets (`0..255`).
- Validates integer range (`0..4294967295`, i.e. `2^32 - 1`).
- Uses bit shifting, so the conversion is effectively network-order style:
  - `serial = (a<<24) + (b<<16) + (c<<8) + d`
- Input that is neither dotted-quad nor a non-negative integer is rejected.

---

## License
This script is covered under the repository’s main [MIT License](../LICENSE).
