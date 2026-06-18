# modules/wit-calendar/default.nix
# WIT Coding Club calendar backend — Rails app + Postgres + Redis as Docker
# containers on a dedicated network, proxied by Traefik.
#
# CI deploys happen without nixos-rebuild:
#   1. CI builds and pushes a new image to ghcr.io
#   2. CI writes the new image ref to /var/lib/wit-calendar/image-ref
#   3. CI SSHes as wit-calendar-deploy and runs:
#        sudo systemctl restart wit-calendar-web
#
# First-time data setup (fresh DB — the old Kamal data is intentionally NOT
# migrated; use the import scripts in the backend repo instead):
#   After nixos-rebuild switch, the web service auto-runs `rails db:prepare`
#   to create and migrate all four databases (primary, cache, queue, cable).
#   Then run the import scripts against the old dump.
#
# Env file (wit-calendar-env.age) must contain:
#   RAILS_MASTER_KEY=...
#   CALENDAR_DATABASE_PASSWORD=...   # used by Rails
#   POSTGRES_PASSWORD=...            # same value — used by postgres container init
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.atelier.services.wit-calendar;
  network = "wit-calendar";
in
{
  options.atelier.services.wit-calendar = {
    enable = lib.mkEnableOption "WIT Calendar backend";

    hostname = lib.mkOption {
      type = lib.types.str;
      default = "server-calendar.witcc.dev";
      description = "Public hostname Traefik routes to this service.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3002;
      description = "Host port the web container binds to (loopback only).";
    };

    image = lib.mkOption {
      type = lib.types.str;
      example = "ghcr.io/witcodingclub/calendar-backend:main";
      description = ''
        Default Docker image for the web container. CI overrides this at
        deploy time by writing a new ref to /var/lib/wit-calendar/image-ref
        and running: sudo systemctl restart wit-calendar-web
        The service always reads that file first; this value is the fallback.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to an env file (e.g. an agenix secret) containing:
          RAILS_MASTER_KEY=...
          CALENDAR_DATABASE_PASSWORD=...   (Rails DB password)
          POSTGRES_PASSWORD=...            (same value — postgres container init)
      '';
    };

    registryCredentialsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Optional path to a file containing a GitHub PAT with packages:read,
        used to authenticate docker pull from ghcr.io. Not needed if the
        package is public.
      '';
    };

    deployAuthorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        SSH public keys for the wit-calendar-deploy CI user.
        That user may only: sudo systemctl restart wit-calendar-web
      '';
    };
  };

  config = lib.mkIf cfg.enable {

    # ── CI deploy user ────────────────────────────────────────────────────────
    users.users.wit-calendar-deploy = lib.mkIf (cfg.deployAuthorizedKeys != [ ]) {
      isNormalUser = true;
      group = "users";
      shell = pkgs.bash;
      openssh.authorizedKeys.keys = cfg.deployAuthorizedKeys;
    };

    security.sudo.extraRules = lib.mkIf (cfg.deployAuthorizedKeys != [ ]) [
      {
        users = [ "wit-calendar-deploy" ];
        commands = [
          {
            command = "/run/current-system/sw/bin/systemctl restart wit-calendar-web";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    # ── State files ───────────────────────────────────────────────────────────
    # image-ref is written by the CI deploy user, so it must be owned by them.
    systemd.tmpfiles.rules = lib.mkIf (cfg.deployAuthorizedKeys != [ ]) [
      "f /var/lib/wit-calendar/image-ref 0644 wit-calendar-deploy users -"
    ];

    # ── Docker network ────────────────────────────────────────────────────────
    systemd.services.wit-calendar-network = {
      description = "Create wit-calendar Docker network";
      after = [ "docker.service" ];
      requires = [ "docker.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StateDirectory = "wit-calendar wit-calendar/db wit-calendar/redis";
        StateDirectoryMode = "0755";
        ExecStart = pkgs.writeShellScript "wit-calendar-network-create" ''
          ${pkgs.docker}/bin/docker network inspect ${network} >/dev/null 2>&1 || \
            ${pkgs.docker}/bin/docker network create ${network}
        '';
      };
    };

    # ── Redis ─────────────────────────────────────────────────────────────────
    systemd.services.wit-calendar-redis = {
      description = "WIT Calendar Redis";
      after = [
        "docker.service"
        "wit-calendar-network.service"
      ];
      requires = [
        "docker.service"
        "wit-calendar-network.service"
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStartPre = [
          "-${pkgs.docker}/bin/docker stop wit-calendar-redis"
          "-${pkgs.docker}/bin/docker rm wit-calendar-redis"
          "${pkgs.docker}/bin/docker pull redis:7-alpine"
        ];
        ExecStart = ''
          ${pkgs.docker}/bin/docker run \
            --name wit-calendar-redis \
            --network ${network} \
            --volume /var/lib/wit-calendar/redis:/data \
            --restart no \
            redis:7-alpine
        '';
        ExecStop = "${pkgs.docker}/bin/docker stop wit-calendar-redis";
        Restart = "on-failure";
        RestartSec = "5s";
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "wit-calendar-redis";
      };
    };

    # ── PostgreSQL ────────────────────────────────────────────────────────────
    systemd.services.wit-calendar-db = {
      description = "WIT Calendar PostgreSQL";
      after = [
        "docker.service"
        "wit-calendar-network.service"
      ];
      requires = [
        "docker.service"
        "wit-calendar-network.service"
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStartPre = [
          "-${pkgs.docker}/bin/docker stop wit-calendar-db"
          "-${pkgs.docker}/bin/docker rm wit-calendar-db"
          "${pkgs.docker}/bin/docker pull postgres:17-alpine"
        ];
        ExecStart = ''
          ${pkgs.docker}/bin/docker run \
            --name wit-calendar-db \
            --network ${network} \
            --env-file ${cfg.environmentFile} \
            --env POSTGRES_USER=calendar \
            --env POSTGRES_DB=calendar_production \
            --volume /var/lib/wit-calendar/db:/var/lib/postgresql/data \
            --restart no \
            postgres:17-alpine
        '';
        ExecStop = "${pkgs.docker}/bin/docker stop wit-calendar-db";
        Restart = "on-failure";
        RestartSec = "10s";
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "wit-calendar-db";
      };
    };

    # ── Web (Rails via Thruster) ──────────────────────────────────────────────
    systemd.services.wit-calendar-web = {
      description = "WIT Calendar web";
      after = [
        "docker.service"
        "wit-calendar-network.service"
        "wit-calendar-db.service"
        "wit-calendar-redis.service"
      ];
      requires = [
        "docker.service"
        "wit-calendar-network.service"
        "wit-calendar-db.service"
        "wit-calendar-redis.service"
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";

        ExecStartPre = [
          # Resolve the image: file written by CI takes precedence over Nix default.
          (pkgs.writeShellScript "wit-calendar-resolve-image" ''
            IMAGE_FILE="/var/lib/wit-calendar/image-ref"
            IMAGE="${cfg.image}"
            if [ -f "$IMAGE_FILE" ]; then
              IMAGE=$(cat "$IMAGE_FILE")
            else
              echo "$IMAGE" > "$IMAGE_FILE"
            fi
            echo "$IMAGE" > /run/wit-calendar-image
          '')

          # Optionally log in to ghcr.io before pulling.
          (pkgs.writeShellScript "wit-calendar-registry-login" ''
            ${lib.optionalString (cfg.registryCredentialsFile != null) ''
              ${pkgs.docker}/bin/docker login ghcr.io \
                --username witcodingclub \
                --password-stdin < ${cfg.registryCredentialsFile}
            ''}
            IMAGE=$(cat /run/wit-calendar-image)
            ${pkgs.docker}/bin/docker pull "$IMAGE"
          '')

          "-${pkgs.docker}/bin/docker stop wit-calendar-web"
          "-${pkgs.docker}/bin/docker rm wit-calendar-web"

          # Wait for postgres then run db:prepare (create + migrate, idempotent).
          (pkgs.writeShellScript "wit-calendar-db-prepare" ''
            set -e
            IMAGE=$(cat /run/wit-calendar-image)
            echo "Waiting for postgres..."
            until ${pkgs.docker}/bin/docker exec wit-calendar-db \
                pg_isready -U calendar -h localhost -q; do
              sleep 2
            done
            echo "Running db:prepare..."
            ${pkgs.docker}/bin/docker run --rm \
              --network ${network} \
              --env-file ${cfg.environmentFile} \
              --env RAILS_ENV=production \
              --env PGHOST=wit-calendar-db \
              --env PGPORT=5432 \
              "$IMAGE" \
              bin/rails db:prepare
          '')
        ];

        ExecStart = pkgs.writeShellScript "wit-calendar-web-start" ''
          IMAGE=$(cat /run/wit-calendar-image)
          exec ${pkgs.docker}/bin/docker run \
            --name wit-calendar-web \
            --network ${network} \
            --publish 127.0.0.1:${toString cfg.port}:3000 \
            --env-file ${cfg.environmentFile} \
            --env RAILS_ENV=production \
            --env PGHOST=wit-calendar-db \
            --env PGPORT=5432 \
            --env REDIS_URL=redis://wit-calendar-redis:6379/0 \
            --env SOLID_QUEUE_IN_PUMA=true \
            --env RAILS_LOG_TO_STDOUT=true \
            --volume wit_calendar_backend_storage:/rails/storage \
            --restart no \
            "$IMAGE"
        '';

        ExecStop = "${pkgs.docker}/bin/docker stop wit-calendar-web";
        Restart = "on-failure";
        RestartSec = "10s";
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "wit-calendar-web";
      };
    };

    # ── Traefik ───────────────────────────────────────────────────────────────
    environment.etc."traefik/conf.d/wit-calendar.toml" = {
      source = (pkgs.formats.toml { }).generate "wit-calendar.toml" {
        http = {
          routers.wit-calendar = {
            rule = "Host(`${cfg.hostname}`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "wit-calendar";
          };
          services.wit-calendar.loadBalancer.servers = [
            { url = "http://127.0.0.1:${toString cfg.port}"; }
          ];
        };
      };
    };
  };
}
