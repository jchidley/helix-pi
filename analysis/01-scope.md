# Phase 1: Scope

## Metrics

| Metric | Value |
|--------|-------|
| Files | 1 |
| LOC | 507 |
| Entry points | 6 (all exported) |

## Entry Points

| Symbol | Description |
|--------|-------------|
| `pi-start` | Start new session |
| `pi-continue` | Resume last session with history |
| `pi-resume` | Picker to select any session |
| `pi-send` | Send prompt to pi |
| `pi-abort` | Abort current operation |
| `pi-quit` | Close session gracefully |

## Logical Sections

| Section | Lines | LOC | Description |
|---------|-------|-----|-------------|
| Header/requires | 1-24 | 24 | Imports and exports |
| Constants | 26-40 | 15 | Buffer names, home dir, sessions dir |
| State | 42-47 | 6 | Global mutable state |
| Helpers | 51-56 | 6 | request-id counter, running check |
| Buffer mgmt | 60-100 | 41 | Create/clear/append/get buffers |
| RPC | 104-122 | 19 | JSON-RPC send, prompt, abort |
| Event handling | 126-212 | 87 | Handle pi events, event loop |
| Session discovery | 216-367 | 152 | **Largest section** - parse sessions |
| Commands | 371-507 | 137 | Public API + spawn helpers |

## Data Flow

```
User command → spawn pi process → RPC send → event loop reads stdout
                                           ↓
                              pi-handle-event → append to output buffer
```

Session resume flow:
```
pi-continue/resume → find session file → spawn process → display-session-history → event loop
```

## Dependencies (external)

| Require | Usage |
|---------|-------|
| steel/process | spawn-process, command, ports |
| steel/result | Ok?, unwrap-ok |
| helix/commands | (prefixed helix.) |
| helix/static | select_all, delete_selection, insert_string, etc. |
| helix/editor | editor state |
| helix/misc | set-status! |
| helix/ext | hx.block-on-task |
| labelled-buffers | make-new-labelled-buffer!, open-labelled-buffer |
| picker | picker-selection |

## Gate 1 Decision

**LOC < 1500 → INLINE all phases.**

Single file, clear sections, no subagents needed.
