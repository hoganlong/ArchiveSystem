<#
  send-website-stats.ps1 — generate the daily CloudFront usage report and email
  it via Amazon SES from admin@archive.keithlong.com. Invoked by the
  "KLA-Website-Stats-Daily" scheduled task (6 AM local).
  Manual run also fine:  .\send-website-stats.ps1

  Requires: AWS CLI configured; cloudfront-usage.ps1 alongside this file;
  the archive.keithlong.com SES identity verified (DKIM) and the recipient
  verified (SES sandbox).
#>
$ErrorActionPreference = 'Stop'

$From   = 'admin@archive.keithlong.com'
$To     = 'hoganlong@gmail.com'
$Region = 'us-east-1'
$Log    = Join-Path $env:TEMP 'kla-website-stats.log'

function Log($m) { ("[{0}] {1}" -f (Get-Date -Format 'u'), $m) | Add-Content -Path $Log -Encoding UTF8 }

try {
    $script = Join-Path $PSScriptRoot 'cloudfront-usage.ps1'
    if (-not (Test-Path $script)) { throw "cloudfront-usage.ps1 not found next to this script ($script)" }

    $report = & $script -Days 7 | Out-String
    if ([string]::IsNullOrWhiteSpace($report)) { $report = 'cloudfront-usage.ps1 produced no output.' }

    $stamp   = (Get-Date).ToString('yyyy-MM-dd')
    $subject = "KLA website stats - $stamp"

    $enc  = $report -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'
    $html = "<!doctype html><html><body style=""background:#0f1115;color:#e6e6e6;margin:16px;"">" +
            "<h2 style=""font-family:Segoe UI,Arial,sans-serif;color:#8ab4f8;"">Keith Long Archive - website stats ($stamp)</h2>" +
            "<pre style=""font-family:Consolas,'Courier New',monospace;font-size:14px;line-height:1.35;"">$enc</pre></body></html>"

    # Build the SES payload as JSON (handles all escaping) and pass via file://.
    $payload = @{
        FromEmailAddress = $From
        Destination      = @{ ToAddresses = @($To) }
        Content          = @{ Simple = @{
                Subject = @{ Data = $subject }
                Body    = @{ Text = @{ Data = $report }; Html = @{ Data = $html } }
            } }
    }
    $json     = $payload | ConvertTo-Json -Depth 8
    $jsonPath = Join-Path $env:TEMP 'kla-ses-email.json'
    [System.IO.File]::WriteAllText($jsonPath, $json)   # UTF-8, no BOM

    $resp = aws sesv2 send-email --region $Region --cli-input-json "file://$jsonPath" --output json | ConvertFrom-Json
    Log "Sent OK ($($report.Length) chars) MessageId=$($resp.MessageId)"
    Write-Host "Sent to $To from $From  (MessageId: $($resp.MessageId))"
}
catch {
    Log "ERROR: $($_.Exception.Message)"
    throw
}
