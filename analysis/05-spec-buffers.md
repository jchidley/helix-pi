# Spec: buffers

## Observable Behaviours

### PI-OUTPUT, PI-INPUT [pure]
- Constants: `"pi/output"`, `"pi/input"`
- Used as labelled buffer identifiers

### pi-create-buffers [side-effects: UI]
- If buffers exist: clears output, focuses input
- If buffers don't exist: creates output (left), input (right), focuses input
- Uses `temporarily-switch-focus` pattern

### pi-clear-output [side-effects: UI]
- Selects all in PI-OUTPUT buffer, deletes selection
- Uses `temporarily-switch-focus` pattern

### pi-clear-input [side-effects: UI]
- Selects all in PI-INPUT buffer, deletes selection
- Uses `temporarily-switch-focus` pattern

### pi-append-output [side-effects: UI]
- **Input**: text (string)
- Moves cursor to end of PI-OUTPUT, inserts text
- Uses `temporarily-switch-focus` pattern

### pi-get-input [side-effects: UI read]
- **Returns**: string (contents of PI-INPUT buffer)
- Uses `temporarily-switch-focus` pattern

## Patterns

All buffer functions use `temporarily-switch-focus` wrapper:
```scheme
(temporarily-switch-focus
  (lambda ()
    (open-labelled-buffer <buffer-name>)
    <operations>))
```

This ensures focus returns to original buffer after operation.
