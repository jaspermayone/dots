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
    inputs.strings.nixosModules.default
    inputs.tangled.nixosModules.knot
    inputs.tangled.nixosModules.spindle
  ];

  # System version
  system.stateVersion = "24.05";

  # Prevent /boot partition from filling up
  boot.loader.grub.configurationLimit = 10;

  # Automatic garbage collection disabled - using nh.clean instead
  # nix.gc = {
  #   automatic = true;
  #   dates = "weekly";
  #   options = "--delete-older-than 7d";
  # };

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
    inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default # agenix CLI
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
      # Add non-ETM MACs for compatibility with Kamal/net-ssh
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
    # Use json-file log driver for compatibility with Kamal proxy log rotation
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

  # Enable zsh system-wide
  programs.zsh.enable = true;

  # Sudo without password for wheel group
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
      owner = "git"; # tangled uses git user
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
    # Restic backup secrets (uncomment when ready)
    # "restic/env" = {
    #   file = ../../secrets/restic/env.age;
    #   mode = "400";
    # };
    # "restic/repo" = {
    #   file = ../../secrets/restic/repo.age;
    #   mode = "400";
    # };
    # "restic/password" = {
    #   file = ../../secrets/restic/password.age;
    #   mode = "400";
    # };

    # Strings pastebin secrets
    strings-hogwarts = {
      file = ../../secrets/strings-hogwarts.age;
      mode = "400";
    };
    strings-witcc = {
      file = ../../secrets/strings-witcc.age;
      mode = "400";
    };

    # DocuSeal SMTP password
    docuseal-smtp = {
      file = ../../secrets/docuseal-smtp.age;
      mode = "400";
      owner = "nobody"; # docuseal runs as nobody
    };

    # Crane services
    crane-services-token = {
      file = ../../secrets/crane-services-token.age;
      mode = "400";
    };
    crane-services-hmac = {
      file = ../../secrets/crane-services-hmac.age;
      mode = "400";
    };
  };

  # FRP tunnel server
  atelier.services.frps = {
    enable = true;
    domain = "tun.hogwarts.channel";
    bindPort = 7000;
    vhostHTTPPort = 7080;
    authTokenFile = config.age.secrets.frps-token.path;
    enableCaddy = true;
  };

  # Status monitoring (served on alastor.hogwarts.channel)
  atelier.services.status = {
    enable = true;
    hostname = "alastor";
    domain = "alastor.hogwarts.channel";
    services = [
      "frps"
      "caddy"
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
    cloudflareCredentialsFile = config.age.secrets.cloudflare-credentials.path;
  };

  # Tangled Knot server (official module)
  services.tangled.knot = {
    enable = true;
    package = inputs.tangled.packages.${pkgs.stdenv.hostPlatform.system}.knot;
    server = {
      owner = "did:plc:abgthiqrd7tczkafjm4ennbo";
      hostname = "knot.jaspermayone.com";
      listenAddr = "127.0.0.1:5555";
    };
  };

  # Tangled Spindle CI/CD runner (official module)
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
    enableGatekeeper = false; # Disabled for now - was causing pdsadmin issues
    enableAgeAssurance = true;
  };

  # Atuin sync server
  atelier.services.atuin-server = {
    enable = true;
    hostname = "atuin.hogwarts.dev";
    cloudflareCredentialsFile = config.age.secrets.cloudflare-credentials.path;
  };

  # Knot to GitHub sync service
  jsp.services.knot-sync = {
    enable = true;
    repoDir = "/var/lib/knot/repos/did:plc:abgthiqrd7tczkafjm4ennbo";
    secretsFile = config.age.secrets.knot-sync-github-token.path;
  };

  # Strings pastebin servers
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

  # DocuSeal document signing
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
      SMTP_ENABLE_STARTTLS = "false"; # Port 465 uses implicit SSL/TLS, not STARTTLS
      SMTP_SSL_VERIFY = "true"; # Enable certificate verification for security
    };
    extraEnvFiles = [
      config.age.secrets.docuseal-smtp.path
    ];
  };

  # Configure docuseal Redis to use a different port
  services.redis.servers.docuseal.port = lib.mkForce 6380;

  # Caddy reverse proxy (with Cloudflare DNS plugin for ACME)
  services.caddy = {
    enable = true;
    package = pkgs.caddy-cloudflare;
    virtualHosts."knot.jaspermayone.com" = {
      extraConfig = ''
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
        }
        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        }
        reverse_proxy localhost:5555 {
          header_up X-Forwarded-Proto {scheme}
          header_up X-Forwarded-For {remote}
        }
      '';
    };
    virtualHosts."str.hogwarts.dev" = {
      extraConfig = ''
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
        }
        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        }
        reverse_proxy localhost:3100 {
          header_up X-Forwarded-Proto {scheme}
          header_up X-Forwarded-For {remote}
        }
      '';
    };
    virtualHosts."str.witcc.dev" = {
      extraConfig = ''
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
        }
        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        }
        reverse_proxy localhost:3101 {
          header_up X-Forwarded-Proto {scheme}
          header_up X-Forwarded-For {remote}
        }
      '';
    };
    virtualHosts."server-calendar.witcc.dev" = {
      extraConfig = ''
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
        }
        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        }
        reverse_proxy localhost:3002 {
          header_up X-Forwarded-Proto {scheme}
          header_up X-Forwarded-For {remote}
          header_up X-Forwarded-Host {host}
        }
      '';
    };
    virtualHosts."1.alastor.spindle.hogwarts.dev" = {
      extraConfig = ''
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
        }
        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        }
        reverse_proxy localhost:6555 {
          header_up X-Forwarded-Proto {scheme}
          header_up X-Forwarded-For {remote}
        }
      '';
    };
    virtualHosts."sign.singlefeather.com" = {
      extraConfig = ''
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
        }
        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        }
        reverse_proxy localhost:3200 {
          header_up X-Forwarded-Proto {scheme}
          header_up X-Forwarded-For {remote}
          header_up X-Forwarded-Host {host}
        }
      '';
    };
    virtualHosts."idp.patchworklabs.org" = {
      extraConfig = ''
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
        }
        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        }
        reverse_proxy localhost:3003 {
          header_up X-Forwarded-Proto {scheme}
          header_up X-Forwarded-For {remote}
          header_up X-Forwarded-Host {host}
        }
      '';
    };
    virtualHosts."plex.hogwarts.dev" = {
      extraConfig = ''
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
        }
        reverse_proxy pensieve.wildebeest-stargazer.ts.net:32400 {
          flush_interval -1
          header_up X-Forwarded-Proto {scheme}
          header_up X-Forwarded-For {remote}
          header_up Host {upstream_hostport}
        }
      '';
    };
    virtualHosts."services.cranebrowser.com" = {
      extraConfig = ''
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
        }
        header {
          Strict-Transport-Security "max-age=63072000"
        }

        @root path /
        redir @root https://cranebrowser.com 302

        handle /robots.txt {
          respond "User-agent: *\nDisallow: /\n" 200
        }

        handle /bangs.json {
          header Cache-Control "public, max-age=86400, stale-if-error=604800"
          header Access-Control-Allow-Origin *
          root * /opt/crane-services/svc/bangs
          file_server
        }

        handle_path /updates/mac* {
          reverse_proxy https://updates.cranebrowser.com {
            header_up Host updates.cranebrowser.com
          }
        }

        handle_path /ext/* {
          reverse_proxy localhost:9002 localhost:9003 {
            lb_policy first
            header_up X-Forwarded-Proto {scheme}
            header_up X-Forwarded-For {remote}
          }
        }

        handle /com* {
          reverse_proxy localhost:9002 localhost:9003 {
            lb_policy first
            header_up X-Forwarded-Proto {scheme}
            header_up X-Forwarded-For {remote}
          }
        }

        handle_path /ubo/* {
          reverse_proxy localhost:9001 {
            header_up X-Forwarded-Proto {scheme}
            header_up X-Forwarded-For {remote}
          }
        }

        handle_path /filters/* {
          header Cache-Control "public, max-age=3600, stale-if-error=86400"
          header Access-Control-Allow-Origin *
          root * /opt/crane-services/filters
          file_server
        }
      '';
    };
  };

  systemd.services.caddy.serviceConfig.EnvironmentFile = [
    config.age.secrets.cloudflare-credentials.path
  ];

  networking.firewall.allowedTCPPorts = [
    80
    443
    2222
  ]; # 2222 for knot SSH

  # Castle backup system (disabled for now - enable when secrets are ready)
  # To enable:
  # 1. Create secrets: agenix -e secrets/restic/env.age (B2_ACCOUNT_ID=..., B2_ACCOUNT_KEY=...)
  # 2. Create secrets: agenix -e secrets/restic/repo.age (b2:bucket-name:/backup-path)
  # 3. Create secrets: agenix -e secrets/restic/password.age (repository encryption password)
  # 4. Uncomment the age.secrets above
  # 5. Uncomment castle.backup below
  #
  # castle.backup = {
  #   enable = true;
  #   services = {
  #     knot = {
  #       paths = [ "/var/lib/knot" "/home/git" ];
  #       exclude = [ "*.log" ".git" ];
  #       tags = [ "service:knot" "type:git" ];
  #       preBackup = ''
  #         systemctl stop tangled-knot || true
  #       '';
  #       postBackup = ''
  #         systemctl start tangled-knot || true
  #       '';
  #     };
  #     pds = {
  #       paths = [ "/var/lib/pds" ];
  #       exclude = [ "*.log" "node_modules" ];
  #       tags = [ "service:pds" "type:atproto" ];
  #       preBackup = ''
  #         systemctl stop bluesky-pds || true
  #       '';
  #       postBackup = ''
  #         systemctl start bluesky-pds || true
  #       '';
  #     };
  #     atuin = {
  #       paths = [ "/var/lib/atuin-server" ];
  #       exclude = [ "*.log" ];
  #       tags = [ "service:atuin" "type:sqlite" ];
  #       preBackup = ''
  #         sqlite3 /var/lib/atuin-server/atuin.db "PRAGMA wal_checkpoint(TRUNCATE);" || true
  #         systemctl stop atuin-server || true
  #       '';
  #       postBackup = ''
  #         systemctl start atuin-server || true
  #       '';
  #     };
  #   };
  # };

  # Crane browser services
  crane.services = {
    enable = true;
    hostname = "services.cranebrowser.com";
    proxyBaseUrl = "https://services.cranebrowser.com/ext";
    uboProxyBaseUrl = "https://services.cranebrowser.com/ubo/";
    repoTokenFile = config.age.secrets.crane-services-token.path;
    hmacSecretFile = config.age.secrets.crane-services-hmac.path;
    behindProxy = true;
    openFirewall = false; # ports 80/443 already opened below
  };

  # Automatic updates - checks daily at 4am
  system.autoUpgrade = {
    enable = true;
    flake = "github:jaspermayone/dots#alastor";
    dates = "04:00";
    allowReboot = false; # Set to true if you want automatic reboots when needed
  };
}
