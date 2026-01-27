# helix-pi

Pi coding agent integration for [Helix](https://helix-editor.com/) via [Steel](https://github.com/mattwparas/steel) plugins.

## Status

🚧 Work in progress

## Documentation

- [Tutorial: Your First Steel Plugin](docs/tutorial.md)
- [Plugin Patterns](docs/patterns.md)
- [Steel Development Guide](steel-helix-development.md) - Comprehensive reference

## Quick Start

```bash
# Build Helix with Steel support
cd ~/git/helix && cargo xtask steel

# Run Helix
~/git/helix/target/release/hx

# Test Steel REPL
steel
```

## Examples

Community plugins in `examples/community-plugins/`:

| Plugin | Description |
|--------|-------------|
| [file-tree](https://github.com/mattwparas/helix-config) | Side panel file browser |
| [notify.hx](https://github.com/chuwy/notify.hx) | Notification popups |
| [streal.hx](https://github.com/gllms/streal.hx) | File bookmarks |
| [scooter.hx](https://github.com/thomasschafer/scooter.hx) | Interactive find-replace |

## Related Repos

- [helix](https://github.com/helix-editor/helix) - The editor
- [steel](https://github.com/mattwparas/steel) - The Scheme implementation
- [helix-config](https://github.com/mattwparas/helix-config) - Matt Paras's plugins

## License

Dual-licensed under MIT and Apache-2.0.
