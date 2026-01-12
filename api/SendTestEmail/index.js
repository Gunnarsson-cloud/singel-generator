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
