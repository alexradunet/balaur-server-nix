# Household Server Rebuild

Status: confirmed

## Goal

Rebuild Balaur from scratch as one bare-metal NixOS household server for Alex and Andreea. Shared infrastructure remains efficient, while personal files and applications are isolated, quota-limited, and backed up independently. Every persistent internal filesystem must tolerate either NVMe failing; external backups cover deletion, corruption, theft, and host loss.

The Owner confirmed this design after a completed grilling session. Do not expand the design with optional infrastructure unless a ticket records a concrete need.

## Confirmed decisions

### Platform and disks

- Bare-metal, headless NixOS; no Proxmox and no desktop/VNC.
- Two nominal 1 TB NVMe drives.
- Each drive contains:
  - 1 GiB EFI partition;
  - 128 GiB Linux RAID member for the OS;
  - the remaining roughly 800 GiB as a ZFS mirror member;
  - a small unused tail so a slightly smaller nominal replacement drive can be used.
- `/` is ext4 on md RAID1.
- GRUB is installed independently on both EFI filesystems; EFI itself is not RAID.
- Persistent data uses a two-device ZFS mirror named `tank`.
- Pin Linux 6.18 LTS: the pinned OpenZFS 2.4.3 supports it, and it provides the needed Radeon 890M/ROCm support.
- Internal drives are not encrypted.
- Existing internal service and media data will not be migrated or restored. Existing external backups must remain untouched.

### ZFS data policy

Use quota-controlled owner trees:

```text
tank/users/alex/home
tank/users/alex/apps
tank/users/andreea/home
tank/users/andreea/apps
```

- Each owner's parent tree has a byte-exact 220 GB decimal maximum covering home and private application state.
- Warn at 180 GB decimal.
- Quotas are maxima, not reservations; unused capacity remains shared.
- Export only `/home/alex/files` and `/home/andreea/files` as private SMB shares, not complete home directories.
- Use separate datasets for shared protected state and explicitly disposable media, downloads, models, caches, and temporary files.
- ZFS ARC is capped near 8 GiB.
- Keep 7 daily and 4 weekly local snapshots for protected user/application state.
- Never snapshot or USB-back up media, downloads, LLM models, caches, or temporary state.

### Identity and trust

- Alex is the host administrator and may use SSH keys.
- Andreea is a normal local/SMB user with no sudo and no SSH access initially.
- Separation protects against accidental cross-access, not against the host administrator.
- Use separate application credentials; do not add SSO initially.

### Personal application stacks

Run one lightweight declarative NixOS container per owner. Each contains its own:

- Trilium;
- Paperless-ngx with one OCR worker and private browser/SMB consume path;
- Firefly III and Data Importer;
- Open WebUI;
- databases, credentials, network identity, and persistent state.

Containers share the host kernel but may not mount or read the other owner's files, state, databases, or secrets. Apply equal CPU weighting and memory-pressure controls. Native host singleton instances of these applications must not remain.

### Shared services

Run on the host where hardware/network integration is useful:

- Home Assistant, starting fresh;
- one llama.cpp ROCm backend;
- Jellyfin with separate profiles;
- qBittorrent administered by Alex and confined fail-closed through ProtonVPN;
- Caddy;
- local `home.arpa` DNS;
- Samba;
- storage, backup, health, and email alert services.

Shared media is mirrored but replaceable and excluded from USB backups. Incomplete downloads are disposable. Do not add Sonarr/Radarr, a dashboard, VLAN infrastructure, or a shared document area until a concrete need exists.

### llama.cpp

- Build for Radeon 890M `gfx1150` against ROCm 7.2.3.
- Enable integrated/unified-memory operation.
- Use llama.cpp built-in router mode for true lazy loading.
- One slot, 32K context, F16 KV cache, full tested GPU offload, and unload after 30 idle minutes.
- Keep the raw backend off the LAN; issue separate Alex and Andreea proxy/API credentials.
- Disable prompt-body logging.
- Prioritize Jellyfin usability if GPU contention occurs.
- Benchmark before selecting production:
  1. Qwen3-30B-A3B-Instruct-2507 Q5_K_M;
  2. Mistral Small 3.2 24B Q6_K;
  3. Qwen2.5-Coder 32B Q5_K_M;
  4. gpt-oss-20b MXFP4.
- Do not use Qwen3.6 initially because of unresolved recurrent-cache/correctness problems on this workload.

### Banking

Each owner gets an isolated Firefly III/Data Importer stack and a separate Enable Banking application/key.

- Pilot Revolut first.
- Pilot BCR next and BT last; both connectors are beta.
- Correctly forward the client IP required by BT.
- Import initial history immediately after authorization.
- Schedule daily imports only after validation.
- Remind each owner to reauthorize every 80 days.
- Do not enable payment initiation.
- An optional household budgeting instance is out of scope until requested.

### Networking

- Keep the server at the router-reserved `192.168.50.2`, subject to installation-time verification.
- The ASUS RT-AX82U provides remote WireGuard access.
- Expose nothing directly to the public internet and configure no WAN port forwards.
- Use private `home.arpa` names behind Caddy's internal CA. Install the CA on regular clients; allow HTTP only for incompatible clients and only over the trusted LAN/WireGuard path.
- Run local DNS because the router lacks flexible custom records. WireGuard and LAN clients must use it for `home.arpa`.
- The router does not provide suitable configurable VLANs; do not simulate VLAN isolation on the host.
- Intended names include owner-specific notes, paperless, budget, and chat names plus shared Home Assistant, Jellyfin, and downloads names.

### Backups and recovery

Use two nominal 256 GB USB devices, one per owner.

- Each USB has a distinct expected filesystem UUID and label; both must match before writing.
- Plugging in a device triggers only its owner's Borg job.
- Repositories use separate encryption credentials.
- Stop only the owner's container long enough to take consistent snapshots/dumps; always restart it on success or failure.
- Include the owner's home, personal application state, banking state, encrypted host configuration, and approved shared state.
- Include new Home Assistant state on both devices.
- Do not put plaintext global recovery secrets or the other owner's banking state on a personal USB.
- Keep 4 weekly and 6 monthly Borg archives; warn at 85% USB use.
- Verify, unmount, and email whether removal is safe.
- Test representative restores quarterly.
- Keep the host age key, global recovery secrets, and both Borg recovery materials in a separate offline administrator recovery package.
- Manage repository secrets with sops-nix and age; commit no plaintext secrets.

### Operations

- Use external email alerts, including a monthly end-to-end test.
- Monitor md and ZFS degradation/scrubs, SMART/NVMe health, owner quota warnings, full pool, backup freshness/capacity, required-unit failures, OOM/swap pressure, and thermal throttling.
- Check updates automatically if useful, but deploy deliberately after tests. Do not allow unreviewed application database migrations.
- No UPS initially; document this accepted risk and leave a future NUT integration seam.

## Non-goals

- Proxmox, full personal VMs, Kubernetes, or another orchestrator.
- Public ingress or public ACME challenge endpoints.
- Full-disk/internal encryption.
- SSO.
- Prometheus/Grafana unless simple health checks prove inadequate.
- VLAN replacement infrastructure.
- UPS integration in the first rebuild.
- Restoring current internal application/media state.
- Backing up replaceable media, downloads, caches, models, or Jellyfin metadata.
- A shared household Firefly instance.

## Capacity model

A 128 GiB root member plus EFI and replacement slack leaves approximately 800 GiB per NVMe for the mirrored data pool before ZFS overhead. Two 220 GB decimal owner maxima consume about 410 GiB if both are full, leaving roughly 390 GiB for shared services, disposable content, ZFS overhead, and snapshots. Capacity alerts are mandatory because owner quotas do not reserve space.

A nominal 256 GB USB provides about 238 GiB. The 180 GB source warning preserves room for Borg metadata and retained versions; compression must not be relied upon for fit.

## Safety gates

### Before any agent edits tracked implementation files

- Preserve the currently dirty working tree in a recoverable WIP commit/branch or create a clean isolated feature worktree.
- Never overwrite or silently discard existing staged, unstaged, or deleted user work.

### Before disk wipe

- Complete and review the configuration in a clean branch.
- Pass `nix flake check`, a complete host build, and relevant VM tests.
- Rehearse the disk layout against disposable UEFI VM disks.
- Verify OpenZFS, Linux 6.18, ROCm, and the pinned llama.cpp package from evaluated derivations.
- Record both NVMe by-id paths, models, serials, exact byte sizes, sectors, firmware, and SMART state.
- Physically disconnect existing backup media.
- Prepare and verify the offline recovery package and installer revision.
- Require typed confirmation of both NVMe serials immediately before destructive commands.

### Before enabling applications

- Boot independently from either EFI with the other drive absent.
- Assemble md root degraded from either member.
- Import the ZFS pool degraded from either member.
- Restore both drives and wait for synchronization/resilvering.
- Verify datasets, decimal quotas, mountpoints, ARC cap, snapshot exclusions, and scrub timers.

### Before completion

- Validate firewall listeners and absence of WAN forwarding.
- Validate LAN and WireGuard DNS/TLS.
- Demonstrate cross-owner container and SMB isolation.
- Demonstrate qBittorrent fail-closed behavior.
- Benchmark and select the LLM model.
- Complete, verify, unmount, and restore-test both owner USB backups.
- Confirm fresh service onboarding without restoring old internal data.

## Known implementation facts requiring verification

Implementation tickets must research rather than guess:

- disko support and syntax for dual EFI, md root, and ZFS data in one layout;
- exact tail slack and device by-id values;
- literal ZFS quota semantics and recursive snapshot exclusions;
- the compatible Linux/OpenZFS/ROCm package closure in the implementation revision;
- pinned llama.cpp router/unload/unified-memory flags and separate credential enforcement;
- safe Radeon 890M memory pressure and Jellyfin contention behavior;
- NixOS-container support and migration behavior for the personal application stack;
- Enable Banking flow details for the exact account products;
- ASUS DHCP/WireGuard DNS behavior with the host local resolver;
- SMTP relay details, USB identities, thermal limits, and backup freshness policy.

## Success criteria

The rebuild is successful when either NVMe can fail without losing boot or persistent data, owner services and shares cannot accidentally cross-access, shared services remain usable, each correct USB independently produces and restores its approved encrypted archive, replaceable state is excluded by construction, and all recovery/maintenance procedures are documented and tested.
