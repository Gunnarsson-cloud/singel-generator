param(
  [string]$CanonicalBase = "https://agreeable-ground-0ee11971e.4.azurestaticapps.net"
)

$ErrorActionPreference = "Stop"

$file = Join-Path (Get-Location) "api\IssueOptInTokens\index.js"
if (-not (Test-Path $file)) { throw "Hittar inte: $file. Kör i repo-roten." }

$content = Get-Content $file -Raw -Encoding UTF8
$backup = "$file.bak-" + (Get-Date -Format "yyyyMMdd-HHmmss")
Copy-Item $file $backup -Force

$replacement = @"
function getBase(req) {
  const canonical = "${CanonicalBase}".replace(/\/+$/,"");

  // 1) Env override (but never allow azurewebsites to become canonical)
  const envBaseRaw = (process.env.PUBLIC_BASE_URL || "").trim();
  const envBase = envBaseRaw.replace(/\/+$/,"");
  if (envBase && /^https?:\/\//i.test(envBase) && !envBase.includes("azurewebsites.net")) {
    return envBase;
  }

  // 2) Forwarded headers
  const proto = req.headers["x-forwarded-proto"] || "https";
  const hostHeader =
    req.headers["x-original-host"] ||
    req.headers["x-forwarded-host"] ||
    req.headers["host"];

  const hostStr = Array.isArray(hostHeader) ? hostHeader[0] : hostHeader;
  const host = (hostStr || "").split(",")[0].trim();

  // 3) If we get the Functions host, force SWA canonical
  if (!host) return canonical;
  if (host.includes("azurewebsites.net")) return canonical;

  return `${proto}://${host}`;
}
"@

# Replace getBase(req) function
$patternGetBase = '(?s)function\s+getBase\s*\(\s*req\s*\)\s*\{.*?\n\}'
$newContent = [regex]::Replace($content, $patternGetBase, $replacement, 1)

if ($newContent -eq $content) {
  throw "Kunde inte hitta function getBase(req) att ersätta. Backup: $backup"
}

# Force: const/let base = getBase(req);
$patternBase = '(?m)^\s*(const|let)\s+base\s*=\s*.*?;\s*$'
if ([regex]::IsMatch($newContent, $patternBase)) {
  $newContent = [regex]::Replace($newContent, $patternBase, '  const base = getBase(req);', 1)
} else {
  # If no base assignment exists, we still want it. Insert right after getBase() function.
  $insertAfter = [regex]::Match($newContent, '(?s)function\s+getBase\s*\(\s*req\s*\)\s*\{.*?\n\}')
  if ($insertAfter.Success) {
    $pos = $insertAfter.Index + $insertAfter.Length
    $newContent = $newContent.Insert($pos, "`r`n`r`n  const base = getBase(req);`r`n")
  }
}

Set-Content -Path $file -Value $newContent -Encoding UTF8

Write-Host "DONE. Canonical link fix v2 applied."
Write-Host "Patched: $file"
Write-Host "Backup:  $backup"
