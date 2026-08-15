# Implement isolated Alex and Andreea containers

Status: needs-info
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

The safe non-credential implementation was completed on 2026-08-14. The issue remains `needs-info`: both production containers and all personal application units are fail-closed until the human age/sops and fresh-onboarding gates below are complete.

Implementation evidence:

- `modules/personal-containers.nix` parameterizes exactly `alex-personal` and `andreea-personal`. Both are ephemeral, identity-user-namespaced NixOS containers with distinct point-to-point links (`10.231.12.1/10.231.12.2` and `10.231.13.1/10.231.13.2`), no LAN bridge, `restartIfChanged = false`, equal CPU/IO weight 100, equal systemd-oomd memory-pressure policy, and no guessed `MemoryMax`.
- Each container binds only its owner's complete `/srv/people/<owner>/apps` tree writable at `/srv/personal`, exact `/home/<owner>/files/paperless-consume` writable, and exact owner runtime secret root read-only. `privateUsers = "identity"` is deliberate because pinned plain binds have no safe writable id-map interface. Explicit service IDs and distinct consume-group GIDs are used. The app-root ACL grants root initialization access and execute-only traversal to those fixed service IDs; the owner app root, service-owned subdirectories, and absent cross-owner binds remain the isolation boundary.
- Host preflight requires both owner ZFS mountpoints, exact owner-root ownership/ACLs, canonical non-symlinked files/consume paths on the owner home mount, regular root-owned `0400`/`0600` runtime files, and the protected exact `approved-versions` marker before container startup or app-path preparation. An inner marker/credential gate is required by every native app, setup/migration unit, PostgreSQL, and Redis.
- The pinned native modules/packages are TriliumNext 0.102.2, Paperless-ngx 2.20.15 with one task worker and PostgreSQL/Unix-socket Redis, Firefly III 6.6.3 with PostgreSQL, Data Importer 2.3.4, and Open WebUI 0.11.0 with SQLite. PostgreSQL is 17.10 and Redis 8.8.1. Open WebUI's cache/model paths are redirected into a nested tmpfs so they never enter protected owner snapshots. No OCI runtime, host singleton, legacy state, or old path remains. Open WebUI is the sole narrowly allowlisted unfree package.
- Caddy conditionally registers notes/paperless/budget/chat for each ready owner and the authenticated Importer route only after its second gate. Raw app/DB/cache ports remain off LAN. The host forward policy denies cross-owner, LAN, and host-service access while allowing router DNS, NTP, and HTTPS egress. Importer receives its own private `home.arpa` route only after its separate post-Firefly token gate, avoiding an unproven path-prefix wrapper.
- When issue 10 is ready, each ready owner container independently receives one owner-address-bound systemd socket forwarder to loopback llama TCP 8081. Input rules restrict each source to its own host-side address; each container sees only its own owner secret root/key. There is no broad listener, raw Caddy route, or combined key-file bind.
- Evaluation tests cover the disabled default and a generated-path ready fixture with all five real native modules twice, exact binds/addresses/state, gates, separate databases, Caddy routes, and resource policy. `tests/personal-containers-vm.nix` uses runtime-generated disposable values and fake app/llama servers to exercise nested-container mounts, Caddy-only ingress, cross-owner file/secret/route denial, consume behavior, separate state, equal cgroups, owner llama forwarding, and missing-mount failure without putting test values in production outputs.

Exact remaining human gates:

1. Complete issue 07's dedicated age identity, public recipient, `.sops.yaml`, three encrypted authority files, installed host identity, Alex password-hash workflow, and final sudo recovery validation. No production personal payload can exist before this.
2. Create separate Alex and Andreea payload keys matching `secrets/README.md`: Paperless admin password; persistent Firefly `APP_KEY`; 32-character Firefly cron token; persistent Open WebUI secret key and owner-admin password; and, after fresh Firefly onboarding, that owner's Importer access token and separate Caddy proxy password. Select each owner's non-secret Open WebUI login email as well. Never copy values between owners or reuse VM fixtures.
3. For one owner at a time, write the exact five-line `approved-versions` marker under that mounted apps root only after reviewing/taking the required cold snapshot, wire real sops runtime paths, set base readiness, verify the closed Open WebUI owner-admin bootstrap, and complete fresh Trilium/Firefly browser onboarding. Then create the Firefly token and set Importer readiness. Do not restore legacy databases, SQLite, media, or credentials.
4. Keep Enable Banking credentials and configuration entirely deferred to issue 17. Bank linking/SCA, account mapping, initial-history/duplicate checks, BT behavior, scheduling, and 80-day reauthorization are not part of this issue.
5. Keep Open WebUI inference unavailable until issue 10's physical four-model benchmark selects a passing preset/memory target and separate owner llama keys exist. Then rerun forwarding/key-isolation checks on the physical host before enabling either chat workflow.
6. After authorized deployment, validate the real ZFS bind ownership, both private Caddy routes and clients, raw-port closure, cross-owner denial in both directions, and Paperless consume behavior. No issue-17 onboarding claim is made here.
