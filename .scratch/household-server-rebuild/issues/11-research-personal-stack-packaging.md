# Research personal-stack packaging and migration behavior

Status: ready-for-agent
Blocked by: 03, 04

## Objective

Resolve implementation facts for one reproducible NixOS container per owner before coding the reusable stack.

## Work

For Trilium, Paperless-ngx, Firefly III, Firefly Data Importer/Enable Banking, Open WebUI, PostgreSQL/Redis dependencies, determine supported NixOS packaging, singleton limitations, startup migrations, required ports, persistent paths, backup-consistency operations, and secure secret delivery. Verify the Enable Banking flow for Revolut, BCR, and BT without storing bank credentials.

## Acceptance criteria

- Recommend native NixOS services or pinned images per component with a concrete reason.
- List exact data/cache paths and migration triggers.
- Define how ordinary `nixos-rebuild` avoids unapproved schema migrations.
- Define BT client-IP forwarding and 80-day reauthorization mechanics.

## Comments
