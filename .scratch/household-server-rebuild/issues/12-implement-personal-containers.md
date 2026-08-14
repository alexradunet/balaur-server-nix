# Implement isolated Alex and Andreea containers

Status: ready-for-agent
Blocked by: 06, 07, 08, 10, 11

## Objective

Implement one parameterized personal-stack module and instantiate it twice without cross-owner mounts, networks, credentials, or databases.

## Work

Each declarative NixOS container gets Trilium, Paperless with one OCR worker, Firefly III/importer, Open WebUI, dedicated application databases/roles, owner app storage, private Paperless consume path, equal CPU weight, and memory-pressure controls. Open WebUI instances share only the private llama backend through distinct credentials.

## Acceptance criteria

- No host-level personal application instances remain.
- Each private hostname reaches only its intended instance.
- VM tests prove neither container can read the other owner's files, state, database, or credentials.
- Container root and app writes cannot silently land on md root.
- Automatic app updates/migrations are disabled or explicitly gated.

## Comments
