#!/usr/bin/env bash
set -euo pipefail

CONFIG_PATH="${CONFIG_PATH:-$HOME/tools/dnscrypt-proxy.toml}"
BIN_PATH="${BIN_PATH:-$(command -v dnscrypt-proxy)}"
PIDFILE="${PIDFILE:-$HOME/tools/.dnscrypt-proxy.pid}"
LOGFILE="${LOGFILE:-$HOME/tools/.dnscrypt-proxy.log}"

# settings from dnscrypt-proxy.toml to print
SETTINGS_KEYS=(
  server_names
  listen_addresses
  ipv4_servers
  ipv6_servers
  dnscrypt_servers
  doh_servers
  odoh_servers
  require_dnssec
  require_nolog
  require_nofilter
)

die() { echo "ERROR: $*" >&2; exit 1; }

need_bin() {
  [[ -n "${BIN_PATH}" ]] || die "dnscrypt-proxy not found in PATH"
  [[ -x "${BIN_PATH}" ]] || die "dnscrypt-proxy binary not executable: ${BIN_PATH}"
}

need_config() {
  [[ -f "${CONFIG_PATH}" ]] || die "Config not found: ${CONFIG_PATH}"
  [[ -r "${CONFIG_PATH}" ]] || die "Config not readable: ${CONFIG_PATH}"
}

# Find the newest dnscrypt-proxy PID started with our exact config
find_pid() {
  # -f: match full command line, -n: newest
  # Use sudo because the process is root-owned when binding to :53
  sudo pgrep -fn "dnscrypt-proxy.*-config[[:space:]]+${CONFIG_PATH}" 2>/dev/null || true
}

is_running() {
  local pid
  pid="$(find_pid)"
  [[ -n "${pid}" ]] && sudo kill -0 "${pid}" 2>/dev/null
}

start() {
  need_bin
  need_config

  if is_running; then
    echo "# dnscrypt-proxy already running (pid $(find_pid))"
    exit 0
  fi

  if ! "${BIN_PATH}" -config "${CONFIG_PATH}" -check >/dev/null 2>&1; then
    die "Config check failed. Run: ${BIN_PATH} -config '${CONFIG_PATH}' -check"
  fi

  sudo -v
  echo "# Starting dnscrypt-proxy using ${CONFIG_PATH}"

  # Start it (root-owned). Don't try to trust $! on macOS.
  sudo sh -c "
    '${BIN_PATH}' -config '${CONFIG_PATH}' >>'${LOGFILE}' 2>&1 &
  "

  # Give it a moment, then discover the real PID
  sleep 0.5
  local pid
  pid="$(find_pid)"
  [[ -n "${pid}" ]] || die "dnscrypt-proxy did not appear in process list. Check log: ${LOGFILE}"

  echo "${pid}" > "${PIDFILE}" 2>/dev/null || true

  # Sanity check: ensure it's alive
  if ! sudo kill -0 "${pid}" 2>/dev/null; then
    rm -f "${PIDFILE}" 2>/dev/null || true
    die "dnscrypt-proxy failed to stay up. Check log: ${LOGFILE}"
  fi

  for key in "${SETTINGS_KEYS[@]}"; do
	  line="$(grep -m1 "^${key}[[:space:]]*=" "$CONFIG_PATH" || true)"
	
	  if [[ -n "$line" ]]; then
		value="$(
		  printf '%s\n' "$line" | sed -E '
			s/^[^=]*=[[:space:]]*//;
			s/[[:space:]]+#.*$//;
			s/[[:space:]]+$//
		  '
		)"
		printf '  %s = %s\n' "$key" "$value"
	  else
		printf '  %s = (not set)\n' "$key"
	  fi
  done

  echo "# Started (pid ${pid})"
  echo "  lowest latency: $(sed -nE 's/.*lowest initial latency: ([^ ]+) \(rtt:.*/\1/p' "$LOGFILE" | tail -n1)"
  echo "# Log: ${LOGFILE}"
  
}

stop() {
  sudo -v

  local pid=""
  if [[ -f "${PIDFILE}" ]]; then
    pid="$(cat "${PIDFILE}" 2>/dev/null || true)"
  fi

  # If pidfile is missing/stale, fall back to process discovery
  if [[ -z "${pid}" ]] || ! sudo kill -0 "${pid}" 2>/dev/null; then
    pid="$(find_pid)"
  fi

  if [[ -z "${pid}" ]]; then
    rm -f "${PIDFILE}" 2>/dev/null || true
    echo "# Not running"
    exit 0
  fi

  echo "# Stopping dnscrypt-proxy (pid ${pid})"
  sudo kill "${pid}" 2>/dev/null || true

  for _ in {1..30}; do
    if ! sudo kill -0 "${pid}" 2>/dev/null; then
      rm -f "${PIDFILE}" 2>/dev/null || true
      echo "# Stopped"
      exit 0
    fi
    sleep 0.2
  done

  echo "# Still running; sending SIGKILL"
  sudo kill -9 "${pid}" 2>/dev/null || true
  rm -f "${PIDFILE}" 2>/dev/null || true
  echo "# Stopped (SIGKILL)"
}

status() {
  local pid
  pid="$(find_pid)"
  if [[ -n "${pid}" ]]; then
    echo "# Running (pid ${pid})"
    exit 0
  fi

  echo "# Not running"
  exit 1
}

case "${1:-}" in
  start) start ;;
  stop) stop ;;
  status) status ;;
  *)
    echo "Usage: $0 {start|stop|status}"
    echo "Overrides: CONFIG_PATH=... BIN_PATH=... PIDFILE=... LOGFILE=..."
    exit 2
    ;;
esac