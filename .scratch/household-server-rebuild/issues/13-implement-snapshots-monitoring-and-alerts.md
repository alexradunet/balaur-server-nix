# Implement snapshots, scrubs, monitoring, and email alerts

Status: ready-for-agent
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
