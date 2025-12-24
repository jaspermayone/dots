# Shell configuration
{ config, lib, pkgs, hostname, ... }:

let
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

      # Project shortcuts
      dns = "z dev/dns && source .env && source .venv/bin/activate";

      # Zsh config
      zshedit = "code ~/.zshrc";
      zshreload = "source ~/.zshrc";

      # GPG key sync
      keysync = "gpg --keyserver pgp.mit.edu --send-keys 00E643C21FAC965FFB28D3B714D0D45A1DADAAFA && gpg --keyserver keyserver.ubuntu.com --send-keys 00E643C21FAC965FFB28D3B714D0D45A1DADAAFA && gpg --keyserver keys.openpgp.org --send-keys 00E643C21FAC965FFB28D3B714D0D45A1DADAAFA && gpg --export me@jaspermayone.com | curl -T - https://keys.openpgp.org";
      gpgend = "gpg --keyserver hkps://keys.openpgp.org --send-keys 14D0D45A1DADAAFA";

      path="echo -e \${PATH//:/\\n}";

      # Vim
      vi = "vim";

      afk="/System/Library/CoreServices/Menu\ Extras/User.menu/Contents/Resources/CGSession -suspend";
      reload="exec \${SHELL} -l";
    };

    initContent = ''
      # ============================================================================
      # POWERLEVEL10K INSTANT PROMPT
      # ============================================================================
      if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
        source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
      fi

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
      # ZINIT THEME
      # ============================================================================
      zinit ice depth"1"; zinit light romkatv/powerlevel10k

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

      # ============================================================================
      # ENVIRONMENT VARIABLES
      # ============================================================================
      export COMPOSE_BAKE=true
      export VISUAL="code --wait"
      export EDITOR="code --wait"
      export LDFLAGS="-L/opt/homebrew/opt/postgresql@17/lib"
      export CPPFLAGS="-I/opt/homebrew/opt/postgresql@17/include"
      export ENABLE_BACKGROUND_TASKS=1

      # Fix GPG issues with Homebrew install
      export GPG_TTY=$(tty)

      # ============================================================================
      # SHELL INTEGRATIONS
      # ============================================================================
      # Note: zoxide, fzf, atuin are initialized by home-manager programs.*

      # Mise activation
      eval "$(mise activate zsh)"

      # ============================================================================
      # POWERLEVEL10K CONFIGURATION
      # ============================================================================
      [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
    '';
  };

  # Common CLI tools
  home.packages = with pkgs; [
    # Custom scripts
    tangled-setup

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
    gum         # Required for tangled-setup script

    # Dev tools
    mise          # Version manager (formerly rtx)
    flyctl        # Fly.io CLI
    bun           # JavaScript runtime
    nodePackages.pnpm  # Package manager
    zmx-binary    # Session persistence for terminal processes
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

  # Atuin (shell history) with sync
  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      auto_sync = true;
      sync_frequency = "5m";
      sync_address = "https://api.atuin.sh";
      search_mode = "fuzzy";
      update_check = false;
      style = "auto";
    };
  };

}
