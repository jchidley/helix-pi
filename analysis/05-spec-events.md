# Spec: events

## Observable Behaviours

### pi-event-loop [side-effects: thread, I/O, UI]
- Spawns native thread that reads lines from *pi-stdout*
- For each line: parses JSON, calls pi-handle-event via hx.block-on-task
- Loops until read-line-from-port returns non-string (EOF)

### pi-handle-event [side-effects: UI, state]
- **Input**: event (hash with 'type key)
- Dispatches on event type:

| Event Type | Action |
|------------|--------|
| `agent_start` | status "streaming..." |
| `agent_end` | append "\n\n", status "idle" |
| `message_start` | If role=user: append "## You\n\n"; if role=assistant: append "## Assistant\n\n" |
| `message_update` | See assistantMessageEvent handling below |
| `message_end` | If role=user: extract and append text content |
| `tool_execution_start` | Append "\n**toolName**\n```\n" |
| `tool_execution_update` | Stream tool output delta (tracks accumulated length) |
| `tool_execution_end` | Show final output delta, append "```\n\n" |
| `turn_start` | ignore |
| `turn_end` | ignore |
| `response` | ignore |
| unknown | callback to on-unknown-event |

### assistantMessageEvent handling (in message_update)

| Event Type | Action |
|------------|--------|
| `text_delta` | append delta text |
| `thinking_start` | append "<thinking>\n" |
| `thinking_delta` | append delta text |
| `thinking_end` | append "\n</thinking>\n\n" |
| other | ignore |

### Tool output streaming
- Uses `*tool-output-lengths*` hash to track accumulated output per toolCallId
- `tool_execution_update`: computes delta from accumulated partialResult, appends new text
- `tool_execution_end`: shows any remaining text not yet streamed, closes code block

## Notes

- Event handling follows pi RPC event schema (see pi-mono/packages/coding-agent/docs/rpc.md)
- User message content rendered in message_end (not streamed)
- Assistant text streamed via message_update/text_delta
- Thinking content displayed with `<thinking>` markers
- Tool output streamed with delta computation from accumulated results
