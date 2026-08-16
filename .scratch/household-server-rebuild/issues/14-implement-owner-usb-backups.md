# Implement owner-specific plug-triggered Borg backups

Status: needs-info
Blocked by: 02, 07, 12, 13

## Objective

Create two device-bound encrypted backup workflows that cannot target the wrong USB or leak cross-owner state.

## Work

- Parameterize by owner, exact UUID, exact label, source manifest, and credentials.
- Trigger on matching device insertion, not a blind calendar mount attempt.
- Quiesce only the owner's container, capture consistent snapshots/dumps, and promptly restart it.
- Capture Home Assistant consistently on both devices.
- Keep 4 weekly/6 monthly archives, verify before success, warn at 85%, always clean snapshots/unmount, and email safe-removal status.
- Add freshness alerts and quarterly restore instructions.

## Acceptance criteria

VM tests cover wrong UUID/label, existing mount, Borg/verify failure, owner restart after failure, cleanup/unmount on every path, approved-source isolation, and no plaintext global/other-owner secrets.

## Needs information

Observed identities for both new USB devices and the SMTP relay/alert destination from issue 02.

## Comments

- 2026-08-16: The Owner explicitly deferred this ticket because the two planned nominal 256 GB owner USB devices have not been purchased. Keep `Status: needs-info`; do not invent device identities, implement an operational workflow against placeholders, provision the attached preserved SanDisk `BALAUR_BACKUP`, or weaken the rebuild's recovery gates. Resume with a read-only inventory after both new devices exist.
