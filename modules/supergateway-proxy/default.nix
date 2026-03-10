# Supergateway MCP reverse proxy via Traefik + Python forward-auth
{ config, pkgs, lib, ... }:

let
  # MCP proxy configurations
  mcpProxies = {
    obsidian = {
      domain = "obsidian.mcp.hogwarts.dev";
      upstream = "http://dippet.wildebeest-stargazer.ts.net:8767";
      secretKey = "obsidian";
      favicon = "💎";
    };
    obsidian-search = {
      domain = "obsidian-search.mcp.hogwarts.dev";
      upstream = "http://dippet.wildebeest-stargazer.ts.net:8766";
      secretKey = "obsidian-search";
      favicon = "🔍";
    };
    mbta = {
      domain = "mbta.mcp.hogwarts.dev";
      upstream = "http://dippet.wildebeest-stargazer.ts.net:8768";
      secretKey = "mbta";
      favicon = "🚇";
    };
    parcel-tracking = {
      domain = "parcel-tracking.mcp.hogwarts.dev";
      upstream = "http://dippet.wildebeest-stargazer.ts.net:8769";
      secretKey = "parcel-tracking";
      favicon = "📦";
    };
  };

  mcpNames = builtins.attrNames mcpProxies;

  # Python forward-auth service: validates Bearer tokens from mcp-api-keys JSON
  mcpAuthServer = pkgs.writeText "mcp-auth-server.py" ''
    import http.server
    import json
    import os

    KEYS_FILE = os.environ["KEYS_FILE"]

    def load_keys():
        with open(KEYS_FILE) as f:
            return json.load(f)

    class AuthHandler(http.server.BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            pass

        def send_status(self, code, body=""):
            encoded = body.encode()
            self.send_response(code)
            self.send_header("Content-Length", len(encoded))
            self.end_headers()
            if encoded:
                self.wfile.write(encoded)

        def do_GET(self):
            host = self.headers.get("X-Forwarded-Host", "")
            auth = self.headers.get("Authorization", "")

            try:
                keys = load_keys()
            except Exception as e:
                self.send_status(500, f"key load error: {e}")
                return

            matched_keys = None
            for key_name, key_list in keys.items():
                if host.startswith(key_name + "."):
                    matched_keys = key_list
                    break

            if matched_keys is None:
                self.send_status(403, "unknown host")
                return

            if not auth.startswith("Bearer "):
                self.send_status(401, "missing Authorization header")
                return

            token = auth[len("Bearer "):]
            if token in matched_keys:
                self.send_status(200)
            else:
                self.send_status(403, "invalid token")

    if __name__ == "__main__":
        server = http.server.HTTPServer(("127.0.0.1", 8094), AuthHandler)
        server.serve_forever()
  '';

  # Build routers attrset for all MCPs
  mcpRouters = lib.foldl' (acc: name:
    let mcpCfg = mcpProxies.${name}; in
    acc // {
      "mcp-${name}-public" = {
        rule = "Host(`${mcpCfg.domain}`) && (Path(`/health`) || Path(`/favicon.ico`))";
        entryPoints = [ "websecure" ];
        tls.certResolver = "cloudflare";
        service = "mcp-${name}";
        priority = 20;
      };
      "mcp-${name}" = {
        rule = "Host(`${mcpCfg.domain}`)";
        entryPoints = [ "websecure" ];
        tls.certResolver = "cloudflare";
        middlewares = [ "hsts" "mcp-auth" ];
        service = "mcp-${name}";
        priority = 10;
      };
    }
  ) {} mcpNames;

  # Build services attrset for all MCPs
  mcpServices = lib.foldl' (acc: name:
    let mcpCfg = mcpProxies.${name}; in
    acc // {
      "mcp-${name}".loadBalancer = {
        servers = [ { url = mcpCfg.upstream; } ];
        responseForwarding.flushInterval = "-1"; # SSE streaming
      };
    }
  ) {} mcpNames;

in {
  # Python forward-auth service
  systemd.services.mcp-auth = {
    description = "MCP bearer-token forward-auth service";
    after = [ "network.target" "agenix.service" ];
    wantedBy = [ "multi-user.target" ];
    environment.KEYS_FILE = config.age.secrets.mcp-api-keys.path;
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.python3}/bin/python3 ${mcpAuthServer}";
      Restart = "on-failure";
      User = "mcp-auth";
      Group = "mcp-auth";
      NoNewPrivileges = true;
      PrivateTmp = true;
    };
  };

  users.users.mcp-auth = {
    isSystemUser = true;
    group = "mcp-auth";
  };
  users.groups.mcp-auth = { };

  # Traefik dynamic config fragment (file provider)
  environment.etc."traefik/conf.d/mcp.toml" = {
    source = (pkgs.formats.toml { }).generate "mcp.toml" {
      http = {
        middlewares.mcp-auth.forwardAuth = {
          address = "http://127.0.0.1:8094";
          authRequestHeaders = [ "Authorization" "X-Forwarded-Host" ];
        };
        routers = mcpRouters;
        services = mcpServices;
      };
    };
  };

  # Agenix secret for MCP API keys (JSON format)
  age.secrets.mcp-api-keys = {
    file = ../../secrets/mcp-api-keys.age;
    mode = "400";
    owner = "mcp-auth";
    group = "mcp-auth";
  };
}
