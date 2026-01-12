param(
  [string]$CanonicalBase = "https://agreeable-ground-0ee11971e.4.azurestaticapps.net"
)

$ErrorActionPreference = "Stop"

$file = Join-Path (Get-Location) "api\IssueOptInTokens\index.js"
if (-not (Test-Path $file)) {
  throw "Hittar inte: $file. Kör detta i repo-roten."
}

$content = Get-Content $file -Raw -Encoding UTF8

# If already patched, do nothing
if ($content -match "azurewebsites\.net\)\)\s*return\s*canonical") {
  Write-Host "Redan patchad (azurewebsites -> canonical). Inget att göra."
  exit 0
}

$backup = "$file.bak-" + (Get-Date -Format "yyyyMMdd-HHmmss")
Copy-Item $file $backup -Force

$replacement = @"
function getBase(req) {
  // 1) Prefer explicit canonical base if provided (easy to override later)
  const envBase = (process.env.PUBLIC_BASE_URL || "").trim();
  if (envBase && /^https?:\/\//i.test(envBase)) {
    return envBase.replace(/\/+$/,"");
  }

  // 2) Build from forwarded headers
  const proto = req.headers["x-forwarded-proto"] || "https";
  const hostHeader =
    req.headers["x-original-host"] ||
    req.headers["x-forwarded-host"] ||
    req.headers["host"];

  const host = Array.isArray(hostHeader) ? hostHeader[0] : hostHeader;

  // 3) SWA sometimes forwards the Functions host (azurewebsites) - force canonical SWA domain
  const canonical = "$CanonicalBase";
  if (host && host.includes("azurewebsites.net")) return canonical;

  return `${proto}://${host}`;
}
"@

# Replace the whole getBase(req) function
$pattern = '(?s)function\s+getBase\s*\(\s*req\s*\)\s*\{.*?\n\}'
$newContent = [regex]::Replace($content, $pattern, $replacement, 1)

if ($newContent -eq $content) {
  Write-Host "Kunde inte hitta getBase(req) att ersätta. Avbryter."
  Write-Host "Backup finns: $backup"
  exit 1
}

Set-Content -Path $file -Value $newContent -Encoding UTF8

Write-Host "DONE. Patchad: $file"
Write-Host "Backup: $backup"
Write-Host "Next: git add/commit/push"
