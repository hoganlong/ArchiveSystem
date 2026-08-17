param(
    [int]$StartStep = 1,
    [int]$StopStep = 7,
    [string]$Root = "D:\Projects\KLA"
)

$ErrorActionPreference = "Stop"
# Workspace root that holds the project subfolders. Defaults to the standard
# path so this script works whether it's run from its tracked home in
# archivesystem/scripts/ or via a symlink at the workspace root. Override with
# -Root if the workspace lives elsewhere.
$root = $Root
$aws = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"

function Run-Step($step, $name, $dir, $cmd) {
    if ($step -lt $StartStep -or $step -gt $StopStep) {
        Write-Host "`n=== $name (skipped) ===" -ForegroundColor DarkGray
        return
    }
    Write-Host "`n=== $name ===" -ForegroundColor Cyan
    Set-Location (Join-Path $root $dir)
    Invoke-Expression $cmd
    if ($LASTEXITCODE -ne 0) {
        Write-Host "$name failed. Aborting." -ForegroundColor Red
        exit 1
    }
    Set-Location $root
}

if (1 -ge $StartStep -and 1 -le $StopStep) {
    Write-Host "`n=== 1/7 Airtable Image Downloader ===" -ForegroundColor Cyan
    Set-Location (Join-Path $root "AirtableImageDownloader")
    dotnet run
    $newImages = $LASTEXITCODE
    Set-Location $root
} else {
    Write-Host "`n=== 1/7 Airtable Image Downloader (skipped) ===" -ForegroundColor DarkGray
    if (2 -eq $StartStep) {
      $newImages = 1
    }
    else {
      $newImages = 0
    }
}
if ($newImages -eq 0) {
    Write-Host "`n=== 2/7 Check S3 vs Local (skipped - no new images) ===" -ForegroundColor DarkGray
} else {
    Run-Step 2 "2/7 Check S3 vs Local" "checks3vslocal" "dotnet run --upload"
}

# Wake the auto-pausing Aurora DB before the ETL (step 3) so it
# doesn't hit the cold-start connection timeout. Non-fatal: if it can't confirm the
# DB is up, continue anyway and let the generator's own retry/timeout handle it.
if (3 -ge $StartStep -and 3 -le $StopStep) {
    Write-Host "`n=== Waking database (before Airtable ETL) ===" -ForegroundColor Cyan
    & (Join-Path $root "ArchiveSystem\scripts\wake-db.ps1")
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  (couldn't confirm DB is up; continuing anyway)" -ForegroundColor Yellow
    }
    Set-Location $root
}

Run-Step 3 "3/7 Airtable to Postgres ETL"   "AirtableToPostgres"      "dotnet run"

Run-Step 4 "4/7 tif2jpg (sscan)"            "tif2jpg"                 "dotnet run -- s3://keithlong-art-photos/sscan/ --create --upload"


# Run-Step 5 "5/7 Generate HTML"              "ArtWorkHTML"              "dotnet run -- --dbsketchonly"

Run-Step 5 "5/7 Generate HTML"              "ArtWorkHTML"              "dotnet run"

$deployToAws = $false
if ($StartStep -le 6 -and $StopStep -ge 6) {
    $answer = Read-Host "`nDeploy to AWS? (y/n)"
    $deployToAws = $answer -eq "y"
}

if ($deployToAws) {
    Write-Host "`n=== 6/7 Sync to S3 ===" -ForegroundColor Cyan
    & $aws s3 sync (Join-Path $root "ArtWorkHTML\artwork_html\") s3://archive.keithlong.com/
# to delete in sync use this:  Write-Host "`n=== 6/7 Sync to S3 ===" -ForegroundColor Cyan & $aws s3 sync (Join-Path $root "ArtWorkHTML\artwork_html\") s3://archive.keithlong.com/ --delete
    if ($LASTEXITCODE -ne 0) { Write-Host "S3 sync failed." -ForegroundColor Red; exit 1 }
} else {
    Write-Host "`n=== 6/7 Sync to S3 (skipped) ===" -ForegroundColor DarkGray
}

if ($deployToAws -and $StopStep -ge 7) {
    Write-Host "`n=== 7/7 CloudFront Invalidation ===" -ForegroundColor Cyan
    & $aws cloudfront create-invalidation --distribution-id E1WA80M7F42SVB --paths "/*"
    if ($LASTEXITCODE -ne 0) { Write-Host "CloudFront invalidation failed." -ForegroundColor Red; exit 1 }
} else {
    Write-Host "`n=== 7/7 CloudFront Invalidation (skipped) ===" -ForegroundColor DarkGray
}

Write-Host "`nDone." -ForegroundColor Green
