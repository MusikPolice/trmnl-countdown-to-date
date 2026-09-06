# trmnl-countdown-to-date

A private [TRMNL](https://usetrmnl.com) plugin that counts down to a configurable date,
showing the number of days remaining alongside an image identifying that date. No companion
app — all configuration happens via plugin custom fields in the TRMNL dashboard.

## What it shows

An image identifying the date (a greyscale line drawing you supply — see Data model below),
sized as large as possible within a consistent margin, with a single line below it naming the
number of days remaining until `target_date` and what it's counting down to (e.g. "16 days
until Canada Day"). `target_date` recurs annually — once it's passed this year, the countdown
rolls over to next year's occurrence.

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

`.trmnlp.yml` contains sample custom field values (`title`, `target_date`, `image_base64`)
used during local preview, plus a fixed `trmnl.system.timestamp_utc` so "today" is
reproducible. Update `timestamp_utc` when testing against a different date.

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

| Layout | Status | Description |
|---|---|---|
| Full (800×480) | complete | Image stacked above the label, image as large as possible |
| Half Horizontal (800×240) | complete | Image to the left of the label |
| Half Vertical (400×480) | complete | Image stacked above the label |
| Quadrant (400×240) | complete | Same as above, tightest margins |

## Data model

Custom fields, defined in `src/settings.yml` and configured per-user in the TRMNL dashboard:

| Field | Type | Notes |
|---|---|---|
| `title` | string | Name of the thing being counted down to, e.g. "Canada Day" |
| `target_date` | date | `YYYY-MM-DD`. Recurs annually |
| `image_base64` | text | Base64-encoded image shown above the countdown number |

## Known issues / roadmap

This started as a clone of an existing live plugin, with just enough fixed to get it
rendering correctly again. Planned follow-ups:

- Replace the manually-uploaded base64 raster image with a **generated greyscale SVG** that
  identifies the target date, instead of requiring the user to supply their own image. The
  current TRMNL CSS framework ([3.3 docs](https://trmnl.com/framework/docs/3.3)) adds themes
  and adaptive icons/charts that may be useful here.
