# Monitoring operations

`modules/monitoring.nix` is the single monitoring policy for Balaur. It intentionally does not add Prometheus, Grafana, NUT, or a local mail provider.

## Scheduled behavior

- `balaur-snapshot-daily.timer` and `balaur-snapshot-weekly.timer` take non-recursive snapshots of exactly `balaur.storage.protectedLeafDatasets`. They retain 7 daily and 4 weekly snapshots. Pruning only accepts exact dataset names and the `balaur-monitoring-{daily,weekly}-<UTC timestamp>` namespace.
- `zfs-scrub.timer` scrubs only `tank` monthly and waits for completion. `balaur-md-check.timer` starts the `/dev/md/root` consistency check on a separate, staggered monthly date; its command waits for `sync_action=idle`, fails after 24 hours, and alerts on any nonzero `mismatch_cnt`.
- `smartd.service` monitors autodetected SMART/NVMe devices without direct mail or desktop notifications.
- `balaur-monitoring-check.timer` classifies storage degradation, ZFS scrub errors/cancellation, md mismatch results, a full pool, exact 180000000000-byte owner warnings, required-unit failures, new kernel OOM events, nonzero swap, configured backup staleness and 85% capacity warnings, smartd/SMART health evidence, and thermal critical/throttling evidence.

Inspect schedules with:

```console
systemctl list-timers 'balaur-*' zfs-scrub.timer
```

No physical scrub or SMART run has been validated by issue 13. Those checks remain part of physical-host validation.

## Local alert interface

`balaur-monitor` is the one executable interface. Production uses `balaur-monitor check`; tests may pass the documented normalized JSON with `check --input /absolute/root-owned/file.json`. The same executable handles `snapshot`, `md-scrub`, md events, `deliver`, and `monthly-test`. The shared mdadm configuration calls a tiny `/bin/sh` bridge copied into the initrd and deployed system: early events queue under `/run` for replay after switch-root, while stage-2 events dispatch directly without requiring Python in the initrd.

Durable root-only state is under `/var/lib/balaur-monitoring`:

- `alerts/`: append-only local JSON alert records;
- `active/`: deduplication markers for currently active findings;
- `outbox/`: atomically queued RFC822 messages not yet delivered;
- `sent/`: messages archived only after adapter success;
- `tmp/`: incomplete atomic writes, isolated from the consumed queues so an interrupted write cannot wedge checks or delivery.

Useful local checks:

```console
systemctl status balaur-monitoring-check.service balaur-monitoring-delivery.service
journalctl -u balaur-monitoring-check.service -u balaur-monitoring-delivery.service
find /var/lib/balaur-monitoring/alerts -type f -maxdepth 1
find /var/lib/balaur-monitoring/outbox -type f -maxdepth 1
```

A failed external adapter leaves the message in `outbox/`, exits nonzero, and is visible in the delivery unit and journal. Delivery failures do not recursively generate more email alerts. Local health records work when email is disabled. If a collector fails, its previous related incidents remain active as unknown rather than being falsely resolved; a separate collection-failure alert records the visibility gap.

## Remaining human gates

Production deliberately evaluates with blocker warnings and these readiness fields unset:

1. **Email:** choose and configure an external sendmail-compatible adapter, sender, and recipient. Keep provider credentials outside Nix and point `balaur.monitoring.readiness.email.adapter` at the root-owned runtime executable. Only then set all email fields and `ready = true`. This also enables delivery and the monthly end-to-end timer.
2. **Backup freshness/capacity:** issue 14 must provide one root-owned success stamp and one root-owned integer capacity-percentage file per Owner, plus an approved `maxAgeSeconds`. The confirmed capacity threshold is fixed at 85%. Set the complete `readiness.backup` group together; partial configuration is rejected.
3. **Numeric thermal limits:** identify canonical sensor files and establish a measured safe `criticalMilliCelsius` for the physical host. Set the complete `readiness.thermal` group together. Journal evidence of critical conditions and throttling remains active before this gate.

Issue 13 did not invent or validate SMTP settings, backup age policy/status paths, sensor paths, or thermal limits. The VM values are disposable fixtures only. Physical mail delivery, thermal behavior, backup freshness/capacity, ZFS/md scrub, and SMART/NVMe behavior remain unvalidated until the corresponding human/physical gates are completed.
