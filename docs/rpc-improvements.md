# RPC Improvements Plan

Based on review of `~/git/pi-mono` reference implementation.

## Problem

Currently helix-pi ignores RPC response events:

```scheme
[(equal? type "response") #t]  ; silently ignored!
```

This means:
- **Errors are silent** - no API key, invalid model, rate limits
- **No confirmation** - don't know if abort succeeded
- **No state tracking** - can't tell if we're streaming

## Changes Required

### 1. Handle Response Events

**In `pi-core.scm`, update `pi-handle-event`:**

```scheme
[(equal? type "response")
 (handle-response event)
 #t]
```

**Add `handle-response` function:**

```scheme
(define (handle-response event)
  (let ([success (hash-try-get event 'success)]
        [command (hash-try-get event 'command)]
        [error-msg (hash-try-get event 'error)])
    (cond
      ;; Error response - show to user
      [(not success)
       (append-output! (string-append "\n**Error**: " (or error-msg "Unknown error") "\n\n"))
       (set-status! (string-append "pi: error - " (or error-msg "unknown")))]
      ;; Success responses we care about
      [(equal? command "abort")
       (set-status! "pi: aborted")]
      ;; Other success responses - ignore
      [else #f])))
```

### 2. Track Streaming State

**Add state variable in `pi-core.scm`:**

```scheme
(define *pi-is-streaming* #f)
```

**Update event handlers:**

```scheme
;; In agent_start handler
[(equal? type "agent_start")
 (set! *pi-is-streaming* #t)
 (set-status! "pi: streaming...")
 #t]

;; In agent_end handler  
[(equal? type "agent_end")
 (set! *pi-is-streaming* #f)
 (append-output! "\n\n")
 (set-status! "pi: idle")
 #t]
```

**Export predicate:**

```scheme
(provide pi-is-streaming?)

(define (pi-is-streaming?)
  *pi-is-streaming*)
```

### 3. Handle Streaming Conflicts in `pi.scm`

**Update `pi-send`:**

```scheme
(define (pi-send)
  (cond
    [(not (pi-running?))
     (set-status! "pi: not running (use :pi-start)")]
    [(pi-is-streaming?)
     ;; Queue as follow-up instead of error
     (let ([text (trim (pi-get-input))])
       (if (equal? text "")
           (set-status! "pi: empty prompt")
           (begin
             (pi-rpc-send (pi-make-follow-up-request text))
             (pi-clear-input)
             (set-status! "pi: queued follow-up"))))]
    [else
     (let ([text (trim (pi-get-input))])
       (if (equal? text "")
           (set-status! "pi: empty prompt")
           (begin
             (pi-rpc-send (pi-make-prompt-request text))
             (pi-clear-input)
             (set-status! "pi: sending..."))))]))
```

### 4. Add Missing RPC Commands

**In `pi-core.scm`:**

```scheme
(define (pi-make-follow-up-request message)
  "Create a follow_up RPC request (queued until agent idle)."
  (hash "type" "follow_up"
        "message" message
        "id" (next-request-id)))

(define (pi-make-steer-request message)
  "Create a steer RPC request (interrupts current operation)."
  (hash "type" "steer"
        "message" message
        "id" (next-request-id)))

(define (pi-make-get-state-request)
  "Create a get_state RPC request."
  (hash "type" "get_state"
        "id" (next-request-id)))
```

### 5. Request/Response Correlation (Optional)

For more robust error handling, track pending requests:

```scheme
;; Track pending request IDs
(define *pending-requests* (hash))

(define (register-pending-request id command)
  (set! *pending-requests* 
        (hash-insert *pending-requests* id command)))

(define (resolve-pending-request id)
  (let ([command (hash-try-get *pending-requests* id)])
    (set! *pending-requests*
          (hash-insert *pending-requests* id #f))  ; no hash-remove in Steel
    command))
```

This allows matching errors to specific commands.

## Implementation Order

1. **Phase 1: Error visibility** (critical) ✅ DONE
   - Handle response events
   - Show errors to user
   - ~20 lines changed

2. **Phase 2: State tracking** (important) ✅ DONE
   - Track streaming state
   - Prevent conflicts
   - ~15 lines changed

3. **Phase 3: Queue support** (nice-to-have) ✅ DONE
   - Add follow_up/steer commands
   - Smart send behavior
   - ~30 lines changed

4. **Phase 4: Full correlation** (optional) ✅ DONE
   - Track pending requests
   - Match responses to commands
   - ~25 lines changed

## Testing

After each phase, test:

```bash
# Phase 1: Error handling
pi --mode rpc --no-session
{"type":"prompt","message":"test","id":"1"}
# Should see response with success:true

# Simulate error (no API key)
ANTHROPIC_API_KEY= pi --mode rpc --no-session
{"type":"prompt","message":"test","id":"1"}
# Should see response with success:false, error message

# Phase 2: State tracking
# Send prompt, immediately send another
# Should queue or show "streaming" status

# Phase 3: Queue support  
# Send prompt, then follow_up while streaming
# Should queue and execute after first completes
```

## Bug Fixes

### 1. State Reset on Session Start/Quit/Process End

**Problem**: Streaming state (`*pi-is-streaming*`) was not reset when:
1. Starting a new session (carried over from previous session)
2. User calls `:pi-quit`
3. Pi process terminates unexpectedly

**Fix**: Added `pi-reset-state!` function and call it:
- In `pi-spawn-process` before starting new session
- In `pi-quit` before setting status
- In event loop when EOF detected (process ended)

### 2. Missing `error` Event Handler

**Problem**: When the agent stream failed (API timeout, rate limit, etc.), pi sent an `error` event that we ignored, leaving the UI stuck at "pi: streaming...".

**Fix**: Added handlers for error-related events:
- `error` - Stream error (aborted, timeout, etc.)
- `extension_error` - Extension threw an error  
- `auto_retry_start` - Transient error, retrying
- `auto_retry_end` - Retry completed (success or final failure)

### 3. Missing stderr Capture

**Problem**: If pi crashed or logged errors to stderr, we never saw them.

**Fix**: Added `with-stderr-piped` and `pi-stderr-loop` to capture and display stderr output.

## Files Changed

| File | Changes |
|------|---------|
| `src/pi-core.scm` | Add response handling, state tracking, new RPC constructors, `pi-reset-state!` |
| `src/pi.scm` | Update pi-send for streaming awareness, reset state on quit/EOF |
| `tests/pi-core-test.scm` | Add tests for response handling and state reset |
