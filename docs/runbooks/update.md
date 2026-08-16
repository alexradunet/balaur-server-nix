# Deliberate update and migration runbook (draft)

> **Not currently executable:** Balaur has not passed issue 16, production secrets are absent, and owner USB recovery is deferred. Use this procedure only after initial provisioning and recovery gates are complete.

NixOS updates are deliberate. Nothing automatically deploys a new lock file or host generation. A NixOS rollback restores code and configuration, not an application database that newer code has migrated.

## Ordinary host update

Work on a reviewed branch and record the old and proposed revisions:

```console
git status --short
git rev-parse HEAD
git diff -- flake.lock
nix flake metadata path:$PWD
```

Abort on unrelated work, an unexplained input change, or an unavailable prior generation. Review upstream release and migration notes for every stateful package changed by the lock. The active configuration has no separate migration gate for Home Assistant or other host databases; schema-changing host updates therefore require a reviewed application-consistent recovery point and working recovery media. While issue 14 is deferred, do not activate a host update that can irreversibly migrate protected state.

Before building or switching, require healthy storage, free capacity, no unexplained failed units, and a tested administrative path:

```console
sudo mdadm --detail --test /dev/md/root
sudo zpool status -x tank
sudo zfs get -H -p -o name,property,value available tank
df -B1 / /nix/store
systemctl --failed
```

From a separately authorized client—not from Balaur itself—open and retain a second SSH session before activation:

```console
ssh alex@192.168.50.2
```

Verify interactive password-authenticated `sudo` there without closing the existing administrative session. Abort on degraded md/ZFS, zero or unexpectedly low available space, a failed required unit, failed independent SSH/sudo, or missing recovery material. For a stateful migration, stop here unless its reviewed cold snapshot/native backup and matching old closure have both been verified.

Validate without activation:

```console
nix flake check -L path:$PWD
nix build --no-link path:$PWD#nixosConfigurations.balaur.config.system.build.toplevel
sudo nixos-rebuild dry-activate --flake path:$PWD#balaur
```

Read the dry-activation unit changes. Abort if it would unexpectedly stop storage, networking, SSH, Caddy/CoreDNS, an owner container, or another stateful service. Personal containers use `restartIfChanged = false`; a host switch must not be treated as approval to migrate them.

After review, activate deliberately from an already authenticated session:

```console
sudo nixos-rebuild switch --flake path:$PWD#balaur
```

Keep that session open while checking a second SSH session and password-authenticated `sudo`. Then inspect:

```console
cat /proc/mdstat
sudo zpool status tank
systemctl --failed
systemctl status sshd caddy coredns home-assistant jellyfin
balaur-monitor check
journalctl -b -p warning..alert --no-pager
```

Also run the DNS/TLS checks in `docs/network-access.md` and inspect the alerts/timers in `docs/monitoring.md`. Retain the previous NixOS generation until service checks and any migrations pass. Automatic garbage collection removes store paths older than 30 days, so long-lived rollback cannot be assumed.

## Personal application migration: one owner at a time

The approved package versions are defined in `modules/personal-containers.nix`. Each owner also has a protected marker at:

```text
/srv/people/<owner>/apps/approved-versions
```

The host and container refuse startup unless that marker exactly matches the reviewed package record. Changing the Nix source and changing the marker are two parts of one human approval; neither is an automated updater.

Trilium, Paperless, Firefly III, and Open WebUI can mutate their database/schema during startup. Importer refreshes caches. For each owner independently:

1. Review package and migration notes, build the proposed closure, and notify that owner.
2. Confirm the other owner's container is healthy and will not be touched.
3. Record the old NixOS generation, exact five-line version marker, and current ZFS snapshot list.
4. Stop only `container@<owner>-personal.service` and verify it is inactive.
5. Take one cold, non-recursive, same-timestamp snapshot of exactly that owner's `home` and `apps` datasets; verify both snapshots exist before changing the marker.
6. Replace the marker with the exact five reviewed `name=version` lines from the proposed source. It is non-secret owner state; do not edit any credential while doing this.
7. Start only that owner's container. Watch setup/runtime units and application logs for migrations.
8. Test owner sign-in, Trilium content, Paperless consume/search, Firefly and Importer access, and Open WebUI durable state.
9. Keep the pre-migration snapshot and old closure until rollback has been rehearsed against a temporary restore.

Useful observation/control interfaces are:

```console
owner=alex  # or andreea; inspect this value before every command
case "$owner" in alex|andreea) ;; *) echo 'invalid owner' >&2; exit 1 ;; esac
systemctl status "container@$owner-personal.service"
sudo systemctl stop "container@$owner-personal.service"
sudo zfs list -H -t snapshot -o name -s creation \
  "tank/users/$owner/home" "tank/users/$owner/apps"
sudo systemctl start "container@$owner-personal.service"
journalctl -u "container@$owner-personal.service" --since today
```

Do not copy a marker or database between owners. Do not snapshot recursively: disposable Open WebUI caches/model paths are deliberately nested and excluded. Do not rely on the daily live snapshots as application-consistent pre-migration snapshots.

This repository does not yet provide an automated cold-snapshot/migration command or a tested data rollback command. If stop, snapshot, marker replacement, startup, or health checking fails, restart the same owner's previously approved container when safe, leave the other owner untouched, preserve all evidence, and stop for recovery review. **Never start old application code against a database already migrated by newer code.** Rollback requires both the old closure and matching pre-migration data.

## Shared-service and llama changes

- Jellyfin state is disposable; do not restore old Jellyfin metadata.
- Home Assistant state is protected but currently has no package-version marker. Review its migration notes and require application-consistent recovery before a schema-changing update.
- qBittorrent, Samba, and personal services must remain fail-closed if their runtime credentials are absent.
- Keep llama readiness false until `docs/llama-rocm.md` records a passing physical benchmark, approved local preset, separate owner keys, and measured `MemoryHigh`. Updating the llama package does not authorize a model download or production enablement.

## Failed update

Before choosing a rollback, collect the failed unit status and logs and determine whether any database migration ran. A generation rollback may be appropriate only when state is still compatible. If state changed, do not guess: stop the affected service, retain the failed and prior closures, retain the pre-migration snapshot, and follow the reviewed recovery decision. Never destroy the newest snapshot or run a ZFS rollback merely to make an old unit start.
