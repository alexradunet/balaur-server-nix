# Household server recovery runbook (draft)

> **Observation-only draft:** physical replacement, md/ZFS mutation, root reinstall, Borg restore, and credential rotation have not been rehearsed. This document deliberately stops before every destructive boundary. Issue 16 validates installation and one-drive-absent degraded boot; replacement, motherboard/root recovery, and credential rotation still require separately reviewed rehearsals. Issue 17 validates physical USB/Borg restores.

Start by preserving evidence. Do not run disko for a single-drive or root-only recovery: the generated scripts wipe both complete NVMe devices, including intact `tank` members.

## Common observation bundle

From the installed host or trusted installer, record UTC time and collect without changing array/pool state:

```console
date -u
lsblk -b -o NAME,PATH,TYPE,SIZE,FSTYPE,LABEL,UUID,MODEL,SERIAL,MOUNTPOINTS
for target in / /boot /boot-fallback /home/alex /home/andreea /srv/services /srv/shared; do
  if mountpoint "$target"; then findmnt --mountpoint "$target"; else printf 'MISSING MOUNT: %s\n' "$target"; fi
done
cat /proc/mdstat
sudo mdadm --detail /dev/md/root
sudo zpool status -P tank
sudo zpool import
sudo zfs list -o name,mountpoint,canmount,mounted
sudo efibootmgr -v
systemctl --failed
journalctl -b -p warning..alert --no-pager
```

`zpool import` without a pool argument is inventory only; do not add `-f`, import, online/offline, detach, replace, clear, or rewind options during observation. Save output outside the affected filesystems when possible.

Abort and request review before any partition write, filesystem creation, `mdadm --create/assemble/add/remove/fail`, ZFS import or vdev mutation, snapshot rollback/destruction, or bootloader write.

## Either NVMe fails

Roles are fixed by stable identity:

| Failed device | Missing ESP | Surviving boot path |
| --- | --- | --- |
| Crucial `24454C2CAAFE` | `/boot` | Kingston `/boot-fallback` |
| Kingston `50026B76870B8ECD` | `/boot-fallback` | Crucial `/boot` |

1. Power down before physically changing storage unless the reviewed hardware procedure explicitly permits hot-plugging.
2. Remove only the failed device. Boot the surviving ESP through firmware selection.
3. Re-run the common observation bundle. Confirm `/dev/md/root` is degraded but mounted from the expected member, and `tank` is degraded but contains the expected surviving vdev. Do not enable personal/shared applications merely because the system booted.
4. Record the failed member identity/vdev GUID and the proposed replacement's by-id, model, serial, byte size, logical/physical sectors, blank/content status, and SMART report.
5. Abort if the replacement is smaller than the required partition endpoints, has unexplained content, or could be confused with the surviving disk or any USB device.
6. Before any future activation, update and review the replacement's new stable by-id in both `hosts/balaur/disko.nix` and the matching GRUB entry in `modules/boot.nix`. The old serial cannot remain declarative authority.
7. Obtain human approval for a reviewed replacement procedure that recreates only the failed disk's GPT/ESP/root member/tank member, restores the correct independent EFI payload, adds the root member, and replaces the missing ZFS vdev.
8. Wait for md synchronization and ZFS resilver completion. Re-run all storage/dataset/boot checks before returning services.

No exact replacement mutation commands are approved yet. Do not infer them from generic mdadm/ZFS examples, and never use the whole-host disko output for replacement.

## Motherboard loss with both NVMe drives intact

1. Keep both disks together and record which stable identity provided `/boot` and `/boot-fallback`.
2. On replacement hardware, first attempt the removable-media fallback `EFI/BOOT/BOOTX64.EFI` on either ESP; both payloads are present in the tested layout.
3. Observe md and `tank` before allowing imports or writes. Preserve the configured ZFS host ID `8bdbe130`; do not force-import a pool merely because firmware/NIC identity changed.
4. Recheck CPU/GPU compatibility and regenerate hardware-specific configuration only through a reviewed source change. Do not silently replace the pinned kernel/OpenZFS/ROCm policy.
5. Update the ASUS DHCP reservation if the wired MAC changes. Re-run every LAN/WireGuard DNS, TLS, firewall, and no-WAN-forward check in `docs/network-access.md`.

If root and `/var/lib/caddy` survived, retain the existing Caddy CA state. If it did not, treat clients as requiring enrollment in a new CA; never copy or regenerate a CA private key manually.

## Lost root filesystem with intact `tank`

Stop. The normal disko script is forbidden because it would destroy the intact ZFS partitions.

1. Boot trusted, hash-verified installer media and collect the common disk/md/ZFS inventory.
2. Confirm both `tank` member partitions and pool GUIDs before any md/root action.
3. Preserve an external copy of the observation output and current repository revision.
4. Have a reviewed recovery procedure rebuild only the ESP/root-md portions, install the exact approved NixOS closure, restore the host age identity and encrypted configuration, and then import/mount `tank` without recreating it.
5. Verify protected datasets and snapshots before starting services. Disposable media/model/cache state may be empty.

There is currently no tested root-only reinstall sequence. Do not invent one during an incident and do not claim local ZFS snapshots protect against pool loss.

## Lost SSH, sudo, or age credentials

SSH admits only Alex and only through the two declarative public keys; root login and SSH passwords are disabled. Andreea has no host shell.

- If one Alex client key is lost, use the other already-authorized key and remove/replace the lost public key through a reviewed configuration change.
- If both client keys are unavailable, use a reviewed physical-console/installer recovery path. No out-of-band console login is currently proven; do not enable root/password SSH as an emergency shortcut.
- Alex's final Unix password/hash is not yet configured. During onboarding, keep one authenticated SSH session open, test password-authenticated `sudo` from a second session, disable bootstrap passwordless sudo, rebuild, and test again.

The dedicated age identity belongs at `/var/lib/sops-nix/key.txt`, with `/var/lib/sops-nix` mode `0700` and the root-owned key mode `0600`. It must come from the separately protected offline administrator package; never recover it from an owner container or paste it through chat/history.

After restoring the controlled copy, verify metadata and test sops decryption without printing values. If every private identity copy is lost, existing ciphertext is unrecoverable: generate a new dedicated identity under human control and rotate/recreate every affected host and owner credential. Do not substitute an SSH/GPG key or enable automatic age-key generation.

## Private network and Caddy CA recovery

Follow `docs/network-access.md` as the authority. Minimum observations include:

```console
nslookup balaur.home.arpa 192.168.50.2
nslookup example.com 192.168.50.2
sudo install -m 0644 -o alex -g users \
  /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt \
  /home/alex/balaur-caddy-root.crt
sha256sum /home/alex/balaur-caddy-root.crt
nix shell nixpkgs#openssl -c openssl x509 -noout -fingerprint -sha256 \
  -in /home/alex/balaur-caddy-root.crt
curl --fail --silent \
  --cacert /home/alex/balaur-caddy-root.crt \
  --resolve balaur.home.arpa:443:192.168.50.2 \
  https://balaur.home.arpa/health
rm /home/alex/balaur-caddy-root.crt
```

The health response is `balaur ok`. Verify an unknown `home.arpa` name does not resolve. Test WireGuard from mobile data with client DNS effectively using `192.168.50.2`; inspect the ASUS UI for no port forwards, DMZ, or unexpected UPnP mappings. Never record WireGuard private keys/profile secrets in this repository.

Only the public Caddy root certificate may be exported from:

```text
/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt
```

Record its SHA-256 certificate fingerprint and enroll it on the human-approved client list. Transfer only the public certificate, calculate the fingerprint again on the client, and compare it with the independently recorded server value before changing client trust. Abort enrollment on any mismatch. Never copy the CA private key. Root loss can create a new CA, in which case all clients must remove/review the old trust and enroll the new public root.

## Lost owner USB or Borg recovery material

Future owner devices remain independent. Loss of one device must never cause use of the other owner's device, repository, credentials, or private state.

- If one encrypted USB is lost but the host survives, mark that owner's off-host backup unavailable/stale, determine whether repository credentials may also be exposed, and purchase a replacement. Inventory it read-only, obtain explicit erase approval, assign a new UUID/label and separate repository credentials through the future issue-14 procedure, then complete and restore-test a new full archive before clearing the alert. Rotate that owner's Borg material if confidentiality of the old material is uncertain.
- If both owner devices are lost, internal mirrored data is the only remaining copy. Replace and independently provision both workflows; do not clone one owner's repository or key into the other.
- If an owner USB and the host are both lost, only another verified copy/archive can restore that owner's state. Without one, the state is unrecoverable; mirroring is not a backup.
- If a Borg passphrase or repository key is lost and no protected offline copy exists, do not bypass encryption or guess credentials. That repository is cryptographically unrecoverable. Retire it and create a new independently keyed repository from surviving trusted data.
- If a device is stolen, encryption protects confidentiality only while its passphrase/key remains secret. Record the incident, rotate material when exposure is plausible, and do not claim availability until a replacement archive passes verification and restore testing.

## Offline administrator recovery package

Before issue 16, create and verify one offline package, separate from both owner USB devices. Its manifest must record:

- reviewed repository bundle and exact installation commit;
- `flake.lock`, installer image/source, and verified SHA-256;
- this runbook and the hardware inventory;
- both public SSH keys and the approved client-device/CA fingerprint list;
- public age recipient and encrypted host/Alex/Andreea sops payloads;
- the dedicated age private identity and recovery instructions, protected as a secret;
- Alex administrative recovery material, protected as a secret;
- after issue 14, both separate Borg repository identities/keys/passphrases plus the reviewed VM failure/restore-test evidence; append dated physical restore evidence only after issue 17.

Test that the package can be read on a separate trusted machine and that public metadata matches the repository. Do not print secret values during verification. Store at least one physically separate protected copy. The package is not complete while its age/Borg/installer fields are absent.

## Deferred owner USB/Borg recovery

The Owner deferred issue 14 until two new nominal 256 GB devices are purchased. Therefore there is no approved filesystem UUID/label, repository path, passphrase/key path, backup service, archive format, freshness age, SMTP destination, safe-removal workflow, or restore command for either owner.

The existing SanDisk `BALAUR_BACKUP` (UUID `4c83b0a2-5de3-4100-98bd-8d562149d9e0`) is preserved pre-rebuild media, not an Alex or Andreea target. Do not mount it for provisioning, relabel it, format it, initialize Borg on it, or use legacy README backup commands.

When the new devices exist, provisioning must stop until a read-only inventory records each device's by-id, model, serial, raw byte size, partition table, filesystem UUID/label, mount state, and existing-content status; the Owner must map each serial to one owner and separately approve erasure. Both UUID and label must match the reviewed owner configuration before any later backup write. A mounted device, wrong/missing identity, existing unexplained content, unavailable owner-specific credential, or attached preserved SanDisk is an abort condition.

Keep each future repository passphrase/key only in its separated encrypted schema and the offline administrator package. Recovery must verify that the offline material opens the matching owner repository without displaying it and without trying the other owner's material. Never weaken encryption, share keys, or treat successful archive listing as a restore test.

A quarterly drill must select a dated verified archive, restore representative owner files, Trilium, Paperless, Firefly, and Home Assistant only into new temporary locations, compare content/ownership and application startup there, and delete the temporary restore only after recording results. It must not overwrite live data, start restored databases beside live instances, or mark success from `borg check` alone. Record UTC date, owner/device identity, archive identifier, tested components, result, cleanup, and reviewer; email contains only safe-removal/result metadata.

Until issue 14 implements and VM-tests the workflow and issue 17 records two successful physical restore drills, off-host recovery is unproven. Under the current ticket dependencies selected by the Owner, the destructive rebuild remains blocked; changing that sequencing requires an explicit spec/ticket revision.
