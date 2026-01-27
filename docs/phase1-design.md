# Phase 1: Two-Buffer RPC Integration

Minimal viable integration: input buffer → pi RPC → output buffer.

## RPC Protocol Summary

**Start**: `pi --mode rpc --no-session`

**Communication**: JSON lines over stdin/stdout

### Send Prompt (stdin → pi)

```json
{"type": "prompt", "message": "Hello, explain this code", "id": "req_1"}
```

### Receive Response (pi → stdout)

First, immediate acknowledgment:
```json
{"type": "response", "command": "prompt", "success": true, "id": "req_1"}
```

Then streaming events:
```json
{"type": "agent_start"}
{"type": "turn_start"}
{"type": "message_start", "message": {"role": "user", "content": [{"type": "text", "text": "Hello..."}], "timestamp": 1234567890}}
{"type": "message_end", "message": {"role": "user", ...}}
{"type": "message_start", "message": {"role": "assistant", "content": [], ...}}
{"type": "message_update", "message": {...}, "assistantMessageEvent": {"type": "text_delta", "delta": "Hi"}}
{"type": "message_update", "message": {...}, "assistantMessageEvent": {"type": "text_delta", "delta": " there"}}
{"type": "message_update", "message": {...}, "assistantMessageEvent": {"type": "text_delta", "delta": "!"}}
{"type": "message_end", "message": {"role": "assistant", "content": [{"type": "text", "text": "Hi there!"}], ...}}
{"type": "turn_end", "message": {...}, "toolResults": []}
{"type": "agent_end", "messages": [...]}
```

### Key Event Types

| Event | When | Data |
|-------|------|------|
| `agent_start` | Prompt begins processing | - |
| `agent_end` | Prompt complete | `messages`: all new messages |
| `message_start` | Message begins (user/assistant/toolResult) | `message` |
| `message_update` | Assistant streaming | `assistantMessageEvent.delta` |
| `message_end` | Message complete | `message` with full content |
| `tool_execution_start` | Tool begins | `toolCallId`, `toolName`, `args` |
| `tool_execution_update` | Tool progress | `partialResult` |
| `tool_execution_end` | Tool complete | `result`, `isError` |

### Other Useful Commands

```json
{"type": "get_state", "id": "req_2"}
{"type": "abort", "id": "req_3"}
```

## Phase 1 Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Helix                                 │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                 Output Buffer                          │  │
│  │  (read-only, shows conversation as markdown)           │  │
│  │                                                        │  │
│  │  ## You                                                │  │
│  │  Hello, explain this code                              │  │
│  │                                                        │  │
│  │  ## Assistant                                          │  │
│  │  Hi there! [streaming...]                              │  │
│  │                                                        │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                 Input Buffer                           │  │
│  │  (editable, plain text, multi-line)                    │  │
│  │                                                        │  │
│  │  > type your prompt here                               │  │
│  │                                                        │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
        │                                    ▲
        │ {"type":"prompt","message":"..."}  │ events (JSON lines)
        ▼                                    │
    ┌───────────────────────────────────────────┐
    │           pi --mode rpc --no-session      │
    └───────────────────────────────────────────┘
```

## Steel Module Structure

### `pi.scm` - Main entry point

```scheme
;; Provides commands:
;; - pi-start      : Start session (spawn process, create buffers)
;; - pi-send       : Send input buffer contents to pi
;; - pi-abort      : Abort current operation
;; - pi-quit       : Close session

(provide pi-start pi-send pi-abort pi-quit)

;; Load submodules
(require "pi/rpc.scm")
(require "pi/buffers.scm")
(require "pi/events.scm")
```

### `pi/rpc.scm` - Process and JSON communication

**State**:
```scheme
(define *pi-process* #f)      ; Child process handle
(define *pi-stdin* #f)        ; Write port
(define *pi-stdout* #f)       ; Read port
(define *pi-request-id* 0)    ; Counter for request IDs
```

**Functions**:
```scheme
;; Start pi process
(define (pi-rpc-start)
  (define child
    (unwrap-ok
      (spawn-process
        (with-stdout-piped
          (with-stdin-piped
            (command "pi" '("--mode" "rpc" "--no-session")))))))
  (set! *pi-process* child)
  (set! *pi-stdin* (child-stdin child))
  (set! *pi-stdout* (child-stdout child))
  (pi-start-event-loop))

;; Send JSON command
(define (pi-rpc-send command)
  (define id (begin
               (set! *pi-request-id* (+ *pi-request-id* 1))
               (string-append "req_" (number->string *pi-request-id*))))
  (define json (hash-insert command "id" id))
  (write-line! *pi-stdin* (value->jsexpr-string json))
  id)

;; Send prompt
(define (pi-rpc-prompt message)
  (pi-rpc-send (hash "type" "prompt" "message" message)))

;; Send abort
(define (pi-rpc-abort)
  (pi-rpc-send (hash "type" "abort")))
```

### `pi/buffers.scm` - Buffer management

**Labels**:
```scheme
(define PI-OUTPUT "helix-pi/output")
(define PI-INPUT "helix-pi/input")
```

**Functions**:
```scheme
;; Create split layout with output (top) and input (bottom)
(define (pi-create-buffers)
  ;; Create output buffer (read-only)
  (make-new-labelled-buffer! #:label PI-OUTPUT #:side 'top)
  
  ;; Create input buffer (editable)
  (make-new-labelled-buffer! #:label PI-INPUT #:side 'bottom)
  
  ;; Set focus to input
  (open-labelled-buffer PI-INPUT))

;; Get contents of input buffer
(define (pi-get-input)
  (temporarily-switch-focus
    (lambda ()
      (open-labelled-buffer PI-INPUT)
      (helix.static.select_all)
      (helix.static.current-highlighted-text!))))

;; Clear input buffer
(define (pi-clear-input)
  (temporarily-switch-focus
    (lambda ()
      (open-labelled-buffer PI-INPUT)
      (helix.static.select_all)
      (helix.static.delete_selection))))

;; Append text to output buffer
(define (pi-append-output text)
  (temporarily-switch-focus
    (lambda ()
      (open-labelled-buffer PI-OUTPUT)
      (helix.static.goto_file_end)
      (helix.static.insert_string text))))
```

### `pi/events.scm` - Event loop and rendering

**State**:
```scheme
(define *pi-is-streaming* #f)
(define *pi-current-role* #f)   ; "user" | "assistant" | #f
```

**Event loop** (runs in background thread):
```scheme
(define (pi-start-event-loop)
  (spawn-native-thread
    (lambda ()
      (let loop ()
        (define line (read-line-from-port *pi-stdout*))
        (when line
          (define event (string->jsexpr line))
          (hx.block-on-task
            (lambda ()
              (pi-handle-event event)))
          (loop))))))
```

**Event handlers**:
```scheme
(define (pi-handle-event event)
  (define type (hash-ref event "type"))
  
  (cond
    ;; Agent lifecycle
    [(equal? type "agent_start")
     (set! *pi-is-streaming* #t)
     (set-status! "pi: streaming...")]
    
    [(equal? type "agent_end")
     (set! *pi-is-streaming* #f)
     (set! *pi-current-role* #f)
     (set-status! "pi: idle")]
    
    ;; Message lifecycle
    [(equal? type "message_start")
     (define msg (hash-ref event "message"))
     (define role (hash-ref msg "role"))
     (set! *pi-current-role* role)
     (pi-render-message-header role)]
    
    [(equal? type "message_update")
     (define evt (hash-ref event "assistantMessageEvent"))
     (define evt-type (hash-ref evt "type"))
     (when (equal? evt-type "text_delta")
       (define delta (hash-ref evt "delta"))
       (pi-append-output delta))]
    
    [(equal? type "message_end")
     (pi-append-output "\n\n")]
    
    ;; Tool lifecycle (phase 2)
    [(equal? type "tool_execution_start")
     (pi-render-tool-start event)]
    
    [(equal? type "tool_execution_end")
     (pi-render-tool-end event)]
    
    [else (void)]))
```

**Rendering helpers**:
```scheme
;; Render message header
(define (pi-render-message-header role)
  (cond
    [(equal? role "user")
     (pi-append-output "## You\n\n")]
    [(equal? role "assistant")
     (pi-append-output "## Assistant\n\n")]
    [(equal? role "toolResult")
     (void)]  ; Tool results rendered by tool_execution_end
    [else (void)]))

;; Render tool start (simple for phase 1)
(define (pi-render-tool-start event)
  (define tool-name (hash-ref event "toolName"))
  (pi-append-output (string-append "\n**" tool-name "**\n```\n")))

;; Render tool end
(define (pi-render-tool-end event)
  (define result (hash-ref event "result"))
  (define is-error (hash-ref event "isError"))
  ;; Simple: just close the code block
  (pi-append-output "```\n\n"))
```

## Commands

### `:pi-start`

1. Spawn `pi --mode rpc --no-session`
2. Create output buffer (top, read-only)
3. Create input buffer (bottom, editable)
4. Start event loop thread
5. Focus input buffer

### `:pi-send`

1. Get input buffer contents
2. If empty, do nothing
3. Send `{"type": "prompt", "message": "..."}`
4. Clear input buffer

### `:pi-abort`

1. Send `{"type": "abort"}`

### `:pi-quit`

1. Kill pi process
2. Close buffers

## Keybindings (init.scm)

```scheme
;; Input buffer keybindings
(define pi-input-keybindings
  (hash "normal"
        (hash "C-c" (hash "C-c" ':pi-send
                          "C-k" ':pi-abort
                          "C-q" ':pi-quit))))

;; Apply to input buffer only
(set-global-buffer-or-extension-keymap
  (hash PI-INPUT pi-input-keybindings))
```

## Output Format (Markdown)

The output buffer will contain markdown that looks like:

```markdown
## You

What does this function do?

## Assistant

This function calculates the factorial of a number. Let me explain:

**Read**
```
function factorial(n) {
  if (n <= 1) return 1;
  return n * factorial(n - 1);
}
```

The function uses recursion to multiply n by factorial(n-1) until it reaches the base case.

## You

Can you add error handling?

## Assistant

Sure! Here's the improved version:

**Edit**
```diff
- function factorial(n) {
+ function factorial(n) {
+   if (typeof n !== 'number' || n < 0) {
+     throw new Error('Input must be a non-negative number');
+   }
    if (n <= 1) return 1;
    return n * factorial(n - 1);
  }
```

I've added validation to check for invalid inputs.
```

## Dependencies

### Steel builtins needed:
- `steel/process` - spawn-process, child-stdin, child-stdout
- `steel/result` - unwrap-ok
- JSON encode/decode (need to verify Steel has this)

### Helix APIs needed:
- Labelled buffer pattern (from helix-config)
- `helix.static.*` for text manipulation
- `set-status!` for status messages
- `spawn-native-thread` for background event loop
- `hx.block-on-task` for UI updates from thread

## Steel JSON Functions

Verified in Steel REPL:

```scheme
;; Encode: Steel value → JSON string
(value->jsexpr-string (hash "type" "test" "id" 123))
;; => "{\"id\":123,\"type\":\"test\"}"

;; Decode: JSON string → Steel hash
(string->jsexpr "{\"type\": \"test\"}")
;; => '#hash((type . "test"))
```

## Open Questions

1. ~~**JSON in Steel**~~: ✓ `value->jsexpr-string` and `string->jsexpr` work

2. **Read-only buffer**: Can we make output buffer truly read-only, or just use mode keybindings?

3. **Horizontal split**: How to create horizontal split (output top, input bottom) vs vertical?

4. **Auto-scroll**: How to make output buffer follow new text during streaming?

5. **Process cleanup**: How to handle pi process dying unexpectedly?

## Next Steps After Phase 1

- Phase 2: Tool output rendering (collapsible, syntax highlighted)
- Phase 3: Input history
- Phase 4: @ file completion, / commands
- Phase 5: Model switching, status display
- Phase 6: Session management (resume, fork, export)
