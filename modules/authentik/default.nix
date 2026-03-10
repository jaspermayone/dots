# modules/authentik/default.nix
# Authentik identity provider using nix-community/authentik-nix
{
  lib,
  config,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.atelier.services.authentik;
in
{
  imports = [ inputs.authentik-nix.nixosModules.default ];

  options.atelier.services.authentik = {
    enable = lib.mkEnableOption "Authentik identity provider";

    hostname = lib.mkOption {
      type = lib.types.str;
      example = "a.hogwarts.dev";
      description = "Hostname for the Authentik server.";
    };

    port = lib.mkOption {
      type = lib.types.int;
      default = 9000;
      description = "Internal HTTP port for Authentik.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to environment file with Authentik secrets.
        Must contain:
          AUTHENTIK_SECRET_KEY=<50+ char random string>
          AUTHENTIK_POSTGRESQL__PASSWORD=<db password>
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.authentik = {
      enable = true;
      environmentFile = cfg.environmentFile;
      settings = {
        disable_startup_analytics = true;
        avatars = "initials";
        # Bind HTTP to localhost only; Traefik handles TLS externally
        listen = {
          http = "127.0.0.1:${toString cfg.port}";
          https = "127.0.0.1:${toString (cfg.port + 443)}";
          metrics = "127.0.0.1:9300";
        };
      };
    };

    # Traefik dynamic config fragment (file provider)
    environment.etc."traefik/conf.d/authentik.toml" = {
      source = (pkgs.formats.toml { }).generate "authentik.toml" {
        http = {
          routers.authentik = {
            rule = "Host(`${cfg.hostname}`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "authentik";
          };
          services.authentik.loadBalancer.servers = [
            { url = "http://127.0.0.1:${toString cfg.port}"; }
          ];
        };
      };
    };
  };
}
