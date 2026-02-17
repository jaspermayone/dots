# Supergateway MCP reverse proxy with SSL and API key authentication
{ config, pkgs, lib, ... }:

let
  # MCP proxy configurations
  mcpProxies = {
    omnifocus = {
      domain = "omnifocus.mcp.hogwarts.dev";
      upstreamHost = "dippet.local";
      upstreamPort = 8000;
    };

    # Add more MCPs here as needed
    # example-mcp = {
    #   domain = "example.mcp.hogwarts.dev";
    #   upstreamHost = "dippet.local";
    #   upstreamPort = 8001;
    # };
  };

  # Build-time placeholder auth files (live in the Nix store, always present)
  # nginx -t will include these. They deny all requests until the preStart
  # script overwrites the symlink target with real keys from the agenix secret.
  mkPlaceholder = name: pkgs.writeText "auth-${name}-placeholder.conf" ''
    # Placeholder - overwritten at nginx startup from agenix secret
    set $valid_key_${name} 0;
  '';

  # Script to generate real auth config from agenix secret at startup
  # Writes to /run/nginx/ which is the service's RuntimeDirectory (always writable)
  generateAuthMap = name: pkgs.writeShellScript "generate-auth-map-${name}" ''
    set -euo pipefail

    SECRET_FILE="${config.age.secrets.mcp-api-keys.path}"
    OUTPUT_FILE="/run/nginx/auth-${name}.conf"

    if [ ! -f "$SECRET_FILE" ]; then
      echo "mcp-auth: secret file not found, keeping placeholder" >&2
      exit 0
    fi

    KEYS=$(${pkgs.jq}/bin/jq -r '.["${name}"] // [] | .[]' "$SECRET_FILE" 2>/dev/null || true)

    if [ -z "$KEYS" ]; then
      echo "mcp-auth: no keys found for ${name}, keeping placeholder" >&2
      exit 0
    fi

    {
      echo "# Generated at $(date) from agenix secret"
      echo "set \$valid_key_${name} 0;"
      echo "$KEYS" | while read -r key; do
        [ -n "$key" ] || continue
        echo "if (\$http_authorization = \"Bearer $key\") { set \$valid_key_${name} 1; }"
      done
    } > "$OUTPUT_FILE"
  '';

  # Generate nginx virtual host config for each MCP
  mkSecureProxy = name: cfg: {
    "${cfg.domain}" = {
      forceSSL = true;
      enableACME = true;

      extraConfig = ''
        add_header X-Frame-Options "DENY" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

        access_log /var/log/nginx/${cfg.domain}.access.log;
        error_log /var/log/nginx/${cfg.domain}.error.log;
      '';

      locations."/" = {
        proxyPass = "http://${cfg.upstreamHost}:${toString cfg.upstreamPort}";
        proxyWebsockets = true;

        extraConfig = ''
          if ($http_authorization = "") {
            return 401 '{"error": "Missing Authorization header. Use: Bearer YOUR_API_KEY"}';
          }

          # Include auth config - written by preStart from agenix secret.
          # Falls back to build-time placeholder (denies all) if not yet generated.
          include /run/nginx/auth-${name}.conf;

          if ($valid_key_${name} = 0) {
            return 403 '{"error": "Invalid API key"}';
          }

          limit_req zone=${name}_ratelimit burst=20 nodelay;

          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;

          proxy_buffering off;
          proxy_cache off;
          proxy_read_timeout 86400s;
          proxy_send_timeout 86400s;
          proxy_connect_timeout 30s;

          proxy_next_upstream error timeout invalid_header http_500 http_502 http_503;
        '';
      };

      locations."/health" = {
        return = "200 'OK'";
        extraConfig = "access_log off;";
      };
    };
  };

in {
  services.nginx = {
    enable = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    commonHttpConfig = lib.concatMapStringsSep "\n" (name: ''
      limit_req_zone $binary_remote_addr zone=${name}_ratelimit:10m rate=10r/s;
    '') (builtins.attrNames mcpProxies);

    virtualHosts = pkgs.lib.attrsets.mergeAttrsList (
      pkgs.lib.attrsets.mapAttrsToList mkSecureProxy mcpProxies
    );
  };

  # Seed /run/nginx/ with placeholder auth files at activation so nginx -t
  # always passes, then overwrite with real keys before nginx actually starts.
  systemd.tmpfiles.rules = pkgs.lib.attrsets.mapAttrsToList (name: _:
    "L+ /run/nginx/auth-${name}.conf - - - - ${mkPlaceholder name}"
  ) mcpProxies;

  systemd.services.nginx = {
    # Write real auth configs into /run/nginx/ before nginx -t runs.
    # /run/nginx is the nginx RuntimeDirectory so it's always writable.
    preStart = lib.mkBefore (lib.concatMapStringsSep "\n" (name: ''
      ${generateAuthMap name}
    '') (builtins.attrNames mcpProxies));

    serviceConfig.SupplementaryGroups = [ "keys" ];
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "hey@jaspermayone.com";
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];

  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";
    jails = {
      nginx-auth = ''
        enabled = true
        filter = nginx-auth
        port = http,https
        logpath = /var/log/nginx/error.log
        maxretry = 5
        findtime = 600
        bantime = 3600
      '';
      nginx-limit-req = ''
        enabled = true
        filter = nginx-limit-req
        port = http,https
        logpath = /var/log/nginx/error.log
        maxretry = 10
        findtime = 60
        bantime = 600
      '';
    };
  };

  age.secrets.mcp-api-keys = {
    file = ../../secrets/mcp-api-keys.age;
    owner = "nginx";
    mode = "400";
  };
}
