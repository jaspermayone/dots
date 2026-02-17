# Supergateway MCP reverse proxy via Caddy
{ config, pkgs, lib, ... }:

let
  # MCP proxy configurations
  mcpProxies = {
    omnifocus = {
      domain = "omnifocus.mcp.hogwarts.dev";
      upstream = "dippet.wildebeest-stargazer.ts.net:8000";
      # Name of the key in mcp-api-keys.age JSON: { "omnifocus": ["key1"] }
      secretKey = "omnifocus";
      # Env var name that will hold the API key for use in Caddy config
      envVar = "MCP_KEY_OMNIFOCUS";
    };

    # Add more MCPs here:
    # example = {
    #   domain = "example.mcp.hogwarts.dev";
    #   upstream = "dippet.wildebeest-stargazer.ts.net:8001";
    #   secretKey = "example";
    #   envVar = "MCP_KEY_EXAMPLE";
    # };
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

  # One-shot service that extracts API keys from the agenix JSON secret
  # and writes them as KEY=VALUE pairs to /run/mcp-keys.env for Caddy to load
  systemd.services.mcp-env-gen = {
    description = "Generate MCP API key env vars from agenix secret";
    before = [ "caddy.service" ];
    wantedBy = [ "caddy.service" ];
    after = [ "agenix.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      SECRET="${config.age.secrets.mcp-api-keys.path}"
      OUT="/run/mcp-keys.env"

      ${lib.concatMapStringsSep "\n" (name: let cfg = mcpProxies.${name}; in ''
        KEY=$(${pkgs.jq}/bin/jq -r '.["${cfg.secretKey}"][0] // ""' "$SECRET")
        echo '${cfg.envVar}='"$KEY"
      '') (builtins.attrNames mcpProxies)} > "$OUT"

      chmod 600 "$OUT"
    '';
  };

  # Load the generated env file into Caddy alongside the existing Cloudflare creds
  systemd.services.caddy = {
    requires = [ "mcp-env-gen.service" ];
    after = [ "mcp-env-gen.service" ];
    serviceConfig.EnvironmentFile = [ "/run/mcp-keys.env" ];
  };

  # Agenix secret for MCP API keys (JSON format)
  # { "omnifocus": ["key1", "key2"], "other-mcp": ["key1"] }
  age.secrets.mcp-api-keys = {
    file = ../../secrets/mcp-api-keys.age;
    mode = "400";
  };
}
