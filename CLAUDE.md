# CLAUDE.md - helix-pi

Pi coding agent integration for Helix editor via Steel plugins.

## Quick Reference

| Task | Command |
|------|---------|
| Run tests | `cd ~/git/helix-pi && steel test tests/` |
| Interactive REPL | `steel interactive src/pi-core.scm` |
| Build Helix | `cd ~/git/helix && cargo xtask steel` |
| Run Helix | `~/git/helix/target/release/hx` |

## Architecture

```
pi-core.scm  →  Pure Steel logic (testable, 33 tests)
pi.scm       →  Thin Helix integration (callbacks only)
```

**Rule**: All logic goes in pi-core.scm. Helix layer only wires callbacks.

## Plugin Commands

| Command | Description |
|---------|-------------|
| `:pi-start` | Start new session |
| `:pi-continue` | Resume previous session (cache-friendly) |
| `:pi-resume` | Picker to select session |
| `:pi-send` | Send prompt |
| `:pi-abort` | Abort operation |
| `:pi-quit` | Close session |

## UI Layout

Horizontal layout with pi buffers:
- **Top**: Original buffer (close with `C-w q` if not needed)
- **Middle**: Output buffer `[pi/output]`  
- **Bottom**: Input buffer `[pi/input]` (focus here)

Auto-scrolls output to show new content.

## Project Structure

```
helix-pi/
├── src/
│   ├── pi-core.scm         # Pure Steel (event handling, RPC, sessions)
│   └── pi.scm              # Helix integration
├── tests/
│   └── pi-core-test.scm    # 33 unit tests
└── docs/
    └── debugging.md        # Testing workflow
```

## Critical Gotchas

| Problem | Wrong | Right |
|---------|-------|-------|
| JSON to pipe | `write-line!` | `#%raw-write-string` + `\n` + `flush-output-port` |
| JSON keys | `"type"` | `'type` (symbol after parse) |
| define in when | `(when x (define y ...))` | `(when x (let ([y ...]) ...))` |

## Key Files

| File | Purpose |
|------|---------|
| `~/.config/helix/cogs/pi/pi.scm` | Installed plugin |
| `~/.config/helix/cogs/pi/pi-core.scm` | Installed core |
| `~/.config/helix/helix.scm` | Command exports |

## Deploy Changes

```bash
cp ~/git/helix-pi/src/*.scm ~/.config/helix/cogs/pi/
```

Then restart Helix.
