# Capture hardware and external-system facts

Status: needs-info
Blocked by: 01
Inventory captured: 2026-08-14

## Objective

Record observed identifiers and human-owned integration values needed for safe implementation. Guessing is prohibited.

## Work

Record both NVMe by-id paths, models, serials, byte sizes, sectors, firmware and SMART state; NIC names/MAC; both USB models, UUIDs, labels and whether either contains an existing backup; SMTP relay/alert destination; retained SSH keys; approved shared backup paths; media write policy; and client CA-installation targets.

Place non-secret facts in a host facts module or runbook. Put secret values only into newly encrypted sops files when issue 07 establishes key management.

## Acceptance criteria

- Disk and USB identities come from observed devices.
- Existing backup devices are clearly distinguished from wipe targets.
- Missing human values are explicit, not placeholders silently usable in production.

## Comments

Read-only observed facts are recorded in `docs/research/household-hardware-inventory.md`. Both NVMe devices passed SMART with zero media errors, both current md members were healthy, and both existing EFI payloads were present.

The attached SanDisk `BALAUR_BACKUP` device is the existing 123,009,761,280-byte backup and is explicitly excluded from provisioning.

Still needed from the Owner:

- Attach the two new nominal 256 GB USB devices later for identity capture.
- Select SMTP relay and alert destination; implementation remains provider-neutral until then.
- Identify client devices that need the Caddy CA.

Applied the accepted defaults: Alex may write shared media while both owners may read it; both current Alex SSH public keys remain; Andreea has no SSH or local TTY login.
