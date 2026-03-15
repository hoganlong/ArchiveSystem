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

cd ArtWorkHTML && dotnet run               # default: generate all HTML pages
cd ArtWorkHTML && dotnet run -- gen-static # generate static pages only (no DB required)
```
Additional Command line options (not needed in standard build process)

```bash
cd AirtableToPostgres && dotnet run -- query # interactive SQL REPL
cd AirtableToPostgres && dotnet run -- showall
cd AirtableToPostgres && dotnet run -- diagnostic


cd ArtWorkHTML && dotnet run -- test-db    # test PostgreSQL connection
cd ArtWorkHTML && dotnet run -- test-airtable # test Airtable connection
```

Root-level batch scripts (in the keithlong repo):
- `etl.bat` — runs AirtableToPostgres sync
- `makeweb.bat` — runs ArtWorkHTML generator

---

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
- File naming: `{prefix}_{recordId}_{size}.{ext}` (e.g., `artwork_rec123_1920x1080.jpg`)
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

## Airtable Tables (Keith Long Archive)

`ARTWORK`, `ARTWORK_IMAGE`, `PHOTO`, `SOLD`, `ARCHIVE`, `ARCHIVE_IMAGE`, `ARTWORK_TYPE`, `PHOTO_CATEGORY`, `SKETCH`

---

## Code Style

- .NET 10.0, C#, implicit usings, nullable reference types enabled
- 2-space indentation
- Async/await throughout
- `Newtonsoft.Json` for JSON, `Npgsql` for PostgreSQL, `AWSSDK.*` for AWS
