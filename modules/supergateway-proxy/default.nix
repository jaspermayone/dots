# Supergateway MCP reverse proxy with SSL and API key authentication
{ config, pkgs, lib, ... }:

let
  # MCP proxy configurations
  mcpProxies = {
    omnifocus = {
      domain = "omnifocus.mcp.hogwarts.dev";
      upstreamHost = "dippet.local";  # or use IP if .local doesn't resolve
      upstreamPort = 8000;
    };

    # Add more MCPs here as needed
    # example-mcp = {
    #   domain = "example.mcp.hogwarts.dev";
    #   upstreamHost = "dippet.local";
    #   upstreamPort = 8001;
    # };
  };

  # Script to generate nginx auth map from agenix secret
  # This runs at nginx start time, not build time
  generateAuthMap = mcpName: pkgs.writeShellScript "generate-auth-map-${mcpName}" ''
    set -euo pipefail

    SECRET_FILE="${config.age.secrets.mcp-api-keys.path}"
    OUTPUT_FILE="/var/lib/nginx/auth-${mcpName}.conf"

    # Ensure directory exists
    mkdir -p /var/lib/nginx

    # Read API keys from secret and generate nginx map
    if [ -f "$SECRET_FILE" ]; then
      # Extract keys for this MCP from JSON
      KEYS=$(${pkgs.jq}/bin/jq -r '.["${mcpName}"] // [] | .[]' "$SECRET_FILE" 2>/dev/null || echo "")

      if [ -z "$KEYS" ]; then
        echo "Warning: No API keys found for ${mcpName}" >&2
        echo "# No keys configured for ${mcpName}" > "$OUTPUT_FILE"
        exit 0
      fi

      # Generate nginx config snippet with if statements
      {
        echo "# Auto-generated auth config for ${mcpName}"
        echo "# Generated at: $(date)"
        echo ""
        echo "set \$valid_key_${mcpName} 0;"
        echo "$KEYS" | while read -r key; do
          if [ -n "$key" ]; then
            echo "if (\$http_authorization = \"Bearer $key\") {"
            echo "  set \$valid_key_${mcpName} 1;"
            echo "}"
          fi
        done
      } > "$OUTPUT_FILE"

      chmod 644 "$OUTPUT_FILE"
      chown nginx:nginx "$OUTPUT_FILE"
    else
      echo "Error: Secret file $SECRET_FILE not found" >&2
      exit 1
    fi
  '';

  # Generate secure nginx virtual host config for each MCP
  mkSecureProxy = name: cfg: {
    "${cfg.domain}" = {
      forceSSL = true;
      enableACME = true;

      extraConfig = ''
        # Security headers
        add_header X-Frame-Options "DENY" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

        # Custom log format with API key prefix
        access_log /var/log/nginx/${cfg.domain}.access.log;
        error_log /var/log/nginx/${cfg.domain}.error.log;
      '';

      locations."/" = {
        proxyPass = "http://${cfg.upstreamHost}:${toString cfg.upstreamPort}";
        proxyWebsockets = true;

        extraConfig = ''
          # API Key Authentication
          if ($http_authorization = "") {
            return 401 '{"error": "Missing Authorization header. Use: Bearer YOUR_API_KEY"}';
          }

          # Load auth config generated from secret
          include /var/lib/nginx/auth-${name}.conf;

          if ($valid_key_${name} = 0) {
            return 403 '{"error": "Invalid API key"}';
          }

          # Rate limiting (burst up to 20 requests)
          limit_req zone=${name}_ratelimit burst=20 nodelay;

          # Proxy headers
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;

          # SSE-specific settings (disable buffering, long timeout)
          proxy_buffering off;
          proxy_cache off;
          proxy_read_timeout 86400s;  # 24 hours
          proxy_send_timeout 86400s;
          proxy_connect_timeout 30s;

          # Error handling
          proxy_next_upstream error timeout invalid_header http_500 http_502 http_503;
        '';
      };

      # Public health check endpoint (no auth required)
      locations."/health" = {
        return = "200 'OK'";
        extraConfig = ''
          add_header Content-Type text/plain;
          access_log off;
        '';
      };
    };
  };

in {
  # Nginx configuration with MCP proxies
  services.nginx = {
    enable = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    # Add rate limiting zones to http block (early in config)
    commonHttpConfig = ''
      # Rate limiting zones for MCP proxies (10 req/sec per IP)
      ${lib.concatMapStringsSep "\n" (name: ''
        limit_req_zone $binary_remote_addr zone=${name}_ratelimit:10m rate=10r/s;
      '') (builtins.attrNames mcpProxies)}
    '';

    # Virtual hosts for all MCP proxies
    virtualHosts = pkgs.lib.attrsets.mergeAttrsList (
      pkgs.lib.attrsets.mapAttrsToList mkSecureProxy mcpProxies
    );
  };

  # Generate auth config files before nginx starts
  systemd.services.nginx = {
    preStart = lib.mkAfter ''
      echo "Generating MCP auth configs..."
      ${lib.concatMapStringsSep "\n" (name: ''
        ${generateAuthMap name}
      '') (builtins.attrNames mcpProxies)}
    '';
    serviceConfig = {
      # Ensure nginx can read the secret
      SupplementaryGroups = [ "keys" ];
    };
  };

  # ACME for SSL certificates
  security.acme = {
    acceptTerms = true;
    defaults.email = "hey@jaspermayone.com";  # Adjust if needed
  };

  # Ensure firewall allows HTTP/HTTPS
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  # Fail2ban for additional security
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";

    jails = {
      # Ban IPs with repeated auth failures
      nginx-auth = ''
        enabled = true
        filter = nginx-auth
        port = http,https
        logpath = /var/log/nginx/error.log
        maxretry = 5
        findtime = 600
        bantime = 3600
      '';

      # Ban IPs hitting rate limits repeatedly
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

  # Agenix secret for MCP API keys
  age.secrets.mcp-api-keys = {
    file = ../../secrets/mcp-api-keys.age;
    owner = "nginx";
    mode = "400";
  };
}
