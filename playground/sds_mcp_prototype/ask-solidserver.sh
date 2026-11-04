#!/bin/zsh

DEFAULT_SERVER="ipam.mktg.emea.demo"
DEFAULT_USER="ipmadmin"

export SOLIDSERVER_INSECURE_TLS="true"

if [ -z "${SOLIDSERVER_URL:-}" ]; then
  read "SOLIDSERVER_HOST?SOLIDserver IP/Host [$DEFAULT_SERVER]: "
  SOLIDSERVER_HOST="${SOLIDSERVER_HOST:-$DEFAULT_SERVER}"

  read "SOLIDSERVER_USER?Username [$DEFAULT_USER]: "
  SOLIDSERVER_USER="${SOLIDSERVER_USER:-$DEFAULT_USER}"

  if [ -z "${SOLIDSERVER_PASSWORD:-}" ]; then
    read -s "SOLIDSERVER_PASSWORD?Password: "
    echo
  fi

  export SOLIDSERVER_URL="https://${SOLIDSERVER_HOST}"
  export SOLIDSERVER_USER
  export SOLIDSERVER_PASSWORD
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec /usr/bin/env python3 "$SCRIPT_DIR/ask_solidserver.py"