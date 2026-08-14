# Implement users and sops-nix secret boundaries

Status: ready-for-agent
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
