# CLAUDE.md - helix-pi

Pi coding agent integration for Helix editor via Steel plugins.

## Quick Reference

| Task | Command |
|------|---------|
| Build Helix | `cd ~/git/helix && cargo xtask steel` |
| Run Helix | `~/git/helix/target/release/hx` |
| Steel REPL | `steel` |
| Steel interactive | `steel interactive file.scm` |
| Unit tests | `steel test tests.scm` |

## Plugin Commands

| Command | Description |
|---------|-------------|
| `:pi-start` | Start new session |
| `:pi-continue` | Resume previous session (cache-friendly) |
| `:pi-resume` | Picker to select any session to resume |
| `:pi-send` | Send prompt |
| `:pi-abort` | Abort operation |
| `:pi-quit` | Close session |

## Debugging Workflow

```
1. steel interactive plugin.scm   ← Test pure Scheme (no helix APIs)
2. :open-debug-window             ← See displayln output
3. :eval-buffer                   ← Hot reload changes
4. :evalp (expr)                  ← Quick expression test
```

**Do NOT use tmux** for development. Use official tools above.

## Critical Gotchas

| Problem | Wrong | Right |
|---------|-------|-------|
| JSON to pipe | `write-line!` (adds quotes) | `#%raw-write-string` + `\n` |
| Pipe flush | (nothing) | `flush-output-port` after write |
| JSON keys | `"type"` | `'type` (symbol) |
| Void in cond | `(void)` | `#f` |
| String coercion | `symbol->string` | `to-string` (universal) |
| eval-buffer | Not available by default | Add to helix.scm provides |
| define in when | `(when x (define y ...))` | `(when x (let ([y ...]) ...))` |

## Key Files

| File | Purpose |
|------|---------|
| `~/.config/helix/helix.scm` | Exported commands |
| `~/.config/helix/cogs/pi/pi.scm` | Plugin source |
| `~/.config/helix/init.scm` | Config, keybindings |

## Process I/O Pattern

```scheme
(require-builtin steel/process)
(require "steel/result")

;; Spawn with pipes
(define child (unwrap-ok (spawn-process 
  (with-stdout-piped (with-stdin-piped 
    (command "pi" '("--mode" "rpc")))))))

;; Write JSON (MUST use raw write + flush)
(#%raw-write-string json-str (child-stdin child))
(#%raw-write-string "\n" (child-stdin child))
(flush-output-port (child-stdin child))

;; Read response
(define line (read-line-from-port (child-stdout child)))
(define event (string->jsexpr line))  ; Keys are symbols!
(hash-try-get event 'type)  ; Use 'type not "type"
```

## Background Thread Pattern

```scheme
(require (only-in "helix/ext.scm" hx.block-on-task))

(spawn-native-thread
  (lambda ()
    (let loop ()
      (define line (read-line-from-port stdout))
      (when line
        (hx.block-on-task  ; Required for UI updates
          (lambda () (handle-event line)))
        (loop)))))
```

## Adding eval-buffer

Required in `~/.config/helix/helix.scm`:
```scheme
(require (only-in "helix/ext.scm" eval-buffer))
;; In (provide ...):
eval-buffer
```

## Project Structure

```
helix-pi/
├── src/pi.scm              # MVP plugin source
├── docs/debugging.md       # How-to: debugging workflow
├── docs/architecture.md    # Design decisions
└── examples/               # Community plugin references
```

## See Also

- `~/git/helix/STEEL.md` - Official Steel docs
- `~/git/helix-config/` - Reference plugins
- `~/git/pi-mono/packages/coding-agent/src/modes/rpc/` - RPC types
