# Balaur remediation roadmap

This is the remaining work identified during the NixOS architecture review. Items
are ordered by risk and operational value.

## P0 — resolve before treating the host as a hardened server

### 1. Replace unrestricted passwordless sudo

`alex` currently has `NOPASSWD: ALL` in `modules/access.nix`. This means any
compromise of an authenticated `alex` session is a root compromise.

- Decide whether `alex` should have a password or whether only a small set of
  deployment/recovery commands should be permitted.
- Ensure an out-of-band recovery path exists before removing passwordless sudo.
- Re-test SSH access and deployment after changing the policy.

### 2. Complete and verify disaster recovery

The Borg job now includes `/home/alex`, `/srv/app-data`, `/srv/personal`,
`/var/lib/hass`, and `/srv/secrets`, while excluding the re-downloadable
FastFlowLM model cache.

- Run a successful backup with the expanded scope.
- Verify the USB is unmounted afterward.
- Test restoring representative files from Borg.
- Restore at least one application state/database in a disposable location.
- Use Home Assistant's native backup for its live application state.
- Store the Borg passphrase and repository key independently of the server and
  USB drive.
- Add monitoring or notification for a missing USB or failed/stale backup.
- Document recovery point and recovery time objectives.

### 3. Reboot and validate the deployed kernel/NPU stack

The deployed system uses a newer kernel than the currently running kernel.
After scheduling a maintenance window:

```sh
sudo reboot
uname -r
sudo -u fastflowlm flm validate
systemctl --failed
systemctl status fastflowlm
```

Confirm both EFI boot paths remain usable and that FastFlowLM still reports
`ready: true`.

## P1 — improve security and observability

### 4. Decide authentication for LAN services

The Herdr web terminal and noVNC gateway have been removed. Herdr is accessed
as a CLI over SSH, while native VNC access is tunnelled over SSH. The following
services still rely on the trusted-LAN boundary:

- FastFlowLM has no API authentication.
- The dashboard is HTTP-only and unauthenticated.
- Several application UIs are reachable directly on LAN ports.

Decide whether the intended model is trusted-LAN-only or authenticated remote
access. If stronger isolation is required, add HTTPS and authentication through
Caddy or a VPN, and keep direct service ports closed.

### 5. Add independent alerting

RAID monitoring and SMART monitoring are enabled, but local logs are not enough
if the host or disks fail.

Add independent alerts for:

- degraded RAID arrays
- SMART/NVMe errors
- failed services
- failed or stale backups
- `/`, `/boot`, and `/srv` capacity/inode exhaustion
- failed NixOS upgrades

### 6. Harden remaining custom systemd services

Review the current systemd security posture and add restrictions where
compatible:

```sh
systemd-analyze security qbt-webui-proxy.service
systemd-analyze security balaur-backup.service
systemd-analyze security arr-qbittorrent-sync.service
```

Pay particular attention to `CapabilityBoundingSet`, `NoNewPrivileges`,
`ProtectSystem`, `PrivateDevices`, `ProtectHome`, resource limits, and explicit
read/write paths.

### 7. Add runtime/integration tests

Current checks primarily evaluate configuration and run the dashboard in
isolation. Add NixOS VM or host-level tests for:

- interface-scoped firewall rules
- absence of Herdr/noVNC web listeners and loopback-only raw VNC access
- missing storage mount behavior
- qBittorrent VPN and proxy readiness
- backup mount/unmount cleanup
- service startup ordering
- representative restore procedures

## P2 — maintenance and architecture improvements

### 8. Clean stale application state

Inspect stale directories under `/srv/app-data` for disabled services such as
Lidarr, Readarr, Seerr, Whisparr, and FlexGet. Preserve anything still needed,
then remove obsolete state deliberately and document the cleanup.

### 9. Reconsider the kernel policy

`linuxPackages_latest` is currently used for AMD XDNA/NPU support. Once the NPU
requirement is understood, pin and test a specific kernel package/version rather
than following the moving latest-kernel alias.

### 10. Review persistent service identities

Several service UIDs/GIDs are dynamic while application data is persistent.
Document the migration rationale for pinned IDs and decide whether all services
with persistent state should use stable identities.

### 11. Improve secret management

Secrets are correctly kept out of the Nix store, but are manually provisioned
under `/srv/secrets`. Evaluate agenix or sops-nix for encrypted-at-rest
provisioning, rotation, replacement-host recovery, and controlled ownership.

### 12. Evaluate storage encryption

The server's NVMe data is currently unencrypted at rest. Decide whether the
physical-theft threat model requires LUKS or another encryption design, taking
RAID boot/recovery and unattended reboot requirements into account.

### 13. Add CI and update discipline

Automate:

- formatting
- `nix flake check`
- configuration evaluation/builds
- VM tests
- reviewed flake input updates

Keep `flake.lock` changes reviewed and committed together with configuration
changes.

## Completed review actions

- Herdr web terminal and noVNC gateway removed.
- SSH and native VNC tunnel instructions documented.
- FastFlowLM now requires `/srv/app-data`.
- Syncthing global discovery, relays, and NAT traversal disabled.
- Firewall and SSH access scoped to trusted LAN interfaces.
- Nix garbage collection and store optimisation enabled.
- zram emergency swap enabled.
- SMART monitoring enabled for both NVMe drives.
- Borg backup coverage expanded.
