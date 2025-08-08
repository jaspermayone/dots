{ config, pkgs, ... }:

{
  # Common packages for all machines
  home.packages = with pkgs; [
    git
    curl
    wget
    htop
  ];

  # Let Home Manager install and manage itself
  programs.home-manager.enable = true;
}