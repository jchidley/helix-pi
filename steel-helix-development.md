# Steel Development for Helix

Write and debug Steel (Scheme) plugins for the helix editor using the Steel REPL and tmux for interactive development.

## Quick Reference

| Task | Command |
|------|---------|
| Start Steel REPL | `steel` |
| Start Helix (steel-enabled) | `~/git/helix/target/release/hx` |
| Eval expression in Helix | `:evalp` → type expression → Enter |
| Open config | `:open-helix-scm` or `:open-init-scm` |
| Open debug window | `:open-debug-window` |
| Open terminal | `:open-term` |

## Project Structure

```
~/.config/helix/
├── helix.scm          # Exported commands (loaded first)
├── init.scm           # Initialization, keybindings (loaded second)
└── config.toml        # Standard helix config

~/.local/share/steel/cogs/
├── helix/             # Helix Steel runtime modules
├── steel-pty/         # Terminal emulator package
└── mattwparas-helix-package/  # Extended plugins
```

## Two Environments

| Environment | Use For | Helix APIs? |
|-------------|---------|-------------|
| **Steel REPL** (`steel`) | Pure Scheme, learning APIs, syntax testing | ❌ No |
| **Helix** (`:evalp`) | Full plugin testing, editor integration | ✅ Yes |

---

# For LLMs: Development Workflow

## Testing Steel Code via tmux

Use tmux to interact with Steel REPL or Helix when developing plugins.

### Steel REPL Session

```bash
# Create isolated tmux session
SESSION="$(date +%s%N | sha256sum | head -c 6)"
SOCKET="/tmp/tmux-sockets/$SESSION.sock"
mkdir -p /tmp/tmux-sockets

# Start Steel REPL
TMUX= tmux -S "$SOCKET" new -d -s "$SESSION"
tmux -S "$SOCKET" send-keys -t "$SESSION":0.0 'steel' Enter
sleep 2

# Send expression
tmux -S "$SOCKET" send-keys -t "$SESSION":0.0 '(+ 1 2 3)' Enter
sleep 0.5

# Capture output
tmux -S "$SOCKET" capture-pane -p -t "$SESSION":0.0 | tail -5
# => 6

# Cleanup
tmux -S "$SOCKET" kill-session -t "$SESSION"
```

### Helix Session

```bash
# Start Helix
TMUX= tmux -S "$SOCKET" new -d -s "$SESSION"
tmux -S "$SOCKET" send-keys -t "$SESSION":0.0 '~/git/helix/target/release/hx' Enter
sleep 2

# Send command
tmux -S "$SOCKET" send-keys -t "$SESSION":0.0 ':evalp' Enter
sleep 0.3
tmux -S "$SOCKET" send-keys -t "$SESSION":0.0 -l '(+ 1 2)'
tmux -S "$SOCKET" send-keys -t "$SESSION":0.0 Enter
sleep 0.5

# Capture (result appears in status bar)
tmux -S "$SOCKET" capture-pane -p -t "$SESSION":0.0 | tail -3
```

## Steel API Discovery Pattern

When unsure of function names, test in REPL:

```scheme
;; Try common variations
(string-split "a b" " ")      ; ❌ not found
(split-whitespace "a b")      ; ✅ => '("a" "b")

(hash-ref h key default)      ; ❌ only 2 args
(hash-try-get h key)          ; ✅ returns #false if missing
```

## Common Steel Functions

```scheme
;; Data structures
(hash "key" value ...)        ; Create hash map
(hash-ref h key)              ; Get value (errors if missing)
(hash-try-get h key)          ; Get value (returns #false if missing)
(hash-insert h key val)       ; Returns new hash (immutable)
(hash-contains? h key)        ; Check existence

;; Strings
(split-whitespace str)        ; Split on whitespace
(string-append s1 s2 ...)     ; Concatenate
(string-join lst sep)         ; Join with separator

;; Lists
(map fn lst)                  ; Transform
(filter fn lst)               ; Filter
(foldl fn init lst)           ; Reduce left

;; Process I/O (for pi RPC integration)
(require-builtin steel/process)
(require "steel/result")
(command "prog" '("arg1"))              ; Create command
(with-stdin-piped cmd)                  ; Pipe stdin
(with-stdout-piped cmd)                 ; Pipe stdout
(spawn-process cmd)                     ; Returns (Ok child) or (Err e)
(unwrap-ok result)                      ; Extract from Ok
(child-stdin child)                     ; Get stdin port
(child-stdout child)                    ; Get stdout port
(write-line! port str)                  ; Write line
(read-line-from-port port)              ; Read line (blocking)
```

## Helix-Specific APIs

Only available inside Helix, not in standalone REPL:

```scheme
;; Require helix modules
(require (prefix-in helix. "helix/commands.scm"))
(require (prefix-in helix.static. "helix/static.scm"))
(require "helix/editor.scm")
(require "helix/misc.scm")
(require "helix/components.scm")

;; Editor state
(editor-focus)                          ; Current focused view
(editor->doc-id focus)                  ; Get document ID
(editor-mode)                           ; Current mode (normal/insert/etc)
(editor-document->path doc-id)          ; File path

;; Selection/text
(helix.static.current_selection)        ; Selected text as string
(helix.static.current-selection-object) ; Selection object (for restore)
(helix.static.current-highlighted-text!); Get highlighted text

;; Commands
(helix.open path)                       ; Open file
(helix.theme name)                      ; Set theme
(helix.run-shell-command args...)       ; Run shell command

;; UI
(set-status! msg)                       ; Show in status bar
(push-component! component)             ; Add UI component
(prompt title callback)                 ; Show prompt
```

## Writing a helix.scm Command

```scheme
;; In ~/.config/helix/helix.scm

(require (prefix-in helix. "helix/commands.scm"))
(require (prefix-in helix.static. "helix/static.scm"))
(require "helix/editor.scm")

;; Export the function
(provide my-command)

;;@doc
;; Description shown in command palette
(define (my-command)
  ;; Your code here
  (set-status! "Command executed!"))
```

Then restart Helix and use `:my-command`.

---

# For Humans: Tutorial

## Tutorial: Your First Steel Plugin

Learn to create a Steel plugin for Helix by building a word counter.

### Before You Start

- Helix with Steel support installed (`~/git/helix/target/release/hx`)
- Steel CLI installed (`steel --version` works)
- Basic familiarity with Lisp/Scheme syntax

### Step 1: Test in Steel REPL

Start the REPL:

```bash
steel
```

You should see:

```
     _____ __            __
    / ___// /____  ___  / /          Version 0.7.0
    \__ \/ __/ _ \/ _ \/ /           https://github.com/mattwparas/steel
   ___/ / /_/  __/  __/ /            :? for help
  /____/\__/\___/\___/_/

λ >
```

Test basic Scheme:

```scheme
λ > (+ 1 2 3)
=> 6

λ > (define (square x) (* x x))
λ > (square 5)
=> 25
```

### Step 2: Learn String Functions

Try splitting a string:

```scheme
λ > (split-whitespace "hello world test")
=> '("hello" "world" "test")

λ > (length (split-whitespace "hello world test"))
=> 3
```

### Step 3: Create Word Count Function

```scheme
λ > (define (count-words text)
      (length (split-whitespace text)))
λ > (count-words "the quick brown fox")
=> 4
```

Exit the REPL with Ctrl+D.

### Step 4: Add to Helix Config

Edit `~/.config/helix/helix.scm`:

```scheme
;; Add to your existing helix.scm

(provide word-count)

;;@doc
;; Count words in current selection and show in status bar
(define (word-count)
  (let* ([text (helix.static.current-highlighted-text!)]
         [count (length (split-whitespace text))])
    (set-status! (string-append "Words: " (number->string count)))))
```

### Step 5: Test in Helix

1. Start Helix: `~/git/helix/target/release/hx somefile.txt`
2. Select some text (visual mode: `v` then move)
3. Type `:word-count`
4. See the count in the status bar

### Step 6: Debug with :evalp

If something doesn't work:

1. Type `:evalp`
2. Enter: `(split-whitespace "test string")`
3. See result in status bar

Or use `:open-debug-window` to see `displayln` output.

---

## How-to Guide: Debug Steel Plugins

### How to See Error Messages

1. Check the helix log:
   ```bash
   tail -f ~/.cache/helix/helix.log
   ```

2. Or run helix with debug logging:
   ```bash
   HELIX_LOG_LEVEL=debug ~/git/helix/target/release/hx 2>&1 | tee helix-debug.log
   ```

### How to Test Expressions Interactively

1. In Helix, type `:evalp`
2. Enter any Steel expression
3. Result appears in status bar
4. For printed output, use `:open-debug-window` first

### How to Reload Config Without Restarting

Currently requires restart. Workaround:

1. `:open-helix-scm`
2. Edit your function
3. Select the entire function definition
4. `:eval-sexpr` (or `Space o` if bound)

### How to Find Available Functions

In Steel REPL, explore modules:

```scheme
(require-builtin steel/process)  ; Load a module
;; Then try functions
```

In Helix, check the steel-docs.md in the helix repo:
```bash
cat ~/git/helix/steel-docs.md
```

---

## Reference: helix.scm vs init.scm

### helix.scm

- **Loaded**: First, before editor context exists
- **Purpose**: Define functions to export as commands
- **Must use**: `(provide function-name)` for each command
- **Context**: No direct editor access; functions receive context when called

```scheme
;; helix.scm pattern
(provide my-command)

;;@doc
;; Documentation shown in command palette
(define (my-command)
  ...)
```

### init.scm

- **Loaded**: After helix.scm, with editor context available
- **Purpose**: Configuration, keybindings, startup logic
- **Can use**: Direct calls to helix APIs, theme setting, etc.

```scheme
;; init.scm pattern
(require (prefix-in helix. "helix/commands.scm"))

;; Set theme on startup
(helix.theme "gruvbox")

;; Define keybindings
(keymap (global)
  (normal (C-r (f ":recentf-open-files"))))
```

---

## Explanation: Why Steel for Helix Plugins?

### Background

Helix needed a plugin system. Options considered:
- **Lua**: Not Rust-native, large dependency
- **WASM**: Runtime larger than the editor itself
- **RPC**: Latency, complexity, security concerns
- **Steel**: Pure Rust Scheme, embeddable, small footprint

Steel won because @mattwparas built both Steel and the Helix integration, proving it worked as a daily driver.

### Scheme's Advantages

1. **Minimal syntax**: Everything is `(function arg1 arg2)`
2. **Homoiconic**: Code is data; macros are natural
3. **Editor heritage**: Emacs proved Lisp works for extensibility
4. **R5RS spec**: Only ~50 pages vs Common Lisp's 1000+

### Steel-Specific Features

- **Racket-style modules**: `require`/`provide` for organization
- **Immutable data structures**: Hash maps, vectors by default
- **Rust FFI**: Can load native dylibs (e.g., terminal emulator)
- **Async support**: Integrates with Tokio runtime

### Two-File Design

The `helix.scm` / `init.scm` split serves a purpose:

- `helix.scm` is a **module**: Stateless function definitions
- `init.scm` is a **script**: Runs with editor context

This prevents accidental editor state access during module loading, making plugins more predictable.

---

## Appendix: Process Communication (pi RPC)

Steel can spawn and communicate with external processes, enabling integration with tools like `pi --mode rpc`.

```scheme
(require-builtin steel/process)
(require "steel/result")

;; Spawn process with piped I/O
(define child 
  (unwrap-ok 
    (spawn-process 
      (with-stdout-piped 
        (with-stdin-piped 
          (command "pi" '("--mode" "rpc" "--no-session")))))))

;; Get handles
(define pi-in (child-stdin child))
(define pi-out (child-stdout child))

;; Send JSON command
(write-line! pi-in "{\"type\": \"get_state\"}")

;; Read JSON response
(read-line-from-port pi-out)
```

This enables:
- Helix plugins that call AI agents
- Steel scripts that automate pi
- Complex editor+AI workflows
