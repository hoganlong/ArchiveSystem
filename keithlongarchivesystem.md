# Keith Long Archive System — Workspace Overview

A developer overview of every project in the workspace and how they fit together.

## Overview

This workspace manages the **Keith Long Archive** — a system to sync artwork metadata from Airtable to PostgreSQL (AWS RDS), download artwork images, and generate a static HTML website gallery. Each project is its own git repo, cloned as a sibling under one workspace root (`D:\Projects\KLA`). The tools are independent .NET 10.0 console apps, except `website-stats-lambda` (Python, AWS Lambda).

## Projects

| Project | Purpose |
|---|---|
| `AirtableSchemaReader/` | Reads and outputs the Airtable base schema |
| `AirtableToPostgres/` | Syncs Airtable tables to PostgreSQL (incremental or full) |
| `AirtableImageDownloader/` | Downloads images from Airtable attachment fields |
| `CheckS3vsLocal/` | Compares a local image directory to an S3 prefix; uploads missing files |
| `ArtWorkHTML/` | Generates static HTML gallery from PostgreSQL + S3 images |
| `ArchiveSystem/` | Docs hub + PowerShell pipeline scripts (`scripts/build-and-deploy.ps1`, `fix-my-ip.ps1`, …) |
| `RunSql/` | Ad-hoc Postgres query console — read-only by default, `--admin` for writes |
| `GenPageTool/` | Builds one standalone HTML page from a text template of artwork ids (not part of the site build) |
| `CheckPhotoTifs/` | Verifies that photo-table TIFs exist in S3 |
| `CheckPhotoList/` | Verifies Airtable PHOTO records against local manifests and S3 |
| `CsvToAirtable/` | Imports a CSV into an Airtable table, including linked-record fields |
| `getspecialimages/` | Downloads artwork images missing a front view, renamed to HumanId |
| `readawsbucket/ReadAwsBucket/` | Lists S3 bucket contents |
| `tif2jpg/` | Generates derived (sized) JPGs from S3 TIFs |
| `rotate/` | Rotates a JPG/TIF on S3 losslessly by 90/180/270° |
| `fixcsv/` | One-off CSV normalizer |
| `website-stats-lambda/` | Daily website-traffic email (AWS Lambda + EventBridge Scheduler) |

## Build & Run Commands

Each project is independent. Run from the project directory:

```bash
cd AirtableToPostgres && dotnet run          # default: incremental sync
cd AirtableToPostgres && dotnet run -- full  # full sync all tables
cd AirtableToPostgres && dotnet run -- sync ARTWORK [full]  # one table
cd AirtableToPostgres && dotnet run -- query # interactive SQL REPL
cd AirtableToPostgres && dotnet run -- deleted [TABLE]      # rows deleted in Airtable
cd AirtableToPostgres && dotnet run -- showall
cd AirtableToPostgres && dotnet run -- diagnostic <FIELD>
cd AirtableToPostgres && dotnet run -- -v    # -v / --verbose works with any command

cd AirtableImageDownloader && dotnet run
cd AirtableSchemaReader && dotnet run
cd ArtWorkHTML && dotnet run
cd readawsbucket/ReadAwsBucket && dotnet run
cd RunSql && dotnet run -- "SELECT ..."
```

The full pipeline (schema → ETL → images → HTML → deploy) is
`ArchiveSystem/scripts/build-and-deploy.ps1`, also reachable as a symlink at the workspace root.

Every CLI tool in this workspace accepts `-h`, `--help`, `-?`, `/?`, or `?` to print
its full list of commands and options. Unknown flags (any token starting with `-` or
`/` that isn't recognized) print `Unknown option: <flag>` followed by usage, and exit 1.

## Architecture

### Data Flow
```
Airtable Base
       │
       ├─→ AirtableSchemaReader → airtable_schema.txt
       ├─→ AirtableToPostgres  → PostgreSQL (AWS RDS)
       │                              │
       │                              └─→ ArtWorkHTML → artwork_html/ (static site)
       │                                               └─→ reads images from S3
       └─→ AirtableImageDownloader → images/artwork/ and images/archive/
```

### AirtableToPostgres — Key Components
- `Program.cs` — Entry point, command dispatch
- `SchemaGenerator.cs` / `SchemaParser.cs` — Reads `airtable_schema.txt` and creates typed PostgreSQL columns (not generic JSONB)
- `RecordMapper.cs` / `TypeMapper.cs` — Maps Airtable field values to typed PostgreSQL values
- `ChangeDetector.cs` — Classifies records as NEW / UPDATED / UNCHANGED for incremental sync
- `SyncHistoryLogger.cs` — Writes every sync operation to a `sync_history` table
- Incremental sync uses Airtable's `LAST_MODIFIED_TIME()` filter for performance

### ArtWorkHTML — Key Components
Uses C# partial classes, one file per page type:
- `GenerateArtworkPages.cs` — Main gallery (`artwork.html`) plus per-type filtered pages (`artwork-canvas.html`, `artwork-collage.html`, `artwork-drawing.html`, `artwork-jewelry.html`, `artwork-painting-noncanvas.html`, `artwork-sculpture-nonwall.html`, `artwork-study-sketch.html`, `artwork-wall-sculpture.html`) — driven by the `ArtworkTypePages` list in `ArtworkHTML.cs`; add an entry there to generate another type page. Bucket walk now tries to match files under `scans/` and `scans/jpg/` against DB artworks whose `FileName` starts with `scans/` before falling through to the scans-page categorisation. Each artwork also renders any linked photo-table images as thumbnails and gets a visible `photo` tag when it has photos. Also emits `errors.html`, a gallery of just the artworks that have one or more errors
- `GenerateScansPage.cs` — S3 scan files not in the database (only the files that didn't match a `scans/`-prefixed DB artwork), split by filename prefix: a `scanslist.html` hub with a count per prefix, one `scans-{prefix}.html` page per entry in `ScanPrefixes` (case-insensitive match on the bucket basename), and `scans.html` for the "Other" leftovers. All `noindex`. Photos are kept off this page via `LoadShowImageBasenamesAsync` (see GenerateShowsPage), except Exhibition photos (`photo_catagory.code = 'E'`) not yet referenced by a show
- `GenerateShowsPage.cs` — Shows index (`shows.html`) + per-show detail pages (`shows/show-{id}.html`). Also owns `LoadShowImageBasenamesAsync`, the set of photo/show image basenames excluded from the scans page
- `GeneratePhotoPages.cs` — Photos index (`photo.html`, one button per `photo_catagory` with counts) + per-category detail pages (`photo/{category}.html`) showing each photo with date/year/people/location/notes; image URL is `file_location` or synthesized `sscan/KL_{code}_{image_number}`. Generates an "Uncategorized" page only when such photos exist
- `GenerateStatisticsPage.cs` — Stats page. Total Artworks counts every row (date filter dropped); the date-range card uses a `FILTER` so 1899/1900 placeholders don't poison min/max. By Year shows 1899 as "Not yet entered" and 1900 as "Unknown". The By-Type chart links each row to its per-type page, plus a rowspan "browse all" cell for multi-code groups (jewelry). Has a Photos section (Total Photos / Categories / Year Range + per-category table). All "Browse All …" buttons pass `back=statistics.html&backlabel=Return+to+Statistics`
- `GenerateStylesheet.cs` — All CSS
- `GenerateIndexPage.cs` — Home page; the browse nav button is a stateful split button (main click goes to `DefaultBrowsePageFileName`, triangle drops down `ArtworkTypePages` + "Browse All Artworks", selection persists in `localStorage` as `kla_browse_default`). Carries an "Admin only" link to `admin.html`; the Polaroids and Scans buttons were moved off the home page onto the admin page
- `GenerateAdminPage.cs` — `admin.html`, a password-gated admin/development page (client-side **soft** gate only — the SHA-256 hash and validation JS are visible in page source, so it is NOT real security; real auth must be server-side). Consolidates the dev links (Errors, Polaroids, Scans → `scanslist.html`, Archive, Hidden Sketchbooks) and renders the current run's error summary below the buttons
- `GenerateHowIsMadePage.cs`, etc. — Other supporting pages
- `GenerateHelpPage.cs` — `help.html`; accepts optional `List<int>? years` to render a Find section with year/type dropdowns that navigate to `artwork.html?show={HumanId}`
- `ArtList.cs` — Data model for artwork records
- `GenerateArchivePages.cs` — `archive.html`, an admin page listing each `archive` record with its `archive_image` views; `archive_image` URLs are also kept off the scans pages
- `GenerateErrorsPage.cs` — `errors.html` + per-error-type detail pages
- Reads from PostgreSQL tables: `artwork`, `artwork_image`, `artwork_type`, `sketch`, `photo`, `photo_catagory`, `show`, `artlist`, `artlist_item`, `archive`, `archive_image`
- **HumanId format**: `KL_{year}_{typeCode}_{number}` — 4-digit year, single-letter type code (W/D/S/C/J/P/B/N/T/L; T = Study / Sketch, L = Collage), number zero-padded to 4 digits. Example: `KL_1982_D_0042`

### AirtableSchemaReader
- Outputs schema to `airtable_schema.txt` (consumed by AirtableToPostgres)
- `schema_overrides.json` supports: `exclude`, `setType`, `rename`, `setOptions`, `add`

## Configuration

Each project has its own `appsettings.json`. Use `appsettings.template.json` as a starting point where available. PostgreSQL credentials are retrieved at runtime from AWS Secrets Manager — not stored in config files.

## Airtable Tables

ARTWORK, ARTWORK_IMAGE, PHOTO, SOLD, ARCHIVE, ARCHIVE_IMAGE, ARTWORK_TYPE, PHOTO_CATEGORY, SKETCH

## Code Style

- .NET 10.0, C#, implicit usings, nullable reference types enabled
- 2-space indentation
- Async/await throughout
- `Newtonsoft.Json` for JSON, `Npgsql` for PostgreSQL, `AWSSDK.*` for AWS
