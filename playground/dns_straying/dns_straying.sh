#!/usr/bin/env bash

set -u

ZONE=${1:-}
if [ -z "$ZONE" ]; then
  echo "Usage: $0 <zone>"
  exit 1
fi

# strip trailing dot
ZONE=${ZONE%.}

MAX_FQDNS=${MAX_FQDNS:-16}

#
# 1) Get NS names
#
NSNAMES_RAW=$(dig +short NS "$ZONE")
if [ -z "$NSNAMES_RAW" ]; then
  echo "No NS records found for zone: $ZONE"
  exit 1
fi

NSNAMES=()
while read -r ns; do
  [ -z "$ns" ] && continue
  NSNAMES+=("${ns%.}")
done <<< "$NSNAMES_RAW"

#
# 2) Resolve NS to A + AAAA
#
SERVERS=()

for ns in "${NSNAMES[@]}"; do
  while read -r ip; do
    [ -n "$ip" ] && SERVERS+=("$ip")
  done < <(dig +short "$ns" A)

  while read -r ip; do
    [ -n "$ip" ] && SERVERS+=("$ip")
  done < <(dig +short "$ns" AAAA)
done

if [ "${#SERVERS[@]}" -eq 0 ]; then
  echo "Could not resolve any IPs for NS records of $ZONE"
  exit 1
fi

# Deduplicate
TMP_SERVERS=$(printf '%s\n' "${SERVERS[@]}" | sort -u)
SERVERS=()
while read -r ip; do
  [ -z "$ip" ] && continue
  SERVERS+=("$ip")
done <<< "$TMP_SERVERS"

echo
echo "Zone:       $ZONE"
echo "NS names:   ${NSNAMES[*]}"
echo "NS addrs:   ${SERVERS[*]}"
echo

#
# 3) Generate random hostname strings
#
# Generate 16-character DNS-safe base64-like tokens
#
FQDNS=()
for ((i=0; i<MAX_FQDNS; i++)); do
  host=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 16)
  FQDNS+=("${host}.${ZONE}")
done

echo "Generated FQDNs:"
printf '  %s\n' "${FQDNS[@]}"
echo

#
# 4) Ask before sending
#
read -r -p "Send ${#FQDNS[@]} DNS queries to ${#SERVERS[@]} servers? [Y/n]: " answer
answer=${answer:-Y}

case "$answer" in
  [Yy]* ) ;;
  * )
    echo "Aborted."
    exit 0
    ;;
esac

#
# 5) Query + random delays
#
delays=(0.50 0.75 1.00 1.25 1.50 1.75 2.00)

echo
echo "Sending queries..."
for fqdn in "${FQDNS[@]}"; do
  srv=${SERVERS[$((RANDOM % ${#SERVERS[@]}))]}
  delay=${delays[$((RANDOM % ${#delays[@]}))]}

  echo "  $fqdn with ${delay}s delay to $srv"
  dig @"$srv" "$fqdn" +time=1 +tries=1 >/dev/null 2>&1

  sleep "$delay"
done

echo
echo "Done."
echo