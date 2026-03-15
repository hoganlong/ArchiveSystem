# Airtable Image Downloader

A standalone tool for downloading images from Airtable attachment fields to your local disk. No PostgreSQL database required.

---

## What It Does

AirtableImageDownloader connects to your Airtable base, finds all attachment fields across your tables, and downloads the image files to organized local directories. It is completely independent — it reads directly from Airtable and writes files to disk.

---

## Prerequisites

- .NET 10 SDK
- An Airtable Personal Access Token with `data.records:read` and `schema.bases:read` scopes

See [getting-started.md](getting-started.md) for setup details.

---

## Setup

1. Clone the repo and configure `appsettings.json`:

```bash
git clone https://github.com/hoganlong/AirtableImageDownloader
cd AirtableImageDownloader
cp appsettings.template.json appsettings.json
```

2. Edit `appsettings.json` with your values:

```json
{
  "AirtableApiKey": "your-personal-access-token",
  "AirtableBaseId": "appYourBaseIdHere",
  "ArtworkOutputPath": "images/artwork",
  "ArchiveOutputPath": "images/archive"
}
```

---

## Running

```bash
dotnet run
```

That's it. The tool will scan your base, find all attachment fields, and begin downloading.

---

## How Files Are Organized

Images are saved into subdirectories based on the source table:

```
images/
├── artwork/
│   ├── artwork_A001_full.jpg
│   ├── artwork_A001_large.jpg
│   └── artwork_A001_small.jpg
└── archive/
    ├── archive_B001_full.jpg
    └── archive_B001_large.jpg
```

**File naming:** `{prefix}_{recordId}_{size}.{ext}`

- `prefix` — derived from the table name (`artwork` or `archive`)
- `recordId` — the value of the `ID` field in the Airtable record
- `size` — one of three constants: `full` (main image), `small`, or `large` (Airtable thumbnail sizes)
- `ext` — file extension from the original file (`.jpeg` is normalized to `.jpg`)

Example filenames:
```
artwork_A001_full.jpg
artwork_A001_large.jpg
artwork_A001_small.jpg
```

---

## Resume Support

The downloader skips files that already exist on disk. If a run is interrupted, just run it again — it picks up where it left off without re-downloading completed files.

---

## Dynamic Field Discovery

Attachment field names are discovered automatically from the Airtable schema. You do not need to hard-code field names. If you add a new attachment field to your base, it will be picked up on the next run.

---

## Adapting for Your Base

Change only `AirtableApiKey` and `AirtableBaseId` in `appsettings.json`. The tool works with any Airtable base table that has attachment fields — no other changes needed.  (TODO: verify what happens with differtly named tables with images)

See [adapting-for-new-artist.md](adapting-for-new-artist.md) and [configuration-reference.md](configuration-reference.md) for more options.
