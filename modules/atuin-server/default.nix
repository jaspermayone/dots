# modules/atuin-server/default.nix
# NixOS module for self-hosted Atuin sync server
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.atelier.services.atuin-server;

  # nixpkgs dropped the "server" feature at 18.12.0 (cargoHash changed too,
  # so we can't just patch buildFeatures on the current pkg — we pin 18.11.0).
  atuinWithServer = pkgs.rustPlatform.buildRustPackage {
    pname = "atuin";
    version = "18.11.0";

    src = pkgs.fetchFromGitHub {
      owner = "atuinsh";
      repo = "atuin";
      tag = "v18.11.0";
      hash = "sha256-yjsCNN15E06te6cueSZksg7mcMyx2FiXKrbGAEcQWmg=";
    };

    cargoHash = "sha256-xaALIVJpMek4nbSozxtOEWivRDlMmKdu6KqKiNMp0jk=";

    buildNoDefaultFeatures = true;
    buildFeatures = [ "client" "sync" "server" "clipboard" "daemon" ];

    nativeBuildInputs = [ pkgs.installShellFiles ];

    postInstall = lib.optionalString (pkgs.stdenv.buildPlatform.canExecute pkgs.stdenv.hostPlatform) ''
      installShellCompletion --cmd atuin \
        --bash <($out/bin/atuin gen-completions -s bash) \
        --fish <($out/bin/atuin gen-completions -s fish) \
        --zsh <($out/bin/atuin gen-completions -s zsh)
    '';

    checkFlags = [
      "--skip=registration"
      "--skip=sync"
      "--skip=change_password"
      "--skip=multi_user_test"
    ];

    preCheck = "export HOME=$(mktemp -d)";

    meta.mainProgram = "atuin";
  };
in
{
  options.atelier.services.atuin-server = {
    enable = lib.mkEnableOption "Atuin sync server";

    hostname = lib.mkOption {
      type = lib.types.str;
      example = "atuin.example.com";
      description = "Hostname for the Atuin server.";
    };

    port = lib.mkOption {
      type = lib.types.int;
      default = 8888;
      description = "Internal port for the Atuin server.";
    };

    openRegistration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to allow new user registrations.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/atuin-server";
      description = "Directory for Atuin server data (SQLite database).";
    };
  };

  config = lib.mkIf cfg.enable {
    # Systemd service for Atuin server
    systemd.services.atuin-server = {
      description = "Atuin Sync Server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        ATUIN_HOST = "127.0.0.1";
        ATUIN_PORT = toString cfg.port;
        ATUIN_OPEN_REGISTRATION = lib.boolToString cfg.openRegistration;
        ATUIN_DB_URI = "sqlite://${cfg.dataDir}/atuin.db";
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${atuinWithServer}/bin/atuin server start";
        Restart = "on-failure";
        User = "atuin";
        Group = "atuin";
        WorkingDirectory = cfg.dataDir;

        # Hardening
        CapabilityBoundingSet = "";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        LockPersonality = true;
        ReadWritePaths = [ cfg.dataDir ];
      };
    };

    # System user for Atuin
    users.users.atuin = {
      isSystemUser = true;
      group = "atuin";
      home = cfg.dataDir;
      createHome = true;
    };
    users.groups.atuin = { };

    # Traefik dynamic config fragment (file provider)
    environment.etc."traefik/conf.d/atuin.toml" = {
      source = (pkgs.formats.toml { }).generate "atuin.toml" {
        http = {
          routers.atuin = {
            rule = "Host(`${cfg.hostname}`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "atuin";
          };
          services.atuin.loadBalancer.servers = [
            { url = "http://127.0.0.1:${toString cfg.port}"; }
          ];
        };
      };
    };
  };
}
