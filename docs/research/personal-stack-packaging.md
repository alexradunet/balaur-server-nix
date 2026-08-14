# Personal-stack packaging and operations

Verified: 2026-08-14

This resolves issue 11 against pinned nixpkgs
`ee48b147c18c7de1e6ec97dc74792be42724bed1` on `x86_64-linux`. It is a
research result, not an implementation or a bank-credential test. No real bank
credentials were used.

## Decision

Use the native NixOS modules and native packages for all five applications.
Use one native PostgreSQL server per owner container for Paperless and Firefly,
the Paperless module's native named Redis server, and SQLite as supplied by
Trilium and Open WebUI. There is no current need for an OCI image. Native
packages give a Nix-store-pinned closure, systemd ordering/hardening and direct
paths; an OCI image would add a second update mechanism and require a separately
reviewed digest without solving a missing-package problem.

Each application option is a singleton *within one NixOS evaluation* (fixed
names such as `services.paperless`, `services.firefly-iii`, and fixed systemd/PHP
pool names). This is not a blocker: `containers.alex.config` and
`containers.andreea.config` are separate NixOS evaluations, so each may contain
one instance. Do not attempt two instances in one container and do not leave a
host instance enabled. The pinned container module evaluates each declarative
container configuration separately and inherits pinned nixpkgs
([source](https://github.com/NixOS/nixpkgs/blob/ee48b147c18c7de1e6ec97dc74792be42724bed1/nixos/modules/virtualisation/nixos-containers.nix#L530-L651)).

## Pinned component matrix

Versions below were evaluated from the locked flake, not inferred from a branch
name. PostgreSQL evaluates to 17.10, Redis to 8.8.1, and both Firefly packages
use PHP 8.5.9.

| Component | Exact pinned package and native module | Recommended internal listener | Required state/dependency | Startup mutation and backup operation |
| --- | --- | --- | --- | --- |
| TriliumNext | `pkgs.trilium-server` 0.102.2 (`trilium-next-server` is only an alias); `services.trilium-server` | Module default `127.0.0.1:8080`; use container address and 8080 for host Caddy | SQLite in `/var/lib/trilium/document.db`; no PostgreSQL/Redis | Automatically migrates an older DB at application startup. Cold-snapshot all of `/var/lib/trilium`; built-in DB copies are useful secondary recovery points. |
| Paperless-ngx | `pkgs.paperless-ngx` 2.20.15; `services.paperless` | `28981` | PostgreSQL 17.10 plus named Redis 8.8.1; set `PAPERLESS_TASK_WORKERS=1` | The module runs Django `migrate` on first start or package-version change. Cold snapshot DB, data and media; optional `document_exporter` is portable only to the same Paperless version. |
| Firefly III | `pkgs.firefly-iii` 6.6.3; `services.firefly-iii` | PHP-FPM behind native nginx, port 80 selected by the budget virtual host | PostgreSQL 17.10; no required Redis | `firefly-iii-setup` calls `firefly-iii:upgrade-database` before PHP-FPM on every service start (normally idempotent at the current schema). Cold snapshot PostgreSQL and `/var/lib/firefly-iii`. |
| Firefly III Data Importer | `pkgs.firefly-iii-data-importer` 2.3.4; `services.firefly-iii-data-importer` | Same nginx port 80, selected by a distinct importer virtual host | File-backed state; no separate DB/cache required | Setup runs package discovery/config-cache generation, not a schema migration. Cold snapshot `/var/lib/firefly-iii-data-importer`; retain downloaded import configurations and session mappings as sensitive state. |
| Open WebUI | `pkgs.open-webui` 0.11.0; `services.open-webui` | Module default is 8080, which conflicts with Trilium; set 3000 | Use its SQLite DB for this single-user/single-replica case; no Redis/PostgreSQL needed | Alembic migrations default on at every app startup. Cold snapshot its `data/`; keep `WEBUI_SECRET_KEY`. Exclude downloaded model caches. |

The exact package versions are declared by the pinned expressions:
[Trilium](https://github.com/NixOS/nixpkgs/blob/ee48b147c18c7de1e6ec97dc74792be42724bed1/pkgs/by-name/tr/trilium-server/package.nix#L8-L22),
[Paperless](https://github.com/NixOS/nixpkgs/blob/ee48b147c18c7de1e6ec97dc74792be42724bed1/pkgs/by-name/pa/paperless-ngx/package.nix#L31-L42),
[Firefly](https://github.com/NixOS/nixpkgs/blob/ee48b147c18c7de1e6ec97dc74792be42724bed1/pkgs/by-name/fi/firefly-iii/package.nix#L13-L28),
[Importer](https://github.com/NixOS/nixpkgs/blob/ee48b147c18c7de1e6ec97dc74792be42724bed1/pkgs/by-name/fi/firefly-iii-data-importer/package.nix#L16-L29), and
[Open WebUI](https://github.com/NixOS/nixpkgs/blob/ee48b147c18c7de1e6ec97dc74792be42724bed1/pkgs/by-name/op/open-webui/package.nix#L9-L24).
`open-webui` has a custom non-free license in pinned nixpkgs, so issue 12 must
allowlist that package explicitly rather than globally allowing all unfree
software
([package metadata](https://github.com/NixOS/nixpkgs/blob/ee48b147c18c7de1e6ec97dc74792be42724bed1/pkgs/by-name/op/open-webui/package.nix#L246-L267)).

### Local module facts

- Trilium exposes `dataDir`, `environmentFile`, host and port; its module writes
  `TRILIUM_DATA_DIR` and runs one fixed `trilium-server` unit
  ([module](https://github.com/NixOS/nixpkgs/blob/ee48b147c18c7de1e6ec97dc74792be42724bed1/nixos/modules/services/web-apps/trilium.nix#L31-L97),
  [unit](https://github.com/NixOS/nixpkgs/blob/ee48b147c18c7de1e6ec97dc74792be42724bed1/nixos/modules/services/web-apps/trilium.nix#L126-L151)).
- Paperless exposes separate `dataDir`, `mediaDir`, `consumptionDir`, secret
  environment/password files and `database.createLocally`; when Redis is not
  overridden it creates `services.redis.servers.paperless` on a Unix socket
  ([module options](https://github.com/NixOS/nixpkgs/blob/ee48b147c18c7de1e6ec97dc74792be42724bed1/nixos/modules/services/misc/paperless.nix#L136-L334),
  [dependencies](https://github.com/NixOS/nixpkgs/blob/ee48b147c18c7de1e6ec97dc74792be42724bed1/nixos/modules/services/misc/paperless.nix#L418-L451)). Upstream's default task-worker count is one; declare
  `PAPERLESS_TASK_WORKERS=1` anyway so the requirement cannot drift
  ([configuration](https://docs.paperless-ngx.com/configuration/#PAPERLESS_TASK_WORKERS)).
- The Firefly modules expose `dataDir`, package, nginx/PHP pool and free-form
  settings. Settings ending in `_FILE` are read at runtime and exported without
  `_FILE`, keeping secret values out of the store
  ([Firefly module](https://github.com/NixOS/nixpkgs/blob/ee48b147c18c7de1e6ec97dc74792be42724bed1/nixos/modules/services/web-apps/firefly-iii.nix#L18-L42),
  [Importer module](https://github.com/NixOS/nixpkgs/blob/ee48b147c18c7de1e6ec97dc74792be42724bed1/nixos/modules/services/web-apps/firefly-iii-data-importer.nix#L18-L37)).
- Open WebUI exposes `stateDir`, host, port, environment and
  `environmentFile`. The pinned module maps `data`, `hf_home`,
  `transformers_home` and `static` below `stateDir` and performs a one-time old
  layout move in `preStart`
  ([module](https://github.com/NixOS/nixpkgs/blob/ee48b147c18c7de1e6ec97dc74792be42724bed1/nixos/modules/services/misc/open-webui.nix#L14-L82),
  [paths/preStart](https://github.com/NixOS/nixpkgs/blob/ee48b147c18c7de1e6ec97dc74792be42724bed1/nixos/modules/services/misc/open-webui.nix#L86-L124)).

## Per-owner container and storage design

Use the same parameterized module twice, with only owner, addresses, hostnames,
mount sources and secret sources differing.

- `ephemeral = true`: the container root is recreated below `/run`, so mutable
  application state cannot silently become a backup dependency on md root.
- `privateNetwork = true` with a distinct static point-to-point veth address for
  each owner. Host Caddy is the only caller of web listeners. Give containers
  outbound NAT for package-independent HTTPS calls (banks and Open WebUI
  features), but host firewall rules must reject owner-to-owner forwarding.
- Use `privateUsers = "identity"`: this retains a user namespace/capability
  boundary while avoiding unsafe ownership guesses for writable bind mounts and
  root-only runtime secrets. `pick` is stronger UID remapping, but the pinned
  `bindMounts` type has only source, destination and read-only fields and emits
  plain `--bind[-ro]`; it has no declarative id-map option
  ([options](https://github.com/NixOS/nixpkgs/blob/ee48b147c18c7de1e6ec97dc74792be42724bed1/nixos/modules/virtualisation/nixos-containers.nix#L765-L799),
  [bind implementation](https://github.com/NixOS/nixpkgs/blob/ee48b147c18c7de1e6ec97dc74792be42724bed1/nixos/modules/virtualisation/nixos-containers.nix#L346-L405)). Do not switch to `pick` until an id-mapped writable-bind VM test proves ownership and restore behavior on ZFS.
- Bind only exact owner paths. Never bind `/home`, `tank/users`, the other
  owner's tree, the whole host `/run/secrets`, or the host PostgreSQL socket.
  The pinned module adds bind sources to the container unit's
  `RequiresMountsFor`, which is needed to fail closed when ZFS is absent
  ([unit generation](https://github.com/NixOS/nixpkgs/blob/ee48b147c18c7de1e6ec97dc74792be42724bed1/nixos/modules/virtualisation/nixos-containers.nix#L1082-L1094)).

Recommended mount classification (same container paths for both owners):

| Container path | Class | Contents/restore significance |
| --- | --- | --- |
| `/var/lib/postgresql/17` | **protected** | Paperless and Firefly databases; PostgreSQL-major-specific physical state |
| `/var/lib/trilium` | **protected** | `document.db`, config and built-in DB backups |
| `/var/lib/paperless` | **protected** | index/classifier state, `src-version`, generated secret, media and optional exports |
| `/srv/paperless/consume` | **protected owner-home bind** | only `/home/<owner>/files/paperless-consume`; private SMB inbox, never the complete home |
| `/var/lib/firefly-iii` | **protected** | uploads/exports, Laravel/Passport keys and writable state |
| `/var/lib/firefly-iii-data-importer/storage` | **protected, banking-sensitive** | saved configurations, jobs, mappings, uploads and Enable Banking session IDs |
| `/var/lib/open-webui/data` | **protected** | `webui.db`, uploads and vector DB; put `data/cache` on a nested disposable mount |
| `/var/lib/redis-paperless`, `/var/cache/paperless` | **disposable** | queue/cache; disable Redis persistence if testing confirms clean shutdown leaves no required work |
| `/var/lib/open-webui/hf_home`, `/var/lib/open-webui/transformers_home`, `/var/lib/open-webui/static` | **disposable cache/model** | redownload/rebuild; exclude from snapshots and USB |
| Trilium log/tmp, app logs, OCR temp and system `/tmp` | **disposable tmpfs/log** | set `TRILIUM_LOG_DIR`/`TRILIUM_TMP_DIR` outside its protected data directory |

Upstream confirms Trilium's data directory contents and its independently
relocatable document, backup, log and temp paths
([v0.102.2 data-directory docs](https://github.com/TriliumNext/Trilium/blob/v0.102.2/docs/User%20Guide/User%20Guide/Installation%20%26%20Setup/Data%20directory.md)).
Open WebUI documents `webui.db`, `uploads/`, `vector_db/` and `cache/` under its
data directory and explicitly treats cache as excludable
([backup guide](https://docs.openwebui.com/tutorials/maintenance/backups/#files-in-persistent-data-store)).

PostgreSQL should use local Unix-socket peer authentication with separate roles
and databases (`paperless` and `firefly-iii`), no TCP listener and no shared
cross-owner server. Redis should remain the Paperless-only Unix-socket named
instance. Open WebUI upstream explicitly endorses SQLite on locally attached
NVMe for a single-user/single-replica home-lab deployment; PostgreSQL is needed
for replicas/network storage, neither of which applies
([database configuration](https://docs.openwebui.com/reference/env-configuration/#database_url)).

## Migration and update gate

Merely pinning nixpkgs is insufficient. Three apps migrate at startup, and the
pinned container option defaults `restartIfChanged = true`
([option](https://github.com/NixOS/nixpkgs/blob/ee48b147c18c7de1e6ec97dc74792be42724bed1/nixos/modules/virtualisation/nixos-containers.nix#L830-L845)).
Issue 12 should implement both gates below:

1. Set each owner container's `restartIfChanged = false`. An ordinary host
   `nixos-rebuild switch` may update the desired closure but must not restart a
   running personal stack.
2. Assert evaluated application versions against an explicit
   `approvedVersions` record, and require a protected runtime marker containing
   the same five versions before **any** application or migration/setup unit can
   start. A changed package therefore leaves apps stopped after a reboot rather
   than silently migrating. Updating the assertion/marker is a human-approved
   maintenance action, not an automatic activation script.

Approved update sequence: build/test without changing the runtime marker;
notify owner; quiesce stack; take the cold pre-migration snapshot and verify it;
update the marker; start only that owner container; wait for setup/migrations and
health checks; test sign-in/import; retain the pre-migration snapshot until
rollback is tested. Rollback means restoring both old application closure and
pre-migration state, never starting old code on a newer schema.

Exact triggers:

- Trilium automatically checks and migrates on startup and older versions cannot
  read the migrated DB; it creates a pre-migration backup
  ([v0.102.2 upgrade docs](https://github.com/TriliumNext/Trilium/blob/v0.102.2/docs/User%20Guide/User%20Guide/Installation%20%26%20Setup/Upgrading%20TriliumNext.md),
  [transactional migration source](https://github.com/TriliumNext/Trilium/blob/v0.102.2/apps/server/src/services/migration.ts)).
- Paperless's scheduler `preStart` compares `/var/lib/paperless/src-version` to
  the package version and runs `paperless-ngx migrate` when different
  ([pinned module](https://github.com/NixOS/nixpkgs/blob/ee48b147c18c7de1e6ec97dc74792be42724bed1/nixos/modules/services/misc/paperless.nix#L494-L521)).
- Firefly's required setup unit runs `firefly-iii:upgrade-database` before
  PHP-FPM
  ([pinned module](https://github.com/NixOS/nixpkgs/blob/ee48b147c18c7de1e6ec97dc74792be42724bed1/nixos/modules/services/web-apps/firefly-iii.nix#L25-L42),
  [ordering](https://github.com/NixOS/nixpkgs/blob/ee48b147c18c7de1e6ec97dc74792be42724bed1/nixos/modules/services/web-apps/firefly-iii.nix#L310-L325)).
- The importer setup only refreshes Laravel package/config caches
  ([pinned module](https://github.com/NixOS/nixpkgs/blob/ee48b147c18c7de1e6ec97dc74792be42724bed1/nixos/modules/services/web-apps/firefly-iii-data-importer.nix#L25-L35)).
- Open WebUI v0.11.0 has `ENABLE_DB_MIGRATIONS=True` by default and executes
  Alembic `upgrade head` during import/startup
  ([environment source](https://github.com/open-webui/open-webui/blob/v0.11.0/backend/open_webui/env.py),
  [migration source](https://github.com/open-webui/open-webui/blob/v0.11.0/backend/open_webui/config.py#L62-L79)). Keep one worker and the runtime marker; do not rely on setting migrations permanently false, which can start code against an old schema.

## Backup and restore contract

The consistency primitive for issue 14 should be a **cold ZFS snapshot**, not a
collection of app-specific live copies:

1. Acquire the owner's backup/update lock and stop only that owner's container
   with a graceful timeout. A failure to stop is a backup failure.
2. Atomically snapshot the explicit protected owner-home/app dataset allowlist;
   do not recurse into disposable descendants. The stopped PostgreSQL and SQLite
   files are then crash-free and mutually stable.
3. In an unconditional trap, restart the owner container whether snapshot or
   Borg later succeeds or fails. Wait for health before reporting service
   restored.
4. Borg reads a read-only snapshot/clone, never live paths. Include the encrypted
   configuration needed to recreate this owner and the approved-version record;
   exclude all paths marked disposable above.
5. Verify the Borg archive, destroy the temporary snapshot/clone, unmount, and
   report safe removal only after all cleanup succeeds.

This preserves the simplest authoritative restore. Logical PostgreSQL dumps may
be generated as an additional portability aid, but they are not required for
consistency and must never replace the cold database snapshot. Paperless's
native exporter may be run periodically/quarterly as a second recovery format;
its docs warn that importer and exporter versions must match
([Paperless administration](https://docs.paperless-ngx.com/administration/#exporter)).
Firefly has no built-in backup routine and requires DB, upload/storage and the
same `APP_KEY`
([Firefly backup guidance](https://docs.firefly-iii.org/how-to/firefly-iii/advanced/backup/)).
Trilium's own daily/weekly/monthly/pre-migration DB files are secondary copies;
its documented restore stops Trilium, replaces `document.db`, removes WAL/SHM
and fixes permissions
([v0.102.2 backup docs](https://github.com/TriliumNext/Trilium/blob/v0.102.2/docs/User%20Guide/User%20Guide/Installation%20%26%20Setup/Backup.md)).
Open WebUI recommends cold filesystems for integrity
([backup guide](https://docs.openwebui.com/tutorials/maintenance/backups/#rsync-job-with-container-interruption)).

Restore prerequisites:

- recreate exact mount topology and permissions before container start;
- initially select the archived approved app versions and PostgreSQL major 17
  closure; restore `/var/lib/postgresql/17` only to compatible PostgreSQL 17;
- restore each app's protected state and owner-only encrypted secrets, especially
  Firefly `APP_KEY`, Open WebUI `WEBUI_SECRET_KEY`, database/import tokens and
  Enable Banking private key;
- leave disposable mounts empty and let caches/models rebuild;
- start behind the migration marker, health-test, then deliberately upgrade;
- bank consent is external state: a restored session may be expired/revoked and
  must then be reauthorized. A backup cannot recreate SCA or consent.

## Secret delivery

Keep one sops secret namespace per owner. On the host, decrypt only that owner's
files below a dedicated root-only runtime directory. Bind that directory
read-only into only that owner's container; a root oneshot inside the container
copies individual values into a tmpfs runtime directory with service-specific
owner/mode before services start. Never bind the repository age key, the other
owner directory, or a common decrypted secret directory.

Use module-native file interfaces: Trilium `environmentFile`; Paperless
`environmentFile`/`passwordFile`; Firefly and Importer settings with `_FILE`
(including `APP_KEY_FILE`, access token, `ENABLE_BANKING_APP_ID_FILE` and
`ENABLE_BANKING_PRIVATE_KEY_FILE`); Open WebUI `environmentFile`. Preserve the
Open WebUI secret key because upstream uses it for JWTs and encrypted tokens
([configuration](https://docs.openwebui.com/reference/env-configuration/#webui_secret_key)).
The Enable Banking PEM is an application-wide credential capable of accessing
that application's sessions, so it must never be exposed to a browser, logs,
Nix store or the other owner
([Enable Banking authentication](https://enablebanking.com/docs/api/reference/#authentication)).

Issue 12 must test source directory mode, missing-secret failure, container
service readability, absence from `/nix/store`, and both directions of
cross-owner denial. `privateUsers="identity"` makes exact bind isolation and
service sandboxing—not UID shifting—the security boundary; document this
accepted tradeoff and retain the VM test.

## Networking constraints for issue 12

- Give each container a distinct static `localAddress`/`hostAddress`; without a
  bridge the pinned module establishes point-to-point routing and defaults to
  `/32`
  ([options](https://github.com/NixOS/nixpkgs/blob/ee48b147c18c7de1e6ec97dc74792be42724bed1/nixos/modules/virtualisation/nixos-containers.nix#L455-L491)). Do not bridge containers onto the LAN.
- Caddy targets container IPs directly: 8080 Trilium, 28981 Paperless, 3000 Open
  WebUI, and nginx port 80 with preserved Host for Firefly/Importer virtual
  hosts. Open only these from the host-side veth address, not from LAN/WAN.
- Container egress permits DNS, NTP, HTTPS and only the owner's credentialed
  llama proxy endpoint. Reject either owner subnet reaching the other owner,
  host SMB paths, host admin services or raw llama backend.
- Put budget and importer names in container `/etc/hosts` at loopback so the
  Importer can reach Firefly's nginx virtual host internally without routing
  through Caddy. Use the external HTTPS budget/importer URL only for browser
  redirects/vanity URL. Production Enable Banking callback must be the exact
  HTTPS `https://<owner-importer>/eb-callback`; it need not be public
  ([Firefly tutorial](https://docs.firefly-iii.org/tutorials/data-importer/eb/#create-an-application)).
- Bind sources must exist and be mounted before container start. Every durable
  writable path must be an exact protected/disposable bind; temp is tmpfs.

## Enable Banking: current practical boundary

### Verified support and owner separation

Enable Banking's public `GET /api/aspsps?country=RO` response was checked on
2026-08-14. It currently reports:

| Connector (`name`, `country`) | Personal redirect | Maximum advertised consent | Beta | Required PSU headers |
| --- | --- | ---: | --- | --- |
| `Revolut`, `RO` | yes | 15,552,000 s (180 days) | no | none listed |
| `Banca Comerciala Romana`, `RO` | yes | 15,552,000 s | **yes** | none listed |
| `Banca Transilvania`, `RO` | yes | 15,552,000 s | **yes** | `psu-ip-address` |

This is stronger and more current evidence than the prose market page:
[public ASPSP response](https://enablebanking.com/api/aspsps?country=RO) and
[Romania market flow](https://enablebanking.com/docs/markets/ro/). Enable
Banking says beta integrations are usable but have not yet accumulated enough
traffic to remove the flag
([FAQ](https://enablebanking.com/docs/faq/#what-does-the-beta-flag-in-the-aspsp-list-mean)). Therefore pilot Revolut, then BCR, then BT, and treat the live API response and a real owner-authorized test as the final availability check; bank names/flags are not stable identifiers.

Create **one separate production/restricted Enable Banking application and RSA
private key per owner**, and link all of that owner's intended accounts. One
owner application may cover that owner's three banks; do not share one app/key
between owners. Restricted mode returns only accounts explicitly linked in the
control panel
([Enable Banking FAQ](https://enablebanking.com/docs/faq/#why-does-my-restricted-application-receive-an-empty-list-of-accounts-after-successful-authorisation),
[Importer setup](https://docs.firefly-iii.org/tutorials/data-importer/eb/)). Use
account-information access only. Do not implement or request PIS: production
payment initiation requires separate PISP enablement and is outside the Data
Importer flow
([API reference](https://enablebanking.com/docs/api/reference/#payments)).

### BT IP, history, duplicates and schedule

Pinned Importer 2.3.4 natively supports Enable Banking credentials and has
`ENABLE_BANKING_IMPORT_IP_HEADER` plus `ENABLE_BANKING_IMPORT_IP`. When enabled,
it validates the configured value as a public IP and sends it as
`PSU-IP-Address`; `autodetect` calls `icanhazip.com`
([v2.3.4 environment](https://github.com/firefly-iii/data-importer/blob/v2.3.4/.env.example#L111-L132),
[request source](https://github.com/firefly-iii/data-importer/blob/v2.3.4/app/Services/EnableBanking/Request/Request.php#L108-L118)). For BT, set the
header flag and the household's actual public egress IP. This is **not** Caddy's
`X-Forwarded-For` and not the container address. If WAN IP is dynamic,
`autodetect` is the app-native fallback but discloses a request to an external
service and is not a guarantee; validate BT after each WAN-IP change. Enable
Banking says scheduled/background retrieval should send no PSU headers, while
interactive retrieval should send all headers required by that ASPSP
([PSU-header FAQ](https://enablebanking.com/docs/faq/#what-are-the-psu-headers-in-the-endpoints-for-fetching-account-details-balances-and-transactions-used-for)). Importer 2.3.4 exposes only one global IP-header toggle, so it cannot perfectly distinguish interactive BT calls from daily background calls. This is a native-integration limitation; test bank rate limits and disable BT daily automation if it causes 422/429 responses.

Immediately after each authorization, manually select **Import everything** and
inspect balances/date bounds before the commonly short initial-history window
closes. Enable Banking says many banks expose the longest history only for about
an hour, then may restrict retrieval to 90 days, and recommends
`strategy=longest` for first fetch
([history FAQ](https://enablebanking.com/docs/faq/#why-is-only-90-days-of-transactions-history-available),
[strategy FAQ](https://enablebanking.com/docs/faq/#can-i-find-somewhere-how-long-history-of-transactions-an-aspsp-provides)). However Importer 2.3.4's request sends date bounds and pagination but **does not send the Enable Banking `strategy` parameter**
([source](https://github.com/firefly-iii/data-importer/blob/v2.3.4/app/Services/EnableBanking/Request/GetTransactionsRequest.php)). Thus “all available history” cannot be guaranteed by the native integration. A guaranteed `strategy=longest` fetch would require an upstream fix or a custom direct-API importer and is explicitly not safely automatable now.

For duplicate safety, keep content/cell-based duplicate detection enabled, map
accounts, run a small overlap twice and compare counts before scheduling. The
provider notes that `entry_reference` is usually—but not universally—usable and
may be absent/duplicated
([transaction identifiers](https://enablebanking.com/docs/faq/#are-there-unique-identifiers-for-transactions)). Importer 2.3.4's
`IGNORE_DUPLICATE_ERRORS=true` suppresses duplicate complaints; it does not make
detection correct
([environment](https://github.com/firefly-iii/data-importer/blob/v2.3.4/.env.example#L176-L190)). Its own v2.3.2 changelog warns some conversion changes may produce duplicates
([changelog](https://github.com/firefly-iii/data-importer/blob/v2.3.4/changelog.md#v232---2026-04-20)). Keep it false during pilots and review every connector separately.

After validation, daily automation may use a protected, owner-only downloaded
configuration with the local CLI `php artisan importer:import <config.json>` and
a systemd oneshot/timer; do not expose the POST auto-import endpoint. The saved
configuration contains Enable Banking session IDs in 2.3.4 and is sensitive
([configuration source](https://github.com/firefly-iii/data-importer/blob/v2.3.4/app/Services/Shared/Configuration/Configuration.php#L1084-L1089)); upstream documents the CLI/timer flow
([automated imports](https://docs.firefly-iii.org/how-to/data-importer/import/automated/)). The NixOS Importer module supplies no daily bank-import timer, so this timer and failure alert are custom issue-12 integration.

### Consent expiration

Importer 2.3.4 requests `valid_until = +90 days` and does not pass the selected
bank's advertised 180-day maximum into that request
([source](https://github.com/firefly-iii/data-importer/blob/v2.3.4/app/Services/EnableBanking/Request/PostAuthRequest.php#L82-L94)). Therefore create an owner-specific reminder at authorization date +80 days, not +170 days. The reminder can be automated; reauthorization cannot, because bank SCA is a human action. Sessions can also expire early, and reauthorization creates new session/account IDs
([session validity](https://enablebanking.com/docs/faq/#how-long-is-session-validity),
[reauthorization](https://enablebanking.com/docs/faq/#how-should-re-authorisation-be-performed-and-how-to-match-accounts-across-sessions)). After reauthorization, rerun a manual overlap import, match accounts, replace the protected automation configuration, and reset the 80-day reminder. Alert on `EXPIRED_SESSION`; do not silently create or remap a new session.

## Risks and non-automatable items

1. **Migration risk:** Trilium, Paperless, Firefly and Open WebUI mutate schemas
   on startup. Both the no-restart setting and version marker are mandatory.
2. **Bind/user-namespace risk:** `privateUsers="pick"` is not ready with the
   pinned plain-bind interface. Use identity mapping plus exact mount/firewall
   isolation and prove it in both cross-owner directions.
3. **Dynamic-user permissions:** Open WebUI uses `DynamicUser`; issue 12 must VM
   test its protected and nested disposable binds rather than guessing modes.
4. **Bank connector drift:** ASPSP names, beta flags, required headers and bank
   behavior can change independently of Nix. Query the live catalog during
   onboarding and never use real credentials in tests.
5. **Not safely automatable:** bank linking/SCA, initial-history validation,
   account mapping, duplicate acceptance, consent renewal, guaranteed
   `strategy=longest`, and BT behavior under a dynamic public IP require human
   validation or upstream/custom code.
6. **Native gaps:** the Data Importer NixOS module has no Enable Banking timer or
   80-day reminder; Importer 2.3.4 does not expose `strategy=longest` and cannot
   vary PSU headers between interactive and scheduled requests. These are small
   explicit custom systemd integration seams, not reasons to replace the native
   package with an OCI image.
7. **Restore coupling:** physical PostgreSQL restore requires PostgreSQL 17 and
   exact app secrets; app exports/logical dumps are useful secondary formats,
   not substitutes for quarterly restore tests.
