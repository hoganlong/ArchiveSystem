<#
  fix-my-ip.ps1 — quick check: is this machine's public IP still allowed to reach the
  archive database?

  Residential IPs rotate. When yours changes, the DB security group no longer allows you
  and every connection just times out — which looks exactly like the Aurora cluster being
  asleep, except retrying never helps. Run this FIRST when the DB won't connect.

  A port test (Test-NetConnection :5432) cannot tell the two cases apart, because a paused
  cluster drops SYN packets just like a blocked security group does. Comparing the IPs is
  the real test.

  Usage:
    .\fix-my-ip.ps1                      # check current IP against the DB security group
    .\fix-my-ip.ps1 -SecurityGroupId sg-xxxx -Port 5432
#>
param(
  [string]$SecurityGroupId,
  [int]$Port = 5432
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false   # we check aws exit codes ourselves

$myIp = (Invoke-RestMethod -Uri 'https://checkip.amazonaws.com' -TimeoutSec 15).Trim()

# Discover the DB security group from AWS rather than hardcoding it, so this keeps working
# if the cluster is ever rebuilt and the SG id changes.
if (-not $SecurityGroupId) {
  $SecurityGroupId = (aws rds describe-db-clusters --query 'DBClusters[0].VpcSecurityGroups[0].VpcSecurityGroupId' --output text)
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($SecurityGroupId) -or $SecurityGroupId -eq 'None') {
    Write-Host "[FAIL] Could not resolve the DB security group from AWS. Pass -SecurityGroupId." -ForegroundColor Red
    exit 2
  }
}

$allowed = @((aws ec2 describe-security-groups --group-ids $SecurityGroupId `
  --query "SecurityGroups[0].IpPermissions[?FromPort==``$Port``].IpRanges[].CidrIp" `
  --output text) -split '\s+' | Where-Object { $_ })

Write-Host "My public IP        : $myIp" -ForegroundColor Cyan
Write-Host "Allowed on $Port    : $($allowed -join ', ')" -ForegroundColor Cyan
Write-Host "Security group      : $SecurityGroupId" -ForegroundColor DarkGray

if ($allowed -contains "$myIp/32") {
  Write-Host "[OK] Your IP is authorized. If the DB still won't connect it is just asleep --" -ForegroundColor Green
  Write-Host "     retry, or run wake-db.ps1 to resume it with a real query." -ForegroundColor Green
} else {
  Write-Host "[PROBLEM] Your IP is NOT authorized -- retrying will never work. Fix it with:" -ForegroundColor Red
  Write-Host "  $PSScriptRoot\authorize-my-ip.ps1 -ReplaceOthers" -ForegroundColor Yellow
}
