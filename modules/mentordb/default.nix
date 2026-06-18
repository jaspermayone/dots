# MentorDb — Rails 8.1 app for Mad River Mentoring.
# One instance per dedicated VM; container uses --network host so it can reach
# the host PostgreSQL at 127.0.0.1:5432 without a separate network bridge.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.mentordb;
in
{
  options.services.mentordb = {
    enable = lib.mkEnableOption "MentorDb Rails app";

    image = lib.mkOption {
      type = lib.types.str;
      example = "ghcr.io/singlefeather/mentordb:latest";
      description = "Docker image reference.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Host port Thruster binds to (passed as PORT env var).";
    };

    publicHostname = lib.mkOption {
      type = lib.types.str;
      example = "p.madrivermentoring.com";
      description = "Public hostname — used as BASE_URL for Rails link generation.";
    };

    railsEnv = lib.mkOption {
      type = lib.types.str;
      default = "production";
      description = "RAILS_ENV value passed to the container.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to agenix env file with instance secrets. Must contain at minimum:
          RAILS_MASTER_KEY=...
          LOCKBOX_MASTER_KEY=...
          DATABASE_URL=postgresql://mentordb@127.0.0.1/mentordb
          CACHE_DATABASE_URL=postgresql://mentordb@127.0.0.1/mentordb_cache
          QUEUE_DATABASE_URL=postgresql://mentordb@127.0.0.1/mentordb_queue
          CABLE_DATABASE_URL=postgresql://mentordb@127.0.0.1/mentordb_cable
          SMTP_ADDRESS=smtp.gmail.com
          SMTP_PORT=587
          SMTP_USERNAME=...
          SMTP_PASSWORD=...
          MAILER_FROM_ADDRESS=...
      '';
    };

    databaseUser = lib.mkOption {
      type = lib.types.str;
      default = "mentordb";
      description = "PostgreSQL role name for the app.";
    };

    databaseName = lib.mkOption {
      type = lib.types.str;
      default = "mentordb";
      description = "Base PostgreSQL database name. Cache/queue/cable databases are derived from it.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = true;

    services.postgresql = {
      enable = true;
      package = pkgs.postgresql_16;
      ensureUsers = [
        {
          name = cfg.databaseUser;
          # owns the primary DB (same name as user); auxiliary DBs are set by
          # the mentordb-db-owner oneshot below after ensureDatabases runs.
          ensureDBOwnership = true;
        }
      ];
      ensureDatabases = [
        cfg.databaseName
        "${cfg.databaseName}_cache"
        "${cfg.databaseName}_queue"
        "${cfg.databaseName}_cable"
      ];
      # Trust all local + loopback connections — the Docker container reaches pg
      # via 127.0.0.1 with --network host, no password needed.
      authentication = pkgs.lib.mkOverride 10 ''
        local all all              trust
        host  all all 127.0.0.1/32 trust
        host  all all ::1/128      trust
      '';
    };

    # Ensure the auxiliary databases are owned by the mentordb role.
    # ensureDBOwnership only covers the primary (same-name) DB; this oneshot
    # runs once after postgresql.service has applied ensureUsers/ensureDatabases.
    systemd.services.mentordb-db-owner = {
      description = "Set ownership of auxiliary MentorDb databases";
      after = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "postgres";
        ExecStart = pkgs.writeShellScript "mentordb-db-owner" ''
          ${pkgs.postgresql_16}/bin/psql -c "ALTER DATABASE ${cfg.databaseName}_cache OWNER TO ${cfg.databaseUser};"
          ${pkgs.postgresql_16}/bin/psql -c "ALTER DATABASE ${cfg.databaseName}_queue OWNER TO ${cfg.databaseUser};"
          ${pkgs.postgresql_16}/bin/psql -c "ALTER DATABASE ${cfg.databaseName}_cable OWNER TO ${cfg.databaseUser};"
          # PostgreSQL 15+ revoked CREATE on public schema by default; grant it
          # explicitly on all four databases so db:prepare can create tables.
          ${pkgs.postgresql_16}/bin/psql -d ${cfg.databaseName}       -c "GRANT ALL ON SCHEMA public TO ${cfg.databaseUser};"
          ${pkgs.postgresql_16}/bin/psql -d ${cfg.databaseName}_cache  -c "GRANT ALL ON SCHEMA public TO ${cfg.databaseUser};"
          ${pkgs.postgresql_16}/bin/psql -d ${cfg.databaseName}_queue  -c "GRANT ALL ON SCHEMA public TO ${cfg.databaseUser};"
          ${pkgs.postgresql_16}/bin/psql -d ${cfg.databaseName}_cable  -c "GRANT ALL ON SCHEMA public TO ${cfg.databaseUser};"
        '';
      };
    };

    systemd.services.mentordb = {
      description = "MentorDb (${cfg.publicHostname})";
      after = [
        "docker.service"
        "network-online.target"
        "postgresql.service"
        "mentordb-db-owner.service"
      ];
      requires = [
        "docker.service"
        "postgresql.service"
      ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        StateDirectory = "mentordb";
        ExecStartPre = [
          # Generate SECRET_KEY_BASE once; stable across restarts so sessions
          # survive container updates.
          (pkgs.writeShellScript "mentordb-secrets" ''
            env_file="/var/lib/mentordb/env"
            if [ ! -f "$env_file" ]; then
              umask 077
              echo "SECRET_KEY_BASE=$(${pkgs.openssl}/bin/openssl rand -hex 64)" > "$env_file"
            fi
          '')
          "-${pkgs.docker}/bin/docker stop mentordb"
          "-${pkgs.docker}/bin/docker rm mentordb"
          "${pkgs.docker}/bin/docker pull ${cfg.image}"
        ];
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.docker}/bin/docker run --name mentordb"
          # Share host network so the container can reach pg at 127.0.0.1:5432
          "--network host"
          "--env-file /var/lib/mentordb/env"
          "--env-file ${cfg.environmentFile}"
          "--env DISABLE_SSL=true"
          "--env RAILS_ENV=${cfg.railsEnv}"
          # HTTP_PORT: port Thruster (the Rails 8 proxy) binds externally.
          # TARGET_PORT: internal port Thruster forwards to Rails/Puma.
          "--env HTTP_PORT=${toString cfg.port}"
          "--env TARGET_PORT=${toString (cfg.port + 1)}"
          "--env BASE_URL=https://${cfg.publicHostname}"
          "--volume mentordb-storage:/rails/storage"
          cfg.image
        ];
        ExecStop = "${pkgs.docker}/bin/docker stop mentordb";
        Restart = "on-failure";
        RestartSec = "10s";
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "mentordb";
      };
    };

    # Tailscale traffic is trusted; public internet cannot reach port 3000.
    networking.firewall.trustedInterfaces = [ "tailscale0" ];
  };
}
