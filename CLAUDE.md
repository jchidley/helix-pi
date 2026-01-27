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
├── pi-core.scm   # Pure Steel logic (264 LOC, 33 tests)
│   ├── Event handling (text/thinking/tool streaming)
│   ├── RPC message construction
│   └── Session file parsing
└── pi.scm        # Helix integration (317 LOC)
    ├── Buffer management
    ├── Process lifecycle
    └── Callback wiring
```

**Rule**: All logic in pi-core.scm. Helix layer only wires callbacks.

## RPC Protocol

Based on pi-mono reference implementation at `~/git/pi-mono`:

| Reference | Path |
|-----------|------|
| RPC docs | `packages/coding-agent/docs/rpc.md` |
| RPC client | `packages/coding-agent/src/modes/rpc/rpc-client.ts` |
| SDK examples | `packages/coding-agent/examples/sdk/` |
| Agent core | `packages/agent/src/agent.ts` |
| Event types | `packages/agent/src/types.ts` |

Spawns `pi --mode rpc` subprocess, communicates via JSON lines over stdio.

**Key Events**:
| Event | Handling |
|-------|----------|
| `message_update` | Streams `text_delta` and `thinking_delta` |
| `tool_execution_update` | Streams tool output (accumulated→delta) |
| `tool_execution_end` | Shows final result, closes code block |

## Commands

| Command | Description |
|---------|-------------|
| `:pi-start` | Start new session |
| `:pi-continue` | Resume previous (cache-friendly) |
| `:pi-resume` | Picker to select session |
| `:pi-send` | Send prompt |
| `:pi-abort` | Abort operation |
| `:pi-quit` | Close session |

## UI Layout

```
┌─────────────────────┐
│ Original buffer     │  ← close with C-w q
├─────────────────────┤
│ [pi/output]         │  ← streaming output
├─────────────────────┤
│ [pi/input]          │  ← type prompts here
└─────────────────────┘
```

## Critical Gotchas

| Problem | Wrong | Right |
|---------|-------|-------|
| JSON to pipe | `write-line!` | `#%raw-write-string` + `\n` + `flush` |
| JSON keys | `"type"` | `'type` (symbol after parse) |
| define in when | `(when x (define y ...))` | `(when x (let ([y ...]) ...))` |

## Files

| Location | Purpose |
|----------|---------|
| `src/pi-core.scm` | Core logic (testable) |
| `src/pi.scm` | Helix integration |
| `tests/pi-core-test.scm` | 33 unit tests |
| `~/.config/helix/cogs/pi/` | Installed plugin |
