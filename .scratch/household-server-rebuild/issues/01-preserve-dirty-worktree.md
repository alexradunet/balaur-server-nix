# Preserve the current dirty worktree

Status: ready-for-human
Completed: 2026-08-14

## Objective

Make all current staged, unstaged, and deleted work recoverable before any implementation agent edits tracked files.

## Work

- Record `git status --porcelain=v2` and the current revision.
- Preserve all changes in a dedicated WIP branch/commit, or leave this directory untouched and create a clean feature worktree.
- Do not rely only on stash or reflog.
- Record the clean implementation worktree path.

## Acceptance criteria

- Every current change is recoverable from a named commit.
- The implementation worktree is clean.
- No replacement-design work starts in the dirty tree.

## Comments

Completed on `feature/household-server-rebuild`.

- Original revision: `600ce03f692c6e3de1819e3907f789c1b3cbb330`
- Preserved WIP branch: `wip/pre-household-rebuild`
- Preserved WIP commit: `390f328199a8f11cfbdd3f3a41fd7b92e0681b3b`
- Clean feature branch specification commit: `dcff8de6a748f78e20ff2569fb474db831e7fc3a`
- The feature branch matches `main` outside `.scratch/household-server-rebuild`.
