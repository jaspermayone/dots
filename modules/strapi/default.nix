# modules/strapi/default.nix
# Strapi CMS — runs a pre-built Strapi project from a local directory, proxied by Traefik.
# The project directory must already contain node_modules (installed by the deploy script).
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.atelier.services.strapi;
in
{
  options.atelier.services.strapi = {
    enable = lib.mkEnableOption "Strapi CMS";

    hostname = lib.mkOption {
      type = lib.types.str;
      example = "cms.fundingfindr.co";
      description = "Public hostname for the Strapi admin UI.";
    };

    port = lib.mkOption {
      type = lib.types.int;
      default = 1337;
      description = "Internal HTTP port for Strapi.";
    };

    projectDir = lib.mkOption {
      type = lib.types.str;
      example = "/home/jsp/funding_findr/cms";
      description = "Absolute path to the Strapi project directory.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "jsp";
      description = "User to run Strapi as.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "users";
      description = "Group to run Strapi as.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to an environment file containing Strapi secrets. Must include:
          APP_KEYS=<four comma-separated random strings>
          API_TOKEN_SALT=<random string>
          ADMIN_JWT_SECRET=<random string>
          TRANSFER_TOKEN_SALT=<random string>
          JWT_SECRET=<random string>
          DATABASE_CLIENT=sqlite
          DATABASE_FILENAME=.tmp/data.db
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.strapi = {
      description = "Strapi CMS";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.projectDir;
        EnvironmentFile = cfg.environmentFile;
        Environment = [
          "NODE_ENV=production"
          "HOST=127.0.0.1"
          "PORT=${toString cfg.port}"
        ];
        ExecStart = "${pkgs.nodejs}/bin/node node_modules/.bin/strapi start";
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };

    # Traefik dynamic config fragment (file provider, hot-reloaded)
    environment.etc."traefik/conf.d/strapi.toml" = {
      source = (pkgs.formats.toml { }).generate "strapi.toml" {
        http = {
          routers.strapi = {
            rule = "Host(`${cfg.hostname}`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "strapi";
          };
          services.strapi.loadBalancer.servers = [
            { url = "http://127.0.0.1:${toString cfg.port}"; }
          ];
        };
      };
    };
  };
}
