# Rebuild the host baseline and test seams

Status: ready-for-agent
Blocked by: 01, 03

## Objective

Create a headless target composition and focused test structure without yet provisioning disks.

## Work

- Pin Linux 6.18.
- Remove target imports for desktop/VNC, FastFlowLM, and host-level personal applications.
- Retain nixarr only if it remains the simplest verified fail-closed qBittorrent design.
- Split monolithic tests into storage, access/networking, shared-services, personal-containers, backup, and monitoring checks.
- Keep old dirty legacy files unimported until final cleanup rather than rewriting unrelated WIP.

## Acceptance criteria

- `nix flake check` and full host build pass.
- No desktop, VNC, FastFlowLM, Qwen3.6, host Trilium, or host Paperless units evaluate.
- Tests have focused ownership so later tickets do not all modify one assertion block.

## Comments
