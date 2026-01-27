# Phase 7: YAGNI Scan

## Dead Code

| Symbol | Line | Evidence | Verdict |
|--------|------|----------|---------|
| `list-sessions` | 323-338 | Zero callers in codebase | **REMOVE** |
| `pi-rpc-get-state` | 123 | Zero callers in codebase | **REMOVE** |
| `*pi-is-streaming*` | 47 | Written by pi-handle-event, pi-quit. Never read. | **REMOVE** (or document future use) |

## Verification

```bash
# Confirm no callers
grep -n "list-sessions[^-]" src/pi.scm    # Only definition
grep -n "pi-rpc-get-state" src/pi.scm     # Only definition
grep -rn "\*pi-is-streaming\*" src/pi.scm # Only writes, no reads
```

## Unused But Potentially Useful

| Symbol | Notes |
|--------|-------|
| `list-sessions` | Was for cross-project session browser. Could be useful feature. |
| `pi-rpc-get-state` | pi RPC supports this. Could be used for status display. |
| `*pi-is-streaming*` | Could guard against sending prompts while streaming. |

## Recommendation

Ask user: Remove all three, or keep any for future use?

If keeping for future:
- Add comment `;;; RESERVED: future use for <purpose>`
- Or remove now, git history preserves them

## Lines Saved

| Symbol | LOC |
|--------|-----|
| list-sessions | 16 |
| pi-rpc-get-state | 2 |
| *pi-is-streaming* | 1 + 3 writes |
| **Total** | ~22 |
