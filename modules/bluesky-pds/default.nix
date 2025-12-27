# modules/bluesky-pds/default.nix
# NixOS module enabling Bluesky PDS with Caddy reverse proxy and optional gatekeeper
{ lib, config, pkgs, ... }:
let
  cfg = config.services.bluesky-pds-hosting;
  pdsSettings = config.services.bluesky-pds.settings;
  gatekeeperPort = 3001;
  # When gatekeeper is enabled, Caddy proxies to gatekeeper; otherwise directly to PDS
  proxyTarget = if cfg.enableGatekeeper then "localhost:${toString gatekeeperPort}" else "localhost:${toString cfg.port}";
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
    enableGatekeeper = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable PDS gatekeeper for 2FA email and spam prevention.";
    };
    enableAgeAssurance = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Serve age assurance stub endpoints (UK Online Safety Act).";
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

    # PDS Gatekeeper for 2FA and spam prevention
    services.pds-gatekeeper = lib.mkIf cfg.enableGatekeeper {
      enable = true;
      setupNginx = false; # We use Caddy
      settings = {
        GATEKEEPER_PORT = gatekeeperPort;
        PDS_BASE_URL = "http://127.0.0.1:${toString cfg.port}";
        GATEKEEPER_TRUST_PROXY = "true";
        PDS_ENV_LOCATION = cfg.environmentFile;
      };
    };

    # Caddy reverse proxy for PDS
    services.caddy.virtualHosts = {
      "${cfg.hostname}" = {
        serverAliases = [ "*.${cfg.hostname}" ];
        extraConfig = ''
          tls {
            dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          }

          ${lib.optionalString cfg.enableAgeAssurance ''
          handle /xrpc/app.bsky.unspecced.getAgeAssuranceState {
            header content-type "application/json"
            header access-control-allow-headers "authorization,dpop,atproto-accept-labelers,atproto-proxy"
            header access-control-allow-origin "*"
            respond `{"lastInitiatedAt":"2025-07-14T14:22:43.912Z","status":"assured"}` 200
          }

          handle /xrpc/app.bsky.ageassurance.getConfig {
            header content-type "application/json"
            header access-control-allow-headers "authorization,dpop,atproto-accept-labelers,atproto-proxy"
            header access-control-allow-origin "*"
            respond `{"regions":[]}` 200
          }

          handle /xrpc/app.bsky.ageassurance.getState {
            header content-type "application/json"
            header access-control-allow-headers "authorization,dpop,atproto-accept-labelers,atproto-proxy"
            header access-control-allow-origin "*"
            respond `{"state":{"lastInitiatedAt":"2025-07-14T14:22:43.912Z","status":"assured","access":"full"},"metadata":{"accountCreatedAt":"2022-11-17T00:35:16.391Z"}}` 200
          }
          ''}

          reverse_proxy ${proxyTarget}
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
