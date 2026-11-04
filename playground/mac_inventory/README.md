# mac_inventory.sh

## Description

Collects hardware, operating-system, storage, network, display, battery, and security information from the Mac on which it is run. It prints a human-readable summary to the terminal and saves the full inventory as a private, timestamped JSON file in the current directory.

The script runs locally and does not transmit the collected data.

---

## Usage

Make the script executable, then run it without arguments:

```bash
chmod +x mac_inventory.sh
./mac_inventory.sh
```

It can also be run through Bash directly:

```bash
bash mac_inventory.sh
```

Run the script from the directory in which the JSON report should be saved. Supplying any command-line argument causes the script to exit with an error.

---

## Requirements

- macOS; the script exits if run on another operating system.
- Bash 3.2 or later.
- Write access to the current directory.
- Standard macOS command-line utilities, including `system_profiler`, `sw_vers`, `sysctl`, `vm_stat`, `diskutil`, `route`, `ifconfig`, `ipconfig`, `pmset`, `ioreg`, `fdesetup`, and `defaults`.
- Optional: `smartctl` from smartmontools for disk power-on hours and reallocated-sector or media-error data.

No Python modules, third-party APIs, network access, or vendor credentials are required.

---

## Input / Output

- **Input:** None. The script inventories the local Mac and accepts no parameters or input files.
- **Terminal output:** A human-readable summary is written to standard output. Progress and error messages are written to standard error.
- **JSON output:** A report named `mac_inventory_YYYYMMDD-HHMMSS.json` is created in the current directory.
- **File permissions:** The JSON report is created with owner-only permissions (`0600`, subject to filesystem behavior) and is not overwritten if a file with the same name already exists.

The report includes:

| Category | Collected information |
| --- | --- |
| System | Hostname, macOS version and build, architecture, Rosetta 2 translation state, and kernel version |
| Hardware | Apple model and identifier, serial number, machine type, estimated model year, and firmware type |
| Processor | CPU or Apple chip model, physical cores, logical threads, and speed when available |
| Memory | Total and estimated used memory, type, speed, and slot counts when applicable |
| Storage | Model, type, capacity, usage, SMART health, and optional SMART statistics |
| Network | MAC address and IPv4 address for the default network interface |
| Displays | Detected display names and resolutions, plus an estimated built-in display size for recognized models |
| Battery and security | Battery presence and health, detected antivirus product, firewall and stealth-mode state, FileVault state, and last successful OS update date |

Example JSON filename:

```text
mac_inventory_20260904-143015.json
```

---

## Notes

- The report contains sensitive device identifiers and network information, including the hostname, serial number, MAC address, and IP address. Store and share it accordingly.
- Missing or inaccessible text values are reported as `"Unknown"`; unavailable numeric and Boolean values may be reported as `null`.
- The manufacture year is inferred from the model name or a built-in model-identifier mapping. The `purchase_year` field mirrors this estimate and is not the device's verified purchase date.
- Built-in display size and Apple silicon memory speed are inferred from static mappings and may be unavailable or inaccurate for unrecognized or newly released models.
- Used memory is an estimate based on active and wired pages, not the complete memory-pressure calculation shown by Activity Monitor.
- Storage capacity is measured for `/System/Volumes/Data` when available, otherwise `/`. Disk model and health checks target the primary storage information exposed by macOS; optional SMART details depend on `smartctl`, device support, and permissions.
- Antivirus detection checks a fixed list of common installation paths and whether `clamscan` is available. `None detected` does not prove that no endpoint-protection software is installed, running, or managed by another service.
- Some macOS privacy controls, permissions, hardware differences, or command-output changes can prevent individual values from being detected. The script continues where possible and records an unavailable value.

---

## License

This script is covered under the repository's main [MIT License](../LICENSE).
