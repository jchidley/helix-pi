# Decisions

## Gate 2 Findings

| Finding | Count |
|---------|-------|
| God functions | 4 (spawn×2, handle-event, display-history) |
| Orphans/dead code | 3 (list-sessions, pi-rpc-get-state, *pi-is-streaming*) |
| DRY violations | 2 significant (spawn dup, session iteration) |
| Circular deps | 0 |

**Verdict**: Issues found. Proceed with refactoring.

## Scope Lock

This pass will:
1. Remove dead code (list-sessions, pi-rpc-get-state, *pi-is-streaming*)
2. Merge pi-spawn-process and pi-spawn-process-with-history into one function
3. Extract session message iterator to reduce duplication
4. Reuse get-text-parts consistently

## Pending User Decisions

### YAGNI Removal
- [ ] Remove `list-sessions`? (cross-project browser - not currently needed)
- [ ] Remove `pi-rpc-get-state`? (could be used for status)
- [ ] Remove `*pi-is-streaming*`? (could guard against double-send)

### Bug Found During Analysis
None - code appears functionally correct, just has dead code and duplication.
