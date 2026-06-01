# Basecamp ONCE-style apps (Writebook, Campfire, Fizzy, …) run as plain Docker
# containers fronted by alastor's Traefik — NOT via the `once` CLI, which ships
# its own kamal-proxy that hardcodes host ports 80/443 and collides with Traefik.
#
# Each app is the same Thruster/Rails image: listens on :80, persists data in
# /rails/storage, needs SECRET_KEY_BASE, and honours DISABLE_SSL=true to serve
# plain HTTP so Traefik can terminate TLS at the edge (X-Forwarded-Proto=https
# is added by Traefik, same as kamal-proxy would). SECRET_KEY_BASE is generated
# once into the per-app StateDirectory so sessions survive restarts.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.basecampApps;

  appModule = lib.types.submodule (
    { name, ... }:
    {
      options = {
        image = lib.mkOption {
          type = lib.types.str;
          example = "ghcr.io/basecamp/writebook";
          description = "Docker image reference for the app.";
        };
        hostname = lib.mkOption {
          type = lib.types.str;
          example = "writebook.hogwarts.dev";
          description = "Public hostname Traefik routes to this app.";
        };
        port = lib.mkOption {
          type = lib.types.port;
          description = "Loopback host port bound to the container's :80.";
        };
        extraEnv = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "Extra environment variables passed to the container (e.g. VAPID_PUBLIC_KEY).";
        };
      };
    }
  );

  # Build the `--env k=v` flags for any extra environment.
  extraEnvFlags =
    app: lib.concatStringsSep " " (lib.mapAttrsToList (k: v: "--env ${k}=${lib.escapeShellArg v}") app.extraEnv);

  # Shared non-secret SMTP settings (host/port/username/from), applied to all
  # apps. The password stays in smtpEnvironmentFile.
  smtpSettingsFlags =
    lib.concatStringsSep " " (lib.mapAttrsToList (k: v: "--env ${k}=${lib.escapeShellArg v}") cfg.smtpSettings);
in
{
  options.services.basecampApps.apps = lib.mkOption {
    type = lib.types.attrsOf appModule;
    default = { };
    description = "Basecamp ONCE-style apps to run as Docker services behind Traefik.";
  };

  options.services.basecampApps.smtpEnvironmentFile = lib.mkOption {
    type = lib.types.nullOr lib.types.path;
    default = null;
    example = "/run/agenix/docuseal-smtp";
    description = ''
      Optional env file (e.g. an agenix secret) with the SMTP password —
      typically just SMTP_PASSWORD=... — passed to every app. Kept separate
      from smtpSettings so the secret value stays out of the Nix store.
      These Rails/Thruster apps gate sign-in behind emailed links, so without
      SMTP you can't actually log in.
    '';
  };

  options.services.basecampApps.smtpSettings = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    example = {
      SMTP_ADDRESS = "smtp.gmail.com";
      SMTP_PORT = "587";
      SMTP_USERNAME = "fizzy@hogwarts.dev";
      MAILER_FROM_ADDRESS = "fizzy@hogwarts.dev";
    };
    description = ''
      Shared non-secret SMTP env vars applied to every app (host, port,
      username, from). The password belongs in smtpEnvironmentFile.
      A per-app extraEnv value overrides the shared one (e.g. a different
      MAILER_FROM_ADDRESS per app).
    '';
  };

  config = lib.mkIf (cfg.apps != { }) {
    systemd.services = lib.mapAttrs' (
      name: app:
      lib.nameValuePair "basecamp-${name}" {
        description = "Basecamp ${name} (${app.hostname})";
        after = [ "docker.service" "network-online.target" ];
        requires = [ "docker.service" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          StateDirectory = "basecamp-${name}";
          ExecStartPre = [
            # Generate SECRET_KEY_BASE once; keep it out of the Nix store and
            # stable across restarts so user sessions aren't invalidated.
            (pkgs.writeShellScript "basecamp-${name}-secrets" ''
              env_file="/var/lib/basecamp-${name}/env"
              if [ ! -f "$env_file" ]; then
                umask 077
                echo "SECRET_KEY_BASE=$(${pkgs.openssl}/bin/openssl rand -hex 64)" > "$env_file"
              fi
            '')
            "-${pkgs.docker}/bin/docker stop basecamp-${name}"
            "-${pkgs.docker}/bin/docker rm basecamp-${name}"
            "${pkgs.docker}/bin/docker pull ${app.image}"
          ];
          ExecStart = lib.concatStringsSep " " (
            [
              "${pkgs.docker}/bin/docker run --name basecamp-${name}"
              "--publish 127.0.0.1:${toString app.port}:80"
              "--env-file /var/lib/basecamp-${name}/env"
            ]
            # SMTP creds (shared across apps) — without these, email-based
            # sign-in links never get delivered.
            ++ lib.optional (cfg.smtpEnvironmentFile != null) "--env-file ${cfg.smtpEnvironmentFile}"
            ++ [
              "--env DISABLE_SSL=true"
              # Public URL used for links in emails (magic sign-in, etc.) and
              # other absolute URLs. Always https://<hostname> behind Traefik.
              "--env BASE_URL=https://${app.hostname}"
              smtpSettingsFlags
              (extraEnvFlags app)
              "--volume basecamp-${name}:/rails/storage"
              "--volume basecamp-${name}:/storage"
              app.image
            ]
          );
          ExecStop = "${pkgs.docker}/bin/docker stop basecamp-${name}";
          Restart = "on-failure";
          RestartSec = "10s";
          StandardOutput = "journal";
          StandardError = "journal";
          SyslogIdentifier = "basecamp-${name}";
        };
      }
    ) cfg.apps;

    # Traefik dynamic config fragments (file provider watches /etc/traefik/conf.d).
    environment.etc = lib.mapAttrs' (
      name: app:
      lib.nameValuePair "traefik/conf.d/basecamp-${name}.toml" {
        source = (pkgs.formats.toml { }).generate "basecamp-${name}.toml" {
          http = {
            routers."basecamp-${name}" = {
              rule = "Host(`${app.hostname}`)";
              entryPoints = [ "websecure" ];
              tls.certResolver = "cloudflare";
              service = "basecamp-${name}";
            };
            services."basecamp-${name}".loadBalancer.servers = [
              { url = "http://127.0.0.1:${toString app.port}"; }
            ];
          };
        };
      }
    ) cfg.apps;
  };
}
