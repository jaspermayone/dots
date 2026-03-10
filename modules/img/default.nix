# modules/img/default.nix
# Hosts a static copy of dunkirk.sh/img, protected by Authentik forward_auth.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.atelier.services.img;
  staticPort = 8095;
in
{
  options.atelier.services.img = {
    enable = lib.mkEnableOption "img lightweight image tools (dunkirk.sh/img)";

    hostname = lib.mkOption {
      type = lib.types.str;
      default = "img.hogwarts.dev";
      description = "Hostname to serve img on.";
    };

    repoUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://tangled.org/dunkirk.sh/img.git";
      description = "Git clone URL for the img repo.";
    };

    authentikHostname = lib.mkOption {
      type = lib.types.str;
      default = "a.hogwarts.dev";
      description = "Hostname of the Authentik instance (used in redirect URIs).";
    };

    authentikPort = lib.mkOption {
      type = lib.types.int;
      default = 9000;
      description = "Internal port of the Authentik instance for forward_auth.";
    };
  };

  config = lib.mkIf cfg.enable {
    # System user to own the cloned repo
    users.users.img = {
      isSystemUser = true;
      group = "img";
    };
    users.groups.img = { };

    # Clone / update the repo on boot (and daily via timer)
    systemd.services.img-sync = {
      description = "Clone or update dunkirk.sh/img repository";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "img";
        Group = "img";
        StateDirectory = "img";
        StateDirectoryMode = "0750";
        ExecStart = pkgs.writeShellScript "img-sync" ''
          set -euo pipefail
          REPO=/var/lib/img/repo
          if [ -d "$REPO/.git" ]; then
            ${pkgs.git}/bin/git -C "$REPO" fetch --quiet origin
            ${pkgs.git}/bin/git -C "$REPO" reset --hard origin/HEAD
          else
            ${pkgs.git}/bin/git clone --depth 1 "${cfg.repoUrl}" "$REPO"
          fi
        '';
      };
    };

    systemd.timers.img-sync = {
      description = "Daily sync of dunkirk.sh/img repo";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };

    # nginx on port 8095 serves static files from /var/lib/img/repo/public
    services.nginx = {
      enable = true;
      virtualHosts."img-static" = {
        listen = [ { addr = "127.0.0.1"; port = staticPort; } ];
        root = "/var/lib/img/repo/public";
        locations."/" = {
          tryFiles = "$uri $uri/ =404";
        };
      };
    };

    # Allow nginx to read files owned by the img user
    users.users.nginx.extraGroups = [ "img" ];

    # Traefik dynamic config fragment (file provider)
    environment.etc."traefik/conf.d/img.toml" = {
      source = (pkgs.formats.toml { }).generate "img.toml" {
        http = {
          middlewares.img-auth.forwardAuth = {
            address = "http://127.0.0.1:${toString cfg.authentikPort}/outpost.goauthentik.io/auth/traefik";
            authResponseHeaders = [
              "X-authentik-username"
              "X-authentik-groups"
              "X-authentik-email"
              "X-authentik-name"
              "X-authentik-uid"
              "X-authentik-jwt"
              "X-authentik-meta-jwks"
              "X-authentik-meta-outpost"
              "X-authentik-meta-provider"
              "X-authentik-meta-app"
              "X-authentik-meta-version"
            ];
            trustForwardHeader = true;
          };
          routers = {
            # Authentik outpost paths pass straight through
            img-outpost = {
              rule = "Host(`${cfg.hostname}`) && PathPrefix(`/outpost.goauthentik.io`)";
              entryPoints = [ "websecure" ];
              tls.certResolver = "cloudflare";
              middlewares = [ "hsts" ];
              service = "img-authentik-outpost";
              priority = 20;
            };
            # Everything else: forward_auth check then static files
            img = {
              rule = "Host(`${cfg.hostname}`)";
              entryPoints = [ "websecure" ];
              tls.certResolver = "cloudflare";
              middlewares = [ "hsts" "img-auth" ];
              service = "img-static";
              priority = 10;
            };
          };
          services = {
            img-static.loadBalancer.servers = [
              { url = "http://127.0.0.1:${toString staticPort}"; }
            ];
            img-authentik-outpost.loadBalancer.servers = [
              { url = "http://127.0.0.1:${toString cfg.authentikPort}"; }
            ];
          };
        };
      };
    };
  };
}
