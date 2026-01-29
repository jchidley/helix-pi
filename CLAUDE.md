# CLAUDE.md - helix-pi

Pi coding agent integration for Helix editor via Steel plugins.

## Commands

| Task | Command |
|------|---------|
| Test | `steel test tests/` |
| Deploy | `cp src/*.scm ~/.config/helix/cogs/pi/` |

## Prerequisites

Custom Helix: [mattwparas/helix](https://github.com/mattwparas/helix) + [PR #8546](https://github.com/helix-editor/helix/pull/8546)

Build: `cd ~/git/helix && cargo install --path helix-term --locked`

## Limitations

Bare integration — no status, model info, or instrumentation. Use `pi` CLI to change models.

## Architecture

```
src/
├── pi-core.scm   # Pure logic (testable)
├── pi.scm        # Helix integration
└── pi-stdio.scm  # CLI debugging client
```

Rule: Logic in pi-core.scm. Helix layer wires callbacks only.

## Gotchas

### `provide` at END of file

```scheme
(define (pi-start) ...)
(provide pi-start ...)  ; LAST LINE
```

### Steel process handles — call ONCE

```scheme
;; WRONG
(child-stdin child)  ; returns port
(child-stdin child)  ; returns #f!

;; RIGHT
(define stdin (child-stdin child))
```

### JSON to pipes

Use `#%raw-write-string` + `\n` + `flush`, not `write-line!`

### helix.scm must re-export

```scheme
;; pi.scm END
(provide pi-start pi-send ...)

;; helix.scm
(require (only-in "cogs/pi/pi.scm" pi-start pi-send ...))
(provide ... pi-start pi-send ...)
```

## RPC

Reference: `~/git/pi-mono/packages/coding-agent/docs/rpc.md`

Spawns `pi --mode rpc`, JSON lines over stdio.
