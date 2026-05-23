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

cd checks3vslocal && dotnet run                 # compare local vs S3
cd checks3vslocal && dotnet run -- --upload     # upload missing files to S3
cd checks3vslocal && dotnet run -- --hidelocal  # suppress "in S3 but not local" listing

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

### Help / discoverability

Every console tool in the workspace accepts a help flag and prints the full list
of commands and options for that tool. Any of `-h`, `--help`, `-?`, `/?`, or `?`
will print usage and exit 0:

```bash
cd <ProjectDir> && dotnet run -- --help
cd <ProjectDir> && dotnet run -- /?
```

An unrecognized flag (any unknown token starting with `-` or `/`) prints
`Unknown option: <flag>` followed by the same usage block and exits with code 1.
Positional arguments (paths, table names, S3 URIs, etc.) are passed through to
each tool's existing argument-handling logic unchanged.

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
| `RecordMapper.cs` / `TypeMapper.cs` | Maps Airtable field values to typed PostgreSQL values. Known Airtable types: `autoNumber`, `singleLineText`, `multilineText`, `number`, `currency`, `date`, `dateTime`, `createdTime`, `singleSelect`, `url`, `formula`, `count`, `multipleRecordLinks`, `multipleAttachments`, `multipleLookupValues`, `checkbox`. Unknown types log a warning and fall back to `TEXT` — add the mapping in `TypeMapper.cs` to fix |
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
| `ArtworkHTML.cs` | Main orchestrator — calls all page generators; also defines `ArtworkTypePages` (the per-type-page config list — drives the gallery generator, the index split button, and the statistics By-Type chart) |
| `ArtList.cs` | Data model for artwork records. `TryAttachBucketFile(name, ext, dbPrefix)` matches a bucket file to a DB artwork whose `FileName` is `<dbPrefix><name>` (e.g. `scans/<name>`) without creating a noDB entry on miss. The main `Artwork` constructor detects `FileName` starting with `scans/` and points its JPG URL at `scans/jpg/<basename>.jpg` instead of the default `jpg/<filename>.jpg` |
| `GenerateArtworkPages.cs` | Main gallery (`artwork.html`) plus per-type filtered pages (`artwork-canvas.html`, `artwork-drawing.html`, `artwork-jewelry.html`, `artwork-painting-noncanvas.html`, `artwork-sculpture-nonwall.html`, `artwork-wall-sculpture.html`) — add a new entry to `ArtworkTypePages` to generate another type page. The S3 bucket walk tries `TryAttachBucketFile(..., "scans/")` first for files under `scans/` and `scans/jpg/`; only files with no matching DB artwork fall through to sketchbook/polaroid/scans-page categorisation |
| `GenerateScansPage.cs` | Lists S3 scan files not in the database (`scans.html`) — populated only by bucket files that didn't match a DB artwork via the `scans/` prefix check |
| `GenerateStatisticsPage.cs` | Stats page; the By-Type chart links each row to its per-type page (single-code pages) and adds a rowspan "browse all" cell for multi-code pages (e.g. jewelry). Total Artworks counts every row (no date filter); Date Range uses a `FILTER (WHERE year > 1900)` so 1899/1900 placeholders don't poison the displayed range. By Year buckets year 1899 as "Not yet entered" and 1900 as "Unknown", both sorted after real years |
| `GenerateStylesheet.cs` | All CSS |
| `GenerateIndexPage.cs` | Home page; the "browse" nav button is a stateful split button — main click goes to the configured default (`DefaultBrowsePageFileName` constant), triangle opens a menu listing every `ArtworkTypePages` entry plus "Browse All Artworks", and the user's last selection persists in `localStorage` (`kla_browse_default`) |
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

Compares a local directory against an S3 bucket prefix. Reports files present locally but missing from S3, and (informationally) files in S3 that are not local. With `--upload`, uploads the missing-from-S3 files.

```bash
dotnet run -- <localPath> <s3Uri> [--upload] [--hidelocal]
```

Flags:
- `--upload` — upload files that exist locally but are missing from S3
- `--hidelocal` — suppress the "files in S3 but not local" informational section (useful when the S3 prefix has many files you don't have locally and only the upload direction matters)

Flags can be combined and given in any order. Positional `<localPath>` and `<s3Uri>` override the `appsettings.json` defaults (`S3:LocalPath`, `S3:S3Uri`, `S3:Region`).

---

## readawsbucket

Lists objects in the configured S3 bucket and writes them to a text file. Parameter-driven:

```bash
dotnet run -- <prefix> <outputFile> [format] [--unique] [--no-recurse]
```

- `prefix` — S3 prefix to filter (e.g. `scans/`; `""` for whole bucket)
- `outputFile` — text file to write the list to (one entry per line)
- `format` — line template, default `<prefix><filename><ext>`; tokens `<prefix>` (dir with trailing `/`), `<filename>` (base, no extension), `<ext>` (with leading dot)
- `--unique` — drop duplicate lines (preserves first-seen order)
- `--no-recurse` — list only files directly under the prefix; uses S3 `Delimiter="/"` so subdirectory keys aren't fetched

Example — produce a deduped list of base filenames directly under `scans/`:
```bash
dotnet run -- scans/ scanlist.txt "<filename>" --unique --no-recurse
```

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
