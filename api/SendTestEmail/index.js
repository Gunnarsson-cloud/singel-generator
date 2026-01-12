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
