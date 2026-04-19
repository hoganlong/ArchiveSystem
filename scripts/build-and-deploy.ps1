param(
    [int]$StartStep = 1,
    [int]$StopStep = 6
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
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
    Write-Host "`n=== 1/6 Airtable Image Downloader ===" -ForegroundColor Cyan
    Set-Location (Join-Path $root "AirtableImageDownloader")
    dotnet run
    $newImages = $LASTEXITCODE
    Set-Location $root
} else {
    Write-Host "`n=== 1/6 Airtable Image Downloader (skipped) ===" -ForegroundColor DarkGray
    $newImages = 0
}
if ($newImages -eq 0) {
    Write-Host "`n=== 2/6 Check S3 vs Local (skipped - no new images) ===" -ForegroundColor DarkGray
} else {
    Run-Step 2 "2/6 Check S3 vs Local" "checks3vslocal" "dotnet run --upload"
}
Run-Step 3 "3/6 Airtable to Postgres ETL"   "AirtableToPostgres"      "dotnet run"
# Run-Step 4 "4/6 Generate HTML"              "ArtWorkHTML"              "dotnet run -- --dbsketchonly"
Run-Step 4 "4/6 Generate HTML"              "ArtWorkHTML"              "dotnet run"

$deployToAws = $false
if ($StartStep -le 5 -and $StopStep -ge 5) {
    $answer = Read-Host "`nDeploy to AWS? (y/n)"
    $deployToAws = $answer -eq "y"
}

if ($deployToAws) {
    Write-Host "`n=== 5/6 Sync to S3 ===" -ForegroundColor Cyan
    & $aws s3 sync (Join-Path $root "ArtWorkHTML\artwork_html\") s3://archive.keithlong.com/
# to delete in sync use this:  Write-Host "`n=== 5/6 Sync to S3 ===" -ForegroundColor Cyan & $aws s3 sync (Join-Path $root "ArtWorkHTML\artwork_html\") s3://archive.keithlong.com/ --delete
    if ($LASTEXITCODE -ne 0) { Write-Host "S3 sync failed." -ForegroundColor Red; exit 1 }
} else {
    Write-Host "`n=== 5/6 Sync to S3 (skipped) ===" -ForegroundColor DarkGray
}

if ($deployToAws -and $StopStep -ge 6) {
    Write-Host "`n=== 6/6 CloudFront Invalidation ===" -ForegroundColor Cyan
    & $aws cloudfront create-invalidation --distribution-id E1WA80M7F42SVB --paths "/*"
    if ($LASTEXITCODE -ne 0) { Write-Host "CloudFront invalidation failed." -ForegroundColor Red; exit 1 }
} else {
    Write-Host "`n=== 6/6 CloudFront Invalidation (skipped) ===" -ForegroundColor DarkGray
}

Write-Host "`nDone." -ForegroundColor Green
