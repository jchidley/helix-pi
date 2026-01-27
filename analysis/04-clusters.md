# Phase 4: Clusters

## Cluster Assignments

| Cluster | Symbols | LOC | Cohesion |
|---------|---------|-----|----------|
| **core** | pi-start, pi-continue, pi-resume, pi-send, pi-abort, pi-quit, pi-spawn-process, pi-spawn-process-with-history, pi-running? | ~120 | Public API + spawn |
| **buffers** | pi-create-buffers, pi-clear-output, pi-clear-input, pi-append-output, pi-get-input, PI-OUTPUT, PI-INPUT | ~50 | Buffer CRUD |
| **rpc** | pi-rpc-send, pi-rpc-prompt, pi-rpc-abort, pi-rpc-get-state, next-request-id, *pi-request-id* | ~25 | JSON-RPC protocol |
| **events** | pi-handle-event, pi-event-loop, *pi-is-streaming* | ~90 | Event stream processing |
| **sessions** | get-home-dir, pi-sessions-dir, session-dir-to-display-name, get-latest-session-file, get-first-user-message, get-text-parts, display-session-history, list-sessions, path-to-session-dir-name, get-cwd-latest-session, list-sessions-for-cwd, *home-dir*, *pi-session-map* | ~170 | Session discovery & history |
| **state** | *pi-process*, *pi-stdin*, *pi-stdout* | 3 | Process handles (shared) |

## Issues

### Gods (>5 callees)
| Symbol | Callees |
|--------|---------|
| `pi-spawn-process` | 6 (spawn-process, pi-create-buffers, pi-event-loop, pi-append-output, set-status!, child-*) |
| `pi-spawn-process-with-history` | 7 (same + display-session-history) |
| `pi-handle-event` | 6+ (many hash-try-get, pi-append-output, set-status!, for-each) |
| `display-session-history` | 6 (call-with-input-file, read-line-from-port, string->jsexpr, get-text-parts, pi-append-output) |

### Orphans (no internal callers)
| Symbol | Status |
|--------|--------|
| `list-sessions` | **Dead code** - never called |
| `pi-rpc-get-state` | **Dead code** - never called |
| `*pi-is-streaming*` | **Write-only** - set but never read |

### Circular Dependencies
None detected.

### DRY Candidates
| Pattern | Locations |
|---------|-----------|
| spawn-process + setup state + create-buffers + event-loop | pi-spawn-process, pi-spawn-process-with-history |
| parse session file + iterate lines + extract message | get-first-user-message, display-session-history |
| hash-try-get chains | pi-handle-event (8x), display-session-history (6x), get-first-user-message (5x) |

## Priority Order (for Loop 3)

1. **sessions** (170 LOC) - largest, has DRY violations, dead code
2. **core** (120 LOC) - DRY violation between spawn functions
3. **events** (90 LOC) - god function, write-only state
4. **buffers** (50 LOC) - clean
5. **rpc** (25 LOC) - has dead code (pi-rpc-get-state)
