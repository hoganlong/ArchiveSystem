<#
  wake-db.ps1 — wake the archive's Aurora PostgreSQL, which auto-pauses when idle.

  When the DB has been idle it pauses, and the FIRST real connection then fails/
  times out while it resumes (~30-60s). Run this first to knock on its port until
  it answers, so your next tool/query (RunSql, the site generator, etc.) connects
  cleanly instead of hitting the cold-start timeout.

  It only opens a TCP connection to the DB port — no credentials, no query, nothing
  is read or changed. "Port open" = the instance is up.

  The DB endpoint is NOT stored in this file (kept out of the repo, like the tools'
  gitignored appsettings). It is resolved in this order:
    1. -DbHost parameter
    2. $env:KLA_DB_HOST
    3. discovered from AWS at runtime (the account's Aurora cluster endpoint)

  Usage:
    .\wake-db.ps1
    .\wake-db.ps1 -Attempts 30
    .\wake-db.ps1 -DbHost my-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com
#>
param(
  [string]$DbHost,
  [int]$Port = 5432,
  [int]$Attempts = 20,
  [int]$DelaySeconds = 8
)

if (-not $DbHost) { $DbHost = $env:KLA_DB_HOST }
if (-not $DbHost) {
  Write-Host "Resolving DB endpoint from AWS..." -ForegroundColor DarkGray
  $DbHost = (aws rds describe-db-clusters --query 'DBClusters[0].Endpoint' --output text 2>$null)
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($DbHost) -or $DbHost -eq 'None') {
    Write-Host "[FAIL] Could not resolve the DB endpoint. Pass -DbHost, set `$env:KLA_DB_HOST, or configure the AWS CLI." -ForegroundColor Red
    exit 2
  }
}

Write-Host "Waking Aurora PostgreSQL at ${DbHost}:${Port} (it auto-pauses when idle)..." -ForegroundColor Cyan
for ($i = 1; $i -le $Attempts; $i++) {
  if (Test-NetConnection -ComputerName $DbHost -Port $Port -InformationLevel Quiet -WarningAction SilentlyContinue) {
    Write-Host "[OK] Database is awake - port $Port is open (attempt $i of $Attempts)." -ForegroundColor Green
    exit 0
  }
  Write-Host ("  attempt {0}/{1}: still waking, retrying in {2}s..." -f $i, $Attempts, $DelaySeconds) -ForegroundColor DarkGray
  Start-Sleep -Seconds $DelaySeconds
}
Write-Host "[FAIL] Port $Port did not open after $Attempts attempts. Give it a moment and re-run." -ForegroundColor Red
exit 1
