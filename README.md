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

The free space on both NVMe drives is divided into 125 GiB of mirrored
application data, 400 GiB of mirrored personal data, and two independent
filesystems using all remaining space (roughly 277 GiB each) for replaceable
downloads.

| Mount | Usable size | Redundancy |
| --- | ---: | --- |
| `/srv/app-data` | 125 GiB | RAID1 |
| `/srv/personal` | 400 GiB | RAID1 |
| `/srv/media/ssd0` | ~277 GiB | none |
| `/srv/media/ssd1` | ~277 GiB | none |

Provision this layout once. **The following commands destroy both existing `p3`
partitions.** Confirm that they are the unused 802.5 GiB partitions before
continuing. Do not change partitions 1 or 2; they contain EFI and the OS RAID.

```sh
sudo nixos-rebuild switch --flake .#balaur
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS,MODEL

for disk in /dev/nvme0n1 /dev/nvme1n1; do
  sudo sgdisk --delete=3 \
    --new=3:0:+125G --typecode=3:fd00 --change-name=3:APP_DATA_RAID \
    --new=4:0:+400G --typecode=4:fd00 --change-name=4:PERSONAL_RAID \
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

SSH is the only service allowed through the host firewall. Connect from the LAN
using the server's address:

```sh
ssh alex@192.168.50.13
```

Authentication uses the declaratively managed `alex@yoga-laptop` Ed25519 key.
Password authentication, root login, keyboard-interactive authentication, and X11
forwarding are disabled.

The web services listen only on loopback. Forward their ports through SSH when
needed:

```sh
ssh -N -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:8080:127.0.0.1:8080 \
  -L 127.0.0.1:8123:127.0.0.1:8123 \
  -L 127.0.0.1:8383:127.0.0.1:8383 \
  -L 127.0.0.1:6080:127.0.0.1:6080 \
  -L 127.0.0.1:7681:127.0.0.1:7681 \
  -L 127.0.0.1:8081:127.0.0.1:8081 \
  alex@192.168.50.13
```

Open `http://localhost:8080` in Waterfox. The dashboard links point to each
service's forwarded port. Keep the SSH command running while using the services.

## Local Services

The dashboard monitors Home Assistant, Syncthing, the web desktop, Herdr, and
llama.cpp through their loopback listeners. They are reachable only through SSH
forwarding; no public HTTPS endpoint, VPN, or overlay network is configured.

Home Assistant is available at `http://localhost:8123` while the SSH forward is
running. Complete its first-run onboarding there. NixOS packages integration
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

Herdr remains available as the `herdr` CLI. Its web endpoint runs the same terminal UI through a loopback-only ttyd process as the `alex` user, so it shares the CLI's persistent sessions and development environment.

noVNC and the Herdr web terminal do not have an additional application authentication layer. They must remain bound to loopback and accessed only through SSH forwarding.

XFCE is the host's principal local desktop and starts through LightDM. The web desktop uses a separate persistent TigerVNC display with an XFCE session and a loopback-only noVNC gateway.
