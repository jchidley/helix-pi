# helix-pi

Pi coding agent integration for [Helix](https://helix-editor.com/) via [Steel](https://github.com/mattwparas/steel) plugins.

## Status

✅ **Working** - RPC integration with testable architecture

## Features

- **Split-buffer UI**: Output (top) + Input (bottom) - horizontal layout
- **Streaming responses**: Live display as LLM generates
- **Cache-friendly sessions**: `:pi-continue` reuses cached context
- **Testable core**: 55 unit tests, pure Steel logic separated from Helix

## Quick Start

```bash
# Build Helix with Steel support
cd ~/git/helix && cargo xtask steel

# Copy plugin to config
mkdir -p ~/.config/helix/cogs/pi
cp src/*.scm ~/.config/helix/cogs/pi/

# Add to ~/.config/helix/helix.scm (see Installation below)

# Run Helix
~/git/helix/target/release/hx

# Start pi session
:pi-start
```

## Installation

Add to `~/.config/helix/helix.scm`:

```scheme
;; Import pi plugin functions
(require (only-in "cogs/pi/pi.scm" 
                  pi-start pi-send pi-abort pi-quit 
                  pi-continue pi-resume pi-recover))

;; Add to your existing provide statement:
(provide ...your-other-commands...
         pi-start pi-send pi-abort pi-quit 
         pi-continue pi-resume pi-recover)
```

## Commands

| Command | Description |
|---------|-------------|
| `:pi-start` | Start new session |
| `:pi-continue` | Resume previous session (cache-friendly) |
| `:pi-send` | Send prompt from input buffer |
| `:pi-abort` | Abort current operation |
| `:pi-quit` | Close session |
| `:pi-recover` | Force reset state (if stuck) |

## Usage

1. `:pi-start` creates split buffers:
   - `[pi/output]` - streaming LLM responses
   - `[pi/input]` - type your prompts here

2. Type in the input buffer, then `:pi-send`

3. Use `:pi-quit` when done (session is saved)

4. Next time, `:pi-continue` resumes with cached context

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

- [Debugging & Testing](docs/debugging.md)
- [Steel Plugin Patterns](docs/patterns.md)
- [Architecture](docs/architecture.md)

## Troubleshooting

### Helix won't start / Steel errors

Steel compilation errors scroll by fast. Use tmux to capture:

```bash
tmux new-session -d -s test 'hx .'
sleep 3
tmux capture-pane -p -t test -S -50
```

### "FreeIdentifier" error

Your `provide` is before the `define`. Move `provide` to END of file.

### Command not found

helix.scm must import AND re-export. See Installation above.

## License

Dual-licensed under MIT and Apache-2.0.
