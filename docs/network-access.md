# Balaur remote network access

Balaur is reachable from the home LAN and from remote clients through the ASUS
router's WireGuard VPN. The VPN is split-tunnel: only home-network traffic is
sent through WireGuard; ordinary internet traffic remains on the client’s
normal connection.

## ASUS WireGuard server

Use **VPN → VPN Server → WireGuard**, not VPN Fusion or the site-to-site setup.
Create a separate client profile for every phone or laptop.

For each client:

- Enable **Access Intranet**.
- Enable **NAT** under Advanced Settings. This lets Balaur see VPN traffic as
  LAN traffic and avoids adding WireGuard interfaces to the host firewall.
- Enable **Allow DNS** if the client should use the router for home DNS.
- Enable the **Pre-shared key** and let ASUS generate the secret.
- Keep the router-generated tunnel network, normally `10.6.0.0/24`.
- Give each client a unique address, such as `10.6.0.2/32` or `10.6.0.3/32`.
- The server-side allowed IP for a client should be that client address, for
  example `10.6.0.3/32`.

Export the profile or scan its QR code in the official WireGuard app. The
client profile should use split-tunnel routes:

```ini
[Interface]
Address = 10.6.0.3/32
DNS = 10.6.0.1

[Peer]
AllowedIPs = 10.6.0.1/32, 192.168.50.0/24
Endpoint = YOUR_PUBLIC_WAN_ADDRESS:51820
PersistentKeepalive = 25
```

Keep the ASUS-generated `PrivateKey` and router `PublicKey`; never commit a
WireGuard configuration or share its private key. If a private key is exposed,
delete that client profile in ASUS and generate a replacement.

`192.168.50.0/24` routes the whole home LAN, including Balaur at
`192.168.50.2`. `10.6.0.1/32` routes the router's WireGuard address. Do not use
`0.0.0.0/0` unless all client internet traffic should go through home.

## Services

With WireGuard active, remote clients can use the same addresses as LAN
clients:

- SSH: `ssh alex@192.168.50.2`
- Dashboard: `http://192.168.50.2`
- Trilium desktop/browser: `https://192.168.50.2:8084`
- Pocket Trilium fallback: `http://192.168.50.2:8085`
- ASUS router: `http://192.168.50.1`

Port 8085 is a deliberate HTTP-only compatibility endpoint for Pocket
Trilium, whose embedded environment may not trust the private Caddy CA. It is
firewall-limited to the LAN interfaces and must not be forwarded from the
router WAN. Use HTTPS on port 8084 everywhere that can trust the Caddy root CA.

To test genuine remote access, connect the client through mobile data or a
separate network rather than the home Wi-Fi. On Windows, use PowerShell:

```powershell
Test-NetConnection 192.168.50.2 -Port 22
Test-NetConnection 192.168.50.2 -Port 8085
```

The WireGuard application should also show a recent handshake and received
traffic. A client profile can reach the LAN only when the router has a public
WAN address and the WireGuard server profile is enabled.
