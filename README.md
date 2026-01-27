# helix-pi

Pi coding agent integration for [Helix](https://helix-editor.com/) via [Steel](https://github.com/mattwparas/steel) plugins.

## Status

✅ **MVP Complete** - RPC integration with testable architecture

## Features

- **Split-buffer UI**: Output (top) + Input (bottom) - horizontal layout
- **Streaming responses**: Live display as LLM generates
- **Cache-friendly sessions**: `:pi-continue` reuses cached context
- **Testable core**: 33 unit tests, pure Steel logic separated from Helix

## Quick Start

```bash
# Build Helix with Steel support
cd ~/git/helix && cargo xtask steel

# Copy plugin to config
mkdir -p ~/.config/helix/cogs/pi
cp src/*.scm ~/.config/helix/cogs/pi/

# Add to ~/.config/helix/helix.scm:
# (require "cogs/pi/pi.scm")

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
| `:pi-resume` | Picker to select any session |
| `:pi-send` | Send prompt from input buffer |
| `:pi-abort` | Abort current operation |
| `:pi-quit` | Close session |

## Development

### Run Tests

```bash
steel test tests/
```

### Architecture

```
src/pi-core.scm   # Pure Steel logic (testable)
src/pi.scm        # Thin Helix integration layer
tests/            # Unit tests (steel test)
```

All event handling, RPC construction, and session utilities are in `pi-core.scm` with full test coverage. The Helix layer only wires callbacks.

### Documentation

- [Debugging & Testing](docs/debugging.md) - Development workflow
- [CLAUDE.md](CLAUDE.md) - LLM context

## License

Dual-licensed under MIT and Apache-2.0.
