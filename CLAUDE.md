# CLAUDE.md - helix-pi

Pi coding agent integration for Helix editor via Steel (Scheme) plugins.

## Quick Reference

| Task | Command |
|------|---------|
| Build Helix with Steel | `cargo xtask steel` (in ~/git/helix) |
| Run Helix | `~/git/helix/target/release/hx` |
| Steel REPL | `steel` |
| Eval in Helix | `:evalp` → expression → Enter |
| Helix config | `~/.config/helix/` |
| Steel packages | `~/.local/share/steel/cogs/` |

## Project Structure

```
helix-pi/
├── CLAUDE.md                    # This file
├── steel-helix-development.md   # Detailed dev guide (existing)
├── docs/                        # Human documentation
│   ├── tutorial.md              # First plugin tutorial
│   ├── reference.md             # API reference
│   └── patterns.md              # Plugin patterns
└── examples/
    └── community-plugins/       # Downloaded plugins for reference
```

## Key Files for Steel Plugins

| File | Purpose | Loads |
|------|---------|-------|
| `~/.config/helix/helix.scm` | Exported commands | First, no editor context |
| `~/.config/helix/init.scm` | Config, keybindings, startup | Second, with editor context |

## Steel Plugin Pattern

```scheme
;; helix.scm - Define and export commands
(require (prefix-in helix. "helix/commands.scm"))
(require (prefix-in helix.static. "helix/static.scm"))
(require "helix/editor.scm")
(require "helix/misc.scm")

(provide my-command)

;;@doc
;; Description shown in command palette
(define (my-command)
  (set-status! "Done!"))
```

## Common Helix APIs

```scheme
;; Editor state
(editor-focus)                    ; Get focused view
(editor->doc-id view)             ; Get doc ID from view
(editor-mode)                     ; Current mode
(editor-document->path doc-id)    ; File path

;; Selection/text
(helix.static.current_selection)  ; Selected text as string
(helix.static.current-highlighted-text!)

;; Commands
(helix.open path)                 ; Open file
(helix.theme name)                ; Set theme
(helix.run-shell-command args...) ; Shell command

;; UI
(set-status! msg)                 ; Status bar message
(push-component! component)       ; Add UI component
(prompt title callback)           ; Show prompt
```

## Testing Steel Code

Two environments:
1. **Steel REPL** (`steel`): Pure Scheme, no Helix APIs
2. **Helix** (`:evalp`): Full plugin testing with Helix context

Use tmux skill for automated testing - see steel-helix-development.md.

## Reference Repos

| Repo | Location | Contains |
|------|----------|----------|
| helix | ~/git/helix | Editor source, STEEL.md, steel-docs.md |
| steel | ~/git/steel | Language implementation |
| helix-config | ~/git/helix-config | Matt Paras's plugins |
| pi-mono | ~/git/pi-mono | Pi agent SDK |

## Community Plugins (examples/)

- **file-tree.scm**: Side panel file browser with folding
- **recentf.scm**: Recent files persistence
- **notify.hx**: Notification popups with custom components
- **streal.hx**: File bookmarks with popup picker
- **scooter.hx**: Interactive find-and-replace

## Plugin Development Workflow

1. Test pure Scheme in `steel` REPL
2. Add function to `helix.scm` with `(provide name)`
3. Add `;;@doc` comment for command palette
4. Restart Helix or use `:evalp` to test
5. Debug with `:open-debug-window` for `displayln` output

## Gotchas

- `helix.scm` loads before editor context exists - functions receive context when called
- Helix-specific APIs only work inside Helix, not standalone REPL
- Use `enqueue-thread-local-callback` to schedule work after current execution
- Long-running code blocks UI - use threads + `hx.block-on-task` for async
