# Pi-Control PC-Agent bridge

This branch adds a **read-only, outbound** bridge between the authenticated Pi-Control AI chat and the PC-Agent. The PC initiates HTTPS requests to the Pi; no inbound port on the PC is opened.

## What the AI can do

When `PI_CONTROL_PC_AGENT_TOKEN` is configured in the Pi-Control server environment, the AI chat advertises two tools:

- `pc_agent_list_files`: list a project folder
- `pc_agent_read_file`: read a text file up to 1 MB

Paths must begin with `pi-control`. This is intentionally limited to the checked-out project, not the whole home folder. The local API also blocks known credential and private-key paths. Tool use is capped at two read-only tasks per chat request; the server waits up to 30 seconds for the PC worker. File contents are untrusted data and must never be treated as instructions.

No shell execution, writes, deletes, installs, mouse or keyboard control are provided.

## Authentication model

- `POST /api/pc-agent/tasks` is restricted to a logged-in Pi-Control administrator session.
- `GET /api/pc-agent/next` and `POST /api/pc-agent/results` require a separate high-entropy bearer token shared only between the Pi server and the PC bridge.
- The PC local API remains on `127.0.0.1:8765`; never expose it with a router port-forward, ngrok, or a public tunnel.
- The task/result queue is currently in memory. Pending tasks and results are lost if the Pi server restarts. This is an MVP, not production-ready.

## Server setup (Raspberry Pi)

Set a unique token of at least 40 characters in the environment used by `pi-control.service`. Generate one locally on the Pi with:

```bash
python3 -c 'import secrets; print(secrets.token_urlsafe(48))'
```

Configure that value as `PI_CONTROL_PC_AGENT_TOKEN` in the service environment, then restart `pi-control.service`. Never commit the token or paste it into GitHub issues, screenshots, or chat messages. The AI tools stay disabled until this environment variable is set.

## PC setup

The scripts assume the repository is at `~/pi-control` on CachyOS/Linux or `%USERPROFILE%\pi-control` on Windows.

CachyOS/Linux:

```bash
bash ~/pi-control/pc-agent/start-bridge.sh
```

Windows PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File "$HOME\pi-control\pc-agent\start-bridge.ps1"
```

The launcher prompts for the Pi-Control HTTPS URL and the same shared token. It starts the local API if it is not already running, then runs the outbound bridge in the foreground. The local API's own random token stays on the PC in `~/.pi-control-agent/token`.

## API protocol

- The authenticated chat submits a task through `POST /api/pc-agent/tasks`.
- The PC polls `GET /api/pc-agent/next` and posts the result to `POST /api/pc-agent/results`.
- The AI chat waits for the matching task ID and then asks Ollama for a final answer.

## Verification still required

This change has regression tests in `server/test_pc_agent_bridge.py`, but they must be run in a Python environment with Flask installed. End-to-end verification against the real Raspberry Pi, the configured Ollama model, the desktop PC, and the ngrok URL is still required before enabling it for everyday use.
