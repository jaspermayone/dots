# Home Manager configuration
# Shared between NixOS and Darwin
{ config, pkgs, lib, hostname, isDarwin, ... }:

{
  imports = [
    ../profiles/bore.nix
    ../modules/shell.nix
    ../modules/ssh.nix
    ../modules/git.nix
    ../modules/configs.nix
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

  # RC files from ../rc/ directory (each file is linked as-is to ~/)
  home.file = builtins.listToAttrs (
    map (name: {
      name = name;
      value = { source = ../rc/${name}; };
    }) (builtins.attrNames (builtins.readDir ../rc))
  );

  home.packages = with pkgs; [
    eza
  ];

  # Git configuration
  jsp.git.enable = true;

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
        zmx = true;  # auto-attach zmx session
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
