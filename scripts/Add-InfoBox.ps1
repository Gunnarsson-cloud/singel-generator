# Add-InfoBox.ps1
# Inserts or updates a styled info-box on the landing page (index.html).
# - Adds CSS once
# - Inserts the box right before the first <form>
# - Safe to run multiple times (idempotent)
# - Creates a timestamped backup

$ErrorActionPreference = "Stop"

$file = Join-Path (Get-Location) "index.html"
if (-not (Test-Path $file)) {
  throw "Cannot find index.html in: $(Get-Location). cd to the repo root first."
}

$content = Get-Content -Path $file -Raw -Encoding UTF8

$startMarker = "<!-- HERO_SHORT_START -->"
$endMarker   = "<!-- HERO_SHORT_END -->"
$cssMarker   = "/* INFOBOX_CSS */"

# Info-box HTML (ASCII-only using HTML entities for Swedish chars)
$boxHtml = @"
$startMarker
<div class="infobox">
  <div class="infobox-title">En trygg match i din stad</div>
  <div class="infobox-sub">Kontaktuppgifter delas f&ouml;rst n&auml;r b&aring;da sagt <strong>JA</strong>.</div>
  <ul class="infobox-list">
    <li><strong>Double opt-in:</strong> JA/NEJ via mail</li>
    <li><strong>Trygghet:</strong> blockera &amp; rapportera</li>
    <li><strong>48h:</strong> svarstid p&aring; match</li>
  </ul>
</div>
$endMarker

"@

# CSS to add inside <style> once
$css = @"
$cssMarker
.infobox {
  border: 1px solid rgba(0,0,0,.12);
  background: rgba(0,0,0,.03);
  padding: 0.9rem 1rem;
  border-radius: 14px;
  margin: 0.75rem 0 1rem 0;
  position: relative;
}
.infobox:before {
  content: "";
  position: absolute;
  left: 0;
  top: 12px;
  bottom: 12px;
  width: 5px;
  border-radius: 14px;
  background: #0078d4;
}
.infobox-title { font-weight: 700; margin-left: 10px; }
.infobox-sub { margin: 0.35rem 0 0.6rem 10px; }
.infobox-list { margin: 0 0 0 22px; padding-left: 1.1rem; }
.infobox-list li { margin: 0.2rem 0; }
"@

# Backup first
$backup = "$file.bak-" + (Get-Date -Format "yyyyMMdd-HHmmss")
Copy-Item $file $backup -Force

# 1) Ensure CSS exists in <style> block
if ($content -notlike "*$cssMarker*") {
  $styleClose = [regex]::Match($content, '(?is)</style>')
  if (-not $styleClose.Success) {
    throw "Could not find </style> in index.html. Aborting to avoid breaking layout."
  }

  $insertAt = $styleClose.Index
  $content = $content.Insert($insertAt, "`r`n$css`r`n")
}

# 2) Insert or replace info-box before first <form>
if ($content -like "*$startMarker*") {
  # Replace existing block between markers
  $pattern = [regex]::Escape($startMarker) + ".*?" + [regex]::Escape($endMarker)
  $content = [regex]::Replace($content, $pattern, ($boxHtml.TrimEnd() -replace '\$', '$$'), "Singleline")
} else {
  $formMatch = [regex]::Match($content, '(?is)<form\b')
  if (-not $formMatch.Success) {
    throw "Could not find a <form ...> tag in index.html. Aborting."
  }
  $content = $content.Insert($formMatch.Index, $boxHtml)
}

Set-Content -Path $file -Value $content -Encoding UTF8

Write-Host "DONE. Info-box inserted/updated."
Write-Host "Backup created: $backup"
Write-Host "Next: git status -> commit -> push"
