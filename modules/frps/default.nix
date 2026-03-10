{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.atelier.services.frps;
  escapedDomain = lib.strings.replaceStrings [ "." ] [ "\\." ] cfg.domain;
in
{
  options.atelier.services.frps = {
    enable = lib.mkEnableOption "frp server for tunneling services";

    bindAddr = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Address to bind frp server to";
    };

    bindPort = lib.mkOption {
      type = lib.types.port;
      default = 7000;
      description = "Port for frp control connection";
    };

    vhostHTTPPort = lib.mkOption {
      type = lib.types.port;
      default = 7080;
      description = "Port for HTTP virtual host traffic";
    };

    allowedTCPPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = lib.lists.range 20000 20099;
      example = [ 20000 20001 20002 20003 20004 ];
      description = "TCP port range to allow for TCP tunnels (default: 20000-20099)";
    };

    allowedUDPPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = lib.lists.range 20000 20099;
      example = [ 20000 20001 20002 20003 20004 ];
      description = "UDP port range to allow for UDP tunnels (default: 20000-20099)";
    };

    authToken = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Authentication token for clients (deprecated: use authTokenFile)";
    };

    authTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to file containing authentication token";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      example = "tun.hogwarts.channel";
      description = "Base domain for subdomains (e.g., *.tun.hogwarts.channel)";
    };

    enableTraefik = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Automatically configure Traefik reverse proxy for wildcard domain";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.authToken != null || cfg.authTokenFile != null;
        message = "Either authToken or authTokenFile must be set for frps";
      }
    ];

    # Open firewall ports for frp control connection and TCP/UDP tunnels
    networking.firewall.allowedTCPPorts = [ cfg.bindPort ] ++ cfg.allowedTCPPorts;
    networking.firewall.allowedUDPPorts = cfg.allowedUDPPorts;

    # frp server service
    systemd.services.frps =
      let
        tokenConfig =
          if cfg.authTokenFile != null then
            ''
              auth.tokenSource.type = "file"
              auth.tokenSource.file.path = "${cfg.authTokenFile}"
            ''
          else
            ''auth.token = "${cfg.authToken}"'';

        configFile = pkgs.writeText "frps.toml" ''
          bindAddr = "${cfg.bindAddr}"
          bindPort = ${toString cfg.bindPort}
          vhostHTTPPort = ${toString cfg.vhostHTTPPort}

          # Dashboard and Prometheus metrics
          webServer.addr = "127.0.0.1"
          webServer.port = 7400
          enablePrometheus = true

          # Authentication token - clients need this to connect
          auth.method = "token"
          ${tokenConfig}

          # Subdomain support for *.${cfg.domain}
          subDomainHost = "${cfg.domain}"

          # Allow port ranges for TCP/UDP tunnels
          allowPorts = [
            { start = 20000, end = 20099 }
          ]

          # Custom 404 page
          custom404Page = "${./404.html}"

          # Logging
          log.to = "console"
          log.level = "info"
        '';
      in
      {
        description = "frp server for ${cfg.domain} tunneling";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          Restart = "on-failure";
          RestartSec = "5s";
          ExecStart = "${pkgs.frp}/bin/frps -c ${configFile}";
        };
      };

    # Traefik dynamic config fragment (file provider)
    environment.etc."traefik/conf.d/frps.json" = lib.mkIf cfg.enableTraefik {
      text = builtins.toJSON {
        http = {
          routers = {
            frps-dashboard = {
              rule = "Host(`${cfg.domain}`)";
              entryPoints = [ "websecure" ];
              tls = {
                certResolver = "cloudflare";
                domains = [
                  { main = cfg.domain; sans = [ "*.${cfg.domain}" ]; }
                ];
              };
              middlewares = [ "hsts" ];
              service = "frps-dashboard";
            };
            frps-tunnels = {
              rule = "HostRegexp(`^.+\\.${escapedDomain}$`)";
              entryPoints = [ "websecure" ];
              tls = {
                certResolver = "cloudflare";
                domains = [
                  { main = "*.${cfg.domain}"; sans = [ cfg.domain ]; }
                ];
              };
              middlewares = [ "hsts" ];
              service = "frps-tunnels";
              priority = 1;
            };
          };
          services = {
            frps-dashboard.loadBalancer.servers = [
              { url = "http://127.0.0.1:7400"; }
            ];
            frps-tunnels.loadBalancer.servers = [
              { url = "http://127.0.0.1:${toString cfg.vhostHTTPPort}"; }
            ];
          };
        };
      };
    };
  };
}
