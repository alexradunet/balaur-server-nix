# Household rebuild hardware inventory

Observed: 2026-08-14

This is a read-only inventory for `.scratch/household-server-rebuild/`. No disk, filesystem, service, firmware, or boot configuration was changed while collecting it.

## Wipe-target NVMe devices

Both namespaces report exactly 1,000,204,886,016 bytes, 1,953,525,168 sectors, and 512-byte logical/physical sectors.

| Linux device at observation | Stable by-id | Model | Serial | Firmware | PCI path |
| --- | --- | --- | --- | --- | --- |
| `/dev/nvme0n1` | `/dev/disk/by-id/nvme-CT1000P3PSSD8_24454C2CAAFE` | Crucial `CT1000P3PSSD8` | `24454C2CAAFE` | `P9CR413` | `pci-0000:61:00.0-nvme-1` |
| `/dev/nvme1n1` | `/dev/disk/by-id/nvme-KINGSTON_SNV3S1000G_50026B76870B8ECD` | Kingston `SNV3S1000G` | `50026B76870B8ECD` | `ERFK1N.3` | `pci-0000:65:00.0-nvme-1` |

Stable EUI identifiers are also present:

- Crucial: `/dev/disk/by-id/nvme-eui.000000000000000100a075244c2caafe`
- Kingston: `/dev/disk/by-id/nvme-eui.00000000000000000026b76870b8ecd5`

The rebuild must use verified by-id paths and must re-display model, serial, byte size, sector size, and target partition table immediately before typed destructive confirmation. Linux enumeration (`nvme0n1` versus `nvme1n1`) is observation-only.

### SMART snapshot

Both devices returned `PASSED`, zero critical warnings, zero media errors, and zero error-log entries.

| Device | Composite temperature | Used | Spare | Data read | Data written | Power-on hours | Unsafe shutdowns |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Crucial | 34 °C | 6% | 100% | 18.07 TB | 27.11 TB | 3,846 | 170 |
| Kingston | 35 °C | 3% | 100% | 9.65 TB | 20.36 TB | 1,917 | 143 |

The Kingston also exposed sensor 2 at 68 °C while its composite temperature was 35 °C. This is not currently a SMART failure, but implementation should retain per-sensor thermal monitoring rather than checking only the composite value.

### Current layout (to be destroyed later)

Each disk currently has:

1. 1 GiB EFI;
2. 128 GiB OS md RAID1 member;
3. 125 GiB app-data md RAID1 member;
4. 100 GiB personal md RAID1 member;
5. 577.5 GiB independent ext4 media partition.

Current arrays `/dev/md125`, `/dev/md126`, and `/dev/md127` were healthy `[UU]` during observation. The future installer must not infer wipe authority from this inventory; issue 16 requires fresh typed serial confirmation.

## Current boot facts

- `/boot` is the Crucial EFI partition, FAT UUID `9A81-7B8A`.
- `/boot-fallback` is the Kingston EFI partition, FAT UUID `9A81-CE59`.
- Both contain independent GRUB EFI executables.
- UEFI has both `NixOS-boot` and `NixOS-boot-fallback` entries.
- Observed boot order was fallback first, primary second; the current boot was fallback.
- Root is ext4 on healthy md RAID1 `/dev/md125`.

These facts show that both EFI payloads exist, not that the future layout has passed its required one-disk boot rehearsal.

## Existing USB backup device — preserve, do not provision

One USB device was attached and unmounted:

| Stable by-id | Model/serial | Raw size | Partition label | Filesystem UUID |
| --- | --- | ---: | --- | --- |
| `/dev/disk/by-id/usb-USB_SanDisk_3.2Gen1_00017730081925061541-0:0` | SanDisk 3.2Gen1 / `00017730081925061541` | 123,009,761,280 bytes | `BALAUR_BACKUP` | `4c83b0a2-5de3-4100-98bd-8d562149d9e0` |

This is the existing roughly 115 GiB backup device, not either planned nominal 256 GB owner device. Do not inspect, format, relabel, mount for provisioning, or use it as an installation target. Physically disconnect it before the NVMe rebuild.

The USB bridge does not expose SMART through smartctl's default device type. No attempt was made to probe alternate bridge modes because preserving the backup matters more than obtaining USB SMART data.

## Compute and accelerator facts

- CPU: AMD Ryzen AI 9 HX 370 with Radeon 890M
- 12 cores / 24 threads, AMD-V available
- RAM: 58,556,502,016 bytes (about 54.5 GiB)
- GPU: Radeon 880M/890M, PCI `1002:150e`, driver `amdgpu`
- NPU: Strix NPU, PCI `1022:17f0`, currently using `amdxdna`
- Available device nodes: `/dev/kfd`, `/dev/dri/renderD128`, `/dev/accel/accel0`
- Kernel reported 8 GiB carved-out VRAM and roughly 27.3 GiB GTT memory for the Radeon GPU.

The target removes FastFlowLM/NPU dependence but retains the hardware fact for recovery and diagnostics.

## Network facts

| Interface | MAC | Observed role/address |
| --- | --- | --- |
| `enp100s0` | `c8:ff:bf:05:0a:45` | primary wired LAN, `192.168.50.2/24` |
| `wlp98s0` | `88:f4:da:37:7d:14` | Wi-Fi fallback, DHCP observation `192.168.50.215/24` |
| `eno1` | `c8:ff:bf:05:0a:44` | down |
| `wg-br` | runtime-generated | qBittorrent VPN namespace bridge, `192.168.15.5/24` |

- Default gateway/router: `192.168.50.1` (ASUS RT-AX82U per repository documentation).
- The router reservation for `192.168.50.2` must be rechecked before install.
- Router WireGuard commonly uses `10.6.0.0/24`; exact active profile values remain router-owned secrets and are not recorded here.

## Retained public access facts

The current configuration contains two Alex SSH public keys:

- `alex@yoga-laptop`
- `alex@balaur.space`

Both remain authorized under the previously accepted access recommendation. No private key was inspected.

Andreea is intended to have a normal local/SMB account with no sudo, SSH admission, or local TTY login. Samba/application credentials do not grant a host shell.

## Confirmed backup/source policy

Each future owner USB includes only that owner's home/files, private application state, banking state, encrypted host configuration, and approved shared state. New Home Assistant state goes to both. Media, downloads, models, caches, Jellyfin state, and temporary files are excluded.

## Values still requiring human input or future attached hardware

1. Both new nominal 256 GB USB devices: model, by-id, serial, byte size, partition UUID, label, and blank/existing-content status. They are not currently attached.
2. SMTP relay and destination email for operational alerts. The implementation should expose a provider-neutral sendmail interface so this can be supplied later as an encrypted secret.
3. The list of client devices on which the Caddy private CA will be installed.
4. Final thermal alert thresholds after a sustained ROCm/Jellyfin benchmark.

Confirmed policy: Alex may write the shared-media SMB share; both owners may read it. Both existing Alex SSH public keys remain. Andreea receives no host shell through SSH or local TTY.

These unresolved values must remain non-operational placeholders or explicit assertions; implementation must not guess them.

## Commands used

Read-only observations used `lsblk`, `/sys/class/{nvme,block,net}`, `ip`, `lscpu`, `free`, `lspci`, `findmnt`, `/proc/mdstat`, `sgdisk --print`, `efibootmgr -v`, `nvme smart-log`, and `smartctl -H -i`. The last three tools were run from temporary Nix shell packages. Commands requiring device access used existing passwordless sudo and performed no writes.
