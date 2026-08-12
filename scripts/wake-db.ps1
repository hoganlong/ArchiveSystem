<#
  wake-db.ps1 — wake the archive's auto-pausing Aurora PostgreSQL
  (Serverless v2, scale-to-0 after idle).

  IMPORTANT: a bare TCP port-knock does NOT trigger Aurora's resume — when the
  cluster is paused the port doesn't even answer, and only a real *database*
  connection attempt drives the scale-up. So this delegates to the RunSql tool,
  running a trivial "SELECT 1"; RunSql's OpenWithRetryAsync loop keeps retrying the
  connection until the cluster resumes. Read-only — nothing is changed.

  Usage:
    .\wake-db.ps1
    .\wake-db.ps1 -RunSqlProject D:\path\to\RunSql
#>
param(
  [string]$RunSqlProject
)

# Handle the DB-connection result ourselves; never throw out of this script so
# callers (build-and-deploy) can treat a failed wake as non-fatal.
$ErrorActionPreference = 'Continue'
$PSNativeCommandUseErrorActionPreference = $false

if (-not $RunSqlProject) {
  # RunSql lives at <workspace root>/RunSql; this script is at
  # <workspace root>/ArchiveSystem/scripts, so go up two levels.
  $RunSqlProject = Join-Path $PSScriptRoot '..\..\RunSql'
}

if (-not (Test-Path (Join-Path $RunSqlProject 'RunSql.csproj'))) {
  Write-Host "[FAIL] RunSql project not found (looked in '$RunSqlProject'). Pass -RunSqlProject <path to RunSql>." -ForegroundColor Red
  exit 2
}

Write-Host "Waking Aurora PostgreSQL via a real DB connection (RunSql 'SELECT 1')..." -ForegroundColor Cyan
dotnet run --project $RunSqlProject -- "SELECT 1 AS db_awake"
$code = $LASTEXITCODE

if ($code -eq 0) {
  Write-Host "[OK] Database is awake." -ForegroundColor Green
  exit 0
}
Write-Host "[FAIL] Could not wake the DB (RunSql exit $code). Give it a moment and re-run." -ForegroundColor Red
exit 1
