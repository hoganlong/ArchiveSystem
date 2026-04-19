# Archive System

A set of .NET 10.0 tools for syncing Airtable data to PostgreSQL (AWS RDS), downloading images, and generating a static HTML gallery.

This system was built for the [archive.keithlong.com](https://archive.keithlong.com) ([Keith Long Archive](https://github.com/hoganlong/keithlong)) but is designed to be adapted for any artist.

---

## What It Does

```
Airtable Base
       │
       ├─→ AirtableSchemaReader  → airtable_schema.txt
       ├─→ AirtableToPostgres    → PostgreSQL (AWS RDS)
       │                                │
       │                                └─→ ArtWorkHTML → static HTML gallery
       │                                                   (reads images from S3)
       └─→ AirtableImageDownloader → images/artwork/ and images/archive/
```

---

## Projects

### Core Pipeline

| Project | Purpose |
|---|---|
| `AirtableSchemaReader` | Reads your Airtable base schema and outputs `airtable_schema.txt` |
| `AirtableToPostgres` | Syncs Airtable tables to PostgreSQL with typed columns (incremental or full); uses `airtable_schema.txt` |
| `AirtableImageDownloader` | Downloads images from Airtable attachment fields to local disk |
| `checks3vslocal` | Compares a local image directory to an S3 bucket prefix; uploads missing files |
| `ArtWorkHTML` | Generates a static HTML gallery from PostgreSQL data + S3 images |

### Utility Tools

| Project | Purpose |
|---|---|
| `getspecialimages` | Downloads artwork images missing a front-view from S3, renaming them to HumanId format |
| `CheckPhotoList` | Verifies Airtable PHOTO table records against local manifests and S3 bucket |
| `readawsbucket` | Lists S3 bucket contents with file sizes and metadata |
| `fixcsv` | One-off CSV normalizer: fixes headers and strips `.tif` extensions from filename fields |

### Pipeline Scripts

| Script | Purpose |
|---|---|
| `build-and-deploy.ps1` | Runs all 6 pipeline steps in sequence; prompts before deploying to AWS; supports `-StartStep`/`-StopStep` to run a subset |

---

## Three Ways to Use This System

### Path A — Airtable to PostgreSQL only
You want to sync your Airtable base to a PostgreSQL database. You don't need images or HTML.

→ Start here: [docs/airtable-to-postgres.md](docs/airtable-to-postgres.md)

### Path B — Image download only
You want to extract and download images from your Airtable attachment fields to local disk. No database required.

→ Start here: [docs/airtable-image-downloader.md](docs/airtable-image-downloader.md)

### Path C — Full artist archive pipeline
You want the complete system: database sync, image downloads, and a generated HTML gallery.

→ Start here: [docs/getting-started.md](docs/getting-started.md)
→ Then follow: [docs/full-system-guide.md](docs/full-system-guide.md)

---

## Adapting for a Different Artist

→ [docs/adapting-for-new-artist.md](docs/adapting-for-new-artist.md)

## Configuration Reference

→ [docs/configuration-reference.md](docs/configuration-reference.md)

## Technical Reference (build commands, architecture details)

→ [technical-reference.md](technical-reference.md)
