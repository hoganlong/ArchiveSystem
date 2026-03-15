# Adapting for a Different Artist

This guide explains what to change to point the Archive System at a different Airtable base or artist archive.

---

## AirtableSchemaReader and AirtableToPostgres

These tools are fully generic — they have no hard-coded table or field names.

### appsettings.json

Change these two values to point at your base:

```json
{
  "AirtableApiKey": "your-personal-access-token",
  "AirtableBaseId": "appYourBaseIdHere"
}
```

That's all. The tools will read whatever tables and fields exist in that base.

### schema_overrides.json

The overrides file is also not artist-specific. You define overrides per table name, and the table names come from your base. Start with an empty object and add entries as needed:

```json
{}
```

Common reasons to add overrides:
- A field has a name that is awkward as a PostgreSQL column name → use `rename`
- A number field contains integers, not decimals → use `setType: "integer"`
- A field is large and you don't need it in the database → use `exclude`

---

## AirtableImageDownloader

This tool discovers attachment fields dynamically from the Airtable schema — there are no hard-coded field names. Change the base ID and API key in `appsettings.json` and it will find and download images from all attachment fields in all tables.

### What you may want to customize

- **Output directories**: By default images go to `images/artwork/` and `images/archive/`. You can change these folder names in `appsettings.json` or the source.
- **Table filter**: If your base has many tables and you only want images from some of them, add a table filter in `appsettings.json`.

---

## ArtWorkHTML

This is the most artist-specific component. It was built for the Keith Long Archive and contains content and structure that reflects that.
(TODO: Move all content to txt files so removing or changing artist specific is a file copy operation.)

### What is generic
- The mechanism for reading from PostgreSQL and rendering HTML
- The CSS structure and grid layout
- The partial class architecture (one file per page type)

### What is Keith-Long-specific
- Page titles, descriptions, and navigation text
- The specific PostgreSQL tables it queries: `artwork`, `artwork_image`, `artwork_type`, `sketch`
- The statistics page (counts by year, medium, type)
- The "How It's Made" page
- Image URLs pointing to the Keith Long S3 bucket

### Adapting it

To use ArtWorkHTML for a different artist:

1. Update `appsettings.json` with your PostgreSQL connection details
2. Edit the table names in each `Generate*.cs` file to match your schema
3. Update page titles, navigation, and any artist-specific text in the HTML templates
4. Update the S3 bucket name or image URL pattern

If your archive has a significantly different structure (different tables, different relationships), ArtWorkHTML will need more substantial changes. The Airtable-to-PostgreSQL tools are easier to adapt than the HTML generator.

---

## Summary: What Needs Changing per Tool

| Tool | What to change |
|---|---|
| AirtableSchemaReader | `appsettings.json` (API key, base ID) |
| AirtableToPostgres | `appsettings.json` (API key, base ID, DB connection); optionally `schema_overrides.json` |
| AirtableImageDownloader | `appsettings.json` (API key, base ID); optionally output folder names |
| ArtWorkHTML | `appsettings.json` (DB connection); source files for table names, page text, and HTML structure |
