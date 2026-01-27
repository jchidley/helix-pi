# Spec: sessions

## Observable Behaviours

### get-home-dir [side-effects: process spawn, caches]
- Returns home directory path (e.g., "/home/jack")
- Spawns `printenv HOME` once, caches in *home-dir*
- Subsequent calls return cached value

### pi-sessions-dir [pure after first get-home-dir]
- Returns `"<home>/.pi/agent/sessions"`

### path-to-session-dir-name [pure]
- **Input**: path like "/home/jack/git/helix-pi"
- **Output**: "--home-jack-git-helix-pi--"
- Replaces `/` with `-`, wraps with `--`

### session-dir-to-display-name [pure]
- **Input**: dir name like "--home-jack-git-helix-pi--"
- **Output**: "~/git-helix-pi" (or "~" for home, or raw name if no match)
- Inverse of path-to-session-dir-name but with ~ substitution

### get-latest-session-file [side-effects: file I/O]
- **Input**: session directory path
- **Output**: newest .jsonl file path, or #f if none
- Sorts by filename (ISO timestamp = chronological)

### get-cwd-latest-session [side-effects: file I/O]
- Combines current-directory + path-to-session-dir-name + get-latest-session-file
- Returns newest session file for current working directory, or #f

### list-sessions-for-cwd [side-effects: file I/O]
- Returns list of `(first-user-message . file-path)` pairs
- Sorted newest first
- Calls get-first-user-message for each file

### list-sessions [DEAD CODE]
- Returns all sessions across all directories
- **Never called** - candidate for removal

### get-first-user-message [side-effects: file I/O]
- **Input**: session file path
- **Output**: first user message text (truncated to 50 chars), or "(empty)"/"(no text)"
- Parses JSONL, finds first message with role=user

### get-text-parts [pure]
- **Input**: content list (from message)
- **Output**: list of text strings (filters for type="text")

### display-session-history [side-effects: file I/O, UI]
- **Input**: session file path
- Parses entire JSONL file
- For each message with text content: appends "## You/Assistant\n\n" + text
- Skips messages without text (tool calls, thinking)

### *pi-session-map* [state]
- Temporary storage for picker callback
- Maps display-name → file-path

## DRY Issues

1. **Session file parsing** duplicated in:
   - `get-first-user-message` (finds first user message)
   - `display-session-history` (iterates all messages)
   
   Both do: call-with-input-file, loop read-line, string->jsexpr, check type="message", extract role/content

2. **Text extraction** pattern repeated:
   - `get-first-user-message`: extracts first text from first content part
   - `display-session-history`: uses get-text-parts helper
   - `pi-handle-event` (message_end): inline extraction
