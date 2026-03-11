# modules/l4/default.nix
# l4 image CDN — clones taciturnaxolotl/l4, runs via Bun, proxied by Traefik.
# Secrets (S3 credentials, auth token, Slack tokens) come from an agenix env file.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.atelier.services.l4;
in
{
  options.atelier.services.l4 = {
    enable = lib.mkEnableOption "l4 image CDN";

    hostname = lib.mkOption {
      type = lib.types.str;
      example = "l4.jaspermayone.com";
      description = "Public hostname for the l4 service.";
    };

    port = lib.mkOption {
      type = lib.types.int;
      default = 8096;
      description = "Internal HTTP port for the Bun server.";
    };

    repoUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://github.com/taciturnaxolotl/l4.git";
      description = "Git clone URL for the l4 repository.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to environment file with l4 secrets.
        Must contain:
          S3_ACCESS_KEY_ID=...
          S3_SECRET_ACCESS_KEY=...
          S3_ENDPOINT=https://<account-id>.r2.cloudflarestorage.com
          R2_PUBLIC_URL=https://l4-bucket.jaspermayone.com
          AUTH_TOKEN=...
          SLACK_BOT_TOKEN=...
          SLACK_SIGNING_SECRET=...
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.l4 = {
      isSystemUser = true;
      group = "l4";
    };
    users.groups.l4 = { };

    # Clone / update the repo and install dependencies on boot
    systemd.services.l4-sync = {
      description = "Clone or update l4 repository";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      before = [ "l4.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "l4";
        Group = "l4";
        StateDirectory = "l4";
        StateDirectoryMode = "0750";
        ExecStart = pkgs.writeShellScript "l4-sync" ''
          set -euo pipefail
          REPO=/var/lib/l4/repo
          if [ -d "$REPO/.git" ]; then
            ${pkgs.git}/bin/git -C "$REPO" fetch --quiet origin
            ${pkgs.git}/bin/git -C "$REPO" reset --hard origin/HEAD
          else
            ${pkgs.git}/bin/git clone --depth 1 "${cfg.repoUrl}" "$REPO"
          fi
          cd "$REPO"
          ${pkgs.bun}/bin/bun install
        '';
      };
    };

    # Main l4 server
    systemd.services.l4 = {
      description = "l4 image CDN server";
      after = [
        "network.target"
        "l4-sync.service"
      ];
      requires = [ "l4-sync.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = "l4";
        Group = "l4";
        StateDirectory = "l4";
        WorkingDirectory = "/var/lib/l4/repo";
        EnvironmentFile = cfg.environmentFile;
        Environment = [
          "PORT=${toString cfg.port}"
          "PUBLIC_URL=https://${cfg.hostname}"
          "LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath [ pkgs.stdenv.cc.cc ]}"
        ];
        ExecStart = "${pkgs.bun}/bin/bun src/index.ts";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    # Traefik dynamic config fragment (file provider)
    environment.etc."traefik/conf.d/l4.toml" = {
      source = (pkgs.formats.toml { }).generate "l4.toml" {
        http = {
          routers.l4 = {
            rule = "Host(`${cfg.hostname}`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "l4";
          };
          services.l4.loadBalancer.servers = [
            { url = "http://127.0.0.1:${toString cfg.port}"; }
          ];
        };
      };
    };
  };
}
