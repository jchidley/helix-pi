# Command Reference

## Operating limits

These commands are implemented, not a guarantee of successful operation on an arbitrary Steel/Helix/Pi combination. Installation, editor restart, private session reads and paid prompts/compaction need explicit scope. The key column is an example mapping: it applies only after the Keybindings configuration below is installed.

- Both clients launch `pi --mode rpc` with ambient cwd/config/extensions/credentials; no explicit model/thinking selection is passed. Use the running child's model/status commands, not another Pi process, to inspect/change that session. Do not change defaults during a guidance review.
- `pi-core.scm` does not handle `extension_ui_request` or send `extension_ui_response`. RPC confirmation/input dialogs may wait indefinitely unless their own timeout resolves them. Do not auto-approve or remove safety extensions to work around this gap; use a supported interface for such operations.
- The core marks `agent_end` idle and ignores `agent_settled`, queue and compaction events. Current RPC distinguishes a low-level run ending from final settlement. Do not equate idle with all work stopped. `:pi-abort` does not clear queued messages; steering is queued after the current turn's tool calls, not a kill/undo operation.
- Helix send clears input after a pipe write, before RPC acceptance. Keep valuable prompt text until acceptance is confirmed. New/switch commands can clear/render output before success; new-session cancellation is not handled. A displayed history or switched message is not authoritative child state.
- Session helpers assume POSIX slash paths and HOME, shell out to `ls`, split names on whitespace and do not filter only JSONL files. Listing waits before draining the pipe, so large listings can block. Native Windows paths are not supported by these helpers. Session selection by modification time is not verified to match Pi's selection.
- History rendering scans all message entries in file order, not the active parent-linked branch, and extracts only text-block arrays. A parse/read/content error can discard the entire display. It is not a faithful full-session viewer; keep private session data out of tests and reports.
- Cleanup closes stdin and clears local state, but does not wait for or kill the child or join readers. Buffers survive quit. “stopped (session saved)” is an unverified legacy diagnostic, not proof of exit/persistence. Confirm the exact child state before any separately authorized recovery action; never kill unrelated Pi processes.
- The CLI client blocks while reading responses and cannot accept interactive abort/steer input then. It pipes but does not drain stderr, does not match waits to response IDs, can wait after prompt rejection, and prints some success messages without checking the response. It is not an unattended test driver.
- Outbound framing is raw JSON plus LF and flush. Inbound Steel line-reader behavior still needs actual Unicode/CRLF framing tests. Tool-output rendering assumes cumulative append-only text, omits nontext results and does not use final isError as a success gate.

For RPC details use `docs/rpc.md` from the exact installed `@earendil-works/pi-coding-agent` package. A guessed `~/git/pi-mono` checkout may describe another version. The source comparison used installed 0.85.1 documentation; it did not execute a Pi child or certify compatibility.

## Helix Commands

| Command | Key | Description |
|---------|-----|-------------|
| `:pi-start` | `Alt-p n` | Start new session |
| `:pi-continue` | `Alt-p p` | Resume last session (cache-friendly) |
| `:pi-sessions` | `Alt-p l` | List available sessions |
| `:pi-resume` | `Alt-p r` | Resume session (picker if empty, path from input) |
| `:pi-send` | `Alt-p s` | Send prompt from input buffer |
| `:pi-abort` | `Alt-p a` | Abort current operation |
| `:pi-quit` | `Alt-p q` | Close stdin and clear local process state; buffers remain, exit/persistence unverified |
| `:pi-model` | `Alt-p m` | Cycle to next model |
| `:pi-thinking` | `Alt-p t` | Cycle thinking level |
| `:pi-status` | `Alt-p S` | Show current status |
| `:pi-compact` | `Alt-p C` | Compact conversation context |
| `:pi-new` | `Alt-p N` | Fresh session (keep buffers) |
| `:pi-steer` | `Alt-p i` | Queue steering for delivery after the current turn's tool calls |
| `:pi-follow` | `Alt-p f` | Queue follow-up message |
| `:pi-recover` | `Alt-p R` | Force reset state |

## Installation

Only for an explicitly approved live-config change; preserve existing imports/exports and plugin bytes. The ellipsis in the example is a placeholder, not literal Scheme to paste.

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
