# quad9_dig.sh

## Description
Fetches the latest Quad9 top 500 domains JSON file from the `Quad9DNS/quad9-domains-top500` GitHub repository, extracts the domain names, and resolves each domain with `dig` against a chosen DNS server. The script stores the downloaded JSON, extracted domain list, and resolution results in a date-based temporary folder.

---

## Usage
Run the script with the default Quad9 resolver:

```bash
./quad9_dig.sh
```

Run the script with a custom DNS server:

```bash
./quad9_dig.sh 1.1.1.1
```

---

## Requirements
- Bash
- `curl`
- `grep`
- `sort`
- `head`
- `jq`
- `dig`
- `wc`

---

## Input / Output
- **Input:**
  - Optional first argument: DNS server IP address
  - Remote source: latest `top500-YYYY-MM-DD.json` file from the Quad9 GitHub repository
- **Output:**
  - Temporary working directory: `./tmp_quad9_run_YYYY-MM-DD`
  - Downloaded JSON file: `top500-YYYY-MM-DD.json`
  - Extracted domain list: `top500.csv`
  - Resolution results: `results.txt`

The `results.txt` file contains one line per domain in this format:

```text
domain.tld,answer
```

---

## Notes
- If no DNS server is provided, the script uses `9.9.9.9` by default.
- The script determines the latest Quad9 top 500 file by parsing the repository HTML page.
- The JSON extraction assumes each entry contains a `domain_name` field.
- `dig +short` may return multiple records for a domain. They are written after the comma as returned by `dig`.
- If the GitHub repository layout changes, detection of the latest JSON file may fail.
- The script exits with an error if:
  - no matching JSON file is found
  - the JSON file cannot be downloaded
  - no domains can be extracted

Useful references:
- Quad9 top domains repository: `https://github.com/Quad9DNS/quad9-domains-top500`
- `dig` manual: `man dig`

---

## License
This script is covered under the repository’s main [MIT License](../LICENSE).
