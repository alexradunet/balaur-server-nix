# Implement shared host services

Status: ready-for-agent
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
