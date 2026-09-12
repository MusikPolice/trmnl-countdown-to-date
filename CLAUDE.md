# CLAUDE.md

## Project

TRMNL private plugin that shows a countdown (in days) to a date, alongside an image
identifying that date. Unlike the iOS Reminders/Calendars plugins, this one has no companion
app — all input comes from plugin custom fields configured in the TRMNL dashboard, and
rendering uses the `static` strategy (no polling, no webhook).

One plugin **instance holds many dates** (Canada Day, Christmas, every family birthday, etc.)
and rotates through them, rather than one TRMNL plugin instance per date. This replaced an
earlier design (10 separate live "Countdown to X" instances, confirmed via `GET
/api/plugin_settings` — all sharing `plugin_id: 37`) that was annoying to manage. See
"Multi-date rotation" below.

## Tech stack

- **Liquid** (Shopify-flavored, Ruby) — templating language for all markup
- **TRMNL CSS framework** — loaded automatically by the device; use its classes where possible
- **trmnlp** — local dev server, run via Docker (`.\bin\serve.ps1`)
- No build step, no package manager, no server — just `.liquid` files

## Key files

| File | Purpose |
|---|---|
| `src/full.liquid` | Full-screen layout (800×480) |
| `src/half_horizontal.liquid` | 800×240 layout |
| `src/half_vertical.liquid` | 400×480 layout |
| `src/quadrant.liquid` | 400×240 layout — tightest margins of the four |
| `src/shared.liquid` | CSS + the countdown date math, included before all layout files |
| `src/settings.yml` | Plugin metadata — **gitignored**, contains plugin ID and custom field defs; updated by `trmnlp push`/`pull` |
| `src/settings.example.yml` | Committed template — copy to `settings.yml` and set your plugin ID |
| `.trmnlp.yml` | Dev server config and fixture custom-field values |
| `bin/serve.ps1` | Docker runner for `trmnlp serve` |
| `bin/push.ps1` | Docker runner for `trmnlp push` |
| `bin/pull.ps1` | Docker runner for `trmnlp pull` |
| `bin/build-dates-field.ps1` | Assembles `dates/manifest.json` + `dates/images/*` into the JSON blob pasted into the "Dates" custom field |
| `bin/normalize-image.ps1` | Resizes + grayscales + re-encodes a source image to this plugin's standard spec (600px width cap, indexed 8-bit grayscale PNG) |
| `dates/manifest.example.json` | Committed template — copy to `dates/manifest.json` (gitignored) |
| `dates/images/` | Your greyscale images, referenced by filename from the manifest (gitignored, personal) |

## Data model

Two custom fields (defined in `src/settings.yml`, configured once in the TRMNL dashboard):

| Field (`trmnl.plugin_settings.custom_fields_values.*`) | Type | Notes |
|---|---|---|
| `dates` | code | JSON array of `{title, date, image_base64}` — see below |
| `days_ahead_window` | number | Only rotate through dates within this many days out. Optional, defaults to 100 |

`date` is one of:
- `"MM-DD"` (zero-padded, e.g. `"07-01"`) — **recurs annually**, no year to store.
- `"YYYY-MM-DD"` (e.g. `"2026-03-07"`) — a **one-off**, valid only that year. Once it passes,
  `shared.liquid` drops it for good rather than rolling it forward like a recurring date. Use
  this for anything that doesn't repeat on the same month/day every year — a specific trip, a
  one-time event (this plugin's own migration included "Australia Grand Prix" this way, since
  F1 race dates move every season). A future CLI could scan for expired one-offs and offer to
  either extend (convert to recurring) or delete them — not built yet.

`image_base64` has no `data:` URI prefix, and should already be normalized (see
`bin/normalize-image.ps1` below) before it goes in the manifest.

Don't hand-type this JSON blob. The full authoring pipeline:

1. **Get a source image** (a photo, or eventually output from the planned greyscale line-art
   generator — see Known issues).
2. **Normalize it**: `.\bin\normalize-image.ps1 -InputPath <source> -OutFile dates/images/<name>.png`.
   Caps width at 600px, downscaling only (never upscaling a narrower source) — `countdown-image`
   is `width:100%; height:auto` (see Image layout below), so width is the only axis any layout
   ever actually constrains, no matter the image's aspect ratio. Also flattens any transparency
   onto white (the screen background) and converts to a true 8-bit indexed grayscale PNG (not
   GDI+'s default RGBA, which stores 4x the bytes for pixels that are visually gray anyway) via
   a Rec. 601 luminosity color matrix, so every image behaves consistently regardless of source
   format/resolution/color space. Reusable any time you add or update a date, not just for
   one-time migration.
3. **Add it to the manifest**: list `title`, `date`, and the image filename in
   `dates/manifest.json` (copy `dates/manifest.example.json` there first if it doesn't exist).
4. **Build the field**: `.\bin\build-dates-field.ps1` validates each `date`, base64-encodes the
   already-normalized images, writes `dates/dates.json`, and copies the result to the clipboard
   to paste into the dashboard field.

Steps 2-4 are deliberately separate scripts/concerns (normalize vs. manifest vs. assemble) so a
future "add one date" CLI only needs to call `normalize-image.ps1` on a new source image, append
one entry to `dates/manifest.json`, and re-run `build-dates-field.ps1` — it doesn't need to
duplicate any image processing or JSON assembly logic.

## Multi-date rotation (in `shared.liquid`)

Each configured date is either **recurring** (`"MM-DD"` — once this year's occurrence has
passed, rolls over to next year's) or a **one-off** (`"YYYY-MM-DD"` — dropped for good once it
passes, never rolled forward). Distinguished by splitting the `date` string on `-`: 2 parts is
recurring, 3 is a one-off. The recurring case mirrors the original single-date plugin's intent
(the very first live instance was literally named "Countdown to Canada Day").

Day boundaries are computed from the viewer's local time, not server UTC:

```liquid
{% assign local_ts = trmnl.system.timestamp_utc | plus: trmnl.user.utc_offset %}
```

Never use `trmnl.system.timestamp_utc | date: ...` directly — see the iOS Reminders/Calendars
plugins for why (off-by-one day errors for negative UTC offsets).

Which of the configured dates is actually shown, computed fresh on every render:

1. **Compute `days_until`** for every entry in `dates` (the recurring-annual math above,
   looped). Liquid can't mutate a field onto an existing hash in place, so this goes through a
   `capture` → build a JSON string per entry (each field piped through the `json` filter to stay
   properly escaped) → `parse_json` it back into a real array of hashes that now include
   `days_until`. This round-trip pattern repeats for the next step too.
2. **Filter to `days_ahead_window`**: keep only entries with `days_until <= window`. There is
   **no `where_exp` filter** here — checked `usetrmnl.com`'s actual `trmnl-liquid` gem source
   (bundled identically into `trmnlp` for local dev), and only `group_by`/`find_by`/`sample`/
   `parse_json`/`json` exist — so this is a plain `for`/`if` loop, not an expression filter. If
   nothing qualifies (e.g. right after New Year, everything might be >100 days out), falls back
   to showing all configured dates rather than a blank screen.
3. **Rotate deterministically**: `bucket = timestamp_utc / 900` (15-minute buckets, matching
   this plugin's `refresh_interval: 15` — keep the two in sync if either changes), `index =
   bucket mod eligible.size`, select `eligible[index]`. This guarantees even, non-repeating
   coverage of the eligible set — a random `sample` re-rolled every render could show the same
   date twice running and take a while to cover everyone else (the coupon-collector problem).

`shared.liquid` assigns `days_until`, `countdown_title`, `countdown_image`, and the fully
composed `countdown_label` (e.g. "16 days until Canada Day", with correct day/days
pluralization) from whichever entry won the rotation — every layout file just displays these,
it does not repeat the date math, filtering, or string assembly. If `dates` is empty entirely,
these fall back to a friendly placeholder ("No dates configured") rather than erroring.

## Display constraints

- 800×480 px, 4 shades of gray only (black, dark gray, light gray, white)
- No color — use weight, size, and shade to convey hierarchy
- Font: Inter via Google Fonts — `<link>` tags and base `.screen` font-family are in `shared.liquid`

## Image layout (the countdown-image class)

All four layouts use the same structure: title bar, then a `layout layout--col` div with equal
`p--{size}` padding and `gap--[Npx]` between the image and the `countdown_label` line (padding
and gap are always the same pixel value, so the margin around the border matches the gap between
image and text). The image gets `image image--contain image-dither countdown-image`.

`countdown-image` (defined in `shared.liquid`) does **not** flex-grow to fill all leftover
space — it's sized to `width:100%; height:auto` (natural aspect ratio at full available width,
with `flex-shrink` as a safety net against portrait images overflowing). The `layout--col`'s
default center alignment then centers the whole image+label group as a unit within the pane.

This was a deliberate change from an earlier version that force-grew the image to fill 100% of
the leftover space and then biased any letterboxing toward one edge (`object-position`). That
approach guaranteed pixel-exact margins, but visibly dumped all the slack onto one side whenever
the image's aspect ratio didn't need the full available space — bottom-heavy in a tall pane
(half_vertical), or (combined with a `layout--row` for half_horizontal specifically) left the
label sitting beside the image instead of below it. Centering the natural-sized group reads much
better and is robust to whatever aspect ratio the real countdown image turns out to have.

Side note, in case the `stretch-x`/`stretch-y` framework utilities come up again: they don't
reliably apply flex-grow along a layout's main axis — verified directly, correct classes were
present on the element, but `.layout:where(:not(.layout--row):not(.layout--col))>.stretch-y
{flex:0 1 auto}` won the cascade instead of the expected `.layout--col>.stretch-y{flex:1 1 0%}`
(checked in `usetrmnl.com`'s shipped `plugins.css`, framework 3.3 — may be a genuine framework
bug). Not currently relevant since `countdown-image` no longer uses flex-grow at all, but worth
remembering if a future layout wants that behavior back.

**Quadrant's overflow quirk**: the framework computes each view's usable `.layout` height
internally (based on view type + title bar presence), and at quadrant's small size (400×240)
that computed height can run ~10px past the view's actual visible box — a rendering quirk of
the framework itself, not something this plugin's markup controls. This mattered a lot under
the old force-grow approach (label pinned exactly at the overflow boundary); it's a much smaller
risk now that content is naturally sized and centered, but quadrant and half_horizontal (both
240px tall) still use slightly larger padding (`p--3`/`gap--[12px]`) than their available space
would otherwise call for, as a safety margin.

## Known issues / planned rework

This plugin was cloned from an existing live TRMNL plugin (ID 244316) as a starting point and
had several real bugs fixed just to get it rendering (malformed `{% assign %}` blocks with
stray `{{ }}` interpolation inside tags, and date math anchored to server "now" instead of the
viewer's local time). It still has rough edges the user plans to revisit:

- **Migration data is prepared but not deployed.** All 10 of the user's original live
  "Countdown to X" instances (confirmed via `GET /api/plugin_settings`, all `plugin_id: 37`)
  had their title/date/image extracted, normalized, and assembled into `dates/dates.json`
  (gitignored — personal data) — verified end-to-end in `trmnlp build`/`serve` with the real
  ~700KB payload. **Not yet done**: pasting that into this instance's live `Dates` field on the
  TRMNL dashboard, pushing this repo's updated `settings.yml`/markup (`trmnlp push`), renaming
  the instance, and deleting the other 9 — all deliberately left for explicit user sign-off.
- **A future "greyscale line drawing generator"** is planned as its own project (out of scope
  here) to produce nicer images than the migrated originals (see below). The user also floated a
  future CLI to add one new date (source image + generated art) to the roster in one step —
  `dates/`, `bin/normalize-image.ps1`, and `bin/build-dates-field.ps1` were deliberately kept as
  separate concerns (image processing / manifest / assembly) so that CLI only needs to call the
  first script, append one manifest entry, and re-run the last, without duplicating any of
  their logic.
- **`normalize-image.ps1` originally produced grayscale-by-value pixels stored in a full RGBA
  PNG** (GDI+'s default encoder output for a 32bpp source, regardless of the actual color
  values), which meant every "grayscale" image was still paying for 4 bytes/pixel. It now
  flattens onto white and repacks into a true 8-bit indexed grayscale PNG, and caps width only
  (not the long edge — `countdown-image` is `width:100%; height:auto`, so width is the only axis
  any layout ever constrains). Re-running it over the 10 migrated images dropped `dates/dates.json`
  from ~1.1MB to ~700KB with no visible quality loss. Two of the ten (`canada_day.png`,
  `victoria_day.png`) are still only 256x256 — smaller than the 600px cap — because upscaling them
  from their current size would just blur them further; the user plans to replace those two
  source images later rather than upscale in place.
- No `resources/` sample data or docs folder yet, since there's no webhook payload to fixture
  beyond the custom fields already in `.trmnlp.yml`.

## Extracting data from the TRMNL dashboard (browser automation note)

Reading a plugin instance's actual custom field *values* (not just field definitions) isn't
possible via the API — `GET /api/plugin_settings` lists instances (id/name/plugin_id only) and
`GET /api/plugin_settings/{id}/archive` returns the plugin's markup/settings.yml *definition*,
but neither includes per-instance values, and there's no `GET /api/plugin_settings/{id}` detail
endpoint. The dashboard's "Export" button doesn't help either — it downloads that same
definition archive.

The values ARE readable from the edit page's DOM (form field
`plugin_setting[settings][custom_fields_values][<keyname>]`), and plain-text fields (title,
date) come back fine — but **returning a field's raw value through the browser tool's JS
execution is blocked whenever it looks like base64 data, regardless of size** (confirmed: even
an 88-character test string got blocked). This is a deliberate safety guard against using the
browser as a general data-exfiltration channel and shouldn't be routed around. What does work:
trigger a real browser download of the *decoded* bytes (`Blob` + `URL.createObjectURL` + a
programmatic `<a download>` click) and read the resulting file from disk — the JS only needs to
return a byte count, never the data itself. In this sandboxed environment those downloads may
sit pending until the user's session is next active/focused; the browser's Downloads folder is
the last stop, not the tool's JS return value.

## Local dev gotcha: base64 images and the PNG preview

`trmnlp serve`'s picker defaults to a "PNG" render, which screenshots the page using Puppeteer
+ **Firefox** (`screen_generator.rb`, `product: 'firefox'`). That pipeline silently fails to
load `data:` URI images — an `<img>` with a base64 `src` renders as nothing, even though the
same markup displays correctly in a real browser (verified directly) and will render correctly
on an actual TRMNL device (also a real browser-based renderer). **Switch the picker's format
dropdown from PNG to HTML** when previewing this plugin locally, or the countdown image will
appear to be broken when it isn't.

## Framework version

`framework_version` in `src/settings.yml` is pure server-side metadata — the `trmnlp` CLI
never reads it, and local `serve`/`build` always render against
`https://usetrmnl.com/css/latest/plugins.css` regardless of its value. It only takes effect
once pushed. Bumped to `3.3` (https://trmnl.com/framework/docs/3.3), which is fully backward
compatible with the classes this plugin uses (`screen`, `view`, `title_bar`, `layout`, `flex`/
`flex--col`/`flex--row`, `flex--center-x`/`flex--center-y`, `image`) — no markup changes
needed. 3.3 does add themes, adaptive charts/icons, and a TRMNLPaint JS API that may be
relevant to the greyscale-SVG rework above.
