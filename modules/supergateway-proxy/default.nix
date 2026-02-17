# Supergateway MCP reverse proxy with SSL and API key authentication
{ config, pkgs, lib, ... }:

let
  # Read API keys from agenix secret
  # Secret file format: { "omnifocus": ["key1", "key2"], "other-mcp": ["key3"] }
  apiKeysJson = builtins.readFile config.age.secrets.mcp-api-keys.path;
  apiKeysData = builtins.fromJSON apiKeysJson;

  # MCP proxy configurations
  mcpProxies = {
    omnifocus = {
      domain = "omnifocus.mcp.hogwarts.dev";
      upstreamHost = "dippet.local";  # or use IP if .local doesn't resolve
      upstreamPort = 8000;
      apiKeys = apiKeysData.omnifocus or [];  # Read from agenix secret
    };

    # Add more MCPs here as needed
    # example-mcp = {
    #   domain = "example.mcp.hogwarts.dev";
    #   upstreamHost = "dippet.local";
    #   upstreamPort = 8001;
    #   apiKeys = apiKeysData.example-mcp or [];
    # };
  };

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

        # Rate limiting zone (10 req/sec per IP)
        limit_req_zone $binary_remote_addr zone=${name}_ratelimit:10m rate=10r/s;

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

          # Validate API key against allowed keys
          set $valid_key 0;
          ${lib.concatMapStringsSep "\n" (key: ''
            if ($http_authorization = "Bearer ${key}") {
              set $valid_key 1;
            }
          '') cfg.apiKeys}

          if ($valid_key = 0) {
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
  # Generate nginx virtual hosts for all MCP proxies
  services.nginx.virtualHosts = pkgs.lib.attrsets.mergeAttrsList (
    pkgs.lib.attrsets.mapAttrsToList mkSecureProxy mcpProxies
  );

  # Ensure nginx is enabled with recommended settings
  services.nginx = {
    enable = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
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
