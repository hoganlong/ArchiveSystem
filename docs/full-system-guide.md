# Full System Guide

End-to-end walkthrough for running the complete archive pipeline: schema reading, database sync, image downloads, and HTML generation.

Before starting, complete [getting-started.md](getting-started.md).

---

## Pipeline Overview

Run the tools in this order. Each step's output feeds the next:

```
Step 1: AirtableSchemaReader     →  airtable_schema.txt
Step 2: AirtableToPostgres       →  PostgreSQL database (populated)
Step 3: AirtableImageDownloader  →  images/ on local disk
Step 4: CheckS3vsLocal           →  uploads missing images to S3
Step 5: ArtWorkHTML              →  artwork_html/ (static site)
```

---

## Step 1: Read the Airtable Schema

```bash
cd AirtableSchemaReader
dotnet run
```

**Output:** `airtable_schema.txt`

**When to re-run:** Whenever your Airtable base schema changes (new tables, new fields, renamed fields). You must also re-run AirtableToPostgres with `-- full` after a schema change.

**Customization:** Edit `schema_overrides.json` to exclude fields, override types, or rename columns before they reach PostgreSQL. See [airtable-to-postgres.md](airtable-to-postgres.md#schema-overrides) for details.

---

## Step 2: Sync to PostgreSQL

Copy or symlink `airtable_schema.txt` into the `AirtableToPostgres` directory, then:

### First run (full sync)

```bash
cd AirtableToPostgres
dotnet run -- full
```

Creates all PostgreSQL tables and loads all records.

### Ongoing runs (incremental sync)

```bash
cd AirtableToPostgres
dotnet run
```

Fetches only records changed since the last sync. Much faster than a full sync.

**Output:** All Airtable tables are mirrored in PostgreSQL. A `sync_history` table records each run.

**Dependency:** Requires `airtable_schema.txt` from Step 1.

---

## Step 3: Download Images

```bash
cd AirtableImageDownloader
dotnet run
```

**Output:** Images saved to `images/artwork/` and `images/archive/`

**File naming:** `{prefix}_{recordId}_{size}.{ext}` — size is one of `full`, `large`, or `small` (e.g., `artwork_A001_full.jpg`)

**Resume support:** Already-downloaded files are skipped. Safe to re-run.

**Dependency:** Reads directly from Airtable (not PostgreSQL). Can run independently of Steps 1–2, but is typically run after the database sync so your local state is consistent.

---

## Step 4: Sync Images to S3

```bash
cd CheckS3vsLocal
dotnet run -- --upload
```

**Output:** Any local images not yet in S3 are uploaded.

**Resume support:** Already-uploaded files are skipped. Safe to re-run.

**Dependency:** Requires the local images directory from Step 3 and AWS credentials configured. Set `LocalPath` and `S3Uri` in `appsettings.json` or pass them as arguments:

```bash
dotnet run -- C:\path\to\images s3://your-bucket/prefix/ --upload
```

---

## Step 5: Generate HTML

```bash
cd ArtWorkHTML
dotnet run
```

**Output:** Static HTML files in `artwork_html/`

**Dependency:** Reads from the PostgreSQL database populated in Step 2. Image URLs in the database point to S3 — images must be uploaded to S3 separately (or you can adapt the HTML generator to point at local files).

**Keith-Long-specific content:** Page templates, CSS, and navigation are tailored to the Keith Long Archive. See [adapting-for-new-artist.md](adapting-for-new-artist.md) for what to change.

---

## Running the Full Pipeline

For routine use, run Steps 2–5 together. Step 1 only needs to run when the schema changes.

```bash
cd AirtableToPostgres && dotnet run       # incremental sync
cd AirtableImageDownloader && dotnet run  # download new/changed images
cd CheckS3vsLocal && dotnet run -- --upload  # upload missing images to S3
cd ArtWorkHTML && dotnet run              # regenerate HTML
```

The batch scripts in the keithlong repo (`etl.bat`, `makeweb.bat`) automate parts of this.

---

## Dependency Summary

| Tool | Depends on |
|---|---|
| AirtableSchemaReader | Airtable API only |
| AirtableToPostgres | Airtable API + `airtable_schema.txt` |
| AirtableImageDownloader | Airtable API only (independent) |
| CheckS3vsLocal | Local image directory + AWS credentials |
| ArtWorkHTML | PostgreSQL database |
