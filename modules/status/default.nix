# Status monitoring module - serves /status endpoints for shields.io badges
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.atelier.services.status;

  # Script to check services and write status JSON
  statusScript = pkgs.writeShellScript "status-check" ''
    set -euo pipefail
    STATUS_DIR="/var/lib/status"
    mkdir -p "$STATUS_DIR"

    # Check each configured service
    ${concatStringsSep "\n" (map (svc: ''
      if systemctl is-active --quiet ${escapeShellArg svc}; then
        echo "ok" > "$STATUS_DIR/${svc}"
      else
        rm -f "$STATUS_DIR/${svc}"
      fi
    '') cfg.services)}

    # Always write host status (if this runs, host is up)
    echo "ok" > "$STATUS_DIR/${cfg.hostname}"

    # Build services JSON
    SERVICES_JSON="{"
    ${concatStringsSep "\n" (imap0 (i: svc: ''
      if systemctl is-active --quiet ${escapeShellArg svc}; then
        SERVICES_JSON="$SERVICES_JSON${if i > 0 then "," else ""}\"${svc}\":true"
      else
        SERVICES_JSON="$SERVICES_JSON${if i > 0 then "," else ""}\"${svc}\":false"
      fi
    '') cfg.services)}
    SERVICES_JSON="$SERVICES_JSON}"

    # Write full status JSON
    cat > "$STATUS_DIR/status.json" << EOF
    {
      "hostname": "${cfg.hostname}",
      "timestamp": "$(date -Iseconds)",
      "services": $SERVICES_JSON
    }
    EOF
  '';
in
{
  options.atelier.services.status = {
    enable = mkEnableOption "status monitoring endpoints";

    hostname = mkOption {
      type = types.str;
      description = "Hostname for this machine's status endpoint";
    };

    domain = mkOption {
      type = types.str;
      description = "Domain to serve status on";
    };

    services = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of systemd services to monitor";
    };

    cloudflareCredentialsFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to Cloudflare credentials file for DNS challenge";
    };
  };

  config = mkIf cfg.enable {
    # Timer to update status every minute
    systemd.services.status-check = {
      description = "Update status endpoints";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = statusScript;
      };
    };

    systemd.timers.status-check = {
      description = "Run status check every minute";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "1min";
      };
    };

    # Ensure status directory exists
    systemd.tmpfiles.rules = [
      "d /var/lib/status 0755 root root -"
    ];

    # Caddy virtual host for status
    services.caddy.virtualHosts."${cfg.domain}".extraConfig = ''
      ${optionalString (cfg.cloudflareCredentialsFile != null) ''
      tls {
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
      }
      ''}

      # Individual host status (returns 200 if file exists)
      @status_host path /status/${cfg.hostname}
      handle @status_host {
        @online file /var/lib/status/${cfg.hostname}
        handle @online {
          respond "ok" 200
        }
        handle {
          respond "offline" 503
        }
      }

      # Service status endpoints
      ${concatStringsSep "\n" (map (svc: ''
      @status_${svc} path /status/service/${svc}
      handle @status_${svc} {
        @online_${svc} file /var/lib/status/${svc}
        handle @online_${svc} {
          respond "ok" 200
        }
        handle {
          respond "offline" 503
        }
      }
      '') cfg.services)}

      # Full status JSON
      @status_json path /status
      handle @status_json {
        root * /var/lib/status
        rewrite * /status.json
        file_server
        header Content-Type application/json
      }

      # Root redirect to status
      handle {
        respond "alastor.hogwarts.channel - see /status" 200
      }
    '';
  };
}
