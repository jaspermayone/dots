# modules/bluesky-pds/default.nix
# NixOS module enabling Bluesky PDS with Caddy reverse proxy
{ lib, config, pkgs, ... }:
let
  cfg = config.services.bluesky-pds-hosting;
in
{
  options.services.bluesky-pds-hosting = {
    enable = lib.mkEnableOption "Bluesky PDS hosting bundle (service + Caddy)";
    hostname = lib.mkOption {
      type = lib.types.str;
      example = "example.com";
      description = "Primary PDS hostname (root domain for handles).";
    };
    port = lib.mkOption {
      type = lib.types.int;
      default = 3000;
      description = "Internal PDS port.";
    };
    adminEmail = lib.mkOption {
      type = lib.types.str;
      example = "pds@example.com";
    };
    environmentFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to agenix-managed env file (pds.age).";
    };
    mailerEnvironmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Optional env file for SMTP/Resend (pds-mailer.age).";
    };
    cloudflareCredentialsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to Cloudflare credentials for ACME DNS challenge.";
    };
    enableAgeAssurance = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Serve age assurance stub endpoints.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.bluesky-pds = {
      enable = true;
      environmentFiles =
        lib.lists.flatten [
          [ cfg.environmentFile ]
          (lib.optional (cfg.mailerEnvironmentFile != null) cfg.mailerEnvironmentFile)
        ];
      settings = {
        PDS_PORT = cfg.port;
        PDS_HOSTNAME = cfg.hostname;
        PDS_ADMIN_EMAIL = cfg.adminEmail;
        PDS_CRAWLERS = lib.concatStringsSep "," [
          "https://bsky.network"
          "https://relay.cerulea.blue"
          "https://relay.fire.hose.cam"
          "https://relay2.fire.hose.cam"
          "https://relay3.fr.hose.cam"
          "https://relay.hayescmd.net"
          "https://relay.xero.systems"
          "https://relay.upcloud.world"
          "https://relay.feeds.blue"
          "https://atproto.africa"
        ];
      };
    };

    # Caddy reverse proxy for PDS
    services.caddy.virtualHosts = {
      # Main domain and wildcard for handles
      "${cfg.hostname}" = {
        serverAliases = [ "*.${cfg.hostname}" ];
        extraConfig = ''
          tls {
            dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          }
          reverse_proxy localhost:${toString cfg.port} {
            header_up X-Forwarded-Proto {scheme}
            header_up X-Forwarded-For {remote}
          }
        '';
      };
    };

    # Hardening: restrict service user
    users.users.pds = {
      isSystemUser = true;
      group = "pds";
      home = "/var/lib/pds";
      createHome = true;
    };
    users.groups.pds = { };
  };
}
