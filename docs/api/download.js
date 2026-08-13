// The actual "Download for Mac" button points here instead of straight at
// the GitHub release asset. This increments a persistent counter (Vercel
// KV) that survives every future DMG re-upload, then redirects to the
// real file — GitHub's own per-asset download count resets to 0 every
// time the asset is replaced, which happens on every app update, so it
// can't tell you a lifetime total on its own.
const DMG_URL = "https://github.com/reneezhang99/to-do-app/releases/download/v1.6.0/Tood.dmg";

export default async function handler(req, res) {
  const kvUrl = process.env.KV_REST_API_URL;
  const kvToken = process.env.KV_REST_API_TOKEN;

  if (kvUrl && kvToken) {
    try {
      await fetch(`${kvUrl}/incr/tood_downloads`, {
        headers: { Authorization: `Bearer ${kvToken}` },
      });
    } catch (err) {
      // Never block the actual download over a counter hiccup.
      console.error("download counter increment failed", err);
    }
  }

  res.setHeader("Cache-Control", "no-store");
  res.writeHead(302, { Location: DMG_URL });
  res.end();
}
