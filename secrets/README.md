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
4. Create the three owner-separated files with `sops` only after each consuming module defines its exact schema. Issue 08 now reserves two host-authority Samba values (one password per owner), but no encrypted host file path or payload is declared yet. Confirm every eventual file has sops metadata and cannot be decrypted without the offline identity. Commit ciphertext only.
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

## Why there is no credential wizard yet

A wizard is intentionally not authored at this stage. The encrypted file paths and secret key schema do not exist, so a script would have nowhere safe and reviewable to write the password hash or payloads. Author the wizard from the repository wizard template only after those declarations exist; it must use hidden input, avoid printing values, write only via `sops`, pass `bash -n`/`shellcheck`, and never be run by an agent.
