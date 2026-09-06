# Refactor: Session State Encapsulation

**Historical refactor record — examples and completion claims are superseded.** Current source has mutable pi-session callbacks and separate *pi-process*, *pi-ui* and *pi-session* globals, not the immutable-return/single-atom design below. The old test count, no-state-leakage and thread-safety claims are not current verification. Preserve this record as rationale; use [operating limits](commands.md#operating-limits) and source before implementation.

## Problem

Original code used 14+ global mutable variables:
- State leaks between sessions
- Race conditions between event loop thread and main thread
- Hard to test and reason about
- Bugs like "stuck streaming" from stale state

## Solution

Encapsulated all session state in two structs:

### pi-core.scm - Pure functions

```scheme
;; Session state structure
(struct pi-session
  (streaming?        ; #t if currently streaming
   pending-requests  ; hash of id -> command
   request-counter   ; for generating unique IDs
   tool-output-lens  ; hash of tool-call-id -> output length
   ) #:transparent)

(define (make-pi-session)
  (pi-session #f (hash) 0 (hash)))

;; Event handler returns NEW session state (immutable update)
(define (pi-handle-event session event callbacks)
  "Handle event, return updated session state."
  (let ([type (hash-try-get event 'type)])
    (cond
      [(equal? type "agent_start")
       (callbacks-set-status callbacks "pi: streaming...")
       (set-pi-session-streaming? session #t)]
      
      [(equal? type "agent_end")
       (callbacks-append-output callbacks "\n\n")
       (callbacks-set-status callbacks "pi: idle")
       (set-pi-session-streaming? session #f)]
      
      ;; ... etc
      [else session])))

;; RPC construction - returns (values request new-session)
(define (pi-make-prompt-request session message)
  (let* ([counter (pi-session-request-counter session)]
         [id (string-append "req_" (number->string (+ counter 1)))]
         [new-pending (hash-insert (pi-session-pending-requests session) id "prompt")]
         [new-session (struct-copy pi-session session
                        [request-counter (+ counter 1)]
                        [pending-requests new-pending])])
    (values (hash "type" "prompt" "message" message "id" id)
            new-session)))
```

### pi.scm - Helix integration with single state atom

```scheme
;; Single mutable cell holding all state
(define *pi-state* #f)  ; #f or pi-state struct

(struct pi-state
  (session     ; pi-session from pi-core
   process     ; child process handle
   stdin       ; input port
   stdout      ; output port  
   stderr      ; error port
   output-doc  ; helix doc id
   input-doc   ; helix doc id
   ) #:transparent)

(define (pi-running?)
  (and *pi-state* (pi-state-process *pi-state*)))

(define (pi-start)
  (when (pi-running?)
    (error "pi: already running"))
  (set! *pi-state* (make-fresh-pi-state)))

(define (pi-send)
  (when (not (pi-running?))
    (error "pi: not running"))
  (let-values ([(request new-session) 
                (pi-make-prompt-request (pi-state-session *pi-state*) text)])
    ;; Atomically update state
    (set! *pi-state* 
          (struct-copy pi-state *pi-state*
            [session new-session]))
    (send-to-process request)))
```

## Benefits

1. **No state leakage** - Fresh session = fresh state
2. **Testable** - Pass session struct to pure functions
3. **Thread-safe** - Single atomic update point
4. **Debuggable** - Can inspect entire state at once
5. **Explicit** - State flow is visible in code

## Migration Path

1. Create `pi-session` struct in pi-core.scm
2. Update `pi-handle-event` to take and return session
3. Create `pi-state` struct in pi.scm  
4. Update commands to use single `*pi-state*` atom
5. Remove individual globals one by one
6. Update tests to use struct-based API

## Implementation

### pi-core.scm - `pi-session` struct

```scheme
(struct pi-session
  (streaming?        ; #t if currently streaming
   pending-requests  ; hash of id -> command  
   request-counter   ; for generating unique IDs
   tool-output-lens  ; hash of tool-call-id -> output length seen
   cb-append-output  ; callback: (lambda (text) ...)
   cb-set-status     ; callback: (lambda (msg) ...)
   cb-on-unknown     ; callback: (lambda (type) ...)
   ) #:mutable)
```

### pi.scm - `pi-state` struct

```scheme
(struct pi-state
  (session      ; pi-session from pi-core
   process      ; child process handle
   stdin        ; input port to process
   stdout       ; output port from process
   stderr       ; error port from process
   output-doc   ; helix document id for output buffer
   input-doc    ; helix document id for input buffer
   ) #:mutable)

;; Single global
(define *pi* #f)
```

## Benefits Achieved

1. **No state leakage** - Fresh `pi-spawn-process` creates fresh session
2. **Testable** - Tests create isolated sessions with mock callbacks
3. **Single update point** - Only `*pi*` is modified
4. **Explicit state flow** - Session passed to all functions
5. **55 tests passing**
