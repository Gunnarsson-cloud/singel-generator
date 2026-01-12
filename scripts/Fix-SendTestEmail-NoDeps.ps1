# Fix-SendTestEmail-NoDeps.ps1
# - Removes "resend" npm dependency
# - Rewrites SendTestEmail function to call Resend REST API via fetch
# - Commits + pushes + waits for GitHub Actions

$ErrorActionPreference = "Stop"

function Write-Section($t) { Write-Host "`n=== $t ===" }
function Assert-File($p) { if (-not (Test-Path $p)) { throw "Missing file: $p" } }

$repo = "Gunnarsson-cloud/singel-generator"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

$sendFile = Join-Path $repoRoot "api\SendTestEmail\index.js"
$pkgFile  = Join-Path $repoRoot "api\package.json"

Assert-File $sendFile
Assert-File $pkgFile

Write-Section "Backup"
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$sendBak = "$sendFile.bak-$ts"
$pkgBak  = "$pkgFile.bak-$ts"
Copy-Item $sendFile $sendBak -Force
Copy-Item $pkgFile  $pkgBak  -Force
Write-Host "Backup OK:"
Write-Host " - $sendBak"
Write-Host " - $pkgBak"

Write-Section "Rewrite api/SendTestEmail/index.js (no npm dependency)"
@'
// SendTestEmail (no npm dependency)
// Uses Resend REST API directly via fetch (Node 18+).
// Env:
// - RESEND_API_KEY (required)
// - RESEND_FROM (required, must be a verified sender in Resend)
// - MAIL_OVERRIDE_TO (optional; if set, overrides any 'to' to avoid accidental real emails)

module.exports = async function (context, req) {
  try {
    const apiKey = process.env.RESEND_API_KEY;
    const from = process.env.RESEND_FROM;
    const overrideTo = process.env.MAIL_OVERRIDE_TO;

    const body = req.body || {};
    const q = req.query || {};

    const to = overrideTo || body.to || q.to;
    const subject = body.subject || q.subject || "Testmail - MotesGenerator";
    const html =
      body.html ||
      "<div style=\"font-family:Arial,Helvetica,sans-serif;line-height:1.5\">" +
      "<h2>Testmail</h2>" +
      "<p>Detta ar ett testutskick fran SendTestEmail-endpointen.</p>" +
      "<p>(Om du fick detta: mail funkar. Om du inte fick detta: mail funkar kanske anda, men inte till dig.)</p>" +
      "</div>";

    if (!apiKey) {
      context.res = { status: 500, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ok: false, error: "Missing RESEND_API_KEY app setting" }) };
      return;
    }
    if (!from) {
      context.res = { status: 500, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ok: false, error: "Missing RESEND_FROM app setting" }) };
      return;
    }
    if (!to) {
      context.res = { status: 400, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ok: false, error: "Missing recipient. Provide ?to=... or JSON body { to: ... }, or set MAIL_OVERRIDE_TO" }) };
      return;
    }

    if (typeof fetch !== "function") {
      context.res = { status: 500, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ok: false, error: "fetch() not available in this runtime. Node 18+ required." }) };
      return;
    }

    const payload = {
      from,
      to: [to],
      subject,
      html
    };

    const resp = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify(payload)
    });

    const raw = await resp.text();
    let parsed = null;
    try { parsed = JSON.parse(raw); } catch (_) { parsed = { raw }; }

    context.res = {
      status: resp.status,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        ok: resp.ok,
        status: resp.status,
        to,
        overrideToUsed: !!overrideTo,
        resend: parsed
      }, null, 2)
    };
  } catch (e) {
    context.log("SendTestEmail error:", e);
    context.res = { status: 500, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ok: false, error: String(e && e.message ? e.message : e) }) };
  }
};
'@ | Set-Content -Path $sendFile -Encoding UTF8

Write-Host "Patched: $sendFile"

Write-Section "Remove 'resend' from api/package.json"
$pkgRaw = Get-Content $pkgFile -Raw
$pkgObj = $pkgRaw | ConvertFrom-Json

if ($null -ne $pkgObj.dependencies) {
  $depNames = @($pkgObj.dependencies.PSObject.Properties.Name)
  if ($depNames -contains "resend") {
    $pkgObj.dependencies.PSObject.Properties.Remove("resend")
    Write-Host "Removed dependency: resend"
  } else {
    Write-Host "Dependency 'resend' not found (already removed)."
  }
} else {
  Write-Host "No dependencies object found in api/package.json (unexpected, but continuing)."
}

($pkgObj | ConvertTo-Json -Depth 50) | Set-Content -Path $pkgFile -Encoding UTF8

Write-Section "Git commit + push"
Push-Location $repoRoot

git status --porcelain | ForEach-Object { $_ } | Out-Host

git add $sendFile $pkgFile

$msg = "Fix SendTestEmail: call Resend REST API (no npm dependency)"
git commit -m $msg

git push

Write-Section "Wait for GitHub Actions"
$runId = (gh run list --repo $repo --limit 1 --json databaseId | ConvertFrom-Json).databaseId
Write-Host "RunId: $runId"
gh run watch $runId --repo $repo --exit-status

Pop-Location

Write-Host "`nDONE. If the run is green, we can test /api/SendTestEmail."
Write-Host "Backups:"
Write-Host " - $sendBak"
Write-Host " - $pkgBak"
