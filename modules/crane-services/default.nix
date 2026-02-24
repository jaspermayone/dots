# crane services — Docker Compose stack for cranebrowser backend
#
# Clones cranebrowser/services from GitHub at activation time using a PAT,
# then runs the compose stack. This avoids bundling the private repo into
# the dots flake closure, which keeps `system.autoUpgrade` working correctly.
{ config, lib, pkgs, ... }:

let
  cfg = config.crane.services;

  # Non-secret env vars rendered as a string (never goes in the Nix store
  # with a secret value — HMAC_SECRET is appended at activation time).
  envVars = lib.concatLines (lib.filter (s: s != "") [
    "SERVICES_HOSTNAME=${cfg.hostname}"
    "PROXY_BASE_URL=${cfg.proxyBaseUrl}"
    "UBO_PROXY_BASE_URL=${cfg.uboProxyBaseUrl}"
    (lib.optionalString (cfg.uboAssetsJsonUrl != null)
      "UBO_ASSETS_JSON_URL=${cfg.uboAssetsJsonUrl}")
    (lib.optionalString (cfg.uboAssetsJsonSha256 != null)
      "UBO_ASSETS_JSON_SHA256=${cfg.uboAssetsJsonSha256}")
  ]);

in {
  options.crane.services = {
    enable = lib.mkEnableOption "crane services (Docker Compose stack)";

    hostname = lib.mkOption {
      type = lib.types.str;
      example = "services.cranebrowser.com";
      description = "Public hostname (SERVICES_HOSTNAME).";
    };

    proxyBaseUrl = lib.mkOption {
      type = lib.types.str;
      example = "https://services.cranebrowser.com/ext";
      description = "Base URL for ext_proxy (PROXY_BASE_URL).";
    };

    uboProxyBaseUrl = lib.mkOption {
      type = lib.types.str;
      example = "https://services.cranebrowser.com/ubo/";
      description = "Base URL for ubo_proxy (UBO_PROXY_BASE_URL).";
    };

    uboAssetsJsonUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Override URL for assets.json (UBO_ASSETS_JSON_URL). Optional.";
    };

    uboAssetsJsonSha256 = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "SHA-256 of a custom assets.json (UBO_ASSETS_JSON_SHA256). Optional.";
    };

    repoTokenFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to a file containing a GitHub PAT with read access to
        cranebrowser/services. Used to clone/pull the repo at activation time.
        Use an agenix secret: config.age.secrets.crane-services-token.path
      '';
    };

    hmacSecretFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to a file containing the raw HMAC_SECRET value for ext_proxy.
        Use an agenix secret: config.age.secrets.crane-services-hmac.path
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open ports 80 and 443 (TCP) and 443 (UDP/HTTP3) in the firewall.";
    };
  };

  config = lib.mkIf cfg.enable {

    # ── Docker ────────────────────────────────────────────────────────────────
    virtualisation.docker = {
      enable = true;
      daemon.settings.ipv6 = true;
    };

    environment.systemPackages = [ pkgs.docker-compose ];

    # ── Directory layout ──────────────────────────────────────────────────────
    systemd.tmpfiles.rules = [
      "d /opt/crane-services                 0755 root root -"
      "d /opt/crane-services/private         0750 root root -"
      "d /opt/crane-services/private/certs   0750 root root -"
      "d /opt/crane-services/private/acme-tmp 0755 root root -"
    ];

    # ── Source sync + .env ────────────────────────────────────────────────────
    # Runs on every nixos-rebuild switch. Clones on first run, pulls on
    # subsequent runs. Secrets are read at runtime so they never touch the
    # Nix store.
    system.activationScripts.crane-services-deploy = {
      deps = [ "agenix" "users" "groups" ];
      text = ''
        set -euo pipefail

        TOKEN=$(cat "${cfg.repoTokenFile}")
        REPO_URL="https://x-access-token:$TOKEN@github.com/cranebrowser/services.git"
        WORK_DIR="/opt/crane-services"

        if [ -d "$WORK_DIR/.git" ]; then
          echo "[crane-services] pulling latest source..."
          ${pkgs.git}/bin/git -C "$WORK_DIR" remote set-url origin "$REPO_URL"
          ${pkgs.git}/bin/git -C "$WORK_DIR" pull --ff-only
        else
          echo "[crane-services] cloning cranebrowser/services..."
          ${pkgs.git}/bin/git clone "$REPO_URL" "$WORK_DIR"
        fi

        echo "[crane-services] writing .env..."
        HMAC_SECRET=$(cat "${cfg.hmacSecretFile}")
        printf '%s\nHMAC_SECRET=%s\n' \
          ${lib.escapeShellArg envVars} \
          "$HMAC_SECRET" \
          > "$WORK_DIR/.env"
        chmod 600 "$WORK_DIR/.env"
      '';
    };

    # ── Systemd service ───────────────────────────────────────────────────────
    systemd.services.crane-services = {
      description = "Crane services (Docker Compose)";
      after    = [ "docker.service" "network-online.target" ];
      wants    = [ "network-online.target" ];
      requires = [ "docker.service" ];
      wantedBy = [ "multi-user.target" ];

      # Restart when config values change across generations.
      restartTriggers = [ cfg.hostname cfg.proxyBaseUrl cfg.uboProxyBaseUrl ];

      serviceConfig = {
        Type             = "oneshot";
        RemainAfterExit  = true;
        WorkingDirectory = "/opt/crane-services";
        ExecStart        = "${pkgs.docker-compose}/bin/docker-compose up --build -d";
        ExecStop         = "${pkgs.docker-compose}/bin/docker-compose down";
        TimeoutStartSec  = "10min";
      };
    };

    # ── Daily rebuild timer ───────────────────────────────────────────────────
    systemd.services.crane-services-rebuild = {
      description = "Crane services daily rebuild";
      after    = [ "crane-services.service" ];
      requires = [ "crane-services.service" ];
      serviceConfig = {
        Type             = "oneshot";
        WorkingDirectory = "/opt/crane-services";
        ExecStart        = "${pkgs.docker-compose}/bin/docker-compose up --build -d";
        TimeoutStartSec  = "10min";
      };
    };

    systemd.timers.crane-services-rebuild = {
      description = "Daily crane services rebuild";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "05:00"; # offset from autoUpgrade at 04:00
        Persistent = true;
      };
    };

    # ── Firewall ──────────────────────────────────────────────────────────────
    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ 80 443 ];
      allowedUDPPorts = [ 443 ];
    };
  };
}
