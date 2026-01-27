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
| `agent_start` | Set *pi-is-streaming* #t, status "streaming..." |
| `agent_end` | Set *pi-is-streaming* #f, append "\n\n", status "idle" |
| `message_start` | If role=user: append "## You\n\n"; if role=assistant: append "## Assistant\n\n" |
| `message_update` | If text_delta: append delta text |
| `message_end` | If role=user: extract and append text content |
| `tool_execution_start` | Append "\n**toolName**\n```\n" |
| `tool_execution_end` | Append "```\n\n" |
| `turn_start` | ignore |
| `turn_end` | ignore |
| `response` | ignore |
| unknown | displayln warning |

### *pi-is-streaming* [WRITE-ONLY]
- Set by pi-handle-event (agent_start/end) and pi-quit
- **Never read** - candidate for removal or future use

## Notes

- Event handling assumes specific pi RPC event schema
- User message content rendered in message_end (not streamed)
- Assistant content streamed via message_update/text_delta
