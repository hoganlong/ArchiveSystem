# Data Quality Checks — Future Project

A separate .NET project to query the PostgreSQL database for data problems and report on them.

## Planned Checks

- **Same image assigned to multiple artworks** — detect when the same filename or `artwork_image` record is referenced by more than one artwork
- **Images not assigned to any artwork** — detect `artwork_image` records (from Airtable) that have no corresponding artwork
- **Leading/trailing spaces in artwork filename** — detect rows in the `artwork` table where the `iFileName` column has leading or trailing whitespace (`iFileName != TRIM(iFileName)`)
- **W-type artworks missing back image** — count artworks with type code `W` (Wall hanging sculpture) that have no corresponding `artwork_image` record with `view = 'Back'`

- **HumanId sequence check** — for each year and type code in the artwork table, verify that the numbers start at 1 and increment without gaps (e.g. no skipping from 0042 to 0044)
- **Records deleted in Airtable but still in DB** — the sync never deletes; add a check that compares DB records against Airtable and reports any that exist in the DB but not in Airtable (per table). Optionally extend to support actual deletion.
- **Location "sold" but sold field is NULL** — detect artworks where `LOWER(TRIM(location)) = 'sold'` but the `sold` field is NULL; these are marked sold by location but have no sale record.
- **Broken/missing image references** — detect image references that don't resolve to an existing S3 object (an HTTP 403/404, vs 200 for a real file); these silently render as broken thumbnails on the site. Sources to check: `artwork_image.url`, `photo.file_location` (and the synthesized `sscan/KL_<code>_<image_number>` form), `artwork.filename`, `artlist_item.url`, `sketch.filename`. Could also be surfaced directly in the ArtWorkHTML end-of-run error summary. Example found 2026-06-19: a bogus `make error` value in `artwork_image.url` for KL_1976_W_0016 (fix at the Airtable source, then re-sync).

## Notes

- Will be a new project directory under `D:\Projects\claudetest\`
- Should output a report to console (and optionally a file)
- Uses the same PostgreSQL connection as `AirtableToPostgres` and `ArtWorkHTML`
