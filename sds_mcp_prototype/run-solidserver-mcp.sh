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

cat <<'EOT'
MCP JSON-RPC examples:
  {"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
  {"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
  {"jsonrpc":"2.0","id":3,"method":"resources/list","params":{}}
  {"jsonrpc":"2.0","id":4,"method":"prompts/list","params":{}}
  {"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"lookup_host_identity","arguments":{"name":"laptop39396"}}}

Type exit or quit to close the session.
EOT

tmpdir="$(mktemp -d)" || exit 1
in_fifo="$tmpdir/mcp_in"
out_fifo="$tmpdir/mcp_out"
mkfifo "$in_fifo" "$out_fifo" || exit 1
cleanup() {
  exec 3>&- 4<&-
  [[ -n "${mcp_pid:-}" ]] && kill "$mcp_pid" 2>/dev/null
  rm -rf "$tmpdir"
}
trap cleanup EXIT INT TERM

/usr/bin/env python3 "$SCRIPT_DIR/solidserver_mcp.py" "$@" <"$in_fifo" >"$out_fifo" &
mcp_pid=$!
exec 3>"$in_fifo"
exec 4<"$out_fifo"

while IFS= read -r line; do
  cmd="$(printf '%s' "$line" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  case "$cmd:l" in
    exit|quit)
      echo "Closing MCP session."
      break
      ;;
    '')
      continue
      ;;
  esac

  print -r -- "$line" >&3

  if IFS= read -r response <&4; then
    print -r -- "$response"
  else
    echo "MCP server closed the session."
    break
  fi
done
