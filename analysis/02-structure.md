# Phase 2: Structure Map

## Symbol Table

| Symbol | Line | Kind | Visibility | Signature/Type |
|--------|------|------|------------|----------------|
| **Constants** |
| `PI-OUTPUT` | 27 | const | private | `"pi/output"` |
| `PI-INPUT` | 28 | const | private | `"pi/input"` |
| **State** |
| `*home-dir*` | 31 | state | private | `#f \| string` |
| `*pi-process*` | 43 | state | private | `#f \| child-process` |
| `*pi-stdin*` | 44 | state | private | `#f \| output-port` |
| `*pi-stdout*` | 45 | state | private | `#f \| input-port` |
| `*pi-request-id*` | 46 | state | private | `integer` |
| `*pi-is-streaming*` | 47 | state | private | `boolean` |
| `*pi-session-map*` | 368 | state | private | `hash` |
| **Helpers** |
| `get-home-dir` | 32 | fn | private | `() -> string` |
| `pi-sessions-dir` | 39 | fn | private | `() -> string` |
| `next-request-id` | 51 | fn | private | `() -> string` |
| `pi-running?` | 55 | fn | private | `() -> boolean` |
| **Buffer Management** |
| `pi-create-buffers` | 60 | fn | private | `() -> void` |
| `pi-clear-output` | 76 | fn | private | `() -> void` |
| `pi-clear-input` | 96 | fn | private | `() -> void` |
| `pi-append-output` | 82 | fn | private | `(text: string) -> void` |
| `pi-get-input` | 88 | fn | private | `() -> string` |
| **RPC** |
| `pi-rpc-send` | 104 | fn | private | `(command: hash) -> string \| #f` |
| `pi-rpc-prompt` | 117 | fn | private | `(message: string) -> string \| #f` |
| `pi-rpc-abort` | 120 | fn | private | `() -> string \| #f` |
| `pi-rpc-get-state` | 123 | fn | private | `() -> string \| #f` (unused) |
| **Event Handling** |
| `pi-handle-event` | 127 | fn | private | `(event: hash) -> void` |
| `pi-event-loop` | 203 | fn | private | `() -> void` |
| **Session Discovery** |
| `session-dir-to-display-name` | 216 | fn | private | `(dir-name: string) -> string` |
| `get-latest-session-file` | 241 | fn | private | `(session-dir: string) -> string \| #f` |
| `get-first-user-message` | 252 | fn | private | `(session-file: string) -> string` |
| `get-text-parts` | 280 | fn | private | `(content: list \| #f) -> list<string>` |
| `display-session-history` | 290 | fn | private | `(session-file: string) -> void` |
| `list-sessions` | 323 | fn | private | `() -> list<pair>` (unused) |
| `path-to-session-dir-name` | 340 | fn | private | `(path: string) -> string` |
| `get-cwd-latest-session` | 344 | fn | private | `() -> string \| #f` |
| `list-sessions-for-cwd` | 353 | fn | private | `() -> list<pair>` |
| **Commands (public)** |
| `pi-start` | 374 | fn | **public** | `() -> void` |
| `pi-continue` | 380 | fn | **public** | `() -> void` |
| `pi-resume` | 392 | fn | **public** | `() -> void` |
| `pi-send` | 464 | fn | **public** | `() -> void` |
| `pi-abort` | 476 | fn | **public** | `() -> void` |
| `pi-quit` | 484 | fn | **public** | `() -> void` |
| **Internal Spawn** |
| `pi-spawn-process` | 418 | fn | private | `(args: list, welcome-msg: string) -> void` |
| `pi-spawn-process-with-history` | 438 | fn | private | `(args: list, session-file: string) -> void` |

## Counts

| Kind | Count |
|------|-------|
| Constants | 2 |
| State vars | 7 |
| Private fns | 25 |
| Public fns | 6 |
| **Total symbols** | 40 |
