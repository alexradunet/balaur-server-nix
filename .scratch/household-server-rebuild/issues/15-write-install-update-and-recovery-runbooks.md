# Write installation, update, and recovery runbooks

Status: needs-info
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

- 2026-08-16: Added guarded draft install, update/migration, and recovery runbooks plus flake-checked documentation invariants. The install document records exact observed NVMe identities and safe observations but intentionally contains no physical disko or `nixos-install` invocation. Recovery stops before untested md/ZFS/root mutation. The Owner deferred issue 14 until both new owner USB devices exist, so USB provisioning, Borg recovery, quarterly restores, and the complete offline package remain blocked.
- Safety incident during drafting: an unprivileged attempt to inspect the generated `diskoScript` with unsupported `--help` entered the script's destructive path. Every displayed unmount, wipe, and md-stop operation was denied for lack of privilege. Immediate read-only verification found all filesystems still mounted, all three current md arrays clean `[UU]`, and both GPT partition tables unchanged. The runbook now states that generated disko outputs have no safe help/dry-run interface and must never be invoked for inspection. No privileged destructive command was run.
- This ticket remains `needs-info` pending issue 14, selected/hash-verified installer media, completed age/sops and sudo recovery onboarding, a verified offline recovery package, reviewed physical install/replacement/root-only recovery commands, router/client facts, and dated issue-16/17 physical rehearsals.
