#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# Minimal DGA demo
#
# Generates:
# - TIMESTAMPS_COUNT distinct timestamps (continuous, slot-based)
# - For each timestamp: DOMAINS_PER_TIMESTAMP domains
# - Exactly REGISTERED_PER_TIMESTAMP domains per timestamp are "REGISTERED"
#
# Constraint enforced:
#   TIMESTAMPS_COUNT > DOMAINS_PER_TIMESTAMP > REGISTERED_PER_TIMESTAMP
# ------------------------------------------------------------

# ====== Demo knobs (edit only these) ======
TIMESTAMPS_COUNT=5               # how many timestamps to print
SLOT_SECONDS=3600                # distance between timestamps (continuous timeline)
DOMAINS_PER_TIMESTAMP=3          # how many domains per timestamp
REGISTERED_PER_TIMESTAMP=1       # how many are reachable per timestamp
LABEL_LEN=12
SECRET="demo-shared-secret"
TLDs=(com net org de fr)
# =========================================

# ---- validations ----
if ! [[ "$TIMESTAMPS_COUNT" =~ ^[0-9]+$ && "$SLOT_SECONDS" =~ ^[0-9]+$ && \
        "$DOMAINS_PER_TIMESTAMP" =~ ^[0-9]+$ && "$REGISTERED_PER_TIMESTAMP" =~ ^[0-9]+$ ]]; then
  echo "All variables must be integers." >&2
  exit 2
fi

if [[ "$TIMESTAMPS_COUNT" -le "$DOMAINS_PER_TIMESTAMP" ]] || [[ "$DOMAINS_PER_TIMESTAMP" -le "$REGISTERED_PER_TIMESTAMP" ]]; then
  echo "Constraint violated: TIMESTAMPS_COUNT > DOMAINS_PER_TIMESTAMP > REGISTERED_PER_TIMESTAMP" >&2
  echo "Current: $TIMESTAMPS_COUNT > $DOMAINS_PER_TIMESTAMP > $REGISTERED_PER_TIMESTAMP" >&2
  exit 2
fi

command -v openssl >/dev/null || { echo "openssl required." >&2; exit 2; }

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
    [[ -z "$byte_hex" ]] && hex=$(hmac_hex "$hex") && i=0 && continue
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
  local ts_index="$1"
  local dom_index="$2"
  local digest
  digest=$(hmac_hex "ts:${ts_index}:dom:${dom_index}")
  printf '%s.%s' "$(gen_label "$digest")" "$(pick_tld "$digest")"
}

# deterministically select REGISTERED_PER_TIMESTAMP indices within [0..DOMAINS_PER_TIMESTAMP-1]
registered_set_for_ts() {
  local ts_index="$1"
  local seed
  seed=$(hmac_hex "reg:${ts_index}")

  declare -A reg=()
  local picked=0
  local offset=0

  while [[ "$picked" -lt "$REGISTERED_PER_TIMESTAMP" ]]; do
    # extend seed if we run out of bytes
    if [[ $((offset*2 + 2)) -gt ${#seed} ]]; then
      seed=$(hmac_hex "$seed")
      offset=0
      continue
    fi

    local idx=$((16#${seed:$((offset*2)):2} % DOMAINS_PER_TIMESTAMP))
    offset=$((offset + 1))

    if [[ -z "${reg[$idx]:-}" ]]; then
      reg["$idx"]=1
      picked=$((picked + 1))
    fi
  done

  # print keys (indices), one per line
  for k in "${!reg[@]}"; do
    printf '%s\n' "$k"
  done
}

# ---- main ----
START_EPOCH=$(date +%s)

printf "#\n"
printf "%-16s %-28s %s\n" "timestamp" "domain" "status"
printf "#\n"


for ((t=0; t<TIMESTAMPS_COUNT; t++)); do
  epoch=$((START_EPOCH + t * SLOT_SECONDS))
  ts=$(fmt_ts "$epoch")

  # build registered lookup for this timestamp
  declare -A IS_REG=()
  while IFS= read -r idx; do
    IS_REG["$idx"]=1
  done < <(registered_set_for_ts "$t")

  for ((d=0; d<DOMAINS_PER_TIMESTAMP; d++)); do
    dom=$(domain_for "$t" "$d")
    if [[ -n "${IS_REG[$d]:-}" ]]; then
      status="REGISTERED"
    else
      status="NXDOMAIN"
    fi
    printf "%-16s %-28s %s\n" "$ts" "$dom" "$status"
  done
    printf "#\n"
done
