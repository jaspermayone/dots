{ config, pkgs, ... }:

{
  # Common packages for all machines
  home.packages = with pkgs; [
    git
    curl
    wget
    htop
  ];

  # Home Manager user settings
  home.username = "jsp";
  home.homeDirectory = "/Users/jsp";
  home.stateVersion = "23.11";

  # XDG directories
  xdg = {
    enable = true;
    configHome = "/Users/jsp/.config";
    dataHome = "/Users/jsp/.local/share";
    cacheHome = "/Users/jsp/.cache";
  };

  # Let Home Manager install and manage itself
  programs.home-manager.enable = true;
}