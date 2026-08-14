# Implement private DNS, Caddy, firewall, and SMB

Status: needs-info
Blocked by: 02, 06, 07

## Objective

Expose friendly household services only on trusted LAN/WireGuard paths and provide isolated file shares.

## Work

- Serve approved `home.arpa` records locally and validate the ASUS/WireGuard DNS path.
- Configure Caddy internal-CA TLS and owner-specific reverse proxies.
- Expose only required host ingress on trusted interfaces; raw app/container ports remain private.
- Add private SMB shares for each owner's `files` directory and Paperless consume path.
- Add the approved shared-media access policy.
- Do not export full homes or app state.

## Acceptance criteria

- No WAN/public listeners or public ACME dependencies.
- LAN and WireGuard clients resolve names and can trust the private CA.
- Alex cannot access Andreea's share and vice versa.
- Router port-forward absence is included in the human validation gate.

## Comments

The non-credential implementation was completed on 2026-08-14, but this issue is intentionally not Completed because production credentials and router/client validation remain human-owned gates.

Implementation evidence:

- `modules/networking.nix` now defines the shared trusted-interface/address policy, an authoritative `home.arpa` CoreDNS zone, forwarding for all non-household queries only to `192.168.50.1`, no query log plugin, and listeners bound to `192.168.50.2`. The exact records are `balaur.home.arpa`; notes, paperless, budget, and chat beneath each of `alex.home.arpa` and `andreea.home.arpa`; and `home-assistant.home.arpa`, `jellyfin.home.arpa`, and `downloads.home.arpa`. Unknown household names are authoritative NXDOMAIN.
- Caddy uses only its internal issuer, disables automatic trust installation, its admin API, and HTTP/3, binds `192.168.50.2`, and currently serves only an HTTP-to-HTTPS redirect plus `https://balaur.home.arpa/health`. There are no public ACME settings or application routes. `balaur.ingress.reverseProxies` is the typed extension seam: only an approved household name and private IPv4 backend/port are accepted, and registration never changes firewall rules.
- Production firewall globals remain empty. On each of `enp100s0` and `wlp98s0`, TCP 22/53/80/443 and UDP 53 are allowed. TCP 445 is conditional on the Samba credential gate. NetBIOS 137/138/139, UDP 443, all raw application ports, and every global interface remain closed.
- Samba policy evaluates with exactly the `alex` (`/home/alex/files`), `andreea` (`/home/andreea/files`), and `media` (`/srv/media`) disk exports. It is standalone SMB2/3 on TCP 445, trusted-interface-bound, guest/anonymous access denied, usershares/NetBIOS/nmbd/winbind disabled, and no full-home/apps/secret/download/consume roots exported. Private shares are owner-only. `/srv/media` is `alex:media` mode `2750`; both owners can read via SMB, while only Alex can write, and Andreea remains nologin/no-SSH/no-sudo despite media membership.
- Production Samba is deliberately disabled and TCP 445 closed because `balaur.samba.credentials.ready = false`. The typed interface requires two distinct runtime-only files beneath `/run/balaur-secrets/host/samba/`. When enabled later, a oneshot uses systemd `LoadCredential` and `smbpasswd -s` without Nix-store or command-line passwords. No sops declaration, encrypted payload, fake password, recipient, or CA private material was created.
- `tests/network-access-vm.nix` uses passwords generated only inside a disposable VM at boot. Its router node gives deterministic forwarding evidence. The test verifies every authoritative record and household NXDOMAIN, forwarding, internal-CA certificate validation and health, exact bound listeners, no HTTP/3/NetBIOS/raw ports, guest and SMB1 rejection, the exact disk-share list, no full-home/apps export, both cross-owner denials, both owners reading media, Andreea's SMB and direct filesystem writes denied, Alex's SMB write accepted, and Andreea's login shell denied.
- `docs/network-access.md` supersedes the old raw-service instructions and records target DNS, the ASUS LAN/WireGuard DNS advertisement tests, private-CA enrollment, exact SMB policy, no-port-forward/DMZ/UPnP checks, and the production credential gate. `secrets/README.md` records the later sops-backed Samba runtime interface.
- Final verification passed: pinned nixfmt on changed Nix files; focused `network-access-vm`, access/networking, shared-service, and secret checks; `nix flake check -L path:$PWD` including the disposable disko VM; full `nixosConfigurations.balaur.config.system.build.toplevel` build with `--no-link`; and `git diff --check`. The explicit `path:` form includes the new untracked VM test without staging it.

Remaining human inputs/actions:

1. Complete issue 07's age recipient and real encrypted host payload onboarding. Choose distinct Alex and Andreea Samba passwords privately, expose them through two reviewed host-authority sops declarations under the reserved runtime root, set the typed password file paths, and only then set `balaur.samba.credentials.ready = true`. Rebuild and repeat the SMB isolation test with authorized real clients. Bootstrap passwordless sudo also remains an issue-07/16 blocker.
2. Reconfirm the ASUS reservation for `192.168.50.2`. Advertise that address as LAN client DNS without setting it as the router's own upstream resolver, renew a client lease, and verify one household plus one forwarded lookup.
3. Export and inspect a disposable ASUS WireGuard client profile. Ensure its effective DNS is `192.168.50.2` and its split routes include `192.168.50.0/24`; from mobile data verify DNS and TLS without assuming **Allow DNS** preserved that value.
4. After authorized deployment lets Caddy generate its CA, install only the public root certificate on the approved clients and verify `balaur.home.arpa/health` with normal certificate validation over LAN and WireGuard. Never copy the CA private key.
5. In the ASUS UI, record that no WAN virtual-server/port-forward, DMZ-host, or UPnP mapping exposes Balaur (especially 22, 53, 80, 443, 445, or old raw ports).

The acceptance criteria cannot yet truthfully pass: production SMB has no usable passdb by design, client CA trust is not enrolled, and router DNS/WireGuard/WAN state has not been observed. Keep this issue `needs-info` until those human checks are dated and attached.
