# Packs the mod folders (lua, scripts, ui, locales) into ./perfbox.zip (forward-slash entry names, the game's folders at the top).
# Usage: powershell -ExecutionPolicy Bypass -File build.ps1 [-Install]
#   -Install  also copies the zip into the BeamNG user mods folder
param([switch]$Install)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = $PSScriptRoot
$name = 'perfbox.zip'
$zip = Join-Path $root $name
$folders = 'lua', 'scripts', 'ui', 'locales'

if (Test-Path $zip) { Remove-Item $zip -Force }

$archive = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
try {
  foreach ($f in $folders) {
    Get-ChildItem (Join-Path $root $f) -Recurse -File | ForEach-Object {
      $entry = $_.FullName.Substring($root.Length + 1).Replace('\', '/')
      [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $_.FullName, $entry, [System.IO.Compression.CompressionLevel]::Optimal)
      "  + $entry"
    }
  }
} finally {
  $archive.Dispose()
}
"Built $zip"

if ($Install) {
  $mods = Join-Path $env:LOCALAPPDATA 'BeamNG\BeamNG.drive\current\mods'
  if (-not (Test-Path $mods)) { throw "Mods folder not found: $mods" }
  Copy-Item $zip (Join-Path $mods $name) -Force
  "Installed to $mods\$name"
}
