# PC Agent persistent memory

This package provides the durable journal used by the PC Agent to resume work
after a process restart. It stores state locally in SQLite and does not send
task history to an external service.

## Storage

By default, the database is stored at:

`~/.local/share/pi-control/agent-memory.sqlite3`

Set `PI_CONTROL_AGENT_MEMORY_DB` to use a different path. Keep the database
outside Git and do not put it in a public web directory: task logs can contain
file paths and diagnostic output.

## Integration contract

The PC Agent HTTP server should create one `AgentMemory()` instance when it
starts and call it at each meaningful state transition:

1. `start_task(title, goal)` when the user submits a task.
2. `record_step(..., status="in_progress")` before/after each bounded action.
3. `record_step(..., status="paused")` when waiting for approval or when work
   stops, including the next step to resume.
4. `record_step(..., status="failed")` when a command or test fails. Preserve
   the real exit code and a short error summary in `details`.
5. `record_step(..., status="completed")` only after verification actually
   passes. Never mark a task complete just because a command was launched.
6. On server startup, use `resume_context()` to show the latest in-progress
   or paused task and its recent journal entries.

The journal records progress; it is not an authorization system. Existing
approval checks must still gate file writes, deletes, shell commands, commits,
deployments, and other consequential actions. Never store secrets or entire
environment dumps in event details.

## Tests

Run from the repository root:

```sh
python -m unittest pc_agent.test_memory
```

The PC Agent HTTP server itself must import and use this package for memory to
be visible in the UI. This package alone does not start autonomous work.
