# Agent Instructions

See **[CLAUDE.md](./CLAUDE.md)** for full documentation.

## Prerequisites

Requires: [mattwparas/helix](https://github.com/mattwparas/helix) + [PR #8546](https://github.com/helix-editor/helix/pull/8546)

## Limitations

Bare input buffer — no progress, model info, or instrumentation. Use `pi` CLI to change models.

## Commands

| Task | Command |
|------|---------|
| Run tests | `steel test tests/` |
| Deploy | `cp src/*.scm ~/.config/helix/cogs/pi/` |

## Critical

**`provide` must be at END of file**, after all definitions.

```scheme
(define (pi-start) ...)
;; ... all definitions ...
(provide pi-start ...)  ; LAST LINE
```
