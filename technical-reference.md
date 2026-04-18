# Technical Reference

Build commands, architecture details, and component notes for developers working on the Archive System.

---

## Build & Run Commands

Each project is independent. Run from the project directory:

```bash
cd AirtableSchemaReader && dotnet run

cd AirtableToPostgres && dotnet run          # default: incremental sync
cd AirtableToPostgres && dotnet run -- full  # full sync all tables

cd AirtableImageDownloader && dotnet run

cd checks3vslocal && dotnet run              # compare local vs S3
cd checks3vslocal && dotnet run -- --upload  # upload missing files to S3

cd ArtWorkHTML && dotnet run               # default: generate all HTML pages
cd ArtWorkHTML && dotnet run -- gen-static # generate static pages only (no DB required)

cd getspecialimages && dotnet run          # download artworks missing front-view images
cd readawsbucket && dotnet run             # list S3 bucket contents
```

Additional command line options (not needed in standard build process):
```bash
cd AirtableToPostgres && dotnet run -- query      # interactive queries with menu
cd AirtableToPostgres && dotnet run -- showall    # runs all queries
cd AirtableToPostgres && dotnet run -- diagnostic <ARTWORK_IMAGE>

cd ArtWorkHTML && dotnet run -- test-db           # test PostgreSQL connection
cd ArtWorkHTML && dotnet run -- test-airtable     # test Airtable connection
```
## Architecture

### Data Flow

```
Airtable Base
       │
       ├─→ AirtableSchemaReader  → airtable_schema.txt
       ├─→ AirtableToPostgres    → PostgreSQL (AWS RDS)
       │                                │
       │                                └─→ ArtWorkHTML → artwork_html/ (static site)
       │                                                   └─→ reads images from S3
       └─→ AirtableImageDownloader → images/artwork/ and images/archive/
```
### Image File Flow
```
Files from photographer
       ├─→ tif  → S3 "/" root 
       └─→ jpg  → S3 "/jpg" dir
Files from scanning service
       ├─→ tif  → S3 "/scan" dir 
       └─→ jpg  → S3 "/scan/jpg" dir
Files from AirtableImageDownloader
       └─→ jpg  → S3 "/atch" dir
```
---

## AirtableSchemaReader

- Outputs schema to `airtable_schema.txt`, which AirtableToPostgres consumes at startup
- `schema_overrides.json` supports: `exclude`, `setType`, `rename`, `setOptions`, `add`
- Run this first whenever your Airtable base schema changes (new fields, renamed fields, etc.)

---

## AirtableToPostgres — Key Components

| File | Role |
|---|---|
| `Program.cs` | Entry point, command dispatch |
| `SchemaGenerator.cs` / `SchemaParser.cs` | Reads `airtable_schema.txt`, creates typed PostgreSQL columns |
| `RecordMapper.cs` / `TypeMapper.cs` | Maps Airtable field values to typed PostgreSQL values |
| `ChangeDetector.cs` | Classifies records as NEW / UPDATED / UNCHANGED for incremental sync |
| `SyncHistoryLogger.cs` | Writes every sync operation to the `sync_history` table |

- Incremental sync uses Airtable's `LAST_MODIFIED_TIME()` filter for performance
- PostgreSQL columns are typed (not generic JSONB) based on the schema file

---

## AirtableImageDownloader — Key Details

- Downloads from attachment fields in any Airtable table
- Attachment field names are discovered dynamically from the schema — no hard-coding required
- Output directories: `images/artwork/` and `images/archive/`
  (TODO: this will probably change because archive is not used.)
- File naming: `{prefix}_{recordId}_{size}.{ext}` — size is one of `full`, `large`, or `small` (e.g., `artwork_A001_large.jpg`)
- Resume-capable: skips files that already exist on disk

---

## ArtWorkHTML — Key Components

Uses C# partial classes, one file per page type:

| File | Role |
|---|---|
| `ArtworkHTML.cs` | Main orchestrator — calls all page generators |
| `ArtList.cs` | Data model for artwork records |
| `GenerateArtworkPages.cs` | Main gallery (`artworksplus.html`) |
| `GenerateStatisticsPage.cs` | Stats page |
| `GenerateStylesheet.cs` | All CSS |
| `GenerateIndexPage.cs` | Home page |
| `GenerateHowIsMadePage.cs` | "How it's made" page |
| `GenerateCreditsPage.cs` | Credits page |
| `GenerateFeedbackPage.cs` | Feedback page |
| `GenerateHelpPage.cs` | Help page |
| `GenerateOpensourcePage.cs` | Open source page |
| `GenerateCopyrightPage.cs` | Copyright page |

- Reads from PostgreSQL tables: `artwork`, `artwork_image`, `artwork_type`, `sketch`
- Images are served from S3 (URLs stored in PostgreSQL)
- `gen-static` mode skips the database connection and generates only static/non-data pages

---

## getspecialimages

Queries PostgreSQL for artwork records that have no front-view image in `artwork_image` (and do have a reference image), then downloads those source files from S3 and saves them with HumanId-based filenames.

- S3 source prefix: `jpg/` (configurable via `S3:Prefix` in `appsettings.json`)
- Output directory: `images/` (configurable via `Output:Directory`)
- Resume-capable: skips files that already exist locally
- PostgreSQL credentials retrieved from AWS Secrets Manager

---

## checks3vslocal

Compares a local directory against an S3 bucket prefix. Reports files present locally but missing from S3. With `--upload`, uploads the missing files.

```bash
dotnet run -- <localPath> <s3Uri> --upload
```

Paths can also be set via `appsettings.json` (`S3:LocalPath`, `S3:S3Uri`, `S3:Region`).

---

## readawsbucket

Lists all objects in an S3 bucket with their sizes and last-modified dates. Useful for auditing bucket contents.

---

## CheckPhotoList

Verifies that records in the Airtable PHOTO table match local manifest files and S3 bucket contents. Reports missing or mismatched entries.

---

## fixcsv

One-off utility. Normalizes CSV headers and strips `.tif` extensions from filename fields. Used for preparing bulk import files.

---

## Airtable Tables (Keith Long Archive)

`ARTWORK`, `ARTWORK_IMAGE`, `PHOTO`, `SOLD`, `ARCHIVE`, `ARCHIVE_IMAGE`, `ARTWORK_TYPE`, `PHOTO_CATEGORY`, `SKETCH`

---

## Code Style

- .NET 10.0, C#, implicit usings, nullable reference types enabled
- 2-space indentation
- Async/await throughout
- `Newtonsoft.Json` for JSON, `Npgsql` for PostgreSQL, `AWSSDK.*` for AWS
- Functionality generic whenever possible with system specific functionality isolated to `const strings` and txt files when possible.
