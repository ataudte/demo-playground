#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# DGA activity demo
#
# Generates:
# - TIMESTAMPS_COUNT timestamps, starting at the current full hour
# - For each timestamp: DOMAINS_PER_TIMESTAMP domains
# - Domains that change deterministically with each time slot
# - Exactly REGISTERED_PER_TIMESTAMP simulated "REGISTERED" domains per slot
#
# Usage: ./dns_dga-demo.sh [DGA_SECRET]
#
# This script generates demo data; it does not register or resolve domains.
# ------------------------------------------------------------

if (( $# > 1 )); then
  printf 'Usage: %s [DGA_SECRET]\n' "${0##*/}" >&2
  exit 2
fi

# ====== Demo knobs (edit only these) ======
TIMESTAMPS_COUNT=5               # how many time groups to print
SLOT_SECONDS=3600                # distance between groups (3600 = hourly)
DOMAINS_PER_TIMESTAMP=3          # how many domains per timestamp
REGISTERED_PER_TIMESTAMP=1       # simulated registered domains per timestamp
LABEL_LEN=12
SECRET="${1:-demo-shared-secret}}" # $1, then demo default
TLDs=(com net org de fr)
# =========================================

# ---- validations ----
if ! [[ "$TIMESTAMPS_COUNT" =~ ^[0-9]+$ && "$SLOT_SECONDS" =~ ^[0-9]+$ && \
        "$DOMAINS_PER_TIMESTAMP" =~ ^[0-9]+$ && "$REGISTERED_PER_TIMESTAMP" =~ ^[0-9]+$ && \
        "$LABEL_LEN" =~ ^[0-9]+$ ]]; then
  echo "All variables must be integers." >&2
  exit 2
fi

# Normalize decimal values so values such as 08 are not interpreted as octal.
TIMESTAMPS_COUNT=$((10#$TIMESTAMPS_COUNT))
SLOT_SECONDS=$((10#$SLOT_SECONDS))
DOMAINS_PER_TIMESTAMP=$((10#$DOMAINS_PER_TIMESTAMP))
REGISTERED_PER_TIMESTAMP=$((10#$REGISTERED_PER_TIMESTAMP))
LABEL_LEN=$((10#$LABEL_LEN))

if (( TIMESTAMPS_COUNT < 1 || SLOT_SECONDS < 1 || DOMAINS_PER_TIMESTAMP < 1 )); then
  echo "TIMESTAMPS_COUNT, SLOT_SECONDS, and DOMAINS_PER_TIMESTAMP must be greater than zero." >&2
  exit 2
fi

if (( REGISTERED_PER_TIMESTAMP >= DOMAINS_PER_TIMESTAMP )); then
  echo "REGISTERED_PER_TIMESTAMP must be smaller than DOMAINS_PER_TIMESTAMP." >&2
  exit 2
fi

if (( LABEL_LEN < 1 || LABEL_LEN > 63 )); then
  echo "LABEL_LEN must be between 1 and 63." >&2
  exit 2
fi

if (( ${#TLDs[@]} == 0 )); then
  echo "At least one TLD is required." >&2
  exit 2
fi

for required_command in awk date openssl; do
  command -v "$required_command" >/dev/null || {
    echo "$required_command is required." >&2
    exit 2
  }
done

# ---- portable date formatting (macOS BSD + GNU) ----
fmt_ts() {
  local epoch="$1"
  if date -d "@0" >/dev/null 2>&1; then
    date -d "@$epoch" +"%Y%m%d-%H%M%S"     # GNU
  else
    date -r "$epoch" +"%Y%m%d-%H%M%S"      # BSD (macOS)
  fi
}

# ---- deterministic helpers ----
hmac_hex() {
  local msg="$1"
  printf '%s' "$msg" | openssl dgst -sha256 -hmac "$SECRET" 2>/dev/null | awk '{print $NF}'
}

gen_label() {
  local hex="$1"
  local charset="abcdefghijklmnopqrstuvwxyz0123456789"
  local out=""
  local i=0

  while [[ ${#out} -lt "$LABEL_LEN" ]]; do
    local byte_hex=${hex:$((i*2)):2}
    if [[ -z "$byte_hex" ]]; then
      hex=$(hmac_hex "$hex")
      i=0
      continue
    fi
    local byte=$((16#$byte_hex))
    out+=${charset:$((byte % ${#charset})):1}
    i=$((i+1))
  done

  printf '%s' "$out"
}

pick_tld() {
  local hex="$1"
  printf '%s' "${TLDs[$((16#${hex:0:2} % ${#TLDs[@]}))]}"
}

domain_for() {
  local slot_epoch="$1"
  local dom_index="$2"
  local digest
  digest=$(hmac_hex "slot:${slot_epoch}:dom:${dom_index}")
  printf '%s.%s' "$(gen_label "$digest")" "$(pick_tld "$digest")"
}

# deterministically select REGISTERED_PER_TIMESTAMP indices within [0..DOMAINS_PER_TIMESTAMP-1]
registered_set_for_slot() {
  local slot_epoch="$1"
  local -a reg=()
  local picked=0
  local attempt=0
  local digest
  local idx

  while [[ "$picked" -lt "$REGISTERED_PER_TIMESTAMP" ]]; do
    digest=$(hmac_hex "reg:${slot_epoch}:candidate:${attempt}")
    idx=$((16#${digest:0:12} % DOMAINS_PER_TIMESTAMP))
    attempt=$((attempt + 1))

    if [[ -z "${reg[$idx]:-}" ]]; then
      reg["$idx"]=1
      picked=$((picked + 1))
    fi
  done

  # Print selected indices in a stable order.
  for ((idx=0; idx<DOMAINS_PER_TIMESTAMP; idx++)); do
    if [[ -n "${reg[$idx]:-}" ]]; then
      printf '%s\n' "$idx"
    fi
  done
}

# ---- main ----
# Capture all components in one call, then remove minutes and seconds. Unlike
# epoch-modulo alignment, this also lands on :00 in half-hour time zones.
NOW_FIELDS=$(date '+%s %M %S')
NOW_EPOCH=${NOW_FIELDS%% *}
NOW_REMAINDER=${NOW_FIELDS#* }
NOW_MINUTE=${NOW_REMAINDER%% *}
NOW_SECOND=${NOW_REMAINDER#* }
START_EPOCH=$((NOW_EPOCH - 10#$NOW_MINUTE * 60 - 10#$NOW_SECOND))

printf "#\n"
printf "%-16s %-28s %s\n" "timestamp" "domain" "status"
printf "#\n"

for ((t=0; t<TIMESTAMPS_COUNT; t++)); do
  epoch=$((START_EPOCH + t * SLOT_SECONDS))
  ts=$(fmt_ts "$epoch")

  # build registered lookup for this timestamp
  IS_REG=()
  registered_indices=$(registered_set_for_slot "$epoch")
  for idx in $registered_indices; do
    IS_REG["$idx"]=1
  done

  for ((d=0; d<DOMAINS_PER_TIMESTAMP; d++)); do
    dom=$(domain_for "$epoch" "$d")
    if [[ -n "${IS_REG[$d]:-}" ]]; then
      status="REGISTERED"
    else
      status="NXDOMAIN"
    fi
    printf "%-16s %-28s %s\n" "$ts" "$dom" "$status"
  done
  printf "#\n"
done
