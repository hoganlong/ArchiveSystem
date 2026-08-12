<#
  authorize-my-ip.ps1 — allow THIS machine's current public IP to reach the archive
  database (Aurora PostgreSQL) by adding it to the DB's security group on port 5432.

  Why: residential IPs rotate. When yours changes, the DB security group no longer
  allows you and every connection just times out (looks like the DB is asleep, but
  retrying never helps). Run this to re-authorize your current IP.

  - The security group is DISCOVERED from AWS (the archive cluster's SG) — not
    hardcoded here, so no infrastructure IDs live in the repo.
  - Default is add-only (safe). Use -ReplaceOthers to also remove any OTHER IPs on
    the port, keeping only your current one.
  - This edits security-group inbound rules only; it does not touch the database.

  Usage:
    .\authorize-my-ip.ps1                 # add current public IP (leave others)
    .\authorize-my-ip.ps1 -ReplaceOthers  # add current IP and remove all others
    .\authorize-my-ip.ps1 -SecurityGroupId sg-xxxx -Port 5432
#>
param(
  [string]$SecurityGroupId,
  [int]$Port = 5432,
  [switch]$ReplaceOthers
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false   # we check aws exit codes ourselves

function Get-PortCidrs($sg, $port) {
  $out = aws ec2 describe-security-groups --group-ids $sg `
    --query "SecurityGroups[0].IpPermissions[?FromPort==``$port``].IpRanges[].CidrIp" --output text
  return @($out -split '\s+' | Where-Object { $_ })
}

# 1. Current public IP
$ip = (Invoke-RestMethod -Uri 'https://checkip.amazonaws.com' -TimeoutSec 15).Trim()
if ($ip -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
  Write-Host "[FAIL] Could not determine a valid public IPv4 (got '$ip')." -ForegroundColor Red; exit 2
}
$cidr = "$ip/32"
Write-Host "Current public IP : $ip" -ForegroundColor Cyan

# 2. Resolve the DB security group (discover from the Aurora cluster unless overridden)
if (-not $SecurityGroupId) {
  $SecurityGroupId = (aws rds describe-db-clusters --query 'DBClusters[0].VpcSecurityGroups[0].VpcSecurityGroupId' --output text)
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($SecurityGroupId) -or $SecurityGroupId -eq 'None') {
    Write-Host "[FAIL] Could not resolve the DB security group from AWS. Pass -SecurityGroupId." -ForegroundColor Red; exit 2
  }
}
Write-Host "DB security group : $SecurityGroupId (port $Port)" -ForegroundColor Cyan

$existing = Get-PortCidrs $SecurityGroupId $Port

# 3. Add current IP if missing
if ($existing -contains $cidr) {
  Write-Host "[OK] $cidr is already authorized." -ForegroundColor Green
} else {
  aws ec2 authorize-security-group-ingress --group-id $SecurityGroupId --protocol tcp --port $Port --cidr $cidr | Out-Null
  if ($LASTEXITCODE -ne 0) { Write-Host "[FAIL] Could not add $cidr." -ForegroundColor Red; exit 1 }
  Write-Host "[OK] Added $cidr." -ForegroundColor Green
}

# 4. Optionally prune other IPs on the port
$others = $existing | Where-Object { $_ -ne $cidr }
if ($others.Count -gt 0) {
  if ($ReplaceOthers) {
    foreach ($o in $others) {
      aws ec2 revoke-security-group-ingress --group-id $SecurityGroupId --protocol tcp --port $Port --cidr $o | Out-Null
      if ($LASTEXITCODE -eq 0) { Write-Host "  removed $o" -ForegroundColor DarkGray }
      else { Write-Host "  (could not remove $o)" -ForegroundColor Yellow }
    }
  } else {
    Write-Host "Other IPs still allowed on port ${Port}: $($others -join ', ')" -ForegroundColor Yellow
    Write-Host "  (re-run with -ReplaceOthers to keep only your current IP)" -ForegroundColor DarkGray
  }
}

Write-Host "Now allowed on port ${Port}: $((Get-PortCidrs $SecurityGroupId $Port) -join ', ')" -ForegroundColor Cyan
