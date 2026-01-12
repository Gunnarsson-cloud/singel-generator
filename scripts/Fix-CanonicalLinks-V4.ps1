param(
  [string]$CanonicalBase = "https://agreeable-ground-0ee11971e.4.azurestaticapps.net"
)

$ErrorActionPreference = "Stop"

$file = Join-Path (Get-Location) "api\IssueOptInTokens\index.js"
if (-not (Test-Path $file)) { throw "Hittar inte: $file. Kör i repo-roten." }

$content = Get-Content $file -Raw -Encoding UTF8

$backup = "$file.bak-" + (Get-Date -Format "yyyyMMdd-HHmmss")
Copy-Item $file $backup -Force

# Replace our previous mk patch block (from the CANONICAL marker down to the mk line)
$pattern = '(?ms)^\s*//\s*CANONICAL_MK_PATCH.*?\r?\n\s*const\s+mk\s*=.*?;\s*$'
if (-not [regex]::IsMatch($content, $pattern)) {
  throw "Kunde inte hitta CANONICAL_MK_PATCH-blocket att ersätta. Backup: $backup"
}

$replacement = @"
  // CANONICAL_MK_PATCH_V4: force SWA canonical base for opt-in links (safe string concat)
  const canonical = "$CanonicalBase".replace(/\/+$/,"");

  const envBaseRaw = (process.env.PUBLIC_BASE_URL || "").trim();
  const envBase = envBaseRaw.replace(/\/+$/,"");

  const proto = req.headers["x-forwarded-proto"] || "https";
  const hostHeader =
    req.headers["x-original-host"] ||
    req.headers["x-forwarded-host"] ||
    req.headers["host"] ||
    "";

  const hostVal = Array.isArray(hostHeader) ? hostHeader[0] : hostHeader;
  const host = (hostVal || "").split(",")[0].trim();

  let publicBase = canonical;
  if (envBase && /^https?:\/\//i.test(envBase) && !envBase.includes("azurewebsites.net")) {
    publicBase = envBase;
  } else if (host && !host.includes("azurewebsites.net")) {
    publicBase = proto + "://" + host;
  }

  const mk = (tok, ans) => publicBase + "/api/MatchRespond?token=" + encodeURIComponent(tok) + "&answer=" + ans;
"@

$newContent = [regex]::Replace($content, $pattern, $replacement, 1)
Set-Content -Path $file -Value $newContent -Encoding UTF8

Write-Host "DONE. V4 patch applied."
Write-Host "Patched: $file"
Write-Host "Backup:  $backup"
