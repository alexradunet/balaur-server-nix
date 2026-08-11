{ fastFlowLMPackage, pkgs, ... }:

{
  # FastFlowLM runs Qwen 3.6 MoE entirely on the Ryzen AI XDNA2 NPU. Linux 7.0+
  # selects the protocol-7 NPU firmware required by FastFlowLM, while the
  # portable release bundles the matching XRT userspace stack.
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelModules = [ "amdxdna" ];

  users.groups.fastflowlm = { };
  users.users.fastflowlm = {
    isSystemUser = true;
    group = "fastflowlm";
    extraGroups = [ "render" ];
  };

  systemd.services.fastflowlm = {
    description = "FastFlowLM Ryzen AI NPU model server";
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "srv-app\\x2ddata.mount"
    ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      FLM_DISABLE_UPDATE_CHECK = "1";
      FLM_MODEL_PATH = "/srv/app-data/fastflowlm/models";
      HOME = "/var/lib/fastflowlm";
    };

    serviceConfig = {
      User = "fastflowlm";
      Group = "fastflowlm";
      StateDirectory = "fastflowlm";
      WorkingDirectory = "/var/lib/fastflowlm";
      ExecStart = "${fastFlowLMPackage}/bin/flm serve qwen3.6-moe:35b-a3b --host 0.0.0.0 --port 8081 --ctx-len 32768 --cors 0";
      Restart = "on-failure";
      RestartSec = 10;
      LimitMEMLOCK = "infinity";

      DevicePolicy = "closed";
      DeviceAllow = [ "/dev/accel/accel0 rw" ];
      PrivateDevices = false;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "/srv/app-data/fastflowlm/models" ];
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
    };
  };
}
