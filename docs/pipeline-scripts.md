# Pipeline Scripts

Convenience PowerShell scripts live in the `scripts/` folder — their tracked home in this repo. They are not .NET projects; they orchestrate the projects (and S3) for common workflows. `build-and-deploy.ps1` is also copied to the root of the working directory where it's run; the image scripts can be symlinked to the root instead (see [Script locations](#script-locations)).

---

## build-and-deploy.ps1

The main pipeline script. Runs all six steps in order and asks before deploying to AWS.

### Steps

| # | Step | Project | Notes |
|---|---|---|---|
| 1 | Airtable Image Downloader | `AirtableImageDownloader` | Exit code indicates whether new images were found |
| 2 | Check S3 vs Local | `checks3vslocal` | Skipped automatically if step 1 found no new images |
| 3 | Airtable to Postgres ETL | `AirtableToPostgres` | |
| 4 | Generate HTML | `ArtWorkHTML` | |
| 5 | Sync to S3 | AWS CLI | Prompts for confirmation before running |
| 6 | CloudFront Invalidation | AWS CLI | Only runs if step 5 ran |

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

Update the S3 bucket name and CloudFront distribution ID in the script:
- Line 52: `s3://archive.keithlong.com/` → your bucket
- Line 61: `--distribution-id E1WA80M7F42SVB` → your distribution ID

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

## Script locations

The scripts' tracked home is this repo's `scripts/` folder. They reference the
project `.csproj` paths by absolute path, so they run from anywhere. For
convenience they can be **symlinked** into the workspace root (Windows Developer
Mode or an elevated shell is required to create the symlink):

```powershell
# from an elevated PowerShell, per script:
New-Item -ItemType SymbolicLink -Path "D:\Projects\claudetest\rotate-tif-and-jpg.ps1" `
  -Target "D:\Projects\claudetest\archivesystem\scripts\rotate-tif-and-jpg.ps1"
```

Edit the tracked copy in `scripts/`, not the root symlink.

