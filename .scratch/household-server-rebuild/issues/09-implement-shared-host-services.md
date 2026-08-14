# Implement shared host services

Status: needs-info
Blocked by: 06, 07, 08

## Objective

Run fresh shared services with storage and network dependencies made explicit.

## Work

- Configure fresh Home Assistant under protected shared/service storage.
- Configure Jellyfin with separate profiles and replaceable media storage.
- Configure qBittorrent state/downloads and preserve fail-closed ProtonVPN confinement.
- Proxy user interfaces only through Caddy.
- Ensure missing datasets prevent services from writing fallback state to root.
- Give Jellyfin priority over optional inference work without inventing an unverified GPU scheduler.

## Acceptance criteria

- Services start only with required mounts.
- Jellyfin metadata is excluded from USB backup policy.
- Breaking ProtonVPN leaves qBittorrent with no peer/tracker internet path while approved UI access remains.
- No old media paths remain.

## Comments

The non-credential implementation was completed on 2026-08-14. Production qBittorrent remains deliberately disabled, so the issue cannot be marked Completed until real Proton and WebUI credentials are onboarded and the physical VPN path is validated.

Implementation evidence:

- `modules/home-assistant.nix` starts a fresh instance at `/srv/services/home-assistant`, requires the protected `/srv/services` mount, listens only on `127.0.0.1:8123`, and registers `home-assistant.home.arpa` with Caddy. Its retained local-device capabilities include Bluetooth, SSDP UDP 1900, and mDNS UDP 5353 only on trusted household interfaces; raw TCP 8123 remains closed.
- `modules/media.nix` starts Jellyfin on loopback behind `jellyfin.home.arpa`, gives it read-only shared-media access plus Radeon VAAPI render/video access, and assigns CPU/IO weight 200 above the later optional inference service. Its state is fresh and disposable.
- `tank/disposable/jellyfin` is a nested mount at `/srv/services/jellyfin`, disjoint from the protected snapshot allowlist. Storage and disko tests verify the dataset, mount, and fail-closed service dependency.
- qBittorrent has a typed fail-closed gate requiring distinct runtime-only Proton WireGuard and WebUI PBKDF2 files under `/run/balaur-secrets/host/qbittorrent/`. With the production default, qBittorrent, its namespace, Caddy route, proxy, and peer/UI listeners are absent.
- In the credential-ready test configuration, qBittorrent runs as a dedicated service user in the pinned VPN-Confinement namespace, keeps incomplete data under `/srv/downloads/incomplete`, lands completed data at `/srv/media/downloads`, exposes only an authenticated loopback WebUI proxy, and opens TCP/UDP 6881 only on the namespace WireGuard interface. No indexer or media-automation services are enabled.
- Disposable VM tests cover Home Assistant/Jellyfin routing, loopback listeners, closed raw ports, exact mounts and permissions, service priorities, forbidden-service absence, no md-root fallback writes, and a synthetic WireGuard interruption that removes tracker-like egress while preserving approved WebUI access.

Remaining human gates:

1. Complete issue 07 age/sops onboarding, then supply a real Proton WireGuard profile and a qBittorrent-generated PBKDF2 verifier through the documented host-authority runtime paths. No plaintext or test values may be reused.
2. Validate on the physical LAN that qBittorrent's namespace public IP is Proton's, Proton DNS resolves, tracker traffic succeeds while connected, and breaking the real tunnel stops all peer/tracker egress while Caddy UI access remains available.
3. Complete fresh Home Assistant onboarding and create separate Jellyfin profiles for Alex and Andreea under issue 17; confirm hardware transcoding on the physical Radeon device.
