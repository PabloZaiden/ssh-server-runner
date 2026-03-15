# Status

## Current phase

All planned implementation and validation tasks are complete.

## Progress tracker

| Task | Description | Status | Complexity | Depends on |
| --- | --- | --- | --- | --- |
| 1 | Review the current bootstrap flow | Completed | Low | - |
| 2 | Design the `gh` detection and installation strategy | Completed | Medium | 1 |
| 3 | Update `ssh-server.sh` | Completed | Medium | 2 |
| 4 | Update documentation | Completed | Low | 3 |
| 5 | Validate the change | Completed | Medium | 3, 4 |

## Notes

- Goal: ensure `gh` CLI is installed only when missing.
- `AGENTS.md` is not present in the repository root or child directories, so execution is following `.planning/plan.md` and the repository's existing script patterns.
- `ssh-server.sh` currently installs apt dependencies first, then bootstraps `fresh`, then installs GitHub Copilot CLI.
- The chosen strategy is to skip `gh` installation when `gh` is already on `PATH`, otherwise try the default apt package first and fall back to configuring the official GitHub CLI apt repository if needed.
- `ssh-server.sh` now checks for `gh` before installing it, attempts a normal apt install first, and only configures the official GitHub CLI apt repository if the default sources do not provide the package.
- `README.md` now documents that the bootstrap process installs GitHub CLI (`gh`) when it is missing.
- Validation results: `bash -n ssh-server.sh` passed and `git diff --check` passed.
- The current workspace environment does not have `gh` installed yet; the updated bootstrap script will install it on first run when needed.

## Next steps

- No further non-manual tasks remain in the accepted plan.
- Optional follow-up: run `ssh-server.sh` in a target devcontainer or host environment to exercise the live installation path end to end.
