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
    extraGroups = [ "wheel" "docker" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHm7lo7umraewipgQu1Pifmoo/V8jYGDHjBTmt+7SOCe me@jaspermayone.com"
    ];
  };

  nixpkgs.config.allowUnfree = true;

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
    unpoller-env = {
      file = ../../secrets/unpoller-env.age;
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

  # ── Active Directory / SSSD ───────────────────────────────────────────────────
  # After deploying, SSH in and run once:
  #   sudo realm join -U Administrator hogwarts.internal
  security.krb5 = {
    enable = true;
    settings = {
      libdefaults = {
        default_realm = "HOGWARTS.INTERNAL";
        dns_lookup_realm = false;
        dns_lookup_kdc = true;
      };
      realms."HOGWARTS.INTERNAL" = {
        admin_server = "hogwarts.internal";
        kdc = "10.100.20.10";
      };
      domain_realm = {
        ".hogwarts.internal" = "HOGWARTS.INTERNAL";
        "hogwarts.internal" = "HOGWARTS.INTERNAL";
      };
    };
  };

  services.sssd = {
    enable = true;
    config = ''
      [sssd]
      domains = hogwarts.internal
      config_file_version = 2
      services = nss, pam

      [domain/hogwarts.internal]
      ad_domain = hogwarts.internal
      krb5_realm = HOGWARTS.INTERNAL
      realmd_tags = manages-system joined-with-adcli
      cache_credentials = True
      id_provider = ad
      krb5_store_password_if_offline = True
      default_shell = /bin/bash
      ldap_id_mapping = True
      use_fully_qualified_names = True
      fallback_homedir = /home/%u@%d
      access_provider = ad
    '';
  };

  # Don't fail on first boot before realm join — keytab won't exist yet
  systemd.services.sssd.unitConfig.ConditionPathExists = "/etc/krb5.keytab";

  # Create home dirs automatically on first AD-user login
  security.pam.services.sshd.makeHomeDir = true;

  # Domain Admins get passwordless sudo
  # Group name as normalised by SSSD (lowercase, space preserved)
  security.sudo.extraConfig = ''
    %domain\ admins ALL=(ALL) NOPASSWD: ALL
  '';

  # ── UniFi Poller ──────────────────────────────────────────────────────────────
  # Runs in Docker with host networking so it can reach InfluxDB on localhost:8086.
  # UniFi credentials come from the agenix env file; InfluxDB settings are static.
  systemd.services.unpoller = {
    description = "UniFi Poller";
    after = [ "docker.service" "influxdb.service" "network-online.target" ];
    requires = [ "docker.service" "influxdb.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      EnvironmentFile = config.age.secrets.unpoller-env.path;
      ExecStartPre = [
        "-${pkgs.docker}/bin/docker stop unpoller"
        "-${pkgs.docker}/bin/docker rm unpoller"
        "-${pkgs.docker}/bin/docker pull ghcr.io/unpoller/unpoller:latest"
      ];
      ExecStart = "${pkgs.docker}/bin/docker run --name unpoller --network=host --env-file ${config.age.secrets.unpoller-env.path} -e UP_INFLUXDB_URL=http://localhost:8086 -e UP_INFLUXDB_DB=unifi -e UP_POLLER_DEBUG=false ghcr.io/unpoller/unpoller:latest";
      ExecStop = "${pkgs.docker}/bin/docker stop unpoller";
      Restart = "on-failure";
      RestartSec = "10s";
      StandardOutput = "journal";
      StandardError = "journal";
      SyslogIdentifier = "unpoller";
    };
  };

  virtualisation.docker.enable = true;

  services.qemuGuest.enable = true;

  environment.systemPackages = with pkgs; [
    wget
    curl
    git
    htop
    jq
    influxdb # includes influx CLI (v1)
    adcli
    realmd
  ];

  system.stateVersion = "25.11";
}
