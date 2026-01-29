# Command Reference

## Helix Commands

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

## Keybindings

Add to `~/.config/helix/init.scm`:

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
