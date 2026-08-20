# How to Migrate Schema Changes from Airtable

When you add, rename, or change fields in Airtable, follow these steps to propagate the changes through the pipeline into PostgreSQL.

---

## Step 1 — Run AirtableSchemaReader

This tool reads the live Airtable metadata API and generates an updated `airtable_schema.txt`.

```bash
cd D:\Projects\KLA\AirtableSchemaReader
dotnet run
```

Output: `AirtableSchemaReader\airtable_schema.txt`

> **Tip:** The previous schema file is kept as `old.airtable_schema.txt` for comparison. Diff the two files to confirm exactly which fields changed before proceeding.

---

## Step 2 — Identify What Changed

Compare the new and old schema files to find:
- New fields added to existing tables
- Fields renamed or removed
- New tables added
- **Existing fields whose `Type:` line changed** — these are the only ones that need manual work
  before the sync will run. See [Changing an existing field's type](#changing-an-existing-fields-type-manual-step-required) below.

The key tables used by the pipeline are: `ARTWORK`, `ARTWORK_IMAGE`, `ARTWORK_TYPE`, `SKETCH`, `PHOTO`, `PHOTO_CATAGORY`, `ARCHIVE`, `ARCHIVE_IMAGE`, `SOLD`.

---

## Step 3 — Copy the New Schema File to AirtableToPostgres

```
AirtableSchemaReader\airtable_schema.txt
  → AirtableToPostgres\airtable_schema.txt
```

Or check `AirtableToPostgres\appsettings.json` for `Schema:SchemaFilePath` — it may already point to a shared location.

---

## Step 4 — Run a Full Sync for Each Affected Table

The ETL system is **schema-driven**: it automatically generates `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` for every field in the schema file, so no code changes are needed for new fields.

```bash
cd D:\Projects\KLA\AirtableToPostgres

dotnet run -- sync ARTWORK full
dotnet run -- sync SKETCH full
dotnet run -- sync PHOTO full
dotnet run -- sync ARCHIVE full
dotnet run -- sync ARCHIVE_IMAGE full
```

Only run sync for tables that actually changed. Use `full` to ensure all records are updated with the new field values (not just recently modified ones).

The sync will:
1. Run `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` to add new columns to PostgreSQL
2. Fetch all records from Airtable and populate the new columns

---

## Changing an Existing Field's Type (manual step required)

Everything above covers **adding** fields and tables, which is fully automatic. **Changing the type
of a field that already exists is not.** The schema-driven DDL only ever emits
`CREATE TABLE IF NOT EXISTS` and `ADD COLUMN IF NOT EXISTS` — it never emits `ALTER COLUMN ... TYPE`.
So the PostgreSQL column keeps whatever type it was first created with, while the schema file now
says something else.

**How it fails.** If the new mapping is `JSONB` and the existing column is `TEXT`, the sync does not
silently mismatch — it errors out. `AddParameters` in `Program.cs` binds JSONB columns with an
explicit `NpgsqlDbType.Jsonb` parameter, and PostgreSQL rejects that against a text column:

```
42804: column "type" is of type text but expression is of type jsonb
```

Every row of that table fails. Other tables in the same run are unaffected.

**Before you change anything, verify the column has no dependants** (this is also a good read-only
sanity check that you are touching the right column):

```sql
SELECT column_name, data_type FROM information_schema.columns
  WHERE table_schema='public' AND table_name='<table>' AND column_name='<column>';
SELECT indexname, indexdef FROM pg_indexes WHERE schemaname='public' AND tablename='<table>';
SELECT conname, contype FROM pg_constraint WHERE conrelid='public.<table>'::regclass;
SELECT viewname FROM pg_views WHERE schemaname='public';
```

Run these with **RunSql** (`dotnet run -- "SELECT ..."`, read-only) or in DBeaver.

**Then pick one of two fixes:**

### Option A — let the column take the new type (preferred)

Airtable is the source of truth, so the data is re-populated by the next full sync. Drop the old
column and let the ETL recreate it:

```sql
ALTER TABLE <table> DROP COLUMN IF EXISTS <column>;
```

If you want the old values kept for comparison, rename instead of dropping
(`ALTER TABLE <table> RENAME COLUMN <column> TO <column>_old;`) and drop the copy once you are happy.
Writes need RunSql's admin gate (`dotnet run -- --admin "..."`) or DBeaver.

Then run `dotnet run -- sync <TABLE> full` and confirm the new type:

```sql
SELECT column_name, data_type FROM information_schema.columns
  WHERE table_schema='public' AND table_name='<table>';
```

### Option B — pin the old PostgreSQL type

Override the mapping in `AirtableToPostgres\appsettings.json` under `Schema:FieldMappings`, which
wins over the schema file:

```json
"FieldMappings": {
  "ARCHIVE": { "TYPE": "VARCHAR(255)" }
}
```

No DDL needed. For a `multipleRecordLinks` field pinned to `TEXT`/`VARCHAR`, `RecordMapper` stores
the first linked record ID as a plain string — the same approach already used for
`ARTWORK_IMAGE.ARTWORK_ID` and `SKETCH.ARTWORK_ID`.

### Worked example — `ARCHIVE.TYPE`, 2026-08-19

`ARCHIVE.TYPE` was changed in Airtable from `multilineText` to `multipleRecordLinks` (part of adding
the `ARCHIVE_TYPE` and `ARCHIVE_SUBTYPE` lookup tables), so its mapping moved from `TEXT` to `JSONB`
while `archive.type` in PostgreSQL was still `text`. The table held only test rows, so Option A was
used: `ALTER TABLE archive DROP COLUMN IF EXISTS type;` in DBeaver, then
`dotnet run -- sync ARCHIVE full`, after which `archive.type` came back as `jsonb` and all rows
loaded cleanly.

Related: `ARCHIVE.HUMAN_READABLE_ID` is an Airtable formula built from the `ARCHIVE_TYPE` code, the
`SUBTYPE` code and `TYPE_NUMBER` zero-padded to 4 (`<type>_<subtype>_<nnnn>`) — which is why `TYPE`
had to become a real record link rather than free text.

---

## Step 5 — Update ArtWorkHTML (if new fields should appear on the website)

If the new fields need to be displayed on the generated site, three things need updating in the `ArtWorkHTML` project:

1. **`ArtList.cs`** — Add new properties to the `Artwork` model
2. **SQL query in `GenerateArtworkPages.cs`** — Add `SELECT` for the new columns
3. **Relevant generator file** — Display the new data in the HTML output

If the fields are for internal/backend use only, skip this step.

---

## Step 6 — Run the Full Pipeline (if site needs updating)

```powershell
cd D:\Projects\KLA
.\build-and-deploy.ps1
```

Or start from step 4 (HTML generation) if only the site needs regenerating:

```powershell
.\build-and-deploy.ps1 -StartStep 4
```

---

## Notes

- `AirtableToPostgres` uses `Schema:UseCustomSchema = true` mode for this schema-driven approach. The legacy JSONB mode does not use the schema file.
- `createdTime` fields from Airtable map to `rec_create_dt` in PostgreSQL — the DDL generator handles this automatically.
- The `schema_overrides.json` file in `AirtableSchemaReader` can be used to exclude, rename, or change the type of fields before the schema file is generated (e.g. to exclude lookup/rollup fields that don't need to be stored).
