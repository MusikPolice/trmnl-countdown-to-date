# CLAUDE.md

## Project

TRMNL private plugin that shows a countdown (in days) to a user-configured date, alongside
an image identifying that date. Unlike the iOS Reminders/Calendars plugins, this one has no
companion app — all input comes from plugin custom fields configured in the TRMNL dashboard,
and rendering uses the `static` strategy (no polling, no webhook).

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
| `src/quadrant.liquid` | 400×240 layout — number/label only, no image |
| `src/shared.liquid` | CSS + the countdown date math, included before all layout files |
| `src/settings.yml` | Plugin metadata — **gitignored**, contains plugin ID and custom field defs; updated by `trmnlp push`/`pull` |
| `src/settings.example.yml` | Committed template — copy to `settings.yml` and set your plugin ID |
| `.trmnlp.yml` | Dev server config and fixture custom-field values |
| `bin/serve.ps1` | Docker runner for `trmnlp serve` |
| `bin/push.ps1` | Docker runner for `trmnlp push` |
| `bin/pull.ps1` | Docker runner for `trmnlp pull` |

## Data model

This plugin has three custom fields (defined in `src/settings.yml`, configured per-user in the
TRMNL dashboard):

| Field (`trmnl.plugin_settings.custom_fields_values.*`) | Type | Notes |
|---|---|---|
| `title` | string | Name of the thing being counted down to, e.g. "Canada Day" |
| `target_date` | date | `YYYY-MM-DD`. Recurs annually — see below |
| `image_base64` | text | Base64-encoded image shown above the countdown number |

## Countdown logic (in `shared.liquid`)

`target_date` is treated as a **recurring annual date**: once this year's month/day has passed,
the countdown rolls over to next year's occurrence. This mirrors the original plugin's intent
(the live plugin is literally named "Countdown to Canada Day").

Day boundaries are computed from the viewer's local time, not server UTC:

```liquid
{% assign local_ts = trmnl.system.timestamp_utc | plus: trmnl.user.utc_offset %}
```

Never use `trmnl.system.timestamp_utc | date: ...` directly — see the iOS Reminders/Calendars
plugins for why (off-by-one day errors for negative UTC offsets).

`shared.liquid` assigns `days_until`, `countdown_title`, and `countdown_image` — every layout
file just displays these, it does not repeat the date math.

## Display constraints

- 800×480 px, 4 shades of gray only (black, dark gray, light gray, white)
- No color — use weight, size, and shade to convey hierarchy
- Font: Inter via Google Fonts — `<link>` tags and base `.screen` font-family are in `shared.liquid`

## Known issues / planned rework

This plugin was cloned from an existing live TRMNL plugin (ID 244316) as a starting point and
had several real bugs fixed just to get it rendering (malformed `{% assign %}` blocks with
stray `{{ }}` interpolation inside tags, and date math anchored to server "now" instead of the
viewer's local time). It still has rough edges the user plans to revisit:

- **Image is a manually-uploaded base64 raster**, not a generated greyscale SVG identifying the
  date. The end goal is an SVG (icon/illustration) chosen or generated based on the target date,
  not a per-user PNG upload.
- **`framework_version: 2.3.7`** — the TRMNL CSS framework is now at 3.3
  (https://trmnl.com/framework/docs/3.3), which adds themes, adaptive charts/icons, and a
  TRMNLPaint JS API that may be relevant to the SVG rework above.
- No `resources/` sample data or docs folder yet, since there's no webhook payload to fixture
  beyond the custom fields already in `.trmnlp.yml`.
