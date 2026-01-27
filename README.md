# helix-pi

Pi coding agent integration for [Helix](https://helix-editor.com/) via [Steel](https://github.com/mattwparas/steel) plugins.

## Status

🚧 Phase 1: Two-buffer RPC integration (in design)

## Goals

- **Split-buffer UI**: Editable input buffer + read-only markdown output
- **Streaming responses**: Live display as LLM generates text
- **Native Helix editing**: Full modal editing for prompt composition
- **Pi RPC integration**: JSON/stdio communication with `pi --mode rpc`

## Quick Start

```bash
# Build Helix with Steel support
cd ~/git/helix && cargo xtask steel

# Run Helix
~/git/helix/target/release/hx
```

## Documentation

### For Humans (Diátaxis)

| Type | Document | Purpose |
|------|----------|---------|
| Tutorial | [Your First Steel Plugin](docs/tutorial.md) | Learn by building a word counter |
| Reference | [Plugin Patterns](docs/patterns.md) | Common architectural patterns |
| Explanation | [Architecture](docs/architecture.md) | Design decisions and tradeoffs |
| Explanation | [Phase 1 Design](docs/phase1-design.md) | Two-buffer RPC specification |

### For LLMs

- [CLAUDE.md](CLAUDE.md) - Project context for AI agents

### Comprehensive Guide

- [Steel Development Guide](steel-helix-development.md) - Full reference for Steel plugin development

## Examples

Community plugins in `examples/community-plugins/`:

| Plugin | Source | Demonstrates |
|--------|--------|--------------|
| file-tree | [helix-config](https://github.com/mattwparas/helix-config) | Labelled buffers, file navigation |
| notify.hx | [chuwy](https://github.com/chuwy/notify.hx) | Custom components, rendering |
| streal.hx | [gllms](https://github.com/gllms/streal.hx) | Popup picker, file persistence |
| scooter.hx | [thomasschafer](https://github.com/thomasschafer/scooter.hx) | Rust dylib integration |

## Related Projects

- [pi coding agent](https://shittycodingagent.ai/) - The agent we're integrating
- [helix](https://github.com/helix-editor/helix) - The editor
- [steel](https://github.com/mattwparas/steel) - The Scheme implementation

## License

Dual-licensed under MIT and Apache-2.0.
