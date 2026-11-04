# dns_tunnel.sh

## Description
Bash demo script that simulates **DNS tunneling** by encoding a file into a list of DNS-style hostnames (client mode) and reconstructing the original file from that hostname log (server mode).

What it does:
- **client**: base64-encodes a file, splits the output into DNS label-sized chunks (max 63 chars), appends a random domain, and writes the resulting “queries” to a log file.
- **server**: reads that log file, extracts the first label from each hostname, concatenates the chunks, and base64-decodes them back into a reconstructed file.

This is intended for **education and demos** (how data can be carried in DNS labels), not for covert exfiltration.

---

## Usage

### Client mode (encode a file to hostname log)
```bash
chmod +x dns_tunnel.sh
./dns_tunnel.sh client <file-to-send>
```

Output:
- Creates/overwrites `dns_tunnel.log`
- Writes one hostname per line in the form:
  - `<base64-chunk>.<random8>.com`

Example:
```bash
./dns_tunnel.sh client ./sample.bin
# -> File encoded as DNS hostnames and saved to dns_tunnel.log
```

### Server mode (reconstruct file from hostname log)
```bash
./dns_tunnel.sh server <log-file>
```

Example:
```bash
./dns_tunnel.sh server dns_tunnel.log
# -> File successfully reconstructed and saved to tunnel/reconstructed_file
```

---

## Requirements
- Bash
- Tools used by the script:
  - `base64`
  - `awk`
  - `tr`, `fold`, `head`
  - `mkdir`
  - `/dev/urandom`

### Platform note (base64 flags)
This script uses **macOS/BSD** `base64` flags:
- encode: `base64 -i <file>`
- decode: `base64 -D -o <output>`

On Linux/GNU systems, you typically need to adjust these:
- encode: `base64 <file>` (optionally `-w 0` to disable line-wrapping)
- decode: `base64 -d > <output>`

---

## Input / Output
- **Input (client):** a file path passed as `$2`
- **Output (client):**
  - `dns_tunnel.log` in the current directory (overwritten)

- **Input (server):** a log file path passed as `$2`
- **Output (server):**
  - directory: `tunnel/`
  - file: `tunnel/reconstructed_file`

---

## Notes
- Chunks are limited to **63 characters** to stay within the DNS label length limit.
- The generated “domain” is random and only used to make entries look like realistic FQDNs.
- The script does **not** perform any DNS queries; it only generates/consumes a hostname log.
- This is a simplified demo:
  - no ordering/sequence checks
  - no integrity validation (hashing)
  - no handling of packet loss, duplication, or reordering
  - base64 line-wrapping behavior depends on platform defaults (can affect chunking)

---

## License
This script is covered under the repository’s main [MIT License](../LICENSE).
