# Secret onboarding contract

The repository currently contains **no encrypted payloads, secret declarations, age identity, or Alex password hash**. `modules/secrets.nix` only establishes the fail-closed runtime policy. The host is not deployable in this state.

## Non-negotiable boundaries

- Use a dedicated age identity for sops-nix. SSH host/user keys are never recipients or fallback decryption keys.
- Keep the recovery copy of the age private identity offline. Install only a controlled copy at `/var/lib/sops-nix/key.txt` on the host, owned by `root:root` and mode `0600`; its parent is `0700`.
- Commit only public age recipients in `.sops.yaml` and ciphertext carrying sops metadata. Never commit an age private identity, plaintext secret, password, plaintext password hash, `.env`, private key, or decrypted export; a required password hash belongs only inside sops ciphertext.
- Keep encrypted files separated by authority: one host file, one Alex file, and one Andreea file. A value shared deliberately by host services belongs in the host file; do not duplicate or broaden owner access for convenience.
- Later Nix modules must place decrypted values under the typed policy roots exposed by `config.balaur.secrets.policies`: host, Alex, or Andreea. Bind only one exact owner root read-only into that owner's container. Never bind `/run/secrets`, `/run/balaur-secrets`, or the age key into a container.
- Secret values must be consumed through runtime files/credentials, never interpolated into Nix strings, command lines, logs, or derivations.

## Human onboarding gate

Perform these steps on a trusted machine, with backup media and terminals under the Owner's control:

1. Generate one new dedicated age identity with `age-keygen`, writing it directly to protected offline storage under `umask 077`. Do not reuse an SSH key and do not paste the private identity into this repository, chat, shell history, or a ticket.
2. Derive the public recipient from that offline identity with `age-keygen -y`. Keep the private identity offline; the recipient is public.
3. Copy `.sops.yaml.example` to `.sops.yaml`. Replace the deliberately empty rules with three exact path rules for the future host, Alex, and Andreea encrypted files. Put only the real public recipient from step 2 in those rules. Do not invent or copy a sample recipient. Review and commit `.sops.yaml` because it contains public policy only.
4. Create the three owner-separated files with `sops` only after reviewing the consuming schemas. Issues 08, 09, 10, and 12 now reserve host/owner values, but no encrypted file path or payload is declared yet. Confirm every eventual file has sops metadata and cannot be decrypted without the offline identity. Commit ciphertext only.
5. Provision a controlled copy of the same private identity to `/var/lib/sops-nix/key.txt` as `root:root` mode `0600`. Retain the recovery source offline and disconnected. Do not enable automatic key generation.
6. Once the host secret schema declares Alex's password-hash runtime file, generate a strong new Alex password locally with the human present and create a yescrypt hash using an interactive, no-echo password prompt. Insert the hash directly through the `sops` editor; do not save either plaintext password or a decrypted/hash scratch file in the repository. Wire that runtime file to `users.users.alex.hashedPasswordFile`.
7. Build first. In an already authenticated recovery session, deploy only after the issue-16 gates authorize it. Open a second SSH session, verify Alex can run password-authenticated `sudo`, and keep the first session open until recovery access is proven.
8. Set `balaur.access.bootstrapPasswordlessSudo = false`, rebuild, and verify `sudo` again. Issue 16 remains blocked while the option is true or Alex's runtime hash is absent.

Do not remove the bootstrap sudo exception before step 7: Alex currently has no configured Unix password hash, so doing so would silently remove administrative recovery access.

## Samba credential interface

`modules/networking.nix` defines a fail-closed runtime interface without adding
secret material. Future host-authority sops declarations must provide two
distinct files below `/run/balaur-secrets/host/samba/`, then set:

```nix
balaur.samba.credentials = {
  ready = true;
  passwordFiles = {
    alex = "/run/balaur-secrets/host/samba/<real-runtime-name>";
    andreea = "/run/balaur-secrets/host/samba/<real-runtime-name>";
  };
};
```

The names above are schema placeholders, not files to create in plaintext.
Until real encrypted declarations exist, keep `ready = false`; smbd and TCP 445
remain disabled. When enabled, `samba-credentials.service` receives both files
through systemd `LoadCredential` and writes Samba's hashed passdb. It never
uses a Nix-store password or password command-line argument.

## qBittorrent credential interface

`modules/media.nix` reserves two values in the future host-authority encrypted
payload. The exact secret schema is:

1. `qbittorrent.protonWireguardConfig`: the complete Proton-provided wg-quick
   configuration. It must contain one `[Interface]` with `PrivateKey`,
   `Address`, and Proton `DNS`, plus one `[Peer]` with `PublicKey`, an IP-literal
   `Endpoint`, and `AllowedIPs = 0.0.0.0/0` (and `::/0` only when Proton's
   supplied profile supports IPv6). The pinned confinement parser requires the
   endpoint to be an IP address and requires `DNS`; do not substitute the host
   or router resolver.
2. `qbittorrent.webuiPasswordPBKDF2`: exactly one line containing the complete
   qBittorrent-generated serialized value in the form
   `@ByteArray('<base64-salt>:<base64-hash>')`. It is a password verifier, not a
   plaintext WebUI password, but remains secret. The username is declaratively
   fixed to `alex`.

Future reviewed sops declarations must expose these as two distinct root-only
files below `/run/balaur-secrets/host/qbittorrent/`, order the `qbt` namespace
and qBittorrent units after sops provisioning, then set:

```nix
balaur.sharedServices.qbittorrent.credentials = {
  ready = true;
  wireguardConfigFile =
    "/run/balaur-secrets/host/qbittorrent/<real-proton-runtime-name>";
  webuiPasswordHashFile =
    "/run/balaur-secrets/host/qbittorrent/<real-webui-runtime-name>";
};
```

Those names are interfaces, not files to create now. While `ready = false`, no
qBittorrent unit, VPN namespace, Caddy downloads route, loopback proxy, or host
peer/UI firewall opening exists. Do not commit a Proton profile, plaintext
password, generated test value, or fake production payload.

## llama.cpp owner API-key interface

`modules/llama.nix` reserves one independently generated API key in each owner
policy. llama.cpp b9190 reads multiple keys as one non-empty key per line from
`--api-key-file`; the unit combines systemd credential copies only inside its
mode-0700 runtime directory. It never places key values in Nix or command-line
arguments.

Future encrypted owner payloads must expose two distinct files:

```nix
balaur.sharedServices.llama.readiness = {
  ready = true;
  modelPresetFile = "/srv/models/<benchmark-approved>/router.ini";
  ownerApiKeyFiles = {
    alex = "/run/balaur-secrets/owners/alex/llama/<real-runtime-name>";
    andreea = "/run/balaur-secrets/owners/andreea/llama/<real-runtime-name>";
  };
  memoryHighBytes = <measured-peak-plus-reviewed-margin>;
};
```

Do not create those names or keys yet. After the benchmark and age/sops
onboarding, generate separate high-entropy token-shaped values locally under
hidden input, place each directly into its owner's sops payload, and expose only
that owner's file to that owner's issue-12 container. The host backend may read
both through `LoadCredential`; neither owner container may read the other key or
the combined runtime file. The model preset and measured memory target are also
mandatory, so keys alone cannot enable the service.

Until issue 12 supplies stable container addresses and source-restricted private
forwarders, there is no owner container listener or bind. Never work around that
gate by opening TCP 8081, binding a broad bridge address, or adding raw Caddy
chat ingress. VM fixture strings are public test data and must never be reused.

## Personal-container owner schemas

`modules/personal-containers.nix` defines the exact future owner payload
interface. Create the same keys separately in Alex's and Andreea's encrypted
files; expose each only below
`/run/balaur-secrets/owners/<owner>/personal/`:

| Runtime input | Format and purpose |
| --- | --- |
| `paperlessAdminPassword` | Human-chosen, single-line value of at least 20 characters. It bootstraps only that owner's Paperless admin; never use a checked-in/test value. |
| `fireflyAppKey` | Persistent Laravel key in exact `base64:<44-character-base64>` form generated from 32 random bytes. Restore requires the same key. |
| `fireflyCronToken` | Exactly 32 URL-safe alphanumeric/underscore/hyphen characters. |
| `openWebuiSecretKey` | Persistent single-line value of at least 32 characters for JWT/encrypted state. |
| `openWebuiAdminPassword` | Human-chosen, single-line value of at least 20 characters for closed owner-admin bootstrap. |
| `importerAccessToken` | At least 32 characters; created only after fresh Firefly onboarding. It gates the Data Importer separately. |
| `importerProxyPassword` | Separate human-chosen value of at least 20 characters. Caddy hashes it at startup and requires owner basic authentication because Data Importer has no native user login. |

The first five values, a human-selected non-secret `openWebuiAdminEmail`, and
the protected version marker are required before an owner container may start.
Open WebUI creates that owner admin without exposing public signup and then
keeps signup disabled. `importerAccessToken` is a second gate. Caddy receives
the Importer proxy password through `LoadCredential`; neither the plaintext nor
generated bcrypt hash enters the Nix store. The Importer route does not exist
before this second gate.

Enable Banking credentials and configuration remain entirely deferred to issue
17. This issue does not create an app, configure a connector, authorize a bank,
schedule imports, or guess BT's PSU address.

Each owner apps root must also contain `approved-versions` with exactly:

```text
trilium-server=0.102.2
paperless-ngx=2.20.15
firefly-iii=6.6.3
firefly-iii-data-importer=2.3.4
open-webui=0.11.0
```

This marker is non-secret but protected owner state. Change it only in the
reviewed cold-snapshot migration sequence. Runtime files must be root-owned,
regular (not symlink) files at mode `0400` or `0600`; the owner root remains
`0700`. The host checks mountpoints, marker, path scope, ownership, and modes
before starting a container. It rejects symlinked/non-canonical owner paths and
verifies the Paperless inbox remains on the owner's home mount. Inside the
container, a root oneshot receives the files with systemd `LoadCredential`,
validates their shape, and creates service-owned mode-0400 files under
`/run/personal-stack`. That shared parent is root-owned mode `0711`: application
users may traverse to their known file, but cannot enumerate the directory or
read another service's file.

Trilium and Firefly retain fresh browser onboarding. Open WebUI uses the
closed owner-admin bootstrap inputs above with signup disabled. No old
database/media/SQLite path is restored. Open WebUI keeps durable SQLite state
under the owner app root but redirects its `cache`, Hugging Face, embedding,
tiktoken, and Whisper model paths into a nested tmpfs excluded from snapshots
and backups. Inference remains disabled until issue 10 is physically ready;
then only the matching owner's existing llama key is visible in its owner
root.

Human onboarding must now define real sops key paths matching these option
fields, create fresh values privately, write the exact marker after a reviewed
snapshot/update decision, set one owner's `readiness.ready`, complete that
owner's browser onboarding, create the Firefly access token, and only then set
`importerReady`. Do one owner at a time. Do not copy values between owners.

## Why there is no credential wizard yet

A wizard is intentionally not authored at this stage. The consuming schemas now exist, but the human age recipient, `.sops.yaml`, encrypted file paths, and reviewed sops declarations do not. A script still has nowhere authorized to write payloads. Author the wizard from the repository wizard template only after those human decisions; it must use hidden input, avoid printing values, write only via `sops`, pass `bash -n`/`shellcheck`, and never be run by an agent.
