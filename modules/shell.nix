# Shell configuration
{
  config,
  lib,
  pkgs,
  hostname,
  inputs,
  ...
}:

let
  # Strings CLI for uploading to pastebin
  strings-cli = pkgs.writeShellScriptBin "strings" ''
    #!/usr/bin/env bash
    # strings - CLI for strings pastebin
    # Usage: strings <file> or cat file | strings

    set -e

    STRINGS_HOST="''${STRINGS_HOST:-https://str.hogwarts.dev}"
    STRINGS_USER="''${STRINGS_USER:-}"
    STRINGS_PASS="''${STRINGS_PASS:-}"

    # Try to load credentials from file if not set
    if [[ -f "$HOME/.config/strings/credentials" ]]; then
      source "$HOME/.config/strings/credentials"
    fi

    if [ -z "$STRINGS_USER" ] || [ -z "$STRINGS_PASS" ]; then
      echo "Error: STRINGS_USER and STRINGS_PASS environment variables must be set" >&2
      echo "Or create ~/.config/strings/credentials with:" >&2
      echo "  STRINGS_USER=youruser" >&2
      echo "  STRINGS_PASS=yourpass" >&2
      exit 1
    fi

    # Determine filename and content
    FILENAME=""
    SLUG=""

    while [[ $# -gt 0 ]]; do
      case $1 in
        -s|--slug)
          SLUG="$2"
          shift 2
          ;;
        -h|--host)
          STRINGS_HOST="$2"
          shift 2
          ;;
        *)
          if [ -z "$FILENAME" ]; then
            FILENAME="$1"
          fi
          shift
          ;;
      esac
    done

    if [ -n "$FILENAME" ]; then
      if [ ! -f "$FILENAME" ]; then
        echo "Error: File not found: $FILENAME" >&2
        exit 1
      fi
      BASENAME=$(basename "$FILENAME")
      CONTENT=$(cat "$FILENAME")
    else
      CONTENT=$(cat)
      BASENAME=""
    fi

    # Build headers
    HEADERS=(-H "Content-Type: text/plain")
    [ -n "$BASENAME" ] && HEADERS+=(-H "X-Filename: $BASENAME")
    [ -n "$SLUG" ] && HEADERS+=(-H "X-Slug: $SLUG")

    # Make request
    RESPONSE=$(${pkgs.curl}/bin/curl -s -X POST "$STRINGS_HOST/api/paste" \
      -u "$STRINGS_USER:$STRINGS_PASS" \
      "''${HEADERS[@]}" \
      --data-binary "$CONTENT")

    # Parse response
    URL=$(echo "$RESPONSE" | ${pkgs.gnugrep}/bin/grep -o '"url":"[^"]*"' | cut -d'"' -f4)

    if [ -n "$URL" ]; then
      echo "$URL"

      # Copy to clipboard if available
      if command -v pbcopy &> /dev/null; then
        echo -n "$URL" | pbcopy
      elif command -v xclip &> /dev/null; then
        echo -n "$URL" | xclip -selection clipboard
      elif command -v wl-copy &> /dev/null; then
        echo -n "$URL" | wl-copy
      fi
    else
      echo "Error: $RESPONSE" >&2
      exit 1
    fi
  '';

  # Tangled setup script for configuring git remotes
  tangled-setup = pkgs.writeShellScriptBin "tangled-setup" ''
    # Configuration
    default_plc_id="did:plc:krxbvxvis5skq7jj6eot23ul"
    default_github_username="jaspermayone"
    default_knot_host="knot.jaspermayone.com"

    # Verify git repository
    if ! ${pkgs.git}/bin/git rev-parse --is-inside-work-tree &>/dev/null; then
      ${pkgs.gum}/bin/gum style --foreground 196 "Not a git repository"
      exit 1
    fi

    repo_name=$(basename "$(${pkgs.git}/bin/git rev-parse --show-toplevel)")
    ${pkgs.gum}/bin/gum style --bold --foreground 212 "Configuring tangled remotes for: $repo_name"
    echo

    # Check current remotes
    origin_url=$(${pkgs.git}/bin/git remote get-url origin 2>/dev/null)
    github_url=$(${pkgs.git}/bin/git remote get-url github 2>/dev/null)
    origin_is_knot=false
    github_username="$default_github_username"

    # Extract GitHub username from existing origin if it's GitHub
    if [[ "$origin_url" == *"github.com"* ]]; then
      github_username=$(echo "$origin_url" | ${pkgs.gnused}/bin/sed -E 's/.*github\.com[:/]([^/]+)\/.*$/\1/')
    fi

    # Check if origin points to knot
    if [[ "$origin_url" == *"$default_knot_host"* ]] || [[ "$origin_url" == *"tangled"* ]]; then
      origin_is_knot=true
      ${pkgs.gum}/bin/gum style --foreground 35 "✓ Origin → knot ($origin_url)"
    elif [[ -n "$origin_url" ]]; then
      ${pkgs.gum}/bin/gum style --foreground 214 "! Origin → $origin_url (not knot)"
    else
      ${pkgs.gum}/bin/gum style --foreground 214 "! Origin not configured"
    fi

    # Check github remote
    if [[ -n "$github_url" ]]; then
      ${pkgs.gum}/bin/gum style --foreground 35 "✓ GitHub → $github_url"
    else
      ${pkgs.gum}/bin/gum style --foreground 214 "! GitHub remote not configured"
    fi

    echo

    # Configure origin remote if needed
    if [[ "$origin_is_knot" = false ]]; then
      should_migrate=true
      if [[ -n "$origin_url" ]]; then
        ${pkgs.gum}/bin/gum confirm "Migrate origin from $origin_url to knot?" || should_migrate=false
      fi

      if [[ "$should_migrate" = true ]]; then
        plc_id=$(${pkgs.gum}/bin/gum input --placeholder "$default_plc_id" --prompt "PLC ID: " --value "$default_plc_id")
        plc_id=''${plc_id:-$default_plc_id}

        if ${pkgs.git}/bin/git remote get-url origin &>/dev/null; then
          ${pkgs.git}/bin/git remote remove origin
        fi
        ${pkgs.git}/bin/git remote add origin "git@$default_knot_host:''${plc_id}/''${repo_name}"
        ${pkgs.gum}/bin/gum style --foreground 35 "✓ Configured origin → git@$default_knot_host:''${plc_id}/''${repo_name}"
      fi
    fi

    # Configure github remote if needed
    if [[ -z "$github_url" ]]; then
      username=$(${pkgs.gum}/bin/gum input --placeholder "$github_username" --prompt "GitHub username: " --value "$github_username")
      username=''${username:-$github_username}

      ${pkgs.git}/bin/git remote add github "git@github.com:''${username}/''${repo_name}.git"
      ${pkgs.gum}/bin/gum style --foreground 35 "✓ Configured github → git@github.com:''${username}/''${repo_name}.git"
    fi

    echo

    # Configure default push remote
    current_remote=$(${pkgs.git}/bin/git config --get branch.main.remote 2>/dev/null)
    if [[ -z "$current_remote" ]]; then
      if ${pkgs.gum}/bin/gum confirm "Set origin (knot) as default push remote?"; then
        ${pkgs.git}/bin/git config branch.main.remote origin
        ${pkgs.gum}/bin/gum style --foreground 35 "✓ Default push remote → origin"
      fi
    elif [[ "$current_remote" != "origin" ]]; then
      ${pkgs.gum}/bin/gum style --foreground 117 "Current default: $current_remote"
      if ${pkgs.gum}/bin/gum confirm "Change default push remote to origin (knot)?"; then
        ${pkgs.git}/bin/git config branch.main.remote origin
        ${pkgs.gum}/bin/gum style --foreground 35 "✓ Default push remote → origin"
      fi
    else
      ${pkgs.gum}/bin/gum style --foreground 35 "✓ Default push remote is origin"
    fi
  '';

in
{
  # Starship prompt
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      format = "$username$hostname$localip$directory$git_branch$git_commit$git_state$git_metrics$git_status$nix_shell$mise$bun$nodejs$python$ruby$rust$java$swift$direnv$shell$cmd_duration$line_break$character";

      # Hostname - always visible
      hostname = {
        ssh_only = false;
        format = "[$hostname]($style) ";
        style = "dimmed white";
        ssh_symbol = " ";
      };

      # Local IP - show on SSH
      localip = {
        ssh_only = true;
        format = "[@$localipv4]($style) ";
        style = "dimmed white";
        disabled = false;
      };

      # Directory
      directory = {
        style = "cyan";
        truncation_length = 3;
        truncation_symbol = "…/";
        truncate_to_repo = true;
        read_only = " 󰌾";
      };

      # Git branch
      git_branch = {
        format = "[$symbol$branch(:$remote_branch)]($style) ";
        symbol = " ";
        style = "purple";
      };

      # Git commit - show hash when detached
      git_commit = {
        format = "[$hash$tag]($style) ";
        style = "dimmed white";
        only_detached = true;
        tag_disabled = false;
        tag_symbol = "  ";
      };

      # Git state - show rebase/merge/etc
      git_state = {
        format = "[$state( $progress_current/$progress_total)]($style) ";
        style = "yellow";
      };

      # Git metrics - show +/- lines
      git_metrics = {
        format = "([+$added]($added_style))([-$deleted]($deleted_style) )";
        added_style = "green";
        deleted_style = "red";
        disabled = false;
      };

      # Git status - detailed symbols
      git_status = {
        format = "([$all_status$ahead_behind]($style) )";
        style = "dimmed red";
        conflicted = "=";
        ahead = "⇡$count";
        behind = "⇣$count";
        diverged = "⇕⇡$ahead_count⇣$behind_count";
        up_to_date = "";
        untracked = "?$count";
        stashed = "󰏗";
        modified = "!$count";
        staged = "+$count";
        renamed = "»$count";
        deleted = "✘$count";
      };

      # Bun
      bun = {
        format = "[$symbol($version)]($style) ";
        symbol = " ";
        style = "dimmed white";
      };

      # Direnv
      direnv = {
        format = "[$symbol$loaded/$allowed]($style) ";
        symbol = "direnv ";
        style = "dimmed white";
        disabled = false;
      };

      # Command duration
      cmd_duration = {
        min_time = 2000;
        format = "[$duration]($style) ";
        style = "dimmed yellow";
        show_notifications = false;
      };

      # Character
      character = {
        success_symbol = "[❯](cyan)";
        error_symbol = "[❯](red)";
      };

      # Username - show when root or SSH
      username = {
        style_root = "bold red";
        style_user = "dimmed white";
        format = "[$user]($style)@";
        show_always = false;
        disabled = false;
      };

      # Nix shell
      nix_shell = {
        format = "[$symbol$state( \\($name\\))]($style) ";
        symbol = " ";
        style = "dimmed blue";
        impure_msg = "impure";
        pure_msg = "pure";
        disabled = false;
        heuristic = true;
      };

      # Mise (version manager)
      mise = {
        format = "[$symbol$health]($style) ";
        symbol = "mise ";
        style = "dimmed white";
        disabled = false;
      };

      # Node.js
      nodejs = {
        format = "[$symbol($version)]($style) ";
        symbol = " ";
        style = "dimmed green";
        not_capable_style = "red";
      };

      # Python
      python = {
        format = "[$symbol$pyenv_prefix($version )(\\($virtualenv\\))]($style) ";
        symbol = " ";
        style = "dimmed yellow";
        pyenv_version_name = false;
      };

      # Ruby
      ruby = {
        format = "[$symbol($version)]($style) ";
        symbol = " ";
        style = "dimmed red";
      };

      # Rust
      rust = {
        format = "[$symbol($version)]($style) ";
        symbol = "󱘗 ";
        style = "dimmed red";
      };

      # Java
      java = {
        format = "[$symbol($version)]($style) ";
        symbol = " ";
        style = "dimmed red";
      };

      # Swift
      swift = {
        format = "[$symbol($version)]($style) ";
        symbol = " ";
        style = "dimmed white";
      };

      # Shell indicator
      shell = {
        format = "[$indicator]($style) ";
        style = "white bold";
        zsh_indicator = "";
        bash_indicator = "bsh";
        fish_indicator = "fish";
        disabled = true; # enable if you switch shells often
      };
    };
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      # Navigation
      ll = "eza -l";
      la = "eza -la";
      l = "eza";
      ls = "eza";
      ".." = "cd ..";
      "..." = "cd ../..";

      # Safety
      rm = "rm -i";
      cp = "cp -i";
      mv = "mv -i";
      rr = "rm -Rf";

      # Enhanced commands
      cd = "z";
      cat = "bat --paging=never";

      # Quick commands
      e = "exit";
      c = "clear";

      # Directory shortcuts
      dev = "z ~/dev";
      proj = "z ~/dev/projects";
      scripts = "z ~/dev/scripts";

      # Git shortcuts
      g = "git";
      gs = "git status";
      gd = "git diff";
      ga = "git add";
      gc = "git commit";
      gp = "git push";
      gl = "git pull";
      s = "git status";
      push = "git push";
      pull = "git pull";
      goops = "git commit --amend --no-edit && git push --force-with-lease";

      # Python
      pip = "pip3";
      python = "python3";

      cl = "claude --allow-dangerously-skip-permissions";
      clo = "ollama launch claude"

      # Project shortcuts
      dns = "z dev/dns && source .env && source .venv/bin/activate";

      # Zsh config
      zshedit = "code ~/.zshrc";
      zshreload = "source ~/.zshrc";

      # GPG key sync
      keysync = "gpg --keyserver pgp.mit.edu --send-keys 00E643C21FAC965FFB28D3B714D0D45A1DADAAFA && gpg --keyserver keyserver.ubuntu.com --send-keys 00E643C21FAC965FFB28D3B714D0D45A1DADAAFA && gpg --keyserver keys.openpgp.org --send-keys 00E643C21FAC965FFB28D3B714D0D45A1DADAAFA && gpg --export me@jaspermayone.com | curl -T - https://keys.openpgp.org";
      gpgend = "gpg --keyserver hkps://keys.openpgp.org --send-keys 14D0D45A1DADAAFA";

      path = "echo -e \${PATH//:/\\n}";

      # Vim
      vi = "vim";

      afk = "/System/Library/CoreServices/Menu\ Extras/User.menu/Contents/Resources/CGSession -suspend";
      reload = "exec \${SHELL} -l";
    };

    initContent = ''
      # ============================================================================
      # HOMEBREW
      # ============================================================================
      if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      fi

      # ============================================================================
      # ZINIT PLUGIN MANAGER
      # ============================================================================
      if [[ ! -f $HOME/.local/share/zinit/zinit.git/zinit.zsh ]]; then
          print -P "%F{33} %F{220}Installing %F{33}ZDHARMA-CONTINUUM%F{220} Initiative Plugin Manager (%F{33}zdharma-continuum/zinit%F{220})…%f"
          command mkdir -p "$HOME/.local/share/zinit" && command chmod g-rwX "$HOME/.local/share/zinit"
          command git clone https://github.com/zdharma-continuum/zinit "$HOME/.local/share/zinit/zinit.git" && \
              print -P "%F{33} %F{34}Installation successful.%f%b" || \
              print -P "%F{160} The clone has failed.%f%b"
      fi

      source "$HOME/.local/share/zinit/zinit.git/zinit.zsh"
      autoload -Uz _zinit
      (( ''${+_comps} )) && _comps[zinit]=_zinit

      # ============================================================================
      # ZINIT PLUGINS
      # ============================================================================
      zinit light zsh-users/zsh-completions
      zinit light zsh-users/zsh-autosuggestions

      # Defer fzf-tab
      zinit ice wait"0a" lucid
      zinit light Aloxaf/fzf-tab

      # Syntax highlighting loads in background
      zinit ice wait"1" lucid
      zinit light zsh-users/zsh-syntax-highlighting

      # ============================================================================
      # OH-MY-ZSH SNIPPETS (deferred)
      # ============================================================================
      zinit ice wait"0b" lucid
      zinit snippet OMZP::git-commit

      zinit ice wait"0b" lucid
      zinit snippet OMZP::sudo

      zinit ice wait"0b" lucid
      zinit snippet OMZP::command-not-found

      zinit ice wait"0b" lucid
      zinit snippet OMZP::iterm2

      # ============================================================================
      # COMPLETIONS
      # ============================================================================
      autoload -Uz compinit
      if [[ -n ''${HOME}/.zcompdump(#qN.mh+24) ]]; then
        compinit
      else
        compinit -C
      fi
      zinit cdreplay -q

      # ============================================================================
      # KEY BINDINGS
      # ============================================================================
      bindkey '^f' autosuggest-accept
      bindkey '^p' history-search-backward
      bindkey '^n' history-search-forward

      # ============================================================================
      # HISTORY CONFIGURATION
      # ============================================================================
      HISTFILE=~/.zsh_history
      HISTSIZE=999999999999
      SAVEHIST=999999999999
      HISTDUP=erase
      setopt appendhistory
      setopt extendedhistory
      setopt hist_ignore_space
      setopt hist_ignore_all_dups
      setopt hist_save_no_dups
      setopt hist_ignore_dups
      setopt hist_find_no_dups

      # ============================================================================
      # COMPLETION STYLING
      # ============================================================================
      zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
      zstyle ':completion:*' list-colors "''${(s.:.)LS_COLORS}"
      zstyle ':completion:*' menu no
      zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'
      zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'ls --color $realpath'

      # ============================================================================
      # PATH EXPORTS
      # ============================================================================
      # Note: flyctl, bun, pnpm are now managed by nix
      export PATH="$HOME/bin:$PATH"
      export PATH="$HOME/.local/bin:$PATH"
      export PATH="/Users/jsp/.lmstudio/bin:$PATH"
      export PATH="/Users/jsp/.codeium/windsurf/bin:$PATH"
      export PATH="/opt/homebrew/opt/mysql@8.0/bin:$PATH"
      export PATH="/Users/jsp/.antigravity/antigravity/bin:$PATH"
      export PATH="$HOME/go/bin:$PATH"
      export PATH="$HOME/toolchains/gcc-arm-none-eabi-10.3-2021.10/bin:$PATH"

      # ============================================================================
      # ENVIRONMENT VARIABLES
      # ============================================================================
      export PICO_SDK_PATH="$HOME/dev/pico-sdk"
      export COMPOSE_BAKE=true
      export VISUAL="code --wait"
      export EDITOR="code --wait"
      export LDFLAGS="-L/opt/homebrew/opt/postgresql@17/lib"
      export CPPFLAGS="-I/opt/homebrew/opt/postgresql@17/include"
      export ENABLE_BACKGROUND_TASKS=1

      # Fix GPG issues with Homebrew install
      export GPG_TTY=$(tty)

      # Claude Code GitHub token (for MCP server)
      if [[ -f "$HOME/.config/claude/github-token" ]]; then
        export GITHUB_PERSONAL_ACCESS_TOKEN=$(cat "$HOME/.config/claude/github-token")
      fi

      # ============================================================================
      # SHELL INTEGRATIONS
      # ============================================================================
      # Note: zoxide, fzf, atuin are initialized by home-manager programs.*

      # Mise activation
      eval "$(mise activate zsh)"
    '';
  };

  # Common CLI tools
  home.packages = with pkgs; [
    # Custom scripts
    tangled-setup
    strings-cli

    # File management
    tree
    fd
    ripgrep
    bat
    eza
    unzip

    # System monitoring
    htop
    btop

    # Networking
    curl
    wget
    httpie

    # JSON/YAML
    jq
    yq

    # Misc
    fzf
    tmux
    watch
    gum # Required for tangled-setup script

    # Encryption
    age # Modern encryption tool

    # Dev tools
    mise # Version manager (formerly rtx)
    flyctl # Fly.io CLI
    bun # JavaScript runtime
    nodePackages.pnpm # Package manager
    zmx-binary # Session persistence for terminal processes

    # Deployment
    inputs.deploy-rs.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  # Fuzzy finder integration
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    colors = {
      bg = lib.mkForce "";
    };
  };

  # Better cat
  programs.bat = {
    enable = true;
    config = {
      theme = "TwoDark";
    };
  };

  # Zoxide (better cd)
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  # Atuin (shell history) with self-hosted sync server
  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    flags = [
      "--disable-up-arrow"
    ];
    settings = {
      auto_sync = true;
      sync_frequency = "5m";
      sync_address = "https://atuin.hogwarts.dev";
      key_path = "~/.local/share/atuin/key";
      search_mode = "fuzzy";
      update_check = false;
      style = "auto";
      inline_height = 30;
    };
  };

}
