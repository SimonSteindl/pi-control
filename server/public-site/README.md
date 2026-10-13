# Pi-Control public website

This folder contains the public, static project information site. It is separate from the private/admin dashboard and does not call the Raspberry Pi API.

## Cloudflare deployment

- Repository: `SimonSteindl/pi-control`
- Root directory: `server/public-site`
- Build command: `npx wrangler deploy`
- Static assets are configured in `wrangler.jsonc`.
- Cloudflare Access is not required for this public information page.

Do not move the Raspberry Pi server or app into this folder. Keep credentials, tokens, databases and private configuration out of the public site.

After deployment, add the final public URL to the sitemap and verify that URL in Google Search Console.
