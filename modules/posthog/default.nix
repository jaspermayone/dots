# modules/posthog/default.nix
# PostHog analytics — hobby Docker Compose deployment
#
# Clones the PostHog repo on first start (for ClickHouse/compose configs),
# writes a merged .env from the agenix secret + computed values, and runs
# the full hobby stack via docker-compose.  Caddy (bundled) handles TLS via
# Let's Encrypt HTTP-01 — no Traefik needed on dedicated PostHog hosts.
#
# Prerequisites:
#   1. DNS A record for `hostname` pointing to this server.
#   2. Agenix secret at `environmentFile` containing:
#        POSTHOG_SECRET=<openssl rand -hex 28>
#        ENCRYPTION_SALT_KEYS=<openssl rand -hex 16>
{ config, lib, pkgs, ... }:

let
  cfg = config.atelier.services.posthog;

  setupScript = pkgs.writeShellScript "posthog-setup" ''
    set -euo pipefail

    WORK_DIR="${cfg.dataDir}"
    PH_REPO="$WORK_DIR/posthog"

    # Clone the PostHog repo (config files only — app images are pulled separately)
    if [ ! -d "$PH_REPO/.git" ]; then
      ${pkgs.git}/bin/git clone --depth 1 \
        https://github.com/PostHog/posthog.git \
        "$PH_REPO"
    fi

    # Refresh compose files from the repo each startup so config stays in sync
    cp -f "$PH_REPO/docker-compose.base.yml" "$WORK_DIR/"
    cp -f "$PH_REPO/docker-compose.hobby.yml" "$WORK_DIR/docker-compose.yml"

    # Runtime directories and files expected by the stack
    mkdir -p "$WORK_DIR/compose"
    mkdir -p "$WORK_DIR/share"
    touch "$WORK_DIR/dev-services.env"

    # Startup scripts mounted into containers at /compose/.
    # These were removed from the PostHog repo but the hobby compose still references them.
    cat > "$WORK_DIR/compose/start" <<'SCRIPT'
#!/bin/bash
set -e
./bin/docker-migrate
exec ./bin/docker-server
SCRIPT
    chmod +x "$WORK_DIR/compose/start"

    cat > "$WORK_DIR/compose/temporal-django-worker" <<'SCRIPT'
#!/bin/bash
set -e
exec ./bin/temporal-django-worker
SCRIPT
    chmod +x "$WORK_DIR/compose/temporal-django-worker"

    # Write .env: merge the agenix secret (POSTHOG_SECRET, ENCRYPTION_SALT_KEYS)
    # with computed values.  Mode 600 — this file contains secrets.
    install -m 600 /dev/null "$WORK_DIR/.env"
    cat "${cfg.environmentFile}" >> "$WORK_DIR/.env"
    cat >> "$WORK_DIR/.env" <<EOF

DOMAIN=${cfg.hostname}
REGISTRY_URL=posthog/posthog
POSTHOG_APP_TAG=${cfg.tag}

CADDY_TLS_BLOCK=${if cfg.behindProxy then "auto_https off" else ""}
EOF

    # docker-compose.base.yml uses <<: *worker YAML anchors which docker-compose
    # extends: does not propagate. Inject the missing vars via an override file.
    cat > "$WORK_DIR/docker-compose.override.yml" <<'OVERRIDE'
services:
  web:
    environment:
      DATABASE_URL: "postgres://posthog:posthog@db:5432/posthog"
      REDIS_URL: "redis://redis7:6379/"
      SKIP_SERVICE_VERSION_REQUIREMENTS: "1"
      CLICKHOUSE_HOST: "clickhouse"
      CLICKHOUSE_SECURE: "false"
      CLICKHOUSE_VERIFY: "false"
  worker:
    environment:
      DATABASE_URL: "postgres://posthog:posthog@db:5432/posthog"
      REDIS_URL: "redis://redis7:6379/"
      SKIP_SERVICE_VERSION_REQUIREMENTS: "1"
      CLICKHOUSE_HOST: "clickhouse"
      CLICKHOUSE_SECURE: "false"
      CLICKHOUSE_VERIFY: "false"
  temporal-django-worker:
    restart: "no"
    entrypoint: ["/bin/sh", "-c", "echo 'temporal-django-worker not present in this image version, skipping'; exit 0"]
    environment:
      DATABASE_URL: "postgres://posthog:posthog@db:5432/posthog"
      REDIS_URL: "redis://redis7:6379/"
      SKIP_SERVICE_VERSION_REQUIREMENTS: "1"
  feature-flags:
    environment:
      WRITE_DATABASE_URL: "postgres://posthog:posthog@db:5432/posthog"
      READ_DATABASE_URL: "postgres://posthog:posthog@db:5432/posthog"
      PERSONS_WRITE_DATABASE_URL: "postgres://posthog:posthog@db:5432/posthog"
      PERSONS_READ_DATABASE_URL: "postgres://posthog:posthog@db:5432/posthog"
      MAXMIND_DB_PATH: ""
OVERRIDE
  '';
in
{
  options.atelier.services.posthog = {
    enable = lib.mkEnableOption "PostHog analytics (hobby Docker Compose deploy)";

    hostname = lib.mkOption {
      type = lib.types.str;
      example = "ph.singlefeather.com";
      description = ''
        Public hostname for this PostHog instance.
        Must have an A record pointing to this server before startup
        so Caddy can obtain a Let's Encrypt certificate.
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/posthog";
      description = "Working directory for the PostHog compose stack and persistent data.";
    };

    tag = lib.mkOption {
      type = lib.types.str;
      default = "latest-release";
      description = "PostHog Docker image tag (POSTHOG_APP_TAG). Use a pinned release tag for stability.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to an env file (agenix secret) containing:
          POSTHOG_SECRET=<56-char secret — openssl rand -hex 28>
          ENCRYPTION_SALT_KEYS=<32-char hex  — openssl rand -hex 16>
      '';
    };

    behindProxy = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Set to true when TLS is terminated upstream (e.g. Traefik).
        Disables Caddy's own TLS so it serves plain HTTP on port 80.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker = {
      enable = true;
      autoPrune = {
        enable = true;
        dates = "weekly";
      };
      daemon.settings = {
        log-driver = "json-file";
        log-opts = {
          max-size = "50m";
          max-file = "3";
        };
      };
    };

    environment.systemPackages = [
      pkgs.docker-compose
      pkgs.git
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0700 root root -"
    ];

    systemd.services.posthog = {
      description = "PostHog analytics (Docker Compose hobby stack)";
      after = [
        "docker.service"
        "network-online.target"
      ];
      wants = [ "network-online.target" ];
      requires = [ "docker.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = cfg.dataDir;
        ExecStartPre = "${setupScript}";
        ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d";
        ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
        # First start clones the repo and pulls many images — give it time.
        TimeoutStartSec = "20min";
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "posthog";
      };
    };

    networking.firewall.allowedTCPPorts = if cfg.behindProxy
      then [ 80 ]
      else [ 80 443 ];
    networking.firewall.allowedUDPPorts = lib.mkIf (!cfg.behindProxy) [ 443 ];
  };
}
