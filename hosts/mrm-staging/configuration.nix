# mrm-staging — MentorDb staging VM (Proxmox/SeaBIOS, x86_64)
# Accessible at staging.madrivermentoring.com via alastor → Traefik → Tailscale.
{
  config,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
    ../../modules/mentordb
  ];

  networking = {
    hostName = "mrm-staging";
    useDHCP = false;
    interfaces.ens18.useDHCP = true;
    dhcpcd.wait = "background";
    dhcpcd.extraConfig = ''
      nooption domain_name_servers, domain_search
      clientid
    '';
    nameservers = [ "10.100.20.10" ];
    search = [ "hogwarts.internal" ];
  };

  time.timeZone = "America/New_York";

  boot.loader.grub.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

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

  nixpkgs.config.allowUnfree = true;
  programs.zsh.enable = true;
  security.sudo.wheelNeedsPassword = false;

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "root"
      "jsp"
    ];
  };
  nix.optimise.automatic = true;

  # ── QEMU guest agent ─────────────────────────────────────────────────────────
  services.qemuGuest.enable = true;

  # ── Tailscale ────────────────────────────────────────────────────────────────
  services.tailscale.enable = true;

  # ── agenix secrets ───────────────────────────────────────────────────────────
  # After first boot: get the host key with `ssh-keyscan mrm-staging`,
  # add it to secrets/secrets.nix, then create mentordb-staging-env.age.
  age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  age.secrets.mentordb-staging-env = {
    file = ../../secrets/mentordb-staging-env.age;
    mode = "400";
  };

  # ── MentorDb ─────────────────────────────────────────────────────────────────
  services.mentordb = {
    enable = true;
    image = "ghcr.io/singlefeather/mentordb:main";
    publicHostname = "staging.madrivermentoring.com";
    port = 3000;
    environmentFile = config.age.secrets.mentordb-staging-env.path;
  };

  environment.systemPackages = with pkgs; [
    wget
    curl
    git
    htop
    jq
  ];

  system.stateVersion = "25.11";
}
