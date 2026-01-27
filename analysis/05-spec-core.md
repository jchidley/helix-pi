# Spec: core

## Observable Behaviours

### pi-start
- **Pre**: pi not running
- **Post**: pi process spawned with `--mode rpc`, buffers created, event loop running
- **Side-effects**: sets *pi-process*, *pi-stdin*, *pi-stdout*; creates PI-OUTPUT, PI-INPUT buffers
- **Error**: if already running, sets status "pi: already running"

### pi-continue
- **Pre**: pi not running
- **Post**: pi process spawned with `--mode rpc --continue`, session history displayed in output buffer
- **Side-effects**: same as pi-start + reads session file
- **Error**: if already running, sets status; if no session, spawns anyway

### pi-resume
- **Pre**: pi not running
- **Post**: picker shown with session list; on selection, spawns with `--session <file>`
- **Side-effects**: sets *pi-session-map*, pushes picker component
- **Error**: if already running or no sessions, sets status

### pi-send
- **Pre**: pi running, input buffer has text
- **Post**: RPC prompt sent, input cleared
- **Side-effects**: writes to *pi-stdin*, clears PI-INPUT buffer
- **Error**: if not running or empty input, sets status

### pi-abort
- **Pre**: pi running
- **Post**: RPC abort sent
- **Side-effects**: writes to *pi-stdin*
- **Error**: if not running, sets status

### pi-quit
- **Pre**: pi running (or not - silent no-op)
- **Post**: stdin closed, state reset
- **Side-effects**: closes *pi-stdin*, sets *pi-process*/*pi-stdin*/*pi-stdout*/*pi-is-streaming* to #f

### pi-running? [pure]
- Returns #t iff all of *pi-process*, *pi-stdin*, *pi-stdout* are truthy

### pi-spawn-process [side-effects: process, state, buffers]
- Spawns pi with given args
- On success: sets state vars, creates buffers, starts event loop, appends welcome-msg
- On failure: sets status "pi: failed to start process"

### pi-spawn-process-with-history [side-effects: process, state, buffers, file I/O]
- Same as pi-spawn-process but calls display-session-history instead of welcome-msg
