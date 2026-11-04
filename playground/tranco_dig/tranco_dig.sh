#!/bin/bash

# Resolve domains from the Tranco top 1M CSV list with subdomains.
# Usage: ./tranco_dig.sh [dns_server] [limit]
# Example: ./tranco_dig.sh 9.9.9.9 500

DNS_SERVER=${1:-9.9.9.9}
LIMIT=${2:-}
DATE_TAG=$(date +%Y-%m-%d)
TMP_DIR="./tmp_tranco_run_$DATE_TAG"
TRANCO_URL="https://tranco-list.eu/top-1m-incl-subdomains.csv.zip"
ZIP_FILE="$TMP_DIR/top-1m-incl-subdomains.csv.zip"
CSV_FILE="$TMP_DIR/top-1m-incl-subdomains.csv"
DOMAIN_FILE="$TMP_DIR/domains.csv"
RESULT_FILE="$TMP_DIR/results.csv"
DIG_TIMEOUT=${DIG_TIMEOUT:-1}
DIG_TRIES=${DIG_TRIES:-1}

mkdir -p "$TMP_DIR"

if [[ -n "$LIMIT" && ! "$LIMIT" =~ ^[0-9]+$ ]]; then
  echo "[x] Limit must be a positive integer."
  exit 1
fi

if [[ -n "$LIMIT" && "$LIMIT" -eq 0 ]]; then
  echo "[x] Limit must be greater than 0."
  exit 1
fi

for cmd in curl unzip dig wc awk; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[x] Required command not found: $cmd"
    exit 1
  fi
done

csv_escape() {
  # Escape double quotes for CSV and wrap the field in quotes.
  printf '"%s"' "$(printf '%s' "$1" | awk '{ gsub(/"/, "\"\""); printf "%s", $0 }')"
}

join_answers() {
  # Join multiline dig output with semicolons.
  awk 'NF { gsub(/\r/, ""); if (out != "") out = out ";"; out = out $0 } END { printf "%s", out }'
}

echo "[ ] Fetching latest Tranco top 1M list with subdomains..."
if ! curl -fsSL -o "$ZIP_FILE" "$TRANCO_URL"; then
  echo "[x] Failed to download Tranco list."
  exit 1
fi

if [[ ! -s "$ZIP_FILE" ]]; then
  echo "[x] Failed to download or empty file: $ZIP_FILE"
  exit 1
fi

echo "[ ] Extracting CSV file..."
if ! unzip -p "$ZIP_FILE" > "$CSV_FILE"; then
  echo "[x] Failed to extract CSV file from ZIP."
  exit 1
fi

if [[ ! -s "$CSV_FILE" ]]; then
  echo "[x] Failed to extract or empty CSV file: $CSV_FILE"
  exit 1
fi

# Tranco CSV format is rank,domain without a header, for example:
# 1,google.com
# 2,gtld-servers.net
# The source file may use CRLF line endings, so strip carriage returns before lookups.
awk -F, -v limit="$LIMIT" '
  NF >= 2 {
    rank = $1
    domain = $2
    gsub(/\r/, "", rank)
    gsub(/\r/, "", domain)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", rank)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", domain)

    if (rank ~ /^[0-9]+$/ && domain != "") {
      print rank "," domain
      count++
      if (limit != "" && count >= limit) { exit }
    }
  }
' "$CSV_FILE" > "$DOMAIN_FILE"

if [[ ! -s "$DOMAIN_FILE" ]]; then
  echo "[x] No domains extracted. Domain file is empty."
  exit 1
fi

TOTAL=$(wc -l < "$DOMAIN_FILE" | tr -d ' ')
echo "[ ] Domain list ready: $DOMAIN_FILE ($TOTAL domains)"
echo "[ ] Resolving domains with dig (DNS: $DNS_SERVER)..."

echo "rank,domain,status,answers" > "$RESULT_FILE"
COUNT=0
FAILED=0

while IFS=, read -r rank domain || [[ -n "$rank$domain" ]]; do
  # Defensive cleanup in case DOMAIN_FILE was created by an older script version.
  rank=$(printf '%s' "$rank" | tr -d '\r')
  domain=$(printf '%s' "$domain" | tr -d '\r')

  [[ -z "$rank" || -z "$domain" ]] && continue

  COUNT=$((COUNT + 1))
  percent=$((COUNT * 100 / TOTAL))
  printf "\r    Progress: %3d%% (%d/%d, failed: %d)" "$percent" "$COUNT" "$TOTAL" "$FAILED"

  raw_answers=$(dig +time="$DIG_TIMEOUT" +tries="$DIG_TRIES" +short @"$DNS_SERVER" "$domain" 2>/dev/null)
  status=$?

  if [[ "$status" -ne 0 ]]; then
    FAILED=$((FAILED + 1))
  fi

  answers=$(printf '%s\n' "$raw_answers" | join_answers)
  printf '%s,%s,%s,%s\n' "$rank" "$(csv_escape "$domain")" "$status" "$(csv_escape "$answers")" >> "$RESULT_FILE"
done < "$DOMAIN_FILE"

echo -e "\n[ ] Done. Results saved in: $RESULT_FILE"
echo "[ ] Failed lookups: $FAILED"
