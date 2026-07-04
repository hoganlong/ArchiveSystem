# How to Migrate Schema Changes from Airtable

When you add, rename, or change fields in Airtable, follow these steps to propagate the changes through the pipeline into PostgreSQL.

---

## Step 1 — Run AirtableSchemaReader

This tool reads the live Airtable metadata API and generates an updated `airtable_schema.txt`.

```bash
cd D:\Projects\claudetest\AirtableSchemaReader
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
cd D:\Projects\claudetest\AirtableToPostgres

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

## Step 5 — Update ArtWorkHTML (if new fields should appear on the website)

If the new fields need to be displayed on the generated site, three things need updating in the `ArtWorkHTML` project:

1. **`ArtList.cs`** — Add new properties to the `Artwork` model
2. **SQL query in `GenerateArtworkPages.cs`** — Add `SELECT` for the new columns
3. **Relevant generator file** — Display the new data in the HTML output

If the fields are for internal/backend use only, skip this step.

---

## Step 6 — Run the Full Pipeline (if site needs updating)

```powershell
cd D:\Projects\claudetest
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
