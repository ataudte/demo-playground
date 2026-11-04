<#
.SYNOPSIS
  Seed a Windows Server (2019+) with example DNS + DHCP data (IPv4 + IPv6),
  including reverse zones and PTRs.

.DESIGN
  - Zones:
      - Creates each parent zone in $ParentZones
      - Creates child zones from $ChildZoneLabels under every parent zone
      - Zone backend is controlled by $UseAdIntegratedZones:
          - $true  -> AD-integrated (ReplicationScope = Domain)   (requires DC + DNS)
          - $false -> file-backed primary zones (*.dns files)     (works on non-DC DNS servers)
  - Records:
      - $RecordTemplates are created in every parent zone AND every child zone
      - SRV records are created ONLY in parent zones
  - Reverse DNS:
      - For every created A:    creates corresponding /24 reverse zone + PTR
      - For every created AAAA: creates corresponding /64 reverse zone + PTR
  - DHCP:
      - For each IPv4 scope: 10 reservations at the beginning, then a pool of 20 addresses
      - For each IPv6 scope (/64): 10 reservations, then a range of 20 addresses
      - Applies predefined option values for DNS servers, domain name/search, and NTP

.REQUIREMENTS
  - Run as Administrator
  - Roles installed where used:
      - DNS: DNS Server role + service running
      - DHCP: DHCP Server role
  - Modules available: DnsServer, DhcpServer

.DRY-RUN
  - Run with -WhatIf to preview changes without applying them:
      .\ms_demo-data.ps1 -WhatIf

.NOTES
  - Safe to re-run: checks for existing zones/records/scopes/reservations before creating them.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module DnsServer -ErrorAction Stop
Import-Module DhcpServer -ErrorAction Stop

# -----------------------------
# Execution mode
# -----------------------------
# $true  = DNS server is a Domain Controller -> AD-integrated zones
# $false = DNS server is NOT a DC           -> file-backed primary zones
$UseAdIntegratedZones = $false

# -----------------------------
# Variables you will edit
# -----------------------------

$ParentZones = @(
  "company.corp",
  "company.lan"
)

$ChildZoneLabels = @(
  "dev",
  "prod",
  "mgmt"
)

$ForwarderIPs = @(
  "99.77.55.33",
  "88.66.44.22"
)

# Optional: create delegation NS records in parent zones for the child zones
$CreateDelegations = $false
$DelegationNameServers = @("ns1.company.corp.", "ns2.company.corp.")

# Enterprise-ish record templates:
# - Name: relative owner name within zone ("@" for zone apex)
# - Type: A|AAAA|CNAME|MX|TXT|SRV
# - Data: type specific payload
#
# Data conventions:
# A/AAAA:  Data = @("ip1","ip2") or single string
# CNAME:   Data = "target" (relative) or "target.fqdn." (absolute)
# MX:      Data = @(@{Preference=10; Exchange="mx1"}, @{Preference=20; Exchange="mx2.fqdn."})
# TXT:     Data = @("v=spf1 ...", "some other text")
# SRV:     Data = @(@{Priority=0; Weight=100; Port=389; Target="dc1"}, ...)
#
# Notes:
# - For relative targets/exchanges, the script auto-appends the current zone.
# - SRV records are created ONLY in parent zones.
$RecordTemplates = @(
  [pscustomobject]@{ Name="@";     Type="MX";   Data=@(@{Preference=10; Exchange="mx1"}, @{Preference=20; Exchange="mx2"}) },
  [pscustomobject]@{ Name="mx1";   Type="A";    Data=@("10.10.10.25","10.10.10.26") },
  [pscustomobject]@{ Name="mx2";   Type="A";    Data="10.10.10.27" },
  [pscustomobject]@{ Name="mail";  Type="CNAME";Data="mx1" },

  [pscustomobject]@{ Name="www";   Type="A";    Data=@("10.10.10.20","10.10.10.21") },
  [pscustomobject]@{ Name="www";   Type="AAAA"; Data=@("2001:db8:10:10::20","2001:db8:10:10::21") },
  [pscustomobject]@{ Name="api";   Type="CNAME";Data="www" },

  [pscustomobject]@{ Name="dc1";   Type="A";    Data="10.10.10.10" },
  [pscustomobject]@{ Name="dc2";   Type="A";    Data="10.10.10.11" },

  # SRV (ONLY in parent zones)
  [pscustomobject]@{ Name="_ldap._tcp";         Type="SRV"; Data=@(@{Priority=0;Weight=100;Port=389;Target="dc1"}, @{Priority=0;Weight=100;Port=389;Target="dc2"}) },
  [pscustomobject]@{ Name="_kerberos._tcp";     Type="SRV"; Data=@(@{Priority=0;Weight=100;Port=88; Target="dc1"}, @{Priority=0;Weight=100;Port=88; Target="dc2"}) },
  [pscustomobject]@{ Name="_kerberos._udp";     Type="SRV"; Data=@(@{Priority=0;Weight=100;Port=88; Target="dc1"}, @{Priority=0;Weight=100;Port=88; Target="dc2"}) },
  [pscustomobject]@{ Name="_kpasswd._tcp";      Type="SRV"; Data=@(@{Priority=0;Weight=100;Port=464;Target="dc1"}, @{Priority=0;Weight=100;Port=464;Target="dc2"}) },
  [pscustomobject]@{ Name="_kpasswd._udp";      Type="SRV"; Data=@(@{Priority=0;Weight=100;Port=464;Target="dc1"}, @{Priority=0;Weight=100;Port=464;Target="dc2"}) },

  [pscustomobject]@{ Name="@";     Type="TXT";  Data=@("v=spf1 ip4:10.10.10.0/24 ip6:2001:db8:10:10::/64 -all") },
  [pscustomobject]@{ Name="_dmarc";Type="TXT";  Data=@("v=DMARC1; p=quarantine; rua=mailto:dmarc@company.corp") },
  [pscustomobject]@{ Name="selector1._domainkey"; Type="TXT"; Data=@("v=DKIM1; k=rsa; p=MIIBIjANBgkqh...examplestub") },

  [pscustomobject]@{ Name="ntp";   Type="A";    Data="10.10.10.123" },
  [pscustomobject]@{ Name="sip";   Type="A";    Data="10.10.10.80" },
  [pscustomobject]@{ Name="_sip._tcp";          Type="SRV"; Data=@(@{Priority=10;Weight=50;Port=5060;Target="sip"}) },
  [pscustomobject]@{ Name="_sip._tls";          Type="SRV"; Data=@(@{Priority=10;Weight=50;Port=5061;Target="sip"}) }
)

# DHCP IPv4 scopes
$DhcpV4Scopes = @(
  [pscustomobject]@{ NetworkId = "10.50.1.0"; PrefixLength = 24; Name = "Example v4 Scope A" },
  [pscustomobject]@{ NetworkId = "10.50.2.0"; PrefixLength = 24; Name = "Example v4 Scope B" }
)

# DHCP IPv6 scopes
$DhcpV6Scopes = @(
  [pscustomobject]@{ Prefix = "2001:db8:50:1::"; Name = "Example v6 Scope A" },
  [pscustomobject]@{ Prefix = "2001:db8:50:2::"; Name = "Example v6 Scope B" }
)


$DhcpOptionValues = @{
  DnsServersV4 = @("9.9.9.9", "1.1.1.1")
  DomainName   = "company.corp"
  NtpServersV4 = @("10.10.10.123")
  DnsServersV6 = @("2620:fe::fe", "2606:4700:4700::1111")
  NtpServersV6 = @("2001:db8:10:10::123")
  DomainSearch = @("company.corp", "company.lan")
}

$DhcpV4ExtraOptions = @()
$DhcpV6ExtraOptions = @()

# -----------------------------
# Helpers
# -----------------------------

function Convert-IPv4ToUInt32([string]$Ip) {
  $bytes = ([System.Net.IPAddress]::Parse($Ip)).GetAddressBytes()
  [Array]::Reverse($bytes)
  return [BitConverter]::ToUInt32($bytes, 0)
}

function Convert-UInt32ToIPv4([uint32]$Value) {
  $bytes = [BitConverter]::GetBytes($Value)
  [Array]::Reverse($bytes)
  return ([System.Net.IPAddress]::new($bytes)).ToString()
}

function Get-SubnetMaskFromPrefix([int]$PrefixLength) {
  if ($PrefixLength -lt 0 -or $PrefixLength -gt 32) { throw "Invalid IPv4 prefix length: $PrefixLength" }
  $mask = [uint32]0
  if ($PrefixLength -gt 0) { $mask = [uint32]::MaxValue -shl (32 - $PrefixLength) }
  return (Convert-UInt32ToIPv4 $mask)
}

function Normalize-Fqdn([string]$Name, [string]$ZoneName) {
  if ([string]::IsNullOrWhiteSpace($Name)) { throw "Empty name" }
  if ($Name -eq "@") { return ($ZoneName.TrimEnd('.') + ".") }
  if ($Name -match "\.") { return ($Name.TrimEnd('.') + ".") }
  return ("$Name.$ZoneName".TrimEnd('.') + ".")
}

function Get-IPv6ReverseZoneFromAddress64([string]$IPv6) {
  $ip = [System.Net.IPAddress]::Parse($IPv6)
  $bytes = $ip.GetAddressBytes()
  $prefixBytes = $bytes[0..7] # /64
  $hex = ($prefixBytes | ForEach-Object { $_.ToString("x2") }) -join ""
  $n = $hex.ToCharArray()
  [Array]::Reverse($n)
  return (($n -join ".") + ".ip6.arpa")
}

# -----------------------------
# DNS: Zones + Reverse Zones (AD-integrated vs file-backed via $UseAdIntegratedZones)
# -----------------------------

function Ensure-DnsPrimaryZone([string]$ZoneName) {
  $dnsSvc = Get-Service DNS -ErrorAction SilentlyContinue
  if (-not $dnsSvc) {
    throw "DNS Server service not found. Install the DNS Server role."
  }
  if ($dnsSvc.Status -ne "Running") {
    if ($PSCmdlet.ShouldProcess("DNS service", "Start-Service DNS")) {
      Write-Host "Starting DNS Server service..."
      Start-Service DNS
    }
  }

  if (Get-DnsServerZone -Name $ZoneName -ErrorAction SilentlyContinue) {
    Write-Host "DNS zone exists: $ZoneName"
    return
  }

  if ($UseAdIntegratedZones) {
    if ($PSCmdlet.ShouldProcess($ZoneName, "Create AD-integrated forward zone")) {
      Write-Host "Creating AD-integrated DNS zone: $ZoneName"
      Add-DnsServerPrimaryZone `
        -Name $ZoneName `
        -ReplicationScope Domain | Out-Null
    }
  } else {
    $zoneFile = ($ZoneName -replace '\.', '_') + ".dns"
    if ($PSCmdlet.ShouldProcess($ZoneName, "Create file-backed forward zone ($zoneFile)")) {
      Write-Host "Creating file-backed DNS zone: $ZoneName ($zoneFile)"
      Add-DnsServerPrimaryZone `
        -Name $ZoneName `
        -ZoneFile $zoneFile `
        -DynamicUpdate NonsecureAndSecure | Out-Null
    }
  }
}

function Ensure-IPv4ReverseZone([string]$IPv4) {
  $o = $IPv4.Split('.')
  if ($o.Count -ne 4) { throw "Invalid IPv4 address: $IPv4" }

  $zoneName = "$($o[2]).$($o[1]).$($o[0]).in-addr.arpa"
  if (Get-DnsServerZone -Name $zoneName -ErrorAction SilentlyContinue) {
    Write-Host "IPv4 reverse zone exists: $zoneName"
    return $zoneName
  }

  $networkId = "$($o[0]).$($o[1]).$($o[2]).0/24"

  if ($UseAdIntegratedZones) {
    if ($PSCmdlet.ShouldProcess($zoneName, "Create AD-integrated IPv4 reverse zone")) {
      Write-Host "Creating AD-integrated IPv4 reverse zone: $zoneName"
      Add-DnsServerPrimaryZone `
        -NetworkId $networkId `
        -ReplicationScope Domain | Out-Null
    }
  } else {
    $zoneFile = ($zoneName -replace '\.', '_') + ".dns"
    if ($PSCmdlet.ShouldProcess($zoneName, "Create file-backed IPv4 reverse zone ($zoneFile)")) {
      Write-Host "Creating file-backed IPv4 reverse zone: $zoneName ($zoneFile)"
      Add-DnsServerPrimaryZone `
        -NetworkId $networkId `
        -ZoneFile $zoneFile `
        -DynamicUpdate NonsecureAndSecure | Out-Null
    }
  }

  return $zoneName
}

function Ensure-IPv6ReverseZone64([string]$IPv6) {
  $zoneName = Get-IPv6ReverseZoneFromAddress64 $IPv6
  if (Get-DnsServerZone -Name $zoneName -ErrorAction SilentlyContinue) {
    Write-Host "IPv6 reverse zone exists: $zoneName"
    return $zoneName
  }

  $ip = [System.Net.IPAddress]::Parse($IPv6)
  $bytes = $ip.GetAddressBytes()
  #$bytes[8..15] = 0
  for ($i = 8; $i -lt 16; $i++) { $bytes[$i] = 0 }
  $prefix = ([System.Net.IPAddress]::new($bytes)).ToString() + "/64"

  if ($UseAdIntegratedZones) {
    if ($PSCmdlet.ShouldProcess($zoneName, "Create AD-integrated IPv6 reverse zone")) {
      Write-Host "Creating AD-integrated IPv6 reverse zone: $zoneName"
      Add-DnsServerPrimaryZone `
        -NetworkId $prefix `
        -ReplicationScope Domain | Out-Null
    }
  } else {
    $zoneFile = ($zoneName -replace '\.', '_') + ".dns"
    if ($PSCmdlet.ShouldProcess($zoneName, "Create file-backed IPv6 reverse zone ($zoneFile)")) {
      Write-Host "Creating file-backed IPv6 reverse zone: $zoneName ($zoneFile)"
      Add-DnsServerPrimaryZone `
        -NetworkId $prefix `
        -ZoneFile $zoneFile `
        -DynamicUpdate NonsecureAndSecure | Out-Null
    }
  }

  return $zoneName
}


# -----------------------------
# DNS: Records
# -----------------------------

function Ensure-AorAAAA([string]$ZoneName, [string]$Name, [ValidateSet("A","AAAA")] [string]$Type, [string]$Ip) {
  $rrs = Get-DnsServerResourceRecord -ZoneName $ZoneName -Name $Name -ErrorAction SilentlyContinue
  if ($rrs) {
    foreach ($rr in $rrs) {
      if ($rr.RecordType -ne $Type) { continue }
      if ($Type -eq "A" -and $rr.RecordData.IPv4Address.IPAddressToString -eq $Ip)   { return $false }
      if ($Type -eq "AAAA" -and $rr.RecordData.IPv6Address.IPAddressToString -eq $Ip){ return $false }
    }
  }

  if ($PSCmdlet.ShouldProcess("$Name.$ZoneName", "Create $Type record -> $Ip")) {
    Write-Host "Creating record: $Name $Type $Ip in $ZoneName"
    if ($Type -eq "A") {
      Add-DnsServerResourceRecordA -ZoneName $ZoneName -Name $Name -IPv4Address $Ip | Out-Null
    } else {
      Add-DnsServerResourceRecordAAAA -ZoneName $ZoneName -Name $Name -IPv6Address $Ip | Out-Null
    }
    return $true
  }

  return $false
}

function Ensure-CNAME([string]$ZoneName, [string]$Name, [string]$Target) {
  $targetFqdn = Normalize-Fqdn $Target $ZoneName
  $rrs = Get-DnsServerResourceRecord -ZoneName $ZoneName -Name $Name -RRType "CNAME" -ErrorAction SilentlyContinue
  if ($rrs) {
    foreach ($rr in $rrs) {
      if ($rr.RecordData.HostNameAlias.TrimEnd('.') -eq $targetFqdn.TrimEnd('.')) { return }
    }
  }

  if ($PSCmdlet.ShouldProcess("$Name.$ZoneName", "Create CNAME -> $targetFqdn")) {
    Write-Host "Creating record: $Name CNAME $targetFqdn in $ZoneName"
    Add-DnsServerResourceRecordCName -ZoneName $ZoneName -Name $Name -HostNameAlias $targetFqdn | Out-Null
  }
}

function Ensure-TXT([string]$ZoneName, [string]$Name, [string]$Text) {
  $rrs = Get-DnsServerResourceRecord -ZoneName $ZoneName -Name $Name -RRType "TXT" -ErrorAction SilentlyContinue
  if ($rrs) {
    foreach ($rr in $rrs) {
      if (($rr.RecordData.DescriptiveText -join "") -eq $Text) { return }
    }
  }

  if ($PSCmdlet.ShouldProcess("$Name.$ZoneName", "Create TXT -> $Text")) {
    Write-Host "Creating record: $Name TXT `"$Text`" in $ZoneName"
    Add-DnsServerResourceRecord -ZoneName $ZoneName -Name $Name -Txt -DescriptiveText $Text | Out-Null
  }
}

function Ensure-MX([string]$ZoneName, [string]$Name, [int]$Preference, [string]$Exchange) {
  $exchangeFqdn = Normalize-Fqdn $Exchange $ZoneName
  $rrs = Get-DnsServerResourceRecord -ZoneName $ZoneName -Name $Name -RRType "MX" -ErrorAction SilentlyContinue
  if ($rrs) {
    foreach ($rr in $rrs) {
      if ($rr.RecordData.MailExchange.TrimEnd('.') -eq $exchangeFqdn.TrimEnd('.') -and $rr.RecordData.Preference -eq $Preference) { return }
    }
  }

  if ($PSCmdlet.ShouldProcess("$Name.$ZoneName", "Create MX $Preference -> $exchangeFqdn")) {
    Write-Host "Creating record: $Name MX $Preference $exchangeFqdn in $ZoneName"
    Add-DnsServerResourceRecordMX -ZoneName $ZoneName -Name $Name -Preference $Preference -MailExchange $exchangeFqdn | Out-Null
  }
}

function Ensure-SRV([string]$ZoneName, [string]$Name, [int]$Priority, [int]$Weight, [int]$Port, [string]$Target) {
  $targetFqdn = Normalize-Fqdn $Target $ZoneName

  $rrs = Get-DnsServerResourceRecord -ZoneName $ZoneName -Name $Name -RRType "SRV" -ErrorAction SilentlyContinue
  if ($rrs) {
    foreach ($rr in $rrs) {
      $d = $rr.RecordData
      if (
        $d.DomainName.TrimEnd('.') -eq $targetFqdn.TrimEnd('.') -and
        $d.Priority -eq $Priority -and
        $d.Weight   -eq $Weight   -and
        $d.Port     -eq $Port
      ) {
        return
      }
    }
  }

  if ($PSCmdlet.ShouldProcess("$Name.$ZoneName", "Create SRV $Priority $Weight $Port -> $targetFqdn")) {
    Write-Host "Creating record: $Name SRV $Priority $Weight $Port $targetFqdn in $ZoneName"

    Add-DnsServerResourceRecord `
      -ZoneName   $ZoneName `
      -Name       $Name `
      -Srv `
      -Priority   $Priority `
      -Weight     $Weight `
      -Port       $Port `
      -DomainName $targetFqdn | Out-Null
  }
}

function Ensure-PTRv4([string]$Fqdn, [string]$IPv4) {
  $revZone = Ensure-IPv4ReverseZone $IPv4
  $o = $IPv4.Split('.')
  $ptrName = $o[3]

  $target = (Normalize-Fqdn $Fqdn $revZone).TrimEnd('.')

  $existing = Get-DnsServerResourceRecord -ZoneName $revZone -Name $ptrName -RRType "PTR" -ErrorAction SilentlyContinue
  if ($existing) {
    foreach ($rr in @($existing)) {
      if ($rr.RecordData.PtrDomainName.TrimEnd('.') -eq $target) {
        return
      }
    }
  }

  if ($PSCmdlet.ShouldProcess("$ptrName.$revZone", "Create PTR -> $target")) {
    Write-Host "Creating PTR: $ptrName.$revZone -> $target."
    Add-DnsServerResourceRecordPtr -ZoneName $revZone -Name $ptrName -PtrDomainName ($target + ".") | Out-Null
  }
}

function Ensure-PTRv6([string]$Fqdn, [string]$IPv6) {
  $revZone = Ensure-IPv6ReverseZone64 $IPv6

  $ip = [System.Net.IPAddress]::Parse($IPv6)
  $bytes = $ip.GetAddressBytes()
  $iidBytes = $bytes[8..15]
  $iidHex = ($iidBytes | ForEach-Object { $_.ToString("x2") }) -join ""
  $n = $iidHex.ToCharArray()
  [Array]::Reverse($n)
  $ptrName = ($n -join ".")

  $target = (Normalize-Fqdn $Fqdn $revZone).TrimEnd('.')

  $existing = Get-DnsServerResourceRecord -ZoneName $revZone -Name $ptrName -RRType "PTR" -ErrorAction SilentlyContinue
  if ($existing) {
    foreach ($rr in @($existing)) {
      if ($rr.RecordData.PtrDomainName.TrimEnd('.') -eq $target) {
        return
      }
    }
  }

  if ($PSCmdlet.ShouldProcess("$ptrName.$revZone", "Create PTR -> $target")) {
    Write-Host "Creating PTR: $ptrName.$revZone -> $target."
    Add-DnsServerResourceRecordPtr -ZoneName $revZone -Name $ptrName -PtrDomainName ($target + ".") | Out-Null
  }
}


# -----------------------------
# DHCP: Scopes + Reservations + Options
# -----------------------------

function Ensure-DhcpV4ScopeAndData([pscustomobject]$ScopeDef) {
  $networkId = [string](@($ScopeDef.NetworkId)[0]).Trim()
  $prefix = [int](@($ScopeDef.PrefixLength)[0])
  $mask  = Get-SubnetMaskFromPrefix $prefix
  $name  = [string](@($ScopeDef.Name)[0]).Trim()

  # reservations: +10..+19 (10)
  # pool:         +20..+39 (20)
  $base  = Convert-IPv4ToUInt32 $networkId
  $start = Convert-UInt32ToIPv4 ([uint32]($base + 10))
  $end   = Convert-UInt32ToIPv4 ([uint32]($base + 39))

  # Find existing scope by ScopeId (network)
  # Fix: Ensure comparison is done against string value to avoid type mismatch
  $scope = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Where-Object { $_.ScopeId.IPAddressToString -eq $networkId }

  if (-not $scope) {
    if ($PSCmdlet.ShouldProcess($networkId, "Create DHCPv4 scope ($start - $end / $mask)")) {
      Write-Host "Creating DHCPv4 scope: $networkId ($start - $end / $mask)"
      Add-DhcpServerv4Scope `
        -Name $name `
        -StartRange $start `
        -EndRange $end `
        -SubnetMask $mask | Out-Null
    }

    # Re-read created scope
    $scope = Get-DhcpServerv4Scope -ErrorAction Stop | Where-Object { $_.StartRange.IPAddressToString -eq $start -and $_.SubnetMask -eq $mask }
    if (-not $scope) {
      throw "Created scope not found after Add-DhcpServerv4Scope. Expected StartRange=$start SubnetMask=$mask"
    }
  } else {
    Write-Host "DHCPv4 scope exists: $networkId"
  }

  $scopeId = [string](@($scope.ScopeId.IPAddressToString)[0]).Trim()

  # Reservations
  for ($i = 0; $i -lt 10; $i++) {
    $ip = Convert-UInt32ToIPv4 ([uint32]($base + 10 + $i))
    $mac = ("02-00-5E-00-00-{0:X2}" -f (10 + $i))
    $clientName = ("resv{0:00}" -f ($i + 1))

    $resExists = Get-DhcpServerv4Reservation -ScopeId $scopeId -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress.IPAddressToString -eq $ip }
    if (-not $resExists) {
      if ($PSCmdlet.ShouldProcess("$scopeId/$ip", "Create DHCPv4 reservation $ip -> $mac ($clientName)")) {
        Write-Host "Creating DHCPv4 reservation: $ip -> $mac ($clientName)"
        Add-DhcpServerv4Reservation -ScopeId $scopeId -IPAddress $ip -ClientId $mac -Description $clientName -Name $clientName | Out-Null
      }
    }
  }

  # Options (skip validation failures; continue)
  if ($PSCmdlet.ShouldProcess($scopeId, "Set DHCPv4 scope options (DNS, Domain, NTP)")) {
    Write-Host "Setting DHCPv4 options on scope $scopeId"

    try {
      Set-DhcpServerv4OptionValue -ScopeId $scopeId -DnsServer $DhcpOptionValues.DnsServersV4 -DnsDomain $DhcpOptionValues.DomainName | Out-Null
    } catch {
      Write-Host "Skipping DHCPv4 DNS options on scope $scopeId (server rejected DNS IPs: $($DhcpOptionValues.DnsServersV4 -join ', ')). Error: $($_.Exception.Message)"
    }

    try {
      Set-DhcpServerv4OptionValue -ScopeId $scopeId -OptionId 42 -Value $DhcpOptionValues.NtpServersV4 | Out-Null
    } catch {
      Write-Host "Skipping DHCPv4 NTP option (42) on scope $scopeId. Error: $($_.Exception.Message)"
    }

    foreach ($opt in $DhcpV4ExtraOptions) {
      try {
        $optId = [int](@($opt.OptionId)[0])
        Set-DhcpServerv4OptionValue -ScopeId $scopeId -OptionId $optId -Value $opt.Value | Out-Null
      } catch {
        Write-Host "Skipping DHCPv4 optionId $($opt.OptionId) on scope $scopeId. Error: $($_.Exception.Message)"
      }
    }
  }
}

function Ensure-DhcpV6ScopeAndData([pscustomobject]$ScopeDef) {
  $prefixAddr = [string](@($ScopeDef.Prefix)[0]).Trim()
  $name       = [string](@($ScopeDef.Name)[0]).Trim()

  if (-not (Get-DhcpServerv6Scope -Prefix $prefixAddr -ErrorAction SilentlyContinue)) {
    if ($PSCmdlet.ShouldProcess($prefixAddr, "Create DHCPv6 scope")) {
      Write-Host "Creating DHCPv6 scope: $prefixAddr"
      Add-DhcpServerv6Scope -Name $name -Prefix $prefixAddr | Out-Null
    }
  } else {
    Write-Host "DHCPv6 scope exists: $prefixAddr"
  }

  # Exclude first 10 IPv6 addresses in the /64: ::1 .. ::a
  $exclStart = ("$prefixAddr" -replace "::$", "::") + "1"
  $exclEnd   = ("$prefixAddr" -replace "::$", "::") + "a"

  $existingExcl = Get-DhcpServerv6ExclusionRange -Prefix $prefixAddr -ErrorAction SilentlyContinue
  $exclExists = $false
  foreach ($e in @($existingExcl)) {
    if ($e.StartRange -eq $exclStart -and $e.EndRange -eq $exclEnd) { $exclExists = $true }
  }

  if (-not $exclExists) {
    if ($PSCmdlet.ShouldProcess($prefixAddr, "Add DHCPv6 exclusion $exclStart - $exclEnd")) {
      Write-Host "Adding DHCPv6 exclusion: $exclStart - $exclEnd"
      Add-DhcpServerv6ExclusionRange -Prefix $prefixAddr -StartRange $exclStart -EndRange $exclEnd | Out-Null
    }
  } else {
    Write-Host "DHCPv6 exclusion exists: $exclStart - $exclEnd"
  }

  # Reservations: start from 11th address: ::b .. ::14 (10 reservations)
  for ($i = 0; $i -lt 10; $i++) {
    $hostHex = "{0:x}" -f (11 + $i)     # b, c, d, e, f, 10, 11, 12, 13, 14
    $ip = ("$prefixAddr" -replace "::$", "::") + $hostHex

    $duid = ("00-01-00-01-23-45-67-89-02-00-5E-00-00-{0:X2}" -f (11 + $i))
    $iaid = 1100 + $i
    $nameRes = ("v6resv{0:00}" -f ($i + 1))

    $exists = Get-DhcpServerv6Reservation -Prefix $prefixAddr -ErrorAction SilentlyContinue |
      Where-Object { $_.IPAddress.IPAddressToString -eq $ip }

    if (-not $exists) {
      if ($PSCmdlet.ShouldProcess("$prefixAddr/$ip", "Create DHCPv6 reservation $ip (DUID $duid, IAID $iaid)")) {
        Write-Host "Creating DHCPv6 reservation: $ip -> DUID $duid IAID $iaid ($nameRes)"
        Add-DhcpServerv6Reservation -Prefix $prefixAddr -IPAddress $ip -ClientDuid $duid -Iaid $iaid -Description $nameRes -Name $nameRes | Out-Null
      }
    }
  }

  # Options (skip validation failures; continue)
  if ($PSCmdlet.ShouldProcess($prefixAddr, "Set DHCPv6 scope options (DNS, Search List, NTP)")) {
    Write-Host "Setting DHCPv6 options on scope $prefixAddr"

    try {
      Set-DhcpServerv6OptionValue -Prefix $prefixAddr -OptionId 23 -Value $DhcpOptionValues.DnsServersV6 | Out-Null
    } catch {
      Write-Host "Skipping DHCPv6 DNS option (23) on $prefixAddr. Error: $($_.Exception.Message)"
    }

    try {
      Set-DhcpServerv6OptionValue -Prefix $prefixAddr -OptionId 24 -Value $DhcpOptionValues.DomainSearch | Out-Null
    } catch {
      Write-Host "Skipping DHCPv6 Domain Search option (24) on $prefixAddr. Error: $($_.Exception.Message)"
    }

    try {
      Set-DhcpServerv6OptionValue -Prefix $prefixAddr -OptionId 31 -Value $DhcpOptionValues.NtpServersV6 | Out-Null
    } catch {
      Write-Host "Skipping DHCPv6 NTP option (31) on $prefixAddr. Error: $($_.Exception.Message)"
    }

    foreach ($opt in $DhcpV6ExtraOptions) {
      try {
        $optId = [int](@($opt.OptionId)[0])
        Set-DhcpServerv6OptionValue -Prefix $prefixAddr -OptionId $optId -Value $opt.Value | Out-Null
      } catch {
        Write-Host "Skipping DHCPv6 optionId $($opt.OptionId) on $prefixAddr. Error: $($_.Exception.Message)"
      }
    }
  }
}

# -----------------------------
# Main
# -----------------------------

$AllZones      = New-Object System.Collections.Generic.List[string]
$ParentZoneSet = New-Object System.Collections.Generic.HashSet[string]
$HostRecordsForPtr = New-Object System.Collections.Generic.List[object]

# Create zones
foreach ($pz in $ParentZones) {

  # Create local conditional forwarder: affiliate.<parent>
  $cfZone = "affiliate.$pz"
  if (-not (Get-DnsServerZone -Name $cfZone -ErrorAction SilentlyContinue)) {
    if ($PSCmdlet.ShouldProcess($cfZone, "Create local conditional forwarder -> $($ForwarderIPs -join ', ')")) {
      Write-Host "Creating local conditional forwarder zone: $cfZone -> $($ForwarderIPs -join ', ')"
      Add-DnsServerConditionalForwarderZone -Name $cfZone -MasterServers $ForwarderIPs -ErrorAction Stop
    }
  }

  Ensure-DnsPrimaryZone $pz
  [void]$AllZones.Add($pz)
  [void]$ParentZoneSet.Add($pz)

  foreach ($label in $ChildZoneLabels) {
    $cz = "$label.$pz"
    Ensure-DnsPrimaryZone $cz
    [void]$AllZones.Add($cz)

    if ($CreateDelegations) {
      foreach ($ns in $DelegationNameServers) {
        $existing = Get-DnsServerResourceRecord -ZoneName $pz -Name $label -RRType "NS" -ErrorAction SilentlyContinue
        $already = $false
        foreach ($rr in ($existing | ForEach-Object { $_ })) {
          if ($rr.RecordData.NameServer.TrimEnd('.') -eq $ns.TrimEnd('.')) { $already = $true }
        }

        if (-not $already) {
          if ($PSCmdlet.ShouldProcess("${pz}", "Create delegation NS ${label} -> ${ns}")) {
            Write-Host "Creating delegation NS in ${pz}: ${label} -> ${ns}"
            Add-DnsServerResourceRecordNS -ZoneName $pz -Name $label -NameServer $ns | Out-Null
          }
        }
      }
    }
  }
}

# Create records
foreach ($zone in $AllZones) {
  $isParent = $ParentZoneSet.Contains($zone)

  foreach ($tmpl in $RecordTemplates) {
    $name = $tmpl.Name
    $type = $tmpl.Type.ToUpperInvariant()

    if ($type -eq "SRV" -and -not $isParent) { continue }

    switch ($type) {
      "A" {
        $ips = @()
        if ($tmpl.Data -is [System.Array]) { $ips = $tmpl.Data } else { $ips = @([string]$tmpl.Data) }
        foreach ($ip in $ips) {
          # Ensure-AorAAAA returns $true only if it created the record.
          # We ignore the result and track the record for PTR verification regardless.
          [void](Ensure-AorAAAA $zone $name "A" $ip)
          
          if ($name -eq "@") { $fqdn = $zone } else { $fqdn = "$name.$zone" }
          [void]$HostRecordsForPtr.Add([pscustomobject]@{ Fqdn=$fqdn; Type="A"; Address=$ip })
        }
      }
      "AAAA" {
        $ips = @()
        if ($tmpl.Data -is [System.Array]) { $ips = $tmpl.Data } else { $ips = @([string]$tmpl.Data) }
        foreach ($ip in $ips) {
          [void](Ensure-AorAAAA $zone $name "AAAA" $ip)
          
          if ($name -eq "@") { $fqdn = $zone } else { $fqdn = "$name.$zone" }
          [void]$HostRecordsForPtr.Add([pscustomobject]@{ Fqdn=$fqdn; Type="AAAA"; Address=$ip })
        }
      }
      "CNAME" {
        Ensure-CNAME $zone $name ([string]$tmpl.Data)
      }
      "TXT" {
        $texts = @()
        if ($tmpl.Data -is [System.Array]) { $texts = $tmpl.Data } else { $texts = @([string]$tmpl.Data) }
        foreach ($t in $texts) { Ensure-TXT $zone $name $t }
      }
      "MX" {
        foreach ($mx in $tmpl.Data) {
          Ensure-MX $zone $name ([int]$mx.Preference) ([string]$mx.Exchange)
        }
      }
      "SRV" {
        foreach ($srv in $tmpl.Data) {
          Ensure-SRV $zone $name ([int]$srv.Priority) ([int]$srv.Weight) ([int]$srv.Port) ([string]$srv.Target)
        }
      }
      default { throw "Unsupported record type: $type" }
    }
  }
}

# Reverse zones + PTRs
foreach ($hr in $HostRecordsForPtr) {
  if ($hr.Type -eq "A")    { Ensure-PTRv4 $hr.Fqdn $hr.Address }
  if ($hr.Type -eq "AAAA") { Ensure-PTRv6 $hr.Fqdn $hr.Address }
}

# DHCP buildout
foreach ($s in $DhcpV4Scopes) { Ensure-DhcpV4ScopeAndData $s }
foreach ($s in $DhcpV6Scopes) { Ensure-DhcpV6ScopeAndData $s }

Write-Host ""
Write-Host "### Done ###"
Write-Host "AD-integrated: $UseAdIntegratedZones"
Write-Host "Forward zones: $($AllZones.Count)"
Write-Host "Host for PTR:  $($HostRecordsForPtr.Count)"
Write-Host "DHCPv4 scopes: $($DhcpV4Scopes.Count)"
Write-Host "DHCPv6 scopes: $($DhcpV6Scopes.Count)"