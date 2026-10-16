# Pi-Control PC-Agent outbound bridge (MVP)

This is a first read-only bridge prototype. The PC initiates HTTPS requests to the Pi;
no inbound port on the PC is opened.

## Server (Raspberry Pi)

Set a unique, high-entropy token in the environment used by `pi-control.service`:

```ini
Environment="PI_CONTROL_PC_AGENT_TOKEN=replace-with-a-long-random-secret"
```

Use the *same* secret on the PC. Do not commit the secret or expose it in screenshots.
Then restart the Pi-Control service after installing the code.

## PC (Linux or Windows)

Start the local API from `pc-agent/local_api.py` first. Then set:

- `PI_CONTROL_SERVER_URL`: the Pi-Control public HTTPS URL (for example your existing HTTPS URL)
- `PI_CONTROL_PC_AGENT_TOKEN`: the same secret as the server
- Optional `PI_CONTROL_LOCAL_AGENT_URL`: defaults to `http://127.0.0.1:8765`

Run `python pc-agent/bridge_client.py`.

## API protocol

- `POST /api/pc-agent/tasks` with `{"action":"list_files","path":"pi-control"}` or `{"action":"read_file","path":"pi-control/README.md"}`
- The PC polls `GET /api/pc-agent/next` and posts completion to `POST /api/pc-agent/results`.
- Fetch results with `GET /api/pc-agent/results`.

All endpoints require the bearer token. Only `list_files` and `read_file` are accepted; no shell, writes, deletes, mouse or keyboard controls exist. The local agent still enforces its own access-root and sensitive-path protections.

## Current limitation

This prototype queue is in-memory (pending tasks/results disappear when the server restarts) and is not yet connected to the Pi-Control AI chat UI. Do not consider it production-ready until the UI integration, persistent queue, HTTPS configuration and end-to-end tests are completed. Do not forward port 8765 or tunnel it with ngrok.
