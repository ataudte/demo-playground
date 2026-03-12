#!/bin/bash

# Usage: ./quad9_dig.sh [dns_server]
DNS_SERVER=${1:-9.9.9.9}
DATE_TAG=$(date +%Y-%m-%d)
TMP_DIR="./tmp_quad9_run_$DATE_TAG"
RAW_PREFIX="https://raw.githubusercontent.com/Quad9DNS/quad9-domains-top500/main/"
REPO_HTML="https://github.com/Quad9DNS/quad9-domains-top500"

mkdir -p "$TMP_DIR"

echo "[ ] Fetching latest top500 JSON file from GitHub..."

LATEST_FILE=$(curl -s "$REPO_HTML" | grep -oE 'top500-[0-9]{4}-[0-9]{2}-[0-9]{2}\.json' | sort -r | head -n1)

if [[ -z "$LATEST_FILE" ]]; then
  echo "[x] Could not find any top500 JSON files in repo HTML."
  exit 1
fi

echo "[ ] Found latest file: $LATEST_FILE"

JSON_PATH="$TMP_DIR/$LATEST_FILE"
curl -s -o "$JSON_PATH" "${RAW_PREFIX}${LATEST_FILE}"

if [[ ! -s "$JSON_PATH" ]]; then
  echo "[x] Failed to download or empty file: $JSON_PATH"
  exit 1
fi

# Extract domain names (NDJSON format)
CSV_FILE="$TMP_DIR/top500.csv"
jq -r '.domain_name' "$JSON_PATH" > "$CSV_FILE"

if [[ ! -s "$CSV_FILE" ]]; then
  echo "[x] No domains extracted. CSV is empty."
  exit 1
fi

echo "[ ] Domain list ready: $CSV_FILE"
echo "[ ] Resolving domains with dig (DNS: $DNS_SERVER)..."

# Prepare output
RESULT_FILE="$TMP_DIR/results.txt"
> "$RESULT_FILE"

# Progress bar setup
TOTAL=$(wc -l < "$CSV_FILE")
COUNT=0

# Loop with progress bar
while IFS= read -r domain; do
  COUNT=$((COUNT + 1))
  printf "\r    Progress: %3d%% (%d/%d)" $((COUNT * 100 / TOTAL)) "$COUNT" "$TOTAL"
  RESULT=$(dig +short @"$DNS_SERVER" "$domain")
  echo "$domain,$RESULT" >> "$RESULT_FILE"
done < "$CSV_FILE"

echo -e "\n[ ] Done. Results saved in: $RESULT_FILE"
