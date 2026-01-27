# Agent Instructions

See **[CLAUDE.md](./CLAUDE.md)** for full documentation.

## Reference Implementation

`~/git/pi-mono` contains pi-agent reference code:
- `packages/coding-agent/docs/rpc.md` - RPC protocol spec
- `packages/coding-agent/src/modes/rpc/rpc-client.ts` - TypeScript RPC client
- `packages/agent/src/types.ts` - Event type definitions

## Commands

| Task | Command |
|------|---------|
| Run tests | `steel test tests/` |
| Deploy | `cp src/*.scm ~/.config/helix/cogs/pi/` |
| REPL | `steel interactive src/pi-core.scm` |

## Helix Commands

`:pi-start`, `:pi-continue`, `:pi-send`, `:pi-abort`, `:pi-quit`, `:pi-recover`

## Critical: Steel Module Pattern

**`provide` must be at END of file**, after all definitions. Helix's module loader differs from standalone Steel.

```scheme
;; pi.scm structure
(require ...)
(require "pi-core.scm")

(define (pi-start) ...)
(define (pi-send) ...)
;; ... all definitions ...

;; LAST LINE - after all defines
(provide pi-start pi-send pi-abort pi-quit pi-continue pi-resume pi-recover)
```

helix.scm must import with `only-in` and re-export via its `provide`.

## Debugging

Use tmux to capture helix startup errors. Do NOT use tmux for interactive Steel debugging - use `steel interactive` or `:open-debug-window` in helix.
