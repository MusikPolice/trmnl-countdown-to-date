# trmnl-countdown-to-date

A private [TRMNL](https://usetrmnl.com) plugin that counts down to a date, showing the number
of days remaining alongside an image identifying that date. No companion app — all
configuration happens via plugin custom fields in the TRMNL dashboard.

One instance holds **many** dates — Canada Day, Christmas, every family birthday, etc. — and
rotates through them, rather than one separate TRMNL plugin per date (which is how this
started, and was annoying to manage).

## What it shows

An image identifying the currently-selected date (a greyscale line drawing you supply — see
Data model below), sized as large as possible within a consistent margin, with a single line
below it naming the number of days remaining and what it's counting down to (e.g. "16 days
until Canada Day"). Every date recurs annually — once it's passed this year, its countdown
rolls over to next year's occurrence.

Which date is showing changes every 15 minutes, deterministically round-robining through
whichever configured dates are within `days_ahead_window` days out (default 100) — every
eligible date gets an even, non-repeating turn, unlike re-rolling a random pick each time.

Most dates recur annually (a birthday, a holiday), but one-off dates (a trip, a specific race)
are supported too — see Data model below.

## Local development

Requires [Docker Desktop](https://www.docker.com/products/docker-desktop/).

```powershell
# from the repo root
.\bin\serve.ps1
```

Then open `http://localhost:4567` in a browser. The server watches `src/` and `.trmnlp.yml`
for changes and reloads automatically.

**Switch the format dropdown from "PNG" to "HTML"** — the PNG preview renders via a headless
Firefox that doesn't display base64 `data:` URI images (this plugin's countdown image), even
though they render correctly in a real browser and on an actual device.

### Fixture data

`.trmnlp.yml` contains sample `dates`/`days_ahead_window` custom field values used during
local preview, plus a fixed `trmnl.system.timestamp_utc` so "today" is reproducible. Update
`timestamp_utc` when testing against a different date (and note it also determines which date
wins the 15-minute rotation — see Multi-date rotation below).

## Managing your dates

Don't hand-type the `Dates` field's JSON in the TRMNL dashboard. Instead:

1. Get a source image (a photo, or eventually the output of a planned greyscale line-art
   generator — see Known issues).
2. Normalize it: `.\bin\normalize-image.ps1 -InputPath <source> -OutFile dates/images/<name>.png`.
   Caps width at 600px (downscaling only) and converts to a true 8-bit grayscale PNG, so every
   image ends up a consistent size/format regardless of source. Reusable any time, not just for
   migration.
3. Copy `dates/manifest.example.json` to `dates/manifest.json` (gitignored, if it doesn't exist
   yet) and add an entry — `title`, `date` (see Data model below), and the image filename.
4. Run `.\bin\build-dates-field.ps1`. It validates each date, base64-encodes the (already
   normalized) images, writes `dates/dates.json`, and copies the result to your clipboard.
5. Paste that into the plugin's `Dates` custom field on the TRMNL dashboard.

Re-run steps 4-5 any time you add, remove, or change a date.

## Multi-date rotation

Every 15 minutes (matching `refresh_interval`), the plugin recomputes which configured date to
show: filter to whatever's within `days_ahead_window` days out (falling back to showing
everything if nothing currently qualifies), then deterministically round-robin through that
eligible set. See `CLAUDE.md` for the exact algorithm if you're modifying `shared.liquid`.

## Deployment

This is a private TRMNL plugin using the **static** strategy — there's no polling and no
webhook. All data comes from the custom fields you configure on the plugin's settings page
in the TRMNL dashboard.

### First-time setup

Copy `src/settings.example.yml` to `src/settings.yml` and set your plugin ID (the number at
the end of your plugin's URL on `trmnl.com`, e.g. `trmnl.com/plugin_settings/<ID>/edit`). This
file is gitignored — it contains your plugin ID and will be updated by `trmnlp pull`/`push`
with the full server response.

```powershell
# authenticate once (stores credentials in ~/.config/trmnlp)
docker run --rm -it `
  --volume "${PWD}:/plugin" `
  --volume "$env:USERPROFILE/.config/trmnlp:/root/.config/trmnlp" `
  trmnl/trmnlp login

# pull the current live plugin config into src/settings.yml
.\bin\pull.ps1

# push markup changes to your TRMNL plugin
.\bin\push.ps1
```

Credentials are stored in `~/.config/trmnlp/config.yml` (outside the repo). Both
`src/settings.yml` and the credentials file are gitignored.

## Layouts

All four layouts stack the image above the label, sized as large as possible and centered as a
group within the pane.

| Layout | Status | Notes |
|---|---|---|
| Full (800×480) | complete | |
| Half Horizontal (800×240) | complete | Tighter margins (240px tall) |
| Half Vertical (400×480) | complete | |
| Quadrant (400×240) | complete | Tighter margins (240px tall) |

## Data model

Two custom fields, defined in `src/settings.yml` and configured once in the TRMNL dashboard
(see Managing your dates above — don't hand-edit these directly):

| Field | Type | Notes |
|---|---|---|
| `dates` | code | JSON array of `{title, date, image_base64}` |
| `days_ahead_window` | number | Only rotate through dates within this many days out. Optional, defaults to 100 |

`date` is `"MM-DD"` (zero-padded, no year) for anything that recurs annually — e.g. `"07-01"`
for Canada Day — or `"YYYY-MM-DD"` for a one-off that only applies once, like a specific trip or
race (e.g. `"2026-03-07"`); one-offs are dropped automatically once they pass, rather than
rolling forward to next year like a recurring date would.

## Known issues / roadmap

This started as a clone of an existing live plugin, with just enough fixed to get it
rendering correctly again, then reworked from one-plugin-per-date into a single rotating
instance. Planned follow-ups:

- **Migration is done.** All 10 of the original "Countdown to X" instances have been
  consolidated into this single rotating instance and deleted.
- A **greyscale line-drawing generator** (producing nicer images than plain resized/grayscaled
  photos) is planned as its own separate project. A future small CLI to add one new date to the
  roster in a single step is also on the table — `dates/manifest.json`,
  `bin/normalize-image.ps1`, and `bin/build-dates-field.ps1` are kept as separate concerns for
  exactly this, so that CLI only needs to call the normalize script, append to the manifest, and
  re-run the build script.
- The current TRMNL CSS framework ([3.3 docs](https://trmnl.com/framework/docs/3.3)) adds
  themes and adaptive icons/charts that may be useful for the line-art generator above.
