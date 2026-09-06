# AGENTS.md

Pi RPC integration for a custom Steel-enabled Helix, not stock Helix. Work from the intended project root: the child inherits cwd and uses it for project context/session selection.

## Scope and validation

Complete authorized local work with proportionate checks; reviews remain read-only unless edits are requested. Do not install/build a toolchain, overwrite live Helix configuration, restart an editor, inspect personal sessions, invoke paid prompts/compaction or publish without concrete scope. Preserve unsaved buffers and existing config.

- `steel test tests/` is the existing callback/core test suite, not a Helix, process, protocol or provider certification. If Steel is missing, report it; do not install silently. Documentation changes need source/link/patch checks, not a live prompt.
- `steel src/pi-stdio.scm` starts a real Pi child, unlike the unit suite. It loads ambient configuration and can access sessions, extensions, tools and credentials. `--no-session` is not a sandbox, and clearing one API-key variable does not guarantee an offline/authentication-failure test.
- Deployment copies `src/*.scm` into live Helix config and may overwrite work. The custom Helix build/install recipes are separate approved setup tasks, not routine validation.
- Read [commands and operating limits](docs/commands.md) before a live test. Neither client handles extension confirmation dialogs; do not bypass safeguards to make an operation proceed.

## Implementation

`src/pi-core.scm` owns mutable session state, request construction, callbacks and session-file utilities; it has no Helix imports but is not wholly pure (file/env/process access). `pi.scm` owns Helix buffers, child lifecycle and channel polling. `pi-stdio.scm` is a blocking CLI client. Keep new domain logic in the core and editor wiring in the Helix layer; do not treat old design snippets as current APIs.

Preserve the established Steel conventions: obtain each child pipe handle once; write JSON with `#%raw-write-string`, LF and flush; place Helix command exports after definitions and re-export them from helix.scm. Confirm APIs against the actual custom fork rather than assuming stock Helix supports them.

Commands already include model/thinking cycling and status; there is no full dashboard. Launchers pass no explicit model/thinking selection, so current defaults/session state apply. A separate Pi process is not the running child's control interface. Do not alter model defaults during guidance maintenance.

The [architecture](docs/architecture.md), [refactor](docs/refactor-session-state.md) and [RPC plan](docs/rpc-improvements.md) retain historical designs, not current completion guarantees. [Pattern examples](docs/patterns.md) and [Steel development](steel-helix-development.md) are illustrative and version-dependent. Vendored community examples are reference material, not deployment instructions.

Report checks actually run and remaining limits. A displayed ready/idle/switched/saved message does not prove handshake, settlement, successful session switch, persistence or child termination. No current Steel/Helix runtime support is established by this guidance review.
