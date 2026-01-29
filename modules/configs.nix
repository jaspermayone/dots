# Centralized application configs
# Manages configs for espanso, btop, gh, wakatime, etc.
{
  config,
  lib,
  pkgs,
  isDarwin,
  ...
}:

let
  # Paths for secrets - platform-specific
  dotsDir = if isDarwin then "/Users/jsp/dev/dots" else "/home/jsp/dots";
in
{
  # btop configuration
  xdg.configFile."btop/btop.conf".source = ../configs/btop.conf;

  # Note: gh CLI is configured in modules/git.nix via programs.gh

  # Karabiner configuration (keyboard remapping) - macOS only
  xdg.configFile."karabiner/karabiner.json" = lib.mkIf isDarwin {
    source = ../configs/karabiner.json;
  };

  # Mise (version manager) configuration
  xdg.configFile."mise/config.toml".source = ../configs/mise.toml;

  # Home file configurations (merged together)
  home.file = lib.mkMerge [
    # Claude Code configuration
    {
      ".claude/CLAUDE.md".source = ../configs/claude/CLAUDE.md;
      ".claude/settings.json".source = ../configs/claude/settings.json;
    }
    # macOS espanso paths
    (lib.mkIf isDarwin {
      "Library/Application Support/espanso/config/default.yml".source =
        ../configs/espanso/config/default.yml;
      "Library/Application Support/espanso/match/base.yml".source = ../configs/espanso/match/base.yml;
      "Library/Application Support/espanso/match/wit.yml".source = ../configs/espanso/match/wit.yml;
      "Library/Application Support/espanso/match/personal.yml".source = ../configs/espanso/match/personal.yml;
    })

    # Linux espanso paths
    (lib.mkIf (!isDarwin) {
      ".config/espanso/config/default.yml".source = ../configs/espanso/config/default.yml;
      ".config/espanso/match/base.yml".source = ../configs/espanso/match/base.yml;
      ".config/espanso/match/wit.yml".source = ../configs/espanso/match/wit.yml;
      ".config/espanso/match/personal.yml".source = ../configs/espanso/match/personal.yml;
    })

    # VS Code settings (macOS)
    (lib.mkIf isDarwin {
      "Library/Application Support/Code/User/settings.json".source = ../configs/vscode/settings.json;
      "Library/Application Support/Code/User/keybindings.json".source =
        ../configs/vscode/keybindings.json;
    })

    # VS Code settings (Linux)
    (lib.mkIf (!isDarwin) {
      ".config/Code/User/settings.json".source = ../configs/vscode/settings.json;
      ".config/Code/User/keybindings.json".source = ../configs/vscode/keybindings.json;
    })
  ];

  # Activation script to decrypt secrets for user configs
  # This runs on every home-manager activation
  home.activation.decryptUserSecrets = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        SECRETS_DIR="${dotsDir}/secrets"
        AGE="${pkgs.age}/bin/age"
        SSH_KEY="$HOME/.ssh/id_ed25519"
        ${
          if isDarwin then
            ''
              ESPANSO_DIR="$HOME/Library/Application Support/espanso/match"
            ''
          else
            ''
              ESPANSO_DIR="$HOME/.config/espanso/match"
            ''
        }

        # Only proceed if we have the SSH key for decryption
        if [ -f "$SSH_KEY" ]; then
          # Decrypt espanso secrets
          ESPANSO_SECRETS="$SECRETS_DIR/espanso-secrets.age"
          if [ -f "$ESPANSO_SECRETS" ]; then
            $DRY_RUN_CMD mkdir -p "$ESPANSO_DIR"
            $DRY_RUN_CMD $AGE -d -i "$SSH_KEY" "$ESPANSO_SECRETS" > "$ESPANSO_DIR/secrets.yml" 2>/dev/null || echo "Warning: Failed to decrypt espanso secrets"
          fi

          # Decrypt wakatime API key and merge with config
          WAKATIME_SECRET="$SECRETS_DIR/wakatime-api-key.age"
          if [ -f "$WAKATIME_SECRET" ]; then
            API_KEY=$($AGE -d -i "$SSH_KEY" "$WAKATIME_SECRET" 2>/dev/null || echo "")
            if [ -n "$API_KEY" ]; then
              $DRY_RUN_CMD cat > "$HOME/.wakatime.cfg" << EOF
    [settings]
    api_url = https://waka.hogwarts.dev/api
    api_key = $API_KEY
    debug = false
    status_bar_coding_activity = true
    status_bar_enabled = false
    EOF
            fi
          fi

          # Decrypt npmrc (contains registry auth tokens)
          NPMRC_SECRET="$SECRETS_DIR/npmrc.age"
          if [ -f "$NPMRC_SECRET" ]; then
            $DRY_RUN_CMD $AGE -d -i "$SSH_KEY" "$NPMRC_SECRET" > "$HOME/.npmrc" 2>/dev/null || echo "Warning: Failed to decrypt npmrc"
          fi

          # Decrypt Claude GitHub token (for MCP server)
          CLAUDE_GITHUB_SECRET="$SECRETS_DIR/claude-github-token.age"
          if [ -f "$CLAUDE_GITHUB_SECRET" ]; then
            $DRY_RUN_CMD mkdir -p "$HOME/.config/claude"
            $DRY_RUN_CMD $AGE -d -i "$SSH_KEY" "$CLAUDE_GITHUB_SECRET" > "$HOME/.config/claude/github-token" 2>/dev/null || echo "Warning: Failed to decrypt Claude GitHub token"
            $DRY_RUN_CMD chmod 600 "$HOME/.config/claude/github-token"
          fi
        fi
  '';
}
