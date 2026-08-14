# Reconcile WIP and remove obsolete implementation

Status: ready-for-human
Blocked by: 01, 17

## Objective

Remove obsolete desktop, dashboard, FastFlowLM, host personal-app, old storage/backup, and stale media code without discarding preserved user work.

## Work

Compare the completed branch with the WIP commit from issue 01. Port only still-relevant user changes deliberately. Remove obsolete imports/files and update README/review documentation and tests to describe the deployed architecture.

## Acceptance criteria

- Every original dirty-tree change is explicitly retained, superseded, or intentionally discarded by the human.
- No dead service, old path, stale port, or old provisioning instruction remains.
- Final flake checks and full host build pass.

## Comments
