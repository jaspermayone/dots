# Status monitoring module - serves /status endpoints for shields.io badges
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.atelier.services.status;

  # Script to check services and write status JSON
  statusScript = pkgs.writeShellScript "status-check" ''
    set -euo pipefail
    STATUS_DIR="/var/lib/status"
    mkdir -p "$STATUS_DIR"

    # Check each configured service
    ${concatStringsSep "\n" (
      map (svc: ''
        if systemctl is-active --quiet ${escapeShellArg svc}; then
          echo "ok" > "$STATUS_DIR/${svc}"
        else
          rm -f "$STATUS_DIR/${svc}"
        fi
      '') cfg.services
    )}

    # Always write host status (if this runs, host is up)
    echo "ok" > "$STATUS_DIR/${cfg.hostname}"

    # Check remote hosts via ping (Tailscale)
    ${concatStringsSep "\n" (
      map (host: ''
        if ${pkgs.iputils}/bin/ping -c 1 -W 2 ${escapeShellArg host} >/dev/null 2>&1; then
          echo "ok" > "$STATUS_DIR/${host}"
        else
          rm -f "$STATUS_DIR/${host}"
        fi
      '') cfg.remoteHosts
    )}

    # Build services JSON
    SERVICES_JSON="{"
    ${concatStringsSep "\n" (
      imap0 (i: svc: ''
        if systemctl is-active --quiet ${escapeShellArg svc}; then
          SERVICES_JSON="$SERVICES_JSON${if i > 0 then "," else ""}\"${svc}\":true"
        else
          SERVICES_JSON="$SERVICES_JSON${if i > 0 then "," else ""}\"${svc}\":false"
        fi
      '') cfg.services
    )}
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

  # Python HTTP server that reads /var/lib/status/ and serves status endpoints
  statusServer = pkgs.writeText "status-server.py" ''
    import http.server
    import os
    import urllib.parse

    STATUS_DIR = "/var/lib/status"

    class StatusHandler(http.server.BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            pass  # suppress access logs

        def send_text(self, code, body, content_type="text/plain"):
            encoded = body.encode()
            self.send_response(code)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", len(encoded))
            self.end_headers()
            self.wfile.write(encoded)

        def do_GET(self):
            path = urllib.parse.urlparse(self.path).path.rstrip("/")

            # GET /status  ->  serve status.json
            if path == "/status":
                p = os.path.join(STATUS_DIR, "status.json")
                if os.path.exists(p):
                    with open(p) as f:
                        data = f.read()
                    self.send_text(200, data, "application/json")
                else:
                    self.send_text(503, '{"error":"status not yet written"}', "application/json")
                return

            # GET /status/service/<name>
            if path.startswith("/status/service/"):
                name = path[len("/status/service/"):]
                exists = os.path.exists(os.path.join(STATUS_DIR, name))
                self.send_text(200 if exists else 503, "ok" if exists else "offline")
                return

            # GET /status/<name>  (host or any other named marker)
            if path.startswith("/status/"):
                name = path[len("/status/"):]
                exists = os.path.exists(os.path.join(STATUS_DIR, name))
                self.send_text(200 if exists else 503, "ok" if exists else "offline")
                return

            # Root  ->  info blurb
            if path in ("", "/"):
                self.send_text(200, "${cfg.domain} - see /status")
                return

            self.send_text(404, "not found")

    if __name__ == "__main__":
        server = http.server.HTTPServer(("127.0.0.1", ${toString cfg.port}), StatusHandler)
        server.serve_forever()
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

    port = mkOption {
      type = types.int;
      default = 8093;
      description = "Internal port for the status HTTP server";
    };

    services = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of systemd services to monitor";
    };

    remoteHosts = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of remote hosts to check via ping (e.g. Tailscale hosts)";
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

    # Python HTTP server for status endpoints
    systemd.services.status-server = {
      description = "Status HTTP server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.python3}/bin/python3 ${statusServer}";
        Restart = "on-failure";
        DynamicUser = true;
        ReadOnlyPaths = [ "/var/lib/status" ];
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };

    # Ensure status directory exists
    systemd.tmpfiles.rules = [
      "d /var/lib/status 0755 root root -"
    ];

    # Traefik dynamic config fragment (file provider)
    environment.etc."traefik/conf.d/status.toml" = {
      source = (pkgs.formats.toml { }).generate "status.toml" {
        http = {
          routers.status = {
            rule = "Host(`${cfg.domain}`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "status";
          };
          services.status.loadBalancer.servers = [
            { url = "http://127.0.0.1:${toString cfg.port}"; }
          ];
        };
      };
    };
  };
}
