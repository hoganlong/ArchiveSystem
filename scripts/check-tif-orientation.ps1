<#
.SYNOPSIS
  Scan TIF files on S3 for a non-normal EXIF/TIFF orientation tag.

.DESCRIPTION
  Any TIF with an orientation tag other than 1 (normal) will have produced a
  mis-rotated JPG via the (pre-fix) tif2jpg tool, because the tag was ignored
  and then stripped. This flags those TIFs so their JPGs can be regenerated
  with the fixed tif2jpg (which now calls AutoOrient()).

  It reads only ~16 bytes + ~4 KB per file via ranged S3 GETs (no full download).

.EXAMPLE
  ./check-tif-orientation.ps1                     # scans sscan/
  ./check-tif-orientation.ps1 -Prefix ""          # scans the whole bucket
  ./check-tif-orientation.ps1 -Prefix "scans/"    # scans the sketchbook/polaroid TIFs
#>
param(
  [string]$Bucket   = "keithlong-art-photos",
  [string]$Prefix   = "sscan/",
  [string]$Region   = "us-east-1",
  [int]   $Throttle = 16
)

$binDir = "D:\Projects\claudetest\tif2jpg\bin\Debug\net10.0"
Add-Type -Path "$binDir\AWSSDK.Core.dll"
Add-Type -Path "$binDir\AWSSDK.S3.dll"

$regionEndpoint = [Amazon.RegionEndpoint]::GetBySystemName($Region)
$client = [Amazon.S3.AmazonS3Client]::new($regionEndpoint)

# ---- List all .tif/.tiff keys under the prefix (paginated) ----
$keys = New-Object System.Collections.Generic.List[string]
$req  = [Amazon.S3.Model.ListObjectsV2Request]::new()
$req.BucketName = $Bucket
$req.Prefix     = $Prefix
do {
  $resp = $client.ListObjectsV2Async($req).GetAwaiter().GetResult()
  foreach ($o in $resp.S3Objects) {
    if ($o.Key -match '\.t(if|iff)$') { $keys.Add($o.Key) }
  }
  $req.ContinuationToken = $resp.NextContinuationToken
} while ($resp.IsTruncated)

Write-Host ("Found {0} TIF files under s3://{1}/{2}" -f $keys.Count, $Bucket, $Prefix)
Write-Host "Reading orientation tags (ranged GETs)..."

# ---- Read the orientation tag from each TIF in parallel ----
$results = $keys | ForEach-Object -ThrottleLimit $Throttle -Parallel {
  $client = $using:client
  $bucket = $using:Bucket
  $key    = $_

  function Get-Range($client, $bucket, $key, [long]$start, [long]$end) {
    $r = [Amazon.S3.Model.GetObjectRequest]::new()
    $r.BucketName = $bucket; $r.Key = $key
    $r.ByteRange  = [Amazon.S3.Model.ByteRange]::new($start, $end)
    $resp = $client.GetObjectAsync($r).GetAwaiter().GetResult()
    $ms = New-Object System.IO.MemoryStream
    $resp.ResponseStream.CopyTo($ms); $resp.Dispose()
    ,$ms.ToArray()
  }
  function U16($b, $off, $little) { $t = $b[$off..($off+1)]; if (-not $little) { [array]::Reverse($t) }; [BitConverter]::ToUInt16($t,0) }
  function U32($b, $off, $little) { $t = $b[$off..($off+3)]; if (-not $little) { [array]::Reverse($t) }; [BitConverter]::ToUInt32($t,0) }

  try {
    $head = Get-Range $client $bucket $key 0 15
    if ($head.Length -lt 8) { return [pscustomobject]@{ Key=$key; Orientation=$null; Note="too small" } }
    $little = ($head[0] -eq 0x49)
    $magic  = U16 $head 2 $little
    if ($magic -eq 43) { return [pscustomobject]@{ Key=$key; Orientation=$null; Note="BigTIFF (unsupported)" } }
    if ($magic -ne 42) { return [pscustomobject]@{ Key=$key; Orientation=$null; Note="not a TIFF" } }

    $ifdOff = U32 $head 4 $little
    $ifd = Get-Range $client $bucket $key $ifdOff ($ifdOff + 4095)
    if ($ifd.Length -lt 2) { return [pscustomobject]@{ Key=$key; Orientation=$null; Note="short IFD" } }
    $n = U16 $ifd 0 $little
    $orient = $null
    for ($i = 0; $i -lt $n; $i++) {
      $e = 2 + $i * 12
      if ($e + 12 -gt $ifd.Length) { break }
      if ((U16 $ifd $e $little) -eq 274) { $orient = U16 $ifd ($e + 8) $little; break }
    }
    [pscustomobject]@{ Key=$key; Orientation=$orient; Note=$null }
  }
  catch {
    [pscustomobject]@{ Key=$key; Orientation=$null; Note=("ERROR: " + $_.Exception.Message) }
  }
}

# ---- Report ----
$labels = @{ 2="flip-horizontal"; 3="rotate-180"; 4="flip-vertical"; 5="transpose"; 6="rotate-90-CW"; 7="transverse"; 8="rotate-270-CW" }
$funky   = $results | Where-Object { $_.Orientation -ne $null -and $_.Orientation -ne 1 }
$errored = $results | Where-Object { $_.Note -like "ERROR*" -or $_.Note -like "*unsupported*" }

Write-Host ""
Write-Host ("Normal (tag absent or =1): {0}" -f (($results | Where-Object { $_.Orientation -eq $null -and -not $_.Note }).Count + ($results | Where-Object { $_.Orientation -eq 1 }).Count))
Write-Host ("FUNKY orientation        : {0}" -f $funky.Count) -ForegroundColor Yellow
Write-Host ("Errors / unsupported     : {0}" -f $errored.Count)
Write-Host ""
if ($funky.Count -gt 0) {
  Write-Host "TIFs with a non-normal orientation tag (their JPGs are mis-rotated pre-fix):" -ForegroundColor Yellow
  $funky | Sort-Object Key | ForEach-Object {
    $lbl = if ($labels.ContainsKey([int]$_.Orientation)) { $labels[[int]$_.Orientation] } else { "unknown" }
    Write-Host ("  {0}  (orientation={1} = {2})" -f $_.Key, $_.Orientation, $lbl)
  }
}
if ($errored.Count -gt 0) {
  Write-Host ""
  Write-Host "Could not read (review manually):"
  $errored | ForEach-Object { Write-Host ("  {0}  — {1}" -f $_.Key, $_.Note) }
}
