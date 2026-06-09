# tranco_dig.sh

## Description

Downloads the [Tranco top 1M list](https://tranco-list.eu/) including subdomains, extracts the CSV file from the ZIP archive, and resolves each domain with `dig` against a chosen DNS resolver.

The script stores the downloaded ZIP file, extracted CSV file, cleaned domain list, and DNS lookup results in a date-based temporary directory.

## Source format

The CSV file inside the Tranco ZIP has no header and uses this format:

```text
1,google.com
2,gtld-servers.net
3,cloudflare.com
4,gstatic.com
```

The first column is the rank. The second column is the domain name.

The script keeps the rank for traceability and strips carriage returns from the input because the source CSV may use CRLF line endings.

## Usage

Run with the default DNS resolver, Quad9 `9.9.9.9`:

```bash
./tranco_dig.sh
```

Run with a custom DNS resolver:

```bash
./tranco_dig.sh 1.1.1.1
```

Run with a custom DNS resolver and a limit:

```bash
./tranco_dig.sh 9.9.9.9 500
```

The limit is useful for testing because the full list contains up to 1,000,000 domains.

## Optional tuning

You can change the `dig` timeout and retry count with environment variables:

```bash
DIG_TIMEOUT=3 DIG_TRIES=1 ./tranco_dig.sh 9.9.9.9 500
```

Defaults:

```text
DIG_TIMEOUT=3
DIG_TRIES=1
```

## Requirements

- Bash
- `curl`
- `unzip`
- `dig`
- `wc`
- `awk`

## Input and output

Input:

- Optional first argument: DNS server IP address
- Optional second argument: maximum number of domains to resolve
- Remote source: `https://tranco-list.eu/top-1m-incl-subdomains.csv.zip`

Output:

- Temporary working directory: `./tmp_tranco_run_YYYY-MM-DD`
- Downloaded ZIP file: `top-1m-incl-subdomains.csv.zip`
- Extracted source CSV: `top-1m-incl-subdomains.csv`
- Cleaned domain list: `domains.csv`
- Resolution results: `results.csv`

The `results.csv` file contains one line per domain:

```csv
rank,domain,status,answers
1,"google.com",0,"142.250.185.206"
```

Fields:

- `rank`: Tranco rank
- `domain`: domain from the Tranco list
- `status`: exit status from `dig`
- `answers`: `dig +short` output, with multiple answers joined by semicolons

## Notes

- If no DNS server is provided, the script uses Quad9 `9.9.9.9`.
- A failed lookup does not stop the script. It is counted and written with the non-zero `dig` status.
- Multiple `dig +short` answers are joined with semicolons so each domain stays on one CSV row.
- The script strips carriage returns from the Tranco input before lookups.
- Delete the temporary directory before retesting if you want to ensure that no old generated files are reused:

```bash
rm -rf ./tmp_tranco_run_$(date +%Y-%m-%d)
```

## Useful references

- Tranco: `https://tranco-list.eu/`
- Tranco CSV ZIP with subdomains: `https://tranco-list.eu/top-1m-incl-subdomains.csv.zip`
- `dig` manual: `man dig`
