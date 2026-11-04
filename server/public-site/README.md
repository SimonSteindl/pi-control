# Pi-Control public website

This folder contains the public, responsive project landing page. It is a static information site and does not call the Raspberry Pi API or expose the private/admin dashboard.

## Build

`build.py` is the single source of truth for what gets published. It runs the checks from `test_site.py`, then recreates `dist/` containing only `index.html`, `robots.txt` and `sitemap.xml`. Everything else in this folder (README, config, tests, scripts) is never uploaded.

```bash
python3 server/public-site/build.py
```

`dist/` is generated and ignored by Git. `wrangler.jsonc` runs `python3 build.py` automatically before every `wrangler dev`, `wrangler deploy` and `wrangler deploy --dry-run`, so Python 3 must be available wherever Wrangler runs.

## Deploy to Cloudflare (Workers static assets)

Deployment runs only through the GitHub Actions workflow `.github/workflows/deploy-public-site.yml`:

- Pull requests: tests, build and `wrangler deploy --dry-run` (no deployment, no secrets needed).
- Push to `main` or manual **Run workflow**: the same checks, then `wrangler deploy`.
- Required repository secrets: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`.

The Cloudflare Workers Builds Git integration for `pi-control-public` should stay disconnected so that the Worker is not deployed through a second path.

- Worker name: `pi-control-public`
- Config: `server/public-site/wrangler.jsonc`
- Public URL used for canonical metadata, robots.txt and sitemap: `https://pi-control-public.steindlsimon12.workers.dev/`

The landing page includes responsive layouts, accessible focus states and skip navigation, reduced-motion support, search/social metadata, JSON-LD software metadata, a labelled illustrative dashboard preview, release/source links, feature descriptions and a FAQ. The dashboard numbers are explicitly examples, not live device data.

## Validation

Run the dependency-free checks from the repository root:

```bash
python3 server/public-site/test_site.py
```

GitHub Actions runs the same check, the build and a Wrangler dry-run when the public site or its workflow changes.

After deploying, open the canonical URL, confirm that `/robots.txt` and `/sitemap.xml` return successfully, and request indexing through Google Search Console if needed.

Do not move the Raspberry Pi server or app into this folder. Keep credentials, tokens, databases and private configuration out of the public site. Cloudflare Access is not required for this public information page.
