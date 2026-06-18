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
  # Package is patched to bake in the nix ruby path so `try init`'s generated
  # shell function doesn't pick up mise's ruby via /usr/bin/env.
  # Remove once https://github.com/tobi/try/pull/116 is merged and flake updated.
  programs.try =
    let
      ruby = pkgs.ruby_3_3;
      system = pkgs.stdenv.hostPlatform.system;
      patchedTry = (inputs.try.packages.${system}.default).overrideAttrs (_: {
        installPhase = ''
          mkdir -p $out/bin
          cp try.rb $out/bin/try
          cp -r lib $out/bin/
          chmod +x $out/bin/try

          substituteInPlace $out/bin/try \
            --replace "/usr/bin/env ruby '" "${ruby}/bin/ruby '"

          wrapProgram $out/bin/try \
            --prefix PATH : ${ruby}/bin \
            --set GEM_HOME "${ruby}/lib/ruby/gems/3.3.0" \
            --set GEM_PATH "${ruby}/lib/ruby/gems/3.3.0"
        '';
      });
    in
    {
      enable = lib.elem hostname [ "remus" "dippet" "horace" ];
      path = "~/dev/tries";
      package = patchedTry;
    };

  # Ghostty terminal (installed as app bundle on macOS, skip nixpkgs package)
  programs.ghostty = {
    enable = true;
    package = null;
    # systemd socket activation requires a package; disable on packageless installs
    systemd.enable = false;
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
    // {
      # Ghostty config (keybindings, settings)
      # Hyper key = caps lock = ctrl+alt+super+shift
      ".config/ghostty/config".text = ''
        # Split panes (hyper+wasd)
        keybind = ctrl+alt+super+shift+w=new_split:up
        keybind = ctrl+alt+super+shift+s=new_split:down
        keybind = ctrl+alt+super+shift+a=new_split:left
        keybind = ctrl+alt+super+shift+d=new_split:right

        # Navigate splits (hyper+arrow)
        keybind = ctrl+alt+super+shift+up=goto_split:top
        keybind = ctrl+alt+super+shift+down=goto_split:bottom
        keybind = ctrl+alt+super+shift+left=goto_split:left
        keybind = ctrl+alt+super+shift+right=goto_split:right
      '';
    }
    // lib.optionalAttrs (!isDarwin) {
      # Discord settings (skip update nag on NixOS)
      ".config/discord/settings.json".text = builtins.toJSON { SKIP_HOST_UPDATE = true; };
    };

  home.packages = with pkgs; [
    eza
    fizzy-cli
    _1password-cli
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
        extraOptions.SetEnv = "TERM=xterm-256color";
        identityAgent = "\"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock\"";
      };

      # Alastor (tunnel server, named after Mad-Eye Moody)
      alastor = {
        hostname = "tun.hogwarts.channel";
        user = "jsp";
        zmx = true; # auto-attach zmx session
        extraOptions.SetEnv = "TERM=xterm-256color";
      };

      # Dippet (Mac Mini server)
      dippet = {
        hostname = "10.11.0.36";
        user = "jsp";
        extraOptions.SetEnv = "TERM=xterm-256color";
      };

      # Horace (named after Horace Slughorn)
      horace = {
        hostname = "horace";
        user = "jsp";
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
        identityAgent = "\"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock\"";
        extraOptions = {
          PubkeyAcceptedAlgorithms = "+ssh-ed25519";
          HostkeyAlgorithms = "+ssh-ed25519";
        };
      };
    };
  };
}
