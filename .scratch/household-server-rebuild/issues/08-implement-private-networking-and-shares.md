# Implement private DNS, Caddy, firewall, and SMB

Status: ready-for-agent
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
