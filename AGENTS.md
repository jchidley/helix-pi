# Agent Instructions

See **[CLAUDE.md](./CLAUDE.md)** for full documentation.

## Reference Implementation

`~/git/pi-mono` contains pi-agent reference code. Key files:
- `packages/coding-agent/docs/rpc.md` - RPC protocol spec
- `packages/coding-agent/src/modes/rpc/rpc-client.ts` - TypeScript RPC client
- `packages/agent/src/types.ts` - Event type definitions

## Commands

| Command | Description |
|---------|-------------|
| `:pi-start` | Start new session |
| `:pi-continue` | Resume previous (cache-friendly) |
| `:pi-send` | Send prompt |
| `:pi-abort` | Abort operation |
| `:pi-quit` | Close session |

## Testing

```bash
steel test tests/           # Run 33 unit tests
steel interactive src/pi-core.scm  # REPL with core loaded
```

## Debugging

Use `steel interactive`, `:open-debug-window`, `:eval-buffer`. Do NOT use tmux.
