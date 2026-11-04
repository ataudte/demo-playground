# ms_lab-cleanup.ps1

## Description
Destructive lab cleanup helper for **Windows Server DNS and DHCP**.

It interactively deletes, on the **local server**:
- **DNS:** all zones (AD-integrated, primary, reverse) and conditional forwarder zones
- **DHCP:** all configuration data (IPv4/IPv6 scopes, superscopes, failover relationships, allow/deny filters)

Services stay installed and running; only the configuration objects are removed.

---

## Usage
Run in an **elevated PowerShell session** (Run as Administrator).

```powershell
pwsh .\ms_lab-cleanup.ps1
```

You will be prompted to:
- Confirm the destructive action by typing `DELETE`
- Choose what to delete: DNS, DHCP, or BOTH
- Enter your credentials (validated against local machine or domain) as an additional safety check

---

## Requirements
- Windows Server (or Windows with RSAT/management tools installed) with the PowerShell modules:
  - `DnsServer`
  - `DhcpServer`
- Administrator privileges (elevated PowerShell)

> The script imports required modules and aborts if they are not available.

---

## Input / Output
- **Input:** Interactive choices and credentials via prompts.
- **Output:** No files are created. The script prints progress and warnings to the console.

---

## Notes
- **Do not run on production systems.** This is meant for lab resets.
- On a **Domain Controller**, deleting AD-integrated zones (including `_msdcs.*`) will break AD-related DNS until you recreate/import zones.
- The script targets the **local server** by default (`$env:COMPUTERNAME`).  
  The cleanup functions support a `-ComputerName` parameter internally, but the main flow currently calls them without parameters.

---

## License
This script is covered under the repository’s main [MIT License](../LICENSE).
