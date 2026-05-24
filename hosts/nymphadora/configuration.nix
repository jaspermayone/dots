{
  config,
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
    ../../modules/traefik
    ../../modules/telemetry
  ];

  networking = {
    hostName = "nymphadora";
    useDHCP = false;
    interfaces.ens18.useDHCP = true;
    # Don't block boot waiting for DHCP to complete
    dhcpcd.wait = "background";
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
    extraGroups = [ "wheel" "docker" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHm7lo7umraewipgQu1Pifmoo/V8jYGDHjBTmt+7SOCe jsp@remus"
    ];
  };

  programs.zsh.enable = true;

  security.sudo.wheelNeedsPassword = false;

  # ── agenix secrets ───────────────────────────────────────────────────────────
  # After installing: get the host public key with `ssh-keyscan nymphadora`,
  # add it to secrets/secrets.nix, then re-encrypt / create the secrets below.
  age.secrets = {
    cloudflare-credentials = {
      file = ../../secrets/cloudflare-credentials.age;
    };
    grafana-admin-password = {
      file = ../../secrets/grafana-admin-password.age;
      owner = "grafana";
    };
    grafana-oauth-env = {
      file = ../../secrets/grafana-oauth-env.age;
      owner = "grafana";
    };
  };

  # ── Traefik ───────────────────────────────────────────────────────────────────
  services.traefik-compose = {
    enable = true;
    acmeEmail = "jaspermayone@gmail.com";
    cloudflareCredentialsFile = config.age.secrets.cloudflare-credentials.path;
  };

  # ── Telemetry stack ───────────────────────────────────────────────────────────
  atelier.services.telemetry = {
    enable = true;
    hostname = "telemetry.hogwarts.dev";
    authentikHostname = "a.hogwarts.dev";
    grafanaAdminPasswordFile = config.age.secrets.grafana-admin-password.path;
    grafanaOAuthEnvFile = config.age.secrets.grafana-oauth-env.path;
  };

  services.tailscale.enable = true;

  virtualisation.docker.enable = true;

  environment.systemPackages = with pkgs; [
    wget
    curl
    git
    htop
    jq
    influxdb # includes influx CLI (v1)
  ];

  system.stateVersion = "25.11";
}
