# Balaur Server

NixOS configuration for `balaur`, a LAN-accessible development host managed over SSH.

## Repository structure

The configuration follows a feature-oriented, incremental version of the
[dendritic pattern](https://discourse.nixos.org/t/the-dendritic-pattern/61271):
NixOS modules live under `modules/` and are organized by capability rather than
by host or service layer. `hosts/balaur/` only composes the features and keeps
the generated hardware module and installed-host identity together. Standalone
package expressions live under `packages/`; they are intentionally kept out of
the module tree.

This keeps the current single-host flake simple while making features reusable
when another host is added. A full flake-parts/import-tree top-level module tree
can be introduced later if the repository grows beyond this host.

## Deploy

Apply the configuration from the repository root:

```sh
sudo nixos-rebuild switch --flake .#balaur
```

Evaluate the complete system configuration without activating it:

```sh
nix eval .#nixosConfigurations.balaur.config.system.build.toplevel.drvPath --raw
```

## Tests

Run all configuration invariants, dashboard integration tests, package builds, and
the standard NixOS module checks:

```sh
nix flake check
```

Build the complete host system without creating a `result` symlink:

```sh
nix build .#nixosConfigurations.balaur.config.system.build.toplevel --no-link
```

## Data Storage

After the 128 GiB OS RAID1, space on both NVMe drives is divided into
125 GiB of mirrored application data, 100 GiB of mirrored personal data, and
two independent filesystems using all remaining space (roughly 577 GiB each)
for replaceable media. Downloads use only `/srv/media/ssd0`.

| Mount | Usable size | Redundancy |
| --- | ---: | --- |
| `/srv/app-data` | 125 GiB | RAID1 |
| `/srv/personal` | 100 GiB | RAID1 |
| `/srv/media/ssd0` | ~577 GiB | none |
| `/srv/media/ssd1` | ~577 GiB | none |

Provision this layout once. **The following commands destroy both existing `p3`
partitions.** Confirm that they are the unused 802.5 GiB partitions before
continuing. Do not change partitions 1 or 2; they contain EFI and the OS RAID.

```sh
sudo nixos-rebuild switch --flake .#balaur
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS,MODEL

for disk in /dev/nvme0n1 /dev/nvme1n1; do
  sudo sgdisk --delete=3 \
    --new=3:0:+125G --typecode=3:fd00 --change-name=3:APP_DATA_RAID \
    --new=4:0:+100G --typecode=4:fd00 --change-name=4:PERSONAL_RAID \
    --new=5:0:0 --typecode=5:8300 --change-name=5:MEDIA \
    "$disk"
done
sudo partprobe /dev/nvme0n1 /dev/nvme1n1

sudo mdadm --create /dev/md/app-data --metadata=1.2 --level=1 \
  --raid-devices=2 /dev/nvme0n1p3 /dev/nvme1n1p3
sudo mdadm --create /dev/md/personal --metadata=1.2 --level=1 \
  --raid-devices=2 /dev/nvme0n1p4 /dev/nvme1n1p4

sudo mkfs.ext4 -L BALAUR_APP_DATA /dev/md/app-data
sudo mkfs.ext4 -L BALAUR_PERSONAL /dev/md/personal
sudo mkfs.ext4 -L BALAUR_MEDIA_0 /dev/nvme0n1p5
sudo mkfs.ext4 -L BALAUR_MEDIA_1 /dev/nvme1n1p5
sudo nixos-rebuild switch --flake .#balaur
```

Verify the resulting filesystems and initial RAID synchronization:

```sh
findmnt /srv/app-data /srv/personal /srv/media/ssd0 /srv/media/ssd1
cat /proc/mdstat
sudo mdadm --detail /dev/md/app-data
sudo mdadm --detail /dev/md/personal
```

The setgid directories and shared `media` group allow `alex` and future
Jellyfin or Immich service accounts to share files without making them
world-writable. RAID is not a backup; Google Photos remains the off-site copy
of the personal photo library.

## USB Backup

The server creates an encrypted Borg snapshot of `/home/alex`, application
state, personal data, Home Assistant state, and host-local secrets once per day.
The large FastFlowLM model cache is excluded because it can be downloaded again.
The USB filesystem is mounted only for the backup and is unmounted afterward,
including when the backup fails. Retention is 7 daily, 4 weekly, and 6 monthly
snapshots.

Before creating an archive, the job pauses Trilium so its SQLite database and
attachments are captured consistently, then resumes it before Borg prunes and
compacts the repository, including after failures. Trilium also keeps its own
periodic database backups enabled. Other application databases are still
filesystem snapshots of live services; use Home Assistant's native backup as an
additional safeguard and perform restore tests before treating this as a complete
disaster-recovery plan.

Provision the USB stick once. Confirm its device path carefully with `lsblk` before
formatting; the following command destroys that partition's existing contents:

```sh
sudo mkfs.ext4 -L BALAUR_BACKUP /dev/sdX1
sudo install -d -m 0700 /var/lib/balaur-backup
sudo sh -c 'umask 077; head -c 48 /dev/urandom | base64 > /var/lib/balaur-backup/passphrase'
```

Store a copy of `/var/lib/balaur-backup/passphrase` somewhere secure outside this
server. The Borg repository cannot be recovered without it. Then deploy and test the
backup immediately:

```sh
sudo nixos-rebuild switch --flake .#balaur
sudo systemctl start balaur-backup.service
sudo journalctl -u balaur-backup.service
```

The first run initializes `/mnt/balaur-backup/borg`. Check timer scheduling and
verify that the stick is no longer mounted after a run with:

```sh
systemctl list-timers balaur-backup.timer
findmnt /mnt/balaur-backup
```

After the first successful run, mount the stick and export Borg's repository key.
Keep that export together with the passphrase copy, outside the server:

```sh
sudo mount /mnt/balaur-backup
sudo env BORG_PASSCOMMAND='cat /var/lib/balaur-backup/passphrase' \
  borg key export /mnt/balaur-backup/borg /var/lib/balaur-backup/repository-key
sudo umount /mnt/balaur-backup
```

The invariant check covers the host's boot and filesystem layout, backup safety,
SSH and firewall policy, loopback-only services, and systemd sandboxing. The
dashboard check starts the real Node server and verifies its HTTP
routes, security headers, metrics response, and service status payload.

## LAN Address

The server uses the router's reserved LAN address `192.168.50.2`. Reserve this
address for the server's MAC address in the ASUS RT-AX82U DHCP settings and use
the IP address directly from LAN or WireGuard clients. See
[`docs/network-access.md`](docs/network-access.md) for the complete split-tunnel
WireGuard setup and remote-access test procedure.

## SSH Access

Connect over SSH with `ssh alex@192.168.50.2`. Authentication uses the
declaratively managed `alex@yoga-laptop` Ed25519 key; password authentication,
root login, keyboard-interactive authentication, and X11 forwarding are disabled.

The dashboard is available on the LAN at `http://192.168.50.2`; Caddy
forwards the standard HTTP port to the private dashboard process. Administrative
access is deliberately absent from the dashboard: Herdr has no web terminal,
and the remote desktop has no noVNC gateway. The router must not forward any
service ports from the internet.

Run Herdr directly over SSH:

```sh
ssh -t alex@192.168.50.2 herdr
```

For the remote desktop, tunnel the loopback-only VNC server over SSH:

```sh
ssh -N -L 5910:127.0.0.1:5910 alex@192.168.50.2
```

Then configure a native VNC client to connect to `localhost` on port `5910`.
The SSH tunnel supplies authentication and encryption; do not expose the VNC
port directly.

## Local Services

The dashboard monitors Home Assistant, Jellyfin, Prowlarr, qBittorrent,
Trilium, and FastFlowLM. Their service addresses include:

- Dashboard: `http://192.168.50.2`
- Home Assistant: `http://192.168.50.2:8123`
- Jellyfin: `http://192.168.50.2:8096`
- Prowlarr: `http://192.168.50.2:9696`
- qBittorrent: `http://192.168.50.2:8082`
- Trilium: `https://192.168.50.2:8084` (LAN/VPN-only)
- Pocket Trilium fallback: `http://192.168.50.2:8085` (LAN/VPN-only)
- Remote desktop: use the SSH tunnel above and a native VNC client on `localhost:5910`
- Herdr: run `ssh -t alex@192.168.50.2 herdr`
- FastFlowLM models API: `http://192.168.50.2:8081/v1/models`

The media stack is intentionally limited to Jellyfin, Prowlarr, and
qBittorrent. It treats downloads as a temporary watch queue rather than a
permanent managed library:

1. Search FileList from Prowlarr's **Search** page.
2. Grab the chosen release. Prowlarr sends it to qBittorrent with the `manual`
   category.
3. qBittorrent saves completed files directly under
   `/srv/media/ssd0/downloads/complete`.
4. Watch the files through Jellyfin.
5. After satisfying FileList's current ratio and seed-time rules, remove the
   torrent **and its files** through qBittorrent. Let Jellyfin rescan afterward.

For playback, create one Jellyfin library named `Temporary` with content type
**Mixed Movies and Shows** and folder
`/srv/media/ssd0/downloads/complete`. This is a one-time UI setting;
Jellyfin's service account already belongs to the `media` group. Its persistent
state is stored in `/srv/app-data/jellyfin`, while replaceable media is excluded
from the USB Borg backup.

Prowlarr retains the existing FileList configuration in
`/srv/app-data/prowlarr`. The boot-time `prowlarr-qbittorrent-sync` service
registers qBittorrent as Prowlarr's download client and points the `manual`
category at the main completed-download directory. The qBittorrent password is
generated outside the Nix store and loaded through systemd credentials.

qBittorrent remains fail-closed inside Nixarr's WireGuard namespace using
`/srv/secrets/protonvpn.conf`. A host proxy provides its authenticated
`127.0.0.1:8082` and LAN endpoint, while peer port 6881 is exposed only through
the VPN. Its stable `admin` password can be read with
`sudo cat /srv/secrets/qbittorrent-webui-password`.

After the first deployment, remove stale Sonarr, Radarr, Lidarr, and Whisparr
entries under Prowlarr's **Settings → Apps**. Their disabled application state
and old download directories are not deleted automatically; remove them only
after confirming that no retained data or active seeding torrent needs them.

TriliumNext is the LAN/VPN-only structured-notes service. Trilium listens only
on `127.0.0.1:11000`; Caddy publishes `https://192.168.50.2:8084`, terminates
TLS with its private local CA, and proxies WebSockets required for sync. For
clients that cannot trust the private CA (such as Pocket Trilium), Caddy also
publishes `http://192.168.50.2:8085`. Port 8085 is available only on the LAN and
through WireGuard; it is not forwarded from the internet. Use the HTTPS
address for browsers and desktop clients, and the HTTP address for Pocket
Trilium if its embedded certificate trust cannot be configured.

For remote WireGuard clients, configure the router to route the WireGuard client
subnet to `192.168.50.0/24` (or NAT that traffic to the LAN). If using a
hostname instead of the IP address, the router's DNS must resolve that hostname
to `192.168.50.2` for both LAN and WireGuard clients. Install Caddy's local root CA on every sync client before configuring Trilium.
On Windows, stage the root certificate so the SSH user can copy it, then
import it into **Trusted Root Certification Authorities**:

```powershell
ssh alex@192.168.50.2 "sudo cp /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt /home/alex/balaur-caddy-root.crt; sudo chmod 0644 /home/alex/balaur-caddy-root.crt"
scp alex@192.168.50.2:/home/alex/balaur-caddy-root.crt `
  "$env:USERPROFILE\Downloads\balaur-caddy-root.crt"
ssh alex@192.168.50.2 "rm /home/alex/balaur-caddy-root.crt"
Import-Certificate -FilePath "$env:USERPROFILE\Downloads\balaur-caddy-root.crt" `
  -CertStoreLocation Cert:\CurrentUser\Root
```

Alternatively, double-click the `.crt` file, choose **Install Certificate**,
select **Current User**, and place it in **Trusted Root Certification
Authorities**. Fully exit Trilium Desktop, including its tray process, and start
it again after importing the certificate. Linux clients should install the same
certificate into their system trust store and, if necessary, Electron's NSS
store.

The CA is generated on first Caddy start. A publicly trusted certificate for a
real hostname is preferable if clients cannot install this CA. In Trilium,
configure Options → Sync with `https://192.168.50.2:8084` (or
`http://192.168.50.2:8085` for Pocket Trilium); Caddy forwards the WebSocket
upgrade and the server trusts only its local reverse proxy. Its SQLite
database, attachments, configuration, and periodic internal backups live under
`/srv/app-data/trilium`, which is included in the encrypted USB Borg backup.
Complete the first-run setup in the web UI and choose a strong owner password;
authentication remains enabled.

The Obsidian package and Syncthing service are no longer installed. Keep the
external copies of the old vault unchanged and import notes into Trilium in small
batches, checking links and image, audio, and video attachments after each batch.
Trilium's database becomes the source of truth for imported content. The old
Nextcloud, PostgreSQL, and `/srv/personal/nextcloud-data` files are not deleted by
the configuration change; remove them manually only after confirming they are no
longer needed. Use a secured VPN for access away from home; do not forward port
8084 from the router.

Complete Home Assistant's first-run onboarding at its LAN URL. NixOS packages integration
dependencies declaratively: add any new integration to
`services.home-assistant.extraComponents` before configuring it in the UI. Wiz,
Hue, iBeacon, IPP printers, Netatmo, PlayStation Network, Roborock, Samsung TV,
Radio Browser, and Google Translate are currently included.

Its runtime configuration, automations, database, and credentials are stored in
`/var/lib/hass`; do not put Home Assistant secrets in this repository. The USB
Borg job includes this directory, but a native Home Assistant backup remains a
useful application-consistent safeguard.

FastFlowLM runs the reasoning and tool-capable `qwen3.6-moe:35b-a3b` model on the Ryzen AI XDNA2 NPU with its catalog-default 32K context. The Q4_K_S NPU build has a catalog footprint of 24.3 GB, which fits in this host's 54.5 GiB of RAM. Its OpenAI-compatible API remains on port 8081, with endpoints below `/v1`; it does not provide the old llama.cpp web UI. The first service start downloads FastFlowLM's NPU-optimized model files from Hugging Face into `/srv/app-data/fastflowlm/models`, so the API remains unavailable until that large download and model load finish. Follow progress with `journalctl -fu fastflowlm`.

The portable FastFlowLM runtime bundles its XRT userspace libraries. NixOS uses Linux 7.1 so `amdxdna` loads the required protocol-7 NPU firmware, then grants the service access to `/dev/accel/accel0` with unlimited memlock. Reboot after the first deployment to enter the new kernel. Validate the stack with `sudo -u fastflowlm flm validate`; it should report firmware 1.1.2.64 and `ready: true`. Inspect installed models with `sudo -u fastflowlm env FLM_MODEL_PATH=/srv/app-data/fastflowlm/models flm list --filter installed`, and test the API with:

```sh
curl http://127.0.0.1:8081/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.6-moe:35b-a3b","messages":[{"role":"user","content":"Reply with OK"}]}'
```

FastFlowLM has no API authentication. Keep port 8081 LAN-only and do not forward it from the router. The obsolete llama.cpp GGUF cache under `/var/cache/llama-cpp` is not used and may be deleted manually after confirming FastFlowLM works.

Herdr remains available as the `herdr` CLI and shares its persistent sessions
and development environment when run through SSH. No writable web terminal is
started.

**Security:** the noVNC gateway and Herdr web terminal are not configured. The
raw TigerVNC server listens only on loopback (`127.0.0.1`) and is reachable
remotely only through the authenticated, encrypted SSH tunnel above. Keep SSH
keys protected and do not configure router port forwarding for administrative
interfaces.

XFCE is the host's principal local desktop and starts through LightDM. Remote
access uses a separate persistent TigerVNC display with an XFCE session.
