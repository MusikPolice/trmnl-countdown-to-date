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

  # Long edge, in pixels. Matches what the layouts render at largest
  # (full.liquid, ~750px wide) - no point storing more than the display
  # can ever show.
  [int]$MaxDimension = 600
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

$scale = [Math]::Min(1.0, $MaxDimension / [Math]::Max($src.Width, $src.Height))
$w = [Math]::Max(1, [int][Math]::Round($src.Width * $scale))
$h = [Math]::Max(1, [int][Math]::Round($src.Height * $scale))

$dest = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($dest)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

# Standard luminosity-weighted grayscale color matrix (Rec. 601 weights),
# applied while drawing so resize + grayscale happen in one pass.
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

$dest.Save($OutFile, [System.Drawing.Imaging.ImageFormat]::Png)
$dest.Dispose()

$bytes = [IO.File]::ReadAllBytes($OutFile)
$base64 = [Convert]::ToBase64String($bytes)

$clipboardNote = "and copied to the clipboard"
try {
  Set-Clipboard -Value $base64
} catch {
  $clipboardNote = "(clipboard copy unavailable in this environment)"
}

Write-Output "Normalized to ${w}x${h} grayscale PNG -> $OutFile ($($bytes.Length) bytes, $($base64.Length) base64 chars) $clipboardNote"
