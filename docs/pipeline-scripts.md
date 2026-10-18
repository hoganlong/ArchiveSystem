# Pipeline Scripts

Convenience PowerShell scripts live in the `scripts/` folder — their tracked home in this repo. They are not .NET projects; they orchestrate the projects (and S3) for common workflows. `build-and-deploy.ps1` is also copied to the root of the working directory where it's run; the image scripts can be symlinked to the root instead (see [Script locations](#script-locations)).

---

## build-and-deploy.ps1

The main pipeline script. Runs all seven steps in order and asks before deploying to AWS. Before step 3 it runs `wake-db.ps1` so the auto-pausing Aurora database is awake for the ETL (non-fatal if it can't confirm).

### Steps

| # | Step | Project | Notes |
|---|---|---|---|
| 1 | Airtable Image Downloader | `AirtableImageDownloader` | Exit code indicates whether new images were found |
| 2 | Check S3 vs Local | `checks3vslocal` | Skipped automatically if step 1 found no new images |
| 3 | Airtable to Postgres ETL | `AirtableToPostgres` | |
| 4 | tif2jpg (sscan) | `tif2jpg` | Generates missing sized JPGs for `sscan/` TIFs |
| 5 | Generate HTML | `ArtWorkHTML` | |
| 6 | Sync to S3 | AWS CLI | Prompts for confirmation before running |
| 7 | CloudFront Invalidation | AWS CLI | Only runs if step 6 ran |

### Usage

Run all steps:
```powershell
.\build-and-deploy.ps1
```

Run a subset of steps (e.g. ETL and HTML only):
```powershell
.\build-and-deploy.ps1 -StartStep 3 -StopStep 4
```

### Requirements

- AWS CLI installed at `C:\Program Files\Amazon\AWSCLIV2\aws.exe`
- AWS credentials configured with access to the S3 bucket and CloudFront distribution
- All project `appsettings.json` files configured (see [configuration-reference.md](configuration-reference.md))

### Adapting for a different artist

- `-Root <path>` — the workspace folder holding the project subfolders. Defaults to `D:\Projects\KLA`; override if yours lives elsewhere.
- In the **Sync to S3** step, change `s3://archive.keithlong.com/` to your bucket.
- In the **CloudFront Invalidation** step, change `--distribution-id E1WA80M7F42SVB` to your distribution ID.

---

## check-tif-orientation.ps1

Scans every TIF under an S3 prefix for a non-normal EXIF/TIFF orientation tag,
reading only ~16 bytes + ~4 KB per file via ranged S3 GETs (no full download).

```powershell
.\scripts\check-tif-orientation.ps1 -Prefix "sscan/"   # -Prefix "" for the whole bucket
```

---

## rotate-tif-and-jpg.ps1

Rotates one or more TIFs on S3 **and** refreshes the JPG(s) derived from them:
preview → confirm → rotate (via `rotate180 --upload`) → delete stale JPG(s) →
optionally regenerate (via `tif2jpg`).

```powershell
.\scripts\rotate-tif-and-jpg.ps1 -Jobs "scans/KLA_02_110.tif=90","sscan/KL_E_41.tif=270"
.\scripts\rotate-tif-and-jpg.ps1 -Jobs "scans/foo.tif=180" -DryRun   # plan only, no changes
```

Flags: `-DryRun`, `-NoPreview`, `-AssumeYes`, `-Bucket`/`-Region`. Full workflow
and the orientation-tag caveat: [image-rotation-and-orientation.md](image-rotation-and-orientation.md).

---

## deleteemptyfolders.ps1

Recursively removes empty sub-folders under a target path (deepest first). Handy
for cleaning up leftover temp working dirs. Edit the `$TargetRoot` and `$WhatIf`
variables at the top before running; set `$WhatIf = $true` to preview deletions.

```powershell
.\scripts\deleteemptyfolders.ps1
```

---

## Database connection helpers

The archive database is Aurora Serverless and pauses when idle, and its security group allows only specific IPs. A connection timeout can mean either case; these scripts tell them apart and fix them.

| Script | Purpose |
|---|---|
| `wake-db.ps1` | Wakes the paused cluster with a real `SELECT 1` through RunSql (a bare port knock doesn't trigger resume). Read-only. Called by `build-and-deploy.ps1` |
| `fix-my-ip.ps1` | First check when the DB won't connect: compares this machine's public IP to the DB security group's allowlist and says whether it's the IP or just a paused cluster. Changes nothing |
| `authorize-my-ip.ps1` | Adds this machine's current public IP to the DB security group (port 5432); `-ReplaceOthers` also removes stale IPs |

The security group is discovered from AWS, not hardcoded. `fix-my-ip.ps1` is also symlinked at the workspace root.

---

## Website statistics

| Script | Purpose |
|---|---|
| `cloudfront-usage.ps1` (+ `cloudfront-usage.sh`) | Per-day website requests, distinct visitor IPs, photos requests/GB, and a CloudFront Pro-plan usage gauge. `-Days N`, `-SkipUsers` |
| `send-website-stats.ps1` | Legacy: emailed the `cloudfront-usage.ps1` report via SES from a Windows scheduled task. Replaced by the `website-stats-lambda` repo (AWS Lambda + EventBridge Scheduler); the scheduled task has been deleted |

---

## Script locations

The scripts' tracked home is this repo's `scripts/` folder. They reference the
project `.csproj` paths by absolute path, so they run from anywhere. For
convenience they can be **symlinked** into the workspace root (Windows Developer
Mode or an elevated shell is required to create the symlink):

```powershell
# from an elevated PowerShell, per script:
New-Item -ItemType SymbolicLink -Path "D:\Projects\KLA\rotate-tif-and-jpg.ps1" `
  -Target "D:\Projects\KLA\archivesystem\scripts\rotate-tif-and-jpg.ps1"
```

Edit the tracked copy in `scripts/`, not the root symlink.

