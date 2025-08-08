{ config, pkgs, ... }:

{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    # History configuration
    history = {
      size = 999999999999;
      save = 999999999999;  # Save history indefinitely
      path = "${config.xdg.dataHome}/zsh/history";
      ignoreDups = true;
      ignoreSpace = true;
      expireDuplicatesFirst = true;
      share = true;
    };

    # Environment variables
    sessionVariables = {
      EDITOR = "nano";
      BROWSER = "open";
      PAGER = "less";
      LESS = "-R";
    };

    # Shell aliases
    shellAliases = {
      # Navigation
      ".." = "cd ..";
      "..." = "cd ../..";
      "...." = "cd ../../..";
      "....." = "cd ../../../..";

      # List files
      ls = "eza --color=auto --group-directories-first";
      ll = "eza -alF --color=auto --group-directories-first";
      la = "eza -A --color=auto --group-directories-first";
      l = "eza -CF --color=auto --group-directories-first";
      lt = "eza --tree --color=auto";

      # File operations
      cp = "cp -iv";
      mv = "mv -iv";
      rm = "rm -iv";
      mkdir = "mkdir -pv";

      # Utilities
      grep = "grep --color=auto";
      cat = "bat";
      top = "htop";
      du = "du -h";
      df = "df -h";
      free = "free -h";

      # Network
      ping = "ping -c 5";
      wget = "wget -c";

      # System
      reload = "exec zsh";
      path = "echo $PATH | tr ':' '\n'";

      # Nix/Darwin
      rebuild = "darwin-rebuild switch --flake /Users/jsp/dots";
      nr = "sudo nixos-rebuild switch";
      nix-search = "nix search nixpkgs";
      nix-shell = "nix-shell --command zsh";
    };

  };

  # Related packages
  home.packages = with pkgs; [
    eza        # Better ls
    bat        # Better cat
    htop       # Better top
    fzf        # Fuzzy finder
    ripgrep    # Better grep
    fd         # Better find
    tree       # Directory tree viewer
    tldr       # Simplified man pages
    zoxide     # Better cd
  ];

  # Configure zoxide (better cd with frecency)
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  # Configure fzf
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultCommand = "fd --type f --hidden --follow --exclude .git";
    defaultOptions = [
      "--height 40%"
      "--border"
      "--reverse"
      "--preview 'bat --style=numbers --color=always --line-range :500 {}'"
    ];
  };
}