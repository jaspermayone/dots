# Alastor - NixOS server running frp tunnel service (named after Mad-Eye Moody)
{ config, pkgs, lib, inputs, hostname, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/frps
    ../../modules/status
    ../../modules/knot/sync.nix
    ../../modules/bluesky-pds/default.nix
    ../../modules/atuin-server
    inputs.tangled.nixosModules.knot
  ];

  # System version
  system.stateVersion = "24.05";

  # Hostname
  networking.hostName = hostname;

  # Nix settings
  nix = {
    settings.experimental-features = [ "nix-command" "flakes" ];
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
    inputs.agenix.packages.${pkgs.system}.default  # agenix CLI
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

  # User account
  users.users.jsp = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
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
    github-token = {
      file = ../../secrets/github-token.age;
      mode = "400";
      owner = "git";  # tangled uses git user
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
    services = [ "frps" "caddy" "tailscaled" "tangled-knot" "atuin-server" ];
    remoteHosts = [ "remus" "dippet" ];
    cloudflareCredentialsFile = config.age.secrets.cloudflare-credentials.path;
  };

  # Tangled Knot server (official module)
  services.tangled.knot = {
    enable = true;
    package = inputs.tangled.packages.${pkgs.system}.knot;
    server = {
      owner = "did:plc:abgthiqrd7tczkafjm4ennbo";
      hostname = "knot.jaspermayone.com";
      listenAddr = "127.0.0.1:5555";
    };
  };

  services.bluesky-pds-hosting = {
    enable = true;
    hostname = "pds.hogwarts.dev";
    port = 3000;
    adminEmail = "pds-admin@hogwarts.dev";
    environmentFile = config.age.secrets.pds.path;
    mailerEnvironmentFile = config.age.secrets.pds-mailer.path;
    enableGatekeeper = false;  # Disabled for now - was causing pdsadmin issues
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
    secretsFile = config.age.secrets.github-token.path;
  };

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
  };

  systemd.services.caddy.serviceConfig.EnvironmentFile = config.age.secrets.cloudflare-credentials.path;

  networking.firewall.allowedTCPPorts = [ 80 443 2222 ];  # 2222 for knot SSH

  # Automatic garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Automatic updates - checks daily at 4am
  system.autoUpgrade = {
    enable = true;
    flake = "github:jaspermayone/dots#alastor";
    dates = "04:00";
    allowReboot = false;  # Set to true if you want automatic reboots when needed
  };
}
