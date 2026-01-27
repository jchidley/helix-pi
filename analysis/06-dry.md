# Phase 6: DRY Scan

## Violations

### 1. Spawn Process Duplication (HIGH)

**Locations**: `pi-spawn-process` (L418-436), `pi-spawn-process-with-history` (L438-462)

**Pattern** (duplicated ~20 lines):
```scheme
(let ([result (spawn-process (with-stdout-piped (with-stdin-piped (command "pi" args))))])
  (if (Ok? result)
      (let ([child (unwrap-ok result)])
        (set! *pi-process* child)
        (set! *pi-stdin* (child-stdin child))
        (set! *pi-stdout* (child-stdout child))
        (pi-create-buffers)
        (pi-event-loop)
        ;; <only difference: welcome-msg vs display-session-history>
        (set-status! "pi: started/ready"))
      (set-status! "pi: failed to start process")))
```

**Fix**: Single `pi-spawn-process` with optional `session-file` parameter. If provided, call `display-session-history`; otherwise append welcome-msg (or nothing).

### 2. Session File Iteration (MEDIUM)

**Locations**: `get-first-user-message` (L252-278), `display-session-history` (L290-321)

**Pattern**:
```scheme
(call-with-input-file session-file
  (lambda (port)
    (let loop ()
      (let ([line (read-line-from-port port)])
        (if/when (string? line)
          (let ([event (string->jsexpr line)])
            (let ([type (hash-try-get event 'type)]
                  [msg (hash-try-get event 'message)])
              (when (and (equal? type "message") msg)
                ;; <process message>
                ))))))))
```

**Fix**: Extract `for-each-session-message` that takes a callback. Or use a single pass that builds data structure.

### 3. Text Content Extraction (LOW)

**Locations**: 
- `get-text-parts` helper (good)
- `get-first-user-message` inline extraction (L268-275)
- `pi-handle-event` message_end handler (L163-171)

**Fix**: Reuse `get-text-parts` in all locations.

### 4. temporarily-switch-focus Pattern (ACCEPTABLE)

**Locations**: All buffer functions (5 uses)

**Status**: This is intentional - each function needs different operations inside the wrapper. Not a DRY violation.

## Summary

| ID | Severity | Description | Lines Saved |
|----|----------|-------------|-------------|
| 1 | HIGH | Spawn process duplication | ~20 |
| 2 | MEDIUM | Session file iteration | ~15 |
| 3 | LOW | Text extraction inline | ~5 |
