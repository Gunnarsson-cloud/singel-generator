param(
  [string]$CanonicalBase = "https://agreeable-ground-0ee11971e.4.azurestaticapps.net"
)

$ErrorActionPreference = "Stop"

$file = Join-Path (Get-Location) "api\IssueOptInTokens\index.js"
if (-not (Test-Path $file)) { throw "Hittar inte: $file. Kör i repo-roten." }

$content = Get-Content $file -Raw -Encoding UTF8

if ($content -match "CANONICAL_MK_PATCH") {
  Write-Host "Redan patchad (CANONICAL_MK_PATCH). Inget att göra."
  exit 0
}

$backup = "$file.bak-" + (Get-Date -Format "yyyyMMdd-HHmmss")
Copy-Item $file $backup -Force

# Replace the line that defines mk(...) - robust match on 'const mk ='
$pattern = '(?m)^\s*const\s+mk\s*=\s*\(tok,\s*ans\)\s*=>\s*.*$'
if (-not [regex]::IsMatch($content, $pattern)) {
  throw "Kunde inte hitta raden 'const mk = (tok, ans) => ...' att ersätta. Backup: $backup"
}

$replacement = @"
  // CANONICAL_MK_PATCH: force SWA canonical base for opt-in links
  const envBaseRaw = (process.env.PUBLIC_BASE_URL || "").trim();
  const envBase = envBaseRaw.replace(/\/+$/,"");
  const canonical = "$CanonicalBase".replace(/\/+$/,"");
  const publicBase = (envBase && /^https?:\/\//i.test(envBase) && !envBase.includes("azurewebsites.net"))
    ? envBase
    : canonical;

  const mk = (tok, ans) => `${publicBase}/api/MatchRespond?token=${encodeURIComponent(tok)}&answer=${ans}`;
"@

$newContent = [regex]::Replace($content, $pattern, $replacement, 1)
Set-Content -Path $file -Value $newContent -Encoding UTF8

Write-Host "DONE. Patched mk() to use canonical base."
Write-Host "Patched: $file"
Write-Host "Backup:  $backup"
