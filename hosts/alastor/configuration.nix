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
    ../../modules/authentik
    ../../modules/img
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

  programs.zsh.enable = true;
  security.sudo.wheelNeedsPassword = false;

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
    authentik-env = {
      file = ../../secrets/authentik-env.age;
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
      SMTP_PORT = "465";
      SMTP_DOMAIN = "singlefeather.com";
      SMTP_USERNAME = "jasper.mayone@singlefeather.com";
      SMTP_AUTHENTICATION = "plain";
      SMTP_FROM = "legal@singlefeather.com";
      SMTP_ENABLE_STARTTLS = "false";
      SMTP_SSL_VERIFY = "true";
    };
    extraEnvFiles = [ config.age.secrets.docuseal-smtp.path ];
  };

  services.redis.servers.docuseal.port = lib.mkForce 6380;

  # Authentik identity provider
  atelier.services.authentik = {
    enable = true;
    hostname = "a.hogwarts.dev";
    environmentFile = config.age.secrets.authentik-env.path;
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
  # Static config: entrypoints, ACME, and file provider pointing at /etc/traefik/conf.d/
  # Dynamic config for services defined directly in this file goes in the
  # environment.etc fragment below; modules each write their own fragment.
  #
  # We use staticConfigFile instead of staticConfigOptions because the NixOS
  # traefik module unconditionally injects providers.file.filename via
  # recursiveUpdate, which conflicts with providers.file.directory (they are
  # mutually exclusive in Traefik v3). Using staticConfigFile bypasses that.
  services.traefik = {
    enable = true;
    staticConfigFile = (pkgs.formats.toml { }).generate "traefik-static.toml" {
      entryPoints = {
        web = {
          address = ":80";
          http.redirections.entryPoint = {
            to = "websecure";
            scheme = "https";
            permanent = true;
          };
        };
        websecure.address = ":443";
      };
      certificatesResolvers.cloudflare.acme = {
        email = "webmaster@hogwarts.dev";
        storage = "/var/lib/traefik/acme.json";
        dnsChallenge = {
          provider = "cloudflare";
          resolvers = [ "1.1.1.1:53" "1.0.0.1:53" ];
        };
      };
      providers.file = {
        directory = "/etc/traefik/conf.d";
        watch = true;
      };
      log.level = "INFO";
    };
  };

  # Inject Cloudflare credentials for ACME DNS challenge
  systemd.services.traefik.serviceConfig.EnvironmentFile = [
    config.age.secrets.cloudflare-credentials.path
  ];

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
          # /ext/* — ext proxy (port 9002/9003)
          crane-ext = {
            rule = "Host(`services.cranebrowser.com`) && PathPrefix(`/ext/`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "crane-ext";
            priority = 20;
          };
          # /com* — ext proxy
          crane-com = {
            rule = "Host(`services.cranebrowser.com`) && PathPrefix(`/com`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "crane-ext";
            priority = 20;
          };
          # /ubo/* — ubo proxy (port 9001)
          crane-ubo = {
            rule = "Host(`services.cranebrowser.com`) && PathPrefix(`/ubo/`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "crane-ubo";
            priority = 20;
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
        };
      };
    };
  };

  networking.firewall.allowedTCPPorts = [
    80
    443
    2222 # knot SSH
  ];

  # Automatic updates - checks daily at 4am
  system.autoUpgrade = {
    enable = true;
    flake = "github:jaspermayone/dots#alastor";
    dates = "04:00";
    allowReboot = false;
  };
}
