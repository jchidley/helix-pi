# Architecture: Pi Integration for Helix

Design document for integrating pi coding agent with Helix via Steel plugins.

**Note**: This design is inspired by observing the Emacs pi-coding-agent's user experience, but the implementation approach must be original due to license incompatibility (GPL-3 vs MIT/Apache-2).

## Goals

1. **Split-buffer interface**: Separate input (full editing) and output (read-only)
2. **Native Helix editing**: Use Helix's modal editing for prompt composition
3. **Streaming output**: Live display of agent responses
4. **Markdown rendering**: Syntax-highlighted code blocks in output

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Helix Editor                          │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐    │
│  │              Output Buffer (read-only)              │    │
│  │  - Rendered markdown conversation                   │    │
│  │  - Syntax-highlighted code blocks                   │    │
│  │  - Collapsible tool output sections                 │    │
│  │  - Status indicators (model, context usage)         │    │
│  └─────────────────────────────────────────────────────┘    │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              Input Buffer (editable)                │    │
│  │  - Full Helix editing (modal, macros, registers)    │    │
│  │  - Multi-line prompt composition                    │    │
│  │  - History navigation                               │    │
│  │  - @ file references, /commands completion          │    │
│  └─────────────────────────────────────────────────────┘    │
├─────────────────────────────────────────────────────────────┤
│                    Steel Plugin Layer                        │
│  - RPC communication with pi process                        │
│  - State management (model, session, context)               │
│  - Event dispatch (streaming, tool execution)               │
└───────────────────────────┬─────────────────────────────────┘
                            │ JSON/stdio
                            ▼
                    ┌───────────────┐
                    │ pi --mode rpc │
                    └───────────────┘
```

## Component Design

### 1. Buffer Management

Use the **Labelled Buffer** pattern from helix-config:

```
PI-OUTPUT-BUFFER  = "helix-pi/output"   ; Read-only conversation
PI-INPUT-BUFFER   = "helix-pi/input"    ; Editable prompt
```

**Split layout options**:
- Horizontal: Output top, Input bottom (like Emacs version)
- Vertical: Output left, Input right
- User-configurable via Steel variable

**Key behaviors**:
- Output buffer: Markdown mode, read-only, auto-scroll on streaming
- Input buffer: Plain text mode, full Helix editing, mode-specific keybindings

### 2. RPC Communication Layer

**Process management**:
```scheme
;; Spawn pi process
(define pi-process
  (spawn-process
    (with-stdout-piped
      (with-stdin-piped
        (command "pi" '("--mode" "rpc" "--no-session"))))))

;; I/O handles
(define pi-stdin (child-stdin pi-process))
(define pi-stdout (child-stdout pi-process))
```

**Message protocol** (JSON-over-stdio):
```scheme
;; Send command
(define (rpc-send command)
  (write-line! pi-stdin (json-encode command)))

;; Commands have structure:
;; { "type": "send_message", "message": "...", "id": "req_1" }
;; { "type": "get_state", "id": "req_2" }
;; { "type": "abort", "id": "req_3" }
```

**Async event handling**:
- Use `spawn-native-thread` for non-blocking stdout reads
- Use `hx.block-on-task` to update UI from background thread
- Event types: `agent_start`, `agent_end`, `message_update`, `tool_execution_*`

### 3. State Management

**Session state** (stored in module-level variables):
```scheme
(define *pi-status* 'idle)           ; 'idle | 'streaming | 'compacting
(define *pi-model* #f)               ; Current model name
(define *pi-thinking-level* #f)      ; extended | high | none
(define *pi-session-id* #f)          ; Session identifier
(define *pi-context-usage* 0)        ; Percentage 0-100
(define *pi-messages* '())           ; Conversation history
```

**Status transitions**:
```
idle → streaming (on send_message)
streaming → idle (on agent_end)
idle → compacting (on compact)
compacting → idle (on compact_end)
```

### 4. Output Buffer Rendering

**Markdown handling options**:

1. **Raw markdown**: Just insert text, rely on syntax highlighting
   - Pros: Simple, works today
   - Cons: No folding, no rendered formatting

2. **Processed markdown**: Parse and add Helix properties
   - Code blocks: Apply language-specific highlighting
   - Headers: Add fold markers
   - Tool output: Collapsible sections with preview

3. **Hybrid**: Raw markdown with custom overlays for structure
   - Use `overlay` text properties for code blocks
   - Track block boundaries for folding

**Tool output display**:
```
▶ BASH: git status
  ┌────────────────────────────────────
  │ On branch main
  │ Your branch is up to date...
  │ [+3 more lines - press TAB to expand]
  └────────────────────────────────────
```

### 5. Input Buffer Features

**Prompt composition**:
- Full Helix modal editing (normal, insert, select modes)
- Multi-line support (no immediate send on Enter)
- Send with custom keybinding (e.g., `<C-Enter>` or command)

**History**:
```scheme
(define *input-history* '())
(define *history-index* #f)

(define (history-previous)
  (when (and (not (null? *input-history*))
             (or (not *history-index*)
                 (< *history-index* (- (length *input-history*) 1))))
    (set! *history-index* (if *history-index* (+ *history-index* 1) 0))
    (replace-buffer-contents (list-ref *input-history* *history-index*))))
```

**Completions**:
- `@` - File reference (project files, respecting .gitignore)
- `/` - Slash commands from ~/.pi/commands/
- `./`, `../`, `~/` - Path completion

### 6. Keybindings

**Input buffer** (pi-input mode):
| Key | Action |
|-----|--------|
| `<C-Enter>` | Send message |
| `<C-c>` | Abort streaming |
| `<C-p>` | History previous |
| `<C-n>` | History next |
| `<Tab>` | Complete at point |
| `@` | File reference picker |

**Output buffer** (pi-output mode):
| Key | Action |
|-----|--------|
| `n` / `p` | Navigate messages |
| `<Tab>` | Toggle fold |
| `<Enter>` | Open file at point |
| `q` | Close session |

### 7. Status Display

**Header line** (in input buffer or status area):
```
[claude-sonnet-4] thinking:high | context: 45% ████████░░░░░░░░░░░░ | idle
```

**Options for status**:
1. Custom component overlay (like notify.hx)
2. Status line integration (if Helix supports)
3. Buffer header text (first line of output buffer)

## Implementation Phases

### Phase 1: Core RPC
- [ ] Process spawning and management
- [ ] JSON encoding/decoding
- [ ] Basic send/receive
- [ ] State tracking

### Phase 2: Buffer UI
- [ ] Split buffer layout
- [ ] Output buffer (read-only, basic text)
- [ ] Input buffer (editable)
- [ ] Send/abort commands

### Phase 3: Streaming
- [ ] Background thread for stdout
- [ ] Live output updates
- [ ] Progress indicators

### Phase 4: Enhanced Output
- [ ] Markdown syntax highlighting
- [ ] Code block detection
- [ ] Collapsible sections

### Phase 5: Input Enhancements
- [ ] History
- [ ] @ file completion
- [ ] / command completion
- [ ] Path completion

### Phase 6: Session Management
- [ ] Resume session picker
- [ ] Fork conversation
- [ ] Export to HTML

## Open Questions

1. **Markdown rendering**: How much can Helix's tree-sitter do vs custom parsing?

2. **Async I/O**: Best pattern for continuous stdout reading without blocking?

3. **Folding**: Does Helix have native fold support we can leverage?

4. **Status line**: Can we integrate with Helix's status line, or need overlay?

5. **Syntax highlighting in code blocks**: Can we switch tree-sitter parsers mid-buffer?

## References

- [pi RPC documentation](https://shittycodingagent.ai/)
- [Steel process I/O](~/git/steel) - `steel/process` module
- [helix-config plugins](~/git/helix-config) - Labelled buffer patterns
- [notify.hx](examples/community-plugins/notify.hx) - Custom components
- [steel-helix-development.md](../steel-helix-development.md) - Development workflow
