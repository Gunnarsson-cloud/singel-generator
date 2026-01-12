$ErrorActionPreference = "Stop"

# 1) Ensure api/package.json includes resend dependency
$pkgPath = Join-Path (Get-Location) "api\package.json"
if (-not (Test-Path $pkgPath)) { throw "Hittar inte $pkgPath. Kör i repo-roten." }

$pkg = Get-Content $pkgPath -Raw -Encoding UTF8 | ConvertFrom-Json

if (-not $pkg.dependencies) {
  $pkg | Add-Member -MemberType NoteProperty -Name dependencies -Value ([pscustomobject]@{})
}

if (-not $pkg.dependencies.resend) {
  # Pin a reasonably stable major; npm will resolve.
  $pkg.dependencies | Add-Member -MemberType NoteProperty -Name resend -Value "^4.0.0"
  $pkg | ConvertTo-Json -Depth 10 | Set-Content $pkgPath -Encoding UTF8
  Write-Host "Updated api/package.json: added dependency 'resend'"
} else {
  Write-Host "api/package.json already has 'resend' dependency"
}

# 2) Create a new function: api/SendTestEmail
$fnDir = Join-Path (Get-Location) "api\SendTestEmail"
New-Item -ItemType Directory -Path $fnDir -Force | Out-Null

$functionJson = @'
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
$functionJson | Set-Content (Join-Path $fnDir "function.json") -Encoding UTF8

$indexJs = @'
const { Resend } = require("resend");

module.exports = async function (context, req) {
  try {
    const apiKey = process.env.RESEND_API_KEY;
    const from = process.env.RESEND_FROM;
    const overrideTo = process.env.MAIL_OVERRIDE_TO;

    if (!apiKey) return (context.res = { status: 500, body: { error: "Missing RESEND_API_KEY" } });
    if (!from) return (context.res = { status: 500, body: { error: "Missing RESEND_FROM" } });
    if (!overrideTo) return (context.res = { status: 500, body: { error: "Missing MAIL_OVERRIDE_TO" } });

    const resend = new Resend(apiKey);

    const subject = req.query.subject || "MotesGenerator testmail";
    const to = overrideTo; // Always override for safety in test
    const text = "Detta ar ett testmail fran MotessGeneratorn. Om du far detta: allt funkar. :)";
    const html = `
      <div style="font-family:system-ui,Segoe UI,Arial,sans-serif;">
        <h2>Testmail: MotessGeneratorn</h2>
        <p>Om du far detta: Resend + Azure Functions + SWA settings funkar.</p>
        <p><strong>Tips:</strong> Vi skickar just nu alltid till <code>MAIL_OVERRIDE_TO</code> for att undvika olyckor.</p>
      </div>
    `;

    const result = await resend.emails.send({
      from,
      to,
      subject,
      text,
      html
    });

    context.res = {
      status: 200,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ok: true, to, from, result })
    };
  } catch (e) {
    context.log("SendTestEmail error:", e);
    context.res = {
      status: 500,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ok: false, error: String(e && e.message ? e.message : e) })
    };
  }
};
'@
$indexJs | Set-Content (Join-Path $fnDir "index.js") -Encoding UTF8

Write-Host "Created api/SendTestEmail function."
Write-Host "Next: git add/commit/push + wait"
