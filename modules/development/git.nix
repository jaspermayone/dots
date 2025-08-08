{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;
    userName = "Jasper Mayone";
    userEmail = "me@jaspermayone.com";

    extraConfig = {
      init = {
        defaultBranch = "main";
      };

      pull = {
        rebase = false;
      };

      push = {
        default = "simple";
        autoSetupRemote = true;
      };

      core = {
        editor = "nano";
        autocrlf = "input";
      };

      merge = {
        conflictstyle = "diff3";
      };

      diff = {
        colorMoved = "default";
      };

      branch = {
        sort = "-committerdate";
      };

      # Better output formatting
      log = {
        date = "relative";
      };

      # Reuse recorded resolution of conflicted merges
      rerere = {
        enabled = true;
      };

      # URL shortcuts for common Git hosts
      url = {
        "git@github.com:" = {
          insteadOf = "https://github.com/";
        };
      };
    };

    # Git aliases
    aliases = {
      # Status and info
      st = "status";
      s = "status --short";

      # Logging
      l = "log --oneline";
      ll = "log --oneline --graph --decorate --all";
      lg = "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";

      # Branching
      co = "checkout";
      cob = "checkout -b";
      br = "branch";
      bra = "branch -a";

      # Committing
      c = "commit";
      cm = "commit -m";
      ca = "commit -a";
      cam = "commit -a -m";

      # Staging
      a = "add";
      aa = "add .";

      # Diffing
      d = "diff";
      dc = "diff --cached";

      # Pushing/pulling
      p = "push";
      pf = "push --force-with-lease";
      pl = "pull";

      # Rebasing
      rb = "rebase";
      rbi = "rebase -i";

      # Stashing
      stash-all = "stash save --include-untracked";

      # Undoing
      uncommit = "reset --soft HEAD~1";
      unstage = "reset HEAD --";

      # Show what's in the stash
      stash-show = "stash show -p";
    };

    ignores = [
      ".env"
      "*.log"
      "*.sqlite"
      "*.sql"
      ".DS_Store"
      # vim
      "*.swp"
    ];

    # Delta for better diff output (optional but nice)
    delta = {
      enable = true;
      options = {
        navigate = true;
        light = false;
        side-by-side = true;
        line-numbers = true;
      };
    };
  };

  home.packages = with pkgs; [
    delta.      # Include delta package for better diffs
    git-absorb  # Automatically fixup commits
    gh          # GitHub CLI
  ];

  # Git-related shell aliases
  programs.zsh.shellAliases = {
    s = "git status";
  };
}