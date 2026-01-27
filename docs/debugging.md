# How to Debug Steel Plugins for Helix

This guide shows how to debug Steel plugins using official tools from Steel and Helix.

## Prerequisites

- Helix built with Steel: `cargo xtask steel`
- Steel CLI available: `steel --version`
- Plugin loaded in `~/.config/helix/helix.scm`

## The Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│  1. PURE SCHEME        →  steel interactive plugin.scm          │
│  2. HELIX CONTEXT      →  :open-debug-window + :eval-buffer     │
│  3. EXPRESSION TEST    →  :evalp (expr)                         │
│  4. AUTOMATED TESTS    →  steel test tests.scm                  │
└─────────────────────────────────────────────────────────────────┘
```

## Step 1: Test Pure Scheme Logic

Use `steel interactive` to load your plugin and test functions:

```bash
steel interactive ~/.config/helix/cogs/pi/pi.scm
```

```scheme
λ > (value->jsexpr-string (hash "type" "prompt"))
=> "{\"type\":\"prompt\"}"

λ > (hash-try-get (hash 'a 1) 'a)
=> 1
```

**Limitation**: Helix APIs (`helix.static.*`, `editor-focus`) don't work here.

## Step 2: Use the Debug Window

Open the debug window to see `displayln` output:

```
:open-debug-window
```

Add tracing to your code:

```scheme
(define (my-handler event)
  (displayln (string-append "EVENT: " (to-string event)))
  ;; ... rest of handler
)
```

Run your command:

```
:pi-start
```

Debug window shows all `displayln` output.

## Step 3: Hot Reload with eval-buffer

Edit your plugin, then reload without restarting Helix:

```
:open ~/.config/helix/cogs/pi/pi.scm
;; Make edits
:eval-buffer
```

**Setup required**: Add to `~/.config/helix/helix.scm`:

```scheme
(require (only-in "helix/ext.scm" eval-buffer))
;; In (provide ...):
eval-buffer
```

## Step 4: Test Expressions with evalp

Quick test any expression:

```
:evalp → (+ 100 200 300) → 600
:evalp → (editor-mode) → "normal"
:evalp → (maybe-fetch-doc-id "pi/output") → #f
```

## Step 5: Write Unit Tests

Create test file:

```scheme
;; tests/pi-tests.scm
(require "steel/tests/unit-test.scm")

(check-equal? "JSON encoding"
              (value->jsexpr-string (hash "type" "test"))
              "{\"type\":\"test\"}")

(check-equal? "hash-try-get found"
              (hash-try-get (hash 'a 1) 'a)
              1)

(displayln (get-test-stats))
```

Run:

```bash
steel tests/pi-tests.scm
```

Output:

```
test > JSON encoding ... Ok
test > hash-try-get found ... Ok
#hash((success-count . 2) (failure-count . 0) ...)
```

## Variations

### Debug Compilation Issues

```bash
# See bytecode
steel bytecode plugin.scm

# See expanded AST
steel ast plugin.scm
```

### Verbose Helix Logging

```bash
~/git/helix/target/release/hx -v --log /tmp/helix-debug.log
```

### Create a State Inspector Command

```scheme
(provide debug-state)

;;@doc
;; Show plugin state
(define (debug-state)
  (displayln "=== State ===")
  (displayln (string-append "running: " (if *pi-process* "yes" "no")))
  (displayln (string-append "streaming: " (if *pi-is-streaming* "yes" "no"))))
```

Use with `:debug-state`.

## Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| JSON has extra quotes | `write-line!` escapes | Use `#%raw-write-string` |
| Process hangs | No flush | Add `flush-output-port` |
| Key not found in hash | Using string key | Use symbol: `'type` not `"type"` |
| `(void)` syntax error | Invalid in cond | Use `#f` instead |
| `symbol->string` fails | Value is string | Use `to-string` |
| `:eval-buffer` not found | Not exported | Add to helix.scm |
| BadSyntax on `define` | `define` inside `when` | Use `let` binding instead |

### The `define` in `when` Trap

Steel doesn't allow `define` inside `when` (or other non-lexical contexts):

```scheme
;; WRONG - causes BadSyntax error
(when condition
  (define x (compute-something))
  (use x))

;; RIGHT - use let binding
(when condition
  (let ([x (compute-something)])
    (use x)))
```

This error is silent in Helix - the code just doesn't run. Use `steel` CLI to check syntax.

## tmux as Last Resort

Prefer the tools above first. If you need to test interactive behavior that can't be isolated:

```bash
# Start helix in tmux
tmux new-session -d -s hx-test
tmux send-keys -t hx-test '~/git/helix/target/release/hx' Enter
sleep 1

# Run a command
tmux send-keys -t hx-test ':pi-resume' Enter
sleep 1

# Capture output
tmux capture-pane -t hx-test -p

# Cleanup
tmux kill-session -t hx-test
```

**Why prefer other tools first:**
- Race conditions with timing
- Can't easily inspect intermediate state
- Harder to iterate quickly

Use `steel interactive`, `:evalp`, and `:open-debug-window` to isolate issues before resorting to tmux.
