# How to Debug and Test helix-pi

## Architecture: Testable Core + Thin Helix Layer

```
┌─────────────────────────────────────────────────────────────────┐
│  pi-core.scm     Pure Steel logic, NO helix dependencies        │
│                  → Testable with steel test                     │
│                  → Interactive REPL with steel interactive      │
├─────────────────────────────────────────────────────────────────┤
│  pi.scm          Thin Helix integration layer                   │
│                  → Only buffer/window/process management        │
│                  → Cannot be tested outside Helix               │
└─────────────────────────────────────────────────────────────────┘
```

**Rule**: Put all logic in `pi-core.scm`. The helix layer should only wire callbacks.

## Primary: Automated Tests

Run the test suite:

```bash
cd ~/git/helix-pi && steel test tests/
```

Output:
```
###### Running tests for module  pi-handle-event  ######
test > agent_start sets streaming status ... Ok
...
Test result:  55  passed;  0  failed;
```

## Secondary: Interactive REPL

Test pure Steel functions:

```bash
cd ~/git/helix-pi && steel interactive src/pi-core.scm
```

```scheme
λ > (pi-make-prompt-request session "hello")
=> #hash(("id" . "req_1") ("message" . "hello") ("type" . "prompt"))
```

**Note**: `steel interactive src/pi.scm` fails - helix modules aren't available outside Helix.

## Tertiary: Helix Debug Window

For Helix-specific issues:

```
:open-debug-window
```

Add `displayln` statements to see output in the debug window.

## Debugging Helix Startup Errors

Steel compilation errors scroll by too fast to read. Use tmux to capture them:

```bash
# Create isolated tmux session
SESSION="$(date +%s%N | sha256sum | head -c 6)"
SOCKET="/tmp/tmux-$SESSION.sock"
TMUX= tmux -S "$SOCKET" new -d -s "$SESSION"

# Start helix
tmux -S "$SOCKET" send-keys -t "$SESSION":0.0 -- 'hx .' Enter
sleep 3

# Capture output (including any Steel errors)
tmux -S "$SOCKET" capture-pane -p -J -t "$SESSION":0.0 -S -50

# Clean up
tmux -S "$SOCKET" kill-session -t "$SESSION"
rm -f "$SOCKET"
```

Common errors you'll see:

| Error | Cause | Fix |
|-------|-------|-----|
| `FreeIdentifier: Cannot reference identifier before definition` | `provide` before `define` | Move `provide` to END of file |
| `no such command: 'pi-start'` | helix.scm not re-exporting | Add to helix.scm's `provide` |
| `BadSyntax: module not found` | Wrong require path | Check relative path from file location |

## Callback Testing Pattern

pi-core.scm uses callbacks injected via `make-pi-session`:

```scheme
;; In tests
(define *captured-output* "")
(define *captured-status* "")

(define test-session
  (make-pi-session
    #:append-output (lambda (text) 
                      (set! *captured-output* (string-append *captured-output* text)))
    #:set-status (lambda (msg) 
                   (set! *captured-status* msg))))

;; Test event handling
(pi-handle-event test-session (hash 'type "agent_start"))
(check-equal? "status set" *captured-status* "pi: streaming...")
```

## Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| `steel interactive pi.scm` fails | Helix modules not available | Test pi-core.scm instead |
| Test file not found by `steel test` | Missing `__module__` | Add `(provide __module__)` |
| JSON keys not found | Using string keys | Use symbols: `'type` not `"type"` |
| `define` in `when` fails | Invalid Steel syntax | Use `let` binding instead |
| `provide` fails in helix | `provide` before definitions | Move `provide` to END of file |

## Workflow

1. **Write logic** in `pi-core.scm` with no helix imports
2. **Write tests** in `tests/pi-core-test.scm`
3. **Run** `steel test tests/` - iterate until green
4. **Deploy** `cp src/*.scm ~/.config/helix/cogs/pi/`
5. **Test in Helix** - use tmux capture if startup fails
