{ config, pkgs, ... }:

{
  # Basic system packages that every machine should have
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    tree
    htop
  ];

  # Auto upgrade nix package and the daemon service
  services.nix-daemon.enable = true;

  # Necessary for using flakes on this system
  nix.settings.experimental-features = "nix-command flakes";

  # Create /etc/zshrc that loads the nix-darwin environment
  programs.zsh.enable = true;

  # Used for backwards compatibility
  system.stateVersion = 4;

  # System preferences that should be consistent across machines
  system.defaults = {
    dock = {
      autohide = true;
      show-recents = false;
      tilesize = 48;
    };

    finder = {
      AppleShowAllExtensions = true;
      ShowPathbar = true;
      ShowStatusBar = true;
    };
  };
}