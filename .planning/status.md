# Status

## Current phase

Planning complete. Implementation has not started.

## Progress tracker

| Task | Description | Status | Complexity | Depends on |
| --- | --- | --- | --- | --- |
| 1 | Review the current bootstrap flow | Planned | Low | - |
| 2 | Design the `gh` detection and installation strategy | Planned | Medium | 1 |
| 3 | Update `ssh-server.sh` | Planned | Medium | 2 |
| 4 | Update documentation | Planned | Low | 3 |
| 5 | Validate the change | Planned | Medium | 3, 4 |

## Notes

- Goal: ensure `gh` CLI is installed only when missing.
- No code changes have been made yet.
- Next step, when approved, is to implement the plan starting with the bootstrap-flow review already captured in `plan.md`.
