# Onboard services, banks, clients, and backups

Status: ready-for-human
Blocked by: 10, 12, 13, 14, 16

## Objective

Complete fresh human onboarding and validate the full household workflow.

## Work

- Install the Caddy CA on clients and test LAN/WireGuard DNS/TLS.
- Create separate app and Jellyfin profiles.
- Onboard fresh Home Assistant.
- Pilot Revolut, then BCR, then BT for each owner; reconcile initial imports before daily timers and set 80-day reminders.
- Run the llama benchmark and select only a passing model.
- Provision each USB, complete/verify/unmount a backup, and restore representative owner files, Trilium, Paperless, Firefly, and Home Assistant state to temporary locations.
- Confirm qBittorrent fails closed and cross-owner SMB/container tests pass.

## Acceptance criteria

- No public port forwarding exists.
- Both owner workflows work without cross-access.
- Both backup restore drills succeed and are dated.
- Bank beta limitations and model benchmark result are documented.

## Comments
