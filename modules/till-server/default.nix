# modules/till-server/default.nix
# till API server — clones usetill/cleanroom (private), builds via pnpm, runs via Node.
# Requires a GitHub PAT (read-only) for cloning and an agenix env file for runtime secrets.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.atelier.services.till-server;
in
{
  options.atelier.services.till-server = {
    enable = lib.mkEnableOption "till API server";

    hostname = lib.mkOption {
      type = lib.types.str;
      example = "api.usetill.dev";
      description = "Public hostname for the till API.";
    };

    port = lib.mkOption {
      type = lib.types.int;
      default = 3737;
      description = "Internal HTTP port for the Fastify server.";
    };

    repoTokenFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to a file containing a GitHub PAT (read-only) for cloning the private
        usetill/cleanroom repository. File should contain only the raw token, e.g.:
          github_pat_xxxxxxxxxxxxxxxxxxxx
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to env file with runtime secrets. Must contain DATABASE_URL plus any
        GitHub App / OAuth vars. The server connects to PostgreSQL via Unix socket,
        so DATABASE_URL can be:
          DATABASE_URL=postgresql://till@/till
        (PGHOST=/run/postgresql is injected automatically.)
        Optional vars:
          APP_URL=https://api.usetill.dev
          GITHUB_APP_ID=...
          GITHUB_APP_PRIVATE_KEY=...
          GITHUB_WEBHOOK_SECRET=...
          GITHUB_OAUTH_CLIENT_ID=...
          GITHUB_OAUTH_CLIENT_SECRET=...
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.till = {
      isSystemUser = true;
      group = "till";
    };
    users.groups.till = { };

    # Clone / update the repo and build on boot (or after a system activation).
    systemd.services.till-server-sync = {
      description = "Clone or update till server repository and build";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      before = [ "till-server.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "till";
        Group = "till";
        StateDirectory = "till-server";
        StateDirectoryMode = "0750";
        ExecStart = pkgs.writeShellScript "till-server-sync" ''
          set -euo pipefail
          export PATH="${pkgs.git}/bin:${pkgs.nodejs_22}/bin:${pkgs.pnpm}/bin:${pkgs.bash}/bin:$PATH"
          REPO=/var/lib/till-server/repo
          GITHUB_TOKEN=$(cat ${cfg.repoTokenFile})

          if [ -d "$REPO/.git" ]; then
            ${pkgs.git}/bin/git -C "$REPO" remote set-url origin \
              "https://x-access-token:$GITHUB_TOKEN@github.com/usetill/cleanroom.git"
            ${pkgs.git}/bin/git -C "$REPO" fetch --quiet origin
            ${pkgs.git}/bin/git -C "$REPO" reset --hard origin/HEAD
          else
            ${pkgs.git}/bin/git clone --depth 1 \
              "https://x-access-token:$GITHUB_TOKEN@github.com/usetill/cleanroom.git" \
              "$REPO"
          fi

          cd "$REPO"
          # --ignore-scripts skips better-sqlite3 (node-gyp) and esbuild native
          # builds — both are CLI-only deps the server doesn't use.
          ${pkgs.pnpm}/bin/pnpm install --frozen-lockfile --ignore-scripts
          ${pkgs.pnpm}/bin/pnpm --filter @till/shared build
          ${pkgs.pnpm}/bin/pnpm --filter @till/github build
          ${pkgs.pnpm}/bin/pnpm --filter @till/db build
          ${pkgs.pnpm}/bin/pnpm --filter @till/server build
        '';
      };
    };

    # Main Fastify server.
    systemd.services.till-server = {
      description = "till API server";
      after = [
        "network.target"
        "till-server-sync.service"
        "postgresql.service"
      ];
      requires = [
        "till-server-sync.service"
        "postgresql.service"
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = "till";
        Group = "till";
        WorkingDirectory = "/var/lib/till-server/repo";
        EnvironmentFile = cfg.environmentFile;
        Environment = [
          "NODE_ENV=production"
          "PORT=${toString cfg.port}"
          # Unix socket auth — pairs with `local all all trust` in pg_hba and
          # ensureUsers.ensureDBOwnership in configuration.nix.
          "PGHOST=/run/postgresql"
          "USER=till"
        ];
        ExecStart = "${pkgs.nodejs_22}/bin/node packages/server/dist/index.js";
        Restart = "on-failure";
        RestartSec = "5s";
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "till-server";
      };
    };

    # Traefik dynamic config fragment (hot-reloaded, no Traefik restart needed).
    environment.etc."traefik/conf.d/till-server.toml" = {
      source = (pkgs.formats.toml { }).generate "till-server.toml" {
        http = {
          routers.till-server = {
            rule = "Host(`${cfg.hostname}`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "till-server";
          };
          services.till-server.loadBalancer.servers = [
            { url = "http://127.0.0.1:${toString cfg.port}"; }
          ];
        };
      };
    };
  };
}
