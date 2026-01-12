[CmdletBinding()]
param(
  [string]$Repo = "Gunnarsson-cloud/singel-generator",
  [switch]$CommitPush
)

$ErrorActionPreference = "Stop"

function New-Timestamp { Get-Date -Format "yyyyMMdd-HHmmss" }

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$apiRoot  = Join-Path $repoRoot "api"
if (-not (Test-Path $apiRoot)) { throw "Hittar inte api-mappen: $apiRoot" }

$ts = New-Timestamp
Write-Host "Repo root: $repoRoot"
Write-Host "API root : $apiRoot"
Write-Host ""

# --- Ensure host.json (with extensionBundle) ---
$hostJsonPath = Join-Path $apiRoot "host.json"
if (Test-Path $hostJsonPath) {
  Copy-Item $hostJsonPath "$hostJsonPath.bak-$ts" -Force
}

$hostJson = @'
{
  "version": "2.0",
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[4.*, 5.0.0)"
  }
}
'@
Set-Content -Path $hostJsonPath -Value $hostJson -Encoding UTF8
Write-Host "OK: host.json ensured (+ backup if existed)"

# --- Ensure SendTestEmail function (non-crashing startup) ---
$sendDir = Join-Path $apiRoot "SendTestEmail"
New-Item -ItemType Directory -Path $sendDir -Force | Out-Null

$sendFuncJsonPath = Join-Path $sendDir "function.json"
if (Test-Path $sendFuncJsonPath) {
  Copy-Item $sendFuncJsonPath "$sendFuncJsonPath.bak-$ts" -Force
}

$sendFuncJson = @'
{
  "bindings": [
    {
      "authLevel": "anonymous",
      "type": "httpTrigger",
      "direction": "in",
      "name": "req",
      "methods": [ "post", "options" ]
    },
    {
      "type": "http",
      "direction": "out",
      "name": "res"
    }
  ]
}
'@
Set-Content -Path $sendFuncJsonPath -Value $sendFuncJson -Encoding UTF8
Write-Host "OK: SendTestEmail/function.json ensured (+ backup if existed)"

$sendIndexPath = Join-Path $sendDir "index.js"
if (Test-Path $sendIndexPath) {
  Copy-Item $sendIndexPath "$sendIndexPath.bak-$ts" -Force
}

# NOTE: absolutely no throw at module load time
$sendIndex = @'
/**
 * Azure Function: /api/SendTestEmail
 * - No npm deps
 * - Never throws at module load (important for Azure startup/deploy)
 */
module.exports = async function (context, req) {
  try {
    // Preflight
    if ((req.method || "").toUpperCase() === "OPTIONS") {
      context.res = {
        status: 204,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "POST,OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type"
        }
      };
      return;
    }

    if ((req.method || "").toUpperCase() !== "POST") {
      context.res = { status: 405, body: "Use POST." };
      return;
    }

    const apiKey = process.env.RESEND_API_KEY;
    if (!apiKey) {
      // IMPORTANT: return error instead of throwing so Functions host can start
      context.res = {
        status: 500,
        body: "Missing RESEND_API_KEY in app settings."
      };
      return;
    }

    const body = req.body || {};
    const to = body.to || body.email;
    const subject = body.subject || "Test email";
    const html = body.html || "<p>Hello from Azure Functions 👋</p>";
    const from = process.env.RESEND_FROM || "onboarding@resend.dev";

    if (!to) {
      context.res = { status: 400, body: "Missing 'to' (or 'email') in request body." };
      return;
    }

    const payload = {
      from,
      to: Array.isArray(to) ? to : [to],
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

    const text = await resp.text();
    if (!resp.ok) {
      context.res = {
        status: 502,
        body: `Resend error (${resp.status}): ${text}`
      };
      return;
    }

    context.res = {
      status: 200,
      headers: { "Content-Type": "application/json" },
      body: text
    };
  } catch (err) {
    context.res = { status: 500, body: `Function error: ${err && err.message ? err.message : err}` };
  }
};
'@
Set-Content -Path $sendIndexPath -Value $sendIndex -Encoding UTF8
Write-Host "OK: SendTestEmail/index.js rewritten to be deploy-safe (+ backup if existed)"

# --- Add a super-minimal Ping function to verify Functions deploy/run ---
$pingDir = Join-Path $apiRoot "Ping"
New-Item -ItemType Directory -Path $pingDir -Force | Out-Null

$pingFuncJsonPath = Join-Path $pingDir "function.json"
$pingIndexPath    = Join-Path $pingDir "index.js"

$pingFuncJson = @'
{
  "bindings": [
    {
      "authLevel": "anonymous",
      "type": "httpTrigger",
      "direction": "in",
      "name": "req",
      "methods": [ "get" ]
    },
    {
      "type": "http",
      "direction": "out",
      "name": "res"
    }
  ]
}
'@
Set-Content -Path $pingFuncJsonPath -Value $pingFuncJson -Encoding UTF8

$pingIndex = @'
module.exports = async function (context, req) {
  context.res = {
    status: 200,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ ok: true, ts: new Date().toISOString() })
  };
};
'@
Set-Content -Path $pingIndexPath -Value $pingIndex -Encoding UTF8
Write-Host "OK: Ping function added at /api/Ping"

Write-Host ""
Write-Host "Changes:"
git -C $repoRoot status --porcelain

if ($CommitPush) {
  git -C $repoRoot add -A
  $msg = "Fix SWA Functions deploy: safe startup + Ping + host bundle"
  git -C $repoRoot commit -m $msg
  git -C $repoRoot push
  Write-Host "OK: committed + pushed"
} else {
  Write-Host "NOTE: Run again with -CommitPush to commit + push."
}
