# CLAUDE.md - helix-pi

Pi coding agent integration for Helix editor via Steel plugins.

## Quick Reference

| Task | Command |
|------|---------|
| Run tests | `steel test tests/` |
| Interactive REPL | `steel interactive src/pi-core.scm` |
| Deploy to Helix | `cp src/*.scm ~/.config/helix/cogs/pi/` |

## Architecture

```
src/
├── pi-core.scm   # Pure Steel logic (testable, no helix deps)
│   ├── Event handling (text/thinking/tool streaming)
│   ├── RPC message construction
│   └── Session file parsing
└── pi.scm        # Helix integration
    ├── Buffer management
    ├── Process lifecycle
    └── Callback wiring
```

**Rule**: All logic in pi-core.scm. Helix layer only wires callbacks.

## RPC Protocol

Based on pi-mono reference at `~/git/pi-mono`:

| Reference | Path |
|-----------|------|
| RPC docs | `packages/coding-agent/docs/rpc.md` |
| RPC client | `packages/coding-agent/src/modes/rpc/rpc-client.ts` |
| Event types | `packages/agent/src/types.ts` |

Spawns `pi --mode rpc` subprocess, communicates via JSON lines over stdio.

## Commands

| Command | Description |
|---------|-------------|
| `:pi-start` | Start new session |
| `:pi-continue` | Resume previous (cache-friendly) |
| `:pi-send` | Send prompt |
| `:pi-abort` | Abort operation |
| `:pi-quit` | Close session |
| `:pi-recover` | Force reset state |

## Critical Gotchas

### Steel Module Loading (IMPORTANT)

| Problem | Wrong | Right |
|---------|-------|-------|
| `provide` placement | At top of file | **At END of file, after all defines** |
| Export from sub-module | `(require "mod.scm")` | `(require (only-in "mod.scm" fn1 fn2))` then re-export in helix.scm's `provide` |
| JSON to pipe | `write-line!` | `#%raw-write-string` + `\n` + `flush` |
| JSON keys | `"type"` | `'type` (symbol after parse) |
| define in when | `(when x (define y ...))` | `(when x (let ([y ...]) ...))` |

### helix.scm Integration Pattern

pi.scm must export functions, helix.scm must import AND re-export:

```scheme
;; pi.scm - END of file
(provide pi-start pi-send pi-abort pi-quit pi-continue pi-resume pi-recover)

;; helix.scm
(require (only-in "cogs/pi/pi.scm" 
                  pi-start pi-send pi-abort pi-quit 
                  pi-continue pi-resume pi-recover))

(provide ... pi-start pi-send ...)  ; Re-export for :command access
```

### Debugging Helix Startup Errors

Use tmux to see Steel compilation errors (they scroll by too fast otherwise):

```bash
SESSION="$(date +%s%N | sha256sum | head -c 6)"
SOCKET="/tmp/tmux-$SESSION.sock"
TMUX= tmux -S "$SOCKET" new -d -s "$SESSION"
tmux -S "$SOCKET" send-keys -t "$SESSION":0.0 -- 'hx .' Enter
sleep 3
tmux -S "$SOCKET" capture-pane -p -J -t "$SESSION":0.0 -S -50
```

## Files

| Location | Purpose |
|----------|---------|
| `src/pi-core.scm` | Core logic (testable) |
| `src/pi.scm` | Helix integration |
| `tests/pi-core-test.scm` | Unit tests |
| `~/.config/helix/cogs/pi/` | Installed plugin |
| `~/.config/helix/helix.scm` | Must import and re-export pi commands |
