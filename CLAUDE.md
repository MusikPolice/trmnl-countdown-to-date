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
| `src/half_horizontal.liquid` | 800×240 layout — image left, label right |
| `src/half_vertical.liquid` | 400×480 layout |
| `src/quadrant.liquid` | 400×240 layout — tightest margins of the four |
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

`shared.liquid` assigns `days_until`, `countdown_title`, `countdown_image`, and the fully
composed `countdown_label` (e.g. "16 days until Canada Day", with correct day/days
pluralization) — every layout file just displays these, it does not repeat the date math or
string assembly.

## Display constraints

- 800×480 px, 4 shades of gray only (black, dark gray, light gray, white)
- No color — use weight, size, and shade to convey hierarchy
- Font: Inter via Google Fonts — `<link>` tags and base `.screen` font-family are in `shared.liquid`

## Image layout (the countdown-image class)

Every layout follows the same pattern: title bar, then a `layout` div (`layout--col` for
full/half_vertical/quadrant, `layout--row` for half_horizontal) with equal `p--{size}` padding
and `gap--[Npx]` between the image and the `countdown_label` line — padding and gap are always
set to the same pixel value, per the "consistent margin everywhere" requirement. The image gets
`image image--contain image-dither countdown-image` (`countdown-image--row-end` too, for
half_horizontal).

`countdown-image` (defined in `shared.liquid`) exists because the framework's own `stretch-x`/
`stretch-y` child utilities **do not reliably apply flex-grow along the layout's main axis** —
verified directly: correct classes were present on the element, but `.layout:where(:not(
.layout--row):not(.layout--col))>.stretch-y{flex:0 1 auto}` won the cascade instead of the
expected `.layout--col>.stretch-y{flex:1 1 0%}`, despite the element being a `.layout--col`
child (checked in `usetrmnl.com`'s shipped `plugins.css`, framework 3.3 — may be a genuine
framework bug, not something fixable from plugin markup). `countdown-image` sets `flex:1 1 0%`
explicitly so the image reliably grows to fill the exact leftover space after the label.

That flex-grow box can be a different aspect ratio than the image itself, and
`image--contain` letterboxes rather than crops — by default centering the empty space evenly on
both sides, which visibly separates the image from the label. `countdown-image` sets
`object-position: bottom` (bottom-hugging) so any letterbox slack collects near the title bar
instead, keeping the image flush against the label. `countdown-image--row-end` does the same for
half_horizontal's row axis, hugging the trailing edge (right, next to the label) instead.

**Quadrant's overflow quirk**: the framework computes each view's usable `.layout` height
internally (based on view type + title bar presence), and at quadrant's small size (400×240)
that computed height can run ~10px past the view's actual visible box — a rendering quirk of
the framework itself, not something this plugin's markup controls. Because the countdown-image
box always grows to consume exactly the leftover space, this shows up as the label clipping at
the bottom, and the fix is counter-intuitive: **increasing** padding (not decreasing it) is what
pulls the label back into the visible area, since the label's position is `(layout top + layout
height) − padding-bottom` — a value that gets *larger* (moves further off-screen) as padding
shrinks. Quadrant currently uses `p--3`/`gap--[12px]` for this reason, larger than its available
space would otherwise call for.

## Known issues / planned rework

This plugin was cloned from an existing live TRMNL plugin (ID 244316) as a starting point and
had several real bugs fixed just to get it rendering (malformed `{% assign %}` blocks with
stray `{{ }}` interpolation inside tags, and date math anchored to server "now" instead of the
viewer's local time). It still has rough edges the user plans to revisit:

- **Image is a manually-uploaded base64 raster**, not a generated greyscale SVG identifying the
  date. The end goal is an SVG (icon/illustration) chosen or generated based on the target date,
  not a per-user PNG upload.
- No `resources/` sample data or docs folder yet, since there's no webhook payload to fixture
  beyond the custom fields already in `.trmnlp.yml`.

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
