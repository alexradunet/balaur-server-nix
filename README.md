# Balaur Server

NixOS configuration for `balaur`, a LAN-accessible development host managed over SSH.

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
for replaceable downloads.

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

The server creates an encrypted Borg snapshot of `/home/alex` once per day. The
USB filesystem is mounted only for the backup and is unmounted afterward, including
when the backup fails. Retention is 7 daily, 4 weekly, and 6 monthly snapshots.

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

## SSH Access

Connect over SSH with `ssh alex@192.168.50.13`. Authentication uses the
declaratively managed `alex@yoga-laptop` Ed25519 key; password authentication,
root login, keyboard-interactive authentication, and X11 forwarding are disabled.

Web services are available directly on the LAN. Open the dashboard at
`http://192.168.50.13:8080`; its links use the same server address. The router
must not forward any of these ports from the internet.

## Local Services

The dashboard monitors Home Assistant, Jellyfin, the Servarr suite, qBittorrent,
Syncthing, the web desktop, Herdr, and llama.cpp. Their LAN URLs include:

- Dashboard: `http://192.168.50.13:8080`
- Home Assistant: `http://192.168.50.13:8123`
- Jellyfin: `http://192.168.50.13:8096`
- Prowlarr: `http://192.168.50.13:9696`
- Sonarr: `http://192.168.50.13:8989`
- Radarr: `http://192.168.50.13:7878`
- Lidarr: `http://192.168.50.13:8686`
- Readarr: `http://192.168.50.13:8787`
- Whisparr: `http://192.168.50.13:6969`
- Bazarr: `http://192.168.50.13:6767`
- qBittorrent: `http://192.168.50.13:8082`
- Syncthing: `http://192.168.50.13:8383`
- Web desktop: `http://192.168.50.13:6080`
- Herdr: `http://192.168.50.13:7681`
- llama.cpp: `http://192.168.50.13:8081`

Jellyfin first-run setup is available at its LAN URL. Add libraries from
`/srv/media/ssd0` and `/srv/media/ssd1`. Its service account belongs to the
`media` group, and persistent application state is stored in
`/srv/app-data/jellyfin`. The replaceable media itself is not included in the
USB Borg backup.

Prowlarr, Sonarr, Radarr, Lidarr, Readarr, Whisparr, Bazarr, and qBittorrent store their
state under `/srv/app-data`. Configure authentication in every web UI before
adding indexers or download clients. On qBittorrent's first start, retrieve its
temporary admin password with `journalctl -u qbittorrent | grep -i password`, log
in as `admin`, and immediately set a permanent password.

Leave qBittorrent's global incomplete-download folder disabled, then create
categories with these save paths:

- `radarr`: `/srv/media/ssd0/downloads/complete/radarr`
- `whisparr`: `/srv/media/ssd0/downloads/complete/whisparr`
- `sonarr`: `/srv/media/ssd1/downloads/complete/sonarr`
- `lidarr`: `/srv/media/ssd1/downloads/complete/lidarr`
- `readarr`: `/srv/media/ssd1/downloads/complete/readarr`

Use `/srv/media/ssd0/library/movies`, `/srv/media/ssd0/library/whisparr`,
`/srv/media/ssd1/library/tv`, `/srv/media/ssd1/library/music`, and
`/srv/media/ssd1/library/books` as the corresponding root folders. Keeping each category and library on the same SSD
allows hardlinks and atomic imports. Add qBittorrent to each Arr app at
`127.0.0.1:8082` with its matching category. Add each Arr app to Prowlarr using
its `127.0.0.1` URL and API key, preferably with Full Sync.

Complete Home Assistant's first-run onboarding at its LAN URL. NixOS packages integration
dependencies declaratively: add any new integration to
`services.home-assistant.extraComponents` before configuring it in the UI. Wiz,
Hue, iBeacon, IPP printers, Netatmo, PlayStation Network, Roborock, Samsung TV,
Radio Browser, and Google Translate are currently included.

Its runtime configuration, automations, database, and credentials are stored in
`/var/lib/hass`; do not put Home Assistant secrets in this repository. The USB
Borg job does not currently include this directory, so use Home Assistant's
built-in backup feature for its state.

llama.cpp automatically downloads the instruction-tuned `gemma-4-26B-A4B-it` Q4_K_M GGUF from Hugging Face into `/var/cache/llama-cpp` on its first start. The model download is about 16.9 GB, with an additional multimodal projector downloaded automatically when available. It uses a 64K shared context, two request slots, ROCm acceleration targeting the Radeon 890M's `gfx1150` architecture, flash attention, and Gemma 4's 462 MB MTP drafter for lossless speculative decoding. The first service start remains unavailable until the downloads and model load complete; follow progress with `journalctl -fu llama-cpp`. After five idle minutes, llama.cpp unloads the model and KV cache from RAM and VRAM, then reloads them automatically on the next inference request.

The ROCm-enabled `llama-server` and related llama.cpp commands are also installed system-wide. llama.cpp is pinned to release `b10336` because Gemma 4's MTP drafter requires architecture support newer than the Nixpkgs package.

Herdr remains available as the `herdr` CLI. Its web endpoint runs the same terminal UI as the `alex` user, so it shares the CLI's persistent sessions and development environment.

**Security:** noVNC and the writable Herdr terminal have no additional application authentication. Any device that can reach these LAN ports can control the desktop or run commands as `alex`. Keep the LAN trusted and do not configure router port forwarding for these services.

XFCE is the host's principal local desktop and starts through LightDM. The web desktop uses a separate persistent TigerVNC display with an XFCE session; only its noVNC gateway is exposed to the LAN, while raw VNC remains on loopback.
