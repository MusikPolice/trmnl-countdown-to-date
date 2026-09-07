<#
  Turns dates/manifest.json + dates/images/*.png into the JSON blob that
  goes in the plugin's "Dates" custom field on the TRMNL dashboard.

  Kept deliberately separate from manifest editing: a future "add a date"
  script only needs to read/append dates/manifest.json and re-run this,
  not know anything about JSON/base64 assembly.
#>
param(
  [string]$ManifestPath = "dates/manifest.json",
  [string]$ImagesDir = "dates/images",
  [string]$OutFile = "dates/dates.json"
)

if (-not (Test-Path $ManifestPath)) {
  Write-Error "Manifest not found at $ManifestPath. Copy dates/manifest.example.json to $ManifestPath and fill in your dates first."
  exit 1
}

$manifest = @(Get-Content $ManifestPath -Raw | ConvertFrom-Json)

$entries = @(
  foreach ($item in $manifest) {
    $imagePath = Join-Path $ImagesDir $item.image
    if (-not (Test-Path $imagePath)) {
      Write-Error "Image not found: $imagePath (referenced by '$($item.title)')"
      exit 1
    }

    if ($item.month_day -notmatch '^\d{2}-\d{2}$') {
      Write-Error "'$($item.title)' has month_day '$($item.month_day)' - expected zero-padded MM-DD, e.g. '07-01'."
      exit 1
    }

    $bytes = [IO.File]::ReadAllBytes($imagePath)

    [PSCustomObject]@{
      title        = $item.title
      month_day    = $item.month_day
      image_base64 = [Convert]::ToBase64String($bytes)
    }
  }
)

$json = $entries | ConvertTo-Json -Depth 5 -Compress -AsArray
Set-Content -Path $OutFile -Value $json -NoNewline

$clipboardNote = "and copied to the clipboard"
try {
  Set-Clipboard -Value $json
} catch {
  $clipboardNote = "(clipboard copy unavailable in this environment)"
}

Write-Output "Built $($entries.Count) date(s), $($json.Length) characters -> $OutFile $clipboardNote"
Write-Output "Paste this into the plugin's 'Dates' custom field on the TRMNL dashboard."
