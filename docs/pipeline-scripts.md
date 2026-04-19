# Pipeline Scripts

Three convenience scripts live in the `scripts/` folder (and in the root of your working directory). They are not .NET projects — they just orchestrate running the projects in sequence.

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

