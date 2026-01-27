# Architecture: Pi Integration for Helix

Design document for integrating pi coding agent with Helix via Steel plugins.

## Reference Implementation

The official pi-agent SDK (`@mariozechner/pi-agent`) is the reference design. It's MIT licensed and lives in `~/git/pi-mono/packages/agent/`. Key concepts:

- **Agent class**: Stateful wrapper around LLM with tool execution
- **Event streaming**: Fine-grained events for UI updates
- **Steering/follow-up**: Queue messages during execution
- **AgentMessage**: Extensible message type (user, assistant, toolResult, custom)

## Goals

1. **Split-buffer interface**: Separate input (full editing) and output (read-only)
2. **Native Helix editing**: Use Helix's modal editing for prompt composition
3. **Streaming output**: Live display of agent responses via events
4. **Direct SDK integration**: Use pi-agent SDK patterns, not RPC

## Architecture Options

### Option A: RPC Mode (Simpler)

Use `pi --mode rpc` as subprocess, communicate via JSON/stdio.

```
Helix/Steel → JSON/stdio → pi RPC process → LLM
```

**Pros**: Simpler Steel code, process isolation
**Cons**: Extra process, RPC protocol overhead

### Option B: Direct SDK (More Control)

Embed pi-agent logic directly, or call pi-agent via a thin TypeScript bridge.

```
Helix/Steel → (bridge) → pi-agent SDK → LLM
```

**Pros**: Direct event access, no RPC overhead, same patterns as official
**Cons**: More complex Steel code, or requires TS bridge process

**Recommendation**: Start with RPC mode for simplicity, migrate to direct if needed.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Helix Editor                          │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐    │
│  │              Output Buffer (read-only)              │    │
│  │  - Conversation history (AgentMessage[])            │    │
│  │  - Streaming assistant responses                    │    │
│  │  - Tool execution blocks (collapsible)              │    │
│  │  - Status: model, context usage, streaming state    │    │
│  └─────────────────────────────────────────────────────┘    │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              Input Buffer (editable)                │    │
│  │  - Full Helix modal editing                         │    │
│  │  - Multi-line prompt composition                    │    │
│  │  - History navigation (previous prompts)            │    │
│  │  - @ file references, /commands, path completion    │    │
│  └─────────────────────────────────────────────────────┘    │
├─────────────────────────────────────────────────────────────┤
│                    Steel Plugin Layer                        │
│  - Process management (pi RPC subprocess)                   │
│  - Event handling (agent_start/end, message_*, tool_*)      │
│  - State: model, thinkingLevel, isStreaming, messages       │
│  - Steering queue (interrupt tools)                         │
│  - Follow-up queue (queue after completion)                 │
└───────────────────────────┬─────────────────────────────────┘
                            │ JSON/stdio
                            ▼
                    ┌───────────────┐
                    │ pi --mode rpc │
                    └───────────────┘
```

## Event Flow (from pi-agent SDK)

### prompt() Sequence

```
send_message("Hello")
├─ agent_start
├─ turn_start
├─ message_start   { message: userMessage }
├─ message_end     { message: userMessage }
├─ message_start   { message: assistantMessage }
├─ message_update  { delta: "Hi" }              ← Stream to output
├─ message_update  { delta: " there!" }
├─ message_end     { message: assistantMessage }
├─ turn_end        { message, toolResults: [] }
└─ agent_end       { messages: [...] }
```

### With Tool Calls

```
send_message("Read config.json")
├─ agent_start
├─ turn_start
├─ message_start/end  { userMessage }
├─ message_start      { assistantMessage with toolCall }
├─ message_update...                              ← "Let me read that file"
├─ message_end
├─ tool_execution_start  { toolName: "Read", args: {path: "config.json"} }
├─ tool_execution_update { partialResult: "..." } ← Stream tool output
├─ tool_execution_end    { result: "...", isError: false }
├─ message_start/end  { toolResultMessage }
├─ turn_end
│
├─ turn_start                                     ← Next turn
├─ message_start      { assistantMessage }
├─ message_update...                              ← "The config contains..."
├─ message_end
├─ turn_end
└─ agent_end
```

## Component Design

### 1. Buffer Management

Use the **Labelled Buffer** pattern:

```scheme
(define PI-OUTPUT "helix-pi/output")   ; Read-only conversation
(define PI-INPUT  "helix-pi/input")    ; Editable prompt
```

**Output buffer behaviors**:
- Read-only markdown/text mode
- Auto-scroll during streaming (follow insertion point)
- Collapsible tool output sections
- Message navigation (n/p to jump between user messages)

**Input buffer behaviors**:
- Full Helix editing (normal, insert, select modes)
- Multi-line (Enter doesn't send)
- Send with `:pi-send` command or keybinding
- History with `:pi-history-prev` / `:pi-history-next`

### 2. State Management

Map pi-agent's `AgentState` to Steel:

```scheme
;; Core state (mirrors AgentState)
(define *pi-model* #f)                ; Model name string
(define *pi-thinking-level* "off")    ; "off" | "minimal" | "low" | "medium" | "high"
(define *pi-messages* '())            ; List of AgentMessage plists
(define *pi-is-streaming* #f)         ; Boolean
(define *pi-stream-message* #f)       ; Current partial during streaming
(define *pi-pending-tool-calls* '())  ; Set of tool call IDs
(define *pi-error* #f)                ; Error message or #f

;; UI state
(define *pi-input-history* '())       ; List of previous prompts
(define *pi-history-index* #f)        ; Current position in history
```

### 3. RPC Communication

```scheme
(require-builtin steel/process)
(require "steel/result")

;; Start pi RPC process
(define (pi-start-process)
  (define child
    (unwrap-ok
      (spawn-process
        (with-stdout-piped
          (with-stdin-piped
            (command "pi" '("--mode" "rpc" "--no-session")))))))
  (list (child-stdin child) (child-stdout child) child))

;; Send command (JSON-encode plist, add newline)
(define (pi-send! stdin command)
  (write-line! stdin (json-encode command)))

;; Commands map to RPC types:
;; - send_message: { "type": "send_message", "message": "...", "id": "req_1" }
;; - get_state: { "type": "get_state", "id": "req_2" }
;; - abort: { "type": "abort", "id": "req_3" }
;; - set_model: { "type": "set_model", "model": "...", "id": "req_4" }
;; - steer: { "type": "steer", "message": "...", "id": "req_5" }
;; - follow_up: { "type": "follow_up", "message": "...", "id": "req_6" }
```

### 4. Event Handling

Background thread reads stdout, dispatches to UI:

```scheme
(define (pi-event-loop stdout)
  (spawn-native-thread
    (lambda ()
      (let loop ()
        (define line (read-line-from-port stdout))
        (when line
          (define event (json-decode line))
          (hx.block-on-task
            (lambda ()
              (pi-handle-event event)))
          (loop))))))

(define (pi-handle-event event)
  (define type (hash-ref event "type"))
  (cond
    [(equal? type "agent_start")
     (set! *pi-is-streaming* #t)]
    
    [(equal? type "agent_end")
     (set! *pi-is-streaming* #f)
     (set! *pi-messages* (hash-ref event "messages"))]
    
    [(equal? type "message_update")
     (define delta (hash-ref (hash-ref event "assistantMessageEvent") "delta"))
     (pi-append-to-output delta)]
    
    [(equal? type "tool_execution_start")
     (pi-render-tool-start event)]
    
    [(equal? type "tool_execution_update")
     (pi-render-tool-update event)]
    
    [(equal? type "tool_execution_end")
     (pi-render-tool-end event)]
    
    [else (void)]))
```

### 5. Output Rendering

**Message format** (simple text, no complex markdown):

```
─────────────────────────────────────────────────────────────
You [10:30:42]
─────────────────────────────────────────────────────────────
Read the config.json file and explain what it does.

─────────────────────────────────────────────────────────────
Assistant [10:30:43] claude-sonnet-4
─────────────────────────────────────────────────────────────
Let me read that file for you.

▶ READ: config.json
│ {
│   "name": "my-project",
│   "version": "1.0.0"
│ }

The config file is a standard package.json...
```

**Tool output (collapsible)**:

```scheme
(define (pi-render-tool-start event)
  (define tool-name (hash-ref event "toolName"))
  (define args (hash-ref event "args"))
  (pi-append-to-output
    (format "\n▶ ~a: ~a\n│ " 
            (string-upcase tool-name)
            (pi-format-tool-args args))))
```

### 6. Input Features

**Send prompt**:
```scheme
(provide pi-send)

;;@doc
;; Send the current input buffer contents to pi
(define (pi-send)
  (define text (pi-get-input-contents))
  (when (> (string-length (string-trim text)) 0)
    (pi-history-add text)
    (pi-send! *pi-stdin* 
      (hash "type" "send_message" 
            "message" text 
            "id" (pi-next-request-id)))
    (pi-clear-input)))
```

**History**:
```scheme
(provide pi-history-prev pi-history-next)

;;@doc
;; Navigate to previous prompt in history
(define (pi-history-prev)
  (when (not (null? *pi-input-history*))
    (cond
      [(not *pi-history-index*)
       (set! *pi-history-index* 0)]
      [(< *pi-history-index* (- (length *pi-input-history*) 1))
       (set! *pi-history-index* (+ *pi-history-index* 1))])
    (pi-set-input-contents 
      (list-ref *pi-input-history* *pi-history-index*))))
```

**Steering (interrupt)**:
```scheme
(provide pi-steer)

;;@doc
;; Send steering message to interrupt current tool execution
(define (pi-steer)
  (when *pi-is-streaming*
    (define text (pi-get-input-contents))
    (pi-send! *pi-stdin*
      (hash "type" "steer"
            "message" text
            "id" (pi-next-request-id)))
    (pi-clear-input)))
```

### 7. Keybindings

**Input buffer** (pi-input mode):
| Key | Command | Description |
|-----|---------|-------------|
| `<C-CR>` or `:pi-send` | `pi-send` | Send message |
| `<C-k>` | `pi-abort` | Abort streaming |
| `<C-s>` | `pi-steer` | Steering (interrupt) |
| `<C-p>` | `pi-history-prev` | Previous history |
| `<C-n>` | `pi-history-next` | Next history |
| `@` | completion | File reference |
| `/` | completion | Slash command |

**Output buffer** (pi-output mode):
| Key | Command | Description |
|-----|---------|-------------|
| `n` | `pi-next-message` | Jump to next user message |
| `p` | `pi-prev-message` | Jump to previous user message |
| `<Tab>` | `pi-toggle-fold` | Toggle tool output fold |
| `<CR>` | `pi-visit-file` | Open file at point |
| `q` | `pi-quit` | Close session |

## Implementation Phases

### Phase 1: Core Infrastructure
- [ ] Process spawn/management
- [ ] JSON encode/decode helpers
- [ ] Basic send/receive
- [ ] Event dispatch skeleton

### Phase 2: Buffer UI
- [ ] Split buffer layout (output + input)
- [ ] Output buffer with basic text rendering
- [ ] Input buffer with send command
- [ ] Abort command

### Phase 3: Streaming
- [ ] Background thread for stdout
- [ ] Live message_update rendering
- [ ] Status indicator (streaming/idle)

### Phase 4: Tool Output
- [ ] tool_execution_* event handling
- [ ] Formatted tool blocks
- [ ] Basic folding (collapsed by default)

### Phase 5: Input Enhancements
- [ ] History (previous/next)
- [ ] Steering messages
- [ ] Follow-up queue

### Phase 6: Polish
- [ ] @ file completion
- [ ] / command completion
- [ ] Model/thinking-level switching
- [ ] Session management (resume, fork)

## Files Structure

```
~/.config/helix/
├── helix.scm           # Add: (load-package "pi.scm")
└── cogs/
    └── pi/
        ├── pi.scm          # Main module, provides commands
        ├── rpc.scm         # Process management, JSON protocol
        ├── state.scm       # State variables, event handling
        ├── output.scm      # Output buffer rendering
        ├── input.scm       # Input buffer, history
        └── completion.scm  # @ file, / command, path completion
```

## References

- **pi-agent SDK**: `~/git/pi-mono/packages/agent/` (MIT license)
  - `README.md` - API documentation
  - `src/types.ts` - Event types, AgentState
  - `src/agent.ts` - Agent class implementation
  - `src/agent-loop.ts` - Core loop logic

- **Steel plugins**: `~/git/helix-config/`
  - `cogs/file-tree.scm` - Labelled buffer pattern
  - `cogs/recentf.scm` - File persistence pattern

- **Community plugins**: `~/git/helix-pi/examples/community-plugins/`
  - `notify.hx/` - Custom components, rendering
  - `streal.hx/` - Popup picker pattern
