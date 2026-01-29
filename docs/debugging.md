# How to Debug and Test helix-pi

## Run the Test Suite

```bash
steel test tests/
```

Expected output:
```
###### Running tests for module  pi-handle-event  ######
test > agent_start sets streaming status ... Ok
...
Test result:  68  passed;  0  failed;
```

## Test with the CLI Client

`pi-stdio.scm` is a standalone client that uses the same pi-core.scm logic as Helix. Use it to isolate issues:

```bash
steel src/pi-stdio.scm              # new session
steel src/pi-stdio.scm --continue   # resume previous
```

```
pi-stdio - type :help for commands

--- ready ---
> :help

Commands:
  :help, :h, :?       Show this help
  :quit, :q           Exit
  :abort              Abort current operation
  :follow <text>      Queue follow-up message
  :steer <text>       Interrupt with steering message
  :model              Cycle to next model
  :thinking           Cycle thinking level
  :compact            Compact conversation context
  :new                Start fresh session
  :status             Show current state
  :sessions           List available sessions
  :resume <path>      Switch to specific session
  <text>              Send as prompt
```

If something breaks in Helix, reproduce it here first to determine if it's a pi-core.scm issue or Helix integration issue.

## Test Functions Interactively

Use the Steel REPL for pi-core.scm (pure logic, no Helix deps):

```bash
steel interactive src/pi-core.scm
```

```scheme
λ > (define s (make-pi-session #:append-output (lambda (t) #f) #:set-status (lambda (m) #f)))
λ > (pi-make-prompt-request s "hello")
=> #hash(("id" . "req_1") ("message" . "hello") ("type" . "prompt"))
```

Note: `steel interactive src/pi.scm` fails because Helix modules aren't available outside Helix.

## Debug in Helix

For Helix-specific issues, use the debug window:

```
:open-debug-window
```

Add `displayln` statements to see output there.

## Capture Startup Errors

Steel compilation errors scroll by too fast. Use tmux:

```bash
SESSION="$(date +%s%N | sha256sum | head -c 6)"
SOCKET="/tmp/tmux-$SESSION.sock"
TMUX= tmux -S "$SOCKET" new -d -s "$SESSION"
tmux -S "$SOCKET" send-keys -t "$SESSION":0.0 -- 'hx .' Enter
sleep 3
tmux -S "$SOCKET" capture-pane -p -J -t "$SESSION":0.0 -S -50
tmux -S "$SOCKET" kill-session -t "$SESSION"
```

## Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `FreeIdentifier: Cannot reference identifier before definition` | `provide` before `define` | Move `provide` to END of file |
| `no such command: 'pi-start'` | helix.scm not re-exporting | Add to helix.scm's `provide` |
| `BadSyntax: module not found` | Wrong require path | Check relative path |
| `steel interactive pi.scm` fails | Helix modules unavailable | Test pi-core.scm instead |
| JSON keys not found | Using string keys | Use symbols: `'type` not `"type"` |

## Development Workflow

1. Write logic in `pi-core.scm` (no helix imports)
2. Write tests in `tests/pi-core-test.scm`
3. Run `steel test tests/` until green
4. Test with `steel src/pi-stdio.scm` (no Helix needed)
5. Deploy: `cp src/*.scm ~/.config/helix/cogs/pi/`
6. Test in Helix; use tmux capture if startup fails
