# Manual torrent search options for this server

**As of:** 2026-08-11

**Scope:** self-hosted, server-side web UIs for manually searching FileList or another private tracker, choosing a release, downloading through the torrent client, watching from Jellyfin, and deleting afterward. Sources are upstream documentation/source repositories and this repository's configuration only.

## Conclusion

Keep **qBittorrent + Prowlarr**. It is already the smallest credible setup:

1. Search FileList in Prowlarr's web UI.
2. Click the download icon; Prowlarr sends the release directly to its configured qBittorrent download client.
3. Monitor and later remove the torrent plus data in qBittorrent.
4. Let Jellyfin scan a dedicated temporary/manual-download directory.

Prowlarr explicitly supports manual tracker search and pushing selected results to download clients ([project README](https://github.com/Prowlarr/Prowlarr), [search documentation](https://wiki.servarr.com/prowlarr/search)). FileList is a first-class private indexer with search support, username/passkey authentication, freeleech metadata, and a direct API implementation ([FileList indexer](https://github.com/Prowlarr/Prowlarr/blob/develop/src/NzbDrone.Core/Indexers/Definitions/FileList/FileList.cs), [settings](https://github.com/Prowlarr/Prowlarr/blob/develop/src/NzbDrone.Core/Indexers/Definitions/FileList/FileListSettings.cs)).

No single application currently replaces both qBittorrent and Prowlarr with comparable credibility. qBittorrent alone can technically cover this narrow workflow with a new unofficial FileList Python plugin, but that trades a mature native Prowlarr integration for a tiny third-party script containing the tracker credentials. That is not a good Pareto trade for a server where both mature applications are already deployed.

## Current server fit

This repository already enables Jellyfin, Prowlarr, and qBittorrent through Nixarr; qBittorrent is fail-closed in the WireGuard namespace while its authenticated web/API endpoint is mapped back to the host ([`modules/media.nix`](../../modules/media.nix)). The pinned flake currently evaluates to qBittorrent **5.2.2**, Prowlarr **2.5.2.5491**, qui **1.19.0**, VueTorrent **2.34.0**, and ruTorrent **5.2.10**.

Nixarr has direct options for qBittorrent, Prowlarr, Jellyfin, VPN confinement, and the optional qui frontend ([Nixarr options](https://nixarr.com/nixos-options/)). Nixarr also documents that arbitrary covered services can use its VPN namespace, although running Arr applications through the VPN is generally discouraged because tracker/indexer requests may be rate-limited ([basic example](https://nixarr.com/wiki/examples/example-1/), [uncovered services](https://nixarr.com/wiki/vpn/uncovered-services/)).

The existing split is useful:

- **qBittorrent traffic** remains fail-closed through the VPN.
- **Prowlarr searches** can remain outside the torrent VPN, or use Prowlarr's per-indexer SOCKS/HTTP proxy support when specifically required ([Prowlarr README](https://github.com/Prowlarr/Prowlarr)).
- A qBittorrent-local search plugin would run with qBittorrent and therefore inherit its network namespace; that is less flexible if FileList access through the VPN is undesirable.

## Does qBittorrent's official WebUI expose search/plugins?

**Yes.** This is not desktop-GUI-only:

- qBittorrent merged its WebUI Search tab in 2018 and shipped it in 4.1.9 ([upstream implementation](https://github.com/qbittorrent/qBittorrent/pull/9758), [4.1.9 changelog](https://github.com/qbittorrent/qBittorrent/blob/release-4.1.9/Changelog)).
- The current 5.2.2 WebUI source exposes the query field, category/plugin selectors, result filters, **Search plugins…**, and actions to download a selected result ([5.2.2 `search.html`](https://github.com/qbittorrent/qBittorrent/blob/release-5.2.2/src/webui/www/private/views/search.html)).
- The official WebAPI exposes starting/stopping searches, reading results, and installing, enabling, updating, and removing plugins ([5.x WebUI API](https://github.com/qbittorrent/qBittorrent/wiki/WebUI-API-(qBittorrent-5.0))). Search requires Python 3 at runtime ([official build documentation](https://github.com/qbittorrent/qBittorrent/wiki/Compilation-Debian-and-Ubuntu)).

Therefore neither VueTorrent nor qui is required merely to obtain a server-side qBittorrent search UI.

## Options compared

| Option | FileList/manual search | Torznab/indexers | Server UI and lifecycle | NixOS/Nixarr and VPN fit | Assessment |
|---|---|---|---|---|---|
| **Existing qBittorrent + Prowlarr** | First-class FileList implementation; Prowlarr manual search sends a selected result to qBittorrent | Prowlarr supports 500+ trackers, Generic Torznab, and per-indexer proxies ([README](https://github.com/Prowlarr/Prowlarr)) | Two mature web UIs; Prowlarr discovers/grabs, qBittorrent monitors and deletes | Both have NixOS modules and direct Nixarr support; existing VPN/API wiring already works | **Recommended** |
| **qBittorrent alone + unofficial FileList plugin** | Technically yes. The current unofficial list names FileList plugin 1.2 for qBittorrent 5.1/Python 3 ([plugin list](https://github.com/qbittorrent/search-plugins/wiki/Unofficial-search-plugins)); its README uses FileList's API with username/passkey ([plugin repository](https://github.com/RaresPNet/filelist_search_plugin)) | No maintained indexer catalogue or generic FileList-to-Torznab layer; one script per tracker | One official WebUI for search, download, monitoring, and delete | qBittorrent/Nixarr fit is excellent, but search also exits through qBittorrent's VPN namespace | **Possible experiment, not credible replacement**: the plugin was created in March 2026, has only a few commits, embeds credentials in `filelist.py`, and is explicitly unofficial. qBittorrent warns that third-party Python plugins are not guaranteed safe ([installation guide](https://github.com/qbittorrent/search-plugins/wiki/Install-search-plugins)). |
| **qBittorrent + VueTorrent** | Exposes qBittorrent's search engine from a more responsive alternate WebUI ([VueTorrent README](https://github.com/VueTorrent/VueTorrent)) | Inherits qBittorrent's plugins; does not manage tracker definitions itself | Good one-page qBittorrent UI | `vuetorrent` is packaged in nixpkgs and the qBittorrent NixOS module documents using it ([module](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/torrent/qbittorrent.nix), [package](https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/vu/vuetorrent/package.nix)) | UI preference only; replaces neither qBittorrent nor Prowlarr. Do not add unless the native UI is unsatisfactory. |
| **qBittorrent + qui + Prowlarr/Jackett** | qui now has Torznab search/add flows and qBittorrent management, but its docs say Prowlarr or Jackett is needed to provide indexer feeds ([qui cross-seed docs](https://getqui.com/docs/features/cross-seed/overview/), [source API](https://github.com/autobrr/qui/blob/main/web/src/lib/api.ts)) | Consumes Torznab; does not replace FileList scraping/indexer maintenance | Modern multi-instance UI plus substantial cross-seed automation | Packaged with a NixOS service and exposed by Nixarr's qBittorrent options ([nixpkgs package](https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/qu/qui/package.nix), [Nixarr options](https://nixarr.com/nixos-options/)) | Useful for multi-instance/cross-seed needs, but creates a three-service stack for a simple manual workflow. |
| **rTorrent + ruTorrent ExtSearch** | ExtSearch can search and download from public/private sites in the ruTorrent UI ([plugin docs](https://github.com/Novik/ruTorrent/wiki/Plugins)), but the current bundled engine directory has no FileList engine ([engines](https://github.com/Novik/ruTorrent/tree/master/plugins/extsearch/engines)) | Site-specific scrapers, not a maintained Torznab catalogue | Mature web UI/client pair; recent ruTorrent releases remain active ([releases](https://github.com/Novik/ruTorrent/releases)) | NixOS has rTorrent/ruTorrent modules, but Nixarr has no direct stack option; VPN confinement and migration would be custom | **Reject.** ruTorrent maintainers describe ExtSearch as under-maintained and discuss removing it in favor of Prowlarr/Jackett ([maintainer discussion](https://github.com/Novik/ruTorrent/discussions/2838)). |
| **Flood over qBittorrent/rTorrent/Transmission** | No tracker/indexer search is advertised; its “search” is torrent-list filtering | None | Mature client-management web UI supporting several daemons ([Flood README](https://github.com/jesec/flood)) | Extra service; no Nixarr advantage for this workflow | Does not solve discovery and replaces neither layer. |
| **Jackett or NZBHydra2 companion** | Jackett supports FileList, manual search, and Torznab ([Jackett README](https://github.com/Jackett/Jackett)); NZBHydra2 can search Torznab sources | Yes, but both remain companion indexer/search services | Jackett does not replace the torrent client. NZBHydra2's official torrent docs use a black-hole folder rather than direct torrent-client support ([NZBHydra2 torrent docs](https://github.com/theotherp/nzbhydra2/wiki/Torrents)) | Both have NixOS modules, but swapping out already-working Prowlarr adds migration with no clear benefit | No simplification over Prowlarr. |

Transmission and Deluge remain viable download clients behind Prowlarr, but neither supplies the missing private-indexer management/search layer; switching away from the already integrated qBittorrent would only create migration work.

## Watching and deletion are separate from search

None of the search/indexer choices automatically turns an arbitrary manual download into well-organized Jellyfin media. Jellyfin scans folders assigned to libraries and can combine multiple paths; a Mixed Content library is available for less-structured folders ([Jellyfin library docs](https://jellyfin.org/docs/general/server/libraries/)). The simple temporary-media pattern is:

1. Give Prowlarr manual grabs the dedicated qBittorrent `manual` category and temporary-media path.
2. Add only that path as a temporary Jellyfin library.
3. After watching **and after tracker seed obligations are satisfied**, delete the torrent **and its files through qBittorrent**, then let Jellyfin rescan. Deleting through Jellyfin first would remove the file while leaving stale torrent state; Jellyfin's delete permission directly removes files from the filesystem ([Jellyfin user docs](https://jellyfin.org/docs/general/server/users/)).

Prowlarr's current FileList parser advertises a minimum ratio of 1 and minimum seed time of 172,800 seconds (48 hours), so “delete after watching” must not mean “delete immediately after playback” ([FileList parser](https://github.com/Prowlarr/Prowlarr/blob/develop/src/NzbDrone.Core/Indexers/Definitions/FileList/FileListParser.cs)). Confirm the tracker's current rules and qBittorrent's per-torrent seed limits before removal.

## Pareto recommendation

1. **Do not replace anything.** Configure FileList and qBittorrent as Prowlarr indexer/download client if not already done, then use Prowlarr's Search page.
2. Use a dedicated manual-download category/path for the temporary Jellyfin library; remove through qBittorrent only after seeding requirements.
3. If a single browser surface is strongly preferred, qBittorrent's official WebUI Search tab is already present. For FileList it still needs the unofficial direct plugin (or another indexer bridge such as Jackett), so it is not operationally simpler than Prowlarr's own Search page.
4. Consider the direct FileList qBittorrent plugin only as a reversible trial, not as the server's sole private-tracker integration. Do not add qui, VueTorrent, Jackett, NZBHydra2, or an rTorrent migration without a concrete need beyond this manual workflow.
