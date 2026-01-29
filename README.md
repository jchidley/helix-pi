# helix-pi

Pi coding agent integration for [Helix](https://helix-editor.com/) via [Steel](https://github.com/mattwparas/steel) plugins.

## Status

✅ **Working** - Streaming responses, session persistence, prompt caching

⚠️ **Minimal** - Standard AI tools show version, model, context, shortcuts.
helix-pi shows two empty buffers (`[pi/input]`, `[pi/output]`) — nothing else.
Use `pi` CLI directly to change models.

## Prerequisites

Custom Helix build: [mattwparas/helix](https://github.com/mattwparas/helix) (Steel fork)
with [PR #8546](https://github.com/helix-editor/helix/pull/8546) (window resize/focus mode).

```bash
cd ~/git/helix && cargo install --path helix-term --locked
```

## Quick Start

```bash
mkdir -p ~/.config/helix/cogs/pi
cp src/*.scm ~/.config/helix/cogs/pi/
# Configure helix.scm (see docs/tutorial.md)
```

```
:pi-start    # Start session
:pi-send     # Send prompt
:pi-quit     # Close session
```

## Documentation

- [Tutorial: Your First Pi Session](docs/tutorial.md)
- [How to Debug and Test](docs/debugging.md)
- [About the Architecture](docs/architecture.md)
- [Command Reference](docs/commands.md)

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

Dual-licensed under [MIT](LICENSE-MIT) and [Apache-2.0](LICENSE-APACHE).
