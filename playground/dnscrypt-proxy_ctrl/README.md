# dnscrypt-proxy_ctrl.sh

## Description
Small control script to manage a **dnscrypt-proxy** instance that is started with a specific `dnscrypt-proxy.toml` config.

What it does
- `start` checks the config (`dnscrypt-proxy -check`), starts dnscrypt-proxy via `sudo`, writes a PID file, and prints selected config settings.
- `stop` stops the matching dnscrypt-proxy process (PID file first, then process discovery), escalating to `SIGKILL` if needed.
- `status` reports whether the matching dnscrypt-proxy process is running.

---

## Usage
```bash
./dnscrypt-proxy_ctrl.sh start
./dnscrypt-proxy_ctrl.sh stop
./dnscrypt-proxy_ctrl.sh status
```

### Common overrides (environment variables)
You can override paths without editing the script:

```bash
CONFIG_PATH=$HOME/tools/dnscrypt-proxy.toml \
PIDFILE=$HOME/tools/.dnscrypt-proxy.pid \
LOGFILE=$HOME/tools/.dnscrypt-proxy.log \
./dnscrypt-proxy_ctrl.sh start
```

If `dnscrypt-proxy` is not in your `PATH`, you can also set the binary path:

```bash
BIN_PATH=/usr/local/sbin/dnscrypt-proxy ./dnscrypt-proxy_ctrl.sh start
```

---

## Requirements
- Bash (recommended with `set -euo pipefail` support)
- `dnscrypt-proxy` installed and executable
- `sudo` access (required because dnscrypt-proxy is typically bound to privileged ports such as `:53`)
- Tools used by the script: `pgrep`, `grep`, `sed`, `tail`

---

## Input / Output
- **Input**
  - A readable dnscrypt-proxy configuration file (`dnscrypt-proxy.toml`), default:
    - `CONFIG_PATH=$HOME/tools/dnscrypt-proxy.toml`

- **Output / Artifacts**
  - Log file (stdout/stderr of dnscrypt-proxy), default:
    - `LOGFILE=$HOME/tools/.dnscrypt-proxy.log`
  - PID file (best-effort write), default:
    - `PIDFILE=$HOME/tools/.dnscrypt-proxy.pid`
  - Console output:
    - A short “started/stopped” status line
    - Selected config keys (if present as simple `key = value` lines in the TOML)
    - The most recent “lowest initial latency” line parsed from the log (if present)

---

## Notes
- Process detection
  - Uses `sudo pgrep -fn "dnscrypt-proxy.*-config[[:space:]]+${CONFIG_PATH}"` to find the newest matching process.
  - This avoids relying on `$!` (which can be unreliable across platforms when started through `sudo` / subshells).

- Config value printing
  - The script prints only a fixed set of keys and only if they appear as simple single-line assignments (`key = ...`) in the TOML.
  - It will not evaluate TOML arrays/tables spread across multiple lines.

- Port binding
  - If you bind to port 53, dnscrypt-proxy must run with elevated privileges. Consider binding to an unprivileged port and forwarding with your OS firewall if you want to avoid root.

---

## License
This script is covered under the repository’s main [MIT License](../LICENSE).
