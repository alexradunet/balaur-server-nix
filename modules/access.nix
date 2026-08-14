{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.balaur.access;
in
{
  options.balaur.access.bootstrapPasswordlessSudo = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Temporary recovery-access gate. This must remain true until the Owner has
      installed and tested Alex's encrypted password hash, and must be false
      before issue 16 may deploy the host.
    '';
  };

  config = {
    assertions = [
      {
        assertion = cfg.bootstrapPasswordlessSudo || config.users.users.alex.hashedPasswordFile != null;
        message = "Disabling bootstrap passwordless sudo requires Alex's runtime hashedPasswordFile first";
      }
    ];

    warnings = lib.optional cfg.bootstrapPasswordlessSudo ''
      DEPLOYMENT BLOCKER: balaur.access.bootstrapPasswordlessSudo is still enabled. Issue 16 must not deploy until Alex's encrypted password hash is installed and tested, then this option is disabled.
    '';

    users.users = {
      alex = {
        isNormalUser = true;
        description = "Alex";
        group = "users";
        home = "/home/alex";
        homeMode = "0700";
        extraGroups = [
          "wheel"
          "networkmanager"
        ];
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJyNg0fSXVLH2obdAQ9lX2LP4NjATTydZxvu6RguwRWx alex@yoga-laptop"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJb2YvlmOvpu8On8kAdU0bgNQXLSekrVu/s/L7W+XPGV alex@balaur.space"
        ];
      };

      andreea = {
        isNormalUser = true;
        description = "Andreea";
        group = "users";
        home = "/home/andreea";
        homeMode = "0700";
        extraGroups = [ ];
        hashedPassword = "!";
        shell = "${pkgs.shadow}/bin/nologin";
        openssh.authorizedKeys.keys = [ ];
      };
    };

    # Keep the bootstrap exception visible and removable as one policy switch.
    # The normal wheel rule still requires a password.
    security.sudo = {
      wheelNeedsPassword = true;
      extraRules = lib.optionals cfg.bootstrapPasswordlessSudo [
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
    };

    # ZFS owns the mounts; tmpfiles only enforces account ownership and modes
    # after those mandatory mounts are available. Do not create alternate
    # mount policy or fallback directories here.
    systemd.tmpfiles.rules = [
      "d /home/alex 0700 alex users -"
      "d /srv/people/alex/apps 0700 alex users -"
      "d /home/andreea 0700 andreea users -"
      "d /srv/people/andreea/apps 0700 andreea users -"
    ];

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
  };
}
