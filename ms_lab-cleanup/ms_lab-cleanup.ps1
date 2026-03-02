<#
.SYNOPSIS
  Lab cleanup script: deletes ALL DNS zones (incl. AD-integrated, reverse, conditional forwarders)
  and/or ALL DHCP config data (scopes, superscopes, failover, filters, v4/v6) while keeping services installed/running.

.NOTES
  - Run in an elevated PowerShell session (Administrator).
  - On a Domain Controller, deleting AD-integrated zones (including _msdcs.*) will break AD DNS until you recreate/import.
  - This script targets the *local* server by default.

.TESTED CMDLETS
  Requires Windows Server DNS/DHCP PowerShell modules:
    - DnsServer
    - DhcpServer
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Please run this script in an elevated PowerShell window (Run as Administrator)."
  }
}

function Confirm-DestructiveAction {
  Write-Host ""
  Write-Host "This will DELETE DNS/DHCP CONFIGURATION DATA on this server. Services remain installed."
  Write-Host "Type exactly: DELETE"
  $typed = Read-Host "Confirmation"
  if ($typed -ne "DELETE") { throw "Aborted (confirmation mismatch)." }

  $yn = Read-Host "Are you really sure? (Y/N)"
  if ($yn -notin @("Y","y")) { throw "Aborted by user." }
}

function Ask-WhatToDelete {
  Write-Host ""
  Write-Host "What do you want to delete?"
  Write-Host "  1 = DNS"
  Write-Host "  2 = DHCP"
  Write-Host "  3 = BOTH"
  $choice = Read-Host "Enter 1, 2, or 3"
  if ($choice -notin @("1","2","3")) { throw "Invalid selection." }
  return [int]$choice
}

function Validate-Password {
  # Best-effort credential validation against local machine or domain.
  # If validation fails, script aborts.
  Write-Host ""
  Write-Host "Password check (to reduce accidental deletion)."
  Write-Host "Enter YOUR credentials (user/password) to continue."
  $cred = Get-Credential -Message "Enter your credentials to proceed"

  Add-Type -AssemblyName System.DirectoryServices.AccountManagement | Out-Null
  $cs = Get-CimInstance Win32_ComputerSystem
  $isDomainJoined = [bool]$cs.PartOfDomain
  $domainOrMachine = if ($isDomainJoined) { $cs.Domain } else { $env:COMPUTERNAME }
  $contextType = if ($isDomainJoined) {
    [System.DirectoryServices.AccountManagement.ContextType]::Domain
  } else {
    [System.DirectoryServices.AccountManagement.ContextType]::Machine
  }

  # Parse username into (user, domain) if provided as DOMAIN\User or user@domain
  $user = $cred.UserName
  $pwd  = $cred.GetNetworkCredential().Password

  try {
    $ctx = New-Object System.DirectoryServices.AccountManagement.PrincipalContext($contextType, $domainOrMachine)
    $ok  = $ctx.ValidateCredentials($user, $pwd)
  } catch {
    throw "Credential validation failed (context: $domainOrMachine). Error: $($_.Exception.Message)"
  }

  if (-not $ok) { throw "Credential validation failed. Aborting." }
}

function Ensure-Module {
  param([Parameter(Mandatory)][string]$Name)
  if (-not (Get-Module -ListAvailable -Name $Name)) {
    throw "Required module '$Name' not found. Install the role/management tools or run on the server that has it."
  }
  Import-Module $Name -ErrorAction Stop
}

function Clean-Dns {
  param([string]$ComputerName = $env:COMPUTERNAME)

  Ensure-Module -Name "DnsServer"

  Write-Host ""
  Write-Host "DNS cleanup on $ComputerName ..."
  $zones = Get-DnsServerZone -ComputerName $ComputerName

  if (-not $zones) {
    Write-Host "No DNS zones found."
    return
  }

  foreach ($z in $zones) {
    $name = $z.ZoneName
    $type = $z.ZoneType

    try {
      if ($type -eq "Forwarder") {
        Write-Host "Removing conditional forwarder zone: $name"
        Remove-DnsServerConditionalForwarderZone -ComputerName $ComputerName -Name $name -Force
      } else {
        Write-Host "Removing DNS zone: $name (Type=$type, DSIntegrated=$($z.IsDsIntegrated))"
        Remove-DnsServerZone -ComputerName $ComputerName -Name $name -Force
      }
    } catch {
      Write-Warning "Failed to remove zone '$name': $($_.Exception.Message)"
    }
  }

  Write-Host "DNS cleanup done."
}

function Clean-Dhcp {
  param([string]$ComputerName = $env:COMPUTERNAME)

  Ensure-Module -Name "DhcpServer"

  Write-Host ""
  Write-Host "DHCP cleanup on $ComputerName ..."

  # Remove failover relationships first (scopes can be tied to failover)
  try {
    $fos = Get-DhcpServerv4Failover -ComputerName $ComputerName -ErrorAction SilentlyContinue
    foreach ($fo in $fos) {
      Write-Host "Removing DHCPv4 failover: $($fo.Name)"
      Remove-DhcpServerv4Failover -ComputerName $ComputerName -Name $fo.Name -Force
    }
  } catch {
    Write-Warning "Failover removal had issues: $($_.Exception.Message)"
  }

  # Remove superscopes next
  try {
    $ss = Get-DhcpServerv4Superscope -ComputerName $ComputerName -ErrorAction SilentlyContinue
    foreach ($s in $ss) {
      Write-Host "Removing DHCPv4 superscope: $($s.Name)"
      Remove-DhcpServerv4Superscope -ComputerName $ComputerName -Name $s.Name -Force
    }
  } catch {
    Write-Warning "Superscope removal had issues: $($_.Exception.Message)"
  }

  # Remove IPv4 scopes (takes reservations/leases/policies with it)
  try {
    $scopes4 = Get-DhcpServerv4Scope -ComputerName $ComputerName -ErrorAction SilentlyContinue
    foreach ($s in $scopes4) {
      Write-Host "Removing DHCPv4 scope: $($s.ScopeId)  Name=$($s.Name)"
      Remove-DhcpServerv4Scope -ComputerName $ComputerName -ScopeId $s.ScopeId -Force
    }
  } catch {
    Write-Warning "IPv4 scope removal had issues: $($_.Exception.Message)"
  }

  # Remove IPv6 scopes
  try {
    $scopes6 = Get-DhcpServerv6Scope -ComputerName $ComputerName -ErrorAction SilentlyContinue
    foreach ($s in $scopes6) {
      Write-Host "Removing DHCPv6 scope: $($s.Prefix)  Name=$($s.Name)"
      Remove-DhcpServerv6Scope -ComputerName $ComputerName -Prefix $s.Prefix -Force
    }
  } catch {
    Write-Warning "IPv6 scope removal had issues: $($_.Exception.Message)"
  }

  # Clear server-wide allow/deny filters (not tied to scopes)
  try {
    $deny = Get-DhcpServerv4Filter -ComputerName $ComputerName -List Deny -ErrorAction SilentlyContinue
    foreach ($f in $deny) {
      Write-Host "Removing DHCPv4 DENY filter: $($f.MacAddress)"
      Remove-DhcpServerv4Filter -ComputerName $ComputerName -List Deny -MacAddress $f.MacAddress
    }
    $allow = Get-DhcpServerv4Filter -ComputerName $ComputerName -List Allow -ErrorAction SilentlyContinue
    foreach ($f in $allow) {
      Write-Host "Removing DHCPv4 ALLOW filter: $($f.MacAddress)"
      Remove-DhcpServerv4Filter -ComputerName $ComputerName -List Allow -MacAddress $f.MacAddress
    }
  } catch {
    Write-Warning "Filter cleanup had issues: $($_.Exception.Message)"
  }

  Write-Host "DHCP cleanup done."
}

# ---------------- MAIN ----------------
try {
  Assert-Admin
  Confirm-DestructiveAction
  $what = Ask-WhatToDelete
  Validate-Password

  switch ($what) {
    1 { Clean-Dns }
    2 { Clean-Dhcp }
    3 { Clean-Dns; Clean-Dhcp }
  }

  Write-Host ""
  Write-Host "All requested cleanup operations completed."
} catch {
  Write-Host ""
  Write-Error $_.Exception.Message
  exit 1
}
