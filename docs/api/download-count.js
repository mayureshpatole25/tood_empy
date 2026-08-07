// Read-only: returns the persistent download total for display on the
// site, without incrementing it. { count: null } if KV isn't set up yet.
export default async function handler(req, res) {
  const kvUrl = process.env.KV_REST_API_URL;
  const kvToken = process.env.KV_REST_API_TOKEN;

  if (!kvUrl || !kvToken) {
    res.setHeader("Cache-Control", "no-store");
    res.status(200).json({ count: null });
    return;
  }

  try {
    const r = await fetch(`${kvUrl}/get/tood_downloads`, {
      headers: { Authorization: `Bearer ${kvToken}` },
    });
    const data = await r.json();
    const count = data.result ? parseInt(data.result, 10) : 0;
    res.setHeader("Cache-Control", "no-store");
    res.status(200).json({ count });
  } catch (err) {
    res.setHeader("Cache-Control", "no-store");
    res.status(200).json({ count: null });
  }
}
