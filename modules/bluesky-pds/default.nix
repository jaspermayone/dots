# modules/bluesky-pds/default.nix
# NixOS module enabling Bluesky PDS with Traefik reverse proxy and optional gatekeeper
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.services.bluesky-pds-hosting;
  gatekeeperPort = 3001;
  stubsPort = 8092;
  proxyTarget =
    if cfg.enableGatekeeper then
      "http://127.0.0.1:${toString gatekeeperPort}"
    else
      "http://127.0.0.1:${toString cfg.port}";

  escapedHostname = lib.strings.replaceStrings [ "." ] [ "\\." ] cfg.hostname;
in
{
  options.services.bluesky-pds-hosting = {
    enable = lib.mkEnableOption "Bluesky PDS hosting bundle (service + Traefik)";
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
      environmentFiles = lib.lists.flatten [
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
      setupNginx = false;
      settings = {
        GATEKEEPER_PORT = gatekeeperPort;
        PDS_BASE_URL = "http://127.0.0.1:${toString cfg.port}";
        GATEKEEPER_TRUST_PROXY = "true";
        PDS_ENV_LOCATION = cfg.environmentFile;
      };
    };

    # Write age assurance stub JSON files
    systemd.tmpfiles.rules = lib.mkIf cfg.enableAgeAssurance [
      "d /var/lib/pds-stubs 0755 nginx nginx -"
    ];

    system.activationScripts.pds-age-stubs = lib.mkIf cfg.enableAgeAssurance {
      text = ''
        mkdir -p /var/lib/pds-stubs
        cat > /var/lib/pds-stubs/getAgeAssuranceState.json << 'EOF'
        {"lastInitiatedAt":"2025-07-14T14:22:43.912Z","status":"assured"}
        EOF
        cat > /var/lib/pds-stubs/getConfig.json << 'EOF'
        {"regions":[]}
        EOF
        cat > /var/lib/pds-stubs/getState.json << 'EOF'
        {"state":{"lastInitiatedAt":"2025-07-14T14:22:43.912Z","status":"assured","access":"full"},"metadata":{"accountCreatedAt":"2022-11-17T00:35:16.391Z"}}
        EOF
        chown -R nginx:nginx /var/lib/pds-stubs
      '';
    };

    # nginx serves age assurance stubs on port 8092
    services.nginx = lib.mkIf cfg.enableAgeAssurance {
      enable = true;
      virtualHosts."pds-age-stubs" = {
        listen = [ { addr = "127.0.0.1"; port = stubsPort; } ];
        root = "/var/lib/pds-stubs";
        extraConfig = ''
          add_header Content-Type application/json;
          add_header Access-Control-Allow-Origin *;
          add_header Access-Control-Allow-Headers "authorization,dpop,atproto-accept-labelers,atproto-proxy";
        '';
        locations = {
          "/xrpc/app.bsky.unspecced.getAgeAssuranceState" = {
            extraConfig = "try_files /getAgeAssuranceState.json =404;";
          };
          "/xrpc/app.bsky.ageassurance.getConfig" = {
            extraConfig = "try_files /getConfig.json =404;";
          };
          "/xrpc/app.bsky.ageassurance.getState" = {
            extraConfig = "try_files /getState.json =404;";
          };
        };
      };
    };

    # Traefik dynamic config fragment (file provider)
    environment.etc."traefik/conf.d/pds.json" = {
      text = builtins.toJSON {
        http = {
          routers = lib.optionalAttrs cfg.enableAgeAssurance {
            pds-age = {
              rule = "Host(`${cfg.hostname}`) && PathPrefix(`/xrpc/app.bsky`)";
              entryPoints = [ "websecure" ];
              tls = {
                certResolver = "cloudflare";
                domains = [ { main = cfg.hostname; sans = [ "*.${cfg.hostname}" ]; } ];
              };
              middlewares = [ "hsts" ];
              service = "pds-age";
              priority = 10;
            };
          } // {
            pds = {
              rule = "Host(`${cfg.hostname}`)";
              entryPoints = [ "websecure" ];
              tls = {
                certResolver = "cloudflare";
                domains = [ { main = cfg.hostname; sans = [ "*.${cfg.hostname}" ]; } ];
              };
              middlewares = [ "hsts" ];
              service = "pds";
              priority = 5;
            };
            pds-handles = {
              rule = "HostRegexp(`^.+\\.${escapedHostname}$`)";
              entryPoints = [ "websecure" ];
              tls.certResolver = "cloudflare";
              middlewares = [ "hsts" ];
              service = "pds";
              priority = 1;
            };
          };
          services = lib.optionalAttrs cfg.enableAgeAssurance {
            pds-age.loadBalancer.servers = [
              { url = "http://127.0.0.1:${toString stubsPort}"; }
            ];
          } // {
            pds.loadBalancer.servers = [ { url = proxyTarget; } ];
          };
        };
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
