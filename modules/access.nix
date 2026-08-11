{ ... }:

{
  # ------------------------------------------------------------
  # User
  # ------------------------------------------------------------

  users.users.alex = {
    isNormalUser = true;
    description = "Alex";
    extraGroups = [
      "wheel"
      "networkmanager"
      "media"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJyNg0fSXVLH2obdAQ9lX2LP4NjATTydZxvu6RguwRWx alex@yoga-laptop"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJb2YvlmOvpu8On8kAdU0bgNQXLSekrVu/s/L7W+XPGV alex@balaur.space"
    ];
  };

  security.sudo.extraRules = [
    {
      users = [ "alex" ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  # ------------------------------------------------------------
  # SSH
  # ------------------------------------------------------------

  services.openssh = {
    enable = true;
    # networking.nix opens SSH only on the trusted LAN interfaces.
    openFirewall = false;

    settings = {
      AllowUsers = [ "alex" ];
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      X11Forwarding = false;
    };
  };
}
