# Kreacher - PostHog analytics for FundingFindr
# ph.fundingfindr.co
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
    ../../modules/posthog
  ];

  # Disk layout — managed by disko, applied by nixos-anywhere on first install.
  # GPT + BIOS boot partition + ext4 root (Proxmox VirtIO SCSI, /dev/sda, 80GB).
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/sda";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            size = "1M";
            type = "EF02"; # BIOS boot
          };
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              mountOptions = [ "defaults" ];
            };
          };
        };
      };
    };
  };

  system.stateVersion = "25.11";

  boot.tmp.cleanOnBoot = true;
  boot.loader.grub = {
    enable = true;
    efiSupport = false;
    configurationLimit = 5;
  };

  networking.hostName = hostname;

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [ "root" "jsp" ];
    };
    optimise.automatic = true;
  };

  nixpkgs.config.allowUnfree = true;

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    curl
    jq
    tmux
    inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  programs.nh = {
    enable = true;
    clean.enable = true;
    clean.extraArgs = "--keep-since 4d --keep 3";
    flake = "/home/jsp/dots";
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
      KbdInteractiveAuthentication = false;
    };
  };

  services.fail2ban = {
    enable = true;
    maxretry = 5;
  };

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
  };

  users.users.jsp = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHm7lo7umraewipgQu1Pifmoo/V8jYGDHjBTmt+7SOCe jsp@remus"
    ];
  };

  programs.nix-ld.enable = true;
  programs.zsh.enable = true;
  security.sudo.wheelNeedsPassword = false;

  # Agenix — decrypt secrets using this host's SSH host key
  age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  age.secrets = {
    kreacher-posthog = {
      file = ../../secrets/kreacher-posthog.age;
      mode = "400";
    };
  };

  atelier.services.posthog = {
    enable = true;
    hostname = "ph.fundingfindr.co";
    environmentFile = config.age.secrets.kreacher-posthog.path;
    behindProxy = true;
  };

  system.autoUpgrade = {
    enable = true;
    flake = "github:jaspermayone/dots#kreacher";
    dates = "04:00";
    allowReboot = false;
  };
}
