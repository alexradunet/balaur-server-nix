{
  description = "NixOS configuration for balaur";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    disko = {
      url = "github:nix-community/disko/ff8702b4de27f72b4c78573dfb89ec74e36abdf1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixarr = {
      url = "github:nix-media-server/nixarr";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix/a8627b21b9107c5711c96b84f32a9a4b3d45295f";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pi.url = "github:lukasl-dev/pi.nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      disko,
      nixarr,
      sops-nix,
      pi,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      piPackage = pi.packages.${system}.coding-agent;
      piSubagentsPackage = pkgs.callPackage ./packages/pi-subagents.nix { };
      piWebAccessPackage = pkgs.callPackage ./packages/pi-web-access.nix { };
      llamaPackage = pkgs.callPackage ./packages/llama-cpp-rocm.nix { };
    in
    {
      packages.${system} = {
        default = piPackage;
        pi = piPackage;
        pi-subagents = piSubagentsPackage;
        pi-web-access = piWebAccessPackage;
        llama-cpp-rocm = llamaPackage;
      };

      nixosConfigurations.balaur = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit piPackage piSubagentsPackage piWebAccessPackage;
        };
        modules = [
          disko.nixosModules.disko
          nixarr.nixosModules.default
          sops-nix.nixosModules.sops
          ./hosts/balaur/default.nix
        ];
      };

      checks.${system} = {
        configuration = import ./tests/configuration.nix {
          inherit pkgs;
          config = self.nixosConfigurations.balaur.config;
        };
        storage = import ./tests/storage.nix {
          inherit pkgs;
          config = self.nixosConfigurations.balaur.config;
        };
        disko-scripts = import ./tests/disko-scripts.nix {
          inherit pkgs;
          config = self.nixosConfigurations.balaur.config;
          diskoRevision = disko.rev;
        };
        disko-install =
          (self.nixosConfigurations.balaur.extendModules {
            modules = [ ./tests/disko-install.nix ];
          }).config.system.build.installTest;
        access-networking = import ./tests/access-networking.nix {
          inherit pkgs;
          config = self.nixosConfigurations.balaur.config;
        };
        network-access-vm = pkgs.testers.runNixOSTest (import ./tests/network-access-vm.nix);
        secrets = import ./tests/secrets.nix {
          inherit pkgs;
          config = self.nixosConfigurations.balaur.config;
        };
        shared-services = import ./tests/shared-services.nix {
          inherit pkgs;
          config = self.nixosConfigurations.balaur.config;
        };
        shared-services-vm = pkgs.testers.runNixOSTest (
          import ./tests/shared-services-vm.nix {
            nixarrModule = nixarr.nixosModules.default;
            sopsModule = sops-nix.nixosModules.sops;
          }
        );
        llama-package = import ./tests/llama-package.nix {
          inherit pkgs llamaPackage;
        };
        llama-service =
          let
            readyHost = self.nixosConfigurations.balaur.extendModules {
              modules = [
                {
                  balaur.sharedServices.llama.readiness = {
                    ready = true;
                    modelPresetFile = "/srv/models/approved/router.ini";
                    ownerApiKeyFiles = {
                      alex = "/run/balaur-secrets/owners/alex/llama/api-key";
                      andreea = "/run/balaur-secrets/owners/andreea/llama/api-key";
                    };
                    # Synthetic evaluation value only. Production must copy the
                    # measured benchmark target instead of this test fixture.
                    memoryHighBytes = 34359738368;
                  };
                }
              ];
            };
          in
          import ./tests/llama-service.nix {
            inherit pkgs llamaPackage;
            defaultConfig = self.nixosConfigurations.balaur.config;
            readyConfig = readyHost.config;
          };
        llama-service-vm = pkgs.testers.runNixOSTest (
          import ./tests/llama-service-vm.nix {
            sopsModule = sops-nix.nixosModules.sops;
          }
        );
        qbittorrent-vpn-vm = pkgs.testers.runNixOSTest (
          import ./tests/qbittorrent-vpn-vm.nix {
            nixarrModule = nixarr.nixosModules.default;
            sopsModule = sops-nix.nixosModules.sops;
          }
        );
        qbittorrent-ready =
          let
            readyHost = self.nixosConfigurations.balaur.extendModules {
              modules = [
                {
                  balaur.sharedServices.qbittorrent.credentials = {
                    ready = true;
                    wireguardConfigFile = "/run/balaur-secrets/host/qbittorrent/proton.conf";
                    webuiPasswordHashFile = "/run/balaur-secrets/host/qbittorrent/webui-pbkdf2";
                  };
                }
              ];
            };
          in
          import ./tests/qbittorrent-ready.nix {
            inherit pkgs;
            config = readyHost.config;
          };
        personal-containers =
          let
            ownerReadiness =
              owner:
              let
                root = "/run/balaur-secrets/owners/${owner}/personal";
              in
              {
                ready = true;
                importerReady = true;
                openWebuiAdminEmail = "${owner}@home.arpa";
                files = {
                  paperlessAdminPassword = "${root}/paperless-admin-password";
                  fireflyAppKey = "${root}/firefly-app-key";
                  fireflyCronToken = "${root}/firefly-cron-token";
                  openWebuiSecretKey = "${root}/open-webui-secret-key";
                  openWebuiAdminPassword = "${root}/open-webui-admin-password";
                  importerAccessToken = "${root}/importer-access-token";
                  importerProxyPassword = "${root}/importer-proxy-password";
                };
              };
            readyHost = self.nixosConfigurations.balaur.extendModules {
              modules = [
                {
                  balaur.personalContainers.owners = {
                    alex.readiness = ownerReadiness "alex";
                    andreea.readiness = ownerReadiness "andreea";
                  };
                }
              ];
            };
          in
          import ./tests/personal-containers.nix {
            inherit pkgs;
            defaultConfig = self.nixosConfigurations.balaur.config;
            readyConfig = readyHost.config;
          };
        personal-containers-vm = pkgs.testers.runNixOSTest (
          import ./tests/personal-containers-vm.nix {
            sopsModule = sops-nix.nixosModules.sops;
          }
        );
        backup = import ./tests/backup.nix {
          inherit pkgs;
          config = self.nixosConfigurations.balaur.config;
        };
        monitoring = import ./tests/monitoring.nix {
          inherit pkgs;
          config = self.nixosConfigurations.balaur.config;
        };
        pi = piPackage;
        pi-subagents = piSubagentsPackage;
        pi-web-access = piWebAccessPackage;
      };
    };
}
