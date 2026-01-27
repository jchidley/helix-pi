# helix-pi

Pi coding agent integration for [Helix](https://helix-editor.com/) via [Steel](https://github.com/mattwparas/steel) plugins.

## Status

✅ **MVP Complete** - Two-buffer RPC integration working

## Features

- **Split-buffer UI**: Output (left) + Input (right)
- **Streaming responses**: Live display as LLM generates
- **Cache-friendly sessions**: `:pi-continue` reuses cached context
- **Native Helix editing**: Full modal editing for prompts

## Quick Start

```bash
# Build Helix with Steel support
cd ~/git/helix && cargo xtask steel

# Copy plugin to config
mkdir -p ~/.config/helix/cogs/pi
cp src/pi.scm ~/.config/helix/cogs/pi/

# Add to ~/.config/helix/helix.scm:
# (require (only-in "cogs/pi/pi.scm" pi-start pi-send pi-abort pi-quit pi-continue))
# (provide ... pi-start pi-send pi-abort pi-quit pi-continue)

# Run Helix
~/git/helix/target/release/hx

# Start pi session
:pi-start
```

## Commands

| Command | Description |
|---------|-------------|
| `:pi-start` | Start new session |
| `:pi-continue` | Resume previous session (cache-friendly) |
| `:pi-resume` | Picker to select any session to resume |
| `:pi-send` | Send prompt from input buffer |
| `:pi-abort` | Abort current operation |
| `:pi-quit` | Close session |

## Documentation

| Document | Type | Purpose |
|----------|------|---------|
| [Debugging](docs/debugging.md) | How-to | Development and debugging workflow |
| [Architecture](docs/architecture.md) | Explanation | Design decisions |
| [Patterns](docs/patterns.md) | Reference | Steel plugin patterns |

### For LLMs

- [CLAUDE.md](CLAUDE.md) - Project context for AI agents

## Development

Use official Steel/Helix debugging tools:

```bash
# Test pure Scheme
steel interactive src/pi.scm

# In Helix
:open-debug-window    # See displayln output
:eval-buffer          # Hot reload
:evalp                # Test expression
```

See [docs/debugging.md](docs/debugging.md) for complete workflow.

## Related Projects

- [pi coding agent](https://github.com/anthropics/anthropic-quickstarts) - The agent
- [helix](https://github.com/helix-editor/helix) - The editor
- [steel](https://github.com/mattwparas/steel) - The Scheme implementation

## License

Dual-licensed under MIT and Apache-2.0.
