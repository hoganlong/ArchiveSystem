<#
  cloudfront-usage.ps1  —  Keith Long Archive traffic + CloudFront Pro-plan gauge

  Shows, per UTC day:
    * website requests + distinct visitor IPs ("Web users")
    * photos requests + GB, and total GB
  then gauges the photos distribution (art-photos, E11XZPTTZY29I9 — on a
  CloudFront flat-rate Pro plan, $15/month) against the Pro allowances:
    50 TB data transfer + 10 M requests / month.

  Pro is FLAT $15/mo with NO overage charges — exceeding never costs extra
  (first 3x spike forgiven; sustained excess judged over 2-3 months; worst case
  is slower delivery, never a surprise bill).

  "Web users" = distinct client IPs from the website distribution's CloudFront
  access logs. Notes:
    * Only available from when logging was enabled (~2026-07-15); earlier days
      show "-".
    * Website-page viewers only — the photos distro has standard logging OFF,
      so there are no per-IP logs for image traffic.
    * IP count approximates people (shared NAT undercounts; roaming overcounts).

  USAGE (from an open PowerShell window, in this folder):
      .\cloudfront-usage.ps1                # last 7 days
      .\cloudfront-usage.ps1 -Days 30       # last 30 days
      .\cloudfront-usage.ps1 -SkipUsers     # skip the log download (faster)

  Requires: AWS CLI v2 (configured). Read-only CloudWatch + S3 log reads.
#>
[CmdletBinding()]
param([int]$Days = 7, [switch]$SkipUsers)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false   # don't throw on aws exit codes
Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue

# --- config ----------------------------------------------------------------
$PHOTOS  = 'E11XZPTTZY29I9'    # art-photos, dd6nj5ah4a2eh.cloudfront.net (Pro plan)
$WEBSITE = 'E1WA80M7F42SVB'    # archive.keithlong.com (static HTML)
$REGION  = 'us-east-1'
$PRO_TB  = 50                  # Pro monthly data-transfer allowance (TB)
$PRO_RM  = 10                  # Pro monthly request allowance (millions)
$GB = 1073741824.0
$TB = 1099511627776.0

$LogBucket = 'website-logs-hogan'
$LogPrefix = 'cloudfront/archive.keithlong.com/'
$LogCache  = Join-Path $env:TEMP 'kla-cf-weblogs'

# --- pull one CloudWatch metric as a date->sum map (UTC days) --------------
function Get-Daily {
    param($Dist, $Metric, $Start, $End)
    $out = aws cloudwatch get-metric-statistics `
        --namespace AWS/CloudFront --metric-name $Metric `
        --dimensions "Name=DistributionId,Value=$Dist" "Name=Region,Value=Global" `
        --start-time $Start --end-time $End --period 86400 --statistics Sum `
        --region $REGION --output json 2>$null | ConvertFrom-Json
    $map = @{}
    foreach ($dp in $out.Datapoints) {
        $d = ([datetime]$dp.Timestamp).ToUniversalTime().ToString('yyyy-MM-dd')
        $map[$d] = [double]$dp.Sum
    }
    return $map
}

function Bar([double]$pct) {
    $n = [int]($pct / 5); if ($n -gt 20) { $n = 20 }; if ($n -lt 0) { $n = 0 }
    ('#' * $n) + ('.' * (20 - $n))
}

# --- distinct visitor IPs per day from the website CloudFront logs ---------
function Get-UsersByDay {
    New-Item -ItemType Directory -Force -Path $LogCache | Out-Null
    Write-Host "Syncing website CloudFront logs (incremental)..." -ForegroundColor DarkGray
    aws s3 sync "s3://$LogBucket/$LogPrefix" $LogCache --only-show-errors
    $byDay = @{}
    foreach ($f in (Get-ChildItem -Path $LogCache -Filter *.gz -File -ErrorAction SilentlyContinue)) {
        $fs = $gz = $sr = $null
        try {
            $fs = [System.IO.File]::OpenRead($f.FullName)
            $gz = New-Object System.IO.Compression.GzipStream($fs, [System.IO.Compression.CompressionMode]::Decompress)
            $sr = New-Object System.IO.StreamReader($gz)
            while ($null -ne ($line = $sr.ReadLine())) {
                if ($line.Length -eq 0 -or $line[0] -eq '#') { continue }
                $p = $line.Split("`t")
                if ($p.Length -lt 5) { continue }
                $d = $p[0]; $ip = $p[4]          # W3C: [0]=date, [4]=c-ip
                if (-not $byDay.ContainsKey($d)) {
                    $byDay[$d] = New-Object 'System.Collections.Generic.HashSet[string]'
                }
                [void]$byDay[$d].Add($ip)
            }
        } finally {
            if ($sr) { $sr.Dispose() }; if ($gz) { $gz.Dispose() }; if ($fs) { $fs.Dispose() }
        }
    }
    return $byDay
}

# --- date bounds (UTC) ------------------------------------------------------
$today       = [datetime]::UtcNow.Date
$monthStart  = [datetime]::new($today.Year, $today.Month, 1)
$daysInMonth = [datetime]::DaysInMonth($today.Year, $today.Month)
$tblStart    = $today.AddDays(-($Days - 1))
$dataStart   = if ($monthStart -lt $tblStart) { $monthStart } else { $tblStart }
$startIso    = $dataStart.ToString('yyyy-MM-ddT00:00:00Z')
$endIso      = $today.AddDays(1).ToString('yyyy-MM-ddT00:00:00Z')  # include today's partial

# --- fetch ------------------------------------------------------------------
Write-Host "Querying CloudWatch..." -ForegroundColor DarkGray
$wReq  = Get-Daily $WEBSITE Requests        $startIso $endIso
$wByte = Get-Daily $WEBSITE BytesDownloaded $startIso $endIso
$pReq  = Get-Daily $PHOTOS  Requests        $startIso $endIso
$pByte = Get-Daily $PHOTOS  BytesDownloaded $startIso $endIso
$usersByDay = if ($SkipUsers) { @{} } else { Get-UsersByDay }

# --- daily table + accumulate ----------------------------------------------
""
"CloudFront usage - Keith Long Archive   (last $Days days, UTC)"
"========================================================================================"
"{0,-11} {1,9} {2,8} {3,8} {4,11} {5,8} {6,9}" -f 'Day','Web req','Web users','Web GB','Photos req','Ph. GB','Total GB'
"----------------------------------------------------------------------------------------"

$mtdB = 0.0; $mtdR = 0.0
$lastD = $null; $lastB = 0.0; $lastR = 0.0
$winIps = New-Object 'System.Collections.Generic.HashSet[string]'

for ($d = $dataStart; $d -le $today; $d = $d.AddDays(1)) {
    $k  = $d.ToString('yyyy-MM-dd')
    $wr = [double]$wReq[$k]; $wb = [double]$wByte[$k]
    $pr = [double]$pReq[$k]; $pb = [double]$pByte[$k]
    $uCell = if ($usersByDay.ContainsKey($k)) { "{0:N0}" -f $usersByDay[$k].Count } else { '-' }

    if ($d -ge $tblStart) {
        "{0,-11} {1,9:N0} {2,8} {3,8:N2} {4,11:N0} {5,8:N2} {6,9:N2}" -f `
            $k, $wr, $uCell, ($wb/$GB), $pr, ($pb/$GB), (($wb+$pb)/$GB)
        if ($usersByDay.ContainsKey($k)) { $winIps.UnionWith($usersByDay[$k]) }
    }
    if ($d -ge $monthStart) { $mtdB += $pb; $mtdR += $pr }
    if ($pb -gt 0 -and $d -lt $today) { $lastD = $k; $lastB = $pb; $lastR = $pr }
}
"----------------------------------------------------------------------------------------"

if (-not $SkipUsers) {
    $lastFullUsers = if ($lastD -and $usersByDay.ContainsKey($lastD)) { $usersByDay[$lastD].Count } else { $null }
    $lu = if ($null -ne $lastFullUsers) { "{0:N0}" -f $lastFullUsers } else { 'n/a' }
    "Website visitors: last full day ($lastD) = $lu distinct IPs;  {0:N0} unique across the last $Days days (deduped)." -f $winIps.Count
}

# --- Pro-plan gauge (photos distribution) ----------------------------------
$mtdTB = $mtdB / $TB;  $mtdRM = $mtdR / 1e6
$pctT  = 100 * $mtdTB / $PRO_TB
$pctR  = 100 * $mtdRM / $PRO_RM
$projTB = ($lastB * $daysInMonth) / $TB
$projRM = ($lastR * $daysInMonth) / 1e6
$ppctT  = 100 * $projTB / $PRO_TB
$ppctR  = 100 * $projRM / $PRO_RM

""
"Pro plan (`$15/mo, art-photos) - month-to-date vs allowance"
"  Data transfer [{0}] {1,6:N2} / {2} TB  ({3:N1}%)" -f (Bar $pctT), $mtdTB, $PRO_TB, $pctT
"  Requests      [{0}] {1,6:N2} / {2} M   ({3:N1}%)" -f (Bar $pctR), $mtdRM, $PRO_RM, $pctR

if ($lastD) {
    ""
    "At the most recent full day ($lastD`: {0:N1} GB, {1:N0} req), a full month projects to:" -f ($lastB/$GB), $lastR
    "   transfer ~{0:N1} TB ({1:N0}% of 50 TB) , requests ~{2:N1} M ({3:N0}% of 10 M)" -f $projTB, $ppctT, $projRM, $ppctR
    $bind = if ($ppctR -ge $ppctT) { 'requests' } else { 'data transfer' }
    "   -> $bind is the tighter constraint at this traffic mix."
}

$worst = [math]::Max($ppctT, $ppctR)
""
if     ($worst -lt 60)  { "  OK - well within Pro allowances. No overage charges regardless; nothing to do." }
elseif ($worst -lt 100) { "  ~ Trending toward the allowance. No charges even if exceeded, but watch the 80%/100% emails." }
else                    { "  ** Projected over allowance. Still NO overage `$, but sustained 3+ mo excess could slow delivery - consider Business tier." }
"  (Reminder: first 3x spike/month is forgiven; excess judged over 2-3 months, never billed.)"
""
