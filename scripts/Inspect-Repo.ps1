# Inspect-Repo.ps1 (ASCII-safe)
# Skapar en rapport med repo-träd + utdrag ur index.html

$ErrorActionPreference = "Stop"

$here = Get-Location
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportPath = Join-Path $here ("inspect-report-$timestamp.txt")

$lines = New-Object System.Collections.Generic.List[string]
function Add-Line([string]$s = "") { $script:lines.Add($s) | Out-Null }

Add-Line "=== REPO INSPECT REPORT ==="
Add-Line ("Time: " + (Get-Date))
Add-Line ("Path: " + $here.Path)
Add-Line ""

# Trädlistning (begränsad och exkluderar tunga mappar)
$excludeDirs = @("node_modules", ".git", ".github", ".swa", ".vs", ".vscode")
function Add-Tree {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [int]$Depth = 3,
    [string]$Prefix = ""
  )

  if ($Depth -lt 0) { return }

  $items = Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue |
           Sort-Object @{Expression={$_.PSIsContainer};Descending=$true}, Name

  $maxItems = 80
  $count = 0

  foreach ($item in $items) {
    if ($count -ge $maxItems) {
      Add-Line ("$Prefix... (trunkerat efter $maxItems items i '$Path')")
      break
    }
    $count++

    if ($item.PSIsContainer) {
      if ($excludeDirs -contains $item.Name) { continue }
      Add-Line ("$Prefix[DIR ] " + $item.Name)
      Add-Tree -Path $item.FullName -Depth ($Depth - 1) -Prefix ($Prefix + "  ")
    } else {
      $skipFiles = @("local.settings.json", ".env", ".env.local", ".env.production")
      if ($skipFiles -contains $item.Name) { continue }
      Add-Line ("$Prefix[FILE] " + $item.Name)
    }
  }
}

Add-Line "== TOP-LEVEL TREE (depth 3) =="
Add-Tree -Path $here.Path -Depth 3 -Prefix ""
Add-Line ""

# Hitta index.html
$indexPath = Join-Path $here "index.html"
if (-not (Test-Path $indexPath)) {
  $found = Get-ChildItem -Path $here.Path -Recurse -Filter "index.html" -File -ErrorAction SilentlyContinue |
           Where-Object { $_.FullName -notmatch '\\node_modules\\' -and $_.FullName -notmatch '\\\.git\\' } |
           Select-Object -First 5
  if ($found.Count -gt 0) { $indexPath = $found[0].FullName }
}

if (-not (Test-Path $indexPath)) {
  Add-Line "WARNING: Could not find index.html. Are you in repo root?"
  $script:lines | Set-Content -Path $reportPath -Encoding UTF8
  Write-Host "Report created: $reportPath"
  exit 0
}

$indexInfo = Get-Item $indexPath
Add-Line "== INDEX FILE =="
Add-Line ("index.html: " + $indexPath)
Add-Line ("Size: " + $indexInfo.Length + " bytes")
Add-Line ("LastWriteTime: " + $indexInfo.LastWriteTime)
Add-Line ""

$idxLines = Get-Content -Path $indexPath -Encoding UTF8

$startMarker = "<!-- HERO_SHORT_START -->"
$endMarker   = "<!-- HERO_SHORT_END -->"

Add-Line "== HERO MARKERS CHECK =="
Add-Line ("Has HERO_SHORT_START: " + ($idxLines -contains $startMarker))
Add-Line ("Has HERO_SHORT_END: " + ($idxLines -contains $endMarker))
Add-Line ""

Add-Line "== CONTEXT AROUND FIRST <form> =="
$formMatch = $idxLines | Select-String -Pattern '<form\b' -AllMatches | Select-Object -First 1
if ($null -eq $formMatch) {
  Add-Line "WARNING: No <form ...> found in index.html."
} else {
  $lineNumber = $formMatch.LineNumber
  Add-Line ("First <form> at line: " + $lineNumber)
  Add-Line ""

  $from = [Math]::Max(1, $lineNumber - 12)
  $to   = [Math]::Min($idxLines.Count, $lineNumber + 20)

  for ($i = $from; $i -le $to; $i++) {
    $prefix = ("{0,5}: " -f $i)
    Add-Line ($prefix + $idxLines[$i-1])
  }
}
Add-Line ""

Add-Line "== FIRST 60 LINES OF index.html =="
$max = [Math]::Min(60, $idxLines.Count)
for ($i = 1; $i -le $max; $i++) {
  Add-Line (("{0,5}: " -f $i) + $idxLines[$i-1])
}
Add-Line ""

$script:lines | Set-Content -Path $reportPath -Encoding UTF8
Write-Host "DONE. Report created:"
Write-Host $reportPath
Write-Host "Open it with:"
Write-Host "notepad `"$reportPath`""
