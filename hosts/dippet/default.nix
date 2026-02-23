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
        ${pkgs.git}/bin/git -C "$repo" pull --ff-only || true
      else
        echo "Cloning $repo..."
        ${pkgs.git}/bin/git clone "https://github.com/$ORG/$repo.git" || true
        sleep 1
      fi
    done

    echo "Sync complete: $(date)"
  '';

  spindle-run = pkgs.writeShellScript "spindle-run" ''
    set -euo pipefail

    export SPINDLE_SERVER_HOSTNAME="1.dippet.spindle.hogwarts.dev"
    export SPINDLE_SERVER_OWNER="did:plc:abgthiqrd7tczkafjm4ennbo"
    export SPINDLE_SERVER_LISTEN_ADDR="127.0.0.1:6556"
    export SPINDLE_SERVER_DB_PATH="/Users/jsp/Library/Application Support/spindle/spindle.db"
    export SPINDLE_PIPELINES_LOG_DIR="/Users/jsp/Library/Logs/spindle"

    # Create necessary directories
    mkdir -p "/Users/jsp/Library/Application Support/spindle"
    mkdir -p "/Users/jsp/Library/Logs/spindle"

    # Run spindle
    exec ${inputs.tangled.packages.${pkgs.stdenv.hostPlatform.system}.spindle}/bin/spindle
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

  # Tangled Spindle CI/CD runner
  launchd.daemons.tangled-spindle = {
    script = ''
      ${spindle-run}
    '';
    serviceConfig = {
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "/Users/jsp/Library/Logs/spindle.log";
      StandardErrorPath = "/Users/jsp/Library/Logs/spindle.log";
      UserName = "jsp";
      GroupName = "staff";
      EnvironmentVariables = {
        HOME = "/Users/jsp";
        PATH = "${pkgs.docker}/bin:/usr/bin:/bin";
      };
    };
  };

  # QMD semantic search MCP for Obsidian vault
  launchd.daemons.qmd-obsidian = {
    script = ''
      ${pkgs.nodejs}/bin/npx -y supergateway \
        --stdio "npx -y @tobilu/qmd mcp" \
        --port 8766 \
        --outputTransport streamableHttp
    '';
    serviceConfig = {
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "/Users/jsp/Library/Logs/qmd-obsidian.log";
      StandardErrorPath = "/Users/jsp/Library/Logs/qmd-obsidian.log";
      UserName = "jsp";
      GroupName = "staff";
      EnvironmentVariables = {
        HOME = "/Users/jsp";
        PATH = "${pkgs.nodejs}/bin:/usr/bin:/bin";
      };
    };
  };

  # Filesystem MCP for Obsidian vault read/write
  launchd.daemons.supergateway-obsidian = {
    script = ''
      ${pkgs.nodejs}/bin/npx -y supergateway \
        --stdio "${pkgs.nodejs}/bin/npx -y @modelcontextprotocol/server-filesystem /Users/jsp/Desktop/Jasper" \
        --port 8767 \
        --outputTransport streamableHttp
    '';
    serviceConfig = {
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "/Users/jsp/Library/Logs/supergateway-obsidian.log";
      StandardErrorPath = "/Users/jsp/Library/Logs/supergateway-obsidian.log";
      UserName = "jsp";
      GroupName = "staff";
      EnvironmentVariables = {
        HOME = "/Users/jsp";
        PATH = "${pkgs.nodejs}/bin:/usr/bin:/bin";
      };
    };
  };

  # MBTA MCP server (runs via Docker)
  launchd.daemons.supergateway-mbta = {
    script = ''
      # Use a clean Docker config to avoid docker-credential-desktop issues
      mkdir -p /Users/jsp/.config/mbta-docker
      echo '{}' > /Users/jsp/.config/mbta-docker/config.json

      MBTA_API_KEY=$(cat /Users/jsp/.config/mbta/api-key)
      ${pkgs.nodejs}/bin/npx -y supergateway \
        --stdio "${pkgs.docker}/bin/docker run --pull never -i -e MBTA_API_KEY=$MBTA_API_KEY ghcr.io/crdant/mbta-mcp-server:latest" \
        --port 8768 \
        --outputTransport streamableHttp
    '';
    serviceConfig = {
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "/Users/jsp/Library/Logs/supergateway-mbta.log";
      StandardErrorPath = "/Users/jsp/Library/Logs/supergateway-mbta.log";
      UserName = "jsp";
      GroupName = "staff";
      EnvironmentVariables = {
        HOME = "/Users/jsp";
        PATH = "${pkgs.nodejs}/bin:${pkgs.docker}/bin:/usr/bin:/bin";
        DOCKER_CONFIG = "/Users/jsp/.config/mbta-docker";
      };
    };
  };

  # MBTA API key for the MCP server
  age.secrets.mbta-api-key = {
    file = ../../secrets/mbta-api-key.age;
    path = "/Users/jsp/.config/mbta/api-key";
    owner = "jsp";
    mode = "400";
  };

  # Cloudflare tunnel for Spindle
  # Add this route to your existing cloudflared tunnel config:
  #   - hostname: 1.dippet.spindle.hogwarts.dev
  #     service: http://localhost:6556

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
    # Docker Desktop for macOS (required for Spindle)
    "docker"
    # Desktop apps are inherited from shared config (espanso, raycast, bitwarden)
  ];

  # Any dippet-specific system defaults
  # system.defaults = { };

  # Set the hostname
  networking.hostName = "dippet";
  networking.computerName = "Dippet";
}
