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

## Endpoints

| Service | URL | Access |
| --- | --- | --- |
| Dashboard | `https://balaur.tailnet.balaur.space/` | Tailnet only |
| Headplane | `https://headscale.balaur.space/admin/` | Public, API key required |
| Headscale API | `https://headscale.balaur.space/` | Public |
| Paseo relay | `https://relay.balaur.space/` | Public |
| Paseo | `https://balaur.tailnet.balaur.space:6767/` | Tailnet only |
| Syncthing | `https://balaur.tailnet.balaur.space:8384/` | Tailnet only |
| Zellij web terminal | `https://balaur.tailnet.balaur.space:8081/` | Tailnet only |
| XFCE web desktop | `https://balaur.tailnet.balaur.space:8084/` | Tailnet only |

`http://balaur/` redirects to the dashboard's canonical HTTPS URL.

Headplane asks for a Headscale API key on first use. Create one on the server with:

```sh
sudo headscale apikeys create
```

## Dashboard HTTPS

Headscale does not provide Tailscale-managed HTTPS certificates, so the dashboard uses a Let's Encrypt certificate through nginx. Split DNS keeps the service private while allowing public ACME validation:

- Public DNS has an `A` record for `balaur.tailnet.balaur.space` pointing to the server's public IPv4 address.
- Headscale MagicDNS resolves the same name to the server's tailnet address (`100.64.0.1`) for connected clients.
- nginx reuses the certificate for every tailnet web endpoint and permits content only from Tailscale IPv4 and IPv6 ranges. The ACME challenge remains publicly reachable.

The public DNS record must exist before deploying a new dashboard certificate configuration.

## Tailnet Services

The dashboard monitors Headscale, Syncthing, Zellij, the web desktop, and Paseo through their loopback listeners. nginx is the only network-facing entry point for their web interfaces and terminates HTTPS on each dedicated tailnet port.

Zellij web and noVNC do not have an additional application authentication layer. Their firewall exposure must remain limited to `tailscale0`.

The web desktop consists of a persistent TigerVNC display, an XFCE session, and a loopback-only noVNC gateway. It is independent of the optional local Sway session.
