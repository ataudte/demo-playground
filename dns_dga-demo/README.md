# dns_dga-demo.sh

## Description
Minimal, deterministic **Domain Generation Algorithm (DGA)** demo script. It generates time-based domain names in fixed slots and marks a deterministic subset of them as **REGISTERED**, while the rest resolve to **NXDOMAIN**.  It is intended for demos, testing, and teaching DNS behavior, *not* for real malware simulation.

Key characteristics:
- Slot-based timestamps on a continuous timeline
- Deterministic output using HMAC-SHA256
- Reproducible results with a shared secret
- Portable across Linux and macOS

---

## Usage
Make the script executable and run it:

```bash
chmod +x dns_dga-demo.sh
./dns_dga-demo.sh
```

The script prints a table to STDOUT containing timestamps, generated domains, and their simulated resolution status.

Example output:
```
timestamp        domain                       status
20260130-120000  abcd1234efgh.com             REGISTERED
20260130-120000  zyxw9876lmno.net              NXDOMAIN
```

---

## Requirements
- Bash (tested with Bash 4+)
- `openssl`
- `date` (GNU or BSD/macOS supported)

No external libraries or network access required.

---

## Input / Output
- **Input:**  
  No external input files. Configuration is done by editing variables at the top of the script:
  - `TIMESTAMPS_COUNT`
  - `SLOT_SECONDS`
  - `DOMAINS_PER_TIMESTAMP`
  - `REGISTERED_PER_TIMESTAMP`
  - `LABEL_LEN`
  - `SECRET`
  - `TLDs`

- **Output:**  
  Plain text table printed to STDOUT, suitable for piping into files, tools, or demos.

---

## Notes
- The constraint `TIMESTAMPS_COUNT > DOMAINS_PER_TIMESTAMP > REGISTERED_PER_TIMESTAMP` is enforced.
- Domains are generated deterministically using HMAC-SHA256; changing the `SECRET` changes the entire dataset.
- This is a **demo and teaching tool**, not a real DGA implementation used by malware.

---

## License
This script is covered under the repository’s main [MIT License](../LICENSE).
