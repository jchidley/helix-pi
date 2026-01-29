# helix-pi

Pi coding agent integration for [Helix](https://helix-editor.com/) via [Steel](https://github.com/mattwparas/steel) plugins.

## Status

✅ **Working** - Streaming responses, session persistence, prompt caching

⚠️ **Minimal** - This is a bare "just working" integration. Standard AI coding
tools (pi, Claude Code, Codex) show version, model name, context usage, keyboard
shortcuts, and status information. helix-pi shows two empty buffers labeled
`[pi/input]` and `[pi/output]` — nothing else.

**To change models:** Use the `pi` command line directly rather than the Helix integration.

## Prerequisites

This plugin requires a custom build of Helix with Steel plugin support:

**Helix with Steel + Window Resize** — My build of [mattwparas/helix](https://github.com/mattwparas/helix)
(Steel fork) patched with [PR #8546](https://github.com/helix-editor/helix/pull/8546)
for flex resize and focus mode (expand/contract windows).

The window resize feature (originally [PR #2704](https://github.com/helix-editor/helix/pull/2704))
allows expanding the active window to focus on code or the AI response buffer.

Building from my local setup:
```bash
cd ~/git/helix
cargo install --path helix-term --locked
```

## Quick Start

```bash
# Install plugin
mkdir -p ~/.config/helix/cogs/pi
cp src/*.scm ~/.config/helix/cogs/pi/

# Add to ~/.config/helix/helix.scm (see Installation)

# Use
:pi-start    # Start new session
:pi-send     # Send prompt from input buffer
:pi-quit     # Close session
```

## Commands

| Command | Key | Description |
|---------|-----|-------------|
| `:pi-start` | `Alt-p n` | Start new session |
| `:pi-continue` | `Alt-p p` | Resume last session (cache-friendly) |
| `:pi-sessions` | `Alt-p l` | List available sessions |
| `:pi-resume` | `Alt-p r` | Resume session (picker if empty, path from input) |
| `:pi-send` | `Alt-p s` | Send prompt from input buffer |
| `:pi-abort` | `Alt-p a` | Abort current operation |
| `:pi-quit` | `Alt-p q` | Close session |
| `:pi-model` | `Alt-p m` | Cycle to next model |
| `:pi-thinking` | `Alt-p t` | Cycle thinking level |
| `:pi-status` | `Alt-p S` | Show current status |
| `:pi-compact` | `Alt-p C` | Compact conversation context |
| `:pi-new` | `Alt-p N` | Fresh session (keep buffers) |
| `:pi-steer` | `Alt-p i` | Interrupt with steering message |
| `:pi-follow` | `Alt-p f` | Queue follow-up message |
| `:pi-recover` | `Alt-p R` | Force reset state |

## Installation

Add to `~/.config/helix/helix.scm`:

```scheme
(require (only-in "cogs/pi/pi.scm" 
                  pi-start pi-continue pi-sessions pi-resume pi-send pi-abort pi-quit pi-recover
                  pi-model pi-thinking pi-status pi-compact pi-new pi-steer pi-follow))

(provide ...your-other-commands...
         pi-start pi-continue pi-sessions pi-resume pi-send pi-abort pi-quit pi-recover
         pi-model pi-thinking pi-status pi-compact pi-new pi-steer pi-follow)
```

Optional keybindings in `~/.config/helix/init.scm`:

```scheme
(add-global-keybinding
 (hash "normal"
       (hash "A-p" (hash "p" ":pi-continue"
                         "n" ":pi-start"
                         "l" ":pi-sessions"
                         "r" ":pi-resume"
                         "s" ":pi-send"
                         "a" ":pi-abort"
                         "q" ":pi-quit"
                         "m" ":pi-model"
                         "t" ":pi-thinking"
                         "R" ":pi-recover"
                         "S" ":pi-status"
                         "C" ":pi-compact"
                         "N" ":pi-new"
                         "f" ":pi-follow"
                         "i" ":pi-steer"))))
```

## Documentation

- [Tutorial: Your First Pi Session](docs/tutorial.md)
- [How to Debug and Test](docs/debugging.md)
- [About the Architecture](docs/architecture.md)
- [Steel Plugin Patterns](docs/patterns.md)

## Development

```bash
steel test tests/                        # Run tests
cp src/*.scm ~/.config/helix/cogs/pi/    # Deploy
```

## About This Code

Almost all of this code is AI/LLM-generated. It's best used as a source of
inspiration for your own AI/LLM efforts rather than as a traditional library.

**This is personal alpha software.** All my GitHub projects should be considered
experimental. If you want to use them:

- **Pin to a specific commit** — don't track `main`, it changes without warning
- **Use AI/LLM to adapt** — without AI assistance, these projects are hard to use
- **Treat as inspiration** — build your own version rather than depending on mine

**Suggestions welcome** — If you have ideas for improvements or changes, I'd be
delighted to read them and use them as inspiration for my own efforts.

**Why not a library?** These days it's often quicker to use AI/LLM to build your
own than to integrate traditional libraries. My use of AI/LLM is inspired by
these people and posts:

- [Simon Willison's Weblog](https://simonwillison.net/) — Essential reading on
  LLMs, prompt engineering, and building with AI
- [CLI over MCP](https://lucumr.pocoo.org/2025/8/18/code-mcps/) — Armin Ronacher
  on why command-line tools are better integration points than custom protocols
- [Build It Yourself](https://lucumr.pocoo.org/2025/12/22/a-year-of-vibes/) —
  Armin Ronacher: "With our newfound power from agentic coding tools, you can
  build much of this yourself..."
- [Shipping at Inference Speed](https://steipete.me/posts/2025/shipping-at-inference-speed) —
  Peter Steinberger on the new workflow of building with AI assistance
- [Year in Review 2025](https://mariozechner.at/posts/2025-12-22-year-in-review-2025/) —
  Mario Zechner on AI-assisted development

**What I use:** Currently Anthropic's Claude Opus, evaluating OpenAI's GPT Codex
as an alternative.

## License

This project is dual-licensed under the terms of both the MIT license and the
Apache License (Version 2.0).

See [LICENSE-APACHE](LICENSE-APACHE) and [LICENSE-MIT](LICENSE-MIT) for details.

### Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in this project by you, as defined in the Apache-2.0 license,
shall be dual licensed as above, without any additional terms or conditions.
