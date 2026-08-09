# Balaur Server

NixOS configuration for `balaur`, a Headscale server and tailnet development host.

## Deploy

Apply the configuration from the repository root:

```sh
sudo nixos-rebuild switch --flake .#balaur
```

Evaluate the complete system configuration without activating it:

```sh
nix eval .#nixosConfigurations.balaur.config.system.build.toplevel.drvPath --raw
```

## Tests

Run all configuration invariants, dashboard integration tests, package builds, and
the standard NixOS module checks:

```sh
nix flake check
```

Build the complete host system without creating a `result` symlink:

```sh
nix build .#nixosConfigurations.balaur.config.system.build.toplevel --no-link
```

The invariant check covers the host's boot and filesystem layout, SSH and firewall
policy, loopback-only services, MagicDNS records, nginx routes and access controls,
service enablement, Paseo relay settings, runtime secret generation, and systemd
sandboxing. The dashboard check starts the real Node server and verifies its HTTP
routes, security headers, metrics response, and service status payload.

## Endpoints

| Service | URL | Access |
| --- | --- | --- |
| Dashboard | `https://dashboard.balaur.space/` | Tailnet only |
| Headplane | `https://headscale.balaur.space/admin/` | Public, API key required |
| Headscale API | `https://headscale.balaur.space/` | Public |
| Paseo relay | `https://relay.balaur.space/` | Public |
| Paseo | `https://paseo.balaur.space/` | Tailnet only |
| Syncthing | `https://syncthing.balaur.space/` | Tailnet only |
| XFCE web desktop | `https://desktop.balaur.space/` | Tailnet only |

`http://balaur/` redirects to the dashboard's canonical HTTPS URL.

Headplane asks for a Headscale API key on first use. Create one on the server with:

```sh
sudo headscale apikeys create
```

## Dashboard HTTPS

Headscale does not provide Tailscale-managed HTTPS certificates, so the tailnet services use Let's Encrypt certificates through nginx. Split DNS keeps the services private while allowing public ACME validation:

- Public DNS has `CNAME` records for `dashboard.balaur.space`, `desktop.balaur.space`, `paseo.balaur.space`, and `syncthing.balaur.space` pointing to `balaur.tailnet.balaur.space`.
- Headscale MagicDNS overrides those names with the server's tailnet address (`100.64.0.1`) for connected clients.
- Headscale provides Tailnet DNS globally and forwards other lookups to Cloudflare so operating systems use the private records outside the MagicDNS base domain.
- nginx permits content only from Tailscale IPv4 and IPv6 ranges. The ACME challenges remain publicly reachable.

The public DNS record must exist before deploying a new dashboard certificate configuration.

## Tailnet Services

The dashboard monitors Headscale, Syncthing, the web desktop, and Paseo through their loopback listeners. nginx is the only network-facing entry point for their web interfaces and routes each Tailnet-only subdomain over standard HTTPS.

noVNC does not have an additional application authentication layer. Its firewall exposure must remain limited to `tailscale0`.

The web desktop consists of a persistent TigerVNC display, an XFCE session, and a loopback-only noVNC gateway. It is independent of the optional local Sway session.
