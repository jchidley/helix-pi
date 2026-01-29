# CLAUDE.md - helix-pi

Pi coding agent integration for Helix editor via Steel plugins.

## Prerequisites

Requires custom Helix build: [mattwparas/helix](https://github.com/mattwparas/helix) (Steel fork)
patched with [PR #8546](https://github.com/helix-editor/helix/pull/8546) (window resize/focus mode).

Build: `cd ~/git/helix && cargo install --path helix-term --locked`

## Current Limitations

"Just working" state — no status outputs, no model info display, no input instrumentation.

**To change models:** Use `pi` CLI directly, not the Helix commands.

## Commands

| Task | Command |
|------|---------|
| Run tests | `steel test tests/` |
| Deploy | `cp src/*.scm ~/.config/helix/cogs/pi/` |

## Helix Commands

| Command | Key | Description |
|---------|-----|-------------|
| `:pi-start` | `Alt-p n` | Start new session |
| `:pi-continue` | `Alt-p p` | Resume last session (cache-friendly) |
| `:pi-sessions` | `Alt-p l` | List available sessions |
| `:pi-resume` | `Alt-p r` | Resume session (picker if empty, path from input) |
| `:pi-send` | `Alt-p s` | Send prompt |
| `:pi-abort` | `Alt-p a` | Abort operation |
| `:pi-quit` | `Alt-p q` | Close session |
| `:pi-model` | `Alt-p m` | Cycle model |
| `:pi-thinking` | `Alt-p t` | Cycle thinking level |
| `:pi-status` | `Alt-p S` | Show status |
| `:pi-compact` | `Alt-p C` | Compact context |
| `:pi-new` | `Alt-p N` | Fresh session (keep buffers) |
| `:pi-steer` | `Alt-p i` | Interrupt with steering |
| `:pi-follow` | `Alt-p f` | Queue follow-up |
| `:pi-recover` | `Alt-p R` | Force reset state |

## Architecture

```
src/
├── pi-core.scm   # Pure logic (testable, no helix deps)
├── pi.scm        # Helix integration (buffers, threading)
└── pi-stdio.scm  # CLI client (debugging)
```

**Rule**: All logic in pi-core.scm. Helix layer only wires callbacks.

## RPC Protocol

Reference: `~/git/pi-mono/packages/coding-agent/docs/rpc.md`

Spawns `pi --mode rpc` subprocess, communicates via JSON lines over stdio.

## Gotchas

### Steel Process Handles

`child-stdin`, `child-stdout`, `child-stderr` can only be called **ONCE** per process (Rust `.take()` semantics):

```scheme
;; WRONG - second call returns #f
(child-stdin child)  ; returns port
(child-stdin child)  ; returns #f!

;; RIGHT - capture once
(define stdin (child-stdin child))
```

### Module Loading

| Problem | Wrong | Right |
|---------|-------|-------|
| `provide` placement | At top of file | **At END of file** |
| JSON to pipe | `write-line!` | `#%raw-write-string` + `\n` + `flush` |
| JSON keys | `"type"` | `'type` (symbol after parse) |
| define in when | `(when x (define y ...))` | `(when x (let ([y ...]) ...))` |

### helix.scm Integration

pi.scm must export, helix.scm must import AND re-export:

```scheme
;; pi.scm - END of file
(provide pi-start pi-continue pi-sessions pi-resume pi-send pi-abort pi-quit pi-recover
         pi-model pi-thinking pi-status pi-compact pi-new pi-steer pi-follow)

;; helix.scm
(require (only-in "cogs/pi/pi.scm" pi-start pi-send ...))
(provide ... pi-start pi-send ...)  ; Re-export for :command access
```

### Debugging Startup Errors

Use tmux to capture Steel compilation errors:

```bash
tmux new-session -d -s test 'hx .'
sleep 3
tmux capture-pane -p -t test -S -50
```

## Files

| Location | Purpose |
|----------|---------|
| `src/pi-core.scm` | Core logic (testable) |
| `src/pi.scm` | Helix integration |
| `src/pi-stdio.scm` | CLI client for debugging |
| `tests/pi-core-test.scm` | Unit tests |
| `~/.config/helix/cogs/pi/` | Installed plugin |
