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
    const html = body.html || "<p>Hello from Azure Functions ðŸ‘‹</p>";
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
