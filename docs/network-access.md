# Balaur private network access

This document supersedes the former raw-IP dashboard and Trilium port
instructions. Those application services are intentionally absent during the
household rebuild, and their old ports remain closed.

Balaur is private to the home LAN. Remote access is provided by the ASUS
RT-AX82U WireGuard server and routed back to the LAN; Balaur does not terminate
WireGuard itself.

## Fixed network boundary

- Server reservation/target: `192.168.50.2` on `192.168.50.0/24`.
- ASUS router/forwarding resolver: `192.168.50.1`.
- Trusted server interfaces: `enp100s0` and Wi-Fi fallback `wlp98s0`.
- No service is intentionally reachable from a WAN interface.
- Do not create router port forwards, DMZ-host rules, public ACME challenges,
  or public DNS records for any name in this document.

Recheck the `192.168.50.2` reservation before installation. The configuration
opens ports only in the per-interface firewall rules; the global firewall
allowlists remain empty.

## Local `home.arpa` DNS

CoreDNS is authoritative only for `home.arpa`, binds to `192.168.50.2`, and
serves these exact private A records at `192.168.50.2`:

- `balaur.home.arpa`
- `notes.alex.home.arpa`, `paperless.alex.home.arpa`,
  `budget.alex.home.arpa`, `chat.alex.home.arpa`
- `notes.andreea.home.arpa`, `paperless.andreea.home.arpa`,
  `budget.andreea.home.arpa`, `chat.andreea.home.arpa`
- `home-assistant.home.arpa`, `jellyfin.home.arpa`,
  `downloads.home.arpa`

Names do not imply that an application exists yet. Unknown `home.arpa` names
return NXDOMAIN. Queries outside the household zone are forwarded only to the
ASUS resolver at `192.168.50.1`. Routine DNS query logging is not enabled.
TCP and UDP 53 are allowed only on the trusted LAN interfaces.

The server being down therefore makes household application names unavailable.
That is an accepted trade-off; no secondary public zone or resolver is added.

### Human router and LAN DNS gate

No router setting has been changed by this repository. Before relying on the
names:

1. In the ASUS LAN DHCP settings, advertise `192.168.50.2` as the client DNS
   server. Do not change the router's own upstream/WAN resolver to
   `192.168.50.2`, because CoreDNS forwards non-household queries back to the
   router and that would create a loop.
2. Renew one LAN client's DHCP lease and confirm its effective resolver is
   `192.168.50.2`.
3. Run both an authoritative and forwarded lookup:

   ```console
   nslookup balaur.home.arpa 192.168.50.2
   nslookup example.com 192.168.50.2
   ```

4. Confirm an unknown name such as `missing.home.arpa` does not resolve.

If this ASUS firmware cannot advertise a custom LAN DNS server without also
changing its upstream resolver, configure `192.168.50.2` directly on household
clients and record the firmware limitation before deployment. Do not silently
fall back to public `home.arpa` publication.

## ASUS WireGuard DNS gate

Use **VPN -> VPN Server -> WireGuard**, not VPN Fusion or a site-to-site
profile. Keep one ASUS-generated profile per client, **Access Intranet** on,
NAT on, a pre-shared key on, and split-tunnel routes. Keep all private keys out
of this repository.

The previously documented `DNS = 10.6.0.1` is not sufficient unless that exact
router firmware is first proven to relay `home.arpa` to Balaur. The target
client profile is:

```ini
[Interface]
Address = 10.6.0.3/32
DNS = 192.168.50.2

[Peer]
AllowedIPs = 10.6.0.1/32, 192.168.50.0/24
Endpoint = YOUR_PUBLIC_WAN_ADDRESS:51820
PersistentKeepalive = 25
```

Treat the DNS line as a human validation gate: ASUS may regenerate it as
`10.6.0.1` when **Allow DNS** is enabled. Export a disposable profile, inspect
the effective client configuration, and edit only that client's DNS setting if
necessary. Do not claim this gate complete until a client on mobile data, with
Wi-Fi disabled, can perform both lookups above through WireGuard. Also confirm
ordinary internet traffic still uses the client's normal connection.

## Caddy private TLS ingress

Caddy binds TCP 80 and 443 at `192.168.50.2` and uses its runtime-generated
internal CA. HTTP exists only to redirect the host health URL; HTTP/3 and the
local admin API are disabled, so UDP 443 and TCP 2019 are not listening. There
is no public ACME configuration.

The only current route is:

```text
https://balaur.home.arpa/health  ->  200 "balaur ok"
```

All application reverse proxies remain absent. Later service modules must use
the typed `balaur.ingress.reverseProxies` registration seam; it accepts only an
approved household name and a private backend address/port. Backend ports are
never added to the firewall by registration.

Caddy creates the CA material itself on first start. Never manually generate or
copy its private key. After an authorized deployment, an administrator may
export only the public root certificate from:

```text
/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt
```

Installing that public root in each regular client trust store and testing TLS
on LAN and WireGuard are human issue-17 gates. Until enrollment, a client will
correctly report an untrusted issuer. Do not bypass certificate validation for
normal use.

## SMB shares and credential gate

Samba is declared with SMB2/3 only, standalone user security, guest mapping
disabled, anonymous access restricted, NetBIOS/nmbd and winbind disabled, and
only TCP 445. It binds only to the trusted LAN interfaces. These are the only
exports:

| Share | Host path | Read | Write through SMB |
| --- | --- | --- | --- |
| `alex` | `/home/alex/files` | Alex | Alex |
| `andreea` | `/home/andreea/files` | Andreea | Andreea |
| `media` | `/srv/media` | Alex and Andreea | Alex only |

Full home directories, owner app roots, secret roots, downloads, and Paperless
consume paths are not exported. The non-privileged `media` group provides host
filesystem access to shared media. Andreea remains nologin, has no SSH keys,
no wheel membership, and no sudo rule; media membership grants none of those
capabilities.

Production Samba is currently fail-closed: `balaur.samba.credentials.ready` is
false, smbd is disabled, and TCP 445 is closed. Human onboarding must create
distinct real sops-nix values exposed at runtime beneath
`/run/balaur-secrets/host/samba/`, set both typed `passwordFiles`, and only then
set `ready = true`. The activation unit loads those files with systemd
credentials and updates passdb without putting passwords in Nix or command-line
arguments. Do not add placeholder passwords or plaintext files to the host
configuration.

## Router/WAN validation before completion

From the ASUS administration UI, a human must record that:

1. WAN port forwarding/virtual server has no rule for Balaur, especially TCP or
   UDP 53, TCP 80/443/445, SSH 22, or any old raw application port.
2. DMZ host is disabled and UPnP has not created an equivalent mapping.
3. The WireGuard profile alone provides remote reachability.
4. LAN and mobile-data WireGuard tests pass for DNS and trusted private TLS.

The server firewall cannot prove the absence of router NAT rules, so issue 08
must remain `needs-info` until this check, DNS advertisement, CA enrollment, and
real Samba credential onboarding are performed.
