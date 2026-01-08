# Horace - NixOS desktop (named after Horace Slughorn)
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
    inputs.rust-fp.nixosModules.default
    ../../modules/wifi.nix
  ];

  # Boot loader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # System version
  system.stateVersion = "25.11";

  # WiFi with eduroam
  jsp.network.wifi = {
    enable = true;
    hostName = hostname;
    envFile = config.age.secrets.wifi-passwords.path;
    profiles = {
      "eduroam" = {
        eduroam = true;
        identity = "mayonej@wit.edu";
        pskVar = "EDUROAM_PSK";
      };
    };
  };

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
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # X11 windowing system
  services.xserver.enable = true;
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Plasma desktop environment
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Printing
  services.printing.enable = true;

  # Chromebook fingerprint reader (via rust-fp)
  # After rebuild, enroll with: cros-fp-cli enroll

  # Audio
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Basic packages
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    curl
    jq
    tmux
    usbutils
    kdePackages.kate
    alacritty
    discord
    element-desktop
    google-chrome
    obsidian
    signal-desktop
    slack
    spotify
    inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  # Firefox
  programs.firefox.enable = true;

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
    description = "Jasper";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
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
  age.secrets.bore-token = {
    file = ../../secrets/bore-token.age;
    path = "/home/jsp/.config/bore/token";
    owner = "jsp";
    mode = "400";
  };
  age.secrets.atuin-key = {
    file = ../../secrets/atuin-key.age;
    path = "/home/jsp/.local/share/atuin/key";
    owner = "jsp";
    mode = "400";
  };
  age.secrets.wifi-passwords = {
    file = ../../secrets/wifi-passwords.age;
  };

  # Automatic updates
  system.autoUpgrade = {
    enable = true;
    flake = "github:jaspermayone/dots#horace";
    dates = "04:00";
    allowReboot = false;
  };
}
