# Pi-Control PC-Agent bridge

This branch adds a **read-only, outbound** bridge between the authenticated Pi-Control AI chat and the PC-Agent. The PC initiates HTTPS requests to the Pi; no inbound port on the PC is opened.

## What the AI can do

When `PI_CONTROL_PC_AGENT_TOKEN` is configured in the Pi-Control server environment, the AI chat advertises two tools:

- `pc_agent_list_files`: list a project folder
- `pc_agent_read_file`: read a text file up to 1 MB

Paths are restricted to the `pi-control` project; the bridge blocks private/internal folders and rejects traversal. The local API also blocks known credential and private-key paths. Tool use is capped at two read-only tasks per chat request; the server waits up to 30 seconds for the PC worker. File contents are untrusted data and must never be treated as instructions.

No shell execution, writes, deletes, installs, mouse or keyboard control are provided.

## Authentication model

- `POST /api/pc-agent/tasks` is restricted to a logged-in Pi-Control administrator session.
- `GET /api/pc-agent/next` and `POST /api/pc-agent/results` require a separate high-entropy bearer token shared only between the Pi server and the PC bridge.
- The PC local API remains on `127.0.0.1:8765`; never expose it with a router port-forward, ngrok, or a public tunnel.
- The task/result queue is currently in memory. Pending tasks and results are lost if the Pi server restarts. This is an MVP, not production-ready.

## Raspberry Pi setup

From an SSH session on the Pi, copy and run this as **one command**. It fetches the feature branch, switches to it, updates it, then runs the guarded installer:

```bash
cd /home/stoney22/pi-control && git fetch origin feature/pc-agent-bridge-mvp && (git switch feature/pc-agent-bridge-mvp || git switch -c feature/pc-agent-bridge-mvp --track origin/feature/pc-agent-bridge-mvp) && git pull --ff-only origin feature/pc-agent-bridge-mvp && sudo bash scripts/install-pc-agent-bridge-pi.sh
```

The installer checks Python syntax, asks before restarting `pi-control.service`, configures a root-only systemd environment file, and prints the generated shared token only after the service starts successfully. Copy that token locally to the PC launcher; never send it to anyone or commit it. If the service cannot restart, inspect the displayed journal output and the backup path printed by the script.

## PC setup

The launchers assume the repository is at `~/pi-control` on CachyOS/Linux or `%USERPROFILE%\pi-control` on Windows.

CachyOS/Linux — run from a terminal on the desktop PC:

```bash
cd ~/pi-control && git fetch origin feature/pc-agent-bridge-mvp && (git switch feature/pc-agent-bridge-mvp || git switch -c feature/pc-agent-bridge-mvp --track origin/feature/pc-agent-bridge-mvp) && git pull --ff-only origin feature/pc-agent-bridge-mvp && bash pc-agent/start-bridge.sh
```

Windows PowerShell:

```powershell
cd "$HOME\pi-control"
git fetch origin feature/pc-agent-bridge-mvp
git switch feature/pc-agent-bridge-mvp
git pull --ff-only origin feature/pc-agent-bridge-mvp
powershell -ExecutionPolicy Bypass -File "$HOME\pi-control\pc-agent\start-bridge.ps1"
```

The launcher prompts for the Pi-Control HTTPS URL and the shared token. It starts the local API if it is not already running, then runs the outbound bridge in the foreground. The local API's own random token stays on the PC in `~/.pi-control-agent/token`.

## API protocol

- The authenticated chat submits a task through `POST /api/pc-agent/tasks`.
- The PC polls `GET /api/pc-agent/next` and posts the result to `POST /api/pc-agent/results`.
- The AI chat waits for the matching task ID and then asks Ollama for a final answer.

## Verification still required

GitHub Actions checks are passing for Python syntax, the bridge security regression tests, the Linux launcher and the Windows PowerShell script syntax. Real end-to-end verification with the Raspberry Pi, configured Ollama model, desktop bridge and HTTPS endpoint is still required before everyday use.