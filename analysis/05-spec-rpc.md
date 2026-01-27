# Spec: rpc

## Observable Behaviours

### next-request-id [side-effects: state]
- Increments *pi-request-id*
- Returns `"req_N"` where N is new counter value

### pi-rpc-send [side-effects: I/O]
- **Input**: command (hash)
- **Pre**: pi-running? is #t
- **Post**: JSON written to *pi-stdin* with newline, flushed
- **Returns**: request id string, or #f if not running
- **Wire format**: `{"id":"req_N",...command...}\n`

### pi-rpc-prompt [side-effects: I/O]
- **Input**: message (string)
- Calls pi-rpc-send with `{"type":"prompt","message":<message>}`

### pi-rpc-abort [side-effects: I/O]
- Calls pi-rpc-send with `{"type":"abort"}`

### pi-rpc-get-state [DEAD CODE]
- Calls pi-rpc-send with `{"type":"get_state"}`
- **Never called** - candidate for removal
