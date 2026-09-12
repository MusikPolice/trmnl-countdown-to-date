<#
  Normalizes an image to this plugin's standard spec — resize, grayscale,
  PNG — so every countdown image behaves consistently regardless of source.
  Reusable any time you add or update a date's image, not just for
  one-time migration: download/export the source image, run it through
  this script, then reference the -OutFile from dates/manifest.json.
#>
param(
  [Parameter(Mandatory=$true)]
  [string]$InputPath,

  # Defaults next to the input as <name>.normalized.png if not given.
  [string]$OutFile,

  # Caps width only, in pixels - never height. shared.liquid's
  # .countdown-image is width:100%; height:auto, so every layout renders
  # the image at the pane's full content width regardless of its aspect
  # ratio; width is the only axis that's ever actually constrained.
  # Only scales down (a source narrower than this is left at its own
  # size for now rather than upscaled and blurred).
  [int]$MaxWidth = 600
)

Add-Type -AssemblyName System.Drawing

$resolvedInput = Resolve-Path $InputPath -ErrorAction SilentlyContinue
if (-not $resolvedInput) {
  Write-Error "Input image not found: $InputPath"
  exit 1
}

if (-not $OutFile) {
  $OutFile = [IO.Path]::ChangeExtension($InputPath, $null).TrimEnd('.') + ".normalized.png"
}

$src = [System.Drawing.Image]::FromFile($resolvedInput)

$scale = [Math]::Min(1.0, $MaxWidth / $src.Width)
$w = [Math]::Max(1, [int][Math]::Round($src.Width * $scale))
$h = [Math]::Max(1, [int][Math]::Round($src.Height * $scale))

$rgb = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($rgb)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

# Flatten onto white (the screen background - see shared.liquid) before
# resizing/graying, so a transparent source doesn't leave us storing an
# alpha channel of our own - nothing in this plugin's markup composites
# the countdown image over anything else.
$g.Clear([System.Drawing.Color]::White)

# Standard luminosity-weighted grayscale color matrix (Rec. 601 weights),
# applied while drawing so resize + grayscale + flatten happen in one pass.
$matrixRows = [float[][]]@(
  [float[]]@(0.299, 0.299, 0.299, 0, 0),
  [float[]]@(0.587, 0.587, 0.587, 0, 0),
  [float[]]@(0.114, 0.114, 0.114, 0, 0),
  [float[]]@(0, 0, 0, 1, 0),
  [float[]]@(0, 0, 0, 0, 1)
)
$matrix = New-Object System.Drawing.Imaging.ColorMatrix (,$matrixRows)
$attrs = New-Object System.Drawing.Imaging.ImageAttributes
$attrs.SetColorMatrix($matrix)

$srcRect = New-Object System.Drawing.Rectangle 0, 0, $src.Width, $src.Height
$g.DrawImage($src, [System.Drawing.Rectangle]::FromLTRB(0, 0, $w, $h), $srcRect.X, $srcRect.Y, $srcRect.Width, $srcRect.Height, [System.Drawing.GraphicsUnit]::Pixel, $attrs)

$g.Dispose()
$src.Dispose()

# Repack into a true 8-bit indexed grayscale PNG (identity gray palette)
# instead of GDI+'s default: its PNG encoder always writes 32-bit RGBA for
# a 32bppArgb source, even when every pixel is R=G=B, which wastes 4x the
# bytes on what's visually a grayscale image.
$gray = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format8bppIndexed)
$palette = $gray.Palette
for ($i = 0; $i -lt 256; $i++) {
  $palette.Entries[$i] = [System.Drawing.Color]::FromArgb($i, $i, $i)
}
$gray.Palette = $palette

$rgbRect = New-Object System.Drawing.Rectangle 0, 0, $w, $h
$rgbData = $rgb.LockBits($rgbRect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$grayData = $gray.LockBits($rgbRect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, [System.Drawing.Imaging.PixelFormat]::Format8bppIndexed)

$rgbRowBytes = New-Object byte[] ([Math]::Abs($rgbData.Stride))
$grayRowBytes = New-Object byte[] ([Math]::Abs($grayData.Stride))

for ($y = 0; $y -lt $h; $y++) {
  $rgbRowPtr = [IntPtr]::Add($rgbData.Scan0, $y * $rgbData.Stride)
  [System.Runtime.InteropServices.Marshal]::Copy($rgbRowPtr, $rgbRowBytes, 0, $rgbRowBytes.Length)
  for ($x = 0; $x -lt $w; $x++) {
    # BGRA byte order; R == G == B post-color-matrix, so any one channel works.
    $grayRowBytes[$x] = $rgbRowBytes[$x * 4 + 2]
  }
  $grayRowPtr = [IntPtr]::Add($grayData.Scan0, $y * $grayData.Stride)
  [System.Runtime.InteropServices.Marshal]::Copy($grayRowBytes, 0, $grayRowPtr, $grayRowBytes.Length)
}

$rgb.UnlockBits($rgbData)
$gray.UnlockBits($grayData)
$rgb.Dispose()

$gray.Save($OutFile, [System.Drawing.Imaging.ImageFormat]::Png)
$gray.Dispose()

$bytes = [IO.File]::ReadAllBytes($OutFile)
$base64 = [Convert]::ToBase64String($bytes)

$clipboardNote = "and copied to the clipboard"
try {
  Set-Clipboard -Value $base64
} catch {
  $clipboardNote = "(clipboard copy unavailable in this environment)"
}

Write-Output "Normalized to ${w}x${h} grayscale PNG -> $OutFile ($($bytes.Length) bytes, $($base64.Length) base64 chars) $clipboardNote"
