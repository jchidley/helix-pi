# Phase 3: Dependency Graph

## Call Graph

```
pi-start
  └── pi-spawn-process
        ├── spawn-process (external)
        ├── pi-create-buffers
        │     ├── maybe-fetch-doc-id (external)
        │     ├── pi-clear-output
        │     │     └── open-labelled-buffer, helix.static.*
        │     ├── make-new-labelled-buffer! (external)
        │     └── open-labelled-buffer (external)
        ├── pi-event-loop
        │     ├── spawn-native-thread (external)
        │     ├── read-line-from-port (external)
        │     ├── string->jsexpr (external)
        │     ├── hx.block-on-task (external)
        │     └── pi-handle-event
        │           ├── pi-append-output
        │           └── set-status! (external)
        └── pi-append-output

pi-continue
  ├── get-cwd-latest-session
  │     ├── current-directory (external)
  │     ├── path-to-session-dir-name
  │     ├── pi-sessions-dir
  │     │     └── get-home-dir
  │     ├── path-exists? (external)
  │     └── get-latest-session-file
  │           └── read-dir, ends-with?, sort (external)
  ├── pi-spawn-process-with-history
  │     ├── spawn-process (external)
  │     ├── pi-create-buffers
  │     ├── pi-event-loop
  │     ├── display-session-history
  │     │     ├── call-with-input-file (external)
  │     │     ├── read-line-from-port (external)
  │     │     ├── string->jsexpr (external)
  │     │     ├── get-text-parts
  │     │     └── pi-append-output
  │     └── pi-append-output
  └── pi-spawn-process (fallback)

pi-resume
  ├── list-sessions-for-cwd
  │     ├── current-directory (external)
  │     ├── path-to-session-dir-name
  │     ├── pi-sessions-dir
  │     ├── path-exists? (external)
  │     ├── read-dir (external)
  │     ├── get-first-user-message
  │     │     ├── call-with-input-file (external)
  │     │     ├── read-line-from-port (external)
  │     │     └── string->jsexpr (external)
  │     └── sort (external)
  ├── push-component! (external)
  ├── picker-selection (external)
  └── pi-spawn-process-with-history (callback)

pi-send
  ├── pi-running?
  ├── pi-get-input
  ├── pi-rpc-prompt
  │     └── pi-rpc-send
  │           ├── next-request-id
  │           ├── value->jsexpr-string (external)
  │           ├── #%raw-write-string (external)
  │           └── flush-output-port (external)
  └── pi-clear-input

pi-abort
  ├── pi-running?
  └── pi-rpc-abort
        └── pi-rpc-send

pi-quit
  └── close-output-port (external)
```

## Shared State Access

| State Variable | Writers | Readers |
|----------------|---------|---------|
| `*home-dir*` | get-home-dir | get-home-dir |
| `*pi-process*` | pi-spawn-process, pi-spawn-process-with-history, pi-quit | pi-running?, pi-quit |
| `*pi-stdin*` | pi-spawn-process, pi-spawn-process-with-history, pi-quit | pi-running?, pi-rpc-send, pi-quit |
| `*pi-stdout*` | pi-spawn-process, pi-spawn-process-with-history, pi-quit | pi-running?, pi-event-loop |
| `*pi-request-id*` | next-request-id | next-request-id |
| `*pi-is-streaming*` | pi-handle-event, pi-quit | (unused read) |
| `*pi-session-map*` | pi-resume | pi-resume (callback) |

## Observations

1. **pi-spawn-process vs pi-spawn-process-with-history** - 90% identical code (DRY violation)
2. **list-sessions** - defined but unused (YAGNI candidate)
3. **pi-rpc-get-state** - defined but unused (YAGNI candidate)
4. **`*pi-is-streaming*`** - written but never read (YAGNI candidate)
5. **session parsing logic** duplicated between `get-first-user-message` and `display-session-history`
