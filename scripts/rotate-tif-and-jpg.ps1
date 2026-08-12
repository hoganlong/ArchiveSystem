<#
.SYNOPSIS
  Rotate one or more TIFs on S3 and refresh the JPG(s) derived from them.

.DESCRIPTION
  For each "key=angle" job it:
    1. (preview) shows current vs. proposed rotation, built from the small
       derived JPG (no full-size TIF download), and opens it for you to verify.
    2. rotates the source TIF on S3 in place via rotate180 (--upload).
    3. deletes the stale derived JPG(s) so they can be regenerated
       (auto-detects sized _small/_large/_full vs. flat <base>.jpg layout).
    4. optionally (y/n) regenerates the JPG(s) now via tif2jpg — one run covers
       every affected prefix. If you skip it, the exact command(s) to run later
       are printed (the stale JPGs are already deleted, so a later run rebuilds them).

  rotate180 already calls AutoOrient() on the TIF, so the rotated TIF is written
  with a normalized orientation tag and the regenerated JPGs match it.

  Angle is clockwise (90 | 180 | 270), same as rotate180.

.PARAMETER Jobs
  One or more "s3key=angle" entries, e.g. "scans/KLA_02_110.tif=90".
  The s3key is relative to the bucket (no s3:// prefix).

.EXAMPLE
  ./rotate-tif-and-jpg.ps1 -Jobs "scans/KLA_02_110.tif=90","sscan/KL_E_41.tif=270"

.EXAMPLE
  ./rotate-tif-and-jpg.ps1 -Jobs "scans/foo.tif=180" -DryRun     # show plan, change nothing
#>
param(
  [Parameter(Mandatory=$true)][string[]]$Jobs,
  [string]$Bucket        = "keithlong-art-photos",
  [string]$Region        = "us-east-1",
  [string]$Rotate180Proj = (Join-Path $PSScriptRoot '..\..\rotate\rotate180.csproj'),
  [string]$Tif2JpgProj   = (Join-Path $PSScriptRoot '..\..\tif2jpg\tif2jpg.csproj'),
  [switch]$NoPreview,
  [switch]$DryRun,
  [switch]$AssumeYes
)
$ErrorActionPreference = "Stop"

# ---------- Magick.NET (from rotate180 build output) ----------
$bin = Join-Path (Split-Path $Rotate180Proj) "bin\Debug\net10.0"
$env:PATH = "$bin\runtimes\win-x64\native;$env:PATH"
Add-Type -Path "$bin\Magick.NET.Core.dll"
Add-Type -Path "$bin\Magick.NET-Q8-AnyCPU.dll"

function New-Thumb($img, $border) {
  $img.BackgroundColor = [ImageMagick.MagickColor]::new("white")
  $img.Resize([ImageMagick.MagickGeometry]::new(300,300))
  $img.Extent([ImageMagick.MagickGeometry]::new(300,300), [ImageMagick.Gravity]::Center)
  $img.BorderColor = [ImageMagick.MagickColor]::new($border)
  $img.Border(4)
  $img
}

function Parse-Job($s) {
  $idx = $s.LastIndexOf('=')
  if ($idx -lt 0) { throw "Bad job '$s' (expected key=angle)" }
  $key   = $s.Substring(0, $idx).Trim()
  $angle = [int]$s.Substring($idx + 1).Trim()
  if ($angle -notin 90,180,270) { throw "Bad angle '$angle' for '$key' (must be 90, 180, or 270)" }
  if ($key -notmatch '\.tiff?$') { throw "Not a .tif/.tiff key: '$key'" }
  $slash = $key.LastIndexOf('/')
  [pscustomobject]@{
    Key       = $key
    Angle     = $angle
    Prefix    = $key.Substring(0, $slash + 1)
    Base      = [System.IO.Path]::GetFileNameWithoutExtension($key)
    JpgFolder = $key.Substring(0, $slash + 1) + "jpg/"
  }
}

function Get-JpgKeys($folder, $base) {
  $out = aws s3api list-objects-v2 --bucket $Bucket --prefix "$folder$base" --query "Contents[].Key" --output text 2>$null
  if (-not $out -or $out -eq "None") { return @() }
  $pat = "^$([regex]::Escape($base))(_(small|large|full))?\.(jpg|jpeg)$"
  @($out -split "\s+" | Where-Object { $_ } | Where-Object { ($_ -replace '.*/','') -match $pat })
}

function Select-PreviewKey($keys, $base) {
  $p = $keys | Where-Object { $_ -match '_large\.(jpg|jpeg)$' } | Select-Object -First 1
  if (-not $p) { $p = $keys | Where-Object { ($_ -replace '.*/','') -match "^$([regex]::Escape($base))\.(jpg|jpeg)$" } | Select-Object -First 1 }
  if (-not $p) { $p = $keys | Where-Object { $_ -match '_full\.(jpg|jpeg)$' } | Select-Object -First 1 }
  if (-not $p) { $p = $keys | Select-Object -First 1 }
  $p
}

$parsed = @($Jobs | ForEach-Object { Parse-Job $_ })

Write-Host ""
Write-Host ("Bucket: {0}   Files: {1}   Mode: {2}" -f $Bucket, $parsed.Count, ($(if($DryRun){"DRY RUN (no changes)"}else{"live"})))
$parsed | ForEach-Object { Write-Host ("  {0}  ->  rotate {1} CW" -f $_.Key, $_.Angle) }

# ---------- Verify every TIF key exists on S3 (fail fast on typos) ----------
$missing = @()
foreach ($j in $parsed) {
  aws s3api head-object --bucket $Bucket --key $j.Key 1>$null 2>$null
  if ($LASTEXITCODE -ne 0) { $missing += $j.Key }
}
if ($missing.Count -gt 0) {
  Write-Host ""
  Write-Host "Not found on S3 — check the key/prefix. Nothing was changed:" -ForegroundColor Red
  $missing | ForEach-Object { Write-Host ("  x s3://{0}/{1}" -f $Bucket, $_) -ForegroundColor Red }
  exit 1
}

# ---------- Preview ----------
if (-not $NoPreview) {
  $pdir = Join-Path $env:TEMP ("rotprev_" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force $pdir | Out-Null
  $rows  = New-Object ImageMagick.MagickImageCollection
  $order = @()
  foreach ($j in $parsed) {
    $jkeys = Get-JpgKeys $j.JpgFolder $j.Base
    if ($jkeys.Count -eq 0) {
      Write-Host ("  [preview] {0}: no derived JPG to preview (TIF will still rotate)" -f $j.Base) -ForegroundColor Yellow
      continue
    }
    $dst = Join-Path $pdir ($j.Base + ".jpg")
    aws s3 cp "s3://$Bucket/$(Select-PreviewKey $jkeys $j.Base)" $dst --quiet
    $cur = [ImageMagick.MagickImage]::new($dst)
    $rot = [ImageMagick.MagickImage]::new($dst); $rot.Rotate($j.Angle)
    $rc = New-Object ImageMagick.MagickImageCollection
    $rc.Add((New-Thumb $cur "gray")); $rc.Add((New-Thumb $rot "green"))
    $rows.Add($rc.AppendHorizontally()); $rc.Dispose()
    $order += ("{0}  (current gray -> proposed +{1} CW green)" -f $j.Key, $j.Angle)
  }
  if ($rows.Count -gt 0) {
    $maxW = ($rows | ForEach-Object { $_.Width } | Measure-Object -Maximum).Maximum
    foreach ($r in $rows) { $r.BackgroundColor=[ImageMagick.MagickColor]::new("white"); $r.Extent([ImageMagick.MagickGeometry]::new($maxW, $r.Height), [ImageMagick.Gravity]::West) }
    $sheet = $rows.AppendVertically()
    $sheetPath = Join-Path $pdir "preview.png"
    $sheet.Write($sheetPath)
    Write-Host ""
    Write-Host "PREVIEW rows (top to bottom):"
    $i = 1; $order | ForEach-Object { Write-Host ("  {0}. {1}" -f $i++, $_) }
    Invoke-Item $sheetPath
    Write-Host "Opened: $sheetPath"
  }
}

# ---------- Confirm ----------
if ($DryRun) {
  Write-Host ""
  Write-Host "DRY RUN — would rotate the TIF(s) above (--upload), delete their derived JPG(s), then regenerate."
  $prefixes = $parsed | Group-Object Prefix | ForEach-Object { $_.Name }
  Write-Host "Regeneration command(s) that would apply:"
  foreach ($p in $prefixes) {
    $flat = if ($p -like "*sscan/") { "" } else { " --flat" }
    Write-Host ("  dotnet run --project `"{0}`" -- s3://{1}/{2}{3} --create --upload" -f $Tif2JpgProj, $Bucket, $p, $flat)
  }
  return
}
if (-not $AssumeYes) {
  $ans = Read-Host "Rotate these $($parsed.Count) TIF(s) on S3 and OVERWRITE the originals? (y/n)"
  if ($ans -notmatch '^(y|yes)$') { Write-Host "Aborted. No changes made."; return }
}

# ---------- Rotate TIFs ----------
$tmp = Join-Path $env:TEMP ("rotwork_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force $tmp | Out-Null
$rotated = New-Object System.Collections.Generic.List[object]
foreach ($j in $parsed) {
  Write-Host ""
  Write-Host ("↻ Rotating s3://{0}/{1} by {2} CW..." -f $Bucket, $j.Key, $j.Angle)
  Push-Location $tmp
  try { & dotnet run --project $Rotate180Proj -- "s3://$Bucket/$($j.Key)" --angle $j.Angle --upload | Out-Null; $ok = ($LASTEXITCODE -eq 0) }
  finally { Pop-Location }
  if ($ok) { $rotated.Add($j); Write-Host "  OK: rotated TIF uploaded" -ForegroundColor Green }
  else     { Write-Host "  FAILED (rotate180 exit $LASTEXITCODE) — skipping this file's JPG refresh" -ForegroundColor Red }
}
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue

if ($rotated.Count -eq 0) { Write-Host "No TIFs rotated successfully. Nothing else to do."; return }

# ---------- Delete stale derived JPGs (+ record layout per prefix) ----------
Write-Host ""
Write-Host "Deleting stale derived JPG(s)..."
$prefixSized = @{}
foreach ($j in $rotated) {
  $jkeys = Get-JpgKeys $j.JpgFolder $j.Base
  if ($jkeys.Count -gt 0) { $sized = [bool]($jkeys | Where-Object { $_ -match '_(small|large|full)\.(jpg|jpeg)$' }) }
  else                    { $sized = ($j.Prefix -like "*sscan/") }   # heuristic when nothing to inspect
  if (-not $prefixSized.ContainsKey($j.Prefix)) { $prefixSized[$j.Prefix] = $sized }
  foreach ($k in $jkeys) { aws s3 rm "s3://$Bucket/$k" | Out-Null; Write-Host "  deleted s3://$Bucket/$k" }
  if ($jkeys.Count -eq 0) { Write-Host ("  ({0}: no existing JPG; will be created on regen)" -f $j.Base) -ForegroundColor Yellow }
}

# ---------- Build regen command(s) ----------
$cmds = @()
foreach ($p in $prefixSized.Keys) {
  $flat = if ($prefixSized[$p]) { "" } else { " --flat" }
  $cmds += ("dotnet run --project `"{0}`" -- s3://{1}/{2}{3} --create --upload" -f $Tif2JpgProj, $Bucket, $p, $flat)
}

# ---------- Regenerate now? ----------
$doRegen = $AssumeYes
if (-not $AssumeYes) { $doRegen = ((Read-Host "Regenerate JPG(s) now? (y/n)") -match '^(y|yes)$') }

if ($doRegen) {
  foreach ($c in $cmds) { Write-Host ""; Write-Host "-> $c"; Invoke-Expression $c }
  # ---- view the result ----
  if (-not $NoPreview) {
    $vdir = Join-Path $env:TEMP ("rotresult_" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force $vdir | Out-Null
    $vrows = New-Object ImageMagick.MagickImageCollection
    foreach ($j in $rotated) {
      $jkeys = Get-JpgKeys $j.JpgFolder $j.Base
      if ($jkeys.Count -eq 0) { continue }
      $dst = Join-Path $vdir ($j.Base + ".jpg")
      aws s3 cp "s3://$Bucket/$(Select-PreviewKey $jkeys $j.Base)" $dst --quiet
      $vrows.Add((New-Thumb ([ImageMagick.MagickImage]::new($dst)) "green"))
    }
    if ($vrows.Count -gt 0) {
      $vsheet = $vrows.AppendVertically()
      $vpath = Join-Path $vdir "result.png"
      $vsheet.Write($vpath)
      Invoke-Item $vpath
      Write-Host ""
      Write-Host "Opened regenerated result: $vpath"
    }
  }
  Write-Host ""
  Write-Host "Done. For reference, the regeneration command(s) used:" -ForegroundColor Cyan
} else {
  Write-Host ""
  Write-Host "Skipped regeneration. Stale JPG(s) are deleted — run this later to rebuild them:" -ForegroundColor Yellow
}
$cmds | ForEach-Object { Write-Host "  $_" }
