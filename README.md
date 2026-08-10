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
service enablement, runtime secret generation, and systemd
sandboxing. The dashboard check starts the real Node server and verifies its HTTP
routes, security headers, metrics response, and service status payload.

## Endpoints

| Service | URL | Access |
| --- | --- | --- |
| Dashboard | `https://dashboard.balaur.space/` | Tailnet only |
| Headplane | `https://headscale.balaur.space/admin/` | Public, API key required |
| Headscale API | `https://headscale.balaur.space/` | Public |
| Herdr | `https://herdr.balaur.space/` | Tailnet only |
| llama.cpp | `https://llama.balaur.space/` | Tailnet only |
| Syncthing | `https://syncthing.balaur.space/` | Tailnet only |
| XFCE web desktop | `https://desktop.balaur.space/` | Tailnet only |

`http://balaur/` redirects to the dashboard's canonical HTTPS URL.

Headplane asks for a Headscale API key on first use. Create one on the server with:

```sh
sudo headscale apikeys create
```

## Dashboard HTTPS

Headscale does not provide Tailscale-managed HTTPS certificates, so the tailnet services use Let's Encrypt certificates through nginx. Split DNS keeps the services private while allowing public ACME validation:

- Public DNS has one wildcard `CNAME` record, `*.balaur.space`, pointing to `balaur.tailnet.balaur.space`. Explicit records such as `headscale.balaur.space` take precedence.
- Headscale MagicDNS overrides those names with the server's tailnet address (`100.64.0.1`) for connected clients.
- Headscale provides Tailnet DNS globally and forwards other lookups to Cloudflare so operating systems use the private records outside the MagicDNS base domain.
- nginx permits content only from Tailscale IPv4 and IPv6 ranges. The ACME challenges remain publicly reachable.

The wildcard public DNS record must exist before deploying a certificate for a new service subdomain.

## Tailnet Services

The dashboard monitors Headscale, Syncthing, the web desktop, Herdr, and llama.cpp through their loopback listeners. nginx is the only network-facing entry point for their web interfaces and routes each Tailnet-only subdomain over standard HTTPS.

llama.cpp automatically downloads the instruction-tuned `gemma-4-26B-A4B-it` Q4_K_M GGUF from Hugging Face into `/var/cache/llama-cpp` on its first start. The model download is about 16.9 GB, with an additional multimodal projector downloaded automatically when available. It uses a 64K shared context, two request slots, Vulkan acceleration on the Radeon 890M, flash attention, and Gemma 4's 462 MB MTP drafter for lossless speculative decoding. The first service start remains unavailable until the downloads and model load complete; follow progress with `journalctl -fu llama-cpp`.

The Vulkan-enabled `llama-server` and related llama.cpp commands are also installed system-wide. llama.cpp is pinned to release `b10336` because Gemma 4's MTP drafter requires architecture support newer than the Nixpkgs package.

Herdr remains available as the `herdr` CLI. Its web endpoint runs the same terminal UI through a loopback-only ttyd process as the `alex` user, so it shares the CLI's persistent sessions and development environment.

noVNC and the Herdr web terminal do not have an additional application authentication layer. nginx access controls must remain limited to Tailnet clients.

The web desktop consists of a persistent TigerVNC display, an XFCE session, and a loopback-only noVNC gateway. It is independent of the optional local Sway session.
