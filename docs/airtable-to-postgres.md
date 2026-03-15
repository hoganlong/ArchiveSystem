# Airtable to PostgreSQL

This guide covers syncing your Airtable base to a PostgreSQL database using **AirtableSchemaReader** and **AirtableToPostgres**. You do not need AirtableImageDownloader or ArtWorkHTML for this path.

---

## Overview

The sync process is two steps:

1. **AirtableSchemaReader** reads your Airtable base schema and writes `airtable_schema.txt`
2. **AirtableToPostgres** reads that file and syncs records to PostgreSQL with typed columns

The schema file is the bridge between the two tools — AirtableToPostgres will not run without it.

---

## Step 1: Read the Schema

```bash
cd AirtableSchemaReader
dotnet run
```

This produces `airtable_schema.txt` in the project directory. Copy or symlink it to the `AirtableToPostgres` directory before running the sync.

### Schema Overrides

`schema_overrides.json` lets you customize how Airtable fields map to PostgreSQL columns without modifying code. Supported operations:

| Key | Effect |
|---|---|
| `exclude` | Omit this field from PostgreSQL entirely |
| `setType` | Override the inferred PostgreSQL column type |
| `rename` | Use a different column name in PostgreSQL |
| `setOptions` | Set allowed values for enum-like fields |
| `add` | Add a computed or virtual column not in Airtable |

Example:
```json
{
  "ARTWORK": {
    "LargeImageUrl": { "exclude": true },
    "Year": { "setType": "integer" },
    "Status": { "setOptions": ["Available", "Sold", "NFS"] }
  }
}
```

Re-run AirtableSchemaReader after making changes to `schema_overrides.json`.

---

## Step 2: Sync to PostgreSQL

### First run — full sync

On the first run, use full sync to load all records:

```bash
cd AirtableToPostgres
dotnet run -- full
```

This creates all tables (if they don't exist), then inserts every record from every Airtable table.

### Subsequent runs — incremental sync

After the initial load, use incremental sync for ongoing updates:

```bash
cd AirtableToPostgres
dotnet run
```

Incremental sync uses Airtable's `LAST_MODIFIED_TIME()` filter to fetch only records changed since the last sync. This is faster and uses fewer Airtable API calls.

### Other modes

```bash
dotnet run -- query      # interactive SQL REPL against your PostgreSQL database
dotnet run -- showall    # print all records to console
dotnet run -- diagnostic # print connection and config info
```

---

## How Tables Are Created

AirtableToPostgres creates one PostgreSQL table per Airtable table. Column types are derived from the schema file:

| Airtable field type | PostgreSQL type |
|---|---|
| Single line text, Long text | `text` |
| Number | `numeric` |
| Checkbox | `boolean` |
| Date | `date` |
| Single select | `text` (or enum if `setOptions` is set) |
| Linked record | `text[]` (array of record IDs) |
| Attachment | `jsonb` |

You can override any of these mappings with `schema_overrides.json`.

---

## Sync History

Every sync run is recorded in a `sync_history` table:

| Column | Description |
|---|---|
| `id` | Auto-increment run ID |
| `run_at` | Timestamp of the sync |
| `mode` | `full` or `incremental` |
| `table_name` | Which Airtable table was synced |
| `records_new` | Count of new records inserted |
| `records_updated` | Count of existing records updated |
| `records_unchanged` | Count of records with no changes |
| `error` | Error message, if the run failed |

This table is useful for auditing and debugging.

---

## Next Steps

- [adapting-for-new-artist.md](adapting-for-new-artist.md) — point the tools at a different Airtable base
- [configuration-reference.md](configuration-reference.md) — all appsettings.json fields
