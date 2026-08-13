// The app never knows where bug reports actually go — it only ever POSTs
// here. This function is the only thing that knows the real destination
// (BUG_REPORT_TO_EMAIL, a server-side env var, never committed to the repo
// since it's public), and sends through Resend using the toodapp.com
// sending domain. Subject line is prefixed distinctly so it's easy to
// filter/label separately from everything else in that inbox.

export const config = {
  api: {
    bodyParser: {
      sizeLimit: "8mb", // room for a full-resolution screenshot as base64
    },
  },
};

export default async function handler(req, res) {
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  const apiKey = process.env.RESEND_API_KEY;
  const toEmail = process.env.BUG_REPORT_TO_EMAIL;
  if (!apiKey || !toEmail) {
    console.error("report-bug misconfigured: missing RESEND_API_KEY or BUG_REPORT_TO_EMAIL");
    res.status(500).json({ error: "Not configured" });
    return;
  }

  const { text, imageBase64, appVersion, macOSVersion } = req.body || {};
  const trimmedText = typeof text === "string" ? text.trim() : "";
  if (!trimmedText) {
    res.status(400).json({ error: "Missing bug description" });
    return;
  }

  const attachments = [];
  if (typeof imageBase64 === "string" && imageBase64.length > 0) {
    attachments.push({
      filename: "screenshot.png",
      content: imageBase64, // Resend accepts a plain base64 string here
    });
  }

  const html = `
    <p><strong>From:</strong> Tood v${escapeHtml(appVersion || "unknown")} on macOS ${escapeHtml(macOSVersion || "unknown")}</p>
    <p>${escapeHtml(trimmedText).replace(/\n/g, "<br>")}</p>
  `;

  try {
    const resp = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: "Tood Bug Reports <bugs@toodapp.com>",
        to: [toEmail],
        subject: `[Tood Bug Report] ${trimmedText.slice(0, 60)}`,
        html,
        attachments,
      }),
    });

    if (!resp.ok) {
      const detail = await resp.text();
      console.error("Resend send failed:", resp.status, detail);
      res.status(502).json({ error: "Failed to send" });
      return;
    }

    res.status(200).json({ ok: true });
  } catch (err) {
    console.error("report-bug error:", err);
    res.status(500).json({ error: "Failed to send" });
  }
}

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}
