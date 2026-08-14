# Implement users and sops-nix secret boundaries

Status: needs-info
Blocked by: 02, 04, 06

## Objective

Establish host authority and deliver only owner-specific credentials to each personal stack.

## Work

- Keep Alex as SSH-key administrator; remove unrestricted passwordless sudo unless explicitly retained by the human.
- Create Andreea as a normal user without sudo, wheel, SSH keys, or SSH admission.
- Add sops-nix and age recipient configuration.
- Separate host, Alex, and Andreea encrypted secret sets.
- Deliver secrets through credentials/read-only mounts, never the Nix store.
- Reject plaintext secret files in checks.

Human work: generate age/recovery keys and populate encrypted secret payloads.

## Acceptance criteria

- Containers cannot access the host age private key or the other owner's secrets.
- No plaintext secret is tracked or copied to the Nix store.
- Alex's tested recovery access is documented before SSH/sudo hardening deploys.

## Comments

The agent-wiring portion was implemented on 2026-08-14, but the issue is intentionally not Completed because all human-owned credential material remains absent.

Implementation evidence:

- Pinned sops-nix at `a8627b21b9107c5711c96b84f32a9a4b3d45295f`, made it follow the repository nixpkgs, and imported its NixOS module.
- Added `modules/secrets.nix` with the dedicated `/var/lib/sops-nix/key.txt` age identity, age and GnuPG SSH-key fallback disabled, automatic age-key generation disabled, root-only runtime directories, distinct typed host/Alex/Andreea policy roots, and assertions preventing global/key/cross-owner secret-root container binds. No sops secret, template, recipient, encrypted file, or default sops file is declared.
- Added the fail-closed onboarding contract in `secrets/README.md`, a deliberately unusable recipient-free `.sops.yaml.example`, and targeted private-material gitignore patterns. No fake ciphertext or placeholder recipient was created. A wizard was not authored because encrypted file paths and secret schema do not yet exist; the README records that gate and the requirements for a later safe wizard.
- Finalized identity boundaries that require no unknown credential: both observed Alex SSH keys remain exact; only Alex is admitted by SSH; Andreea is a dynamic-ID normal ownership/SMB account with locked Unix password, nologin shell, no keys, no wheel, and no sudo rule. Both owners' ZFS home/apps mounts receive owner-specific `0700` tmpfiles policy without changing issue 06's mount ownership.
- Added `balaur.access.bootstrapPasswordlessSudo`, defaulting to the existing temporary NOPASSWD rule. An assertion prevents disabling it before `alex.hashedPasswordFile` exists, and a deployment-blocker warning plus tests make the non-final state visible. Alex's password hash was not generated or guessed.
- Tests assert exact identity boundaries, dynamic owner IDs, ZFS runtime ownership/local-login denial, dedicated age-only key sourcing, no configured/encrypted payloads, distinct owner/host roots, no container exposure, and unresolved bootstrap sudo.
- `nix flake check -L path:$PWD` passed, including the disposable disko VM; the full `nixosConfigurations.balaur.config.system.build.toplevel` build passed with `--no-link`; nixfmt and `git diff --check` passed. The explicit `path:` form was required to test newly created untracked files without staging them.

Remaining human inputs/actions:

1. Generate a dedicated age identity on trusted offline storage, retain the private recovery identity offline, and provide only its real public recipient for the committed `.sops.yaml`; then install a controlled private-key copy at `/var/lib/sops-nix/key.txt` with root-only permissions when deployment is authorized.
2. Approve the concrete host/Alex/Andreea encrypted file paths and per-consumer secret schema, then create the three real sops-encrypted payloads. No schema or payload is guessed in this ticket.
3. Choose Alex's new Unix password in a human-controlled session, create its yescrypt hash directly through the encrypted workflow, declare its runtime file, and wire `users.users.alex.hashedPasswordFile`.
4. In an authorized recovery session, deploy/test a second Alex SSH session and password-authenticated sudo while retaining the first session; only then set `balaur.access.bootstrapPasswordlessSudo = false` and verify again.

Issue 16 remains blocked until all four steps are complete and the bootstrap warning is gone.
