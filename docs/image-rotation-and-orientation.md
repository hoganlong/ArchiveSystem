# Image Rotation & Orientation

How to rotate scan images on S3 and keep their derived JPGs in sync, plus the
EXIF/TIFF **orientation-tag** gotcha that makes this trickier than it looks.

The archive stores master **TIF** scans on S3 (`scans/`, `sscan/`) and serves
derived **JPG**s from a sibling `jpg/` folder (`scans/jpg/`, `sscan/jpg/`). The
`scans/` layout is **flat** (one `<base>.jpg` per TIF); the `sscan/` layout is
**sized** (`<base>_small/_large/_full.jpg`).

---

## The orientation-tag gotcha

Some scan TIFs carry an embedded EXIF/TIFF **orientation tag** (e.g. `8` =
"display rotated 270°"). The raw pixels are *not* upright — an orientation-aware
viewer applies the tag to display them correctly.

Any tool that decodes such a TIF and writes derived output must **apply the tag
to the pixels first** (`AutoOrient()`), or it operates on the raw, un-rotated
pixels and produces a silently mis-rotated result. Both tools below now do this.

> **A tag can lie.** `AutoOrient()` is only correct when the tag matches the
> pixels. At least one file (`scans/pds_003.tif`) had a **bogus** tag on
> already-upright pixels — auto-orienting it would rotate a correct image to
> wrong. When you find one, fix the *tag* at the source instead of rotating (see
> [Fixing a bogus tag](#fixing-a-bogus-orientation-tag)).

---

## Tools

### rotate180 (.NET) — [github.com/hoganlong/rotate](https://github.com/hoganlong/rotate)
Rotates a single JPG or TIF on S3 losslessly by 90 / 180 / 270° clockwise.
```
dotnet run -- s3://bucket/prefix/file.tif --angle 90            # preview locally as rot90_<file>
dotnet run -- s3://bucket/prefix/file.tif --angle 90 --upload   # overwrite the S3 key
```
- JPG → `jpegtran` (DCT-block transform, zero re-encode; `-trim` drops the
  partial edge strip on non-MCU-aligned images).
- TIF → Magick.NET: `AutoOrient()` then `Rotate(angle)`, so the output has a
  normalized orientation tag and baked-in rotation.
- `--upload` overwrites the S3 key with **no backup** — preview first.

### tif2jpg (.NET) — [github.com/hoganlong/tif2jpg](https://github.com/hoganlong/tif2jpg)
Generates the derived JPG(s) for TIFs that are missing them.
```
dotnet run -- s3://bucket/scans/ --flat --create --upload    # flat layout
dotnet run -- s3://bucket/sscan/ --create --upload           # sized layout
```
Calls `AutoOrient()` after loading each TIF, so the JPGs match how the TIF
displays. Only rebuilds **missing** JPGs — delete the stale ones first to force
regeneration.

### check-tif-orientation.ps1 — `scripts/`
Lists every TIF under an S3 prefix whose orientation tag is not normal, reading
only ~16 bytes + ~4 KB per file (ranged S3 GETs — no full download).
```powershell
.\scripts\check-tif-orientation.ps1 -Prefix "sscan/"   # or -Prefix "" for the whole bucket
```
It flags tags but can't tell accurate from bogus — eyeball the flagged ones.

### rotate-tif-and-jpg.ps1 — `scripts/`
End-to-end helper: rotate one or more TIFs **and** refresh their derived JPGs.
```powershell
.\scripts\rotate-tif-and-jpg.ps1 -Jobs "scans/KLA_02_110.tif=90","sscan/KL_E_41.tif=270"
```
Per run it: (1) opens a **preview** montage (current vs. proposed rotation, built
from the small JPG) for you to verify; (2) confirms, then rotates the TIF(s) via
rotate180 `--upload`; (3) deletes the stale JPG(s), auto-detecting sized vs. flat;
(4) asks **regenerate now? (y/n)** — one `tif2jpg` run covers all prefixes, and if
you decline it prints the exact command(s) to run later.

Flags: `-DryRun` (plan only, no changes), `-NoPreview`, `-AssumeYes`,
`-Bucket` / `-Region`.

---

## Recommended process

1. **Check** the target TIFs for a pre-existing orientation tag:
   `.\scripts\check-tif-orientation.ps1 -Prefix "<prefix>/"`.
2. **Rotate + refresh** with the helper (preview → confirm → rotate → regen):
   `.\scripts\rotate-tif-and-jpg.ps1 -Jobs "<key>=<angle>", ...`.
3. If the preview shows a rotation off the wrong baseline, the TIF has a bogus
   tag — stop and fix the tag instead (below).

Rotate the **TIF first, then re-derive the JPGs** so they always match the
canonical master. Rotation is clockwise; 270° CW = 90° CCW.

---

## Fixing a bogus orientation tag

When the pixels are already upright but the tag says otherwise, don't rotate —
just reset the tag. Patch TIFF IFD tag `274` (orientation) to `1` in place: a
2-byte, endianness-aware edit at the tag's value offset — no pixel re-encode —
then re-upload. The existing (correct) JPG can stay; future regeneration becomes
a safe no-op. (Done once for `scans/pds_003.tif`.)

---

## Script locations

The PowerShell helpers live in **`scripts/`** in this repo (their tracked home),
alongside `build-and-deploy.ps1`. They reference the project `.csproj` paths by
absolute path, so they run from anywhere. For convenience they can be symlinked
into the workspace root (Windows Developer Mode or an elevated shell required to
create the symlink) — edit the tracked copy in `scripts/`, not the root symlink.
