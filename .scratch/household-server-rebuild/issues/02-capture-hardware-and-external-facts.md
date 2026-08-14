# Capture hardware and external-system facts

Status: ready-for-human
Blocked by: 01

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
