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
test > agent_end sets idle status ... Ok
...
Test result:  33  passed;  0  failed;
```

### Writing Tests

Tests use Steel's unit-test module:

```scheme
;; tests/pi-core-test.scm
(require "steel/tests/unit-test.scm"
         (for-syntax "steel/tests/unit-test.scm"))
(require "../src/pi-core.scm")

(provide __module__)
(define __module__ "pi-core-test")

(test-module "my-tests"
  (check-equal? "description"
    (actual-expression)
    expected-value))
```

**Required**: `(provide __module__)` and `(define __module__ ...)` for `steel test` to find tests.

## Secondary: Interactive REPL

Test pure Steel functions interactively:

```bash
cd ~/git/helix-pi && steel interactive src/pi-core.scm
```

```scheme
λ > (pi-make-prompt-request "hello")
=> #hash(("id" . "req_1") ("message" . "hello") ("type" . "prompt"))

λ > (path-to-session-dir-name "/home/jack/git/helix-pi")
=> "--home-jack-git-helix-pi--"

λ > (get-text-parts (list (hash 'type "text" 'text "hello")))
=> ("hello")
```

**Note**: `steel interactive src/pi.scm` fails - helix modules aren't available outside Helix.

## Tertiary: Helix Debug Window

For Helix-specific issues only:

```
:open-debug-window
```

Add `displayln` statements to see output:

```scheme
(define (helix-append-output text)
  (displayln (string-append "APPEND: " text))  ; Debug
  ...)
```

## Debug Compilation

```bash
# See bytecode
steel bytecode src/pi-core.scm | head -50

# See expanded AST  
steel ast src/pi-core.scm | head -50
```

## Callback Testing Pattern

pi-core.scm uses callbacks for helix operations. Tests inject mocks:

```scheme
;; In tests
(define *captured-output* "")

(define (mock-append-output text)
  (set! *captured-output* (string-append *captured-output* text)))

(pi-set-callbacks! 
  #:append-output mock-append-output
  #:set-status (lambda (msg) #f))

;; Now test event handling
(pi-handle-event (hash 'type "agent_start"))
(check-equal? "status set" *captured-status* "pi: streaming...")
```

## Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| `steel interactive pi.scm` fails | Helix modules not available | Test pi-core.scm instead |
| Test file not found by `steel test` | Missing `__module__` | Add `(provide __module__)` |
| JSON keys not found | Using string keys | Use symbols: `'type` not `"type"` |
| `define` in `when` | Invalid Steel syntax | Use `let` binding instead |

## Workflow Summary

1. **Write logic** in `pi-core.scm` with no helix imports
2. **Write tests** in `tests/pi-core-test.scm`
3. **Run** `steel test tests/` - iterate until green
4. **Wire up** callbacks in `pi.scm`
5. **Manual test** in Helix only for integration issues
