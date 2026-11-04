# ms_demo-data.ps1

## Description
Seeds a Windows Server (2019+) with example **DNS** and **DHCP** data for lab / demo use.

- Creates forward lookup zones (parent + child zones)
- Populates common record types (A, AAAA, CNAME, MX, TXT, SRV)
- Creates reverse lookup zones and matching PTR records:
  - /24 reverse zones for each created **A**
  - /64 reverse zones for each created **AAAA**
- Creates DHCP scopes (IPv4 + IPv6) with example reservations and address pools
- Applies DHCP option values (DNS servers, domain name/search, NTP)
- Safe to re-run: checks for existing zones, records, scopes, and reservations before creating them

---

## Usage
Run from an elevated PowerShell (Administrator). Use `-WhatIf` to preview.

```powershell
# Preview only (no changes)
pwsh .\ms_demo-data.ps1 -WhatIf

# Apply changes
pwsh .\ms_demo-data.ps1
```

Typical workflow:

1. Open the script and adjust the variables in the **“Variables you will edit”** section
2. Run with `-WhatIf`
3. Run again without `-WhatIf` once the preview looks right

---

## Requirements
- PowerShell 7+ (Windows PowerShell may work, but PowerShell 7 is recommended)
- Run as **Administrator**
- Windows Server 2019+ with roles installed where used:
  - DNS: **DNS Server** role + DNS service running
  - DHCP: **DHCP Server** role
- PowerShell modules:
  - `DnsServer`
  - `DhcpServer`

---

## Input / Output
- **Input (script parameters):** none (the script uses internal configuration variables)
- **Input (configuration variables to edit):**
  - `$UseAdIntegratedZones`  
    - `$true`: AD-integrated zones (requires Domain Controller + DNS)
    - `$false`: file-backed primary zones (`*.dns`) for non-DC DNS servers
  - `$ParentZones` and `$ChildZoneLabels` (forward zones to create)
  - `$RecordTemplates` (records to create in each zone; SRV only in parent zones)
  - `$DhcpV4Scopes` and `$DhcpV6Scopes` (scopes to create)
  - `$DhcpOptionValues` (DNS servers, domain/search, NTP, etc.)
  - Optional delegation controls: `$CreateDelegations`, `$DelegationNameServers`
  - Optional forwarders: `$ForwarderIPs`
- **Output:** changes applied to the local Windows DNS/DHCP server configuration:
  - DNS zones and records
  - Reverse zones and PTRs
  - DHCP scopes, reservations, ranges, and options
  - Console output via `Write-Host` (no separate report file by default)

---

## Notes
- Intended for **lab/demo environments**. Review the default IPs, prefixes, and zone names before running.
- Idempotent behavior: the script attempts to detect existing objects and will skip creating duplicates.
- Dry-run support: because the script uses `SupportsShouldProcess`, `-WhatIf` will simulate most operations.
- Reverse zone logic:
  - IPv4: derives a `/24` reverse zone for each A record IP
  - IPv6: derives a `/64` reverse zone for each AAAA record IP

---

## License
This script is covered under the repository’s main [MIT License](../LICENSE).
