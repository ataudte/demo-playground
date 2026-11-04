#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage:
  $0 <ip|serial>
Examples:
  $0 192.168.1.1       # prints 3232235777
  $0 3232235777        # prints 192.168.1.1
EOF
  exit 1
}

if [ $# -ne 1 ]; then
  usage
fi

inp="$1"

# detect dotted-quad
if [[ "$inp" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  # ip -> serial
  IFS=. read -r a b c d <<< "$inp"
  for oct in "$a" "$b" "$c" "$d"; do
    if (( oct < 0 || oct > 255 )); then
      echo "invalid octet: $oct" >&2
      exit 2
    fi
  done
  serial=$(( (a<<24) + (b<<16) + (c<<8) + d ))
  printf '%d\n' "$serial"
  exit 0
fi

# detect integer (serial) -> ip
if [[ "$inp" =~ ^[0-9]+$ ]]; then
  # ensure within 0 .. 2^32-1
  max=4294967295
  if (( inp < 0 || inp > max )); then
    echo "serial out of range (0..$max)" >&2
    exit 2
  fi
  n=$((inp))
  printf '%d.%d.%d.%d\n' $(( (n>>24) & 255 )) $(( (n>>16) & 255 )) $(( (n>>8) & 255 )) $(( n & 255 ))
  exit 0
fi

echo "unrecognized input" >&2
usage
