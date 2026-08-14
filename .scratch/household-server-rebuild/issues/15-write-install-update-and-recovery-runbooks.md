# Write installation, update, and recovery runbooks

Status: ready-for-agent
Blocked by: 05, 08, 09, 10, 12, 13, 14

## Objective

Make destructive installation and recovery reviewable by a human who does not remember implementation details.

## Work

Document exact install revision/media; typed NVMe serial confirmation; dual-EFI/md/ZFS degraded recovery; age and Borg key recovery; deliberate application migration/update procedure; ASUS DNS/WireGuard checks; Caddy CA enrollment; USB provisioning; quarterly restore drill; and the offline recovery package manifest. State clearly that current internal service/media data is not restored.

## Acceptance criteria

- Commands use verified by-id/UUID values or stop for human substitution.
- Every destructive step has a preceding observation and abort point.
- Recovery covers either disk failing, motherboard loss, lost root filesystem, lost USB, and lost credential scenarios.
- No secret value appears in documentation.

## Comments
