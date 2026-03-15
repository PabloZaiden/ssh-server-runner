# Plan: Add `gh` CLI installation when missing

## Problem

The repository's `ssh-server.sh` bootstraps system packages and installs GitHub Copilot CLI, but it does not currently ensure that the GitHub CLI (`gh`) is installed. The goal is to update the project so `gh` is installed only when missing, while preserving the script's existing idempotent behavior.

## Objectives

1. Ensure `ssh-server.sh` installs `gh` only if it is not already available.
2. Keep the installation flow safe to rerun without reinstalling tools unnecessarily.
3. Fit the `gh` installation into the script's existing privilege and package-management patterns.
4. Update any directly affected documentation so the bootstrap behavior remains accurate.
5. Validate that the planned change does not break the current setup flow.

## Proposed approach

Use the current bootstrap script as the integration point. Reuse the existing root-escalation helpers and package-install conventions where possible. Add an explicit detection step for `gh`, then install it only when absent. Prefer an approach that works cleanly in the current Debian/Ubuntu-style environment implied by the script's `apt-get` usage. After the script logic is adjusted, update repository documentation to reflect the new behavior and verify the flow with the repository's existing validation options.

## Tasks

### 1. Review the current bootstrap flow

- Confirm how `ssh-server.sh` currently installs apt dependencies and GitHub Copilot CLI.
- Identify the most appropriate insertion point for `gh` detection and installation.
- Check whether any documentation already describes installed tools and needs to be updated.

**Deliverable:** Clear map of where the `gh` logic and related documentation updates belong.

**Estimated complexity:** Low

### 2. Design the `gh` detection and installation strategy

- Decide how to detect an existing `gh` installation, likely by checking whether the command is already available.
- Decide whether `gh` should be installed through existing package management flow or a dedicated install block.
- Account for the fact that GitHub CLI may require repository setup or package-source configuration, depending on the base image.
- Ensure the strategy remains idempotent and does not reinstall `gh` if already present.

**Deliverable:** Final installation strategy compatible with the script's existing Debian/Ubuntu-oriented setup.

**Estimated complexity:** Medium

### 3. Update `ssh-server.sh`

- Add logic to skip installation when `gh` is already installed.
- Add installation steps for `gh` when it is missing.
- Reuse existing helper functions (`as_root`, `as_root_bash`) and existing error-handling style.
- Keep the change narrow so unrelated bootstrap behavior remains untouched.

**Deliverable:** Script changes that install `gh` only when needed.

**Estimated complexity:** Medium

### 4. Update documentation

- Revise `README.md` wherever it describes which tools are bootstrapped.
- Make sure the README wording matches the final script behavior around `gh` and GitHub Copilot CLI.
- Avoid adding unrelated documentation changes.

**Deliverable:** Documentation that accurately reflects the new bootstrap behavior.

**Estimated complexity:** Low

### 5. Validate the change

- Run the repository's available checks or, if no formal test suite exists, run focused verification steps already supported by the repo.
- Confirm the script remains syntactically valid.
- Verify the plan covers both key paths:
  - `gh` already installed -> script skips installation.
  - `gh` missing -> script installs it successfully.
- Confirm documentation changes are consistent with the implementation.

**Deliverable:** Confidence that the change works and preserves existing behavior.

**Estimated complexity:** Medium

## Task dependencies

- Task 2 depends on Task 1.
- Task 3 depends on Task 2.
- Task 4 depends on Task 3.
- Task 5 depends on Tasks 3 and 4.

## Notes and considerations

- The script currently assumes an `apt-get`-based environment, so the `gh` installation plan should align with that assumption unless implementation reveals a safer existing pattern.
- The current script already uses network bootstrap installers for other tooling, so the final implementation should weigh consistency against reliability and package-manager integration.
- Idempotency matters: the desired outcome is "install if missing," not "reinstall every run."
- Validation should avoid introducing new tooling that the repository does not already use.
