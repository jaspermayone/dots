# Alastor - NixOS server running frp tunnel service (named after Mad-Eye Moody)
{
  config,
  pkgs,
  lib,
  inputs,
  hostname,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/frps
    ../../modules/status
    ../../modules/knot/sync.nix
    ../../modules/bluesky-pds/default.nix
    ../../modules/atuin-server
    ../../modules/restic
    ../../modules/supergateway-proxy
    ../../modules/crane-services
    ../../modules/traefik
    ../../modules/strapi
    ../../modules/authentik
    ../../modules/img
    ../../modules/l4
    inputs.strings.nixosModules.default
    inputs.tangled.nixosModules.knot
    inputs.tangled.nixosModules.spindle
  ];

  # System version
  system.stateVersion = "24.05";

  # Prevent /boot partition from filling up
  boot.loader.grub.configurationLimit = 10;

  # Clean /tmp on boot
  boot.tmp.cleanOnBoot = true;

  # Hostname
  networking.hostName = hostname;

  # Nix settings
  nix = {
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    optimise.automatic = true;
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Timezone
  time.timeZone = "America/New_York";

  # Locale
  i18n.defaultLocale = "en_US.UTF-8";

  # Basic packages
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    curl
    jq
    tmux
    bluesky-pds
    inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
    # FundingFindr deploy toolchain
    pkgs.unstable.ruby_4_0
    pkgs.unstable.bundler
    nodejs_22
    bun
    gnumake
    gcc
    pkg-config
    libyaml
    libffi
    libpq
    zlib
    openssl
    libxml2
    libxslt
  ];

  # NH - NixOS helper
  programs.nh = {
    enable = true;
    clean.enable = true;
    clean.extraArgs = "--keep-since 4d --keep 3";
    flake = "/home/jsp/dots";
  };

  # Enable SSH
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
      KbdInteractiveAuthentication = false;
      Macs = [
        "hmac-sha2-512-etm@openssh.com"
        "hmac-sha2-256-etm@openssh.com"
        "umac-128-etm@openssh.com"
        "hmac-sha2-512"
        "hmac-sha2-256"
      ];
    };
  };

  # Fail2ban for SSH protection
  services.fail2ban = {
    enable = true;
    maxretry = 5;
  };

  # Tailscale VPN
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
  };

  # Docker
  virtualisation.docker = {
    enable = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
    daemon.settings = {
      log-driver = "json-file";
      log-opts = {
        max-size = "10m";
        max-file = "3";
      };
    };
  };

  # User account
  users.users.jsp = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHm7lo7umraewipgQu1Pifmoo/V8jYGDHjBTmt+7SOCe jsp@remus"
    ];
  };

  # FundingFindr deploy user
  users.users.fundingfindr = {
    isNormalUser = true;
    group = "users";
    shell = pkgs.bash;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILAuYbGwEnWMap90JJmUAlZv4lBme1av/rifDdRmcFku github-actions-fundingfindr"
    ];
  };

  programs.zsh.enable = true;
  security.sudo.wheelNeedsPassword = false;
  security.sudo.extraRules = [
    {
      users = [ "fundingfindr" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/systemctl restart funding_findr";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl start funding_findr";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl stop funding_findr";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl restart strapi";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  # Agenix secrets
  age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  age.secrets = {
    frps-token = {
      file = ../../secrets/frps-token.age;
      mode = "400";
    };
    cloudflare-credentials = {
      file = ../../secrets/cloudflare-credentials.age;
      mode = "400";
    };
    bore-token = {
      file = ../../secrets/bore-token.age;
      mode = "400";
      owner = "jsp";
    };
    knot-sync-github-token = {
      file = ../../secrets/knot-sync-github-token.age;
      mode = "400";
      owner = "git";
    };
    pds = {
      file = ../../secrets/pds.age;
      mode = "600";
      owner = "pds";
      group = "pds";
    };
    pds-mailer = {
      file = ../../secrets/pds-mailer.age;
      mode = "600";
      owner = "pds";
      group = "pds";
    };
    atuin-key = {
      file = ../../secrets/atuin-key.age;
      path = "/home/jsp/.local/share/atuin/key";
      owner = "jsp";
      mode = "400";
    };
    strings-hogwarts = {
      file = ../../secrets/strings-hogwarts.age;
      mode = "400";
    };
    strings-witcc = {
      file = ../../secrets/strings-witcc.age;
      mode = "400";
    };
    docuseal-smtp = {
      file = ../../secrets/docuseal-smtp.age;
      mode = "400";
      owner = "nobody";
    };
    crane-services-token = {
      file = ../../secrets/crane-services-token.age;
      mode = "400";
    };
    crane-services-hmac = {
      file = ../../secrets/crane-services-hmac.age;
      mode = "400";
    };
    strapi-env = {
      file = ../../secrets/strapi-env.age;
      mode = "400";
      owner = "jsp";
    };
    authentik-env = {
      file = ../../secrets/authentik-env.age;
      mode = "400";
    };
    l4-env = {
      file = ../../secrets/l4-env.age;
      mode = "400";
    };
  };

  # ── Services ────────────────────────────────────────────────────────────────

  # FRP tunnel server
  atelier.services.frps = {
    enable = true;
    domain = "tun.hogwarts.channel";
    bindPort = 7000;
    vhostHTTPPort = 7080;
    authTokenFile = config.age.secrets.frps-token.path;
    enableTraefik = true;
  };

  # Status monitoring (served on alastor.hogwarts.channel)
  atelier.services.status = {
    enable = true;
    hostname = "alastor";
    domain = "alastor.hogwarts.channel";
    services = [
      "frps"
      "traefik"
      "tailscaled"
      "tangled-knot"
      "tangled-spindle"
      "atuin-server"
      "strings-hogwarts"
      "strings-witcc"
      "docuseal"
      "redis-docuseal"
      "docker"
    ];
    remoteHosts = [
      "remus"
      "dippet"
    ];
  };

  # Tangled Knot server
  services.tangled.knot = {
    enable = true;
    package = inputs.tangled.packages.${pkgs.stdenv.hostPlatform.system}.knot;
    server = {
      owner = "did:plc:abgthiqrd7tczkafjm4ennbo";
      hostname = "knot.jaspermayone.com";
      listenAddr = "127.0.0.1:5555";
    };
  };

  # Tangled Spindle CI/CD runner
  services.tangled.spindle = {
    enable = true;
    package = inputs.tangled.packages.${pkgs.stdenv.hostPlatform.system}.spindle;
    server = {
      owner = "did:plc:abgthiqrd7tczkafjm4ennbo";
      hostname = "1.alastor.spindle.hogwarts.dev";
      listenAddr = "127.0.0.1:6555";
    };
  };

  services.bluesky-pds-hosting = {
    enable = true;
    hostname = "pds.hogwarts.dev";
    port = 3000;
    adminEmail = "pds-admin@hogwarts.dev";
    environmentFile = config.age.secrets.pds.path;
    mailerEnvironmentFile = config.age.secrets.pds-mailer.path;
    enableGatekeeper = false;
    enableAgeAssurance = true;
  };

  atelier.services.atuin-server = {
    enable = true;
    hostname = "atuin.hogwarts.dev";
  };

  jsp.services.knot-sync = {
    enable = true;
    repoDir = "/var/lib/knot/repos/did:plc:abgthiqrd7tczkafjm4ennbo";
    secretsFile = config.age.secrets.knot-sync-github-token.path;
  };

  services.strings.instances = {
    hogwarts = {
      enable = true;
      baseUrl = "https://str.hogwarts.dev";
      port = 3100;
      username = "jsp";
      passwordFile = config.age.secrets.strings-hogwarts.path;
    };
    witcc = {
      enable = true;
      baseUrl = "https://str.witcc.dev";
      port = 3101;
      username = "witcc";
      passwordFile = config.age.secrets.strings-witcc.path;
    };
  };

  services.docuseal = {
    enable = true;
    port = 3200;
    host = "127.0.0.1";
    redis.createLocally = true;
    extraConfig = {
      REDIS_URL = "redis://localhost:6380";
      SMTP_ADDRESS = "smtp.gmail.com";
      SMTP_PORT = "587";
      SMTP_DOMAIN = "singlefeather.com";
      SMTP_USERNAME = "jasper.mayone@singlefeather.com";
      SMTP_AUTHENTICATION = "plain";
      SMTP_FROM = "legal@singlefeather.com";
      SMTP_ENABLE_STARTTLS = "true";
      SMTP_SSL_VERIFY = "true";
    };
    extraEnvFiles = [ config.age.secrets.docuseal-smtp.path ];
  };

  services.redis.servers.docuseal.port = lib.mkForce 6380;
  services.redis.servers.fundingfindr = {
    enable = true;
    port = 6382;
    bind = "127.0.0.1";
  };

  # Authentik identity provider
  atelier.services.authentik = {
    enable = true;
    hostname = "a.hogwarts.dev";
    environmentFile = config.age.secrets.authentik-env.path;
  };

  # PostgreSQL for FundingFindr
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
    ensureUsers = [
      {
        name = "fundingfindr";
      }
    ];
    ensureDatabases = [
      "funding_findr_production"
      "funding_findr_queue_production"
      "funding_findr_cache_production"
      "funding_findr_cable_production"
    ];
    initialScript = pkgs.writeText "postgres-init.sql" ''
      GRANT ALL PRIVILEGES ON DATABASE funding_findr_production TO fundingfindr;
      GRANT ALL PRIVILEGES ON DATABASE funding_findr_queue_production TO fundingfindr;
      GRANT ALL PRIVILEGES ON DATABASE funding_findr_cache_production TO fundingfindr;
      GRANT ALL PRIVILEGES ON DATABASE funding_findr_cable_production TO fundingfindr;
      ALTER DATABASE funding_findr_production OWNER TO fundingfindr;
      ALTER DATABASE funding_findr_queue_production OWNER TO fundingfindr;
      ALTER DATABASE funding_findr_cache_production OWNER TO fundingfindr;
      ALTER DATABASE funding_findr_cable_production OWNER TO fundingfindr;
    '';
    authentication = pkgs.lib.mkOverride 10 ''
      local all all trust
      host all all 127.0.0.1/32 scram-sha-256
      host all all ::1/128 scram-sha-256
    '';
  };

  # FundingFindr CMS (Strapi on port 1337)
  atelier.services.strapi = {
    enable = true;
    hostname = "cms.fundingfindr.co";
    port = 1337;
    projectDir = "/home/fundingfindr/funding_findr/cms";
    user = "fundingfindr";
    group = "users";
    environmentFile = config.age.secrets.strapi-env.path;
  };

  # FundingFindr Rails app (Puma on port 3300)
  systemd.services.funding_findr = {
    description = "FundingFindr Puma HTTP Server";
    after = [ "network.target" "postgresql.service" "redis-fundingfindr.service" ];
    requires = [ "postgresql.service" "redis-fundingfindr.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = "fundingfindr";
      Group = "users";
      WorkingDirectory = "/home/fundingfindr/funding_findr";
      EnvironmentFile = "/etc/funding_findr/env";
      Environment = [
        "RAILS_ENV=production"
        "PORT=3300"
        "PUMA_PID=/home/fundingfindr/funding_findr/tmp/pids/puma.pid"
        "PUMA_STATE=/home/fundingfindr/funding_findr/tmp/pids/puma.state"
        "RUBY_YJIT_ENABLE=1"
        "BUNDLE_PATH=vendor/bundle"
        "BUNDLE_WITHOUT=development:test"
      ];
      ExecStart = "/run/current-system/sw/bin/bash -lc 'bundle exec puma -C config/puma.rb'";
      ExecReload = "/run/current-system/sw/bin/bash -lc 'bundle exec pumactl -S /home/fundingfindr/funding_findr/tmp/pids/puma.state phased-restart'";
      ExecStop = "/run/current-system/sw/bin/bash -lc 'bundle exec pumactl -S /home/fundingfindr/funding_findr/tmp/pids/puma.state stop'";
      KillMode = "process";
      Restart = "on-failure";
      RestartSec = "5s";
      StandardOutput = "journal";
      StandardError = "journal";
      SyslogIdentifier = "funding_findr";
    };
  };

  # l4 image CDN
  atelier.services.l4 = {
    enable = true;
    hostname = "l4.jaspermayone.com";
    environmentFile = config.age.secrets.l4-env.path;
  };

  # img static site (Authentik-protected)
  atelier.services.img = {
    enable = true;
    hostname = "img.hogwarts.dev";
    authentikHostname = "a.hogwarts.dev";
  };

  # Crane browser services
  crane.services = {
    enable = true;
    hostname = "services.cranebrowser.com";
    proxyBaseUrl = "https://services.cranebrowser.com/ext";
    uboProxyBaseUrl = "https://services.cranebrowser.com/ubo/";
    repoTokenFile = config.age.secrets.crane-services-token.path;
    hmacSecretFile = config.age.secrets.crane-services-hmac.path;
    behindProxy = true;
    openFirewall = false;
  };

  # ── nginx ────────────────────────────────────────────────────────────────────
  # Port 8091: crane-services static files (bangs.json, filters/, robots.txt)
  # Ports 8092, 8095 are handled by bluesky-pds and img modules respectively.
  services.nginx = {
    enable = true;
    virtualHosts."crane-static" = {
      listen = [ { addr = "127.0.0.1"; port = 8091; } ];
      locations."/robots.txt" = {
        extraConfig = ''
          add_header Content-Type text/plain;
          return 200 "User-agent: *\nDisallow: /\n";
        '';
      };
      locations."/bangs.json" = {
        root = "/opt/crane-services/svc/bangs";
        extraConfig = ''
          add_header Cache-Control "public, max-age=86400, stale-if-error=604800";
          add_header Access-Control-Allow-Origin *;
        '';
      };
      locations."/filters/" = {
        alias = "/opt/crane-services/filters/";
        extraConfig = ''
          add_header Cache-Control "public, max-age=3600, stale-if-error=86400";
          add_header Access-Control-Allow-Origin *;
        '';
      };
    };
  };

  # ── Traefik ──────────────────────────────────────────────────────────────────
  # Runs as its own Docker Compose stack (modules/traefik) so it is fully
  # decoupled from the NixOS rebuild cycle. Dynamic config fragments in
  # /etc/traefik/conf.d/ are still written by NixOS modules below and
  # hot-reloaded by Traefik without a container restart.
  services.traefik-compose = {
    enable = true;
    acmeEmail = "webmaster@hogwarts.dev";
    cloudflareCredentialsFile = config.age.secrets.cloudflare-credentials.path;
    openFirewall = false; # ports opened explicitly in networking.firewall below
  };

  # Dynamic config fragment for services hosted directly in this file
  # (knot, strings, docuseal, idp, plex, crane, spindle)
  environment.etc."traefik/conf.d/alastor.toml" = {
    source = (pkgs.formats.toml { }).generate "alastor.toml" {
      http = {
        routers = {
          knot = {
            rule = "Host(`knot.jaspermayone.com`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "knot";
          };
          str-hogwarts = {
            rule = "Host(`str.hogwarts.dev`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "str-hogwarts";
          };
          str-witcc = {
            rule = "Host(`str.witcc.dev`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "str-witcc";
          };
          server-calendar = {
            rule = "Host(`server-calendar.witcc.dev`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "server-calendar";
          };
          spindle = {
            rule = "Host(`1.alastor.spindle.hogwarts.dev`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "spindle";
          };
          docuseal = {
            rule = "Host(`sign.singlefeather.com`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "docuseal";
          };
          idp = {
            rule = "Host(`idp.patchworklabs.org`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "idp";
          };
          plex = {
            rule = "Host(`plex.hogwarts.dev`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            service = "plex";
          };
          # services.cranebrowser.com — root: redirect to main site
          crane-root = {
            rule = "Host(`services.cranebrowser.com`) && Path(`/`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" "crane-root-redirect" ];
            service = "crane-noop";
            priority = 30;
          };
          # /robots.txt
          crane-robots = {
            rule = "Host(`services.cranebrowser.com`) && Path(`/robots.txt`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "crane-static";
            priority = 25;
          };
          # /bangs.json
          crane-bangs = {
            rule = "Host(`services.cranebrowser.com`) && Path(`/bangs.json`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "crane-static";
            priority = 25;
          };
          # /filters/*
          crane-filters = {
            rule = "Host(`services.cranebrowser.com`) && PathPrefix(`/filters/`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "crane-static";
            priority = 25;
          };
          # /updates/mac* — proxy upstream
          crane-updates = {
            rule = "Host(`services.cranebrowser.com`) && PathPrefix(`/updates/mac`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "crane-updates";
            priority = 25;
          };
          # /ext/* — ext proxy (port 9002/9003); strip /ext prefix so proxy sees /proxy, /cws_snippet, etc.
          crane-ext = {
            rule = "Host(`services.cranebrowser.com`) && PathPrefix(`/ext/`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" "crane-strip-ext" ];
            service = "crane-ext";
            priority = 20;
          };
          # /com* — ext proxy (no prefix stripping; proxy handles /com directly)
          crane-com = {
            rule = "Host(`services.cranebrowser.com`) && PathPrefix(`/com`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "crane-ext";
            priority = 20;
          };
          # /ubo/* — ubo proxy (port 9001); strip /ubo prefix so proxy sees /assets.json, etc.
          crane-ubo = {
            rule = "Host(`services.cranebrowser.com`) && PathPrefix(`/ubo/`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" "crane-strip-ubo" ];
            service = "crane-ubo";
            priority = 20;
          };
          # FundingFindr Rails app (Puma on port 3300)
          funding-findr = {
            rule = "Host(`fundingfindr.co`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "funding-findr";
          };
        };
        middlewares = {
          # Global HSTS middleware — referenced as "hsts" by all file-provider routers
          hsts.headers = {
            stsSeconds = 31536000;
            stsIncludeSubdomains = true;
            stsPreload = true;
          };
          crane-root-redirect.redirectRegex = {
            regex = ".*";
            replacement = "https://cranebrowser.com";
            permanent = false;
          };
          crane-strip-ext.stripPrefix.prefixes = [ "/ext" ];
          crane-strip-ubo.stripPrefix.prefixes = [ "/ubo" ];
        };
        services = {
          knot.loadBalancer.servers = [ { url = "http://127.0.0.1:5555"; } ];
          str-hogwarts.loadBalancer.servers = [ { url = "http://127.0.0.1:3100"; } ];
          str-witcc.loadBalancer.servers = [ { url = "http://127.0.0.1:3101"; } ];
          server-calendar.loadBalancer.servers = [ { url = "http://127.0.0.1:3002"; } ];
          spindle.loadBalancer.servers = [ { url = "http://127.0.0.1:6555"; } ];
          docuseal.loadBalancer.servers = [ { url = "http://127.0.0.1:3200"; } ];
          idp.loadBalancer.servers = [ { url = "http://127.0.0.1:3003"; } ];
          plex.loadBalancer.servers = [ { url = "http://pensieve.wildebeest-stargazer.ts.net:32400"; } ];
          crane-static.loadBalancer.servers = [ { url = "http://127.0.0.1:8091"; } ];
          crane-ext.loadBalancer.servers = [
            { url = "http://127.0.0.1:9002"; }
            { url = "http://127.0.0.1:9003"; }
          ];
          crane-ubo.loadBalancer.servers = [ { url = "http://127.0.0.1:9001"; } ];
          crane-updates.loadBalancer.servers = [ { url = "https://updates.cranebrowser.com"; } ];
          # Dummy backend for the redirect router (never actually contacted)
          crane-noop.loadBalancer.servers = [ { url = "http://127.0.0.1:1"; } ];
          funding-findr.loadBalancer.servers = [ { url = "http://127.0.0.1:3300"; } ];
        };
      };
    };
  };

  networking.firewall.allowedTCPPorts = [
    80
    443
    2222 # knot SSH
  ];
  networking.firewall.allowedUDPPorts = [ 443 ]; # HTTP/3 (QUIC)

  # Automatic updates - checks daily at 4am
  system.autoUpgrade = {
    enable = true;
    flake = "github:jaspermayone/dots#alastor";
    dates = "04:00";
    allowReboot = false;
  };
}
