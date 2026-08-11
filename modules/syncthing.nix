{ ... }:

{
  # ------------------------------------------------------------
  # Services
  # ------------------------------------------------------------

  services.syncthing = {
    enable = true;
    user = "alex";
    group = "users";
    dataDir = "/home/alex";
    configDir = "/home/alex/.config/syncthing";
    guiAddress = "0.0.0.0:8383";
    openDefaultPorts = false;

    # This host is a LAN-only peer. Do not publish it through global discovery,
    # relays, or automatic router port mapping.
    settings.options = {
      globalAnnounceEnabled = false;
      localAnnounceEnabled = true;
      natEnabled = false;
      relaysEnabled = false;
      listenAddresses = [
        "tcp://192.168.50.13:22000"
        "quic://192.168.50.13:22000"
      ];
    };

    # Keep peers and folder sharing editable in the UI while ensuring the
    # mirrored personal partition is always present as a two-way sync folder.
    overrideDevices = false;
    overrideFolders = false;
    settings.folders.personal = {
      path = "/srv/personal";
      label = "Personal";
      type = "sendreceive";
      # ext4 creates this root-owned directory; it is filesystem metadata, not
      # personal data, and Syncthing cannot traverse it as the alex user.
      ignorePatterns = [ "/lost+found" ];
    };
  };

  # Never let Syncthing scan the empty mount point if the nofail disk is absent;
  # that could otherwise propagate deletions to peers.
  systemd.services.syncthing.unitConfig.RequiresMountsFor = [ "/srv/personal" ];
}
