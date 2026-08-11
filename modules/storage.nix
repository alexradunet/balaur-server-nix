{ piSubagentsPackage, piWebAccessPackage, pkgs, ... }:

let
  piFastFlowLMModels = pkgs.writeText "pi-fastflowlm-models.json" (builtins.toJSON {
    providers.fastflowlm = {
      baseUrl = "http://127.0.0.1:8081/v1";
      api = "openai-completions";
      # FastFlowLM does not require authentication, but pi needs a value before
      # it will offer a custom provider in /model.
      apiKey = "fastflowlm";
      compat = {
        supportsDeveloperRole = false;
        supportsReasoningEffort = false;
        # FastFlowLM closes a successful SSE stream without a finish_reason.
        supportsFinishReason = false;
      };
      models = [
        {
          id = "qwen3.6-moe:35b-a3b";
          name = "Qwen 3.6 MoE (FastFlowLM)";
          input = [ "text" ];
          contextWindow = 32768;
          maxTokens = 8192;
          cost = {
            input = 0;
            output = 0;
            cacheRead = 0;
            cacheWrite = 0;
          };
        }
      ];
    };
  });
in
{
  # Mirrored application state for services such as Jellyfin and Immich.
  fileSystems."/srv/app-data" = {
    device = "/dev/disk/by-label/BALAUR_APP_DATA";
    fsType = "ext4";
    options = [
      "nofail"
      "nodev"
      "nosuid"
      "x-systemd.device-timeout=30s"
    ];
  };

  # Mirrored personal data, including the local photo archive.
  fileSystems."/srv/personal" = {
    device = "/dev/disk/by-label/BALAUR_PERSONAL";
    fsType = "ext4";
    options = [
      "nofail"
      "nodev"
      "nosuid"
      "noexec"
      "x-systemd.device-timeout=30s"
    ];
  };

  # Independent, non-redundant storage for replaceable downloaded media.
  fileSystems."/srv/media/ssd0" = {
    device = "/dev/disk/by-label/BALAUR_MEDIA_0";
    fsType = "ext4";
    options = [
      "nofail"
      "nodev"
      "nosuid"
      "noexec"
    ];
  };

  fileSystems."/srv/media/ssd1" = {
    device = "/dev/disk/by-label/BALAUR_MEDIA_1";
    fsType = "ext4";
    options = [
      "nofail"
      "nodev"
      "nosuid"
      "noexec"
    ];
  };

  # Keep the USB backup offline except while Borg is creating a daily snapshot.
  fileSystems."/mnt/balaur-backup" = {
    device = "/dev/disk/by-label/BALAUR_BACKUP";
    fsType = "ext4";
    options = [
      "noauto"
      "nofail"
      "nodev"
      "nosuid"
      "noexec"
      "x-systemd.device-timeout=10s"
    ];
  };

  systemd.tmpfiles.rules = [
    "d /srv/secrets 0700 root root -"
    "d /srv/app-data 2775 root media -"
    "Z /srv/app-data/prowlarr - prowlarr prowlarr -"
    "d /srv/app-data/fastflowlm 0750 fastflowlm fastflowlm -"
    "d /srv/app-data/fastflowlm/models 0750 fastflowlm fastflowlm -"
    "d /srv/media/ssd0/downloads 2775 qbittorrent media -"
    "d /srv/media/ssd0/downloads/incomplete 2775 qbittorrent media -"
    "d /srv/media/ssd0/downloads/complete 2775 qbittorrent media -"
    "d /srv/media/ssd0/downloads/complete/radarr 2775 qbittorrent media -"
    "d /srv/media/ssd0/library 2775 alex media -"
    "d /srv/media/ssd0/library/movies 2775 alex media -"
    "d /srv/media/ssd1/downloads 2775 qbittorrent media -"
    "d /srv/media/ssd1/downloads/incomplete 2775 qbittorrent media -"
    "d /srv/media/ssd1/downloads/complete 2775 qbittorrent media -"
    "d /srv/media/ssd1/downloads/complete/sonarr 2775 qbittorrent media -"
    "d /srv/media/ssd1/library 2775 alex media -"
    "d /srv/media/ssd1/library/tv 2775 alex media -"
    "d /srv/media/ssd1/library/music 2775 alex media -"
    "d /srv/personal 2775 alex media -"
    "d /srv/media 2775 root media -"
    "d /srv/media/ssd0 2775 root media -"
    "d /srv/media/ssd1 2775 root media -"
    "d /mnt/balaur-backup 0700 root root -"
    "d /home/alex/.pi 0755 alex users -"
    "d /home/alex/.pi/agent 0755 alex users -"
    "d /home/alex/.pi/agent/extensions 0755 alex users -"
    "L+ /home/alex/.pi/agent/models.json - - - - ${piFastFlowLMModels}"
    "L+ /home/alex/.pi/agent/extensions/pi-subagents - - - - ${piSubagentsPackage}/lib/node_modules/@tintinweb/pi-subagents"
    "L+ /home/alex/.pi/agent/extensions/pi-web-access - - - - ${piWebAccessPackage}/lib/node_modules/pi-web-access"
  ];
}
