# Home Manager configuration
# Shared between NixOS and Darwin
{
  config,
  pkgs,
  lib,
  hostname,
  isDarwin,
  inputs,
  ...
}:

{
  imports = [
    ../profiles/bore.nix
    ../modules/shell.nix
    ../modules/ssh.nix
    ../modules/git.nix
    ../modules/configs.nix
    ../modules/claude-code.nix
    inputs.try.homeModules.default
  ];

  home.stateVersion = "24.05";

  # Let Home Manager manage itself
  programs.home-manager.enable = true;

  home.username = "jsp";
  home.homeDirectory = lib.mkForce (if isDarwin then "/Users/jsp" else "/home/jsp");

  # Environment variables
  home.sessionVariables = {
    EDITOR = "vim";
    VISUAL = "vim";
    PAGER = "less";
    CLAUDE_CODE_DISABLE_TERMINAL_TITLE = "1";
  };

  # Vim configuration
  programs.vim = {
    enable = true;
    defaultEditor = true;
    settings = {
      number = true;
      relativenumber = true;
      tabstop = 2;
      shiftwidth = 2;
      expandtab = true;
    };
    extraConfig = ''
      set nocompatible
      syntax on
      set encoding=utf-8
      set autoindent
      set smartindent
      set hlsearch
      set incsearch
      set ignorecase
      set smartcase
      set backspace=indent,eol,start

      " Strip trailing whitespace on save
      autocmd BufWritePre * :%s/\s\+$//e
    '';
  };

  # Direnv for per-project environments
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };

  # Try - ephemeral workspace manager (local dev machines only)
  programs.try = {
    enable = lib.elem hostname [ "remus" "dippet" "horace" ];
    path = "~/dev/tries";
  };

  # Alacritty terminal
  programs.alacritty = {
    enable = true;
    settings = {
      window = {
        dimensions = {
          columns = 132;
          lines = 32;
        };
        padding = {
          x = 8;
          y = 8;
        };
        decorations = if isDarwin then "Buttonless" else "Full";
        opacity = 1.0;
        blur = true;
      };

      font = {
        normal = {
          family = "JetBrainsMono Nerd Font";
          style = "Regular";
        };
        bold = {
          family = "JetBrainsMono Nerd Font";
          style = "Bold";
        };
        italic = {
          family = "JetBrainsMono Nerd Font";
          style = "Italic";
        };
        size = 14.0;
      };

      colors = {
        primary = {
          background = "#292B33";
          foreground = "#FFFFFF";
        };
        normal = {
          black = "#1D1F28";
          red = "#F67E7D";
          green = "#00BD9C";
          yellow = "#E5C76B";
          blue = "#6BB8FF";
          magenta = "#DA70D6";
          cyan = "#79DCDA";
          white = "#FFFFFF";
        };
        bright = {
          black = "#535353";
          red = "#FF9391";
          green = "#98C379";
          yellow = "#F9E46B";
          blue = "#91DDFF";
          magenta = "#DA9EF4";
          cyan = "#A3F7F0";
          white = "#FEFFFF";
        };
      };

      cursor = {
        style = {
          shape = "Block";
          blinking = "On";
        };
        blink_interval = 500;
      };

      selection.save_to_clipboard = true;

      terminal.shell = {
        program = "zsh";
        args = [ "-l" ];
      };
    };
  };

  # RC files from ../rc/ directory (each file is linked as-is to ~/)
  home.file =
    builtins.listToAttrs (
      map (name: {
        name = name;
        value = {
          source = ../rc/${name};
        };
      }) (builtins.attrNames (builtins.readDir ../rc))
    )
    // lib.optionalAttrs (!isDarwin) {
      # Discord settings (skip update nag on NixOS)
      ".config/discord/settings.json".text = builtins.toJSON { SKIP_HOST_UPDATE = true; };
    };

  home.packages = with pkgs; [
    eza
  ] ++ lib.optionals stdenv.isDarwin [ pkgs.qmd ];

  # Git configuration
  jsp.git.enable = true;

  # Claude Code configuration with guardrails
  jsp.claude-code = {
    enable = true;
    guardrails = {
      enable = true;
      verbose = false; # Set to true for debugging
    };
  };

  # SSH configuration
  jsp.ssh = {
    enable = true;
    zmx.enable = true;

    hosts = {
      # Default settings for all hosts
      "*" = {
        addKeysToAgent = "yes";
      };

      # Alastor (tunnel server, named after Mad-Eye Moody)
      alastor = {
        hostname = "tun.hogwarts.channel";
        user = "jsp";
        identityFile = "~/.ssh/id_ed25519";
        zmx = true; # auto-attach zmx session
      };

      # Horace (named after Horace Slughorn)
      horace = {
        hostname = "horace";
        user = "jsp";
        identityFile = "~/.ssh/id_ed25519";
        zmx = true;
      };

      # Proxmox and VMs
      pve = {
        hostname = "10.100.0.222";
        user = "root";
        zmx = true;
      };

      proxy = {
        hostname = "10.100.0.229";
        user = "jasper";
        zmx = true;
      };

      # GitHub
      "github.com" = {
        hostname = "github.com";
        user = "git";
        identityFile = "~/.ssh/id_ed25519";
        identitiesOnly = true;
        extraOptions = {
          PubkeyAcceptedAlgorithms = "+ssh-ed25519";
          HostkeyAlgorithms = "+ssh-ed25519";
        };
      };
    };
  };
}
