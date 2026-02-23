# Supergateway MCP reverse proxy via Caddy
{ config, pkgs, lib, ... }:

let
  # MCP proxy configurations
  mcpProxies = {
    obsidian = {
      domain = "obsidian.mcp.hogwarts.dev";
      upstream = "dippet.wildebeest-stargazer.ts.net:8767";
      secretKey = "obsidian";
      envVar = "MCP_KEY_OBSIDIAN";
      favicon = "💎";
    };

    obsidian-search = {
      domain = "obsidian-search.mcp.hogwarts.dev";
      upstream = "dippet.wildebeest-stargazer.ts.net:8766";
      secretKey = "obsidian-search";
      envVar = "MCP_KEY_OBSIDIAN_SEARCH";
      favicon = "🔍";
    };

    mbta = {
      domain = "mbta.mcp.hogwarts.dev";
      upstream = "dippet.wildebeest-stargazer.ts.net:8768";
      secretKey = "mbta";
      envVar = "MCP_KEY_MBTA";
      favicon = "🚇";
    };
  };

  # Generate Caddy virtualHost config for each MCP
  mkCaddyVhost = name: cfg: {
    "${cfg.domain}" = {
      extraConfig = ''
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
        }

        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        }

        # Health check - no auth required
        handle /health {
          respond "OK" 200
        }

        ${lib.optionalString (cfg ? favicon) ''
        # Favicon - no auth required
        handle /favicon.ico {
          header Content-Type image/svg+xml
          respond `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><text y=".9em" font-size="90">${cfg.favicon}</text></svg>` 200
        }
        ''}

        # Require Authorization header
        @missing_auth not header Authorization *
        handle @missing_auth {
          respond `{"error": "Missing Authorization header. Use: Bearer YOUR_API_KEY"}` 401
        }

        # Validate API key against secret
        @invalid_auth not header Authorization "Bearer {env.${cfg.envVar}}"
        handle @invalid_auth {
          respond `{"error": "Invalid API key"}` 403
        }

        # Proxy to upstream MCP (flush_interval -1 enables SSE streaming)
        reverse_proxy ${cfg.upstream} {
          flush_interval -1
          header_up Host {upstream_hostport}
          header_up X-Forwarded-Proto {scheme}
          header_up X-Forwarded-For {remote}
        }
      '';
    };
  };

in {
  # Add a virtual host to Caddy for each MCP
  services.caddy.virtualHosts = pkgs.lib.attrsets.mergeAttrsList (
    pkgs.lib.attrsets.mapAttrsToList mkCaddyVhost mcpProxies
  );

  # Generate the env file at activation time (runs before any services start,
  # after agenix has decrypted secrets) so Caddy's EnvironmentFile always exists.
  system.activationScripts.mcp-caddy-env = {
    deps = [ "agenix" ];
    text = ''
      SECRET="${config.age.secrets.mcp-api-keys.path}"
      OUT="/var/lib/caddy/mcp-keys.env"
      mkdir -p /var/lib/caddy
      if [ -f "$SECRET" ]; then
        (
          ${lib.concatMapStringsSep "\n" (name: let cfg = mcpProxies.${name}; in ''
            KEY=$(${pkgs.jq}/bin/jq -r '.["${cfg.secretKey}"][0] // ""' "$SECRET")
            echo '${cfg.envVar}='"$KEY"
          '') (builtins.attrNames mcpProxies)}
        ) > "$OUT"
        chmod 600 "$OUT"
        chown caddy:caddy "$OUT"
      fi
    '';
  };

  systemd.services.caddy.serviceConfig.EnvironmentFile = [ "/var/lib/caddy/mcp-keys.env" ];

  # Agenix secret for MCP API keys (JSON format)
  # { "omnifocus": ["key1", "key2"], "other-mcp": ["key1"] }
  age.secrets.mcp-api-keys = {
    file = ../../secrets/mcp-api-keys.age;
    mode = "400";
  };
}
