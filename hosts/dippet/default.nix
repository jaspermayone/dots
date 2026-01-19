# Dippet - Mac Mini (server + desktop)
{
  config,
  pkgs,
  lib,
  inputs,
  hostname,
  ...
}:

let
  forks-sync = pkgs.writeShellScript "forks-sync" ''
    set -euo pipefail

    FORKS_DIR="/Users/jsp/forks"
    ORG="jaspermayone-forks"

    mkdir -p "$FORKS_DIR"
    cd "$FORKS_DIR"

    # Get list of repos from GitHub
    repos=$(${pkgs.gh}/bin/gh repo list "$ORG" --limit 1000 --json name -q '.[].name')

    for repo in $repos; do
      if [ -d "$repo" ]; then
        echo "Updating $repo..."
        cd "$repo"
        ${pkgs.git}/bin/git pull --ff-only || true
        cd ..
      else
        echo "Cloning $repo..."
        ${pkgs.gh}/bin/gh repo clone "$ORG/$repo" || true
      fi
    done

    echo "Sync complete: $(date)"
  '';
in
{
  # Disable nix-darwin's Nix management (using Determinate Nix installer)
  nix.enable = false;

  # Auto-update from GitHub daily at 4am
  launchd.daemons.nix-darwin-upgrade = {
    script = ''
      /run/current-system/sw/bin/darwin-rebuild switch --flake github:jaspermayone/dots#dippet
    '';
    serviceConfig = {
      StartCalendarInterval = [
        {
          Hour = 4;
          Minute = 0;
        }
      ];
      StandardOutPath = "/var/log/nix-darwin-upgrade.log";
      StandardErrorPath = "/var/log/nix-darwin-upgrade.log";
    };
  };

  # Sync forks from jaspermayone-forks org hourly
  launchd.daemons.forks-sync = {
    script = ''
      ${forks-sync}
    '';
    serviceConfig = {
      StartInterval = 3600; # Every hour
      StandardOutPath = "/Users/jsp/Library/Logs/forks-sync.log";
      StandardErrorPath = "/Users/jsp/Library/Logs/forks-sync.log";
      UserName = "jsp";
      GroupName = "staff";
      EnvironmentVariables = {
        HOME = "/Users/jsp";
        PATH = "${pkgs.git}/bin:${pkgs.gh}/bin:/usr/bin:/bin";
      };
    };
  };

  # Agenix identity path (use user SSH key on macOS)
  age.identityPaths = [ "/Users/jsp/.ssh/id_ed25519" ];

  # Agenix secrets for bore client
  age.secrets.bore-token = {
    file = ../../secrets/bore-token.age;
    path = "/Users/jsp/.config/bore/token";
    owner = "jsp";
    mode = "400";
  };

  # Atuin encryption key for auto-login
  age.secrets.atuin-key = {
    file = ../../secrets/atuin-key.age;
    path = "/Users/jsp/.local/share/atuin/key";
    owner = "jsp";
    mode = "400";
  };

  # Server packages (dippet-specific)
  homebrew.brews = [
    # Web/networking
    "nginx"
    "cloudflared"
    "certbot"
    "unbound"

    # Libraries/tools currently installed
    "augeas"
    "poppler"
    "python@3.14"
  ];

  # Dippet-specific homebrew casks
  homebrew.casks = [
    # Desktop apps are inherited from shared config (espanso, raycast, bitwarden)
  ];

  # Any dippet-specific system defaults
  # system.defaults = { };

  # Set the hostname
  networking.hostName = "dippet";
  networking.computerName = "Dippet";
}
