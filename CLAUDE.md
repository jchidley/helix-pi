# CLAUDE.md - helix-pi

Pi coding agent integration for Helix editor via Steel (Scheme) plugins.

## Overview

This project creates a Helix plugin that connects to pi coding agent via RPC, providing:
- Split-buffer UI: editable input + read-only markdown output
- Streaming responses from LLM
- Full Helix modal editing for prompts

## Quick Reference

| Task | Command |
|------|---------|
| Build Helix with Steel | `cd ~/git/helix && cargo xtask steel` |
| Run Helix | `~/git/helix/target/release/hx` |
| Steel REPL | `steel` |
| Eval in Helix | `:evalp` → expression → Enter |
| Start pi RPC | `pi --mode rpc --no-session` |

## Project Structure

```
helix-pi/
├── CLAUDE.md                    # This file (LLM context)
├── README.md                    # Human signpost
├── steel-helix-development.md   # Comprehensive Steel dev guide
├── docs/
│   ├── architecture.md          # Design decisions (explanation)
│   ├── phase1-design.md         # Phase 1 spec (explanation)
│   ├── tutorial.md              # First plugin tutorial
│   └── patterns.md              # Plugin patterns reference
└── examples/
    └── community-plugins/       # Reference implementations
```

## Phase 1 Focus: Two-Buffer RPC

```
┌──────────────────────────────┐
│  Output Buffer (markdown)    │  ← agent responses, read-only
├──────────────────────────────┤
│  Input Buffer (plain text)   │  ← user prompts, editable
└──────────────────────────────┘
         │ JSON/stdio │
         ▼            ▲
    pi --mode rpc --no-session
```

**RPC commands**: `prompt`, `abort`, `get_state`
**Key events**: `agent_start`, `message_update` (delta), `agent_end`

## Steel Essentials

```scheme
;; JSON encode/decode
(value->jsexpr-string (hash "type" "prompt" "message" "Hello"))
(string->jsexpr "{\"type\": \"response\"}")

;; Process I/O
(require-builtin steel/process)
(spawn-process (with-stdout-piped (with-stdin-piped (command "pi" args))))
(write-line! stdin json-string)
(read-line-from-port stdout)

;; Async (for event loop)
(spawn-native-thread (lambda () ...))
(hx.block-on-task (lambda () ...))  ; Update UI from thread
```

## Key Config Files

| File | Purpose |
|------|---------|
| `~/.config/helix/helix.scm` | Exported commands (loads first) |
| `~/.config/helix/init.scm` | Config, keybindings (loads second) |

## Reference Repos

| Repo | Path | Use |
|------|------|-----|
| pi-mono | ~/git/pi-mono | RPC types in `packages/coding-agent/src/modes/rpc/` |
| helix-config | ~/git/helix-config | Labelled buffer pattern in `cogs/labelled-buffers.scm` |
| helix | ~/git/helix | Steel docs in `STEEL.md`, `steel-docs.md` |

## Gotchas

- `helix.scm` loads before editor context; use `(provide fn)` to export
- Helix APIs only work in Helix, not standalone Steel REPL
- Long-running code blocks UI; use `spawn-native-thread` + `hx.block-on-task`
- JSON keys become symbols in Steel: `(hash-ref event 'type)` not `"type"`
