# Implement snapshots, scrubs, monitoring, and email alerts

Status: ready-for-human
Blocked by: 02, 06, 09, 12

## Objective

Detect degradation and retain short local recovery history without adding a monitoring platform.

## Work

- Keep 7 daily/4 weekly snapshots for protected owner/application state.
- Exclude disposable child datasets by construction.
- Schedule/monitor ZFS and md scrubs and SMART/NVMe health.
- Alert on owner 180 GB warnings, full pool, stale backups, required-unit failures, OOM/swap pressure, and thermal limits.
- Provide one lightweight email interface and monthly end-to-end test.

## Acceptance criteria

- Snapshot tests show disposable data is never included.
- Degraded/storage/full-pool test conditions produce the alert interface.
- Alert failures are visible locally.
- No Prometheus/Grafana or UPS service is added.

## Comments

- 2026-08-15: Implemented one deep `modules/monitoring.nix` and imported it for Balaur. It owns atomic exact non-recursive protected-leaf snapshots (7 daily/4 weekly), tank scrub and completion-aware md check schedules/results, SMART/NVMe and smartd-warning policy, normalized real/synthetic health classification that preserves incidents across collection gaps, root-only durable local alerts, initrd-safe md `PROGRAM` events, and a provider-neutral atomic sendmail outbox. SMART policy moved out of `modules/base.nix`; `MAILADDR root` was removed.
- Behavioral coverage is registered as `monitoring-vm`: disposable ZFS datasets prove descendant exclusion, multi-leaf atomic naming, exact retention, and foreign-snapshot preservation; normalized input covers degradation, scrub results, backup freshness/85% capacity, SMART, OOM/swap, thermal, collection failures, and deduplication; separate fixtures prove local-only alerts, real-command collection, successful monthly fake-sendmail delivery, retained failed delivery, and systemd/journal visibility. The synthetic SMTP/backup/thermal values exist only in the disposable VM.
- Human gates remain explicit, so this ticket is `ready-for-human`: production email/monthly delivery needs a real external adapter and addresses; issue 14 must define both Owner backup success/capacity status paths and maximum age; and physical sensor paths/measured thermal limits must be approved. No production SMTP, backup-age, USB, or thermal values were invented. Physical mail, thermal, backup freshness/capacity, ZFS/md scrub, and SMART/NVMe behavior have not been validated.
- Verification passed on 2026-08-15: focused monitoring evaluation and VM checks, pinned nixfmt, shellcheck, Python executable startup, direct inspection proving `/etc/balaur-md-event` and its `/bin/sh` closure are present in the evaluated systemd initrd, `git diff --check`, `nix flake check -L path:$PWD` (including the disposable disko and monitoring VMs), and a full Balaur toplevel build. No target deployment or physical command was run.
