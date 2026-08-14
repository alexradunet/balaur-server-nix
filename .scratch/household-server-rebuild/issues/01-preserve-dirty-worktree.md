# Preserve the current dirty worktree

Status: ready-for-human

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
