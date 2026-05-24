# modules/telemetry/default.nix
# Full telemetry stack: Grafana + Prometheus + InfluxDB v2 + Loki
# Grafana is exposed via Traefik and authenticates against an existing Authentik
# instance via Generic OAuth — no outpost or local Authentik needed.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.atelier.services.telemetry;
in
{
  options.atelier.services.telemetry = {
    enable = lib.mkEnableOption "telemetry stack (Grafana, Prometheus, InfluxDB v2, Loki)";

    hostname = lib.mkOption {
      type = lib.types.str;
      example = "telemetry.hogwarts.dev";
      description = "Public hostname for the Grafana dashboard.";
    };

    authentikHostname = lib.mkOption {
      type = lib.types.str;
      default = "a.hogwarts.dev";
      description = "Hostname of the Authentik instance used for OAuth.";
    };

    grafanaAdminPasswordFile = lib.mkOption {
      type = lib.types.path;
      description = "File containing the Grafana admin password (single line, no newline).";
    };

    grafanaOAuthEnvFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Env file for Grafana OAuth secrets. Must contain:
          GF_AUTH_GENERIC_OAUTH_CLIENT_ID=<id>
          GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET=<secret>
      '';
    };

    influxdbDatabases = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "unifi" "telegraf" ];
      description = "InfluxDB 1.x databases to create on first boot.";
    };
  };

  config = lib.mkIf cfg.enable {

    # ── Grafana ───────────────────────────────────────────────────────────────

    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_addr = "0.0.0.0";
          http_port = 3000;
          domain = cfg.hostname;
          root_url = "https://${cfg.hostname}";
        };
        security = {
          admin_user = "admin";
          # $__file{} reads the secret at runtime without it landing in the store
          admin_password = "$__file{${cfg.grafanaAdminPasswordFile}}";
          disable_initial_admin_creation = false;
        };
        "auth.generic_oauth" = {
          enabled = true;
          name = "Authentik";
          allow_sign_up = true;
          scopes = "openid email profile";
          auth_url = "https://${cfg.authentikHostname}/application/o/authorize/";
          token_url = "https://${cfg.authentikHostname}/application/o/token/";
          api_url = "https://${cfg.authentikHostname}/application/o/userinfo/";
          use_pkce = true;
          # Map Authentik group membership to Grafana roles
          role_attribute_path = "contains(groups[*], 'grafana-admins') && 'Admin' || contains(groups[*], 'grafana-editors') && 'Editor' || contains(groups[*], 'grafana-viewers') && 'Viewer' || 'Viewer'";
        };
      };
      provision = {
        enable = true;
        datasources.settings = {
          apiVersion = 1;
          datasources = [
            {
              name = "Prometheus";
              type = "prometheus";
              url = "http://localhost:9090";
              isDefault = true;
              jsonData.timeInterval = "15s";
            }
            {
              name = "Loki";
              type = "loki";
              url = "http://localhost:3100";
            }
            {
              name = "InfluxDB";
              type = "influxdb";
              url = "http://localhost:8086";
              database = "unifi";
              jsonData.httpMode = "GET";
            }
          ];
        };
      };
    };

    # GF_AUTH_GENERIC_OAUTH_CLIENT_ID and GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET
    # come from the env file — never written to the store
    systemd.services.grafana.serviceConfig.EnvironmentFile = cfg.grafanaOAuthEnvFile;

    # ── Prometheus ────────────────────────────────────────────────────────────

    services.prometheus = {
      enable = true;
      listenAddress = "0.0.0.0";
      port = 9090;
      retentionTime = "30d";
      globalConfig.scrape_interval = "15s";
      scrapeConfigs = [
        {
          job_name = "prometheus";
          static_configs = [ { targets = [ "localhost:9090" ]; } ];
        }
        {
          job_name = "node";
          static_configs = [ { targets = [ "localhost:9100" ]; } ];
        }
      ];
    };

    services.prometheus.exporters.node = {
      enable = true;
      port = 9100;
      enabledCollectors = [ "systemd" "processes" ];
    };

    # ── InfluxDB 1.x ─────────────────────────────────────────────────────────
    # UniFi Poller requires InfluxDB 1.8.x; v2 is not supported.

    services.influxdb = {
      enable = true;
    };

    # Create configured databases on first boot — idempotent.
    systemd.services.influxdb-setup = {
      description = "InfluxDB 1.x database creation";
      after = [ "influxdb.service" ];
      requires = [ "influxdb.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.influxdb pkgs.curl ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "influxdb-setup" ''
          set -euo pipefail
          for i in $(seq 1 30); do
            curl -sf http://localhost:8086/ping && break
            sleep 1
          done
          ${lib.concatMapStringsSep "\n" (db: ''
            influx -execute "CREATE DATABASE ${db}" || true
          '') cfg.influxdbDatabases}
        '';
      };
    };

    # ── Loki ─────────────────────────────────────────────────────────────────

    services.loki = {
      enable = true;
      configuration = {
        auth_enabled = false;
        server.http_listen_port = 3100;
        common = {
          instance_addr = "127.0.0.1";
          path_prefix = "/var/lib/loki";
          storage.filesystem = {
            chunks_directory = "/var/lib/loki/chunks";
            rules_directory = "/var/lib/loki/rules";
          };
          replication_factor = 1;
          ring.kvstore.store = "inmemory";
        };
        schema_config.configs = [
          {
            from = "2020-10-24";
            store = "tsdb";
            object_store = "filesystem";
            schema = "v13";
            index = {
              prefix = "index_";
              period = "24h";
            };
          }
        ];
        limits_config = {
          reject_old_samples = true;
          reject_old_samples_max_age = "168h";
        };
        compactor = {
          working_directory = "/var/lib/loki/compactor";
          compaction_interval = "10m";
        };
      };
    };

    # ── Traefik conf.d ────────────────────────────────────────────────────────
    # Exposes Grafana at cfg.hostname. Grafana itself enforces authentication
    # via Authentik OAuth — no forwardAuth middleware needed here.
    # hsts is defined here as the shared global middleware for this host.
    environment.etc."traefik/conf.d/telemetry.toml" = {
      source = (pkgs.formats.toml { }).generate "telemetry.toml" {
        http = {
          middlewares.hsts.headers = {
            stsSeconds = 31536000;
            stsIncludeSubdomains = true;
            stsPreload = true;
          };
          routers.grafana = {
            rule = "Host(`${cfg.hostname}`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "grafana";
          };
          services.grafana.loadBalancer.servers = [
            { url = "http://127.0.0.1:3000"; }
          ];
        };
      };
    };

    # ── Firewall ──────────────────────────────────────────────────────────────
    # Prometheus, InfluxDB, and Loki listen on all interfaces so other machines
    # (e.g. over Tailscale) can scrape/push metrics and logs.
    # Port 9100 (node-exporter) stays on localhost — Prometheus scrapes it locally.
    networking.firewall.allowedTCPPorts = [
      9090 # Prometheus
      8086 # InfluxDB
      3100 # Loki
    ];
  };
}
