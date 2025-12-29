# Centralized application configs
# Manages configs for espanso, btop, gh, wakatime, etc.
{ config, lib, pkgs, isDarwin, ... }:

let
  # Paths for secrets
  secretsDir = ../secrets;
  dotsDir = "/Users/jsp/dev/dots";  # Adjust if needed
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

  # Espanso configuration
  home.file = lib.mkMerge [
    # macOS espanso paths
    (lib.mkIf isDarwin {
      "Library/Application Support/espanso/config/default.yml".source = ../configs/espanso/config/default.yml;
      "Library/Application Support/espanso/match/base.yml".source = ../configs/espanso/match/base.yml;
    })

    # Linux espanso paths
    (lib.mkIf (!isDarwin) {
      ".config/espanso/config/default.yml".source = ../configs/espanso/config/default.yml;
      ".config/espanso/match/base.yml".source = ../configs/espanso/match/base.yml;
    })

    # VS Code settings (macOS)
    (lib.mkIf isDarwin {
      "Library/Application Support/Code/User/settings.json".source = ../configs/vscode/settings.json;
      "Library/Application Support/Code/User/keybindings.json".source = ../configs/vscode/keybindings.json;
    })

    # VS Code settings (Linux)
    (lib.mkIf (!isDarwin) {
      ".config/Code/User/settings.json".source = ../configs/vscode/settings.json;
      ".config/Code/User/keybindings.json".source = ../configs/vscode/keybindings.json;
    })
  ];

  # Activation script to decrypt secrets for user configs
  # This runs on every home-manager activation
  home.activation.decryptUserSecrets = lib.hm.dag.entryAfter ["writeBoundary"] ''
    SECRETS_DIR="${dotsDir}/secrets"
    AGENIX="${pkgs.age}/bin/age"
    SSH_KEY="$HOME/.ssh/id_ed25519"

    # Only proceed if we have the SSH key for decryption
    if [ -f "$SSH_KEY" ]; then
      # Decrypt espanso secrets
      ESPANSO_SECRETS="$SECRETS_DIR/espanso-secrets.age"
      if [ -f "$ESPANSO_SECRETS" ]; then
        ${if isDarwin then ''
          ESPANSO_DIR="$HOME/Library/Application Support/espanso/match"
        '' else ''
          ESPANSO_DIR="$HOME/.config/espanso/match"
        ''}
        mkdir -p "$ESPANSO_DIR"
        $AGENIX -d -i "$SSH_KEY" "$ESPANSO_SECRETS" > "$ESPANSO_DIR/secrets.yml" 2>/dev/null || true
      fi

      # Decrypt wakatime API key and merge with config
      WAKATIME_SECRET="$SECRETS_DIR/wakatime-api-key.age"
      if [ -f "$WAKATIME_SECRET" ]; then
        API_KEY=$($AGENIX -d -i "$SSH_KEY" "$WAKATIME_SECRET" 2>/dev/null || echo "")
        if [ -n "$API_KEY" ]; then
          cat > "$HOME/.wakatime.cfg" << EOF
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
        $AGENIX -d -i "$SSH_KEY" "$NPMRC_SECRET" > "$HOME/.npmrc" 2>/dev/null || true
      fi
    fi
  '';
}
