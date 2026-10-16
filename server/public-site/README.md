# Pi-Control public website

This folder contains the public, responsive project landing page. It is a static information site and does not call the Raspberry Pi API or expose the private/admin dashboard.

## Deploy to Cloudflare Pages/Workers static assets

- Repository: `SimonSteindl/pi-control`
- Root directory: `server/public-site`
- Config: `wrangler.jsonc`
- Deploy command: `npx wrangler deploy`
- Public URL used for canonical metadata, robots.txt and sitemap: `https://pi-control-public.steindlsimon12.workers.dev/`

The landing page includes responsive layouts, accessible focus states and skip navigation, reduced-motion support, search/social metadata, JSON-LD software metadata, a labelled illustrative dashboard preview, release/source links, feature descriptions and a FAQ. The dashboard numbers are explicitly examples, not live device data.

## Validation

Run the dependency-free checks from the repository root:

```bash
python3 server/public-site/test_site.py
```

GitHub Actions runs the same check when the public site or its workflow changes.

After deploying, open the canonical URL, confirm that `/robots.txt` and `/sitemap.xml` return successfully, and request indexing through Google Search Console if needed.

Do not move the Raspberry Pi server or app into this folder. Keep credentials, tokens, databases and private configuration out of the public site. Cloudflare Access is not required for this public information page.
