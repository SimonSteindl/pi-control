# Pi-Control dashboard on Cloudflare

This is a separate deployment from `server/public-site`. It does not replace the public project page or change the Raspberry Pi's running server.

## How it works

- GitHub Actions generates Flutter's web platform files in the temporary CI workspace and builds `app/` for the web.
- The generated web output is copied to `assets/` for the Cloudflare Worker deployment.
- Static dashboard requests are served by Cloudflare.
- Requests to `/api/*` are forwarded to the fixed existing Pi-Control API origin configured in `src/index.js`.
- The dashboard responses are marked `noindex, nofollow`; the separate public project page remains the page intended for search engines.

## Validation and deployment

The `Cloudflare dashboard` workflow builds and validates the app for pull requests and pushes to `main`. It does not deploy on pushes. Deployment only runs when the workflow is started manually with **Run workflow**.

Before manual deployment, configure these GitHub Actions repository secrets:

- `CLOUDFLARE_API_TOKEN`: a Cloudflare API token scoped to the correct account with permission to edit Workers.
- `CLOUDFLARE_ACCOUNT_ID`: the Cloudflare account ID.

Never commit these values to the repository.

## Important security and connectivity notes

- The proxy only forwards the fixed `/api` path; it is not an open proxy.
- Keep the Flask server's authentication and per-user permission checks enabled.
- The API origin must remain reachable from Cloudflare. If the ngrok hostname changes, update `API_ORIGIN` and review the change before deployment.
- Browser sessions, login, file operations and every privileged feature must be tested on the deployed URL before using it regularly.
- This worker is separate from `pi-control-public` and has the name `pi-control-dashboard`.
