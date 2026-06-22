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
    ../../modules/till-server
    ../../modules/basecamp-apps
    ../../modules/wit-calendar
    inputs.strings.nixosModules.default
    inputs.tangled.nixosModules.knot
    inputs.tangled.nixosModules.spindle
  ];

  # System version
  system.stateVersion = "24.05";

  # Prevent /boot partition from filling up. /boot is only 98M and one
  # aarch64 kernel Image (~60M) + initrd (~11M) is ~71M, so it realistically
  # holds 2 same-kernel generations. A kernel-version bump needs a manual
  # /boot free + direct switch-to-configuration (both kernels can't coexist).
  boot.loader.grub.configurationLimit = 2;

  # Clean /tmp on boot
  boot.tmp.cleanOnBoot = true;

  # Hostname
  networking.hostName = hostname;

  # Nix settings
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [
        "root"
        "jsp"
      ];
    };
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

  # Basecamp ONCE-style apps, run directly as Docker services behind Traefik
  # (see modules/basecamp-apps). Bound to loopback; Traefik terminates TLS via
  # the cloudflare resolver. DNS: point each hostname at alastor.
  services.basecampApps.apps = {
    writebook = {
      image = "ghcr.io/basecamp/writebook";
      hostname = "writebook.hogwarts.dev";
      port = 8081;
    };
    campfire = {
      image = "ghcr.io/basecamp/once-campfire";
      hostname = "campfire.hogwarts.dev";
      port = 8082;
    };
    fizzy = {
      image = "ghcr.io/basecamp/fizzy";
      hostname = "fizzy.hogwarts.dev";
      port = 8083;
    };
  };

  # SMTP for the basecamp apps (email-based sign-in links won't deliver without
  # it). Reuses the DocuSeal Google Workspace app password (docuseal-smtp.age,
  # which holds just SMTP_PASSWORD=...); auth is the singlefeather.com account.
  # Sends as the fizzy@hogwarts.dev "send mail as" alias — deliverable under
  # hogwarts.dev's strict DMARC (p=reject) only once Google DKIM is enabled for
  # hogwarts.dev (Admin → Authenticate email → hogwarts.dev).
  services.basecampApps.smtpEnvironmentFile = config.age.secrets.docuseal-smtp.path;
  services.basecampApps.smtpSettings = {
    SMTP_ADDRESS = "smtp.gmail.com";
    SMTP_PORT = "587";
    SMTP_USERNAME = "jasper.mayone@singlefeather.com";
    MAILER_FROM_ADDRESS = "fizzy@hogwarts.dev";
  };

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
    extraGroups = [
      "wheel"
      "docker"
    ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHm7lo7umraewipgQu1Pifmoo/V8jYGDHjBTmt+7SOCe me@jaspermayone.com"
    ];
  };

  users.users.fundingfindr = {
    isNormalUser = true;
    group = "users";
    shell = pkgs.bash;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILAuYbGwEnWMap90JJmUAlZv4lBme1av/rifDdRmcFku github-actions-fundingfindr"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHm7lo7umraewipgQu1Pifmoo/V8jYGDHjBTmt+7SOCe me@jaspermayone.com"
    ];
  };

  programs.nix-ld.enable = true;
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
    wit-calendar-env = {
      file = ../../secrets/wit-calendar-env.age;
      mode = "400";
    };
    crane-services-token = {
      file = ../../secrets/crane-services-token.age;
      mode = "400";
    };
    crane-services-hmac = {
      file = ../../secrets/crane-services-hmac.age;
      mode = "400";
    };
    crane-services-jwt = {
      file = ../../secrets/crane-services-jwt.age;
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
    till-github-token = {
      file = ../../secrets/till-github-token.age;
      mode = "400";
      # owner "till" is gone while till-server is disabled; default to root so
      # agenix can chown. Restore `owner = "till";` when re-enabling till-server.
    };
    till-server-env = {
      file = ../../secrets/till-server-env.age;
      mode = "400";
      # owner "till" is gone while till-server is disabled; default to root.
      # Restore `owner = "till";` when re-enabling till-server.
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
    };
    # SMTP is configured via the DocuSeal UI (Settings → Email) with Noverify.
    # Do NOT set SMTP_ADDRESS or other SMTP_* env vars here — when SMTP_ADDRESS
    # is present in the env the ActionMailerConfigsInterceptor short-circuits and
    # uses the env-var path, which has no openssl_verify_mode support in 2.2.0,
    # causing CRL certificate errors. The DB/UI path correctly applies VERIFY_NONE.
  };

  services.redis.servers.docuseal.port = lib.mkForce 6380;

  # Authentik identity provider
  atelier.services.authentik = {
    enable = true;
    hostname = "a.hogwarts.dev";
    environmentFile = config.age.secrets.authentik-env.path;
  };

  # PostgreSQL for till
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
    ensureUsers = [
      {
        name = "till";
        ensureDBOwnership = true;
      }
    ];
    ensureDatabases = [ "till" ];
    authentication = pkgs.lib.mkOverride 10 ''
      local all all trust
      host all all 127.0.0.1/32 scram-sha-256
      host all all ::1/128 scram-sha-256
    '';
  };

  # WIT Coding Club calendar backend
  atelier.services.wit-calendar = {
    enable = true;
    hostname = "calendar.witcc.dev";
    image = "ghcr.io/witcodingclub/calendar-backend:main";
    environmentFile = config.age.secrets.wit-calendar-env.path;
    deployAuthorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFPR0KgNpNxd34CwP1X9B4tKoQdAwa42WvJZdP1p2RTl github-actions-wit-calendar-deploy"
    ];
  };

  # FundingFindr CMS (Strapi on port 1337) — staying here until Railway migration
  atelier.services.strapi = {
    enable = true;
    hostname = "cms.fundingfindr.co";
    port = 1337;
    projectDir = "/home/fundingfindr/funding_findr/cms";
    user = "fundingfindr";
    group = "users";
    environmentFile = config.age.secrets.strapi-env.path;
  };

  # l4 image CDN
  atelier.services.l4 = {
    enable = true;
    hostname = "l4.jaspermayone.com";
    environmentFile = config.age.secrets.l4-env.path;
  };

  # till API server
  atelier.services.till-server = {
    # Temporarily disabled: till-server-sync fails on an expired/revoked GitHub
    # token (403 on git pull). Re-enable once the token is refreshed.
    enable = false;
    hostname = "api.usetill.dev";
    repoTokenFile = config.age.secrets.till-github-token.path;
    environmentFile = config.age.secrets.till-server-env.path;
    deployAuthorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBUyblP9vb4cO17t8rlWCTn7HkzrBKIy/ndd5yJloqll github-actions-till-deploy"
    ];
  };

  # img static site (Authentik-protected)
  atelier.services.img = {
    enable = true;
    hostname = "img.hogwarts.dev";
    authentikHostname = "a.hogwarts.dev";
  };

  # Crane browser services
  crane.services = {
    # Temporarily disabled: crane-services-sync fails on an expired/invalid
    # GitHub token (password auth no longer supported). Re-enable once the
    # token is refreshed.
    enable = false;
    hostname = "services.cranebrowser.com";
    proxyBaseUrl = "https://services.cranebrowser.com/ext";
    uboProxyBaseUrl = "https://services.cranebrowser.com/ubo/";
    repoTokenFile = config.age.secrets.crane-services-token.path;
    hmacSecretFile = config.age.secrets.crane-services-hmac.path;
    jwtSecretFile = config.age.secrets.crane-services-jwt.path;
    behindProxy = true;
    openFirewall = false;
  };

  # ── nginx ────────────────────────────────────────────────────────────────────
  # Port 8091: crane-services static files (bangs.json, filters/, robots.txt)
  # Ports 8092, 8095 are handled by bluesky-pds and img modules respectively.
  services.nginx = {
    enable = true;
    virtualHosts."crane-static" = {
      listen = [
        {
          addr = "127.0.0.1";
          port = 8091;
        }
      ];
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

  # ── soju IRC bouncer ─────────────────────────────────────────────────────────
  services.soju = {
    enable = true;
    hostName = "irc.hogwarts.dev";
    listen = [ ":6697" ];
    tlsCertificate = "/var/lib/acme/irc.hogwarts.dev/fullchain.pem";
    tlsCertificateKey = "/var/lib/acme/irc.hogwarts.dev/key.pem";
    enableMessageLogging = true;
    acceptProxyIP = [ ];
  };

  # Let soju read ACME certs (DynamicUser needs the group explicitly)
  systemd.services.soju.serviceConfig.SupplementaryGroups = [ "acme" ];

  # TLS cert for soju via Let's Encrypt (Cloudflare DNS-01 challenge)
  security.acme = {
    acceptTerms = true;
    defaults.email = "webmaster@hogwarts.dev";
    certs."irc.hogwarts.dev" = {
      dnsProvider = "cloudflare";
      reloadServices = [ "soju" ];
      environmentFile = config.age.secrets.cloudflare-credentials.path;
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
          # server-calendar routing moved to modules/wit-calendar (wit-calendar.toml)
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
            middlewares = [
              "hsts"
              "crane-root-redirect"
            ];
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
            middlewares = [
              "hsts"
              "crane-strip-ext"
            ];
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
            middlewares = [
              "hsts"
              "crane-strip-ubo"
            ];
            service = "crane-ubo";
            priority = 20;
          };
          # /accounts/* — accounts service (port 9004)
          crane-accounts = {
            rule = "Host(`services.cranebrowser.com`) && PathPrefix(`/accounts/`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "crane-accounts";
            priority = 20;
          };
          # /memory/* — memory service (port 9005)
          crane-memory = {
            rule = "Host(`services.cranebrowser.com`) && PathPrefix(`/memory/`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "crane-memory";
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
          crane-strip-ext.stripPrefix.prefixes = [ "/ext" ];
          crane-strip-ubo.stripPrefix.prefixes = [ "/ubo" ];
        };
        services = {
          knot.loadBalancer.servers = [ { url = "http://127.0.0.1:5555"; } ];
          str-hogwarts.loadBalancer.servers = [ { url = "http://127.0.0.1:3100"; } ];
          str-witcc.loadBalancer.servers = [ { url = "http://127.0.0.1:3101"; } ];
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
          crane-accounts.loadBalancer.servers = [ { url = "http://127.0.0.1:9004"; } ];
          crane-memory.loadBalancer.servers = [ { url = "http://127.0.0.1:9005"; } ];
          # Dummy backend for the redirect router (never actually contacted)
          crane-noop.loadBalancer.servers = [ { url = "http://127.0.0.1:1"; } ];
        };
      };
    };
  };

  # Gringotts password manager (Vaultwarden) — proxied via Tailscale MagicDNS
  environment.etc."traefik/conf.d/pass.toml" = {
    source = (pkgs.formats.toml { }).generate "pass.toml" {
      http = {
        routers.pass = {
          rule = "Host(`pass.hogwarts.dev`)";
          entryPoints = [ "websecure" ];
          tls.certResolver = "cloudflare";
          middlewares = [
            "hsts"
            "pass-no-cache"
            "pass-compress"
          ];
          service = "pass";
        };
        middlewares = {
          pass-no-cache.headers.customResponseHeaders = {
            Cache-Control = "no-store";
            Pragma = "no-cache";
          };
          pass-compress.compress = { };
        };
        services.pass.loadBalancer.servers = [
          { url = "http://gringotts.wildebeest-stargazer.ts.net:80"; }
        ];
      };
    };
  };

  # Pince (LinkAce bookmarks) — proxied via Tailscale MagicDNS
  environment.etc."traefik/conf.d/linkace.toml" = {
    source = (pkgs.formats.toml { }).generate "linkace.toml" {
      http = {
        routers.linkace = {
          rule = "Host(`linkace.hogwarts.dev`)";
          entryPoints = [ "websecure" ];
          tls.certResolver = "cloudflare";
          middlewares = [ "hsts" "linkace-https" ];
          service = "linkace";
        };
        middlewares.linkace-https.headers.customRequestHeaders = {
          "X-Forwarded-Proto" = "https";
          "X-Forwarded-Port" = "";
        };
        services.linkace.loadBalancer.servers = [
          { url = "http://flourish.wildebeest-stargazer.ts.net:80"; }
        ];
      };
    };
  };

  # Nymphadora telemetry (Grafana) — proxied via Tailscale MagicDNS
  environment.etc."traefik/conf.d/nymphadora.toml" = {
    source = (pkgs.formats.toml { }).generate "nymphadora.toml" {
      http = {
        routers.grafana-telemetry = {
          rule = "Host(`telemetry.hogwarts.dev`)";
          entryPoints = [ "websecure" ];
          tls.certResolver = "cloudflare";
          middlewares = [ "hsts" ];
          service = "grafana-telemetry";
        };
        services.grafana-telemetry.loadBalancer.servers = [
          { url = "http://nymphadora.wildebeest-stargazer.ts.net:3000"; }
        ];
      };
    };
  };

  # Proxmox VE — proxied via Tailscale MagicDNS, protected by Authentik
  # Backend is HTTPS with a self-signed cert; insecureSkipVerify bypasses that.
  environment.etc."traefik/conf.d/pve.toml" = {
    source = (pkgs.formats.toml { }).generate "pve.toml" {
      http = {
        middlewares.pve-auth.forwardAuth = {
          address = "http://127.0.0.1:9000/outpost.goauthentik.io/auth/traefik";
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
          pve-outpost = {
            rule = "Host(`pve.hogwarts.dev`) && PathPrefix(`/outpost.goauthentik.io`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "pve-authentik-outpost";
            priority = 30;
          };
          pve-ws = {
            rule = "Host(`pve.hogwarts.dev`) && PathRegexp(`/api2/json/nodes/.+/(vncwebsocket|termproxy|spiceproxy)`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "pve";
            priority = 20;
          };
          pve = {
            rule = "Host(`pve.hogwarts.dev`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" "pve-auth" ];
            service = "pve";
            priority = 10;
          };
        };
        services = {
          pve = {
            loadBalancer = {
              serversTransport = "pve-transport";
              servers = [ { url = "https://pve.wildebeest-stargazer.ts.net:8006"; } ];
            };
          };
          pve-authentik-outpost.loadBalancer.servers = [
            { url = "http://127.0.0.1:9000"; }
          ];
        };
        serversTransports.pve-transport.insecureSkipVerify = true;
      };
    };
  };

  # Skeeter Umami (analytics) — proxied via Tailscale MagicDNS, dashboard behind Authentik
  # /api/send is excluded so tracking scripts can POST without auth.
  environment.etc."traefik/conf.d/umami.toml" = {
    source = (pkgs.formats.toml { }).generate "umami.toml" {
      http = {
        middlewares.umami-auth.forwardAuth = {
          address = "http://127.0.0.1:9000/outpost.goauthentik.io/auth/traefik";
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
          umami-outpost = {
            rule = "Host(`umami.hogwarts.dev`) && PathPrefix(`/outpost.goauthentik.io`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "umami-authentik-outpost";
            priority = 30;
          };
          umami-tracking = {
            rule = "Host(`umami.hogwarts.dev`) && PathPrefix(`/api/send`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "umami";
            priority = 20;
          };
          umami = {
            rule = "Host(`umami.hogwarts.dev`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" "umami-auth" ];
            service = "umami";
            priority = 10;
          };
        };
        services = {
          umami.loadBalancer.servers = [
            { url = "http://skeeter.wildebeest-stargazer.ts.net:3000"; }
          ];
          umami-authentik-outpost.loadBalancer.servers = [
            { url = "http://127.0.0.1:9000"; }
          ];
        };
      };
    };
  };

  # Floo n8n (workflow automation) — proxied via Tailscale MagicDNS, protected by Authentik
  environment.etc."traefik/conf.d/n8n.toml" = {
    source = (pkgs.formats.toml { }).generate "n8n.toml" {
      http = {
        middlewares.n8n-auth.forwardAuth = {
          address = "http://127.0.0.1:9000/outpost.goauthentik.io/auth/traefik";
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
          n8n-outpost = {
            rule = "Host(`n8n.hogwarts.dev`) && PathPrefix(`/outpost.goauthentik.io`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "n8n-authentik-outpost";
            priority = 20;
          };
          n8n = {
            rule = "Host(`n8n.hogwarts.dev`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" "n8n-auth" ];
            service = "n8n";
            priority = 10;
          };
        };
        services = {
          n8n.loadBalancer.servers = [
            { url = "http://floo.wildebeest-stargazer.ts.net:5678"; }
          ];
          n8n-authentik-outpost.loadBalancer.servers = [
            { url = "http://127.0.0.1:9000"; }
          ];
        };
      };
    };
  };

  # Honeydukes Mealie (meal planner) — proxied via Tailscale MagicDNS
  environment.etc."traefik/conf.d/mealie.toml" = {
    source = (pkgs.formats.toml { }).generate "mealie.toml" {
      http = {
        routers.mealie = {
          rule = "Host(`mealie.hogwarts.dev`)";
          entryPoints = [ "websecure" ];
          tls.certResolver = "cloudflare";
          middlewares = [ "hsts" ];
          service = "mealie";
        };
        services.mealie.loadBalancer.servers = [
          { url = "http://honeydukes.wildebeest-stargazer.ts.net:9925"; }
        ];
      };
    };
  };

  # PostHog analytics — proxied to homelab VMs via Tailscale MagicDNS
  environment.etc."traefik/conf.d/posthog.toml" = {
    source = (pkgs.formats.toml { }).generate "posthog.toml" {
      http = {
        routers.posthog-singlefeather = {
          rule = "Host(`ph.singlefeather.com`)";
          entryPoints = [ "websecure" ];
          tls.certResolver = "cloudflare";
          middlewares = [ "hsts" ];
          service = "posthog-singlefeather";
        };
        services.posthog-singlefeather.loadBalancer.servers = [
          { url = "http://dobby.wildebeest-stargazer.ts.net:80"; }
        ];
      };
    };
  };

  # Mad River Mentoring — proxied to dedicated Proxmox VMs via Tailscale MagicDNS
  environment.etc."traefik/conf.d/madrivermentoring.toml" = {
    source = (pkgs.formats.toml { }).generate "madrivermentoring.toml" {
      http = {
        routers = {
          mrm-staging = {
            rule = "Host(`staging.madrivermentoring.com`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "mrm-staging";
          };
          mrm-prod = {
            rule = "Host(`p.madrivermentoring.com`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "mrm-prod";
          };
        };
        services = {
          mrm-staging.loadBalancer.servers = [
            { url = "http://mrm-staging.wildebeest-stargazer.ts.net:3000"; }
          ];
          mrm-prod.loadBalancer.servers = [
            { url = "http://mrm-prod.wildebeest-stargazer.ts.net:3000"; }
          ];
        };
      };
    };
  };

  # Obscurus Excalidraw — proxied via Tailscale MagicDNS, protected by Authentik
  # Main app (port 3000) and excalidraw-room collaboration server (port 3002, /socket.io path)
  environment.etc."traefik/conf.d/obscurus.toml" = {
    source = (pkgs.formats.toml { }).generate "obscurus.toml" {
      http = {
        middlewares.obscurus-auth.forwardAuth = {
          address = "http://127.0.0.1:9000/outpost.goauthentik.io/auth/traefik";
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
          obscurus-outpost = {
            rule = "Host(`obscurus.hogwarts.dev`) && PathPrefix(`/outpost.goauthentik.io`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" ];
            service = "obscurus-authentik-outpost";
            priority = 30;
          };
          obscurus-room = {
            rule = "Host(`obscurus.hogwarts.dev`) && PathPrefix(`/socket.io`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" "obscurus-auth" ];
            service = "obscurus-room";
            priority = 20;
          };
          obscurus = {
            rule = "Host(`obscurus.hogwarts.dev`)";
            entryPoints = [ "websecure" ];
            tls.certResolver = "cloudflare";
            middlewares = [ "hsts" "obscurus-auth" ];
            service = "obscurus";
            priority = 10;
          };
        };
        services = {
          obscurus.loadBalancer.servers = [
            { url = "http://obscurus.wildebeest-stargazer.ts.net:3000"; }
          ];
          obscurus-room.loadBalancer.servers = [
            { url = "http://obscurus.wildebeest-stargazer.ts.net:3002"; }
          ];
          obscurus-authentik-outpost.loadBalancer.servers = [
            { url = "http://127.0.0.1:9000"; }
          ];
        };
      };
    };
  };

  # ExcaliDash — Excalidraw dashboard with persistence, proxied via Tailscale, OIDC handled by app
  environment.etc."traefik/conf.d/excalidash.toml" = {
    source = (pkgs.formats.toml { }).generate "excalidash.toml" {
      http = {
        routers.excalidash = {
          rule = "Host(`excalidash.hogwarts.dev`)";
          entryPoints = [ "websecure" ];
          tls.certResolver = "cloudflare";
          middlewares = [ "hsts" ];
          service = "excalidash";
        };
        services.excalidash.loadBalancer.servers = [
          { url = "http://obscurus.wildebeest-stargazer.ts.net:6767"; }
        ];
      };
    };
  };

  networking.firewall.allowedTCPPorts = [
    80
    443
    2222 # knot SSH
    6697 # soju IRC (TLS)
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
